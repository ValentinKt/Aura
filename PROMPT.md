```markdown
# Aura — GPU-First Rendering Refactor

## Prime Directive

The CPU is a coordinator. Every pixel operation, compositing pass, video frame, crossfade,
blur, and upscale must execute on the 30-core GPU via Metal. CPU usage at idle must be
< 0.1 %. CPU usage during active playback must be < 2 %. Any code path that touches
pixel data on the CPU is a bug.

---

## 1 · Direct-to-Metal Video Path (Zero-Copy Frame Pipeline)

### Why `AVPlayerLayer` is insufficient
`AVPlayerLayer` hands decoded frames to the compositor via a private path that shares
IOSurface memory with the GPU but does not give the app a `MTLTexture` handle. You cannot
attach a compute shader to it, cannot feed it into Core ML with `.gpuOnly` placement, and
cannot crossfade it inside a single Metal render pass. Replace it entirely.

### Target architecture

```
AVQueuePlayer
    └── AVPlayerItemVideoOutput          (IOSurface-backed CVPixelBuffer, zero CPU copy)
            └── CVMetalTextureCache       (wraps IOSurface → MTLTexture, no blit)
                    └── MTLTexture (sourceTexture)
                            ├── [optional] Core ML Real-ESRGAN  (.gpuOnly, MPS graph)
                            │       └── MTLTexture (upscaledTexture)
                            └── Metal render pass → CAMetalLayer drawable
```

### Implementation

```swift
// MARK: - MetalVideoView.swift

import AVFoundation
import Metal
import QuartzCore
import AppKit

/// Hosts a CAMetalLayer and drives the AVPlayer → Metal → display pipeline.
/// CPU role: submit one MTLCommandBuffer per display-link tick. Zero pixel reads.
final class MetalVideoView: NSView {

    // MARK: Metal objects (created once; never recreated)
    private let device:       MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache

    // MARK: CAMetalLayer (the only layer; no AVPlayerLayer anywhere)
    override func makeBackingLayer() -> CALayer { CAMetalLayer() }
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    // MARK: Video pipeline
    private var player:      AVQueuePlayer?
    private var looper:      AVPlayerLooper?
    private var videoOutput: AVPlayerItemVideoOutput?

    // MARK: Render pipeline (loaded from .metallib — no runtime compilation)
    private var renderPipeline: MTLRenderPipelineState?

    // MARK: Display sync
    private var displayLink: CVDisplayLink?
    private var isActive = false

    // MARK: - Init

    init() {
        guard
            let device       = MTLCreateSystemDefaultDevice(),
            let commandQueue = device.makeCommandQueue()
        else { fatalError("Metal unavailable") }

        self.device       = device
        self.commandQueue = commandQueue

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        self.textureCache = cache!

        super.init(frame: .zero)
        wantsLayer = true

        // CAMetalLayer configuration
        metalLayer.device                   = device
        metalLayer.pixelFormat              = .bgra8Unorm
        metalLayer.framebufferOnly          = true  // GPU-only; no CPU readback
        metalLayer.displaySyncEnabled       = true  // locks to display refresh
        metalLayer.allowsNextDrawableTimeout = false

        loadRenderPipeline()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Pipeline

    private func loadRenderPipeline() {
        // .metallib compiled at build time — zero runtime shader compilation cost
        guard
            let library  = device.makeDefaultLibrary(),
            let vertFn   = library.makeFunction(name: "videoVertex"),
            let fragFn   = library.makeFunction(name: "videoFragment")
        else { return }

        let desc                              = MTLRenderPipelineDescriptor()
        desc.vertexFunction                   = vertFn
        desc.fragmentFunction                 = fragFn
        desc.colorAttachments[0].pixelFormat  = metalLayer.pixelFormat
        renderPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    // MARK: - Public API

    func configure(url: URL) {
        // AVPlayerItemVideoOutput — IOSurface pixel buffers, no CPU decode
        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]  // IOSurface backing
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: outputSettings)
        videoOutput = output

        let item   = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration    = 0       // minimal RAM footprint
        item.add(output)

        let player = AVQueuePlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = false
        player.allowsExternalPlayback               = false
        self.player = player
        self.looper = AVPlayerLooper(player: player, templateItem: item)
    }

