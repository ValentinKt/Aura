import Foundation
import Observation
import os

@MainActor
@Observable
final class AppModel {
    enum ShortcutRoutine: Sendable {
        case deepFocusJourney
        case windDown
    }

    private enum StorageKey {
        static let favoriteSceneIDs = "Aura.favoriteSceneIDs"
        static let recentSceneIDs = "Aura.recentSceneIDs"
        static let lastResumableSceneID = "Aura.lastResumableSceneID"
        static let initialAuraWallpaperApplied = "Aura.initialAuraWallpaperApplied"
    }

    static let shared = AppModel(persistence: PersistenceController.shared)

    let persistence: PersistenceController
    let themeManager: ThemeManager
    let settingsEngine: SettingsEngine
    let soundEngine: SoundEngine
    let wallpaperEngine: WallpaperEngine
    let moodEngine: MoodEngine
    let playlistEngine: PlaylistEngine
    let weatherEngine: WeatherEngine
    let dynamicDesktopGenerator: DynamicDesktopGenerator
    let presetEngine: PresetEngine
    let smartDuckingService: SmartDuckingService
    let aiImageGenerationViewModel: AIImageGenerationViewModel

    var moodViewModel: MoodViewModel
    var playerViewModel: PlayerViewModel
    var playlistViewModel: PlaylistViewModel
    var settingsViewModel: SettingsViewModel
    var showImmersive: Bool = false
    var showCommandPalette: Bool = false
    var showCreateMoodSheet: Bool = false
    var isReady: Bool = false
    var isStarting: Bool = false
    var favoriteSceneIDs: [String]
    var recentSceneIDs: [String]
    var lastResumableSceneID: String?
    var sleepTimerEndDate: Date?
    private let startupTimeout: Duration = .seconds(8)
    private let recentSceneLimit = 6
    private var sleepTimerTask: Task<Void, Never>?
    private var startupWaiters: [CheckedContinuation<Void, Never>] = []

    func suspend() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        startupWaiters.forEach { $0.resume() }
        startupWaiters.removeAll()

