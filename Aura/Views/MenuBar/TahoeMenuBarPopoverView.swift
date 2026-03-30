import AppKit
import SwiftUI

struct TahoeMenuBarPopoverView: View {
    @Bindable var appModel: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow
    @Namespace private var glassNamespace

    @State private var isShowingCreateMood = false
    @State private var selectedSubtheme: String = ""
    @State private var expandedSections: Set<String> = []
    @State private var backgroundImage: NSImage?
    @State private var backgroundVideoURL: URL?

    private let panelWidth: CGFloat = 392
    private let panelHeight: CGFloat = 744
    private let panelShape = RoundedRectangle(cornerRadius: 30, style: .continuous)
    private let sectionShape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    private let controlShape = RoundedRectangle(cornerRadius: 16, style: .continuous)

    var body: some View {
        panelContainer
            .sheet(isPresented: $isShowingCreateMood) {
                CreateMoodView(
                    appModel: appModel,
                    defaultTheme: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame ? "Dynamic" : "Custom",
                    defaultSubtheme: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame ? "Image Playground" : "Personal",
                    initialWallpaperSource: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame ? .imagePlayground : .importedMedia
                )
            }
            .environment(\.colorScheme, .dark)
            .task(id: appModel.moodViewModel.currentMood?.id) {
                syncSelectionFromCurrentMood()
                await loadBackgroundMedia()
            }
            .onChange(of: appModel.moodViewModel.selectedSubtheme) { _, newValue in
                guard let newValue, !newValue.isEmpty else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    selectedSubtheme = newValue
                    expandSectionIfNeeded(for: newValue)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReopenMainWindow"))) { _ in
                revealMainWindow()
            }
    }

    private var panelContainer: some View {
        panelContent
            .frame(width: panelWidth, height: panelHeight)
            .background { panelBackground }
            .clipShape(panelShape)
            .overlay { panelBorder }
            .shadow(color: .black.opacity(0.28), radius: 28, y: 18)
    }