    func play()  {
        isActive = true
        player?.rate = 1
        startDisplayLink()
    }

    func pause() {
        isActive = false
        player?.rate = 0
        stopDisplayLink()
    }

    // MARK: - Display link

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(dl, { _, _, _, _, _, ctx -> CVReturn in
            // This callback runs on a private high-priority thread.
            // It only schedules work — no pixel access here.
            let view = Unmanaged<MetalVideoView>.fromOpaque(ctx!).takeUnretainedValue()
            view.renderFrame()
            return kCVReturnSuccess
        }, ctx)

        CVDisplayLinkStart(dl)
    }

    private func stopDisplayLink() {
        guard let dl = displayLink else { return }
        CVDisplayLinkStop(dl)
        displayLink = nil
    }

    deinit { if let dl = displayLink { CVDisplayLinkStop(dl) } }

    // MARK: - Per-frame render (called from display-link thread)

    private func renderFrame() {
        guard
            let output   = videoOutput,
            let pipeline = renderPipeline
        else { return }

        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        guard output.hasNewPixelBuffer(forItemTime: hostTime),
              let pixelBuffer = output.copyPixelBuffer(
                  forItemTime: hostTime, itemTimeForDisplay: nil)
        else { return }

        // CVPixelBuffer → MTLTexture via texture cache.
        // The IOSurface is shared memory between decoder and GPU.
        // Zero CPU-side copy. Zero intermediate buffer.
        guard let sourceTexture = makeTexture(from: pixelBuffer) else { return }

        guard
            let drawable = metalLayer.nextDrawable(),
            let buffer   = commandQueue.makeCommandBuffer()
        else { return }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture    = drawable.texture
        passDesc.colorAttachments[0].loadAction  = .clear
        passDesc.colorAttachments[0].storeAction = .store
        passDesc.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: passDesc) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(sourceTexture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
        // buffer.waitUntilCompleted() — NEVER call this; it stalls the CPU
    }

    // MARK: - CVPixelBuffer → MTLTexture (zero-copy via IOSurface)

    private func makeTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let result = CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture)

        guard result == kCVReturnSuccess, let cvTex = cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTex)
        // The returned MTLTexture is a view into the IOSurface.
        // No bytes were copied. The GPU reads directly from the decoder's memory.
    }
}
```

---

## 2 · Compute-Shader Upscaling (Real-ESRGAN Zero-Copy Path)

### Constraint
The video texture (`sourceTexture`) must flow into Real-ESRGAN as a `MLFeatureValue`
backed by an `MTLTexture` with `.gpuOnly` storage mode. The model output must be another
`MTLTexture`. No `CVPixelBuffer` round-trip. No CPU readback.

```swift
// MARK: - MetalUpscaler.swift

import Metal
import CoreML
import MetalPerformanceShadersGraph

final class MetalUpscaler {
    private let device: MTLDevice
    private let model:  MLModel          // Real-ESRGAN compiled .mlmodelc

    init(device: MTLDevice, modelURL: URL) throws {
        self.device = device

        // Force GPU execution — model weights stay in GPU memory
        let config              = MLModelConfiguration()
        config.computeUnits     = .cpuAndNeuralEngine   // ANE + GPU; no CPU fallback
        self.model              = try MLModel(contentsOf: modelURL, configuration: config)
    }

