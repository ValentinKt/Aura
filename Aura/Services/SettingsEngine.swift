import CoreData
import Foundation

struct UserSettings: Codable, Hashable {
    var weatherSyncEnabled: Bool
    var defaultMoodID: String
    var transitionDuration: Double
    var randomAmbienceInterval: Double
    var lastUsedMoodID: String?
    var keepCurrentWallpaper: Bool
    var websiteWallpaperInteractive: Bool
    var masterVolume: Float
    var smartDuckingEnabled: Bool

    init(weatherSyncEnabled: Bool = false, defaultMoodID: String = "mountain_stream", transitionDuration: Double = 2.5, randomAmbienceInterval: Double = 300, lastUsedMoodID: String? = nil, keepCurrentWallpaper: Bool = false, websiteWallpaperInteractive: Bool = true, masterVolume: Float = 0.6, smartDuckingEnabled: Bool = true) {
        self.weatherSyncEnabled = weatherSyncEnabled
        self.defaultMoodID = defaultMoodID
        self.transitionDuration = transitionDuration
        self.randomAmbienceInterval = randomAmbienceInterval
        self.lastUsedMoodID = lastUsedMoodID
        self.keepCurrentWallpaper = keepCurrentWallpaper
        self.websiteWallpaperInteractive = websiteWallpaperInteractive
        self.masterVolume = masterVolume
        self.smartDuckingEnabled = smartDuckingEnabled
    }
}

final class SettingsEngine {
    private let persistence: PersistenceController
    private let websiteInteractionMigrationKey = "didMigrateWebsiteWallpaperInteractionDefault"

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func loadSettings() -> UserSettings {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserSettings")
        request.fetchLimit = 1
        if let entity = try? context.fetch(request).first {

            // Provide a safe fallback for "smartDuckingEnabled" to prevent crashes on older stores
            let smartDuckingEnabled: Bool
            if entity.entity.attributesByName.keys.contains("smartDuckingEnabled") {
                smartDuckingEnabled = entity.value(forKey: "smartDuckingEnabled") as? Bool ?? true
            } else {
                smartDuckingEnabled = true
            }

            var settings = UserSettings(
                weatherSyncEnabled: entity.value(forKey: "weatherSyncEnabled") as? Bool ?? false,
                defaultMoodID: entity.value(forKey: "defaultMoodID") as? String ?? "mountain_stream",
                transitionDuration: entity.value(forKey: "transitionDuration") as? Double ?? 2.5,
                randomAmbienceInterval: entity.value(forKey: "randomAmbienceInterval") as? Double ?? 300,
                lastUsedMoodID: entity.value(forKey: "lastUsedMoodID") as? String,
                keepCurrentWallpaper: entity.value(forKey: "keepCurrentWallpaper") as? Bool ?? false,
                websiteWallpaperInteractive: entity.value(forKey: "websiteWallpaperInteractive") as? Bool ?? true,
                masterVolume: entity.value(forKey: "masterVolume") as? Float ?? 0.6,
                smartDuckingEnabled: smartDuckingEnabled
            )

            if UserDefaults.standard.bool(forKey: websiteInteractionMigrationKey) == false {
                settings.websiteWallpaperInteractive = true
                saveSettings(settings)
                UserDefaults.standard.set(true, forKey: websiteInteractionMigrationKey)
            }

            return settings
        }
        let defaults = UserSettings()
        saveSettings(defaults)
        UserDefaults.standard.set(true, forKey: websiteInteractionMigrationKey)
        return defaults
    }

