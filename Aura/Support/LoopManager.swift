import AVFoundation

final class LoopManager {
    func startLoop(on player: AVAudioPlayerNode, buffer: AVAudioPCMBuffer) {
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [.loops], completionHandler: nil)
        // Note: we don't call player.play() here anymore. 
        // SoundEngine will handle playback based on volume to save CPU.
    }

    func stopLoop(on player: AVAudioPlayerNode) {
        player.stop()
    }
}
