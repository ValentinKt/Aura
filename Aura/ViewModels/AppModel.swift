import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let persistence: PersistenceController
    let themeManager: ThemeManager
    let settingsEngine: SettingsEngine
    let soundEngine: SoundEngine
    let wallpaperEngine: WallpaperEngine
    let moodEngine: MoodEngine
    let playlistEngine: PlaylistEngine
    let weatherEngine: WeatherEngine
    let travelEngine: TravelEngine
    let presetEngine: PresetEngine

    var moodViewModel: MoodViewModel
    var playerViewModel: PlayerViewModel
    var playlistViewModel: PlaylistViewModel
    var settingsViewModel: SettingsViewModel
    var showImmersive: Bool = false
    var showCommandPalette: Bool = false

    init(persistence: PersistenceController) {
        let themeManager = ThemeManager()
        let settingsEngine = SettingsEngine(persistence: persistence)
        let soundEngine = SoundEngine(assetManager: AssetManager(), loopManager: LoopManager(), audioMixer: AudioMixer())
        let wallpaperEngine = WallpaperEngine(themeManager: themeManager)
        let moodEngine = MoodEngine(soundEngine: soundEngine, wallpaperEngine: wallpaperEngine, themeManager: themeManager, settingsEngine: settingsEngine)
        let playlistEngine = PlaylistEngine(moodEngine: moodEngine, persistence: persistence)
        let weatherEngine = WeatherEngine(moodEngine: moodEngine, settingsEngine: settingsEngine)
        let travelEngine = TravelEngine(moodEngine: moodEngine, wallpaperEngine: wallpaperEngine)
        let presetEngine = PresetEngine(persistence: persistence)

        self.persistence = persistence
        self.themeManager = themeManager
        self.settingsEngine = settingsEngine
        self.soundEngine = soundEngine
        self.wallpaperEngine = wallpaperEngine
        self.moodEngine = moodEngine
        self.playlistEngine = playlistEngine
        self.weatherEngine = weatherEngine
        self.travelEngine = travelEngine
        self.presetEngine = presetEngine

        let playerViewModel = PlayerViewModel(soundEngine: soundEngine, settingsEngine: settingsEngine, moodEngine: moodEngine)
        let moodViewModel = MoodViewModel(moodEngine: moodEngine, playerViewModel: playerViewModel)
        self.playerViewModel = playerViewModel
        self.moodViewModel = moodViewModel
        self.playlistViewModel = PlaylistViewModel(playlistEngine: playlistEngine)
        self.settingsViewModel = SettingsViewModel(settingsEngine: settingsEngine)
    }

    @MainActor
    convenience init() {
        self.init(persistence: PersistenceController.shared)
    }

    func start() async {
        print("🟢 [AppModel] Starting engines...")
        await moodEngine.start()
        print("🟢 [AppModel] Mood engine started.")
        presetEngine.loadDefaultPresets()
        weatherEngine.start()
        let settings = settingsEngine.loadSettings()
        if settings.randomAmbienceInterval > 0 {
            soundEngine.startRandomization(interval: settings.randomAmbienceInterval, validRange: 0.1...0.9)
            print("🟢 [AppModel] Randomization started.")
        }
        print("🟢 [AppModel] Start complete.")
    }

    func toggleWeatherSync(_ enabled: Bool) {
        settingsViewModel.toggleWeatherSync(enabled)
        if enabled {
            weatherEngine.start()
        } else {
            weatherEngine.stop()
        }
    }
}

import Foundation
import Observation

enum DownloadState: Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case downloaded
    case failed(error: String)
}

@MainActor
@Observable
final class DownloadManager {
    static let shared = DownloadManager()
    
    var downloadStates: [String: DownloadState] = [:]
    
    private let baseURL = "https://github.com/ValentinKt/Aura/releases/download/v1.0.0/"
    
    private init() {}
    
    func checkStatus(for resource: String) {
        if MediaUtils.resolveResourceURL(resource) != nil {
            downloadStates[resource] = .downloaded
        } else {
            downloadStates[resource] = .notDownloaded
        }
    }
    
    func isDownloaded(resource: String) -> Bool {
        if downloadStates[resource] == nil {
            checkStatus(for: resource)
        }
        return downloadStates[resource] == .downloaded
    }
    
    func download(_ resource: String) async {
        guard let url = URL(string: "\(baseURL)\(resource).zip") else {
            downloadStates[resource] = .failed(error: "Invalid URL")
            return
        }
        
        downloadStates[resource] = .downloading(progress: 0.0)
        
        do {
            let (tempURL, response) = try await URLSession.shared.download(from: url)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                downloadStates[resource] = .failed(error: "Server returned error")
                return
            }
            
            let fileManager = FileManager.default
            let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            let targetURL = cachesDirectory.appendingPathComponent("AuraExtractedMedia").appendingPathComponent("\(resource).zip")
            
            try? fileManager.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: targetURL.path) {
                try fileManager.removeItem(at: targetURL)
            }
            try fileManager.moveItem(at: tempURL, to: targetURL)
            
            // Extract it
            if let _ = MediaUtils.extractZip(targetURL, originalResource: resource) {
                downloadStates[resource] = .downloaded
            } else {
                downloadStates[resource] = .failed(error: "Extraction failed")
            }
            
        } catch {
            downloadStates[resource] = .failed(error: error.localizedDescription)
        }
    }
}
