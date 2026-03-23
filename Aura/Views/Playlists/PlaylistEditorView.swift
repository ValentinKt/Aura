import SwiftUI
import UniformTypeIdentifiers

struct PlaylistEditorView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    let originalPlaylist: Playlist?
    @State private var name: String
    @State private var entries: [PlaylistEntry]
    @State private var isImportingAudio = false

    init(appModel: AppModel, playlist: Playlist?) {
        self.appModel = appModel
        self.originalPlaylist = playlist
        _name = State(initialValue: playlist?.name ?? "")
        _entries = State(initialValue: playlist?.entries ?? [])
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    entriesSection
                }
                .padding(24)
            }
            
            footer
        }
        .frame(width: 480, height: 560)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fileImporter(
            isPresented: $isImportingAudio,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
        }
    }
    
    private var header: some View {
        HStack {
            Text(originalPlaylist == nil ? "New Playlist" : "Edit Playlist")
                .font(.headline)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background {
            if reduceTransparency {
                Rectangle()
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
        }
    }
    
    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playlist Name")
                .font(.subheadline)
                .bold()
            TextField("Focus Mix, Rainy Afternoon...", text: $name)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
        }
    }
    
    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Segments")
                    .font(.subheadline)
                    .bold()
                Spacer()
                addEntryMenu
            }
            
            if entries.isEmpty {
                emptyEntriesView
            } else {
                ForEach($entries) { $entry in
                    entryRow(for: $entry)
                }
            }
        }
    }
    
    private var addEntryMenu: some View {
        Menu {
            Section("Moods") {
                ForEach(appModel.moodViewModel.moods) { mood in
                    Button(mood.name) {
                        entries.append(PlaylistEntry(moodID: mood.id, duration: 1800, transitionStyle: .crossfade))
                    }
                }
            }
            
            Section("Local Music") {
                Button(action: { isImportingAudio = true }) {
                    Label("Add from Mac...", systemImage: "music.note")
                }
            }
        } label: {
            Label("Add Segment", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
    
    private var emptyEntriesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.list")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("No segments added yet")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func entryRow(for entry: Binding<PlaylistEntry>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                if let audioPath = entry.wrappedValue.customAudioPath {
                    Text(entry.wrappedValue.name ?? "Custom Audio")
                        .font(.body)
                        .bold()
                    Text(URL(fileURLWithPath: audioPath).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let moodID = entry.wrappedValue.moodID {
                    Text(appModel.moodViewModel.mood(for: moodID)?.name ?? "Unknown Mood")
                        .font(.body)
                        .bold()
                } else {
                    Text("Invalid Entry")
                        .font(.body)
                        .bold()
                }
                
                HStack {
                    Picker("Duration", selection: entry.duration) {
                        Text("15 min").tag(TimeInterval(900))
                        Text("30 min").tag(TimeInterval(1800))
                        Text("45 min").tag(TimeInterval(2700))
                        Text("1 hour").tag(TimeInterval(3600))
                        Text("2 hours").tag(TimeInterval(7200))
                        Text("Manual").tag(TimeInterval(0))
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 80)
                    
                    Text("•")
                        .foregroundStyle(.secondary)
                    
                    Picker("Style", selection: entry.transitionStyle) {
                        ForEach(TransitionStyle.allCases, id: \.self) { style in
                            Text(style.rawValue.capitalized).tag(style)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 80)
                }
            }
            
            Spacer()
            
            Button(role: .destructive, action: {
                if let path = entry.wrappedValue.customAudioPath {
                    CustomAssetManager.removeCustomAudio(atPath: path)
                }
                entries.removeAll { $0.id == entry.wrappedValue.id }
            }) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
    
    private func handleAudioImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let savedPath = try CustomAssetManager.saveCustomAudio(from: url)
                let name = url.deletingPathExtension().lastPathComponent
                entries.append(PlaylistEntry(
                    customAudioPath: savedPath,
                    name: name,
                    duration: 1800,
                    transitionStyle: .crossfade
                ))
            } catch {
                print("🟥 [PlaylistEditorView] Failed to save custom audio: \(error)")
            }
        case .failure(let error):
            print("🟥 [PlaylistEditorView] Audio import failed: \(error)")
        }
    }
    
    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            
            Button(action: save) {
                Text("Save Playlist")
                    .bold()
                    .frame(width: 120)
                    .padding(.vertical, 10)
                    .background(name.isEmpty || entries.isEmpty ? Color.gray.opacity(0.3) : Color.accentColor.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(.white.opacity(0.15), lineWidth: 0.5)
                    }
            }
            .buttonStyle(.plain)
            .disabled(name.isEmpty || entries.isEmpty)
        }
        .padding(24)
        .background {
            if reduceTransparency {
                Rectangle()
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: Rectangle())
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
        }
    }
    
    private func save() {
        let playlist = Playlist(
            id: originalPlaylist?.id ?? UUID(),
            name: name,
            entries: entries,
            scheduleTime: originalPlaylist?.scheduleTime
        )
        appModel.playlistViewModel.save(playlist)
        dismiss()
    }
}