    private var panelContent: some View {
        ZStack {
            panelBackdrop

            ScrollView(showsIndicators: false) {
                glassRoot
                    .padding(20)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var panelBackground: some View {
        if reduceTransparency {
            panelShape.fill(.regularMaterial)
        } else if #available(macOS 26.0, *) {
            Color.clear
                .glassEffect(.clear, in: panelShape)
        } else {
            panelShape.fill(.regularMaterial)
        }
    }

    private var panelBorder: some View {
        panelShape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(reduceTransparency ? 0.18 : 0.34),
                        .white.opacity(reduceTransparency ? 0.08 : 0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private var glassRoot: some View {
        if #available(macOS 26.0, *) {
            SwiftUI.GlassEffectContainer(spacing: 16) {
                contentStack
            }
        } else {
            contentStack
        }
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroSection
            volumeSection
            themesHeader
            subthemeSections

            if !currentSubthemeMoods.isEmpty {
                moodCarouselSection
            }

            footerSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var panelBackdrop: some View {
        if reduceTransparency {
            Color(NSColor.windowBackgroundColor)
        } else {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.12, green: 0.20, blue: 0.15),
                        Color(red: 0.05, green: 0.08, blue: 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if let videoURL = backgroundVideoURL {
                    VideoBackgroundView(url: videoURL)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                } else if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(1.05)
                        .brightness(-0.02)
                        .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                }

                LinearGradient(
                    colors: [
                        .black.opacity(0.10),
                        .black.opacity(0.22),
                        .black.opacity(0.42)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                RadialGradient(
                    colors: [
                        accentColor.opacity(0.28),
                        .white.opacity(0.08),
                        .clear
                    ],
                    center: .topLeading,
                    startRadius: 20,
                    endRadius: 320
                )

                RadialGradient(
                    colors: [
                        accentColor.opacity(0.20),
                        .clear
                    ],
                    center: .bottomTrailing,
                    startRadius: 40,
                    endRadius: 300
                )
            }
        }
    }

    private var heroSection: some View {
        HStack(alignment: .center) {
            Text(appModel.moodViewModel.currentMood?.name ?? "Aura")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(primaryForegroundStyle)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                    appModel.playerViewModel.togglePlayback()
                }
            } label: {
                Image(systemName: appModel.playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(primaryForegroundStyle)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
        .padding(.horizontal, 2)
        .padding(.top, 10)
    }

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Master Volume")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(primaryForegroundStyle)

            HStack(spacing: 14) {
                Slider(
                    value: Binding(
                        get: { Double(appModel.playerViewModel.masterVolume) },
                        set: { appModel.playerViewModel.masterVolume = Float($0) }
                    ),
                    in: 0...1
                )
                .controlSize(.large)
                .tint(accentColor)

                Text("\(Int(appModel.playerViewModel.masterVolume * 100))%")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(primaryForegroundStyle)
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 2)
    }

    private var themesHeader: some View {
        Text("Themes")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(primaryForegroundStyle)
            .padding(.horizontal, 2)
            .padding(.top, 4)
    }

    private var subthemeSections: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(appModel.moodViewModel.subthemeSections) { section in
                sectionDisclosure(section)
            }
        }
    }

    private func sectionDisclosure(_ section: MoodSubthemeSection) -> some View {
        let isExpanded = expandedSections.contains(section.id)

        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                    if isExpanded {
                        expandedSections.remove(section.id)
                    } else {
                        expandedSections.insert(section.id)
                    }
                }
            } label: {
                HStack(spacing: 12) {
                    Text(section.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(primaryForegroundStyle)

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(secondaryForegroundStyle)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .frame(height: 42)
                .frame(maxWidth: .infinity)
                .contentShape(controlShape)
            }
            .buttonStyle(.plain)

            if isExpanded {
                subthemeGrid(for: section)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func subthemeGrid(for section: MoodSubthemeSection) -> some View {
        TahoeWrappingLayout(spacing: 10, rowSpacing: 10) {
            ForEach(section.subthemes, id: \.self) { subtheme in
                let isSelected = selectedSubtheme.caseInsensitiveCompare(subtheme) == .orderedSame

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                        selectedSubtheme = subtheme
                        appModel.moodViewModel.selectedSubtheme = subtheme
                        expandSectionIfNeeded(for: subtheme)
                    }
                } label: {
                    Text(subtheme)
                        .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(primaryForegroundStyle)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .tahoeGlassID("subtheme-\(subtheme)", in: glassNamespace)
                .tahoeGlass(
                    Capsule(),
                    interactive: true,
                    tint: isSelected ? .white.opacity(0.14) : .white.opacity(0.03),
                    strokeOpacity: isSelected ? 0.42 : 0.30,
                    shadowOpacity: isSelected ? 0.16 : 0.08
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moodCarouselSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(currentSubthemeMoods, id: \.id) { mood in
                        TahoeMoodCarouselCard(
                            mood: mood,
                            isSelected: appModel.moodViewModel.currentMood?.id == mood.id,
                            appModel: appModel,
                            namespace: glassNamespace,
                            onDelete: UUID(uuidString: mood.id) != nil ? {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    appModel.moodViewModel.removeMood(mood)
                                    syncSelectionAfterDeletion(for: mood)
                                }
                            } : nil
                        ) { force in
                            if force || appModel.moodViewModel.currentMood?.id != mood.id {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                    selectedSubtheme = mood.subtheme
                                    appModel.moodViewModel.selectedSubtheme = mood.subtheme
                                    appModel.moodViewModel.selectMood(mood)
                                }
                            }
                        }
                    }

                    TahoeNewMoodCard(namespace: glassNamespace) {
                        isShowingCreateMood = true
                    }
                }
                .padding(.vertical, 4)
            }
            .contentMargins(.horizontal, 2, for: .scrollContent)
        }
    }

    private var footerSection: some View {
        HStack(spacing: 10) {
            Button {
                revealMainWindow()
            } label: {
                Text("Open Aura")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(primaryForegroundStyle)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(controlShape)
            }
            .buttonStyle(.plain)

            Button {
                appModel.showCommandPalette.toggle()
                revealMainWindow()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryForegroundStyle)
                    .frame(width: 50, height: 50)
                    .contentShape(controlShape)
            }
            .buttonStyle(.plain)
            .help("Search")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(primaryForegroundStyle)
                    .frame(width: 50, height: 50)
                    .contentShape(controlShape)
            }
            .buttonStyle(.plain)
            .help("Quit Aura")
        }
    }

    private var currentSubthemeMoods: [Mood] {
        appModel.moodViewModel.moodsBySubtheme[selectedSubtheme] ?? []
    }

    private var currentMood: Mood? {
        appModel.moodViewModel.currentMood
    }

    private var accentColor: Color {
        let accent = currentMood?.palette.accent ?? ColorComponents(red: 0.38, green: 0.70, blue: 0.58)
        return Color(red: accent.red, green: accent.green, blue: accent.blue)
    }

    private var primaryForegroundStyle: AnyShapeStyle {
        AnyShapeStyle(.primary)
    }

    private var secondaryForegroundStyle: AnyShapeStyle {
        AnyShapeStyle(.secondary)
    }

    private func revealMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")

        for window in NSApp.windows where window.identifier?.rawValue == "main" {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func syncSelectionFromCurrentMood() {
        let fallbackSubtheme = appModel.moodViewModel.currentMood?.subtheme
            ?? appModel.moodViewModel.selectedSubtheme
            ?? appModel.moodViewModel.subthemes.first
            ?? ""

        if !fallbackSubtheme.isEmpty {
            selectedSubtheme = fallbackSubtheme
            appModel.moodViewModel.selectedSubtheme = fallbackSubtheme
        }

        let sectionIDs = Set(appModel.moodViewModel.subthemeSections.map(\.id))
        if expandedSections.isEmpty {
            expandedSections = sectionIDs
        } else {
            expandedSections.formIntersection(sectionIDs)
        }

        if !fallbackSubtheme.isEmpty {
            expandSectionIfNeeded(for: fallbackSubtheme)
        }
    }

    private func expandSectionIfNeeded(for subtheme: String) {
        guard let section = appModel.moodViewModel.subthemeSections.first(where: { $0.subthemes.contains(subtheme) }) else {
            return
        }
        expandedSections.insert(section.id)
    }

    private func syncSelectionAfterDeletion(for deletedMood: Mood) {
        let remainingMoods = appModel.moodViewModel.moodsBySubtheme[deletedMood.subtheme] ?? []

        if let replacement = remainingMoods.first {
            selectedSubtheme = replacement.subtheme
            appModel.moodViewModel.selectedSubtheme = replacement.subtheme
            appModel.moodViewModel.selectMood(replacement)
            return
        }

        if let fallbackSubtheme = appModel.moodViewModel.subthemes.first,
           let fallbackMood = appModel.moodViewModel.moodsBySubtheme[fallbackSubtheme]?.first {
            selectedSubtheme = fallbackSubtheme
            appModel.moodViewModel.selectedSubtheme = fallbackSubtheme
            appModel.moodViewModel.selectMood(fallbackMood)
        } else {
            selectedSubtheme = ""
        }
    }

    @MainActor
    private func loadBackgroundMedia() async {
        guard let mood = appModel.moodViewModel.currentMood,
              mood.wallpaper.type != .time,
              mood.wallpaper.type != .zen,
              mood.wallpaper.type != .quote,
              let resource = mood.wallpaper.resources.first else {
            withAnimation(.easeInOut(duration: 0.35)) {
                backgroundImage = nil
                backgroundVideoURL = nil
            }
            return
        }

        guard let url = MediaUtils.resolveResourceURL(resource) else {
            let image = NSImage(named: resource)
            withAnimation(.easeInOut(duration: 0.35)) {
                backgroundVideoURL = nil
                backgroundImage = image
            }
            return
        }

        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            withAnimation(.easeInOut(duration: 0.35)) {
                backgroundImage = nil
                backgroundVideoURL = url
            }
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                backgroundVideoURL = nil
            }

            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value

            withAnimation(.easeInOut(duration: 0.35)) {
                backgroundImage = loaded
            }
        }
    }
}