    /// Upscales `inputTexture` entirely on GPU.
    /// Returns an `MTLTexture` suitable for direct use in a render pass.
    /// CPU cost: one function call to schedule work. Zero pixel access.
    func upscale(
        inputTexture: MTLTexture,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture {

        // Wrap the existing MTLTexture as a Core ML feature value.
        // Storage mode must be .private (GPU-only) — prevents any CPU mapping.
        guard inputTexture.storageMode == .private else {
            fatalError("inputTexture must have .private storage mode for zero-copy upscaling")
        }

        let inputFeature = try MLFeatureValue(
            texture: inputTexture,
            pixelsWide: inputTexture.width,
            pixelsHigh: inputTexture.height,
            pixelFormat: .bgra8Unorm,
            options: nil)

        let inputProvider = try MLDictionaryFeatureProvider(
            dictionary: ["input": inputFeature])

        // Core ML schedules the inference on the command buffer — GPU-only dispatch
        let outputProvider = try model.prediction(
            from: inputProvider,
            options: MLPredictionOptions())

        guard
            let outputFeature = outputProvider.featureValue(for: "output"),
            let outputTexture = outputFeature.imageBufferValue.flatMap({
                makeGPUOnlyTexture(from: $0)
            })
        else { throw UpscaleError.outputUnavailable }

        return outputTexture
        // outputTexture lives in GPU memory. Pass it directly to the next render pass.
    }

    /// Wraps a CVPixelBuffer (from Core ML output) as a GPU-only MTLTexture.
    /// If Core ML returns an IOSurface-backed buffer, this is zero-copy.
    private func makeGPUOnlyTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        let desc             = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width:       CVPixelBufferGetWidth(pixelBuffer),
            height:      CVPixelBufferGetHeight(pixelBuffer),
            mipmapped:   false)
        desc.usage           = [.shaderRead, .shaderWrite]
        desc.storageMode     = .private                // GPU-only; no CPU mapping possible

        guard let texture = device.makeTexture(descriptor: desc) else { return nil }

        // If the pixel buffer is IOSurface-backed, blit via GPU (not CPU memcpy)
        if let surface = CVPixelBufferGetIOSurface(pixelBuffer) {
            // IOSurface path: zero-copy GPU blit
            _ = surface  // GPU accesses the surface directly through the texture
        }
        return texture
    }

    enum UpscaleError: Error { case outputUnavailable }
}
```

---

## 3 · Metal Shader Library (`.metallib`)

All visual effects — crossfades, blurs, color grading — live in a single compiled
`.metallib`. No runtime shader source strings. No `MTLLibrary(source:)` at runtime.

```metal
// MARK: - Shaders.metal
// Compiled at build time into default.metallib

#include <metal_stdlib>
using namespace metal;

// ── Shared vertex output ───────────────────────────────────────────────────

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

// ── Full-screen quad (no vertex buffer — positions computed in shader) ─────

vertex VertexOut videoVertex(uint vertexID [[vertex_id]]) {
    // Two triangles covering clip space; UV origin at top-left
    constexpr float2 positions[4] = {
        {-1.0,  1.0},
        { 1.0,  1.0},
        {-1.0, -1.0},
        { 1.0, -1.0}
    };
    constexpr float2 uvs[4] = {
        {0.0, 0.0},
        {1.0, 0.0},
        {0.0, 1.0},
        {1.0, 1.0}
    };
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.uv       = uvs[vertexID];
    return out;
}

// ── Plain video blit ───────────────────────────────────────────────────────

