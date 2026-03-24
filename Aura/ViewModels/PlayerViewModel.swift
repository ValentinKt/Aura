import Foundation
import Observation

@MainActor
@Observable
final class PlayerViewModel {
    private let soundEngine: SoundEngine
    private let settingsEngine: SettingsEngine
    private let moodEngine: MoodEngine
    
    var isPlaying: Bool {
        soundEngine.state == .playing
    }
    var randomizeInterval: Double

    var layerVolumes: [String: Float] {
        soundEngine.volumes
    }
    
    var masterVolume: Float {
        get { soundEngine.masterVolume }
        set { 
            soundEngine.masterVolume = newValue 
            settingsEngine.updateMasterVolume(newValue)
        }
    }

    init(soundEngine: SoundEngine, settingsEngine: SettingsEngine, moodEngine: MoodEngine) {
        self.soundEngine = soundEngine
        self.settingsEngine = settingsEngine
        self.moodEngine = moodEngine
        
        let settings = settingsEngine.loadSettings()
        self.randomizeInterval = settings.randomAmbienceInterval
        self.soundEngine.masterVolume = settings.masterVolume
    }

    convenience init(soundEngine: SoundEngine, settingsEngine: SettingsEngine) {
        let themeManager = ThemeManager()
        let wallpaperEngine = WallpaperEngine(themeManager: themeManager)
        let moodEngine = MoodEngine(soundEngine: soundEngine, wallpaperEngine: wallpaperEngine, themeManager: themeManager, settingsEngine: settingsEngine)
        self.init(soundEngine: soundEngine, settingsEngine: settingsEngine, moodEngine: moodEngine)
    }

    func togglePlayback() {
        if isPlaying {
            soundEngine.pause()
        } else {
            soundEngine.resume()
        }
    }

    func setVolume(for id: String, volume: Float) {
        soundEngine.setLayer(id, volume: volume)
        // Update mood mix in persistence
        moodEngine.updateCurrentMoodMix(soundEngine.volumes)
    }

    func applyMix(_ mix: [String: Float]) {
        for (id, volume) in mix {
            setVolume(for: id, volume: volume)
        }
    }

    func updateRandomizeInterval(_ interval: Double) {
        randomizeInterval = interval
        settingsEngine.updateRandomAmbienceInterval(interval)
        if interval > 0 {
            soundEngine.startRandomization(interval: interval, validRange: 0.1...0.9)
        } else {
            soundEngine.stopRandomization()
        }
    }
}
