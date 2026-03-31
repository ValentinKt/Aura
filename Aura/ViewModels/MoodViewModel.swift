import Foundation
import Observation

struct MoodSubthemeSection: Identifiable, Hashable {
    let title: String
    let subthemes: [String]

    var id: String { title }
}

@MainActor
@Observable
final class MoodViewModel {
    private let moodEngine: MoodEngine
    private let playerViewModel: PlayerViewModel
    private let quoteEngine: QuoteEngine
    private var quoteRefreshToken = 0
    private static let dynamicSubthemes: Set<String> = ["Dynamic Desktop", "Image Playground", "Quotes", "Time", "Zen"]
    private static let miscellaneousSubthemes: Set<String> = ["Website"]
    private static let pinnedDynamicSubthemes: Set<String> = ["Dynamic Desktop", "Image Playground"]
    var onMoodSelected: ((Mood) -> Void)?

    private static let quoteTemplatesByStyle: [String: Mood] = Dictionary(
        uniqueKeysWithValues: MoodEngine.builtInMoods()
            .filter { $0.wallpaper.type == .quote }
            .compactMap { mood in
                guard let style = mood.wallpaper.resources.first else {
                    return nil
                }
                return (style, mood)
            }
    )

    var moods: [Mood] {
        _ = quoteRefreshToken
        return moodEngine.moods + customQuoteMoods()
    }

    var currentMood: Mood? {
        moodEngine.currentMood
    }

    init(moodEngine: MoodEngine, playerViewModel: PlayerViewModel, quoteEngine: QuoteEngine) {
        self.moodEngine = moodEngine
        self.playerViewModel = playerViewModel
        self.quoteEngine = quoteEngine
    }

    func selectMood(_ mood: Mood) {
        onMoodSelected?(mood)
        Task {
            await moodEngine.applyMood(mood)
        }
    }

