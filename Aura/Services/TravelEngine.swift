import Foundation
import Observation

struct TravelLocationPack: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var label: String
    var layerMix: [String: Float]
    var wallpaper: WallpaperDescriptor

    init(id: UUID = UUID(), name: String, label: String, layerMix: [String: Float], wallpaper: WallpaperDescriptor) {
        self.id = id
        self.name = name
        self.label = label
        self.layerMix = layerMix
        self.wallpaper = wallpaper
    }
}

enum TravelState: Equatable {
    case idle
    case applying(TravelLocationPack)
    case active(TravelLocationPack)
    case error(String)
}

@MainActor
@Observable
final class TravelEngine {
    private let moodEngine: MoodEngine
    private let wallpaperEngine: WallpaperEngine
    private(set) var packs: [TravelLocationPack] = []
    private(set) var state: TravelState = .idle

    var activePack: TravelLocationPack? {
        switch state {
        case .active(let pack), .applying(let pack):
            return pack
        default:
            return nil
        }
    }

    init(moodEngine: MoodEngine, wallpaperEngine: WallpaperEngine) {
        self.moodEngine = moodEngine
        self.wallpaperEngine = wallpaperEngine
        self.packs = TravelEngine.builtInPacks()
    }

    func shuffle() async -> TravelLocationPack? {
        guard let pack = packs.randomElement() else { return nil }
        await apply(pack)
        return pack
    }

    private var applyTask: Task<Void, Never>?

    func apply(_ pack: TravelLocationPack) async {
        print("🟢 [TravelEngine] Applying pack \(pack.name)")
        
        // Cancel previous apply task to allow rapid switching
        applyTask?.cancel()
        
        applyTask = Task {
            state = .applying(pack)
            
            let mood = Mood(
                id: "travel_\(pack.id.uuidString)",
                name: pack.name,
                theme: "Travel",
                subtheme: pack.name,
                layerMix: pack.layerMix,
                wallpaper: pack.wallpaper,
                palette: themeForPack(pack)
            )
            
            print("🟢 [TravelEngine] Created mood for travel, applying via MoodEngine")
            await self.moodEngine.applyMood(mood)
            
            if !Task.isCancelled {
                state = .active(pack)
                print("🟢 [TravelEngine] Travel application complete")
            }
        }
        
        await applyTask?.value
    }

    func addCustomPack(_ pack: TravelLocationPack) {
        packs.append(pack)
        // Note: In a production app, we would persist this to Core Data or JSON
    }

    private func themeForPack(_ pack: TravelLocationPack) -> ThemePalette {
        let name = pack.name.lowercased()
        if name.contains("tokyo") {
            return ThemePalette(primary: ColorComponents(red: 0.7, green: 0.25, blue: 0.35), secondary: ColorComponents(red: 0.15, green: 0.2, blue: 0.3), accent: ColorComponents(red: 0.85, green: 0.5, blue: 0.6))
        } else if name.contains("nordic") {
            return ThemePalette(primary: ColorComponents(red: 0.2, green: 0.35, blue: 0.25), secondary: ColorComponents(red: 0.3, green: 0.45, blue: 0.35), accent: ColorComponents(red: 0.75, green: 0.8, blue: 0.7))
        } else if name.contains("amazon") {
            return ThemePalette(primary: ColorComponents(red: 0.18, green: 0.4, blue: 0.2), secondary: ColorComponents(red: 0.25, green: 0.5, blue: 0.3), accent: ColorComponents(red: 0.75, green: 0.85, blue: 0.6))
        } else if name.contains("mediterranean") {
            return ThemePalette(primary: ColorComponents(red: 0.2, green: 0.45, blue: 0.75), secondary: ColorComponents(red: 0.35, green: 0.6, blue: 0.85), accent: ColorComponents(red: 0.9, green: 0.75, blue: 0.45))
        } else if name.contains("icelandic") {
            return ThemePalette(primary: ColorComponents(red: 0.2, green: 0.3, blue: 0.45), secondary: ColorComponents(red: 0.3, green: 0.4, blue: 0.6), accent: ColorComponents(red: 0.65, green: 0.75, blue: 0.9))
        } else if name.contains("new york") {
            return ThemePalette(primary: ColorComponents(red: 0.1, green: 0.12, blue: 0.2), secondary: ColorComponents(red: 0.2, green: 0.25, blue: 0.35), accent: ColorComponents(red: 0.7, green: 0.4, blue: 0.5))
        } else {
            return ThemePalette(primary: ColorComponents(red: 0.3, green: 0.3, blue: 0.3), secondary: ColorComponents(red: 0.4, green: 0.4, blue: 0.4), accent: ColorComponents(red: 0.6, green: 0.6, blue: 0.6))
        }
    }

    static func builtInPacks() -> [TravelLocationPack] {
        [
            TravelLocationPack(
                name: "Tokyo Café",
                label: "東京 — Tokyo",
                layerMix: ["cafe": 0.8, "rain": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["Cafe.mp4"], fps: 0.5)
            ),
            TravelLocationPack(
                name: "Nordic Forest",
                label: "Scandinavia",
                layerMix: ["forest": 0.8, "wind": 0.3],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["NordicForest.mp4"], fps: 0.5)
            ),
            TravelLocationPack(
                name: "Amazon Jungle",
                label: "Amazônia",
                layerMix: ["forest": 0.7, "rain": 0.5, "ocean": 0.1],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["AmazonJungle.mov"], fps: 0.5)
            ),
            TravelLocationPack(
                name: "Mediterranean Beach",
                label: "Mare Nostrum",
                layerMix: ["ocean": 0.9, "wind": 0.2],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["MediterraneanBeach.mp4"], fps: 0.5)
            ),
            TravelLocationPack(
                name: "Icelandic Highlands",
                label: "Ísland",
                layerMix: ["wind": 0.7],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["IcelandicHighlands.mov"], fps: 0.5)
            ),
            TravelLocationPack(
                name: "New York Night",
                label: "New York",
                layerMix: ["cafe": 0.6, "rain": 0.4],
                wallpaper: WallpaperDescriptor(type: .animated, resources: ["NewYorkNight.mov"], fps: 0.5)
            )
        ]
    }
}
