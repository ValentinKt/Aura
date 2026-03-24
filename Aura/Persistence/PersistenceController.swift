import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()
    let container: NSPersistentContainer

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    init(inMemory: Bool = false) {
        let model = PersistenceController.makeModel()
        container = NSPersistentContainer(name: "Aura", managedObjectModel: model)
        // Ensure secure transformer is registered for any Transformable attributes
        ValueTransformer.setValueTransformer(NSSecureUnarchiveFromDataTransformer(),
                                             forName: NSValueTransformerName.secureUnarchiveFromDataTransformerName)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        container.persistentStoreDescriptions.first?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        // Ensure SQLite store type and a valid URL; create directory if needed
        if let desc = container.persistentStoreDescriptions.first {
            if desc.type.isEmpty {
                desc.type = NSSQLiteStoreType
            }
            if let url = desc.url {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            } else {
                if let appSupport = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) {
                    let bundleID = Bundle.main.bundleIdentifier ?? "Aura"
                    let dir = appSupport.appendingPathComponent(bundleID, isDirectory: true)
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    desc.url = dir.appendingPathComponent("Aura.sqlite")
                }
            }
        }
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { description, error in
            if error != nil {
                // Attempt recovery by deleting incompatible store and retrying once
                if let url = description.url {
                    let fm = FileManager.default
                    try? fm.removeItem(at: url)
                    try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
                    try? fm.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
                    self.container.loadPersistentStores { _, retryError in
                        if let retryError = retryError {
                            // Fallback to in-memory store as a last resort
                            let inMemoryDescription = NSPersistentStoreDescription()
                            inMemoryDescription.type = NSInMemoryStoreType
                            self.container.persistentStoreDescriptions = [inMemoryDescription]
                            self.container.loadPersistentStores { _, _ in }
                            print("🟥 [PersistenceController] Core Data fallback to in-memory store due to error: \(retryError)")
                        }
                    }
                }
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func saveContext() {
        let context = container.viewContext
        if container.persistentStoreCoordinator.persistentStores.isEmpty {
            return
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("🟥 [PersistenceController] Error saving context: \(error)")
            }
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let preset = NSEntityDescription()
        preset.name = "Preset"
        preset.managedObjectClassName = "NSManagedObject"
        preset.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("name", .stringAttributeType, optional: false),
            attribute("moodID", .stringAttributeType, optional: false),
            transformable("layerConfig", optional: true),
            attribute("createdAt", .dateAttributeType, optional: false),
            attribute("isFavorite", .booleanAttributeType, optional: false)
        ]

        let playlist = NSEntityDescription()
        playlist.name = "Playlist"
        playlist.managedObjectClassName = "NSManagedObject"
        playlist.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("name", .stringAttributeType, optional: false),
            transformable("entries", optional: false),
            attribute("scheduleTime", .dateAttributeType, optional: true),
            attribute("createdAt", .dateAttributeType, optional: false)
        ]

        let settings = NSEntityDescription()
        settings.name = "UserSettings"
        settings.managedObjectClassName = "NSManagedObject"
        settings.properties = [
            attribute("weatherSyncEnabled", .booleanAttributeType, optional: false),
            attribute("defaultMoodID", .stringAttributeType, optional: false),
            attribute("transitionDuration", .doubleAttributeType, optional: false),
            attribute("randomAmbienceInterval", .doubleAttributeType, optional: false),
            attribute("lastUsedMoodID", .stringAttributeType, optional: true),
            attribute("keepCurrentWallpaper", .booleanAttributeType, optional: false),
            attribute("masterVolume", .floatAttributeType, optional: false)
        ]

        let customMood = NSEntityDescription()
        customMood.name = "CustomMood"
        customMood.managedObjectClassName = "NSManagedObject"
        customMood.properties = [
            attribute("id", .stringAttributeType, optional: false),
            attribute("name", .stringAttributeType, optional: false),
            attribute("theme", .stringAttributeType, optional: false),
            attribute("subtheme", .stringAttributeType, optional: false),
            binaryData("layerMix", optional: false, allowsExternalStorage: true),
            binaryData("wallpaper", optional: false, allowsExternalStorage: true),
            binaryData("palette", optional: false, allowsExternalStorage: true)
        ]

        let moodMix = NSEntityDescription()
        moodMix.name = "MoodMix"
        moodMix.managedObjectClassName = "NSManagedObject"
        moodMix.properties = [
            attribute("moodID", .stringAttributeType, optional: false),
            binaryData("layerMix", optional: false, allowsExternalStorage: true)
        ]

        let customQuote = NSEntityDescription()
        customQuote.name = "CustomQuote"
        customQuote.managedObjectClassName = "NSManagedObject"
        customQuote.properties = [
            attribute("id", .UUIDAttributeType, optional: false),
            attribute("text", .stringAttributeType, optional: false),
            attribute("style", .stringAttributeType, optional: false),
            attribute("createdAt", .dateAttributeType, optional: false)
        ]

        model.entities = [preset, playlist, settings, customMood, moodMix, customQuote]
        return model
    }

    private static func attribute(_ name: String, _ type: NSAttributeType, optional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }

    private static func binaryData(_ name: String, optional: Bool, allowsExternalStorage: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .binaryDataAttributeType
        attribute.isOptional = optional
        attribute.allowsExternalBinaryDataStorage = allowsExternalStorage
        return attribute
    }

    private static func transformable(_ name: String, optional: Bool) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = .transformableAttributeType
        attribute.isOptional = optional
        attribute.valueTransformerName = NSValueTransformerName.secureUnarchiveFromDataTransformerName.rawValue
        attribute.allowsExternalBinaryDataStorage = true
        attribute.attributeValueClassName = NSStringFromClass(NSData.self)
        return attribute
    }
}

// MARK: - Custom Quotes

struct CustomQuoteModel: Identifiable, Codable, Hashable {
    let id: UUID
    var text: String
    var style: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, style: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.style = style
        self.createdAt = createdAt
    }
}

@MainActor
final class QuoteEngine {
    private let persistence: PersistenceController

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func loadQuotes(for style: String? = nil) -> [CustomQuoteModel] {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CustomQuote")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        if let style = style {
            request.predicate = NSPredicate(format: "style == %@", style)
        }

        do {
            let results = try context.fetch(request)
            return results.compactMap { entity in
                guard let id = entity.value(forKey: "id") as? UUID,
                      let text = entity.value(forKey: "text") as? String,
                      let entityStyle = entity.value(forKey: "style") as? String,
                      let createdAt = entity.value(forKey: "createdAt") as? Date else {
                    return nil
                }
                return CustomQuoteModel(id: id, text: text, style: entityStyle, createdAt: createdAt)
            }
        } catch {
            print("🟥 [QuoteEngine] Failed to load quotes: \(error)")
            return []
        }
    }

    func saveQuote(_ quote: CustomQuoteModel) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CustomQuote")
        request.predicate = NSPredicate(format: "id == %@", quote.id as CVarArg)

        do {
            let entity = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "CustomQuote", into: context)
            entity.setValue(quote.id, forKey: "id")
            entity.setValue(quote.text, forKey: "text")
            entity.setValue(quote.style, forKey: "style")
            entity.setValue(quote.createdAt, forKey: "createdAt")
            
            try context.save()
        } catch {
            print("🟥 [QuoteEngine] Failed to save quote: \(error)")
        }
    }

    func deleteQuote(id: UUID) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "CustomQuote")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            print("🟥 [QuoteEngine] Failed to delete quote: \(error)")
        }
    }
}

