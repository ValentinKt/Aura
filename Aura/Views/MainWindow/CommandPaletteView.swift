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
            GlassEffectContainer {
                paletteBase
                    .glassEffect(.regular, in: paletteShape)
            }
        }
    }

    private var paletteBase: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image("AuraCircle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .shadow(color: .cyan.opacity(0.4), radius: 8, x: 0, y: 0)

                TextField("Search moods, playlists, settings...", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .font(.system(size: 22, weight: .light))
                    .onChange(of: query) {
                        selectedIndex = 0
                    }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Divider()
                .opacity(0.5)

            if filteredItems.isEmpty {
                VStack(spacing: 16) {
                    Image("AuraCircle")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .opacity(0.3)
                    Text("No results for \"\(query)\"")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(Array(filteredItems.enumerated()), id: \.offset) { index, item in
                                CommandItemRow(item: item, isSelected: index == selectedIndex)
                                    .id(index)
                                    .onTapGesture {
                                        item.action()
                                        appModel.showCommandPalette = false
                                    }
                            }
                        }
                        .padding(12)
                    }
                    .frame(height: 360)
                    .onChange(of: selectedIndex) {
                        proxy.scrollTo(selectedIndex, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 600)
        .shadow(color: .black.opacity(0.4), radius: 50, y: 25)
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            appModel.showCommandPalette = false
        }
        .onKeyDown { event in
            handleKeyEvent(event)
        }
    }

    private var paletteShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
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
        rowBase
            .background {
                if isSelected {
                    rowShape
                        .fill(Color.accentColor.opacity(0.2))
                }
            }
    }

    private var rowBase: some View {
        HStack(spacing: 16) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24, height: 24)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.8)))

                Text(item.category)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.secondary) : AnyShapeStyle(.secondary.opacity(0.7)))
            }

            Spacer()

            if isSelected {
                Image(systemName: "return")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
    }

    private var rowShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
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
