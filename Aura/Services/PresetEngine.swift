import CoreData
import Foundation

final class PresetEngine {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func fetchPresets() -> [Preset] {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Preset")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let results = (try? context.fetch(request)) ?? []
        return results.compactMap { preset(from: $0) }
    }

    func savePreset(_ preset: Preset) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Preset")
        request.predicate = NSPredicate(format: "id == %@", preset.id as CVarArg)
        let entity = (try? context.fetch(request))?.first ?? NSEntityDescription.insertNewObject(forEntityName: "Preset", into: context)
        entity.setValue(preset.id, forKey: "id")
        entity.setValue(preset.name, forKey: "name")
        entity.setValue(preset.moodID, forKey: "moodID")
        if let encodedConfig = try? JSONEncoder().encode(preset.layerConfig) {
            entity.setValue(encodedConfig, forKey: "layerConfig")
        }
        entity.setValue(preset.createdAt, forKey: "createdAt")
        entity.setValue(preset.isFavorite, forKey: "isFavorite")
        persistence.saveContext()
    }

    func deletePreset(id: UUID) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Preset")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            context.delete(entity)
            persistence.saveContext()
        }
    }

    func toggleFavorite(id: UUID) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Preset")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let entity = try? context.fetch(request).first {
            let current = entity.value(forKey: "isFavorite") as? Bool ?? false
            entity.setValue(!current, forKey: "isFavorite")
            persistence.saveContext()
        }
    }

    func exportPresets() -> Data? {
        let presets = fetchPresets()
        return try? JSONEncoder().encode(presets)
    }

    func importPresets(from data: Data) -> [Preset] {
        guard let decoded = try? JSONDecoder().decode([Preset].self, from: data) else {
            return []
        }
        for preset in decoded {
            savePreset(preset)
        }
        return decoded
    }

    func loadDefaultPresets() {
        let presets = fetchPresets()
        guard presets.isEmpty else { return }

        let bundle = Bundle.main
        guard let url = bundle.url(forResource: "default_presets", withExtension: "json", subdirectory: "Resources/Presets") ??
                          bundle.url(forResource: "default_presets", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return
        }

        _ = importPresets(from: data)
    }

    private func preset(from object: NSManagedObject) -> Preset? {
        guard let id = object.value(forKey: "id") as? UUID,
              let name = object.value(forKey: "name") as? String,
              let moodID = object.value(forKey: "moodID") as? String,
              let createdAt = object.value(forKey: "createdAt") as? Date else {
            return nil
        }
        let layerConfigData = object.value(forKey: "layerConfig") as? Data
        let layerConfig: [String: Float]
        if let data = layerConfigData {
            layerConfig = (try? JSONDecoder().decode([String: Float].self, from: data)) ?? [:]
        } else {
            layerConfig = [:]
        }
        let isFavorite = object.value(forKey: "isFavorite") as? Bool ?? false
        return Preset(id: id, name: name, moodID: moodID, layerConfig: layerConfig, createdAt: createdAt, isFavorite: isFavorite)
    }
}
