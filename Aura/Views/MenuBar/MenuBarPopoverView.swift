import AppKit
import SwiftUI

// ─────────────────────────────────────────────────────────────────────────────
// REQUIRED: AppKit window setup (in your NSPopoverDelegate / presenter)
//
// Liquid Glass lenses content *behind* the NSWindow. The window MUST be
// transparent — otherwise glass composites against an opaque window background
// and renders as flat dark shapes regardless of what .glassEffect() is called.
//
//   func popoverDidShow(_ notification: Notification) {
//       if let window = popover.contentViewController?.view.window {
//           window.isOpaque = false
//           window.backgroundColor = .clear
//           // Remove any NSVisualEffectView the system inserted —
//           // it blocks the Liquid Glass compositor on macOS 26.
//       }
//   }
//
// With a transparent window the glass lenses the live video wallpaper on the
// desktop, giving exactly the translucent, refractive look you want.
// ─────────────────────────────────────────────────────────────────────────────

struct MenuBarPopoverView: View {
    @Bindable var appModel: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow

    @State private var isShowingCreateMood = false
    @State private var selectedSubtheme: String = ""
    @State private var expandedSections: Set<String> = []

    @State private var backgroundImage: NSImage?
    @State private var backgroundVideoURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            headerSection
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 24)

            volumeSection
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 16) {
                Text("Themes")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)

                subthemeSelectorSection

                if !selectedSubtheme.isEmpty {
                    moodCarouselSection
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 24)

            footerSection
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .frame(width: 360)
        // ── Mood artwork overlay ───────────────────────────────────────────────
        // Semi-transparent so the root glass (below) can lens the real desktop
        // content behind the window. Opacity ≤ 0.55 keeps glass refraction
        // visible while still conveying the current mood's colour and motion.
        .background {
            moodArtworkOverlay
        }
        // ── Root-level Liquid Glass — the KEY change ──────────────────────────
        // The entire popover surface becomes one glass lens over the desktop
        // (which shows the live video wallpaper). Individual controls add their
        // own .glassEffect() on top for interactive press-highlight behaviour.
        // isEnabled: false collapses to a solid background when the user has
        // enabled Reduce Transparency in System Settings.
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(NSColor.windowBackgroundColor))
            } else {
                if #available(macOS 16.0, *) {
                    Color.clear
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(.regularMaterial)
                }
            }
        }
        // No .clipShape() — the glass `in:` shape defines the visual boundary.
        // No stroke .overlay — glass provides rim lighting and specular edges.
        .onAppear {
            if selectedSubtheme.isEmpty {
                selectedSubtheme = appModel.moodViewModel.currentMood?.subtheme
                    ?? appModel.moodViewModel.subthemes.first ?? ""
            }
            Task { await loadBackgroundMedia() }
        }
        .onChange(of: appModel.moodViewModel.currentMood?.id) { _, _ in
            if let subtheme = appModel.moodViewModel.currentMood?.subtheme,
               appModel.moodViewModel.subthemes.contains(subtheme) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    selectedSubtheme = subtheme
                }
            }
            Task { await loadBackgroundMedia() }
        }
        .sheet(isPresented: $isShowingCreateMood) {
            CreateMoodView(
                appModel: appModel,
                defaultTheme: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame
                    ? "Dynamic" : "Custom",
                defaultSubtheme: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame
                    ? "Image Playground" : "Personal",
                initialWallpaperSource: selectedSubtheme.caseInsensitiveCompare("Image Playground") == .orderedSame
                    ? .imagePlayground : .importedMedia
            )
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReopenMainWindow"))) { _ in
            openWindow(id: "main")
        }
    }

    // MARK: - Artwork overlay
    //
    // Two paths:
    // • reduceTransparency ON  → solid opaque window-background colour (glass disabled)
    // • reduceTransparency OFF → mood video/image at 50% opacity, tinting the glass
    //   surface without fully obscuring the refraction and rim lighting behind it.

    @ViewBuilder
    private var moodArtworkOverlay: some View {
        if reduceTransparency {
            // Solid fallback — fills the shape that glass would have occupied.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        } else {
            ZStack {
                if let videoURL = backgroundVideoURL {
                    VideoBackgroundView(url: videoURL)
                        .aspectRatio(contentMode: .fill)
                        .opacity(0.50)
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                    // Minimal scrim — enough to make white text readable,
                    // light enough to keep glass refraction visible.
                    Color.black.opacity(0.10)
                } else if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 30, opaque: true)
                        .saturation(1.3)
                        .opacity(0.50)
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))
                }
                // No fallback colour needed — when artwork is nil the glass
                // lenses the desktop directly, showing the neutral system tint.
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(appModel.moodViewModel.currentMood?.name ?? "Aura")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Glass applied to the Button so the system wires the interactive
            // press-highlight directly to the glass surface layer.
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    appModel.playerViewModel.togglePlayback()
                }
            } label: {
                Image(systemName: appModel.playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle())
            .focusable(false)
        }
    }

    // MARK: - Volume

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Master Volume")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))

            HStack(spacing: 16) {
                Slider(
                    value: Binding(
                        get: { Double(appModel.playerViewModel.masterVolume) },
                        set: { appModel.playerViewModel.masterVolume = Float($0) }
                    ),
                    in: 0...1
                )
                .tint(.white)

                Text("\(Int(appModel.playerViewModel.masterVolume * 100))%")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Subtheme Selector

    private var subthemeSelectorSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(appModel.moodViewModel.subthemeSections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    // ── Section Header ───────────────────────────────────────
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            if expandedSections.contains(section.id) {
                                expandedSections.remove(section.id)
                            } else {
                                expandedSections.insert(section.id)
                            }
                        }
                    } label: {
                        HStack {
                            Text(section.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                                .rotationEffect(.degrees(expandedSections.contains(section.id) ? 90 : 0))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)

                    // ── Pills (expanded) ─────────────────────────────────────
                    // GlassEffectContainer shares a compositing pass for all
                    // pills in the row, reducing overdraw. spacing: 0 = batch
                    // only (no visual merging between pills).
                    if expandedSections.contains(section.id) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            GlassEffectContainer {
                                HStack(spacing: 8) {
                                    ForEach(section.subthemes, id: \.self) { subtheme in
                                        let isActive = selectedSubtheme == subtheme
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedSubtheme = subtheme
                                            }
                                        } label: {
                                            Text(subtheme)
                                                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                                                .foregroundStyle(isActive ? .white : .white.opacity(0.65))
                                                .padding(.horizontal, 14)
                                                .padding(.vertical, 7)
                                                .contentShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .glassEffect(
                                            isActive
                                                ? .regular.interactive().tint(.white.opacity(0.12))
                                                : .regular.interactive(),
                                            in: Capsule()
                                        )
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .contentMargins(.horizontal, 24, for: .scrollContent)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Mood Carousel

    private var moodCarouselSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                let subthemeMoods = appModel.moodViewModel.moodsBySubtheme[selectedSubtheme] ?? []
                ForEach(subthemeMoods, id: \.id) { mood in
                    MoodCarouselCard(
                        mood: mood,
                        isSelected: appModel.moodViewModel.currentMood?.id == mood.id,
                        appModel: appModel,
                        onDelete: UUID(uuidString: mood.id) != nil ? {
                            withAnimation { appModel.moodViewModel.removeMood(mood) }
                        } : nil
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            appModel.moodViewModel.selectMood(mood)
                        }
                    }
                }
                NewMoodButtonContent { isShowingCreateMood = true }
            }
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .frame(maxWidth: .infinity)
        .frame(height: 180)
    }

    // MARK: - Footer
    //
    // GlassEffectContainer batches the three buttons into a shared compositing
    // layer (spacing: 0 = no visual merging). Reduces overdraw compared to
    // three independent glass surfaces.

    private var footerSection: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                    for window in NSApp.windows where window.identifier?.rawValue == "main" {
                        if window.isMiniaturized { window.deminiaturize(nil) }
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    Text("Open Aura")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    appModel.showCommandPalette.toggle()
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "main")
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .help("Search")

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .help("Quit Aura")
            }
        }
    }

    // MARK: - Background media loading

    @MainActor
    private func loadBackgroundMedia() async {
        guard let mood = appModel.moodViewModel.currentMood,
              mood.wallpaper.type != .time,
              mood.wallpaper.type != .zen,
              mood.wallpaper.type != .quote,
              let resource = mood.wallpaper.resources.first else {
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundImage = nil; backgroundVideoURL = nil
            }
            return
        }

        guard let url = MediaUtils.resolveResourceURL(resource) else {
            let img = NSImage(named: resource)
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundVideoURL = nil; backgroundImage = img
            }
            return
        }

        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundImage = nil; backgroundVideoURL = url
            }
        } else {
            withAnimation(.easeInOut(duration: 0.4)) { backgroundVideoURL = nil }
            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
            withAnimation(.easeInOut(duration: 0.4)) { backgroundImage = loaded }
        }
    }
}

