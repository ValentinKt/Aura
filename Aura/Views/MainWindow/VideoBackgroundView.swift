import AVFoundation
import SwiftUI

struct VideoBackgroundView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let view = VideoLoopView(frame: .zero)
        view.play(url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let loopView = nsView as? VideoLoopView {
            loopView.play(url: url)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        if let loopView = nsView as? VideoLoopView {
            loopView.teardown()
        }
    }
}

private class VideoLoopView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var imageLayer: CALayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var memoryAssetLoader: MemoryAssetLoader?
    private var currentURL: URL?
    private var isSecurityScoped: Bool = false
    private var windowObservation: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        windowObservation?.invalidate()
        windowObservation = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        if let window = self.window {
            windowObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] window, _ in
                self?.updatePlaybackState()
            }
            NotificationCenter.default.addObserver(self, selector: #selector(windowOcclusionDidChange), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        } else {
            updatePlaybackState()
        }
    }

    @objc private func windowOcclusionDidChange() {
        updatePlaybackState()
    }

    private func updatePlaybackState() {
        guard let window = self.window else {
            player?.pause()
            playerLayer?.isHidden = true
            return
        }
        let isOccluded = !window.occlusionState.contains(.visible)
        if window.isVisible && !isOccluded {
            playerLayer?.isHidden = false
            player?.play()
        } else {
            player?.pause()
            playerLayer?.isHidden = true
        }
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func play(url: URL) {
        // Avoid restarting if the same URL is already playing
        if currentURL == url {
            if player != nil || imageLayer != nil {
                return
            }
        }

        // --- STEP 1: SHUTDOWN OLD PIPELINE ---
        teardown()

        print("🟢 [VideoBackgroundView] Loading: \(url.lastPathComponent)")

        currentURL = url
        isSecurityScoped = url.startAccessingSecurityScopedResource()

        // Ensure file exists and is reachable
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("🟥 [VideoBackgroundView] File not found at path: \(url.path)")
            return
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic"].contains(ext) {
            // --- IMAGE FALLBACK ---
            guard let image = NSImage(contentsOf: url) else {
                print("🟥 [VideoBackgroundView] Failed to load image at: \(url.path)")
                return
            }

            let layer = CALayer()
            layer.contents = image
            layer.contentsGravity = .resizeAspectFill
            layer.frame = self.bounds
            self.layer?.addSublayer(layer)
            self.imageLayer = layer
            return
        }

        // --- STEP 2: CONFIGURE ASSET (VIDEO) ---
        // SSD Hygiene: memory-backed buffer for small loopable assets
        var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
        urlComponents?.scheme = "memory"
        
        let asset: AVURLAsset
        if let memoryURL = urlComponents?.url,
           let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size < 50_000_000,
           let loader = MemoryAssetLoader(url: url) {
            
            self.memoryAssetLoader = loader
            asset = AVURLAsset(url: memoryURL)
            asset.resourceLoader.setDelegate(loader, queue: .global(qos: .userInitiated))
        } else {
            self.memoryAssetLoader = nil
            asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        }

        let item = AVPlayerItem(asset: asset)

        // Visual Throttling: Cap video at 30 FPS to save massive GPU energy
        Task {
            _ = try? await asset.load(.tracks)
            if let composition = try? AVMutableVideoComposition(propertiesOf: asset) {
                composition.frameDuration = CMTime(value: 1, timescale: 30)
                item.videoComposition = composition
            }
        }

        // Dynamic Scaling: Set preferred maximum resolution to display's native resolution
        if let screen = self.window?.screen ?? NSScreen.main {
            let scale = screen.backingScaleFactor
            item.preferredMaximumResolution = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
        } else {
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        }
        item.preferredPeakBitRate = 5_000_000
        item.preferredForwardBufferDuration = 2.0

        // Fix for HALC / SoundEngine overload: Disable audio processing
        item.audioTimePitchAlgorithm = .varispeed
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false

        // --- STEP 3: INITIALIZE PLAYER ---
        let newPlayer = AVQueuePlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.allowsExternalPlayback = false
        newPlayer.isMuted = true // Critical: Prevents FigAirPlay_Route errors
        newPlayer.volume = 0

        self.player = newPlayer

        // --- STEP 4: SETUP LOOPER ---
        self.looper = AVPlayerLooper(player: newPlayer, templateItem: item)

        // --- STEP 5: VISUALS ---
        let newLayer = AVPlayerLayer(player: newPlayer)
        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = self.bounds
        self.layer?.addSublayer(newLayer)
        self.playerLayer = newLayer

        if self.window?.isVisible == true {
            newPlayer.play()
        }
    }

    func teardown() {
        // Stop playback
        player?.pause()

        // Break the loop and clear the queue
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()

        // CRITICAL: This line tells the macOS Hardware Decoder (VMC)
        // to immediately release the file handle and GPU buffers.
        player?.replaceCurrentItem(with: nil)

        // Remove the old visual layer so it doesn't draw "nothing"
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        imageLayer?.removeFromSuperlayer()
        imageLayer = nil

        player = nil

        if let url = currentURL, isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
            currentURL = nil
            isSecurityScoped = false
        }
    }

    deinit {
        teardown()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        imageLayer?.frame = bounds
    }
}