private struct TahoeNewMoodCard: View {
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Spacer()

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Create")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Build a new mood")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
            .frame(width: 148, height: 184)
            .contentShape(cardShape)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.02 : 1))
        .tahoeGlassID("create-mood", in: namespace)
        .tahoeGlass(cardShape, interactive: true, tint: .white.opacity(0.05), strokeOpacity: 0.36, shadowOpacity: 0.18)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}

private struct TahoeMoodCarouselCard: View {
    let mood: Mood
    let isSelected: Bool
    var appModel: AppModel
    let namespace: Namespace.ID
    var onDelete: (() -> Void)? = nil
    let action: (Bool) -> Void

    @State private var image: NSImage?
    @State private var isHovered = false
    @State private var isPressed = false

    private let cardShape = RoundedRectangle(cornerRadius: 22, style: .continuous)

    private var primaryResource: String {
        mood.wallpaper.resources.first ?? ""
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleAction) {
                ZStack(alignment: .bottomLeading) {
                    cardArtwork
                        .clipShape(cardShape)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.58)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .clipShape(cardShape)

                    Text(mood.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(14)

                    if !primaryResource.isEmpty,
                       mood.wallpaper.type != .time,
                       mood.wallpaper.type != .zen,
                       mood.wallpaper.type != .quote {
                        downloadOverlay
                    }
                }
                .frame(width: 148, height: 184)
                .contentShape(cardShape)
            }
            .buttonStyle(.plain)

