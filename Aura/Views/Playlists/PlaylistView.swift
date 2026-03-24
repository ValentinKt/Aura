import SwiftUI

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
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("NOW PLAYING")
                    .font(.caption.bold())
                    .tracking(1.2)
                    .foregroundStyle(Color.accentColor)
                
                Spacer()
                
                if isPlaying {
                    HStack(spacing: 3) {
                        ForEach(0..<4) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.accentColor)
                                .frame(width: 2, height: 12)
                                .scaleEffect(y: isPlaying ? 1.0 : 0.4)
                                .animation(.easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.1), value: isPlaying)
                        }
                    }
                }
            }
            
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(playlist.name)
                        .font(.title2)
                        .bold()
                    
                    let entry = playlist.entries[currentIndex]
                    Group {
                        if entry.customAudioPath != nil {
                            Text("Current: \(entry.name ?? "Custom Audio")")
                        } else if let moodID = entry.moodID {
                            let mood = appModel.moodViewModel.mood(for: moodID)
                            Text("Current: \(mood?.name ?? "Unknown Mood")")
                        } else {
                            Text("Current: Invalid Entry")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                playbackControls
            }
            .padding(24)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 30, y: 15)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(action: { appModel.playlistViewModel.previous() }) {
                Image(systemName: "backward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Button(action: {
                if case .playing = appModel.playlistViewModel.state {
                    appModel.playlistViewModel.pause()
                } else {
                    appModel.playlistViewModel.resume()
                }
            }) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 24))
            }
            .buttonStyle(.plain)
            
            Button(action: { appModel.playlistViewModel.skip() }) {
                Image(systemName: "forward.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            
            Divider().frame(height: 24)
            
            Button(action: { appModel.playlistViewModel.toggleShuffle() }) {
                Image(systemName: "shuffle")
                    .foregroundStyle(appModel.playlistViewModel.shuffleEnabled ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            Button(action: { appModel.playlistViewModel.cycleRepeatMode() }) {
                Image(systemName: repeatIcon)
                    .foregroundStyle(appModel.playlistViewModel.repeatMode != .off ? Color.accentColor : .secondary)
            }
            .buttonStyle(.plain)
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
    
    private var playlistList: some View {
        ScrollView {
            GlassEffectContainer {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 16) {
                    ForEach(appModel.playlistViewModel.playlists) { playlist in
                        PlaylistCard(
                            playlist: playlist,
                            isActive: activePlaylist?.id == playlist.id,
                            onPlay: { appModel.playlistViewModel.play(playlist) },
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
}

struct PlaylistCard: View {
    let playlist: Playlist
    let isActive: Bool
    let onPlay: () -> Void
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
                
                Text("\(playlist.entries.count) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
    
    private var footerActions: some View {
        HStack {
            Button(action: onPlay) {
                playButtonLabel
            }
            .buttonStyle(.plain)
            
            Menu {
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
            Image(systemName: isActive ? "arrow.counterclockwise" : "play.fill")
            Text(isActive ? "Restart" : "Play")
        }
        .font(.subheadline.bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .foregroundStyle(isActive ? Color.primary : Color.white)
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
}
