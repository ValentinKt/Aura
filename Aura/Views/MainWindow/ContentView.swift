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
    @State private var isMoodsExpanded = false
    @State private var isPlaylistsExpanded = false
    @State private var selectedPlaylistID: UUID?
    @State private var moodScrollRequest: MoodScrollRequest?

    enum Tab: String, CaseIterable, Identifiable {
        case moods, playlists, settings
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
            ContentBackgroundView(snapshot: contentBackgroundSnapshot)
                .equatable()

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
        .frame(minWidth: 1050, minHeight: 900)
        .overlay {
            if appModel.showCommandPalette {
                ZStack {
                    Color.black.opacity(0.001)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation {
                                appModel.showCommandPalette = false
                            }
                        }

                    CommandPaletteView(appModel: appModel)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .zIndex(99)
            }
            if appModel.showImmersive {
                ImmersiveModeView(appModel: appModel)
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .sheet(isPresented: $appModel.showCreateMoodSheet) {
            createMoodSheet(appModel: appModel)
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

    private var contentBackgroundSnapshot: ContentBackgroundSnapshot {
        ContentBackgroundSnapshot(
            selectedTab: selectedTab,
            wallpaperPreview: WallpaperPreviewSnapshot(appModel: appModel)
        )
    }

    @ViewBuilder
    private var floatingSidebar: some View {
        sidebarContent
            .padding(.top, 16)
            .padding(.bottom, 36)
            .padding(.horizontal, 24)
            .liquidGlass(RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: false, variant: .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func iconForSubtheme(_ subtheme: String) -> String {
        switch subtheme.lowercased() {
        case "autumn": return "leaf.fill"
        case "coffeeshop": return "cup.and.saucer.fill"
        case "color": return "paintpalette.fill"
        case "concentration": return "brain.head.profile"
        case "deepfocus": return "target"
        case "desert": return "sun.dust.fill"
        case "energy": return "bolt.fill"
        case "flow": return "water.waves"
        case "forest": return "tree.fill"
        case "fractal": return "hurricane"
        case "aura": return "circle"
        case "create with ai": return "sparkles"
        case "dynamic desktop": return "desktopcomputer"
        case "image playground": return "wand.and.stars"
        case "mindfulness": return "figure.mind.and.body"
        case "rain": return "cloud.rain.fill"
        case "rest": return "moon.zzz.fill"
        case "retro": return "gamecontroller.fill"
        case "storm": return "cloud.bolt.rain.fill"
        case "time": return "clock.fill"
        case "waterfall": return "drop.fill"
        case "wild": return "pawprint.fill"
        case "website": return "globe"
        case "websites": return "globe"
        default: return "circle.fill"
        }
    }

    private var atmosphereSection: MoodSubthemeSection? {
        appModel.moodViewModel.subthemeSections.first { $0.title == "Atmospheres" }
    }

    private var secondaryMoodSections: [MoodSubthemeSection] {
        appModel.moodViewModel.subthemeSections.filter { $0.title != "Atmospheres" }
    }

    private var atmosphereMenuItems: [AtmosphereCarouselMenuItem] {
        (atmosphereSection?.subthemes ?? []).map { subtheme in
            AtmosphereCarouselMenuItem(
                id: subtheme,
                title: subtheme,
                systemImage: iconForSubtheme(subtheme)
            )
        }
    }

    @State private var lastSelectedAtmosphereID: String?
    @State private var pendingAtmosphereID: String?

    private var selectedAtmosphereID: Binding<String?> {
        Binding(
            get: {
                if let visibleSubtheme = appModel.moodViewModel.visibleSubtheme,
                   atmosphereMenuItems.contains(where: { $0.id == visibleSubtheme }) {
                    return visibleSubtheme
                }

                if let pendingAtmosphereID,
                   atmosphereMenuItems.contains(where: { $0.id == pendingAtmosphereID }) {
                    return pendingAtmosphereID
                }

                let selectedSubtheme = appModel.moodViewModel.selectedSubtheme
                if let selectedSubtheme,
                   atmosphereMenuItems.contains(where: { $0.id == selectedSubtheme }) {
                    return selectedSubtheme
                }

                if let last = lastSelectedAtmosphereID {
                    return last
                }

                if let currentSubtheme = appModel.moodViewModel.currentMood?.subtheme,
                   atmosphereMenuItems.contains(where: { $0.id == currentSubtheme }) {
                    return currentSubtheme
                }

                return atmosphereMenuItems.first?.id
            },
            set: { newValue in
                guard let newValue else { return }

                if atmosphereMenuItems.contains(where: { $0.id == newValue }) {
                    lastSelectedAtmosphereID = newValue
                }

                if newValue == appModel.moodViewModel.visibleSubtheme {
                    pendingAtmosphereID = nil
                    return
                }

                pendingAtmosphereID = newValue
                selectMoodSubtheme(newValue, shouldRequestScroll: true)
            }
        )
    }

    private func selectMoodSubtheme(_ subtheme: String, shouldRequestScroll: Bool = false) {
        let didChangeSelection = appModel.moodViewModel.selectedSubtheme != subtheme

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedTab = .moods
        }

        if didChangeSelection {
            appModel.moodViewModel.selectedSubtheme = subtheme
        }

        if shouldRequestScroll {
            moodScrollRequest = MoodScrollRequest(subtheme: subtheme)
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
            .liquidGlass(RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: false, variant: .clear)
            .padding(.bottom, 24)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // Moods Section
                    VStack(alignment: .leading, spacing: 8) {
                        Button {
                            withAnimation { isMoodsExpanded.toggle() }
                        } label: {
                            HStack {
                                Label("Moods", systemImage: "swatchpalette.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.8))
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .rotationEffect(.degrees(isMoodsExpanded ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if isMoodsExpanded {
                            LazyVStack(alignment: .leading, spacing: 18) {
                                if !atmosphereMenuItems.isEmpty {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("ATMOSPHERES")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .kerning(1.2)
                                            .padding(.horizontal, 16)

                                        AtmospheresWheelMenu(
                                            items: atmosphereMenuItems,
                                            selectedID: selectedAtmosphereID,
                                            onItemActivated: { subtheme in
                                                selectMoodSubtheme(subtheme, shouldRequestScroll: true)
                                            }
                                        )
                                        .frame(height: AtmospheresWheelMenu.viewportHeight)
                                    }
                                }

                                ForEach(secondaryMoodSections) { section in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(section.title.uppercased())
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(.white.opacity(0.45))
                                            .padding(.horizontal, 16)

                                        ForEach(section.subthemes, id: \.self) { subtheme in
                                            SidebarItem(
                                                title: subtheme,
                                                isSelected: selectedTab == .moods && appModel.moodViewModel.selectedSubtheme == subtheme,
                                                systemImage: iconForSubtheme(subtheme),
                                                action: {
                                                    selectMoodSubtheme(subtheme, shouldRequestScroll: true)
                                                }
                                            )
                                        }
                                    }
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
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .rotationEffect(.degrees(isPlaylistsExpanded ? 90 : 0))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

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
        case .settings:
            SettingsView(appModel: appModel)
        }
    }

    private var mainMoodView: some View {
        ScrollViewReader { proxy in
            let moodListHeight: CGFloat = 480
            VStack(spacing: 0) {
                headerView

                ScrollView {
                    MoodSelectorView(appModel: appModel)
                        .padding(.bottom, 24)
                }
                .frame(height: moodListHeight)
                .clipped()
                .onAppear {
                    if let requestedSubtheme = moodScrollRequest?.subtheme {
                        proxy.scrollTo(requestedSubtheme, anchor: .top)
                    } else if let selectedSubtheme = appModel.moodViewModel.selectedSubtheme {
                        proxy.scrollTo(selectedSubtheme, anchor: .top)
                    } else if let subtheme = appModel.moodViewModel.currentMood?.subtheme {
                        proxy.scrollTo(subtheme, anchor: .top)
                    }
                }
                .onChange(of: moodScrollRequest) { _, newValue in
                    guard let subtheme = newValue?.subtheme else {
                        return
                    }

                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                        proxy.scrollTo(subtheme, anchor: .top)
                    }
                }
                .onChange(of: appModel.moodViewModel.selectedSubtheme) { _, newValue in
                    if let subtheme = newValue {
                        if atmosphereMenuItems.contains(where: { $0.id == subtheme }) {
                            lastSelectedAtmosphereID = subtheme
                        }
                        guard moodScrollRequest?.subtheme != subtheme else {
                            return
                        }
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                            proxy.scrollTo(subtheme, anchor: .top)
                        }
                    }
                }
                .onChange(of: appModel.moodViewModel.visibleSubtheme) { _, newValue in
                    guard let subtheme = newValue else {
                        return
                    }

                    pendingAtmosphereID = nil

                    if atmosphereMenuItems.contains(where: { $0.id == subtheme }) {
                        lastSelectedAtmosphereID = subtheme
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
                    .liquidGlass(RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: false, variant: .clear)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
            }
        }
    }

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
                    appModel.showCreateMoodSheet = true
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
                .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true, variant: .clear)
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
                .liquidGlass(RoundedRectangle(cornerRadius: 14, style: .continuous), interactive: true, variant: .clear)
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
        newMoodButtonBase
            .liquidGlass(newMoodButtonShape, interactive: true, variant: .clear)
            .contentShape(newMoodButtonShape)
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

    @ViewBuilder
    private func createMoodSheet(appModel: AppModel) -> some View {
        let selectedSubtheme = appModel.moodViewModel.selectedSubtheme
        let isCreateWithAISubtheme = selectedSubtheme?.caseInsensitiveCompare("Create with AI") == .orderedSame
        let isDynamicDesktopSubtheme = selectedSubtheme?.caseInsensitiveCompare("Dynamic Desktop") == .orderedSame
        let isImagePlaygroundSubtheme = selectedSubtheme?.caseInsensitiveCompare("Image Playground") == .orderedSame

        CreateMoodView(
            appModel: appModel,
            defaultTheme: isCreateWithAISubtheme || isDynamicDesktopSubtheme || isImagePlaygroundSubtheme ? "Dynamic" : "Custom",
            defaultSubtheme: isCreateWithAISubtheme ? "Create with AI" : (isDynamicDesktopSubtheme ? "Dynamic Desktop" : (isImagePlaygroundSubtheme ? "Image Playground" : "Personal")),
            initialWallpaperSource: isCreateWithAISubtheme ? .aiGenerated : (isDynamicDesktopSubtheme || isImagePlaygroundSubtheme ? .imagePlayground : .importedMedia)
        )
    }
}

private struct ContentBackgroundSnapshot: Equatable {
    let selectedTab: ContentView.Tab?
    let wallpaperPreview: WallpaperPreviewSnapshot
}

private struct ContentBackgroundView: View, Equatable {
    let snapshot: ContentBackgroundSnapshot
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static func == (lhs: ContentBackgroundView, rhs: ContentBackgroundView) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        Group {
            if let tab = snapshot.selectedTab {
                if tab == .moods || tab == .playlists || tab == .settings {
                    IsolatedWallpaperPreviewView(snapshot: snapshot.wallpaperPreview, showOverlay: false)
                        .equatable()
                        .overlay(Color.black.opacity(0.4))
                        .overlay {
                            if tab != .moods {
                                backgroundGlassOverlay
                            }
                        }
                } else {
                    fallbackGlassBackground
                }
            } else {
                fallbackGlassBackground
            }
        }
        .ignoresSafeArea()
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
            .contentShape(Rectangle())
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
            .contentShape(Rectangle())
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

private struct AtmosphereCarouselMenuItem: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

private struct MoodScrollRequest: Equatable {
    let id = UUID()
    let subtheme: String
}

private struct RepeatedAtmosphereCarouselItem: Identifiable, Hashable {
    let item: AtmosphereCarouselMenuItem
    let cycle: Int

    var id: String {
        "\(cycle)-\(item.id)"
    }
}

private struct AtmosphereCarouselCenterPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AtmospheresWheelMenu: View {
    static let visibleItemCount = 5
    static let rowHeight: CGFloat = 40
    static let rowSpacing: CGFloat = 8
    static let repetitionCount = 9
    static let viewportHeight: CGFloat =
        (CGFloat(visibleItemCount) * rowHeight) + (CGFloat(visibleItemCount - 1) * rowSpacing)

    let items: [AtmosphereCarouselMenuItem]
    @Binding var selectedID: String?
    let onItemActivated: (String) -> Void
    @State private var scrollPositionID: String?

    private var repeatedItems: [RepeatedAtmosphereCarouselItem] {
        guard !items.isEmpty else { return [] }

        return (0..<Self.repetitionCount).flatMap { cycle in
            items.map { item in
                RepeatedAtmosphereCarouselItem(item: item, cycle: cycle)
            }
        }
    }

    private var middleCycle: Int {
        Self.repetitionCount / 2
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: Self.rowSpacing) {
                ForEach(repeatedItems) { repeatedItem in
                    carouselRow(repeatedItem)
                        .id(repeatedItem.id)
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.vertical, Self.viewportHeight / 2 - Self.rowHeight / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrollPositionID, anchor: .center)
        .onAppear {
            let initialID = selectedID ?? items.first?.id
            guard let initialID else { return }
            selectedID = initialID
            scrollPositionID = repeatedID(for: initialID, cycle: middleCycle)
        }
        .onChange(of: selectedID) { _, newValue in
            guard let newValue else {
                return
            }

            if let scrollPositionID,
               let currentItem = repeatedItems.first(where: { $0.id == scrollPositionID }),
               currentItem.item.id == newValue {
                return
            }

            guard let normalizedID = repeatedID(for: newValue, cycle: middleCycle),
                  scrollPositionID != normalizedID else {
                return
            }

            scrollPositionID = normalizedID
        }
        .onChange(of: scrollPositionID) { _, newValue in
            guard let newValue,
                  let repeatedItem = repeatedItems.first(where: { $0.id == newValue }) else {
                return
            }

            normalizeScrollPositionIfNeeded(for: repeatedItem)

            guard repeatedItem.item.id != selectedID else {
                return
            }
            selectedID = repeatedItem.item.id
        }
    }

    private func carouselRow(_ repeatedItem: RepeatedAtmosphereCarouselItem) -> some View {
        let isSelected = selectedID == repeatedItem.item.id

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selectedID = repeatedItem.item.id
                scrollPositionID = repeatedItem.id
            }
            onItemActivated(repeatedItem.item.id)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: repeatedItem.item.systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.78))
                    .frame(width: 20)

                Text(repeatedItem.item.title)
                    .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(.white.opacity(isSelected ? 0.98 : 0.82))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.white.opacity(0.05))
                }
            }
            .contentShape(Rectangle())
            .frame(height: Self.rowHeight)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity)
        .scrollTransition(.interactive, axis: .vertical) { content, phase in
            content
                .scaleEffect(max(0.74, 1 - (abs(phase.value) * 0.26)), anchor: .leading)
                .opacity(max(0.24, 1 - (abs(phase.value) * 0.76)))
        }
    }

    private func repeatedID(for itemID: String, cycle: Int) -> String? {
        repeatedItems.first {
            $0.item.id == itemID && $0.cycle == cycle
        }?.id
    }

    private func normalizeScrollPositionIfNeeded(for repeatedItem: RepeatedAtmosphereCarouselItem) {
        let thresholdCycle = 1
        let needsNormalization =
            repeatedItem.cycle <= thresholdCycle || repeatedItem.cycle >= (Self.repetitionCount - thresholdCycle - 1)

        guard needsNormalization,
              let normalizedID = repeatedID(for: repeatedItem.item.id, cycle: middleCycle),
              normalizedID != scrollPositionID else {
            return
        }

        scrollPositionID = normalizedID
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
}
