import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    private let settingsEngine: SettingsEngine
    var settings: UserSettings

    init(settingsEngine: SettingsEngine) {
        self.settingsEngine = settingsEngine
        self.settings = settingsEngine.loadSettings()
    }

    func toggleWeatherSync(_ enabled: Bool) {
        settings.weatherSyncEnabled = enabled
        settingsEngine.updateWeatherSync(enabled)
    }

    func updateTransitionDuration(_ duration: Double) {
        settings.transitionDuration = duration
        settingsEngine.updateTransitionDuration(duration)
    }

    func updateRandomAmbienceInterval(_ interval: Double) {
        settings.randomAmbienceInterval = interval
        settingsEngine.updateRandomAmbienceInterval(interval)
    }

    func updateKeepCurrentWallpaper(_ enabled: Bool) {
        settings.keepCurrentWallpaper = enabled
        settingsEngine.updateKeepCurrentWallpaper(enabled)
    }
}