    func addCustomMood(name: String, theme: String = "Custom", subtheme: String = "Personal", wallpaperPath: String, layerMix: [String: Float], type: WallpaperType? = nil) {
        let finalType: WallpaperType
        if let type = type {
            finalType = type
        } else {
            let pathExtension = (wallpaperPath as NSString).pathExtension.lowercased()
            if ["heic", "heif"].contains(pathExtension) {
                finalType = .dynamic
            } else if ["jpg", "jpeg", "png"].contains(pathExtension) {
                finalType = .staticImage
            } else {
                finalType = .animated
            }
        }

        let newMood = Mood(
            id: UUID().uuidString,
            name: name,
            theme: theme,
            subtheme: subtheme,
            layerMix: layerMix,
            wallpaper: WallpaperDescriptor(type: finalType, resources: [wallpaperPath]),
            palette: ThemePalette(
                primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1),
                secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2),
                accent: ColorComponents(red: 0.5, green: 0.5, blue: 0.5)
            )
        )
        moodEngine.addCustomMood(newMood)
    }

    func removeMood(_ mood: Mood) {
        // If it's a custom mood, clean up the wallpaper file
        if let path = mood.wallpaper.resources.first, path.contains("CustomWallpapers") {
            CustomAssetManager.removeCustomWallpaper(atPath: path)
        }
        moodEngine.removeCustomMood(id: mood.id)
    }

    func mood(for id: String) -> Mood? {
        moods.first { $0.id == id }
    }

    func firstMood(inSubtheme subtheme: String) -> Mood? {
        moods.first { $0.subtheme.caseInsensitiveCompare(subtheme) == .orderedSame }
    }

    func refreshQuoteMoods() {
        quoteRefreshToken += 1
    }

    var moodsBySubtheme: [String: [Mood]] {
        Dictionary(grouping: moods, by: { $0.subtheme })
    }

    var subthemes: [String] {
        subthemeSections.flatMap(\.subthemes)
    }

    var subthemeSections: [MoodSubthemeSection] {
        let allSubthemes = Set(moodsBySubtheme.keys)
        let atmosphereSubthemes = allSubthemes
            .filter { !Self.dynamicSubthemes.contains($0) && !Self.miscellaneousSubthemes.contains($0) }
            .sorted()
        let dynamicSubthemes = allSubthemes
            .filter { Self.dynamicSubthemes.contains($0) }
            .union(Self.pinnedDynamicSubthemes)
            .sorted()
        let miscellaneousSubthemes = allSubthemes
            .filter { Self.miscellaneousSubthemes.contains($0) }
            .sorted()
        var sections: [MoodSubthemeSection] = []

        if !atmosphereSubthemes.isEmpty {
            sections.append(MoodSubthemeSection(title: "Atmospheres", subthemes: atmosphereSubthemes))
        }

        if !dynamicSubthemes.isEmpty {
            sections.append(MoodSubthemeSection(title: "Dynamic", subthemes: dynamicSubthemes))
        }

        if !miscellaneousSubthemes.isEmpty {
            sections.append(MoodSubthemeSection(title: "Miscellaneous", subthemes: miscellaneousSubthemes))
        }

        return sections
    }

    var selectedSubtheme: String?

    func selectNextMood() {
        guard let current = currentMood,
              let subthemeMoods = moodsBySubtheme[current.subtheme],
              let index = subthemeMoods.firstIndex(where: { $0.id == current.id }) else {
            if let first = moods.first {
                selectMood(first)
            }
            return
        }

        if index + 1 < subthemeMoods.count {
            selectMood(subthemeMoods[index + 1])
        } else {
            // Cycle to next subtheme if at the end of current one
            selectNextSubtheme()
        }
    }

    func selectPreviousMood() {
        guard let current = currentMood,
              let subthemeMoods = moodsBySubtheme[current.subtheme],
              let index = subthemeMoods.firstIndex(where: { $0.id == current.id }) else {
            if let last = moods.last {
                selectMood(last)
            }
            return
        }

        if index > 0 {
            selectMood(subthemeMoods[index - 1])
        } else {
            // Cycle to previous subtheme if at the start of current one
            selectPreviousSubtheme()
        }
    }

    func selectNextSubtheme() {
        guard let current = currentMood else {
            if let first = moods.first {
                selectMood(first)
                selectedSubtheme = first.subtheme
            }
            return
        }

        let currentSubtheme = current.subtheme
        guard let currentIndex = subthemes.firstIndex(of: currentSubtheme) else { return }

        let nextIndex = (currentIndex + 1) % subthemes.count
        let nextSubtheme = subthemes[nextIndex]
        selectedSubtheme = nextSubtheme

        if let firstMoodInNextSubtheme = moodsBySubtheme[nextSubtheme]?.first {
            selectMood(firstMoodInNextSubtheme)
        }
    }

    func selectPreviousSubtheme() {
        guard let current = currentMood else {
            if let last = moods.last {
                selectMood(last)
                selectedSubtheme = last.subtheme
            }
            return
        }

        let currentSubtheme = current.subtheme
        guard let currentIndex = subthemes.firstIndex(of: currentSubtheme) else { return }

        let prevIndex = (currentIndex - 1 + subthemes.count) % subthemes.count
        let prevSubtheme = subthemes[prevIndex]
        selectedSubtheme = prevSubtheme

        if let firstMoodInPrevSubtheme = moodsBySubtheme[prevSubtheme]?.first {
            selectMood(firstMoodInPrevSubtheme)
        }
    }

    private func customQuoteMoods() -> [Mood] {
        quoteEngine.loadQuotes().map { quote in
            let template = Self.quoteTemplatesByStyle[quote.style]

            return Mood(
                id: "custom_quote_\(quote.id.uuidString)",
                name: quote.text,
                theme: template?.theme ?? "Dynamic",
                subtheme: "Quotes",
                layerMix: template?.layerMix ?? [:],
                wallpaper: WallpaperDescriptor(type: .quote, resources: [quote.style, quote.id.uuidString]),
                palette: template?.palette ?? ThemePalette(
                    primary: ColorComponents(red: 0.95, green: 0.95, blue: 0.95),
                    secondary: ColorComponents(red: 0.75, green: 0.75, blue: 0.75),
                    accent: ColorComponents(red: 0.5, green: 0.5, blue: 0.5)
                )
            )
        }
    }
}
