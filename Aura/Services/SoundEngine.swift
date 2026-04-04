import AVFoundation
import Foundation
import Observation
import os

@MainActor
@Observable
final class SoundEngine {
    enum EngineState: String, Codable {
        case uninitialized
        case preparing
        case ready
        case playing
        case paused
        case error
    }

    enum SoundEngineError: Error {
        case engineStartFailed(String)
        case layerInitializationFailed(String)
    }

    struct LayerNode {
        let player: AVAudioPlayerNode
        let eq: AVAudioUnitEQ
    }

    private let engine = AVAudioEngine()
    private let assetManager: AssetManager
    private let loopManager: LoopManager
    private let audioMixer: AudioMixer

    // Resolved file URLs (tiny — just paths, no audio data)
    private var layerURLs: [String: URL] = [:]

    // Runtime nodes — only attached when the layer is actively playing
    private var layerNodes: [String: LayerNode] = [:]

    // Custom audio player node for external files
    private let customPlayer = AVAudioPlayerNode()
    private let customEQ = AVAudioUnitEQ(numberOfBands: 1)

    private(set) var state: EngineState = .uninitialized
    var volumes: [String: Float] = [:]
    var masterVolume: Float = 0.6 {
        didSet { updateOutputVolume() }
    }

    private var duckingMultiplier: Float = 1.0 {
        didSet { updateOutputVolume() }
    }

    private var duckingTask: Task<Void, Never>?
    private var randomizationTask: Task<Void, Never>?
    private var randomizationInterval: TimeInterval?
    private var randomizationRange: ClosedRange<Float>?
    private var memoryPressureSource: DispatchSourceMemoryPressure?

    private var isEngineRunning = false

    func updateOutputVolume() {
        engine.mainMixerNode.outputVolume = masterVolume * duckingMultiplier
    }

    // MARK: - Idle / Engine Lifecycle

    private func checkIdleState() {
        let hasActiveLayers = volumes.values.contains { $0 > 0.001 }
        let isCustomPlaying = customPlayer.isPlaying
        if !hasActiveLayers && !isCustomPlaying {
            stopEngineAndDetach()
        }
    }

    private func stopEngineAndDetach() {
        guard isEngineRunning else { return }
        Logger.sound.info("⏸️ [SoundEngine] All layers silent. Stopping engine to save CPU.")
        engine.stop()
        for node in layerNodes.values where node.player.engine != nil {
            node.player.stop()
            engine.detach(node.player)
            engine.detach(node.eq)
        }
        if customPlayer.engine != nil {
            customPlayer.stop()
            engine.detach(customPlayer)
            engine.detach(customEQ)
        }
        isEngineRunning = false
    }

    private func startEngineIfNeeded() throws {
        if !isEngineRunning {
            Logger.sound.info("▶️ [SoundEngine] Waking engine from idle.")
            try engine.start()
            isEngineRunning = true
        }
    }

    // MARK: - Node Attach / Detach