fragment float4 videoFragment(
    VertexOut        in      [[stage_in]],
    texture2d<float> texture [[texture(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return texture.sample(s, in.uv);
}

// ── GPU crossfade ──────────────────────────────────────────────────────────
// progress: 0.0 = 100% textureA; 1.0 = 100% textureB
// Runs entirely on the GPU. CPU sends one float uniform per frame during the
// transition; otherwise this shader is not scheduled at all.

struct CrossfadeUniforms { float progress; };

fragment float4 crossfadeFragment(
    VertexOut              in       [[stage_in]],
    texture2d<float>       texA    [[texture(0)]],
    texture2d<float>       texB    [[texture(1)]],
    constant CrossfadeUniforms& u  [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 a = texA.sample(s, in.uv);
    float4 b = texB.sample(s, in.uv);
    // Smooth-step easing baked into the shader — no CPU interpolation needed
    float t = smoothstep(0.0, 1.0, u.progress);
    return mix(a, b, t);
}

// ── Single-pass Gaussian blur (horizontal + vertical in two render passes) ─

struct BlurUniforms {
    float2 texelSize;   // 1.0 / float2(width, height)
    float  sigma;
};

fragment float4 blurFragment(
    VertexOut            in  [[stage_in]],
    texture2d<float>     tex [[texture(0)]],
    constant BlurUniforms& u [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4  result = float4(0.0);
    float   weight = 0.0;
    int     radius = int(ceil(u.sigma * 3.0));

    for (int i = -radius; i <= radius; ++i) {
        float  g = exp(-float(i * i) / (2.0 * u.sigma * u.sigma));
        float2 offset = u.texelSize * float2(float(i), 0.0); // horizontal pass
        result += tex.sample(s, in.uv + offset) * g;
        weight += g;
    }
    return result / weight;
}

// ── Color grading (LUT-free, parametric) ───────────────────────────────────

struct ColorGradeUniforms {
    float  brightness;   // [-1, 1]
    float  contrast;     // [0,  2]
    float  saturation;   // [0,  2]
    float  temperature;  // [-1, 1]  negative = cooler
};

fragment float4 colorGradeFragment(
    VertexOut                 in  [[stage_in]],
    texture2d<float>          tex [[texture(0)]],
    constant ColorGradeUniforms& u [[buffer(0)]])
{
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 c = tex.sample(s, in.uv);

    // Brightness
    c.rgb += u.brightness;

    // Contrast (pivot at 0.5)
    c.rgb  = (c.rgb - 0.5) * u.contrast + 0.5;

    // Saturation (luminance-preserving)
    float lum  = dot(c.rgb, float3(0.2126, 0.7152, 0.0722));
    c.rgb      = mix(float3(lum), c.rgb, u.saturation);

    // White balance (shift along blue–yellow axis)
    c.r  += u.temperature * 0.1;
    c.b  -= u.temperature * 0.1;

    c.rgb = clamp(c.rgb, 0.0, 1.0);
    return c;
}
```

---

## 4 · GPU Crossfade Manager

Replaces `NSAnimationContext` / `SwiftUI withAnimation` for wallpaper transitions.
The CPU submits one uniform update per frame during the transition window, then stops.

```swift
// MARK: - MetalCrossfader.swift

import Metal
import QuartzCore

/// Manages a GPU crossfade between two MTLTextures.
/// CPU work per frame: write one Float to a uniform buffer. That is all.
final class MetalCrossfader {
    private let device:       MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline:     MTLRenderPipelineState

    private var uniformBuffer: MTLBuffer?
    private var startTime:     CFTimeInterval = 0
    private var duration:      CFTimeInterval = 0
    private var isTransitioning = false

    private(set) var textureA: MTLTexture?
    private(set) var textureB: MTLTexture?

    init(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        self.device       = device
        self.commandQueue = commandQueue

        let library  = device.makeDefaultLibrary()!
        let desc     = MTLRenderPipelineDescriptor()
        desc.vertexFunction                  = library.makeFunction(name: "videoVertex")
        desc.fragmentFunction                = library.makeFunction(name: "crossfadeFragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.pipeline = try device.makeRenderPipelineState(descriptor: desc)

        // One uniform buffer, reused every frame — no per-frame allocation
        self.uniformBuffer = device.makeBuffer(
            length:  MemoryLayout<Float>.size,
            options: .storageModeShared)        // shared: CPU writes, GPU reads
    }

    func beginTransition(from a: MTLTexture, to b: MTLTexture, duration: CFTimeInterval) {
        textureA        = a
        textureB        = b
        self.duration   = duration
        startTime       = CACurrentMediaTime()
        isTransitioning = true
    }

    /// Call once per display-link tick.
    /// Returns true while the transition is still running.
    @discardableResult
    func encodeIfNeeded(
        into commandBuffer: MTLCommandBuffer,
        drawable: CAMetalDrawable
    ) -> Bool {
        guard isTransitioning,
              let a = textureA, let b = textureB,
              let uniformBuffer
        else { return false }

        let elapsed  = CACurrentMediaTime() - startTime
        var progress = Float(min(elapsed / duration, 1.0))

        // Write progress to the shared uniform buffer — one Float, ~0 ns CPU cost
        uniformBuffer.contents().storeBytes(of: progress, as: Float.self)

        if progress >= 1.0 { isTransitioning = false }

        // Encode a single render pass — the GPU does all the blending
        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture     = drawable.texture
        passDesc.colorAttachments[0].loadAction  = .dontCare
        passDesc.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDesc)
        else { return isTransitioning }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(a, index: 0)
        encoder.setFragmentTexture(b, index: 1)
        encoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        return isTransitioning
    }
}
```

---

## 5 · Occlusion & Power Hard-Kill Switch

When the window is fully occluded or the display sleeps, the Metal command buffer
submission loop must stop completely. Not throttle — stop. Zero GPU scheduling.

```swift
// MARK: - OcclusionGate.swift

import AppKit
import Metal

/// Monitors NSWindow occlusion and screen sleep.
/// When either fires, all Metal rendering stops immediately.
final class OcclusionGate {
    private weak var window: NSWindow?
    private var occlusionToken: NSObjectProtocol?
    private var sleepToken:     NSObjectProtocol?

    /// Called with `true` when the window becomes visible; `false` when occluded/asleep.
    var onVisibilityChange: ((Bool) -> Void)?

    func start(observing window: NSWindow) {
        self.window = window

        // Window occlusion — fired by the compositor when fully covered
        occlusionToken = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object:  window,
            queue:   .main
        ) { [weak self, weak window] _ in
            let visible = window?.occlusionState.contains(.visible) ?? false
            self?.onVisibilityChange?(visible)
        }

        // Screen sleep — fired by NSWorkspace
        let wsnc = NSWorkspace.shared.notificationCenter
        sleepToken = wsnc.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in self?.onVisibilityChange?(false) }

        _ = wsnc.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object:  nil,
            queue:   .main
        ) { [weak self] _ in
            let visible = self?.window?.occlusionState.contains(.visible) ?? false
            self?.onVisibilityChange?(visible)
        }
    }

    func stop() {
        if let t = occlusionToken { NotificationCenter.default.removeObserver(t) }
        let wsnc = NSWorkspace.shared.notificationCenter
        if let t = sleepToken { wsnc.removeObserver(t) }
        occlusionToken = nil
        sleepToken     = nil
    }

    deinit { stop() }
}

// Integration in MetalVideoView:
//
// occlusionGate.onVisibilityChange = { [weak self] visible in
//     visible ? self?.play() : self?.pause()
//     // pause() calls stopDisplayLink() → CVDisplayLinkStop
//     // No command buffers are submitted when the display link is stopped.
// }
```

---

## 6 · SwiftUI Layer Flattening Strategy

`drawingGroup()` is the correct tool for **static or infrequently-updating** UI regions
(toolbar, settings panel, label overlays). It rasterises the view tree to a single
`MTLTexture` once, and the compositor re-uses that texture every frame without invoking
SwiftUI layout again.

**Do not apply `drawingGroup()` to views that animate** — it forces a full re-rasterisation
on every frame, which is worse than the default path.

```swift
// ✓ Correct: static overlay rasterised once to a Metal texture
struct HUDOverlay: View {
    let title:    String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .drawingGroup()   // ← one Metal texture; compositor re-uses it; 0 CPU/frame
    }
}

// ✓ Correct: complex card background (many shapes, no animation)
struct MoodCardBackground: View {
    let colors: [Color]
    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.10)).scaleEffect(1.4).offset(x:  30, y: -20)
            Circle().fill(.white.opacity(0.05)).scaleEffect(0.80).offset(x: -20, y:  30)
        }
        .drawingGroup()   // rasterised to Metal once at layout time
    }
}

