import Foundation

struct Playlist: Identifiable, Codable, Hashable {
    var id: UUID
    var name: String
    var entries: [PlaylistEntry]
    var scheduleTime: Date?

    init(id: UUID = UUID(), name: String, entries: [PlaylistEntry], scheduleTime: Date? = nil) {
        self.id = id
        self.name = name
        self.entries = entries
        self.scheduleTime = scheduleTime
    }
}

struct PlaylistEntry: Identifiable, Codable, Hashable {
    var id: UUID
    var moodID: String?
    var customAudioPath: String?
    var name: String? // For custom audio
    var duration: TimeInterval
    var transitionStyle: TransitionStyle

    init(id: UUID = UUID(), moodID: String? = nil, customAudioPath: String? = nil, name: String? = nil, duration: TimeInterval, transitionStyle: TransitionStyle) {
        self.id = id
        self.moodID = moodID
        self.customAudioPath = customAudioPath
        self.name = name
        self.duration = duration
        self.transitionStyle = transitionStyle
    }
}

enum TransitionStyle: String, Codable, Hashable, CaseIterable {
    case crossfade
    case dissolve
}

enum RepeatMode: String, Codable, Hashable, CaseIterable {
    case off
    case one
    case all
}
