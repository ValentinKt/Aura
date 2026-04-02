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
        case bufferLoadingFailed(String)
    }

    struct LayerNode {
        let player: AVAudioPlayerNode
        let eq: AVAudioUnitEQ
    }

    private let engine = AVAudioEngine()
    private let assetManager: AssetManager
    private let loopManager: LoopManager
    private let audioMixer: AudioMixer
    private var layerNodes: [String: LayerNode] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]

    // Custom audio player node for external files
    private let customPlayer = AVAudioPlayerNode()
    private let customEQ = AVAudioUnitEQ(numberOfBands: 1)

    private(set) var state: EngineState = .uninitialized
    var volumes: [String: Float] = [:]
    var masterVolume: Float = 0.6 {
        didSet {
            updateOutputVolume()
        }
    }

    private var duckingMultiplier: Float = 1.0 {
        didSet {
            updateOutputVolume()
        }
    }

    private var duckingTask: Task<Void, Never>?

    func updateOutputVolume() {
        engine.mainMixerNode.outputVolume = masterVolume * duckingMultiplier
    }

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
                let value = start + (target - start) * progress
                self.duckingMultiplier = value
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            if !Task.isCancelled {
                self.duckingMultiplier = target
            }
        }
    }

    private var randomizationTask: Task<Void, Never>?

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

    func prepare() async throws {
        guard state == .uninitialized || state == .error else { return }
        state = .preparing
        Logger.sound.info("🟢 [SoundEngine] Starting engine...")

        // 1. Preload buffers first to know their format
        do {
            try await preloadBuffers()
        } catch {
            Logger.sound.error("🟥 [SoundEngine] Failed to preload buffers: \(error.localizedDescription)")
            state = .error
            throw error
        }

        // 2. Attach and connect nodes based on buffer format
        for id in SoundLayerID.allCases.map(\.rawValue) {
            let player = AVAudioPlayerNode()
            let eq = AVAudioUnitEQ(numberOfBands: 1)
            engine.attach(player)
            engine.attach(eq)

            // Use buffer format if available, otherwise default to stereo
            let format = buffers[id]?.format ?? AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)

            engine.connect(player, to: eq, format: format)
            engine.connect(eq, to: engine.mainMixerNode, format: format)
            layerNodes[id] = LayerNode(player: player, eq: eq)
        }

        // Setup custom player
        engine.attach(customPlayer)
        engine.attach(customEQ)
        let standardFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)
        engine.connect(customPlayer, to: customEQ, format: standardFormat)
        engine.connect(customEQ, to: engine.mainMixerNode, format: standardFormat)

        engine.prepare()
        do {
            try engine.start()
        } catch {
            Logger.sound.error("🟥 [SoundEngine] Failed to start engine: \(error.localizedDescription)")
            state = .error
            throw SoundEngineError.engineStartFailed(error.localizedDescription)
        }

        startAllLoops()
        state = .ready
        Logger.sound.info("🟢 [SoundEngine] Engine started and ready.")
    }

    func stop() {
        print("🟢 [SoundEngine] Stopping all audio")
        engine.stop()
        customPlayer.stop()
        state = .uninitialized
    }

    func pause() {
        guard state == .playing || state == .ready else { return }
        for node in layerNodes.values {
            node.player.pause()
        }
        customPlayer.pause()
        state = .paused
    }

    func resume() {
        guard state == .paused || state == .ready else { return }
        if !engine.isRunning {
            try? engine.start()
        }
        for (id, node) in layerNodes {
            if let vol = volumes[id], vol > 0 {
                if !node.player.isPlaying {
                    node.player.play()
                }
            } else {
                node.player.pause()
            }
        }
        if !customPlayer.isPlaying {
            customPlayer.play()
        }
        state = .playing
    }

    func playCustomAudio(url: URL) async throws {
        print("🟢 [SoundEngine] Playing custom audio from URL: \(url.path)")
        // Mute all other layers
        await crossfade(to: [:], duration: 1.0)

        // Stop current custom audio if any
        customPlayer.stop()

        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            print("🟥 [SoundEngine] Failed to read audio file at \(url.path): \(error.localizedDescription)")
            throw error
        }
        let format = file.processingFormat

        // Reconnect with correct format if needed
        engine.disconnectNodeOutput(customPlayer)
        engine.disconnectNodeOutput(customEQ)
        engine.connect(customPlayer, to: customEQ, format: format)
        engine.connect(customEQ, to: engine.mainMixerNode, format: format)

        await customPlayer.scheduleFile(file, at: nil)

        if !engine.isRunning {
            try engine.start()
        }

        customPlayer.volume = 1.0
        customPlayer.play()
        state = .playing
    }

    func setLayer(_ id: String, volume: Float, pan: Float = 0, lowPassCutoff: Float = 12000) {
        guard SoundLayerID(rawValue: id) != nil else { return }
        let clampedVolume = max(0, min(1, volume))
        let previousVolume = volumes[id] ?? 0
        volumes[id] = clampedVolume
        guard let node = layerNodes[id] else { return }

        // Handle play/pause state based on volume
        let shouldPlay = clampedVolume > 0 && state == .playing
        let shouldPause = clampedVolume <= 0
        if shouldPlay {
            if !engine.isRunning {
                try? engine.start()
            }
            if !node.player.isPlaying {
                print("🟢 [SoundEngine] Playing node for \(id)")
                node.player.play()
            }
        } else if shouldPause {
            if node.player.isPlaying {
                print("🟢 [SoundEngine] Pausing node for \(id)")
                node.player.pause()
            }
        }

        if abs(previousVolume - clampedVolume) < 0.002 {
            return
        }

        let cutoff = id == "brownnoise" ? min(lowPassCutoff, 1200) : lowPassCutoff
        audioMixer.apply(volume: clampedVolume, pan: pan, lowPassCutoff: cutoff, to: node.player, eq: node.eq)
    }

    func crossfade(to targetMix: [String: Float], duration: TimeInterval) async {
        print("🟢 [SoundEngine] Crossfade started over \(duration)s")
        if state == .ready || state == .paused {
            resume()
        }

        let safeDuration = max(0.1, duration)
        // Reduce the number of crossfade steps to lower CPU load and avoid HAL overload logs
        let steps = max(4, min(10, Int(safeDuration * 4)))
        let interval = safeDuration / Double(steps)
        let snapshot = volumes
        let allLayerIDs = SoundLayerID.allCases.map(\.rawValue)
        let affectedIDs = allLayerIDs.filter { id in
            let start = snapshot[id] ?? 0
            let target = targetMix[id] ?? 0
            return abs(start - target) > 0.001
        }

        if affectedIDs.isEmpty {
            return
        }

        for step in 0...steps {
            if Task.isCancelled {
                return
            }
            let progress = Float(step) / Float(steps)
            for id in affectedIDs {
                let start = snapshot[id] ?? 0
                let target = targetMix[id] ?? 0
                let value = start + (target - start) * progress
                setLayer(id, volume: value)
            }
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    func startRandomization(interval: TimeInterval, validRange: ClosedRange<Float>) {
        randomizationTask?.cancel()
        guard interval > 0 else { return }
        randomizationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                for id in SoundLayerID.allCases.map(\.rawValue) {
                    let random = Float.random(in: validRange)
                    self.setLayer(id, volume: random)
                }
            }
        }
    }

    func stopRandomization() {
        randomizationTask?.cancel()
        randomizationTask = nil
    }

    func currentLayerCount() -> Int {
        layerNodes.count
    }

    func volume(for id: String) -> Float {
        volumes[id] ?? 0
    }

    private func preloadBuffers() async throws {
        let assetManager = self.assetManager
        await withTaskGroup(of: (String, AVAudioPCMBuffer?).self) { group in
            for id in SoundLayerID.allCases.map(\.rawValue) {
                group.addTask {
                    let buffer = await assetManager.loadAudioBuffer(named: id)
                    return (id, buffer)
                }
            }

            for await (id, buffer) in group {
                if let buffer = buffer {
                    buffers[id] = buffer
                }
            }
        }
    }

    private func startAllLoops() {
        for (id, node) in layerNodes {
            guard let buffer = buffers[id] else {
                continue
            }
            loopManager.startLoop(on: node.player, buffer: buffer)
            volumes[id] = 0
            node.player.volume = 0 // Start muted
        }
    }

    deinit {
    }
}