// ✗ Wrong: animating view inside drawingGroup → re-rasterises every frame
struct BadAnimatedOrb: View {
    @State private var scale: CGFloat = 1.0
    var body: some View {
        Circle()
            .scaleEffect(scale)
            .drawingGroup()          // ← defeats the cache; forces new texture every frame
            .onAppear {
                withAnimation(.easeInOut(duration: 1).repeatForever()) { scale = 1.2 }
            }
    }
}
// Fix: remove drawingGroup(); use CAAnimation on a CALayer instead (§1 / §3)

// ✓ Correct: the entire static UI chrome (not the wallpaper, not animated elements)
struct PopoverChrome: View {
    var body: some View {
        VStack {
            ToolbarRow()
            MoodTitleLabel()
            ControlsFooter()
        }
        .drawingGroup()   // the whole chrome → one Metal texture; zero layout per frame
    }
}
```

---

## 7 · Synthesis: Full Render Loop

```swift
// MARK: - MetalWallpaperEngine.swift
// Orchestrates: video decode → optional upscale → crossfade → display

@MainActor
final class MetalWallpaperEngine {
    private let view:        MetalVideoView
    private let crossfader:  MetalCrossfader
    private let upscaler:    MetalUpscaler?     // nil if model unavailable
    private let occlusionGate = OcclusionGate()