    func saveSettings(_ settings: UserSettings) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "UserSettings")
        request.fetchLimit = 1
        let entity = (try? context.fetch(request))?.first ?? NSEntityDescription.insertNewObject(forEntityName: "UserSettings", into: context)
        entity.setValue(settings.weatherSyncEnabled, forKey: "weatherSyncEnabled")
        entity.setValue(settings.defaultMoodID, forKey: "defaultMoodID")
        entity.setValue(settings.transitionDuration, forKey: "transitionDuration")
        entity.setValue(settings.randomAmbienceInterval, forKey: "randomAmbienceInterval")
        entity.setValue(settings.lastUsedMoodID, forKey: "lastUsedMoodID")
        entity.setValue(settings.keepCurrentWallpaper, forKey: "keepCurrentWallpaper")
        entity.setValue(settings.websiteWallpaperInteractive, forKey: "websiteWallpaperInteractive")
        entity.setValue(settings.masterVolume, forKey: "masterVolume")
        entity.setValue(settings.smartDuckingEnabled, forKey: "smartDuckingEnabled")
        persistence.saveContext()
    }

    func updateMasterVolume(_ volume: Float) {
        var settings = loadSettings()
        settings.masterVolume = volume
        saveSettings(settings)
    }

    func updateLastUsedMood(_ moodID: String) {
        var settings = loadSettings()
        settings.lastUsedMoodID = moodID
        saveSettings(settings)
    }

    func updateWeatherSync(_ enabled: Bool) {
        var settings = loadSettings()
        settings.weatherSyncEnabled = enabled
        saveSettings(settings)
    }

    func updateTransitionDuration(_ duration: Double) {
        var settings = loadSettings()
        settings.transitionDuration = duration
        saveSettings(settings)
    }

    func updateRandomAmbienceInterval(_ interval: Double) {
        var settings = loadSettings()
        settings.randomAmbienceInterval = interval
        saveSettings(settings)
    }

    func updateKeepCurrentWallpaper(_ enabled: Bool) {
        var settings = loadSettings()
        settings.keepCurrentWallpaper = enabled
        saveSettings(settings)
    }

    func updateWebsiteWallpaperInteractive(_ enabled: Bool) {
        var settings = loadSettings()
        settings.websiteWallpaperInteractive = enabled
        saveSettings(settings)
    }

    func updateSmartDuckingEnabled(_ enabled: Bool) {
        var settings = loadSettings()
        settings.smartDuckingEnabled = enabled
        saveSettings(settings)
    }

    func saveMoodMix(moodID: String, layerMix: [String: Float]) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "MoodMix")
        request.predicate = NSPredicate(format: "moodID == %@", moodID)

        let entity = (try? context.fetch(request))?.first ?? NSEntityDescription.insertNewObject(forEntityName: "MoodMix", into: context)

        let encoder = JSONEncoder()
        if let data = try? encoder.encode(layerMix) {
            entity.setValue(moodID, forKey: "moodID")
            entity.setValue(data, forKey: "layerMix")
            persistence.saveContext()
        }
    }

    func loadMoodMixes() -> [String: [String: Float]] {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "MoodMix")
        guard let entities = try? context.fetch(request) else { return [:] }

        let decoder = JSONDecoder()
        var mixes: [String: [String: Float]] = [:]

        for entity in entities {
            if let moodID = entity.value(forKey: "moodID") as? String,
               let data = entity.value(forKey: "layerMix") as? Data,
               let mix = try? decoder.decode([String: Float].self, from: data) {
                mixes[moodID] = mix
            }
        }

        return mixes
    }

    func loadCustomMoods() -> [Mood] {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CustomMood")
        guard let entities = try? context.fetch(request) else { return [] }

        return entities.compactMap { entity -> Mood? in
            guard let id = entity.value(forKey: "id") as? String,
                  let name = entity.value(forKey: "name") as? String,
                  let layerMixData = entity.value(forKey: "layerMix") as? Data,
                  let wallpaperData = entity.value(forKey: "wallpaper") as? Data,
                  let paletteData = entity.value(forKey: "palette") as? Data else {
                return nil
            }

            let theme = entity.value(forKey: "theme") as? String ?? "Custom"
            let subtheme = entity.value(forKey: "subtheme") as? String ?? "Personal"

            let decoder = JSONDecoder()
            guard let layerMix = try? decoder.decode([String: Float].self, from: layerMixData),
                  let wallpaper = try? decoder.decode(WallpaperDescriptor.self, from: wallpaperData),
                  let palette = try? decoder.decode(ThemePalette.self, from: paletteData) else {
                return nil
            }

            return Mood(id: id, name: name, theme: theme, subtheme: subtheme, layerMix: layerMix, wallpaper: wallpaper, palette: palette)
        }
    }

    func saveCustomMoods(_ moods: [Mood]) {
        let context = persistence.viewContext

        // Delete all existing custom moods
        let deleteRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "CustomMood")
        let batchDelete = NSBatchDeleteRequest(fetchRequest: deleteRequest)
        _ = try? context.execute(batchDelete)

        // Save new moods
        let encoder = JSONEncoder()
        for mood in moods {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "CustomMood", into: context)
            entity.setValue(mood.id, forKey: "id")
            entity.setValue(mood.name, forKey: "name")
            entity.setValue(mood.theme, forKey: "theme")
            entity.setValue(mood.subtheme, forKey: "subtheme")
            entity.setValue(try? encoder.encode(mood.layerMix), forKey: "layerMix")
            entity.setValue(try? encoder.encode(mood.wallpaper), forKey: "wallpaper")
            entity.setValue(try? encoder.encode(mood.palette), forKey: "palette")
        }

        persistence.saveContext()
    }
}
