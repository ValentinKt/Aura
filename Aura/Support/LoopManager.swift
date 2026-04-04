import AVFoundation
import os

/// Manages seamless looping of ambient audio layers using file-based streaming.
/// Uses AVAudioPlayerNode.scheduleFile with a completion handler that re-schedules
/// the file for gapless looping — no PCM buffer held in RAM.
final class LoopManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura",
        category: "LoopManager"
    )

    /// Starts seamless looping of `url` on `player`.
    /// The file is opened fresh for reading and streamed from disk each loop.
    /// RAM cost: file descriptor + AVAudioFile header (~4 KB), not the audio data.
    func startLoop(on player: AVAudioPlayerNode, url: URL) {
        player.stop()
        scheduleNextLoop(on: player, url: url)
    }

    func stopLoop(on player: AVAudioPlayerNode) {
        player.stop()
    }

    private func scheduleNextLoop(on player: AVAudioPlayerNode, url: URL) {
        guard let file = openFile(at: url) else { return }

        player.scheduleFile(file, at: nil) { [weak self] in
            // Completion fires on a background thread when the file finishes.
            // Re-schedule only if the player is still running (not detached/stopped).
            guard player.engine != nil else { return }
            self?.scheduleNextLoop(on: player, url: url)
        }
    }

    private func openFile(at url: URL) -> AVAudioFile? {
        do {
            return try AVAudioFile(forReading: url)
        } catch {
            Self.logger.error("Failed to open audio file \(url.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
