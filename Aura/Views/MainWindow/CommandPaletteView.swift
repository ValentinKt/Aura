import SwiftUI

struct CommandPaletteView: View {
    @Bindable var appModel: AppModel
    @State private var query: String = ""
    @State private var selectedIndex: Int = 0
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        paletteSurface
    }

    @ViewBuilder
    private var paletteSurface: some View {
        if reduceTransparency {
            paletteBase
                .background {
                    paletteShape.fill(.regularMaterial)
                }
        } else {
            paletteBase
                .glassEffect(.regular.interactive(), in: paletteShape)
        }
    }

    private var paletteBase: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.title3)
                
                TextField("Search moods, playlists, settings...", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(.title3)
                    .onChange(of: query) {
                        selectedIndex = 0
                    }
            }
            .padding(20)
            
            Divider()
            
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "questionmark.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No results for \"\(query)\"")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                ScrollViewReader { proxy in
                    List(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                        CommandItemRow(item: item, isSelected: index == selectedIndex)
                            .id(index)
                            .onTapGesture {
                                item.action()
                                appModel.showCommandPalette = false
                            }
                    }
                    .listStyle(.plain)
                    .frame(height: 300)
                    .onChange(of: selectedIndex) {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 500)
        .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
        .onAppear {
            isFocused = true
        }
        .onKeyDown { event in
            handleKeyEvent(event)
        }
    }

    private var paletteShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private func handleKeyEvent(_ event: NSEvent) {
        switch event.keyCode {
        case 125: // Down arrow
            selectedIndex = min(filteredItems.count - 1, selectedIndex + 1)
        case 126: // Up arrow
            selectedIndex = max(0, selectedIndex - 1)
        case 36: // Enter
            if selectedIndex < filteredItems.count {
                filteredItems[selectedIndex].action()
                appModel.showCommandPalette = false
            }
        case 53: // Escape
            appModel.showCommandPalette = false
        default:
            break
        }
    }

    private var filteredItems: [CommandItem] {
        let items = commandItems
        if query.isEmpty {
            return items
        }
        
        let lowerQuery = query.lowercased()
        
        // Priority 1: Exact prefix match
        let prefixMatches = items.filter { $0.title.lowercased().hasPrefix(lowerQuery) }
        
        // Priority 2: Case-insensitive contains match (excluding prefix matches)
        let containsMatches = items.filter { 
            $0.title.lowercased().contains(lowerQuery) && 
            !$0.title.lowercased().hasPrefix(lowerQuery) 
        }
        
        return prefixMatches + containsMatches
    }

    private var commandItems: [CommandItem] {
        var items: [CommandItem] = []
        
        // Moods
        items.append(contentsOf: appModel.moodViewModel.moods.map { mood in
            CommandItem(id: "mood-\(mood.id)", title: "Mood: \(mood.name)", category: "Moods", icon: "sparkles") {
                appModel.moodViewModel.selectMood(mood)
            }
        })
        
        // Playlists
        items.append(contentsOf: appModel.playlistViewModel.playlists.map { playlist in
            CommandItem(id: "playlist-\(playlist.id.uuidString)", title: "Playlist: \(playlist.name)", category: "Playlists", icon: "music.note.list") {
                appModel.playlistViewModel.play(playlist)
            }
        })
        
        // Settings/Global
        items.append(CommandItem(id: "toggle-weather", title: "Toggle Weather Sync", category: "Settings", icon: "cloud.sun") {
            appModel.toggleWeatherSync(!appModel.settingsViewModel.settings.weatherSyncEnabled)
        })
        
        items.append(CommandItem(id: "open-settings", title: "Open Settings", category: "Settings", icon: "gearshape") {
            // Logic to open settings if needed
        })

        items.append(CommandItem(id: "toggle-immersive", title: "Toggle Immersive Mode", category: "View", icon: "macwindow.on.rectangle") {
            appModel.showImmersive.toggle()
        })
        
        return items
    }
}

private struct CommandItem: Identifiable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let action: () -> Void
}

private struct CommandItemRow: View {
    let item: CommandItem
    let isSelected: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        rowSurface
    }

    @ViewBuilder
    private var rowSurface: some View {
        if isSelected {
            if reduceTransparency {
                rowBase
                    .background {
                        rowShape.fill(.regularMaterial)
                    }
            } else {
                rowBase
                    .glassEffect(.regular.interactive(), in: rowShape)
            }
        } else {
            rowBase
        }
    }

    private var rowBase: some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .frame(width: 24, height: 24)
                .foregroundStyle(isSelected ? .white : .accentColor)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .primary)
                
                Text(item.category)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }
}

// MARK: - Key Events Extension
extension View {
    func onKeyDown(perform action: @escaping (NSEvent) -> Void) -> some View {
        self.background(KeyEventView(action: action))
    }
}

private struct KeyEventView: NSViewRepresentable {
    let action: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyEventNSView()
        view.action = action
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private class KeyEventNSView: NSView {
    var action: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        action?(event)
    }
}
