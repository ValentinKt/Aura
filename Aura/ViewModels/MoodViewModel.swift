import Foundation
import Observation

@MainActor
@Observable
final class MoodViewModel {
    private let moodEngine: MoodEngine
    private let playerViewModel: PlayerViewModel
    
    var moods: [Mood] {
        moodEngine.moods
    }
    
    var currentMood: Mood? {
        moodEngine.currentMood
    }

    init(moodEngine: MoodEngine, playerViewModel: PlayerViewModel) {
        self.moodEngine = moodEngine
        self.playerViewModel = playerViewModel
    }

    func selectMood(_ mood: Mood) {
        Task {
            await moodEngine.applyMood(mood)
        }
    }

    func addCustomMood(name: String, theme: String = "Custom", subtheme: String = "Personal", wallpaperPath: String, layerMix: [String: Float], type: WallpaperType? = nil) {
        let finalType: WallpaperType
        if let type = type {
            finalType = type
        } else {
            let isHeicOrImage = ["heic", "heif", "jpg", "jpeg", "png"].contains((wallpaperPath as NSString).pathExtension.lowercased())
            finalType = isHeicOrImage ? .dynamic : .animated
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
    
    var moodsBySubtheme: [String: [Mood]] {
        Dictionary(grouping: moods, by: { $0.subtheme })
    }
    
    var subthemes: [String] {
        moodsBySubtheme.keys.sorted()
    }
    
    var selectedSubtheme: String? = nil

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
}
