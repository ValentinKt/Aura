import AVFoundation

final class AudioMixer {
    func apply(volume: Float, pan: Float, lowPassCutoff: Float, to player: AVAudioPlayerNode, eq: AVAudioUnitEQ) {
        player.volume = max(0, min(1, volume))
        player.pan = max(-1, min(1, pan))

        // Optimize by bypassing EQ and silencing if volume is 0
        if volume <= 0 {
            eq.bypass = true
            return
        }

        eq.bypass = false
        if let band = eq.bands.first {
            band.filterType = .lowPass
            band.frequency = max(20, min(20000, lowPassCutoff))
            band.bypass = false
        }
    }
}
