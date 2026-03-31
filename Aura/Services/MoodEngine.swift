import Foundation
import Observation

@MainActor
@Observable
final class MoodEngine {
    enum MoodState: String, Codable {
        case idle
        case transitioning
        case error
    }

    private enum ApplyStrategy {
        case standard
        case deferredStartup
        case wallpaperOnly
    }

    private let soundEngine: SoundEngine
    private let wallpaperEngine: WallpaperEngine
    private let themeManager: ThemeManager
    private let settingsEngine: SettingsEngine

    private(set) var moods: [Mood] = []
    private var customMoods: [Mood] = []
    var currentMood: Mood?
    var state: MoodState = .idle
    var lastError: String?

    private var transitionTask: Task<Void, Never>?
    private var deferredStartupMix: [String: Float]?
    private var deferredStartupMoodID: String?

    init(soundEngine: SoundEngine, wallpaperEngine: WallpaperEngine, themeManager: ThemeManager, settingsEngine: SettingsEngine) {
        self.soundEngine = soundEngine
        self.wallpaperEngine = wallpaperEngine
        self.themeManager = themeManager
        self.settingsEngine = settingsEngine
        self.loadMoods()
    }

    private func loadMoods() {
        self.customMoods = settingsEngine.loadCustomMoods()
        var baseMoods = MoodEngine.builtInMoods()
        let savedMixes = settingsEngine.loadMoodMixes()

        // Apply saved mixes to both built-in and custom moods
        for i in 0..<baseMoods.count {
            if let savedMix = savedMixes[baseMoods[i].id] {
                baseMoods[i].layerMix = savedMix
            }
        }

        for i in 0..<customMoods.count {
            if let savedMix = savedMixes[customMoods[i].id] {
                customMoods[i].layerMix = savedMix
            }
        }

        self.moods = baseMoods + customMoods
    }

    func updateCurrentMoodMix(_ mix: [String: Float]) {
        guard var current = currentMood else { return }
        current.layerMix = mix
        currentMood = current

        // Update in the moods list as well
        if let index = moods.firstIndex(where: { $0.id == current.id }) {
            moods[index].layerMix = mix
        }

        // Persist
        settingsEngine.saveMoodMix(moodID: current.id, layerMix: mix)
    }

    func addCustomMood(_ mood: Mood) {
        print("🟢 [MoodEngine] Adding custom mood: \(mood.name)")
        customMoods.append(mood)
        settingsEngine.saveCustomMoods(customMoods)
        self.moods = MoodEngine.builtInMoods() + customMoods
    }

    func removeCustomMood(id: String) {
        print("🟢 [MoodEngine] Removing custom mood ID: \(id)")
        customMoods.removeAll { $0.id == id }
        settingsEngine.saveCustomMoods(customMoods)
        self.moods = MoodEngine.builtInMoods() + customMoods

        if currentMood?.id == id {
            if let first = moods.first {
                Task { await applyMood(first) }
            }
        }
    }

    func start(deferInitialPresentation: Bool = false) async {
        do {
            try await soundEngine.prepare()
            if let last = settingsEngine.loadSettings().lastUsedMoodID, let mood = moods.first(where: { $0.id == last }) {
                await applyMood(mood, strategy: deferInitialPresentation ? .deferredStartup : .standard)
            } else if let first = moods.first {
                await applyMood(first, strategy: deferInitialPresentation ? .deferredStartup : .standard)
            }
            if state != .error {
                state = .idle
            }
        } catch {
            state = .error
            lastError = error.localizedDescription
            print("🟥 [MoodEngine] Failed to start: \(error)")
        }
    }

    func applyMood(_ mood: Mood) async {
        await applyMood(mood, strategy: .standard)
    }

    func applyWallpaperOnlyMood(_ mood: Mood) async {
        await applyMood(mood, strategy: .wallpaperOnly)
    }

    func completeDeferredStartupIfNeeded() async {
        guard let deferredStartupMix, let deferredStartupMoodID else { return }

        self.deferredStartupMix = nil
        self.deferredStartupMoodID = nil

        await soundEngine.crossfade(to: deferredStartupMix, duration: 0.15)
        settingsEngine.updateLastUsedMood(deferredStartupMoodID)
        state = .idle
    }

    private func applyMood(_ mood: Mood, strategy: ApplyStrategy) async {
        print("🟢 [MoodEngine] Applying mood: \(mood.name) (ID: \(mood.id))")
        currentMood = mood

        transitionTask?.cancel()

        transitionTask = Task {
            state = .transitioning
            if strategy == .standard {
                deferredStartupMix = nil
                deferredStartupMoodID = nil
            }

            if mood.wallpaper.type == .animated {
            // We no longer pre-download the first video
        }

            let settings = settingsEngine.loadSettings()
            let duration = settings.transitionDuration

            themeManager.updatePalette(mood.palette)

            let wallpaperDescriptor = settings.keepCurrentWallpaper ? WallpaperDescriptor(type: .current) : mood.wallpaper
            switch strategy {
            case .standard:
                async let audioTransition: () = soundEngine.crossfade(to: mood.layerMix, duration: duration)
                async let wallpaperTransition = wallpaperEngine.applyWallpaper(wallpaperDescriptor)

                _ = await (audioTransition, wallpaperTransition)

                if !Task.isCancelled {
                    settingsEngine.updateLastUsedMood(mood.id)
                    state = .idle
                }
            case .deferredStartup:
                deferredStartupMix = mood.layerMix
                deferredStartupMoodID = mood.id
                _ = await wallpaperEngine.applyWallpaper(wallpaperDescriptor)

                if !Task.isCancelled {
                    state = .idle
                }
            case .wallpaperOnly:
                _ = await wallpaperEngine.applyWallpaper(wallpaperDescriptor)

                if !Task.isCancelled {
                    settingsEngine.updateLastUsedMood(mood.id)
                    state = .idle
                }
            }
        }

        await transitionTask?.value
    }