            if let onDelete, isHovered {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.red.opacity(0.95))
                        .padding(10)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 148, height: 184)
        .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.015 : 1))
        .tahoeGlassID("mood-\(mood.id)", in: namespace)
        .tahoeGlass(
            cardShape,
            interactive: true,
            tint: isSelected ? .white.opacity(0.10) : nil,
            strokeOpacity: isSelected ? 0.52 : 0.34,
            shadowOpacity: isSelected ? 0.22 : 0.16
        )
        .overlay {
            if isSelected {
                cardShape
                    .strokeBorder(.white.opacity(0.72), lineWidth: 1.4)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task(id: mood.id) {
            if !primaryResource.isEmpty {
                DownloadManager.shared.checkStatus(for: primaryResource)
            }
            await loadPreviewImage()
        }
        .onChange(of: DownloadManager.shared.downloadStates[primaryResource]) { _, newState in
            if newState == .downloaded {
                Task {
                    await loadPreviewImage()
                }
            }
        }
    }

    @ViewBuilder
    private var downloadOverlay: some View {
        let downloadState = DownloadManager.shared.downloadStates[primaryResource] ?? .notDownloaded

        if downloadState == .notDownloaded {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(14)
                }
            }
        } else if case .downloading(let progress) = downloadState {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .padding(14)
                }
            }
        }
    }

    private func handleAction() {
        if mood.wallpaper.type == .time || mood.wallpaper.type == .zen || mood.wallpaper.type == .quote || primaryResource.isEmpty {
            action(false)
            return
        }

        if DownloadManager.shared.isDownloaded(resource: primaryResource) {
            action(false)
            return
        }

        action(false)
        Task {
            await DownloadManager.shared.download(primaryResource)
            if DownloadManager.shared.isDownloaded(resource: primaryResource) {
                await loadPreviewImage()
                action(true)
            }
        }
    }

    @ViewBuilder
    private var cardArtwork: some View {
        if mood.wallpaper.type == .time {
            let style = mood.wallpaper.resources.first ?? "minimal"
            TimeWallpaperView(
                style: style,
                palette: mood.palette,
                selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL,
                isPreview: true
            )
            .frame(width: 148, height: 184)
        } else if mood.wallpaper.type == .quote {
            let style = mood.wallpaper.resources.first ?? "motivational"
            let quoteID = mood.wallpaper.resources.count > 1 ? UUID(uuidString: mood.wallpaper.resources[1]) : nil
            QuoteWallpaperView(
                style: style,
                palette: mood.palette,
                quoteID: quoteID,
                selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL,
                isPreview: true
            )
            .frame(width: 148, height: 184)
        } else if mood.wallpaper.type == .zen {
            let style = mood.wallpaper.resources.first ?? "breathing"
            ZenWallpaperView(
                style: style,
                palette: mood.palette,
                selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL,
                isPreview: true
            )
            .frame(width: 148, height: 184)
        } else if mood.wallpaper.type == .website {
            WebsiteWallpaperPreview(
                mood: mood,
                isPressed: false,
                targetSize: CGSize(width: 148, height: 184)
            )
            .frame(width: 148, height: 184)
        } else if isSelected,
                  let resource = mood.wallpaper.resources.first,
                  let url = MediaUtils.resolveResourceURL(resource),
                  ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            VideoBackgroundView(url: url)
                .frame(width: 148, height: 184)
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 148, height: 184)
        } else {
            LinearGradient(
                colors: [
                    Color.white.opacity(0.16),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(width: 148, height: 184)
        }
    }

    @MainActor
    private func loadPreviewImage() async {
        guard mood.wallpaper.type != .time,
              mood.wallpaper.type != .zen,
              mood.wallpaper.type != .quote,
              let resource = mood.wallpaper.resources.first else {
            return
        }

        if let cached = MoodCard.imageCache.object(forKey: resource as NSString) {
            image = cached
            return
        }

        let loaded = await Task(priority: .utility) { () -> NSImage? in
            if Task.isCancelled {
                return nil
            }

            let resolvedURL = MediaUtils.resolveResourceURL(resource)
            let ext = (resolvedURL?.pathExtension ?? (resource as NSString).pathExtension).lowercased()
            let isVideo = ["mp4", "mov"].contains(ext)

            if let url = resolvedURL, url.isFileURL, FileManager.default.fileExists(atPath: url.path) {
                if isVideo {
                    return await MediaUtils.videoPosterImage(from: url)
                }

                return NSImage(contentsOf: url)
            }

            let baseName = (resource as NSString).deletingPathExtension
            if let image = NSImage(named: baseName) {
                return image
            }

            return NSImage(named: resource)
        }.value

        if let loaded {
            MoodCard.imageCache.setObject(loaded, forKey: resource as NSString)
        }

        image = loaded
    }
}

