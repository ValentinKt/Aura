import CoreData
import Foundation
import Observation

enum PlaylistError: Error, LocalizedError {
    case playlistNotFound
    case emptyEntries
    case invalidMood(String)
    case persistenceError(Error)

    var errorDescription: String? {
        switch self {
        case .playlistNotFound: return "The selected playlist was not found."
        case .emptyEntries: return "The playlist has no entries."
        case .invalidMood(let id): return "Could not find mood with ID: \(id)"
        case .persistenceError(let error): return "Database error: \(error.localizedDescription)"
        }
    }
}

enum PlaylistState: Equatable {
    case idle
    case playing(Playlist, Int) // playlist, current index
    case paused(Playlist, Int)
    case error(String)

    static func == (lhs: PlaylistState, rhs: PlaylistState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.playing(let lp, let li), .playing(let rp, let ri)): return lp.id == rp.id && li == ri
        case (.paused(let lp, let li), .paused(let rp, let ri)): return lp.id == rp.id && li == ri
        case (.error(let l), .error(let r)): return l == r
        default: return false
        }
    }
}

@MainActor
@Observable
final class PlaylistEngine {
    private(set) var playlists: [Playlist] = []
    private(set) var state: PlaylistState = .idle
    private(set) var lastError: PlaylistError?

    var shuffleEnabled: Bool = false
    var repeatMode: RepeatMode = .off

    private let moodEngine: MoodEngine
    private let persistence: PersistenceController
    private var playbackTask: Task<Void, Never>?
    private var scheduleTask: Task<Void, Never>?
    private var playbackStartedAt: Date?
    private var remainingEntryDuration: TimeInterval?

    init(moodEngine: MoodEngine, persistence: PersistenceController) {
        self.moodEngine = moodEngine
        self.persistence = persistence
        self.playlists = loadPlaylists()
        startScheduling()
    }

    func play(_ playlist: Playlist) {
        guard !playlist.entries.isEmpty else {
            state = .error(PlaylistError.emptyEntries.localizedDescription)
            return
        }
        state = .playing(playlist, 0)
        startPlayback()
    }

    func pause() {
        if case .playing(let playlist, let index) = state {
            remainingEntryDuration = remainingDuration(for: playlist.entries[index])
            state = .paused(playlist, index)
            moodEngine.pausePlayback()
            stopPlayback()
        }
    }

    func resume() {
        if case .paused(let playlist, let index) = state {
            state = .playing(playlist, index)
            moodEngine.resumePlayback()
            startPlayback(reapplyEntry: false)
        }
    }

    func skip() {
        advance()
    }

    func previous() {
        if case .playing(let playlist, let index) = state {
            let newIndex = max(0, index - 1)
            state = .playing(playlist, newIndex)
            startPlayback()
        } else if case .paused(let playlist, let index) = state {
            let newIndex = max(0, index - 1)
            state = .paused(playlist, newIndex)
            remainingEntryDuration = playlist.entries[newIndex].duration
        }
    }

    func restart() {
        if case .playing(let playlist, _) = state {
            state = .playing(playlist, 0)
            startPlayback()
        } else if case .paused(let playlist, _) = state {
            state = .paused(playlist, 0)
            remainingEntryDuration = playlist.entries.first?.duration
        }
    }

    func stop() {
        state = .idle
        stopPlayback()
    }

    func savePlaylist(_ playlist: Playlist) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Playlist")
        request.predicate = NSPredicate(format: "id == %@", playlist.id as CVarArg)

