import Foundation
import Observation

@MainActor
@Observable
final class PlaylistViewModel {
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
        if !playlists.isEmpty { return }
        let morning = Playlist(name: "Morning Focus", entries: [
            PlaylistEntry(moodID: "deep_blue", duration: 2700, transitionStyle: .crossfade),
            PlaylistEntry(moodID: "minimalist", duration: 2700, transitionStyle: .crossfade)
        ])
        let afternoon = Playlist(name: "Afternoon Reset", entries: [
            PlaylistEntry(moodID: "vitality", duration: 1200, transitionStyle: .crossfade),
            PlaylistEntry(moodID: "mountain_stream", duration: 2400, transitionStyle: .crossfade)
        ])
        let evening = Playlist(name: "Evening Wind-Down", entries: [
            PlaylistEntry(moodID: "quiet_mind", duration: 1800, transitionStyle: .crossfade),
            PlaylistEntry(moodID: "midnight_rain", duration: 0, transitionStyle: .crossfade)
        ])
        playlistEngine.savePlaylist(morning)
        playlistEngine.savePlaylist(afternoon)
        playlistEngine.savePlaylist(evening)
    }
}
