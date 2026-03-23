import Foundation

enum SoundLayerID: String, CaseIterable, Identifiable, Codable {
    case rain
    case forest
    case ocean
    case wind
    case cafe
    case brownnoise
    case stream
    case night
    case crickets
    case fan
    case hum
    case piano
    case fire
    case thunder
    case birds
    case seaside
    case mountainstream
    case tropicalbeach
    case heavyrain

    var id: String { rawValue }
}

struct SoundLayer: Identifiable, Codable, Hashable {
    var id: String
    var volume: Float
    var pan: Float
    var lowPassCutoff: Float

    init(id: String, volume: Float, pan: Float, lowPassCutoff: Float) {
        self.id = id
        self.volume = volume
        self.pan = pan
        self.lowPassCutoff = lowPassCutoff
    }
}
