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
    let presetEngine: PresetEngine
    let quoteEngine: QuoteEngine

    var moodViewModel: MoodViewModel
    var playerViewModel: PlayerViewModel
    var playlistViewModel: PlaylistViewModel
    var settingsViewModel: SettingsViewModel
    var showImmersive: Bool = false
    var showCommandPalette: Bool = false
    var isReady: Bool = false

    init(persistence: PersistenceController) {
        let themeManager = ThemeManager()
        let settingsEngine = SettingsEngine(persistence: persistence)
        let soundEngine = SoundEngine(assetManager: AssetManager(), loopManager: LoopManager(), audioMixer: AudioMixer())
        let wallpaperEngine = WallpaperEngine(themeManager: themeManager)
        let moodEngine = MoodEngine(soundEngine: soundEngine, wallpaperEngine: wallpaperEngine, themeManager: themeManager, settingsEngine: settingsEngine)
        let playlistEngine = PlaylistEngine(moodEngine: moodEngine, persistence: persistence)
        let weatherEngine = WeatherEngine(moodEngine: moodEngine, settingsEngine: settingsEngine)
        let presetEngine = PresetEngine(persistence: persistence)
        let quoteEngine = QuoteEngine(persistence: persistence)

        self.persistence = persistence
        self.themeManager = themeManager
        self.settingsEngine = settingsEngine
        self.soundEngine = soundEngine
        self.wallpaperEngine = wallpaperEngine
        self.moodEngine = moodEngine
        self.playlistEngine = playlistEngine
        self.weatherEngine = weatherEngine
        self.presetEngine = presetEngine
        self.quoteEngine = quoteEngine

        let playerViewModel = PlayerViewModel(soundEngine: soundEngine, settingsEngine: settingsEngine, moodEngine: moodEngine)
        let moodViewModel = MoodViewModel(moodEngine: moodEngine, playerViewModel: playerViewModel, quoteEngine: quoteEngine)
        self.playerViewModel = playerViewModel
        self.moodViewModel = moodViewModel
        self.playlistViewModel = PlaylistViewModel(playlistEngine: playlistEngine)
        self.settingsViewModel = SettingsViewModel(settingsEngine: settingsEngine)
        self.wallpaperEngine.setWebsiteWallpaperInteractive(self.settingsViewModel.settings.websiteWallpaperInteractive)
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
        isReady = true
    }

    func toggleWeatherSync(_ enabled: Bool) {
        settingsViewModel.toggleWeatherSync(enabled)
        if enabled {
            weatherEngine.start()
        } else {
            weatherEngine.stop()
        }
    }

    func setWebsiteWallpaperInteractive(_ enabled: Bool) {
        settingsViewModel.updateWebsiteWallpaperInteractive(enabled)
        wallpaperEngine.setWebsiteWallpaperInteractive(enabled)
    }
}

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

    private let baseURL = "https://github.com/ValentinKt/Aura/releases/download/v1.0.1/"

    private init() {}

    func isDownloaded(resource: String) -> Bool {
        if downloadStates[resource] == nil {
            if let url = MediaUtils.resolveResourceURL(resource) {
                let expectedExt = (resource as NSString).pathExtension.lowercased()
                let resolvedExt = url.pathExtension.lowercased()
                let isVideoResource = ["mov", "mp4"].contains(expectedExt)
                let isURLVideo = ["mov", "mp4"].contains(resolvedExt)

                if isVideoResource && !isURLVideo {
                    // It resolved to an image fallback, so the video is not actually downloaded
                    downloadStates[resource] = .notDownloaded
                } else {
                    downloadStates[resource] = .downloaded
                }
            } else {
                downloadStates[resource] = .notDownloaded
            }
        }
        return downloadStates[resource] == .downloaded
    }

    func checkStatus(for resource: String) {
        _ = isDownloaded(resource: resource)

        if downloadStates[resource] == .notDownloaded {
            // Auto-download the first video of each mood if not downloaded
            if DownloadManager.isFirstVideo(resource) {
                Task {
                    await downloadIfNeeded(resource)
                }
            }
        }
    }

    static func isFirstVideo(_ resource: String) -> Bool {
        let name = URL(fileURLWithPath: resource).deletingPathExtension().lastPathComponent
        return name.hasSuffix("_1") ||
            name == "Donkey_Kong" ||
            name == "Mario_Pixel_Room" ||
            name == "Pixel_Cosmic" ||
            name == "Pixel_Cyberpunk_City" ||
            name == "Pixel_Gaming_Room" ||
            name == "Sailor_Moon" ||
            name == "Zelda_Pixel_Art"
    }

    func downloadIfNeeded(_ resource: String) async -> Bool {
        if isDownloaded(resource: resource) { return true }

        // Prevent concurrent downloads of the same resource
        if case .downloading = downloadStates[resource] {
            // Wait for it to finish (simple polling for now)
            while case .downloading = downloadStates[resource] {
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            return isDownloaded(resource: resource)
        }

        await download(resource)
        return isDownloaded(resource: resource)
    }

    func download(_ resource: String) async {
        downloadStates[resource] = .downloading(progress: 0.0)

        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            downloadStates[resource] = .failed(error: "Application Support directory not found")
            return
        }

        let videosDir = appSupport.appendingPathComponent("Aura/Videos", isDirectory: true)

        do {
            try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            downloadStates[resource] = .failed(error: error.localizedDescription)
            return
        }

        var lastError: Error?

        for candidate in remoteCandidates(for: resource) {
            guard let url = URL(string: "\(baseURL)\(candidate.remoteName)") else {
                continue
            }

            print("⬇️ [DownloadManager] Starting download for wallpaper from: \(url.absoluteString)")

            do {
                let wrapper = DownloadTaskWrapper()
                let tempURL = try await wrapper.download(url: url) { progress in
                    Task { @MainActor in
                        if case .downloading = self.downloadStates[resource] {
                            self.downloadStates[resource] = .downloading(progress: progress)
                        }
                    }
                }

                let targetURL = videosDir.appendingPathComponent(candidate.localName)

                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.moveItem(at: tempURL, to: targetURL)

                if candidate.shouldExtract {
                    if MediaUtils.extractZip(targetURL, originalResource: resource, destinationDir: videosDir) != nil {
                        print("✅ [DownloadManager] Successfully downloaded and extracted wallpaper from: \(url.absoluteString)")
                        try? fileManager.removeItem(at: targetURL)
                        downloadStates[resource] = .downloaded
                        return
                    }

                    print("❌ [DownloadManager] Extraction failed for archive: \(candidate.remoteName)")
                    try? fileManager.removeItem(at: targetURL)
                    lastError = NSError(
                        domain: "DownloadManager",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Extraction failed for \(candidate.remoteName)"]
                    )
                    continue
                }

                print("✅ [DownloadManager] Successfully downloaded wallpaper from: \(url.absoluteString)")
                downloadStates[resource] = .downloaded
                return
            } catch {
                print("❌ [DownloadManager] Download attempt failed for \(candidate.remoteName): \(error.localizedDescription)")
                lastError = error
            }
        }

        let message = lastError?.localizedDescription ?? "Download failed"
        print("❌ [DownloadManager] Download failed with error: \(message)")
        downloadStates[resource] = .failed(error: message)
    }

    private func remoteCandidates(for resource: String) -> [RemoteDownloadCandidate] {
        let resourceURL = URL(fileURLWithPath: resource)
        let name = resourceURL.deletingPathExtension().lastPathComponent
        let ext = resourceURL.pathExtension.lowercased()

        var candidates: [RemoteDownloadCandidate] = []

        if !ext.isEmpty {
            candidates.append(RemoteDownloadCandidate(remoteName: resource, localName: resource, shouldExtract: false))
        }

        if ext == "mov" {
            candidates.append(RemoteDownloadCandidate(remoteName: "\(name).mp4", localName: "\(name).mp4", shouldExtract: false))
        } else if ext == "mp4" {
            candidates.append(RemoteDownloadCandidate(remoteName: "\(name).mov", localName: "\(name).mov", shouldExtract: false))
        }

        candidates.append(RemoteDownloadCandidate(remoteName: "\(name).zip", localName: "\(name).zip", shouldExtract: true))
        candidates.append(RemoteDownloadCandidate(remoteName: "\(resource).zip", localName: "\(resource).zip", shouldExtract: true))

        if ext == "mov" {
            candidates.append(RemoteDownloadCandidate(remoteName: "\(name).mp4.zip", localName: "\(name).mp4.zip", shouldExtract: true))
        } else if ext == "mp4" {
            candidates.append(RemoteDownloadCandidate(remoteName: "\(name).mov.zip", localName: "\(name).mov.zip", shouldExtract: true))
        }

        var seen = Set<String>()
        return candidates.filter { seen.insert($0.remoteName).inserted }
    }
}

private struct RemoteDownloadCandidate {
    let remoteName: String
    let localName: String
    let shouldExtract: Bool
}

class DownloadTaskWrapper: NSObject {
    private var observation: NSKeyValueObservation?

    func download(url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.downloadTask(with: url) { localURL, response, error in
                self.observation?.invalidate()
                self.observation = nil

                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    continuation.resume(throwing: NSError(domain: "DownloadManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"]))
                    return
                }

                if !(200...299).contains(httpResponse.statusCode) {
                    let statusCode = httpResponse.statusCode
                    continuation.resume(throwing: NSError(domain: "DownloadManager", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Server returned status code \(statusCode)"]))
                    return
                }

                guard let localURL = localURL else {
                    continuation.resume(throwing: NSError(domain: "DownloadManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "No data received"]))
                    return
                }

                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                do {
                    if FileManager.default.fileExists(atPath: tempURL.path) {
                        try FileManager.default.removeItem(at: tempURL)
                    }
                    try FileManager.default.moveItem(at: localURL, to: tempURL)
                    continuation.resume(returning: tempURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            self.observation = task.progress.observe(\.fractionCompleted) { progress, _ in
                progressHandler(progress.fractionCompleted)
            }

            task.resume()
        }
    }
}