    func playCustomAudio(url: URL) async {
        print("🟢 [MoodEngine] Requesting custom audio at \(url.path)")

        // Cancel any existing mood transition
        transitionTask?.cancel()

        transitionTask = Task {
            state = .transitioning
            do {
                try await soundEngine.playCustomAudio(url: url)
                if !Task.isCancelled {
                    state = .idle
                }
            } catch {
                if !Task.isCancelled {
                    state = .error
                    lastError = error.localizedDescription
                    print("🟥 [MoodEngine] Failed to play custom audio: \(error)")
                }
            }
        }

        await transitionTask?.value
    }

    func mood(for id: String) -> Mood? {
        moods.first { $0.id == id }
    }

    static func builtInMoods() -> [Mood] {
        [
            Mood(
                id: "mountain_stream",
                name: "Mountain Stream",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "crystal_cascade",
                name: "Crystal Cascade",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "serene_falls",
                name: "Serene Falls",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "hidden_oasis",
                name: "Hidden Oasis",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "eternal_spring",
                name: "Eternal Spring",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "misty_basin",
                name: "Misty Basin",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_6.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "emerald_falls",
                name: "Emerald Falls",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_7.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "silver_veil",
                name: "Silver Veil",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_8.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "azure_descent",
                name: "Azure Descent",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_9.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "moonlit_current",
                name: "Moonlit Current",
                theme: "Nature",
                subtheme: "Waterfall",
                layerMix: ["rain": 0.3, "forest": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Waterfall_10.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.36, blue: 0.55), secondary: ColorComponents(red: 0.45, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.7, green: 0.65, blue: 0.85))
            ),
            Mood(
                id: "deep_blue",
                name: "Deep Blue",
                theme: "Work",
                subtheme: "DeepFocus",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["DeepFocus_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.1, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.2, blue: 0.24), accent: ColorComponents(red: 0.5, green: 0.55, blue: 0.6))
            ),
            Mood(
                id: "oceanic_flow",
                name: "Oceanic Flow",
                theme: "Work",
                subtheme: "DeepFocus",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["DeepFocus_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.1, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.2, blue: 0.24), accent: ColorComponents(red: 0.5, green: 0.55, blue: 0.6))
            ),
            Mood(
                id: "midnight_echo",
                name: "Midnight Echo",
                theme: "Work",
                subtheme: "DeepFocus",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["DeepFocus_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.1, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.2, blue: 0.24), accent: ColorComponents(red: 0.5, green: 0.55, blue: 0.6))
            ),
            Mood(
                id: "quiet_harbor",
                name: "Quiet Harbor",
                theme: "Work",
                subtheme: "DeepFocus",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["DeepFocus_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.1, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.2, blue: 0.24), accent: ColorComponents(red: 0.5, green: 0.55, blue: 0.6))
            ),
            Mood(
                id: "infinite_calm",
                name: "Infinite Calm",
                theme: "Work",
                subtheme: "DeepFocus",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["DeepFocus_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.1, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.2, blue: 0.24), accent: ColorComponents(red: 0.5, green: 0.55, blue: 0.6))
            ),
            Mood(
                id: "minimalist",
                name: "Minimalist",
                theme: "Work",
                subtheme: "Concentration",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Concentration_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.14, green: 0.14, blue: 0.14), secondary: ColorComponents(red: 0.25, green: 0.23, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.65, blue: 0.3))
            ),
            Mood(
                id: "steel_focus",
                name: "Steel Focus",
                theme: "Work",
                subtheme: "Concentration",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Concentration_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.14, green: 0.14, blue: 0.14), secondary: ColorComponents(red: 0.25, green: 0.23, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.65, blue: 0.3))
            ),
            Mood(
                id: "inner_sanctum",
                name: "Inner Sanctum",
                theme: "Work",
                subtheme: "Concentration",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Concentration_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.14, green: 0.14, blue: 0.14), secondary: ColorComponents(red: 0.25, green: 0.23, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.65, blue: 0.3))
            ),
            Mood(
                id: "golden_hour",
                name: "Golden Hour",
                theme: "Work",
                subtheme: "Concentration",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Concentration_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.14, green: 0.14, blue: 0.14), secondary: ColorComponents(red: 0.25, green: 0.23, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.65, blue: 0.3))
            ),
            Mood(
                id: "prime_time",
                name: "Prime Time",
                theme: "Work",
                subtheme: "Concentration",
                layerMix: ["rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Concentration_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.14, green: 0.14, blue: 0.14), secondary: ColorComponents(red: 0.25, green: 0.23, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.65, blue: 0.3))
            ),
            Mood(
                id: "morning_brew",
                name: "Morning Brew",
                theme: "Work",
                subtheme: "CoffeeShop",
                layerMix: ["cafe": 0.6, "rain": 0.2, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["CoffeeShop_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.25, blue: 0.15), secondary: ColorComponents(red: 0.6, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.6))
            ),
            Mood(
                id: "urban_roast",
                name: "Urban Roast",
                theme: "Work",
                subtheme: "CoffeeShop",
                layerMix: ["cafe": 0.6, "rain": 0.2, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["CoffeeShop_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.25, blue: 0.15), secondary: ColorComponents(red: 0.6, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.6))
            ),
            Mood(
                id: "cosy_nook",
                name: "Cosy Nook",
                theme: "Work",
                subtheme: "CoffeeShop",
                layerMix: ["cafe": 0.6, "rain": 0.2, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["CoffeeShop_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.25, blue: 0.15), secondary: ColorComponents(red: 0.6, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.6))
            ),
            Mood(
                id: "barista_vibes",
                name: "Barista Vibes",
                theme: "Work",
                subtheme: "CoffeeShop",
                layerMix: ["cafe": 0.6, "rain": 0.2, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["CoffeeShop_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.25, blue: 0.15), secondary: ColorComponents(red: 0.6, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.6))
            ),
            Mood(
                id: "rainy_bistro",
                name: "Rainy Bistro",
                theme: "Work",
                subtheme: "CoffeeShop",
                layerMix: ["cafe": 0.6, "rain": 0.2, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["CoffeeShop_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.25, blue: 0.15), secondary: ColorComponents(red: 0.6, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.6))
            ),
            Mood(
                id: "vitality",
                name: "Vitality",
                theme: "Wellness",
                subtheme: "Flow",
                layerMix: ["brownnoise": 0.5, "piano": 0.5],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Flow_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.6, blue: 0.3), accent: ColorComponents(red: 1.0, green: 0.9, blue: 0.5))
            ),
            Mood(
                id: "solar_flare",
                name: "Solar Flare",
                theme: "Wellness",
                subtheme: "Flow",
                layerMix: ["brownnoise": 0.5, "piano": 0.5],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Flow_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.6, blue: 0.3), accent: ColorComponents(red: 1.0, green: 0.9, blue: 0.5))
            ),
            Mood(
                id: "pulse",
                name: "Pulse",
                theme: "Wellness",
                subtheme: "Flow",
                layerMix: ["brownnoise": 0.5, "piano": 0.5],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Flow_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.6, blue: 0.3), accent: ColorComponents(red: 1.0, green: 0.9, blue: 0.5))
            ),
            Mood(
                id: "radiance",
                name: "Radiance",
                theme: "Wellness",
                subtheme: "Flow",
                layerMix: ["brownnoise": 0.5, "piano": 0.5],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Flow_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.6, blue: 0.3), accent: ColorComponents(red: 1.0, green: 0.9, blue: 0.5))
            ),
            Mood(
                id: "zenith",
                name: "Zenith",
                theme: "Wellness",
                subtheme: "Flow",
                layerMix: ["brownnoise": 0.5, "piano": 0.5],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Flow_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.6, blue: 0.3), accent: ColorComponents(red: 1.0, green: 0.9, blue: 0.5))
            ),
            Mood(
                id: "energy_ignition",
                name: "Ignition",
                theme: "Wellness",
                subtheme: "Energy",
                layerMix: ["hum": 0.45, "brownnoise": 0.3, "fire": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Energy_1.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.08, blue: 0.1), secondary: ColorComponents(red: 0.28, green: 0.12, blue: 0.08), accent: ColorComponents(red: 0.98, green: 0.62, blue: 0.18))
            ),
            Mood(
                id: "energy_spark_surge",
                name: "Spark Surge",
                theme: "Wellness",
                subtheme: "Energy",
                layerMix: ["hum": 0.4, "brownnoise": 0.25, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Energy_2.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.06, green: 0.07, blue: 0.1), secondary: ColorComponents(red: 0.22, green: 0.14, blue: 0.1), accent: ColorComponents(red: 0.94, green: 0.5, blue: 0.14))
            ),
            Mood(
                id: "energy_core_pulse",
                name: "Core Pulse",
                theme: "Wellness",
                subtheme: "Energy",
                layerMix: ["hum": 0.35, "brownnoise": 0.35, "piano": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Energy_3.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.09, blue: 0.12), secondary: ColorComponents(red: 0.26, green: 0.16, blue: 0.1), accent: ColorComponents(red: 1.0, green: 0.72, blue: 0.22))
            ),
            Mood(
                id: "energy_voltage_bloom",
                name: "Voltage Bloom",
                theme: "Wellness",
                subtheme: "Energy",
                layerMix: ["hum": 0.4, "fire": 0.2, "wind": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Energy_4.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.07, green: 0.07, blue: 0.09), secondary: ColorComponents(red: 0.24, green: 0.1, blue: 0.08), accent: ColorComponents(red: 1.0, green: 0.56, blue: 0.1))
            ),
            Mood(
                id: "energy_solar_charge",
                name: "Solar Charge",
                theme: "Wellness",
                subtheme: "Energy",
                layerMix: ["hum": 0.45, "brownnoise": 0.2, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Energy_5.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.08, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.12, blue: 0.08), accent: ColorComponents(red: 1.0, green: 0.66, blue: 0.16))
            ),
            Mood(
                id: "quiet_mind",
                name: "Quiet Mind",
                theme: "Wellness",
                subtheme: "Mindfulness",
                layerMix: ["forest": 0.5, "piano": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mindfulness_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.5, blue: 0.35), secondary: ColorComponents(red: 0.55, green: 0.6, blue: 0.45), accent: ColorComponents(red: 0.85, green: 0.8, blue: 0.65))
            ),
            Mood(
                id: "inner_peace",
                name: "Inner Peace",
                theme: "Wellness",
                subtheme: "Mindfulness",
                layerMix: ["forest": 0.5, "piano": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mindfulness2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.5, blue: 0.35), secondary: ColorComponents(red: 0.55, green: 0.6, blue: 0.45), accent: ColorComponents(red: 0.85, green: 0.8, blue: 0.65))
            ),
            Mood(
                id: "ethereal_breath",
                name: "Ethereal Breath",
                theme: "Wellness",
                subtheme: "Mindfulness",
                layerMix: ["forest": 0.5, "piano": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mindfulness3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.5, blue: 0.35), secondary: ColorComponents(red: 0.55, green: 0.6, blue: 0.45), accent: ColorComponents(red: 0.85, green: 0.8, blue: 0.65))
            ),
            Mood(
                id: "spirit_forest",
                name: "Spirit Forest",
                theme: "Wellness",
                subtheme: "Mindfulness",
                layerMix: ["forest": 0.5, "piano": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mindfulness_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.5, blue: 0.35), secondary: ColorComponents(red: 0.55, green: 0.6, blue: 0.45), accent: ColorComponents(red: 0.85, green: 0.8, blue: 0.65))
            ),
            Mood(
                id: "stillness",
                name: "Stillness",
                theme: "Wellness",
                subtheme: "Mindfulness",
                layerMix: ["forest": 0.5, "piano": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mindfulness_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.5, blue: 0.35), secondary: ColorComponents(red: 0.55, green: 0.6, blue: 0.45), accent: ColorComponents(red: 0.85, green: 0.8, blue: 0.65))
            ),
            Mood(
                id: "midnight_rain",
                name: "Midnight Rain",
                theme: "Wellness",
                subtheme: "Rest",
                layerMix: ["rain": 0.7, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rest_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.06, blue: 0.12), secondary: ColorComponents(red: 0.08, green: 0.09, blue: 0.16), accent: ColorComponents(red: 0.2, green: 0.3, blue: 0.5))
            ),
            Mood(
                id: "hearth_glow",
                name: "Hearth Glow",
                theme: "Wellness",
                subtheme: "Rest",
                layerMix: ["rain": 0.7, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rest_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.06, blue: 0.12), secondary: ColorComponents(red: 0.08, green: 0.09, blue: 0.16), accent: ColorComponents(red: 0.2, green: 0.3, blue: 0.5))
            ),
            Mood(
                id: "deep_slumber",
                name: "Deep Slumber",
                theme: "Wellness",
                subtheme: "Rest",
                layerMix: ["rain": 0.7, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rest_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.06, blue: 0.12), secondary: ColorComponents(red: 0.08, green: 0.09, blue: 0.16), accent: ColorComponents(red: 0.2, green: 0.3, blue: 0.5))
            ),
            Mood(
                id: "nightfall",
                name: "Nightfall",
                theme: "Wellness",
                subtheme: "Rest",
                layerMix: ["rain": 0.7, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rest_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.06, blue: 0.12), secondary: ColorComponents(red: 0.08, green: 0.09, blue: 0.16), accent: ColorComponents(red: 0.2, green: 0.3, blue: 0.5))
            ),
            Mood(
                id: "velvet_dreams",
                name: "Velvet Dreams",
                theme: "Wellness",
                subtheme: "Rest",
                layerMix: ["rain": 0.7, "fire": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rest_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.06, blue: 0.12), secondary: ColorComponents(red: 0.08, green: 0.09, blue: 0.16), accent: ColorComponents(red: 0.2, green: 0.3, blue: 0.5))
            ),
            Mood(
                id: "radiant_aura",
                name: "Radiant Aura",
                theme: "Cosmos",
                subtheme: "Aura",
                layerMix: ["night": 0.5, "wind": 0.25, "piano": 0.2, "hum": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Aura_1.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.15, blue: 0.22), secondary: ColorComponents(red: 0.12, green: 0.25, blue: 0.32), accent: ColorComponents(red: 0.35, green: 0.75, blue: 0.55))
            ),
            Mood(
                id: "ethereal_aura",
                name: "Ethereal Aura",
                theme: "Cosmos",
                subtheme: "Aura",
                layerMix: ["night": 0.5, "wind": 0.25, "piano": 0.2, "hum": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Aura_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.15, blue: 0.22), secondary: ColorComponents(red: 0.12, green: 0.25, blue: 0.32), accent: ColorComponents(red: 0.35, green: 0.75, blue: 0.55))
            ),
            Mood(
                id: "luminous_aura",
                name: "Luminous Aura",
                theme: "Cosmos",
                subtheme: "Aura",
                layerMix: ["night": 0.5, "wind": 0.25, "piano": 0.2, "hum": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Aura_3.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.15, blue: 0.22), secondary: ColorComponents(red: 0.12, green: 0.25, blue: 0.32), accent: ColorComponents(red: 0.35, green: 0.75, blue: 0.55))
            ),
            Mood(
                id: "mystic_aura",
                name: "Mystic Aura",
                theme: "Cosmos",
                subtheme: "Aura",
                layerMix: ["night": 0.5, "wind": 0.25, "piano": 0.2, "hum": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Aura_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.15, blue: 0.22), secondary: ColorComponents(red: 0.12, green: 0.25, blue: 0.32), accent: ColorComponents(red: 0.35, green: 0.75, blue: 0.55))
            ),
            Mood(
                id: "serene_aura",
                name: "Serene Aura",
                theme: "Cosmos",
                subtheme: "Aura",
                layerMix: ["night": 0.5, "wind": 0.25, "piano": 0.2, "hum": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Aura_5.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.15, blue: 0.22), secondary: ColorComponents(red: 0.12, green: 0.25, blue: 0.32), accent: ColorComponents(red: 0.35, green: 0.75, blue: 0.55))
            ),
            Mood(
                id: "ancient_pines",
                name: "Ancient Pines",
                theme: "Nature",
                subtheme: "Forest",
                layerMix: ["forest": 0.5, "rain": 0.35, "stream": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Forest_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.12, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.22, green: 0.35, blue: 0.3), accent: ColorComponents(red: 0.55, green: 0.7, blue: 0.6))
            ),
            Mood(
                id: "foggy_valley",
                name: "Foggy Valley",
                theme: "Nature",
                subtheme: "Forest",
                layerMix: ["forest": 0.5, "rain": 0.35, "stream": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Forest_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.12, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.22, green: 0.35, blue: 0.3), accent: ColorComponents(red: 0.55, green: 0.7, blue: 0.6))
            ),
            Mood(
                id: "mossy_trail",
                name: "Mossy Trail",
                theme: "Nature",
                subtheme: "Forest",
                layerMix: ["forest": 0.5, "rain": 0.35, "stream": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Forest_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.12, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.22, green: 0.35, blue: 0.3), accent: ColorComponents(red: 0.55, green: 0.7, blue: 0.6))
            ),
            Mood(
                id: "emerald_shade",
                name: "Emerald Shade",
                theme: "Nature",
                subtheme: "Forest",
                layerMix: ["forest": 0.5, "rain": 0.35, "stream": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Forest_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.12, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.22, green: 0.35, blue: 0.3), accent: ColorComponents(red: 0.55, green: 0.7, blue: 0.6))
            ),
            Mood(
                id: "whispering_leaves",
                name: "Whispering Leaves",
                theme: "Nature",
                subtheme: "Forest",
                layerMix: ["forest": 0.5, "rain": 0.35, "stream": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Forest_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.12, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.22, green: 0.35, blue: 0.3), accent: ColorComponents(red: 0.55, green: 0.7, blue: 0.6))
            ),
            Mood(
                id: "red_sands",
                name: "Red Sands",
                theme: "Nature",
                subtheme: "Desert",
                layerMix: ["wind": 0.5, "hum": 0.25, "night": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Desert_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.25, blue: 0.18), secondary: ColorComponents(red: 0.55, green: 0.42, blue: 0.28), accent: ColorComponents(red: 0.85, green: 0.6, blue: 0.35))
            ),
            Mood(
                id: "dune_silence",
                name: "Dune Silence",
                theme: "Nature",
                subtheme: "Desert",
                layerMix: ["wind": 0.5, "hum": 0.25, "night": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Desert_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.25, blue: 0.18), secondary: ColorComponents(red: 0.55, green: 0.42, blue: 0.28), accent: ColorComponents(red: 0.85, green: 0.6, blue: 0.35))
            ),
            Mood(
                id: "golden_oasis",
                name: "Golden Oasis",
                theme: "Nature",
                subtheme: "Desert",
                layerMix: ["wind": 0.5, "hum": 0.25, "night": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Desert_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.25, blue: 0.18), secondary: ColorComponents(red: 0.55, green: 0.42, blue: 0.28), accent: ColorComponents(red: 0.85, green: 0.6, blue: 0.35))
            ),
            Mood(
                id: "twilight_mirage",
                name: "Twilight Mirage",
                theme: "Nature",
                subtheme: "Desert",
                layerMix: ["wind": 0.5, "hum": 0.25, "night": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Desert_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.25, blue: 0.18), secondary: ColorComponents(red: 0.55, green: 0.42, blue: 0.28), accent: ColorComponents(red: 0.85, green: 0.6, blue: 0.35))
            ),
            Mood(
                id: "nomad_skies",
                name: "Nomad Skies",
                theme: "Nature",
                subtheme: "Desert",
                layerMix: ["wind": 0.5, "hum": 0.25, "night": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Desert_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.35, green: 0.25, blue: 0.18), secondary: ColorComponents(red: 0.55, green: 0.42, blue: 0.28), accent: ColorComponents(red: 0.85, green: 0.6, blue: 0.35))
            ),
            Mood(
                id: "wild_horizon",
                name: "Wild Horizon",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "stream": 0.4, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "valley_breeze",
                name: "Valley Breeze",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "stream": 0.4, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "canyon_path",
                name: "Canyon Path",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "stream": 0.4, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "untamed_peaks",
                name: "Untamed Peaks",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "stream": 0.4, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "primal_echo",
                name: "Primal Echo",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "stream": 0.4, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "herbal_flow",
                name: "Herbal Flow",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_6.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "flower_flow",
                name: "Flower Flow",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_7.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "yellow_flower",
                name: "Yellow Flower",
                theme: "Nature",
                subtheme: "Wild",
                layerMix: ["forest": 0.6, "wind": 0.3, "crickets": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Wild_8.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.3), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "summer_storm",
                name: "Summer Storm",
                theme: "Nature",
                subtheme: "Storm",
                layerMix: ["rain": 0.6, "thunder": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Storm_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.5, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "thunderous",
                name: "Thunderous",
                theme: "Nature",
                subtheme: "Storm",
                layerMix: ["rain": 0.6, "thunder": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Storm_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.5, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "grey_skies",
                name: "Grey Skies",
                theme: "Nature",
                subtheme: "Storm",
                layerMix: ["rain": 0.6, "thunder": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Storm_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.5, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "heavy_pour",
                name: "Heavy Pour",
                theme: "Nature",
                subtheme: "Storm",
                layerMix: ["rain": 0.6, "thunder": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Storm_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.5, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "electric_sky",
                name: "Electric Sky",
                theme: "Nature",
                subtheme: "Storm",
                layerMix: ["rain": 0.6, "thunder": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Storm_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.5, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "rain_monsoon_village",
                name: "Monsoon Village",
                theme: "Nature",
                subtheme: "Rain",
                layerMix: ["rain": 0.65, "wind": 0.2, "stream": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rain_1.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.18, green: 0.2, blue: 0.18), secondary: ColorComponents(red: 0.3, green: 0.34, blue: 0.28), accent: ColorComponents(red: 0.64, green: 0.72, blue: 0.58))
            ),
            Mood(
                id: "rain_rainforest_shelter",
                name: "Rainforest Shelter",
                theme: "Nature",
                subtheme: "Rain",
                layerMix: ["rain": 0.7, "forest": 0.25, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rain_2.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.16, green: 0.18, blue: 0.12), secondary: ColorComponents(red: 0.28, green: 0.32, blue: 0.18), accent: ColorComponents(red: 0.76, green: 0.62, blue: 0.26))
            ),
            Mood(
                id: "rain_lakeside_ember",
                name: "Lakeside Ember",
                theme: "Nature",
                subtheme: "Rain",
                layerMix: ["rain": 0.55, "fire": 0.25, "wind": 0.15],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rain_3.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.14, blue: 0.16), secondary: ColorComponents(red: 0.2, green: 0.24, blue: 0.26), accent: ColorComponents(red: 0.95, green: 0.58, blue: 0.28))
            ),
            Mood(
                id: "rain_emerald_downpour",
                name: "Emerald Downpour",
                theme: "Nature",
                subtheme: "Rain",
                layerMix: ["rain": 0.68, "forest": 0.22, "stream": 0.12],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rain_4.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.08, green: 0.16, blue: 0.12), secondary: ColorComponents(red: 0.18, green: 0.28, blue: 0.22), accent: ColorComponents(red: 0.5, green: 0.74, blue: 0.58))
            ),
            Mood(
                id: "rain_quiet_drizzle",
                name: "Quiet Drizzle",
                theme: "Nature",
                subtheme: "Rain",
                layerMix: ["rain": 0.58, "wind": 0.18, "forest": 0.12],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Rain_5.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.18, blue: 0.14), secondary: ColorComponents(red: 0.18, green: 0.3, blue: 0.24), accent: ColorComponents(red: 0.62, green: 0.82, blue: 0.72))
            ),
            Mood(
                id: "amber_forest",
                name: "Amber Forest",
                theme: "Nature",
                subtheme: "Autumn",
                layerMix: ["wind": 0.4, "forest": 0.3, "rain": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Autumn_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.6, green: 0.2, blue: 0.1), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "rustic_trail",
                name: "Rustic Trail",
                theme: "Nature",
                subtheme: "Autumn",
                layerMix: ["wind": 0.4, "forest": 0.3, "rain": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Autumn_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.6, green: 0.2, blue: 0.1), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "harvest_glow",
                name: "Harvest Glow",
                theme: "Nature",
                subtheme: "Autumn",
                layerMix: ["wind": 0.4, "forest": 0.3, "rain": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Autumn_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.6, green: 0.2, blue: 0.1), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "crisp_morning",
                name: "Crisp Morning",
                theme: "Nature",
                subtheme: "Autumn",
                layerMix: ["wind": 0.4, "forest": 0.3, "rain": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Autumn_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.6, green: 0.2, blue: 0.1), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "crimson_lake",
                name: "Crimson Lake",
                theme: "Nature",
                subtheme: "Autumn",
                layerMix: ["wind": 0.4, "forest": 0.3, "rain": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Autumn_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.6, green: 0.2, blue: 0.1), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.4))
            ),
            // Fractal Submoods
            Mood(
                id: "infinite_echo",
                name: "Infinite Echo",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Fractal_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "geometric_pulse",
                name: "Geometric Pulse",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Fractal_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "quantum_loop",
                name: "Quantum Loop",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Fractal_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "crystal_mirage",
                name: "Crystal Mirage",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Fractal_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "cosmic_weave",
                name: "Cosmic Weave",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Fractal_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "pink_colorfull",
                name: "Pink Colorful",
                theme: "Art",
                subtheme: "Fractal",
                layerMix: ["hum": 0.3, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Pink_Colorfull.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            // Color Submoods
            Mood(
                id: "crimson_flow",
                name: "Crimson Flow",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_1.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.5, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.4, blue: 0.4))
            ),
            Mood(
                id: "emerald_stream",
                name: "Emerald Stream",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_2.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.3, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.5, blue: 0.2), accent: ColorComponents(red: 0.4, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "sapphire_tides",
                name: "Sapphire Tides",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_3.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "golden_aura",
                name: "Golden Aura",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_4.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.3, blue: 0.1), secondary: ColorComponents(red: 0.5, green: 0.5, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "amethyst_drift",
                name: "Amethyst Drift",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_5.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.1, blue: 0.2), secondary: ColorComponents(red: 0.4, green: 0.2, blue: 0.4), accent: ColorComponents(red: 0.7, green: 0.4, blue: 0.7))
            ),
            Mood(
                id: "prismatic_dawn",
                name: "Prismatic Dawn",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_6.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.28, green: 0.12, blue: 0.22), secondary: ColorComponents(red: 0.48, green: 0.24, blue: 0.42), accent: ColorComponents(red: 0.86, green: 0.46, blue: 0.74))
            ),
            Mood(
                id: "violet_spectrum",
                name: "Violet Spectrum",
                theme: "Art",
                subtheme: "Color",
                layerMix: ["piano": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Color_7.mp4"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.16, green: 0.12, blue: 0.3), secondary: ColorComponents(red: 0.28, green: 0.22, blue: 0.5), accent: ColorComponents(red: 0.56, green: 0.46, blue: 0.88))
            ),
            // Time Subthemes
            Mood(
                id: "time_minimal",
                name: "Minimalist Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["hum": 0.2, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["minimal"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.05, blue: 0.08), secondary: ColorComponents(red: 0.1, green: 0.1, blue: 0.15), accent: ColorComponents(red: 0.9, green: 0.9, blue: 0.95))
            ),
            Mood(
                id: "time_analog",
                name: "Analog Clock",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["hum": 0.1, "night": 0.2],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["analog"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.15, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.3), accent: ColorComponents(red: 0.8, green: 0.4, blue: 0.3))
            ),
            Mood(
                id: "time_typographic",
                name: "Typographic Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["piano": 0.3, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["typographic"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.15, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.3, green: 0.15, blue: 0.15), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.7))
            ),
            Mood(
                id: "time_binary",
                name: "Binary Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["hum": 0.4, "piano": 0.1],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["binary"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.02, green: 0.05, blue: 0.02), secondary: ColorComponents(red: 0.05, green: 0.1, blue: 0.05), accent: ColorComponents(red: 0.2, green: 0.9, blue: 0.4))
            ),
            Mood(
                id: "time_solar",
                name: "Solar Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["wind": 0.3, "forest": 0.2],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["solar"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.2, blue: 0.4), secondary: ColorComponents(red: 0.3, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.9, green: 0.8, blue: 0.5))
            ),
            Mood(
                id: "time_glass_blocks",
                name: "Glass Blocks",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["hum": 0.2, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["glass_blocks"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.8, blue: 0.9), secondary: ColorComponents(red: 0.5, green: 0.5, blue: 0.6), accent: ColorComponents(red: 0.2, green: 0.5, blue: 0.9))
            ),
            Mood(
                id: "time_words",
                name: "Prose Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["piano": 0.2, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["words"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.9, green: 0.9, blue: 0.9))
            ),
            Mood(
                id: "time_orbit",
                name: "Orbit Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["hum": 0.4, "night": 0.3],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["orbit"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.05, blue: 0.1), secondary: ColorComponents(red: 0.1, green: 0.1, blue: 0.2), accent: ColorComponents(red: 0.6, green: 0.8, blue: 1.0))
            ),
            Mood(
                id: "time_neon",
                name: "Neon Glow",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["wind": 0.2, "piano": 0.3],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["neon"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.0, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.0, blue: 0.2), accent: ColorComponents(red: 1.0, green: 0.2, blue: 0.8))
            ),
            Mood(
                id: "time_fluid",
                name: "Fluid Time",
                theme: "Dynamic",
                subtheme: "Time",
                layerMix: ["stream": 0.4, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .time, resources: ["fluid"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.4, blue: 0.6), secondary: ColorComponents(red: 0.2, green: 0.5, blue: 0.8), accent: ColorComponents(red: 0.4, green: 0.8, blue: 1.0))
            ),
            // Zen Subthemes
            Mood(
                id: "zen_breathing",
                name: "Breathing",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["wind": 0.2, "hum": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["breathing"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.2, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.3, blue: 0.4), accent: ColorComponents(red: 0.5, green: 0.8, blue: 0.9))
            ),
            Mood(
                id: "zen_mandala",
                name: "Mandala",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["piano": 0.2, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["mandala"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.3, green: 0.1, blue: 0.2), secondary: ColorComponents(red: 0.4, green: 0.2, blue: 0.3), accent: ColorComponents(red: 0.9, green: 0.5, blue: 0.7))
            ),
            Mood(
                id: "zen_ripple",
                name: "Ripple",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["stream": 0.3, "rain": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["ripple"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.3, blue: 0.3), secondary: ColorComponents(red: 0.2, green: 0.4, blue: 0.4), accent: ColorComponents(red: 0.4, green: 0.9, blue: 0.8))
            ),
            Mood(
                id: "zen_orb",
                name: "Energy Orb",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["hum": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["orb"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.8, green: 0.3, blue: 0.1), secondary: ColorComponents(red: 0.9, green: 0.5, blue: 0.2), accent: ColorComponents(red: 1.0, green: 0.8, blue: 0.4))
            ),
            Mood(
                id: "zen_lotus",
                name: "Lotus Flower",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["stream": 0.2, "piano": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["lotus"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.9, green: 0.4, blue: 0.6), secondary: ColorComponents(red: 0.8, green: 0.3, blue: 0.5), accent: ColorComponents(red: 1.0, green: 0.7, blue: 0.8))
            ),
            Mood(
                id: "zen_waves",
                name: "Ocean Waves",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["rain": 0.3, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["waves"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.4, blue: 0.7), secondary: ColorComponents(red: 0.2, green: 0.5, blue: 0.8), accent: ColorComponents(red: 0.6, green: 0.8, blue: 0.9))
            ),
            Mood(
                id: "zen_eclipse",
                name: "Solar Eclipse",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["night": 0.4, "hum": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["eclipse"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.9, green: 0.9, blue: 0.7))
            ),
            Mood(
                id: "zen_particles",
                name: "Stardust",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["wind": 0.3, "piano": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["particles"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.1, blue: 0.4), secondary: ColorComponents(red: 0.3, green: 0.2, blue: 0.5), accent: ColorComponents(red: 0.8, green: 0.6, blue: 0.9))
            ),
            Mood(
                id: "zen_galaxy",
                name: "Galaxy",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["brownnoise": 0.4, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["galaxy"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.0, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.0, blue: 0.5), accent: ColorComponents(red: 0.6, green: 0.2, blue: 0.8))
            ),
            Mood(
                id: "zen_pendulum",
                name: "Pendulum",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["hum": 0.3, "stream": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["pendulum"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.4, green: 0.4, blue: 0.4), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.7, blue: 0.3))
            ),
            Mood(
                id: "zen_infinity",
                name: "Infinity",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["ocean": 0.4, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["infinity"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.5, blue: 0.4), secondary: ColorComponents(red: 0.0, green: 0.3, blue: 0.2), accent: ColorComponents(red: 0.4, green: 0.9, blue: 0.6))
            ),
            Mood(
                id: "zen_prism",
                name: "Prism",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["brownnoise": 0.2, "fire": 0.1],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["prism"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.7, green: 0.1, blue: 0.2), secondary: ColorComponents(red: 0.9, green: 0.4, blue: 0.1), accent: ColorComponents(red: 1.0, green: 0.8, blue: 0.2))
            ),
            Mood(
                id: "zen_stardust",
                name: "Stardust",
                theme: "Dynamic",
                subtheme: "Zen",
                layerMix: ["wind": 0.5, "hum": 0.2],
                wallpaper: WallpaperDescriptor(type: .zen, resources: ["stardust"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.3), secondary: ColorComponents(red: 0.3, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.9, green: 0.9, blue: 1.0))
            ),
            // Quote Subthemes
            Mood(
                id: "quote_motivational",
                name: "Motivational Quote",
                theme: "Dynamic",
                subtheme: "Quotes",
                layerMix: ["hum": 0.1, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .quote, resources: ["motivational"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.15), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.25), accent: ColorComponents(red: 0.9, green: 0.7, blue: 0.3))
            ),
            Mood(
                id: "quote_philosophical",
                name: "Philosophical Quote",
                theme: "Dynamic",
                subtheme: "Quotes",
                layerMix: ["piano": 0.3, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .quote, resources: ["philosophical"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.15, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.3, green: 0.15, blue: 0.15), accent: ColorComponents(red: 0.8, green: 0.4, blue: 0.3))
            ),
            Mood(
                id: "quote_minimal",
                name: "Minimal Quote",
                theme: "Dynamic",
                subtheme: "Quotes",
                layerMix: ["hum": 0.2, "night": 0.1],
                wallpaper: WallpaperDescriptor(type: .quote, resources: ["minimal"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.05, blue: 0.08), secondary: ColorComponents(red: 0.1, green: 0.1, blue: 0.15), accent: ColorComponents(red: 0.9, green: 0.9, blue: 0.95))
            ),
            Mood(
                id: "quote_bold",
                name: "Bold Quote",
                theme: "Dynamic",
                subtheme: "Quotes",
                layerMix: ["wind": 0.4, "piano": 0.1],
                wallpaper: WallpaperDescriptor(type: .quote, resources: ["bold"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.0, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.0, blue: 0.2), accent: ColorComponents(red: 1.0, green: 0.2, blue: 0.8))
            ),
            // MARK: - Website
            Mood(
                id: "website_custom",
                name: "Custom Website",
                theme: "Dynamic",
                subtheme: "Website",
                layerMix: ["hum": 0.1],
                wallpaper: WallpaperDescriptor(type: .website, resources: ["https://example.com"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.15), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.25), accent: ColorComponents(red: 0.4, green: 0.6, blue: 0.9))
            ),
            // MARK: - Retro
            Mood(
                id: "retro_donkey_kong",
                name: "Donkey Kong",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["piano": 0.4, "vinyl": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Donkey_Kong.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.2, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.4, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.3, blue: 0.3))
            ),
            Mood(
                id: "retro_mario_pixel_room",
                name: "Mario Pixel Room",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["piano": 0.3, "rain": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Mario_Pixel_Room.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.4), accent: ColorComponents(red: 0.4, green: 0.4, blue: 0.8))
            ),
            Mood(
                id: "retro_pixel_cosmic",
                name: "Pixel Cosmic",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["wind": 0.4, "vinyl": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Pixel_Cosmic.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.05, blue: 0.15), secondary: ColorComponents(red: 0.2, green: 0.1, blue: 0.3), accent: ColorComponents(red: 0.5, green: 0.2, blue: 0.6))
            ),
            Mood(
                id: "retro_pixel_cyberpunk_city",
                name: "Pixel Cyberpunk City",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["rain": 0.5, "wind": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Pixel_Cyberpunk_City.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.05, green: 0.05, blue: 0.1), secondary: ColorComponents(red: 0.1, green: 0.1, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.2, blue: 0.5))
            ),
            Mood(
                id: "retro_pixel_gaming_room",
                name: "Pixel Gaming Room",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["piano": 0.2, "rain": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Pixel_Gaming_Room.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.4, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "retro_sailor_moon",
                name: "Sailor Moon",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["piano": 0.5, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Sailor_Moon.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.15, green: 0.1, blue: 0.2), secondary: ColorComponents(red: 0.3, green: 0.2, blue: 0.4), accent: ColorComponents(red: 0.8, green: 0.6, blue: 0.8))
            ),
            Mood(
                id: "retro_zelda_pixel_art",
                name: "Zelda Pixel Art",
                theme: "Art",
                subtheme: "Retro",
                layerMix: ["forest": 0.4, "stream": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Zelda_Pixel_Art.mov"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.2, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.3, blue: 0.2), accent: ColorComponents(red: 0.4, green: 0.6, blue: 0.4))
            ),
            // MARK: - Website
            Mood(
                id: "website_apple",
                name: "Apple",
                theme: "Dynamic",
                subtheme: "Website",
                layerMix: ["hum": 0.1, "wind": 0.1],
                wallpaper: WallpaperDescriptor(type: .website, resources: ["https://www.apple.com"]),
                palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.8, green: 0.8, blue: 0.8))
            )
        ]
    }
}
