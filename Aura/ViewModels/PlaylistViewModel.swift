import Foundation
import Observation

private struct PlaylistEntryTemplate {
    let moodID: String?
    let customAudioPath: String?
    let name: String?
    let duration: TimeInterval
    let transitionStyle: TransitionStyle
}

@MainActor
@Observable
final class PlaylistViewModel {
    private struct PlaylistTemplate {
        let name: String
        let entries: [PlaylistEntryTemplate]

        func makePlaylist(id: UUID = UUID(), scheduleTime: Date? = nil) -> Playlist {
            Playlist(
                id: id,
                name: name,
                entries: entries.map {
                    PlaylistEntry(
                        moodID: $0.moodID,
                        customAudioPath: $0.customAudioPath,
                        name: $0.name,
                        duration: $0.duration,
                        transitionStyle: $0.transitionStyle
                    )
                },
                scheduleTime: scheduleTime
            )
        }

        func matches(_ playlist: Playlist) -> Bool {
            guard playlist.name == name, playlist.entries.count == entries.count else {
                return false
            }

            return zip(playlist.entries, entries).allSatisfy { playlistEntry, templateEntry in
                playlistEntry.moodID == templateEntry.moodID &&
                    playlistEntry.customAudioPath == templateEntry.customAudioPath &&
                    playlistEntry.name == templateEntry.name &&
                    playlistEntry.duration == templateEntry.duration &&
                    playlistEntry.transitionStyle == templateEntry.transitionStyle
            }
        }
    }

    private enum Defaults {
        static let versionKey = "Aura.playlistDefaultsVersion"
        static let currentVersion = 2
    }

    private let playlistEngine: PlaylistEngine

    var playlists: [Playlist] {
        playlistEngine.playlists
    }

    var state: PlaylistState {
        playlistEngine.state
    }

    var shuffleEnabled: Bool {
        get { playlistEngine.shuffleEnabled }
        set { playlistEngine.shuffleEnabled = newValue }
    }

    var repeatMode: RepeatMode {
        get { playlistEngine.repeatMode }
        set { playlistEngine.repeatMode = newValue }
    }

    init(playlistEngine: PlaylistEngine) {
        self.playlistEngine = playlistEngine
        ensureDefaults()
    }

    func play(_ playlist: Playlist) {
        playlistEngine.play(playlist)
    }

    func pause() {
        playlistEngine.pause()
    }

    func resume() {
        playlistEngine.resume()
    }

    func skip() {
        playlistEngine.skip()
    }

    func previous() {
        playlistEngine.previous()
    }

    func restart() {
        playlistEngine.restart()
    }

    func stop() {
        playlistEngine.stop()
    }

    func toggleShuffle() {
        playlistEngine.shuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        let modes = RepeatMode.allCases
        if let index = modes.firstIndex(of: playlistEngine.repeatMode) {
            playlistEngine.repeatMode = modes[(index + 1) % modes.count]
        }
    }

    func save(_ playlist: Playlist) {
        playlistEngine.savePlaylist(playlist)
    }

    func delete(id: UUID) {
        playlistEngine.deletePlaylist(id: id)
    }

    private func ensureDefaults() {
        let defaults = UserDefaults.standard

        if playlists.isEmpty {
            defaultTemplates.map { $0.makePlaylist() }.forEach(playlistEngine.savePlaylist)
            defaults.set(Defaults.currentVersion, forKey: Defaults.versionKey)
            return
        }

        guard defaults.integer(forKey: Defaults.versionKey) < Defaults.currentVersion else {
            return
        }

        let legacyTemplatesByName = Dictionary(uniqueKeysWithValues: legacyDefaultTemplates.map { ($0.name, $0) })
        let updatedTemplatesByName = Dictionary(uniqueKeysWithValues: defaultTemplates.map { ($0.name, $0) })

        for playlist in playlists {
            guard let legacyTemplate = legacyTemplatesByName[playlist.name],
                  legacyTemplate.matches(playlist),
                  let updatedTemplate = updatedTemplatesByName[playlist.name] else {
                continue
            }

            let refreshedPlaylist = updatedTemplate.makePlaylist(id: playlist.id, scheduleTime: playlist.scheduleTime)
            playlistEngine.savePlaylist(refreshedPlaylist)
        }

        defaults.set(Defaults.currentVersion, forKey: Defaults.versionKey)
    }

    private var defaultTemplates: [PlaylistTemplate] {
        [
            PlaylistTemplate(
                name: "Morning Focus",
                entries: [
                    .init(moodID: "golden_hour", customAudioPath: nil, name: nil, duration: 900, transitionStyle: .dissolve),
                    .init(moodID: "morning_brew", customAudioPath: nil, name: nil, duration: 1500, transitionStyle: .crossfade),
                    .init(moodID: "steel_focus", customAudioPath: nil, name: nil, duration: 2400, transitionStyle: .crossfade),
                    .init(moodID: "minimalist", customAudioPath: nil, name: nil, duration: 0, transitionStyle: .dissolve)
                ]
            ),
            PlaylistTemplate(
                name: "Afternoon Reset",
                entries: [
                    .init(moodID: "vitality", customAudioPath: nil, name: nil, duration: 720, transitionStyle: .dissolve),
                    .init(moodID: "mountain_stream", customAudioPath: nil, name: nil, duration: 1200, transitionStyle: .crossfade),
                    .init(moodID: "deep_blue", customAudioPath: nil, name: nil, duration: 1800, transitionStyle: .crossfade),
                    .init(moodID: "quiet_harbor", customAudioPath: nil, name: nil, duration: 0, transitionStyle: .dissolve)
                ]
            ),
            PlaylistTemplate(
                name: "Evening Wind-Down",
                entries: [
                    .init(moodID: "golden_hour", customAudioPath: nil, name: nil, duration: 600, transitionStyle: .dissolve),
                    .init(moodID: "quiet_mind", customAudioPath: nil, name: nil, duration: 1500, transitionStyle: .crossfade),
                    .init(moodID: "inner_peace", customAudioPath: nil, name: nil, duration: 1800, transitionStyle: .dissolve),
                    .init(moodID: "midnight_rain", customAudioPath: nil, name: nil, duration: 0, transitionStyle: .crossfade)
                ]
            )
        ]
    }

    private var legacyDefaultTemplates: [PlaylistTemplate] {
        [
            PlaylistTemplate(
                name: "Morning Focus",
                entries: [
                    .init(moodID: "deep_blue", customAudioPath: nil, name: nil, duration: 2700, transitionStyle: .crossfade),
                    .init(moodID: "minimalist", customAudioPath: nil, name: nil, duration: 2700, transitionStyle: .crossfade)
                ]
            ),
            PlaylistTemplate(
                name: "Afternoon Reset",
                entries: [
                    .init(moodID: "vitality", customAudioPath: nil, name: nil, duration: 1200, transitionStyle: .crossfade),
                    .init(moodID: "mountain_stream", customAudioPath: nil, name: nil, duration: 2400, transitionStyle: .crossfade)
                ]
            ),
            PlaylistTemplate(
                name: "Evening Wind-Down",
                entries: [
                    .init(moodID: "quiet_mind", customAudioPath: nil, name: nil, duration: 1800, transitionStyle: .crossfade),
                    .init(moodID: "midnight_rain", customAudioPath: nil, name: nil, duration: 0, transitionStyle: .crossfade)
                ]
            )
        ]
    }
}
