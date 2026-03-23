import Foundation

struct Preset: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var moodID: String
    var layerConfig: [String: Float]
    var createdAt: Date
    var isFavorite: Bool

    init(id: UUID = UUID(), name: String, moodID: String, layerConfig: [String: Float], createdAt: Date = Date(), isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.moodID = moodID
        self.layerConfig = layerConfig
        self.createdAt = createdAt
        self.isFavorite = isFavorite
    }
}
