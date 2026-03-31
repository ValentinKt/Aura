import SwiftUI

private func playlistDurationLabel(for duration: TimeInterval) -> String {
    let totalMinutes = max(1, Int(duration / 60))
    let hours = totalMinutes / 60
    let minutes = totalMinutes % 60

    switch (hours, minutes) {
    case (0, let minutes):
        return "\(minutes)m"
    case (let hours, 0):
        return "\(hours)h"
    default:
        return "\(hours)h \(minutes)m"
    }
}

struct PlaylistView: View {
    @Bindable var appModel: AppModel
    @State private var showEditor: Bool = false
    @State private var selectedPlaylist: Playlist?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            if let activePlaylist = activePlaylist {
                activePlaylistSection(activePlaylist)
            }

            playlistList
        }
        .padding(24)
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: appModel.playlistViewModel.state)
        .sheet(isPresented: $showEditor) {
            PlaylistEditorView(appModel: appModel, playlist: selectedPlaylist)
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Your Playlists")
                    .font(.system(size: 28, weight: .bold))
                Text("Curated soundscapes for your day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: {
                selectedPlaylist = nil
                showEditor = true
            }) {
                createButtonLabel
            }
            .buttonStyle(.plain)
        }
    }

    private var activePlaylist: Playlist? {
        switch appModel.playlistViewModel.state {
        case .playing(let playlist, _), .paused(let playlist, _):
            return playlist
        default:
            return nil
        }
    }

    private var currentIndex: Int {
        switch appModel.playlistViewModel.state {
        case .playing(_, let index), .paused(_, let index):
            return index
        default:
            return 0
        }
    }

    private func activePlaylistSection(_ playlist: Playlist) -> some View {
        GlassEffectContainer(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    statusPill
                    Spacer()
                    Text("\(currentIndex + 1) of \(playlist.entries.count)")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(playlist.name)
                        .font(.title2.weight(.bold))
                    Text(currentEntryTitle)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .bottom, spacing: 24) {
                    playbackControls
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(activeEntryDurationLabel)
                            .font(.headline)
                        Text("Current segment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(24)
            .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, variant: .regular)
            .shadow(color: .black.opacity(reduceTransparency ? 0.08 : 0.15), radius: 30, y: 15)
        }
    }

    private var playbackControls: some View {
        GlassEffectContainer {
            HStack(spacing: 10) {
                controlButton(systemName: "backward.fill", label: "Previous") {
                    appModel.playlistViewModel.previous()
                }

                controlButton(systemName: isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause Playlist" : "Resume Playlist", emphasized: true) {
                    if isPlaying {
                        appModel.playlistViewModel.pause()
                    } else {
                        appModel.playlistViewModel.resume()
                    }
                }

                controlButton(systemName: "forward.fill", label: "Next") {
                    appModel.playlistViewModel.skip()
                }

                controlButton(systemName: "shuffle", label: "Shuffle", isSelected: appModel.playlistViewModel.shuffleEnabled) {
                    appModel.playlistViewModel.toggleShuffle()
                }

                controlButton(systemName: repeatIcon, label: "Repeat", isSelected: appModel.playlistViewModel.repeatMode != .off) {
                    appModel.playlistViewModel.cycleRepeatMode()
                }
            }
        }
    }

    private var isPlaying: Bool {
        if case .playing = appModel.playlistViewModel.state {
            return true
        }
        return false
    }

    private var repeatIcon: String {
        switch appModel.playlistViewModel.repeatMode {
        case .off: return "repeat"
        case .one: return "repeat.1"
        case .all: return "repeat"
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            if isPlaying {
                HStack(spacing: 3) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.accentColor)
                            .frame(width: 3, height: 12)
                            .scaleEffect(y: isPlaying ? 1.0 : 0.35)
                            .animation(.spring(response: 0.45, dampingFraction: 0.72).repeatForever().delay(Double(index) * 0.08), value: isPlaying)
                    }
                }
            } else {
                Image(systemName: "pause.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }

            Text(isPlaying ? "Playing" : "Paused")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlass(Capsule(), interactive: false, variant: .regular)
    }

    private var currentEntryTitle: String {
        guard let entry = activeEntry else {
            return "Current segment unavailable"
        }

        if entry.customAudioPath != nil {
            return entry.name ?? "Custom Audio"
        }

        if let moodID = entry.moodID {
            return appModel.moodViewModel.mood(for: moodID)?.name ?? "Unknown Mood"
        }

        return "Invalid playlist entry"
    }

    private var activeEntryDurationLabel: String {
        guard let entry = activeEntry else {
            return "—"
        }

        return entry.duration <= 0 ? "Until skipped" : playlistDurationLabel(for: entry.duration)
    }

    private var activeEntry: PlaylistEntry? {
        guard let activePlaylist, activePlaylist.entries.indices.contains(currentIndex) else {
            return nil
        }

        return activePlaylist.entries[currentIndex]
    }

    private var playlistList: some View {
        ScrollView {
            GlassEffectContainer {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    ForEach(appModel.playlistViewModel.playlists) { playlist in
                        PlaylistCard(
                            playlist: playlist,
                            isActive: activePlaylist?.id == playlist.id,
                            isPlaying: activePlaylist?.id == playlist.id && isPlaying,
                            isPaused: activePlaylist?.id == playlist.id && !isPlaying,
                            onPlay: { appModel.playlistViewModel.play(playlist) },
                            onPauseResume: {
                                if activePlaylist?.id == playlist.id {
                                    if isPlaying {
                                        appModel.playlistViewModel.pause()
                                    } else {
                                        appModel.playlistViewModel.resume()
                                    }
                                }
                            },
                            onRestart: { appModel.playlistViewModel.play(playlist) },
                            onEdit: {
                                selectedPlaylist = playlist
                                showEditor = true
                            },
                            onDelete: { appModel.playlistViewModel.delete(id: playlist.id) }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var createButtonLabel: some View {
        if reduceTransparency {
            createButtonBase
                .background {
                    buttonShape.fill(.regularMaterial)
                }
        } else {
            createButtonBase
                .glassEffect(.regular.interactive(), in: buttonShape)
        }
    }

    private var createButtonBase: some View {
        Label("Create New", systemImage: "plus.circle.fill")
            .font(.headline)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    @ViewBuilder
    private func controlButton(
        systemName: String,
        label: String,
        emphasized: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(emphasized ? .title3.weight(.bold) : .callout.weight(.semibold))
                .foregroundStyle(isSelected ? Color.accentColor : .primary)
                .frame(width: emphasized ? 46 : 40, height: emphasized ? 46 : 40)
                .background {
                    if emphasized && reduceTransparency {
                        Circle().fill(.regularMaterial)
                    }
                }
                .liquidGlass(Circle(), interactive: true, variant: .regular)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

}

struct PlaylistCard: View {
    let playlist: Playlist
    let isActive: Bool
    let isPlaying: Bool
    let isPaused: Bool
    let onPlay: () -> Void
    let onPauseResume: () -> Void
    let onRestart: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardContent
            Spacer(minLength: 0)
            footerActions
        }
        .frame(height: 180)
        .background {
            if reduceTransparency {
                cardShape.fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: cardShape)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    isActive ? LinearGradient(colors: [Color.accentColor.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing) : LinearGradient(
                        colors: [.white.opacity(isHovered ? 0.4 : 0.2), .clear, .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isActive ? 2 : 0.5
                )
                .blendMode(isActive ? .normal : .plusLighter)
        }
        .contentShape(cardShape)
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHovered)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: isActive ? "waveform" : "music.note.list")
                    .font(.title2)
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .symbolEffect(.bounce, value: isActive)

                Spacer()

                if isActive {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playlist.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(playlistMetadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    private var footerActions: some View {
        HStack {
            Button(action: isActive ? onPauseResume : onPlay) {
                playButtonLabel
            }
            .buttonStyle(.plain)

            if isActive {
                Button(action: onRestart) {
                    restartButtonLabel
                }
                .buttonStyle(.plain)
            }

            Menu {
                if isActive {
                    Button(action: onRestart) {
                        Label("Restart", systemImage: "arrow.counterclockwise")
                    }
                }
                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil")
                }
                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                menuButtonLabel
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var playButtonLabel: some View {
        if isActive {
            if reduceTransparency {
                playButtonBase
                    .background {
                        buttonShape.fill(.regularMaterial)
                    }
            } else {
                playButtonBase
                    .glassEffect(.regular.interactive(), in: buttonShape)
            }
        } else {
            playButtonBase
                .background(Color.accentColor.opacity(0.9))
        }
    }

    private var playButtonBase: some View {
        HStack {
            Image(systemName: playButtonIcon)
            Text(playButtonTitle)
        }
        .font(.subheadline.bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .foregroundStyle(isActive ? Color.primary : Color.white)
    }

    @ViewBuilder
    private var restartButtonLabel: some View {
        if reduceTransparency {
            restartButtonBase
                .background {
                    buttonShape.fill(.regularMaterial)
                }
        } else {
            restartButtonBase
                .glassEffect(.regular.interactive(), in: buttonShape)
        }
    }

    private var restartButtonBase: some View {
        Image(systemName: "arrow.counterclockwise")
            .font(.headline)
            .frame(width: 42, height: 42)
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private var menuButtonLabel: some View {
        if reduceTransparency {
            menuButtonBase
                .background {
                    buttonShape.fill(.regularMaterial)
                }
        } else {
            menuButtonBase
                .glassEffect(.regular.interactive(), in: buttonShape)
        }
    }

    private var menuButtonBase: some View {
        Image(systemName: "ellipsis")
            .font(.headline)
            .frame(width: 36, height: 36)
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var playButtonIcon: String {
        if isPlaying {
            return "pause.fill"
        }

        if isPaused {
            return "play.fill"
        }

        return "play.fill"
    }

    private var playButtonTitle: String {
        if isPlaying {
            return "Pause"
        }

        if isPaused {
            return "Resume"
        }

        return "Play"
    }

    private var playlistMetadata: String {
        let totalDuration = playlist.entries.reduce(0) { partialResult, entry in
            partialResult + max(entry.duration, 0)
        }

        let durationText = totalDuration > 0 ? playlistDurationLabel(for: totalDuration) : "Flexible"
        return "\(playlist.entries.count) segments • \(durationText)"
    }
}