    private func ensureNodeAttachedAndPlaying(id: String, node: LayerNode) {
        guard let url = layerURLs[id] else { return }

        if node.player.engine == nil {
            engine.attach(node.player)
            engine.attach(node.eq)
            // Use a minimal format (44.1 kHz stereo) for connection; AVAudioFile streaming
            // will deliver frames in the file's native format via the render thread.
            let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)
            engine.connect(node.player, to: node.eq, format: format)
            engine.connect(node.eq, to: engine.mainMixerNode, format: format)
            // Stream the file — no PCM buffer allocated
            loopManager.startLoop(on: node.player, url: url)
        }
        if !node.player.isPlaying {
            node.player.play()
        }
    }

    private func detachNodeIfNeeded(_ node: LayerNode) {
        if node.player.engine != nil {
            node.player.stop()
            engine.detach(node.player)
        }
        if node.eq.engine != nil {
            engine.detach(node.eq)
        }
    }

    // MARK: - Init & Prepare

    init(assetManager: AssetManager, loopManager: LoopManager, audioMixer: AudioMixer) {
        self.assetManager = assetManager
        self.loopManager = loopManager
        self.audioMixer = audioMixer
        engine.mainMixerNode.outputVolume = masterVolume
        for id in SoundLayerID.allCases.map(\.rawValue) {
            volumes[id] = 0
        }
        Logger.sound.info("🟢 [SoundEngine] Initializing...")
    }

    /// Prepare resolves file URLs and creates node stubs — NO audio data loaded into RAM.
    func prepare() async throws {
        guard state == .uninitialized || state == .error else { return }
        state = .preparing
        Logger.sound.info("🟢 [SoundEngine] Resolving audio URLs (no buffers loaded)...")

        // Resolve URLs for every layer — this is just a file-exists check, ~0 ms, ~0 RAM.
        await resolveLayerURLs()

        // Create node stubs (not attached to engine yet — attached lazily on first play)
        for id in SoundLayerID.allCases.map(\.rawValue) {
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            layerNodes[id] = LayerNode(player: player, eq: eq)
        }

        engine.prepare()
        state = .ready

        // Start memory pressure monitoring
        startMemoryPressureMonitoring()

        Logger.sound.info("🟢 [SoundEngine] Engine ready (idle, 0 audio RAM used).")
    }

    private func resolveLayerURLs() async {
        for id in SoundLayerID.allCases.map(\.rawValue) {
            if let url = await assetManager.resolveAudioURL(named: id) {
                layerURLs[id] = url
            }
        }
    }

    // MARK: - Playback Control

    func stop() {
        Logger.sound.info("Stopping all audio")
        stopRandomizationSchedule()
        stopEngineAndDetach()
        state = .uninitialized
    }

    func pause() {
        guard state == .playing || state == .ready else { return }
        stopRandomizationSchedule()
        stopEngineAndDetach()
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .ready else { return }

        var hasPlayingNode = false
        if volumes.values.contains(where: { $0 > 0 }) || customPlayer.engine != nil {
            try? startEngineIfNeeded()
        }
        for (id, node) in layerNodes {
            if let vol = volumes[id], vol > 0 {
                hasPlayingNode = true
                ensureNodeAttachedAndPlaying(id: id, node: node)
            } else {
                if node.player.engine != nil {
                    node.player.pause()
                }
            }
        }
        if !customPlayer.isPlaying && customPlayer.engine != nil {
            customPlayer.play()
            hasPlayingNode = true
        }

        if hasPlayingNode {
            state = .playing
            scheduleRandomizationIfNeeded()
        } else {
            state = .playing
            checkIdleState()
        }
    }

    // MARK: - Custom Audio

    func playCustomAudio(url: URL) async throws {
        Logger.sound.info("Playing custom audio from URL: \(url.path, privacy: .public)")
        await crossfade(to: [:], duration: 1.0)
        customPlayer.stop()

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            Logger.sound.error("Failed to read audio file at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
        let format = file.processingFormat

        if customPlayer.engine == nil {
            engine.attach(customPlayer)
            engine.attach(customEQ)
        } else {
            engine.disconnectNodeOutput(customPlayer)
            engine.disconnectNodeOutput(customEQ)
        }
        engine.connect(customPlayer, to: customEQ, format: format)
        engine.connect(customEQ, to: engine.mainMixerNode, format: format)

        await customPlayer.scheduleFile(file, at: nil)
        try? startEngineIfNeeded()
        customPlayer.volume = 1.0
        customPlayer.play()
        state = .playing
    }

    // MARK: - Layer Volume

    func setLayer(_ id: String, volume: Float, pan: Float = 0, lowPassCutoff: Float = 12000) {
        guard SoundLayerID(rawValue: id) != nil else { return }
        let clampedVolume = max(0, min(1, volume))
        let previousVolume = volumes[id] ?? 0
        volumes[id] = clampedVolume
        guard let node = layerNodes[id] else { return }

        let shouldPlay = clampedVolume > 0 && state == .playing
        let shouldPause = clampedVolume <= 0

        if shouldPlay {
            try? startEngineIfNeeded()
            ensureNodeAttachedAndPlaying(id: id, node: node)
            Logger.sound.debug("Playing node for \(id, privacy: .public)")
        } else if shouldPause {
            if node.player.engine != nil {
                Logger.sound.debug("Detaching silent node for \(id, privacy: .public)")
                detachNodeIfNeeded(node)
            }
            checkIdleState()
        }

        if abs(previousVolume - clampedVolume) < 0.002 { return }

        let cutoff = id == "brownnoise" ? min(lowPassCutoff, 1200) : lowPassCutoff
        if node.player.engine != nil {
            audioMixer.apply(volume: clampedVolume, pan: pan, lowPassCutoff: cutoff, to: node.player, eq: node.eq)
        }
    }

    // MARK: - Crossfade

    func crossfade(to targetMix: [String: Float], duration: TimeInterval) async {
        Logger.sound.debug("Crossfade started over \(duration, privacy: .public)s")
        if state == .ready || state == .paused { resume() }

        let safeDuration = max(0.1, duration)
        let steps = max(4, min(10, Int(safeDuration * 4)))
        let interval = safeDuration / Double(steps)
        let snapshot = volumes
        let allLayerIDs = SoundLayerID.allCases.map(\.rawValue)
        let affectedIDs = allLayerIDs.filter { id in
            abs((snapshot[id] ?? 0) - (targetMix[id] ?? 0)) > 0.001
        }

        if affectedIDs.isEmpty { return }

        for step in 0...steps {
            if Task.isCancelled { return }
            let progress = Float(step) / Float(steps)
            for id in affectedIDs {
                let start = snapshot[id] ?? 0
                let target = targetMix[id] ?? 0
                setLayer(id, volume: start + (target - start) * progress)
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    // MARK: - Randomization

    func startRandomization(interval: TimeInterval, validRange: ClosedRange<Float>) {
        guard interval > 0 else { return }
        randomizationInterval = interval
        randomizationRange = validRange
        scheduleRandomizationIfNeeded()
    }

    func stopRandomization() {
        randomizationInterval = nil
        randomizationRange = nil
        stopRandomizationSchedule()
    }

    func currentLayerCount() -> Int { layerNodes.count }
    func volume(for id: String) -> Float { volumes[id] ?? 0 }

    private func scheduleRandomizationIfNeeded() {
        stopRandomizationSchedule()
        guard state == .playing,
              let interval = randomizationInterval,
              interval > 0,
              let validRange = randomizationRange else { return }

        randomizationTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await AuraBackgroundActor.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                guard self.state == .playing else { continue }
                let isSuspended = await AuraBackgroundActor.shared.isRenderingSuspended()
                if isSuspended { continue }
                for id in SoundLayerID.allCases.map(\.rawValue) {
                    self.setLayer(id, volume: Float.random(in: validRange))
                }
            }
        }
    }

    private func stopRandomizationSchedule() {
        randomizationTask?.cancel()
        randomizationTask = nil
    }

    // MARK: - Ducking

    func fadeDucking(to target: Float, duration: TimeInterval) {
        duckingTask?.cancel()
        let safeDuration = max(0.1, duration)
        let steps = max(8, min(30, Int(safeDuration * 15)))
        let interval = safeDuration / Double(steps)
        let start = duckingMultiplier
        guard abs(start - target) > 0.01 else {
            duckingMultiplier = target
            return
        }
        duckingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for step in 1...steps {
                if Task.isCancelled { return }
                let progress = Float(step) / Float(steps)
                self.duckingMultiplier = start + (target - start) * progress
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if !Task.isCancelled { self.duckingMultiplier = target }
        }
    }

    // MARK: - Memory Pressure

    private func startMemoryPressureMonitoring() {
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self else { return }
            let level = src.mask
            if level.contains(.critical) {
                Logger.sound.warning("⚠️ [SoundEngine] Critical memory pressure — stopping engine.")
                self.pause()
            } else if level.contains(.warning) {
                Logger.sound.warning("⚠️ [SoundEngine] Memory pressure warning — stopping idle nodes.")
                self.checkIdleState()
            }
        }
        src.activate()
        memoryPressureSource = src
    }
}