        showCommandPalette = false
        showCreateMoodSheet = false
    }

    init(persistence: PersistenceController) {
        let themeManager = ThemeManager()
        let settingsEngine = SettingsEngine(persistence: persistence)
        let soundEngine = SoundEngine(assetManager: AssetManager(), loopManager: LoopManager(), audioMixer: AudioMixer())
        let wallpaperEngine = WallpaperEngine(themeManager: themeManager)
        let moodEngine = MoodEngine(soundEngine: soundEngine, wallpaperEngine: wallpaperEngine, themeManager: themeManager, settingsEngine: settingsEngine)
        let playlistEngine = PlaylistEngine(moodEngine: moodEngine, persistence: persistence)
        let weatherEngine = WeatherEngine(moodEngine: moodEngine, settingsEngine: settingsEngine)
        let dynamicDesktopGenerator: DynamicDesktopGenerator
        if let generator = try? DynamicDesktopGenerator() {
            dynamicDesktopGenerator = generator
        } else {
            let fallbackManager = UpscaleManager(workerFactory: { ImageUpscaler.createDummy() })
            dynamicDesktopGenerator = DynamicDesktopGenerator(upscaleManager: fallbackManager)
        }
        let presetEngine = PresetEngine(persistence: persistence)
        let smartDuckingService = SmartDuckingService(soundEngine: soundEngine)
        let aiImageGenerationViewModel = AIImageGenerationViewModel()

        self.persistence = persistence
        self.themeManager = themeManager
        self.settingsEngine = settingsEngine
        self.soundEngine = soundEngine
        self.wallpaperEngine = wallpaperEngine
        self.moodEngine = moodEngine
        self.playlistEngine = playlistEngine
        self.weatherEngine = weatherEngine
        self.dynamicDesktopGenerator = dynamicDesktopGenerator
        self.presetEngine = presetEngine
        self.smartDuckingService = smartDuckingService
        self.aiImageGenerationViewModel = aiImageGenerationViewModel
        self.favoriteSceneIDs = UserDefaults.standard.stringArray(forKey: StorageKey.favoriteSceneIDs) ?? []
        self.recentSceneIDs = UserDefaults.standard.stringArray(forKey: StorageKey.recentSceneIDs) ?? []
        self.lastResumableSceneID = UserDefaults.standard.string(forKey: StorageKey.lastResumableSceneID)

        let playerViewModel = PlayerViewModel(soundEngine: soundEngine, settingsEngine: settingsEngine, moodEngine: moodEngine)
        let moodViewModel = MoodViewModel(moodEngine: moodEngine, playerViewModel: playerViewModel, dynamicDesktopGenerator: dynamicDesktopGenerator)
        self.playerViewModel = playerViewModel
        self.moodViewModel = moodViewModel
        self.playlistViewModel = PlaylistViewModel(playlistEngine: playlistEngine)
        self.settingsViewModel = SettingsViewModel(settingsEngine: settingsEngine)
        self.wallpaperEngine.setWebsiteWallpaperInteractive(self.settingsViewModel.settings.websiteWallpaperInteractive)
        self.smartDuckingService.isEnabled = self.settingsViewModel.settings.smartDuckingEnabled
        self.moodViewModel.onMoodSelected = { [weak self] mood in
            self?.recordSceneActivation(moodID: mood.id)
        }
        Logger.app.info("🟢 [AppModel] Initialization started")
    }

    @MainActor
    convenience init() {
        self.init(persistence: PersistenceController.shared)
    }

    func start() async {
        guard !isReady, !isStarting else { return }
        isStarting = true
        wallpaperEngine.setPresentationSuppressed(true)
        defer {
            if !isReady {
                wallpaperEngine.setPresentationSuppressed(false)
            }
            isStarting = false
            resumeStartupWaiters()
        }
        let isFirstLaunch = !UserDefaults.standard.bool(forKey: StorageKey.initialAuraWallpaperApplied)

        Logger.app.info("🟢 [AppModel] Starting engines (First launch: \(isFirstLaunch))...")
        let startupCompleted = await runInitialStartupSequence(isFirstLaunch: isFirstLaunch)
        if !startupCompleted {
            Logger.app.warning("🟧 [AppModel] Startup timed out, continuing with partial readiness.")
        }
        Logger.app.info("🟢 [AppModel] Mood engine started.")
        presetEngine.loadDefaultPresets()
        let settings = settingsEngine.loadSettings()
        isReady = true
        wallpaperEngine.setPresentationSuppressed(false)
        await moodEngine.completeDeferredStartupIfNeeded()
        await setupFirstLaunchExperience()
        weatherEngine.start()
        if settings.randomAmbienceInterval > 0 {
            soundEngine.startRandomization(interval: settings.randomAmbienceInterval, validRange: 0.1...0.9)
            Logger.app.info("🟢 [AppModel] Randomization started.")
        }
        if let currentMood = moodViewModel.currentMood {
            recordSceneActivation(moodID: currentMood.id)
        }
        Logger.app.info("🟢 [AppModel] Start complete.")
    }

    func startIfNeeded() async {
        guard !isReady else { return }

        if isStarting {
            await withCheckedContinuation { continuation in
                startupWaiters.append(continuation)
            }
            return
        }

        await start()
    }

    private func runInitialStartupSequence(isFirstLaunch: Bool) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask { [moodEngine] in
                await moodEngine.start(deferInitialPresentation: true, skipDefaultMood: isFirstLaunch)
                return true
            }

            group.addTask { [startupTimeout] in
                try? await Task.sleep(for: startupTimeout)
                return false
            }

            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }

    private func setupFirstLaunchExperience() async {
        guard !UserDefaults.standard.bool(forKey: StorageKey.initialAuraWallpaperApplied) else { return }
        guard let firstAuraMood = moodViewModel.firstMood(inSubtheme: "Aura") else { return }

        let primaryResource = firstAuraMood.wallpaper.resources.first ?? ""
        if !primaryResource.isEmpty {
            let didDownload = await DownloadManager.shared.downloadIfNeeded(primaryResource)
            guard didDownload else { return }
        }

        moodViewModel.selectedSubtheme = firstAuraMood.subtheme
        await moodEngine.applyWallpaperOnlyMood(firstAuraMood)
        UserDefaults.standard.set(true, forKey: StorageKey.initialAuraWallpaperApplied)
    }

    func performShortcut(_ routine: ShortcutRoutine) async throws {
        await startIfNeeded()

        let mood: Mood?
        switch routine {
        case .deepFocusJourney:
            mood = moodViewModel.firstMood(inSubtheme: "DeepFocus")
        case .windDown:
            mood = moodViewModel.firstMood(inSubtheme: "Rest")
        }

        guard let mood else {
            throw ShortcutExecutionError.moodUnavailable
        }

        showImmersive = true
        moodViewModel.selectedSubtheme = mood.subtheme
        moodViewModel.selectMood(mood)
    }

    var favoriteScenes: [Mood] {
        favoriteSceneIDs.compactMap(moodViewModel.mood(for:))
    }

    var recentScenes: [Mood] {
        recentSceneIDs.compactMap(moodViewModel.mood(for:))
    }

    var lastResumableScene: Mood? {
        guard let lastResumableSceneID else { return nil }
        return moodViewModel.mood(for: lastResumableSceneID)
    }

    var currentSceneIsFavorite: Bool {
        guard let currentMood = moodViewModel.currentMood else { return false }
        return favoriteSceneIDs.contains(currentMood.id)
    }

    var sleepTimerRemainingDescription: String? {
        guard let sleepTimerEndDate else { return nil }
        let remaining = max(0, Int(sleepTimerEndDate.timeIntervalSinceNow))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    func toggleFavoriteForCurrentScene() {
        guard let currentMood = moodViewModel.currentMood else { return }
        toggleFavoriteScene(currentMood.id)
    }

    func toggleFavoriteScene(_ moodID: String) {
        if let index = favoriteSceneIDs.firstIndex(of: moodID) {
            favoriteSceneIDs.remove(at: index)
        } else {
            favoriteSceneIDs.insert(moodID, at: 0)
        }
        favoriteSceneIDs = Array(favoriteSceneIDs.prefix(recentSceneLimit))
        persistSceneState()
    }

    func removeAllFavoriteScenes() {
        favoriteSceneIDs.removeAll()
        persistSceneState()
    }

    func launchScene(id moodID: String, immersive: Bool = true, resumePlayback: Bool = true) async throws -> Mood {
        await startIfNeeded()

        guard let mood = moodViewModel.mood(for: moodID) else {
            throw ShortcutExecutionError.moodUnavailable
        }

        showImmersive = immersive
        moodViewModel.selectedSubtheme = mood.subtheme
        moodViewModel.selectMood(mood)

        if resumePlayback, !playerViewModel.isPlaying {
            soundEngine.resume()
        }

        return mood
    }

    func launchScene(named name: String, immersive: Bool = true, resumePlayback: Bool = true) async throws -> Mood {
        await startIfNeeded()

        guard let mood = moodViewModel.moods.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            throw ShortcutExecutionError.moodUnavailable
        }

        return try await launchScene(id: mood.id, immersive: immersive, resumePlayback: resumePlayback)
    }

    func resumeLastScene() async throws -> Mood {
        guard let lastResumableScene else {
            throw ShortcutExecutionError.moodUnavailable
        }

        return try await launchScene(id: lastResumableScene.id, immersive: showImmersive, resumePlayback: true)
    }

    func startSleepTimer(minutes: Int) {
        guard minutes > 0 else {
            cancelSleepTimer()
            return
        }

        sleepTimerTask?.cancel()
        let endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepTimerEndDate = endDate

        sleepTimerTask = Task(priority: .background) { @MainActor [weak self] in
            guard let self else { return }
            await AuraBackgroundActor.sleep(for: .seconds(minutes * 60))
            await AuraBackgroundActor.waitUntilRenderingActive()
            guard !Task.isCancelled, self.sleepTimerEndDate == endDate else { return }
            self.pauseForSleepTimer()
            self.sleepTimerEndDate = nil
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerEndDate = nil
    }

    private func resumeStartupWaiters() {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func availableAutomationScenes() -> [Mood] {
        moodViewModel.moods.sorted {
            if $0.subtheme == $1.subtheme {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.subtheme.localizedCaseInsensitiveCompare($1.subtheme) == .orderedAscending
        }
    }

    func automationSceneName(for sceneID: String) -> String {
        guard let mood = moodViewModel.mood(for: sceneID) else {
            return sceneID
        }
        return "\(mood.name) · \(mood.subtheme)"
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

    func setSmartDuckingEnabled(_ enabled: Bool) {
        settingsViewModel.updateSmartDuckingEnabled(enabled)
        smartDuckingService.isEnabled = enabled
    }

    func clearVideoCache() {
        Task {
            let fileManager = FileManager.default
            if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let videosDir = appSupport.appendingPathComponent("Aura/Videos", isDirectory: true)
                if fileManager.fileExists(atPath: videosDir.path) {
                    try? fileManager.removeItem(at: videosDir)
                }

                let customWallpapersDir = appSupport.appendingPathComponent("Aura/CustomWallpapers", isDirectory: true)
                if fileManager.fileExists(atPath: customWallpapersDir.path) {
                    try? fileManager.removeItem(at: customWallpapersDir)
                }
            }

            await MainActor.run {
                DownloadManager.shared.downloadStates.removeAll()
                // Remove all custom moods that rely on deleted custom wallpapers
                let moodsToRemove = self.moodViewModel.moods.filter { mood in
                    guard UUID(uuidString: mood.id) != nil else { return false }
                    return mood.wallpaper.resources.first?.contains("CustomWallpapers") == true
                }
                for mood in moodsToRemove {
                    self.moodViewModel.removeMood(mood)
                }
            }
        }
    }

    func purgeTransientCaches() {
        URLCache.shared.removeAllCachedResponses()
        MediaUtils.purgeCaches()
        startupWaiters.removeAll(keepingCapacity: false)
        DownloadManager.shared.purgeTransientState()
    }

    private func recordSceneActivation(moodID: String) {
        recentSceneIDs.removeAll { $0 == moodID }
        recentSceneIDs.insert(moodID, at: 0)
        recentSceneIDs = Array(recentSceneIDs.prefix(recentSceneLimit))
        lastResumableSceneID = moodID
        persistSceneState()
    }

    private func persistSceneState() {
        let defaults = UserDefaults.standard
        defaults.set(favoriteSceneIDs, forKey: StorageKey.favoriteSceneIDs)
        defaults.set(recentSceneIDs, forKey: StorageKey.recentSceneIDs)
        defaults.set(lastResumableSceneID, forKey: StorageKey.lastResumableSceneID)
    }

    private func pauseForSleepTimer() {
        if playerViewModel.isPlaying {
            soundEngine.pause()
        }
    }
}

enum ShortcutExecutionError: LocalizedError {
    case moodUnavailable

    var errorDescription: String? {
        switch self {
        case .moodUnavailable:
            return "Aura couldn't find the requested automation mood."
        }
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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "Download")

    private let urlSession: URLSession
    private var downloadWaiters: [String: [CheckedContinuation<Bool, Never>]] = [:]

    private init() {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 2
        self.urlSession = URLSession(configuration: config)
    }

    func purgeTransientState() {
        downloadStates = downloadStates.filter { _, state in
            if case .downloading = state {
                return true
            }
            return false
        }
        downloadWaiters = downloadWaiters.filter { key, _ in
            if case .downloading = downloadStates[key] {
                return true
            }
            return false
        }
    }

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

        if case .downloading = downloadStates[resource] {
            return await withCheckedContinuation { continuation in
                downloadWaiters[resource, default: []].append(continuation)
            }
        }

        await download(resource)
        return isDownloaded(resource: resource)
    }

    func download(_ resource: String) async {
        updateDownloadState(.downloading(progress: 0.0), for: resource)

        let fileManager = FileManager.default
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            updateDownloadState(.failed(error: "Application Support directory not found"), for: resource)
            return
        }

        let videosDir = appSupport.appendingPathComponent("Aura/Videos", isDirectory: true)

        do {
            try fileManager.createDirectory(at: videosDir, withIntermediateDirectories: true, attributes: nil)
        } catch {
            updateDownloadState(.failed(error: error.localizedDescription), for: resource)
            return
        }

        var lastError: Error?

        for candidate in remoteCandidates(for: resource) {
            guard let url = URL(string: "\(baseURL)\(candidate.remoteName)") else {
                continue
            }

            logger.debug("Starting wallpaper download from \(url.absoluteString, privacy: .public)")

            do {
                let wrapper = DownloadTaskWrapper(session: self.urlSession)
                let tempURL = try await wrapper.download(url: url) { progress in
                    Task(priority: .background) { @MainActor in
                        self.updateDownloadProgress(progress, for: resource)
                    }
                }

                let targetURL = videosDir.appendingPathComponent(candidate.localName)

                if fileManager.fileExists(atPath: targetURL.path) {
                    try fileManager.removeItem(at: targetURL)
                }
                try fileManager.moveItem(at: tempURL, to: targetURL)

                if candidate.shouldExtract {
                    if MediaUtils.extractZip(targetURL, originalResource: resource, destinationDir: videosDir) != nil {
                        logger.notice("Downloaded and extracted wallpaper from \(url.absoluteString, privacy: .public)")
                        try? fileManager.removeItem(at: targetURL)
                        MediaUtils.clearCache(for: resource)
                        updateDownloadState(.downloaded, for: resource)
                        return
                    }

                    logger.error("Extraction failed for archive \(candidate.remoteName, privacy: .public)")
                    try? fileManager.removeItem(at: targetURL)
                    lastError = NSError(
                        domain: "DownloadManager",
                        code: -4,
                        userInfo: [NSLocalizedDescriptionKey: "Extraction failed for \(candidate.remoteName)"]
                    )
                    continue
                }

                logger.notice("Downloaded wallpaper from \(url.absoluteString, privacy: .public)")
                MediaUtils.clearCache(for: resource)
                updateDownloadState(.downloaded, for: resource)
                return
            } catch {
                logger.error("Download attempt failed for \(candidate.remoteName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }

        let message = lastError?.localizedDescription ?? "Download failed"
        logger.error("Download failed: \(message, privacy: .public)")
        updateDownloadState(.failed(error: message), for: resource)
    }

    private func updateDownloadProgress(_ progress: Double, for resource: String) {
        guard case .downloading(let currentProgress) = downloadStates[resource] else { return }

        let clampedProgress = min(max(progress, 0), 1)
        let threshold = 0.05
        let shouldPublish = abs(clampedProgress - currentProgress) >= threshold || clampedProgress >= 1 || clampedProgress <= 0

        guard shouldPublish else { return }
        updateDownloadState(.downloading(progress: clampedProgress), for: resource)
    }

    private func updateDownloadState(_ state: DownloadState, for resource: String) {
        downloadStates[resource] = state

        guard case .downloading = state else {
            let result = state == .downloaded
            let continuations = downloadWaiters.removeValue(forKey: resource) ?? []
            continuations.forEach { $0.resume(returning: result) }
            return
        }
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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        super.init()
    }

    func download(url: URL, progressHandler: @escaping (Double) -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url) { localURL, response, error in
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