private struct TahoeWrappingLayout: Layout {
    let spacing: CGFloat
    let rowSpacing: CGFloat

    init(spacing: CGFloat = 10, rowSpacing: CGFloat = 10) {
        self.spacing = spacing
        self.rowSpacing = rowSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let rows = makeRows(maxWidth: proposal.width, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.enumerated().reduce(CGFloat.zero) { partialResult, entry in
            let (index, row) = entry
            return partialResult + row.height + (index == rows.indices.last ? 0 : rowSpacing)
        }

        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let rows = makeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY

        for row in rows {
            var x = bounds.minX

            for element in row.elements {
                subviews[element.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: element.size.width, height: element.size.height)
                )
                x += element.size.width + spacing
            }

            y += row.height + rowSpacing
        }
    }

    private func makeRows(maxWidth: CGFloat?, subviews: Subviews) -> [Row] {
        let availableWidth = maxWidth ?? .greatestFiniteMagnitude
        var rows: [Row] = []
        var currentRow = Row()

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = currentRow.elements.isEmpty ? size.width : currentRow.width + spacing + size.width

            if nextWidth > availableWidth, !currentRow.elements.isEmpty {
                rows.append(currentRow)
                currentRow = Row()
            }

            currentRow.elements.append(RowElement(index: index, size: size))
            currentRow.width = currentRow.elements.count == 1 ? size.width : currentRow.width + spacing + size.width
            currentRow.height = max(currentRow.height, size.height)
        }

        if !currentRow.elements.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private struct Row {
        var elements: [RowElement] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct RowElement {
        let index: Int
        let size: CGSize
    }
}

private struct TahoeGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?
    let strokeOpacity: Double
    let shadowOpacity: Double

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(.regularMaterial))
                .overlay { strokeOverlay }
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
        } else if #available(macOS 26.0, *) {
            if interactive {
                if let tint {
                    content
                        .glassEffect(.regular.interactive().tint(tint), in: shape)
                        .overlay { strokeOverlay }
                        .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
                } else {
                    content
                        .glassEffect(.regular.interactive(), in: shape)
                        .overlay { strokeOverlay }
                        .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
                }
            } else {
                if let tint {
                    content
                        .glassEffect(.regular.tint(tint), in: shape)
                        .overlay { strokeOverlay }
                        .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
                } else {
                    content
                        .glassEffect(.regular, in: shape)
                        .overlay { strokeOverlay }
                        .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
                }
            }
        } else {
            content
                .background(shape.fill(.regularMaterial))
                .overlay { strokeOverlay }
                .shadow(color: .black.opacity(shadowOpacity), radius: 18, y: 10)
        }
    }

    private var strokeOverlay: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(reduceTransparency ? strokeOpacity * 0.6 : strokeOpacity),
                        .white.opacity(reduceTransparency ? strokeOpacity * 0.18 : strokeOpacity * 0.35)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private extension View {
    func tahoeGlass<S: InsettableShape>(
        _ shape: S,
        interactive: Bool = false,
        tint: Color? = nil,
        strokeOpacity: Double = 0.3,
        shadowOpacity: Double = 0.12
    ) -> some View {
        modifier(
            TahoeGlassModifier(
                shape: shape,
                interactive: interactive,
                tint: tint,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }

    @ViewBuilder
    func tahoeGlassID<ID: Hashable>(_ id: ID, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}