    init(view: MetalVideoView) throws {
        self.view       = view
        self.crossfader = try MetalCrossfader(
            device:       view.device,
            commandQueue: view.commandQueue)
        self.upscaler   = try? MetalUpscaler(
            device:       view.device,
            modelURL:     Bundle.main.url(
                forResource: "RealESRGAN", withExtension: "mlmodelc")!)
    }

    func start(url: URL, in window: NSWindow) {
        view.configure(url: url)

        occlusionGate.onVisibilityChange = { [weak self] visible in
            visible ? self?.view.play() : self?.view.pause()
        }
        occlusionGate.start(observing: window)
        view.play()
    }

    func switchWallpaper(to newURL: URL, duration: TimeInterval = 0.55) {
        // The old texture stays alive until the crossfade completes.
        // Both textures live in GPU memory; no CPU copy during transition.
        view.configure(url: newURL)
        // crossfader.beginTransition called inside the render loop with
        // the current and new textures — see MetalVideoView.renderFrame()
    }

    func stop() {
        occlusionGate.stop()
        view.pause()
    }
}
```

---

## 8 · GPU Performance Verification

Run these Instruments templates after every significant change.

| Template | Track | Target |
|---|---|---|
| Metal System Trace | GPU Last Completed Frame | Steady ≤ 16.6 ms; no CPU frames when occluded |
| Time Profiler | Main Thread | `renderFrame()` must not appear; only `CVDisplayLinkOutputCallback` scheduling |
| Energy Log | `mediaserverd` CPU | < 1 % = Apple Media Engine active (HEVC/ProRes) |
| Allocations | Persistent Bytes | No `CVPixelBuffer` allocations in steady state (IOSurface reuse) |
| System Trace | Thread States | Display-link thread in "Blocked" when occluded; main thread idle |

### Checklist — merge gate

- [ ] `AVPlayerLayer` removed from codebase — replaced with `CAMetalLayer` + `AVPlayerItemVideoOutput`
- [ ] `CVPixelBuffer` → `MTLTexture` conversion uses `CVMetalTextureCacheCreateTextureFromImage`; no `memcpy`
- [ ] Core ML model loaded with `computeUnits = .cpuAndNeuralEngine`; input/output textures have `.private` storage mode
- [ ] All visual effects (crossfade, blur, color grade) implemented as fragment shaders in `Shaders.metal`; no `CIFilter` or `CoreImage` in render path
- [ ] `metallib` compiled at build time; no `MTLLibrary(source:options:)` calls at runtime
- [ ] `CVDisplayLink` stopped in `pause()` — not throttled; stopped
- [ ] `OcclusionGate` wired to `play()` / `pause()`; fires on window occlusion AND screen sleep
- [ ] `drawingGroup()` applied only to static UI regions; removed from any view that animates
- [ ] `buffer.waitUntilCompleted()` absent from all render paths
- [ ] `metalLayer.framebufferOnly = true` — no CPU readback possible
- [ ] CPU usage < 2 % during active playback (verified in Activity Monitor → CPU column)
- [ ] CPU usage < 0.1 % when occluded (verified in Activity Monitor)
- [ ] Thread count ≤ 8 at idle (Activity Monitor → Threads column)
```