        do {
            let entity = try context.fetch(request).first ?? NSEntityDescription.insertNewObject(forEntityName: "Playlist", into: context)
            entity.setValue(playlist.id, forKey: "id")
            entity.setValue(playlist.name, forKey: "name")

            if let encodedEntries = try? JSONEncoder().encode(playlist.entries) {
                entity.setValue(encodedEntries, forKey: "entries")
            }
            entity.setValue(playlist.scheduleTime, forKey: "scheduleTime")
            entity.setValue(Date(), forKey: "createdAt")

            try context.save()
            playlists = loadPlaylists()
            startScheduling()
        } catch {
            print("🟥 [PlaylistEngine] Failed to save playlist: \(error)")
            lastError = .persistenceError(error)
        }
    }

    func deletePlaylist(id: UUID) {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Playlist")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)

        do {
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
                playlists = loadPlaylists()

                if case .playing(let p, _) = state, p.id == id {
                    stop()
                } else if case .paused(let p, _) = state, p.id == id {
                    stop()
                }

                startScheduling()
            }
        } catch {
            print("🟥 [PlaylistEngine] Failed to delete playlist: \(error)")
            lastError = .persistenceError(error)
        }
    }

    private func startPlayback(reapplyEntry: Bool = true) {
        stopPlayback()

        guard case .playing(let playlist, let index) = state else { return }

        playbackTask = Task { [weak self] in
            guard let self else { return }

            let entry = playlist.entries[index]

            if reapplyEntry {
                if let audioPath = entry.customAudioPath {
                    let url = URL(fileURLWithPath: audioPath)
                    await moodEngine.playCustomAudio(url: url)
                } else if let moodID = entry.moodID {
                    guard let mood = moodEngine.mood(for: moodID) else {
                        await MainActor.run {
                            self.state = .error(PlaylistError.invalidMood(moodID).localizedDescription)
                        }
                        return
                    }
                    await moodEngine.applyMood(mood)
                } else {
                    await MainActor.run {
                        self.state = .error("Invalid playlist entry: no mood or audio.")
                    }
                    return
                }
            }

            await self.scheduleAdvance(after: reapplyEntry ? entry.duration : (self.remainingEntryDuration ?? entry.duration))
        }
    }

    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        playbackStartedAt = nil
    }

    private func advance() {
        guard case .playing(let playlist, let index) = state else { return }

        var nextIndex = index + 1

        if shuffleEnabled {
            nextIndex = Int.random(in: 0..<playlist.entries.count)
        } else if nextIndex >= playlist.entries.count {
            switch repeatMode {
            case .off:
                state = .idle
                return
            case .one:
                nextIndex = index // Repeat current
            case .all:
                nextIndex = 0
            }
        }

        state = .playing(playlist, nextIndex)
        startPlayback()
    }

    private func scheduleAdvance(after duration: TimeInterval) async {
        remainingEntryDuration = duration

        guard duration > 0 else {
            playbackStartedAt = nil
            return
        }

        playbackStartedAt = Date()
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        if !Task.isCancelled {
            await MainActor.run {
                self.advance()
            }
        }
    }

    private func remainingDuration(for entry: PlaylistEntry) -> TimeInterval {
        guard entry.duration > 0 else { return 0 }
        guard let playbackStartedAt, let remainingEntryDuration else {
            return entry.duration
        }

        let elapsed = Date().timeIntervalSince(playbackStartedAt)
        return max(0, remainingEntryDuration - elapsed)
    }

    private func loadPlaylists() -> [Playlist] {
        let context = persistence.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Playlist")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        request.fetchBatchSize = 20

        do {
            let results = try context.fetch(request)
            return results.compactMap { playlist(from: $0) }
        } catch {
            print("🟥 [PlaylistEngine] Failed to load playlists: \(error)")
            lastError = .persistenceError(error)
            return []
        }
    }

    private var lastScheduledPlaylistID: UUID?
    private var lastScheduledDate: Date?

    private func startScheduling() {
        scheduleTask?.cancel()
        scheduleTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

                // Check if any playlist is scheduled for now
                let now = Date()
                let playlistToStart = await MainActor.run { () -> Playlist? in
                    self.playlists.first { p in
                        guard let schedule = p.scheduleTime else { return false }

                        // Check if we already started this today within the last hour
                        if self.lastScheduledPlaylistID == p.id,
                           let lastDate = self.lastScheduledDate,
                           now.timeIntervalSince(lastDate) < 3600 {
                            return false
                        }

                        // Within 1 minute of schedule time
                        // We use hour and minute matching for daily scheduling
                        let calendar = Calendar.current
                        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)
                        let scheduleComponents = calendar.dateComponents([.hour, .minute], from: schedule)

                        return nowComponents.hour == scheduleComponents.hour &&
                            nowComponents.minute == scheduleComponents.minute
                    }
                }

                if let playlistToStart {
                    await MainActor.run {
                        self.lastScheduledPlaylistID = playlistToStart.id
                        self.lastScheduledDate = now
                        self.play(playlistToStart)
                    }
                }

                // Sleep for 30 seconds before next check
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
            }
        }
    }

    private static let entriesDecoder = JSONDecoder()

    private func playlist(from object: NSManagedObject) -> Playlist? {
        guard let id = object.value(forKey: "id") as? UUID,
              let name = object.value(forKey: "name") as? String,
              let entriesData = object.value(forKey: "entries") as? Data else {
            return nil
        }
        let entries = (try? Self.entriesDecoder.decode([PlaylistEntry].self, from: entriesData)) ?? []
        let scheduleTime = object.value(forKey: "scheduleTime") as? Date
        return Playlist(id: id, name: name, entries: entries, scheduleTime: scheduleTime)
    }
}