// MARK: - NewMoodButtonContent

private struct NewMoodButtonContent: View {
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                Text("Create a\nnew Mood")
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .padding(16)
            .frame(width: 120, height: 160)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(isHovered ? 0.42 : 0.24), lineWidth: isHovered ? 1.5 : 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.24 : 0.16), radius: isHovered ? 14 : 10, y: 6)
        .scaleEffect(isHovered ? 1.03 : 1.0)
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isHovered)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
        .focusable(false)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Create a new mood")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - MoodCarouselCard

private struct MoodCarouselCard: View {
    let mood: Mood
    let isSelected: Bool
    var appModel: AppModel
    var onDelete: (() -> Void)?
    let action: () -> Void

    @State private var image: NSImage?
    @State private var isHovered = false
    @State private var isPressed = false

    private var primaryResource: String { mood.wallpaper.resources.first ?? "" }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleAction) {
                ZStack(alignment: .bottomLeading) {
                    cardBackground.frame(width: 120, height: 160)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center, endPoint: .bottom
                    )

                    Text(mood.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .padding(12)
                }
                .frame(width: 120, height: 160)
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { downloadOverlay }
            }
            .buttonStyle(.plain)
            .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.white.opacity(0.75) : Color.white.opacity(0.28),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(
                color: isSelected ? Color.white.opacity(0.22) : .black.opacity(0.2),
                radius: isSelected ? 12 : 4, y: 4
            )
            .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)

            if let onDelete, isHovered {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.red.opacity(0.85))
                        .background(Circle().fill(.white).padding(2))
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task {
            if !primaryResource.isEmpty { DownloadManager.shared.checkStatus(for: primaryResource) }
            await loadPreviewImage()
        }
        .onChange(of: DownloadManager.shared.downloadStates[primaryResource]) { _, newState in
            if newState == .downloaded { Task { await loadPreviewImage() } }
        }
    }

    @ViewBuilder
    private var downloadOverlay: some View {
        if mood.wallpaper.type != .time, mood.wallpaper.type != .zen,
           mood.wallpaper.type != .quote, !primaryResource.isEmpty {
            let state = DownloadManager.shared.downloadStates[primaryResource] ?? .notDownloaded
            if state == .notDownloaded {
                VStack { Spacer()
                    HStack { Spacer()
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white).shadow(radius: 2).padding(14)
                    }
                }
            } else if case .downloading(let progress) = state {
                VStack { Spacer()
                    HStack { Spacer()
                        ProgressView(value: progress)
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8).padding(14)
                    }
                }
            }
        }
    }

    private func handleAction() {
        guard mood.wallpaper.type != .time, mood.wallpaper.type != .zen,
              mood.wallpaper.type != .quote, !primaryResource.isEmpty else {
            action(); return
        }
        if DownloadManager.shared.isDownloaded(resource: primaryResource) {
            action()
        } else {
            Task {
                await DownloadManager.shared.download(primaryResource)
                if DownloadManager.shared.isDownloaded(resource: primaryResource) {
                    await loadPreviewImage(); action()
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if mood.wallpaper.type == .time {
            TimeWallpaperView(style: mood.wallpaper.resources.first ?? "minimal", palette: mood.palette,
                              selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL, isPreview: true)
                .frame(width: 120, height: 160).clipped()
        } else if mood.wallpaper.type == .quote {
            let quoteID = mood.wallpaper.resources.count > 1 ? UUID(uuidString: mood.wallpaper.resources[1]) : nil
            QuoteWallpaperView(style: mood.wallpaper.resources.first ?? "motivational", palette: mood.palette,
                               quoteID: quoteID, selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL, isPreview: true)
                .frame(width: 120, height: 160).clipped()
        } else if mood.wallpaper.type == .zen {
            ZenWallpaperView(style: mood.wallpaper.resources.first ?? "breathing", palette: mood.palette,
                             selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL, isPreview: true)
                .frame(width: 120, height: 160).clipped()
        } else if mood.wallpaper.type == .website {
            WebsiteWallpaperPreview(mood: mood, isPressed: false, targetSize: CGSize(width: 120, height: 160))
                .frame(width: 120, height: 160).clipped()
        } else if isSelected,
                  let resource = mood.wallpaper.resources.first,
                  let url = MediaUtils.resolveResourceURL(resource),
                  ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            VideoBackgroundView(url: url).frame(width: 120, height: 160).clipped()
        } else if let image {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 160).clipped()
        } else {
            Color.clear.frame(width: 120, height: 160)
        }
    }

    @MainActor
    private func loadPreviewImage() async {
        guard mood.wallpaper.type != .time, mood.wallpaper.type != .zen,
              mood.wallpaper.type != .quote,
              let resource = mood.wallpaper.resources.first else { return }

        if let cached = MoodCard.imageCache.object(forKey: resource as NSString) {
            self.image = cached; return
        }

        let loaded = await Task(priority: .utility) { () -> NSImage? in
            if Task.isCancelled { return nil }
            let resolvedURL = MediaUtils.resolveResourceURL(resource)
            let ext = (resolvedURL?.pathExtension ?? (resource as NSString).pathExtension).lowercased()
            if let url = resolvedURL, url.isFileURL,
               FileManager.default.fileExists(atPath: url.path) {
                if ["mp4", "mov"].contains(ext) { return await MediaUtils.videoPosterImage(from: url) }
                return NSImage(contentsOf: url)
            }
            let base = (resource as NSString).deletingPathExtension
            return NSImage(named: base) ?? NSImage(named: resource)
        }.value

        if let loaded {
            MoodCard.imageCache.setObject(loaded, forKey: resource as NSString)
            self.image = loaded
        } else {
            self.image = nil
        }
    }
}
