//
//  ContentView.swift
//  Aura
//
//  Created by Valentin on 3/13/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var selectedTab: Tab? = .moods
    @State private var isMoodsExpanded = true
    @State private var isPlaylistsExpanded = true
    @State private var selectedPlaylistID: UUID?

    enum Tab: String, CaseIterable, Identifiable {
        case moods, playlists, travel, settings
        var id: String { rawValue }
    }

    var body: some View {
        @Bindable var appModel = appModel
        mainContent(appModel: appModel)
    }

    @ViewBuilder
    private func mainContent(appModel: AppModel) -> some View {
        @Bindable var appModel = appModel
        ZStack {
            // Background Layer
            if let tab = selectedTab {
                if tab == .moods || tab == .travel || tab == .playlists || tab == .settings {
                    WallpaperPreviewView(appModel: appModel, showOverlay: false)
                        .ignoresSafeArea()
                        .overlay(Color.black.opacity(0.4))
                        .overlay {
                            if tab != .moods {
                                backgroundGlassOverlay
                            }
                        }
                } else {
                    fallbackGlassBackground
                        .ignoresSafeArea()
                }
            } else {
                fallbackGlassBackground
                    .ignoresSafeArea()
            }

            // Foreground Layout
            HStack(spacing: 0) {
                floatingSidebar
                    .frame(width: 240)
                    .padding(.leading, 24)
                    .padding(.vertical, 24)
                
                if let selectedTab {
                    contentLayer(for: selectedTab)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Text("Select a category")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .opacity(appModel.showImmersive ? 0 : 1)
            .animation(.easeInOut(duration: 0.5), value: appModel.showImmersive)
        }
        .frame(minWidth: 950, minHeight: 800)
        .overlay {
            if appModel.showCommandPalette {
                CommandPaletteView(appModel: appModel)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            if appModel.showImmersive {
                ImmersiveModeView(appModel: appModel)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $isShowingCreateMood) {
            CreateMoodView(appModel: appModel)
        }
        .focusable()
        .onKeyPress(.rightArrow) {
            appModel.moodViewModel.selectNextMood()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            appModel.moodViewModel.selectPreviousMood()
            return .handled
        }
        .onKeyPress(.downArrow) {
            appModel.moodViewModel.selectNextSubtheme()
            return .handled
        }
        .onKeyPress(.upArrow) {
            appModel.moodViewModel.selectPreviousSubtheme()
            return .handled
        }
    }

    @ViewBuilder
    private var floatingSidebar: some View {
        sidebarContent
            .padding(.top, 16)
            .padding(.bottom, 36)
            .padding(.horizontal, 24)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconForSubtheme(_ subtheme: String) -> String {
        switch subtheme.lowercased() {
        case "aurora": return "sparkles"
        case "autumn": return "leaf.fill"
        case "coffeeshop": return "cup.and.saucer.fill"
        case "color": return "paintpalette.fill"
        case "concentration": return "brain.head.profile"
        case "deepfocus": return "target"
        case "desert": return "sun.dust.fill"
        case "flow": return "water.waves"
        case "forest": return "tree.fill"
        case "fractal": return "hurricane"
        case "mindfulness": return "figure.mind.and.body"
        case "rest": return "moon.zzz.fill"
        case "retro": return "gamecontroller.fill"
        case "storm": return "cloud.bolt.rain.fill"
        case "waterfall": return "drop.fill"
        case "wild": return "pawprint.fill"
        default: return "circle.fill"
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Branded Header — now a Liquid Glass pill ──────────────────
            HStack(spacing: 12) {
                Image("AuraCircle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.5)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                Text("Aura")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            // Liquid Glass pill behind the brand mark
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(.bottom, 24)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Moods Section
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { isMoodsExpanded.toggle() }
                        } label: {
                            HStack {
                                Label("Moods", systemImage: "sparkles")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .rotationEffect(.degrees(isMoodsExpanded ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        if isMoodsExpanded {
                            LazyVStack(spacing: 2) {
                                ForEach(appModel.moodViewModel.subthemes, id: \.self) { subtheme in
                                    SidebarItem(
                                        title: subtheme,
                                        isSelected: selectedTab == .moods && appModel.moodViewModel.selectedSubtheme == subtheme,
                                        systemImage: iconForSubtheme(subtheme),
                                        action: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                selectedTab = .moods
                                            }
                                            appModel.moodViewModel.selectedSubtheme = subtheme
                                        }
                                    )
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }

                    // Playlists Section
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { isPlaylistsExpanded.toggle() }
                        } label: {
                            HStack {
                                Label("Playlists", systemImage: "music.note.list")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .rotationEffect(.degrees(isPlaylistsExpanded ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())

                        if isPlaylistsExpanded {
                            LazyVStack(spacing: 2) {
                                ForEach(appModel.playlistViewModel.playlists) { playlist in
                                    SidebarItem(
                                        title: playlist.name,
                                        isSelected: selectedTab == .playlists && selectedPlaylistID == playlist.id,
                                        systemImage: "music.note",
                                        action: {
                                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                                selectedTab = .playlists
                                                selectedPlaylistID = playlist.id
                                            }
                                        }
                                    )
                                }
                            }
                            .padding(.leading, 8)
                        }
                    }

                    // Library Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Library")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        GlassNavLink(
                            tab: .travel,
                            selectedTab: $selectedTab,
                            label: "Travel",
                            systemImage: "airplane"
                        )
                    }

                    // App Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("App")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.6))
                            .padding(.horizontal, 16)
                            .padding(.top, 8)

                        GlassNavLink(
                            tab: .settings,
                            selectedTab: $selectedTab,
                            label: "Settings",
                            systemImage: "gearshape.fill"
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func contentLayer(for tab: Tab) -> some View {
        // Content Layer
        switch tab {
        case .moods:
            mainMoodView
        case .playlists:
            PlaylistView(appModel: appModel)
        case .travel:
            TravelView(appModel: appModel)
        case .settings:
            SettingsView(appModel: appModel)
        }
    }

    private var mainMoodView: some View {
        ScrollViewReader { proxy in
            let moodListHeight: CGFloat = 380
            VStack(spacing: 0) {
                headerView

                ScrollView {
                    MoodSelectorView(appModel: appModel)
                        .padding(.bottom, 24)
                }
                .frame(height: moodListHeight)
                .clipped()
                .onAppear {
                    if let subtheme = appModel.moodViewModel.currentMood?.subtheme {
                        proxy.scrollTo(subtheme, anchor: .top)
                    }
                }
                .onChange(of: appModel.moodViewModel.selectedSubtheme) { _, newValue in
                    if let subtheme = newValue {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            proxy.scrollTo(subtheme, anchor: .top)
                        }
                    }
                }
                .onChange(of: appModel.moodViewModel.currentMood) { _, newValue in
                    if let mood = newValue {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            proxy.scrollTo(mood.subtheme, anchor: .top)
                        }
                    }
                }

                // ── Mixer panel — Liquid Glass card ───────────────────────
                SoundLayerMixerView(appModel: appModel, isScrollable: true)
                    .padding(.top, 16)
                    .padding(.bottom, 36)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
                    .background {
                        if reduceTransparency {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.regularMaterial)
                        } else {
                            Color.clear
                                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
            }
        }
    }

    @State private var isShowingCreateMood = false
    @State private var isHoveringNewMood = false

    private var headerView: some View {
        HStack {
            // ── Title card ──────────────────────
            VStack(alignment: .leading, spacing: 4) {
                Text("CURRENT ATMOSPHERE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                    .kerning(1.2)

                Text(appModel.moodViewModel.currentMood?.name ?? "Select a Mood")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.vertical, 22)

            Spacer()

            HStack(spacing: 16) {
                // New Mood button
                Button {
                    isShowingCreateMood = true
                } label: {
                    newMoodButtonLabel
                }
                .buttonStyle(.plain)
                .focusable(false)
                .scaleEffect(isHoveringNewMood ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHoveringNewMood)
                .onHover { isHoveringNewMood = $0 }
                
                // Search button
                Button {
                    appModel.showCommandPalette.toggle()
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .help("Search (⌘K)")

                // Settings button
                Button {
                    selectedTab = .settings
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .help("Settings")
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 60)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var backgroundGlassOverlay: some View {
        if reduceTransparency {
            Rectangle()
                .fill(.regularMaterial.opacity(0.35))
        } else {
            Color.clear
                .glassEffect(.clear, in: Rectangle())
        }
    }

    @ViewBuilder
    private var fallbackGlassBackground: some View {
        if reduceTransparency {
            Rectangle()
                .fill(.regularMaterial)
        } else {
            Color.clear
                .glassEffect(.regular, in: Rectangle())
        }
    }

    @ViewBuilder
    private var newMoodButtonLabel: some View {
        if reduceTransparency {
            newMoodButtonBase
                .background {
                    newMoodButtonShape.fill(.regularMaterial)
                }
                .contentShape(newMoodButtonShape)
        } else {
            newMoodButtonBase
                .glassEffect(.regular.interactive(), in: newMoodButtonShape)
                .contentShape(newMoodButtonShape)
        }
    }

    private var newMoodButtonBase: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 14))
            Text("New Mood")
                .font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
    }

    private var newMoodButtonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
    }
}

// MARK: - GlassNavLink
/// NavigationLink replacement that shows a Liquid Glass background
/// both when hovered and when selected, matching the SidebarItem style.
private struct GlassNavLink: View {
    let tab: ContentView.Tab
    @Binding var selectedTab: ContentView.Tab?
    let label: String
    let systemImage: String

    @State private var isHovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var isSelected: Bool { selectedTab == tab }
    private var showGlass: Bool { isSelected || isHovering }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.6))
                    .frame(width: 20)

                Text(label)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if showGlass {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? .regularMaterial : .ultraThinMaterial)
                    } else {
                        Color.clear
                            .glassEffect(isSelected ? .regular.interactive() : .clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.spring(response: 0.25, dampingFraction: 0.75), value: showGlass)
        .padding(.horizontal, 12)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .onHover { isHovering = $0 }
    }
}

// MARK: - SidebarItem
struct SidebarItem: View {
    let title: String
    let isSelected: Bool
    let systemImage: String?
    let action: () -> Void
    @State private var isHovering = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(title: String, isSelected: Bool, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isSelected ? Color.accentColor : .white.opacity(0.6))
                        .frame(width: 20)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.2))
                        .frame(width: 4, height: 4)
                        .padding(.leading, 8)
                        .padding(.trailing, 8)
                }

                Text(title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : .white.opacity(0.8))
                    .lineLimit(1)

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                if isSelected || isHovering {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? .regularMaterial : .ultraThinMaterial)
                    } else {
                        Color.clear
                            .glassEffect(isSelected ? .regular.interactive() : .clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovering)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
