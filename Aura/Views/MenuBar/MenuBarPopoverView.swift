import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @Bindable var appModel: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.openWindow) private var openWindow

    @State private var isShowingCreateMood = false
    @State private var selectedSubtheme: String = ""

    // ── Background media state ────────────────────────────────────────────────
    // Only one of these is non-nil at a time.
    // • backgroundVideoURL  → video wallpaper; VideoBackgroundView plays it live.
    // • backgroundImage     → static/image wallpaper; rendered blurred as before.
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
        .background { backgroundLayer }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        }
        .onAppear {
            if selectedSubtheme.isEmpty {
                selectedSubtheme = appModel.moodViewModel.currentMood?.subtheme
                    ?? appModel.moodViewModel.subthemes.first
                    ?? ""
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
            CreateMoodView(appModel: appModel)
        }
        .environment(\.colorScheme, .dark)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ReopenMainWindow"))) { _ in
            openWindow(id: "main")
        }
    }

    // MARK: - Background
    //
    // Video wallpapers play through unblurred — a single semi-transparent scrim
    // provides enough contrast for white text without obscuring the motion.
    //
    // Static/image wallpapers keep the original heavily-blurred treatment so
    // they read as a soft tinted canvas rather than a literal photo crop.
    //
    // Do NOT apply .glassEffect() at the popover level — it would add its own
    // adaptive dark tint over the artwork. Each interactive control carries its
    // own individual .glassEffect() and lenses the art beneath it directly.

    @ViewBuilder
    private var backgroundLayer: some View {
        if reduceTransparency {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.97))
        } else {
            ZStack {
                // Neutral fallback colour while media is loading
                Color(red: 0.08, green: 0.12, blue: 0.10)

                if let videoURL = backgroundVideoURL {
                    // ── Video path: play live, no blur ────────────────────────
                    // VideoBackgroundView fills the frame; a single dark scrim
                    // (0.30 alpha) is sufficient for WCAG-AA white-text contrast
                    // while keeping the motion clearly visible.
                    VideoBackgroundView(url: videoURL)
                        .aspectRatio(contentMode: .fill)
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))

                    Color.black.opacity(0.30)

                } else if let backgroundImage {
                    // ── Image path: blurred wash, unchanged from original ─────
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 50, opaque: true)
                        .saturation(1.5)
                        .brightness(0.08)
                        .transition(.opacity.animation(.easeInOut(duration: 0.4)))

                    Color.black.opacity(0.08)
                }
            }
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
    //
    // No container box — label and slider float directly on the background.

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
    //
    // Each pill gets its own .glassEffect() independently — no GlassEffectContainer
    // so pills stay visually separated (no merging into one dark bar).

    private var subthemeSelectorSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appModel.moodViewModel.subthemes, id: \.self) { subtheme in
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
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
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
                        onDelete: mood.id.count > 15 ? {
                            withAnimation { appModel.moodViewModel.removeMood(mood) }
                        } : nil
                    ) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            appModel.moodViewModel.selectMood(mood)
                        }
                    }
                }

                Button { isShowingCreateMood = true } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                        Text("New Mood")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .frame(width: 140, height: 220)
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .contentMargins(.horizontal, 24, for: .scrollContent)
        .frame(maxWidth: .infinity)
        .frame(height: 236)
    }

    // MARK: - Footer
    //
    // Three independent glass buttons — no GlassEffectContainer, no merging.

    private var footerSection: some View {
        HStack(spacing: 8) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "main")
                
                // Ensure the window is un-minimized and brought to front
                for window in NSApp.windows where window.identifier?.rawValue == "main" {
                    if window.isMiniaturized {
                        window.deminiaturize(nil)
                    }
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
                // If the main window isn't visible, we should probably open it since Command Palette is there
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

    // MARK: - Background media loading
    //
    // Renamed from loadBackgroundImage.
    //
    // Decision tree:
    //   • No mood / time-based wallpaper → clear both, show neutral fallback colour.
    //   • Video resource              → set backgroundVideoURL, clear backgroundImage.
    //                                   No poster frame needed — VideoBackgroundView
    //                                   renders the first frame itself while buffering.
    //   • Image resource              → clear backgroundVideoURL, load NSImage async.
    //
    // Both state mutations happen inside withAnimation so the crossfade between
    // moods is smooth rather than a hard cut.

    @MainActor
    private func loadBackgroundMedia() async {
        guard let mood = appModel.moodViewModel.currentMood,
              mood.wallpaper.type != .time,
              let resource = mood.wallpaper.resources.first else {
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundImage = nil
                backgroundVideoURL = nil
            }
            return
        }

        guard let url = MediaUtils.resolveResourceURL(resource) else {
            // Named-asset fallback (bundled image)
            let img = NSImage(named: resource)
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundVideoURL = nil
                backgroundImage = img
            }
            return
        }

        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            // ── Video mood ────────────────────────────────────────────────────
            // Assign the URL immediately so VideoBackgroundView can start
            // buffering; no need to extract a poster frame for the background.
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundImage = nil
                backgroundVideoURL = url
            }
        } else {
            // ── Image mood ────────────────────────────────────────────────────
            // Clear the video first so the neutral fallback shows while the
            // image loads, then crossfade in the result.
            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundVideoURL = nil
            }

            let loaded = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value

            withAnimation(.easeInOut(duration: 0.4)) {
                backgroundImage = loaded
            }
        }
    }
}

// MARK: - MoodCarouselCard

private struct MoodCarouselCard: View {
    let mood: Mood
    let isSelected: Bool
    var onDelete: (() -> Void)? = nil
    let action: () -> Void

    @State private var image: NSImage?
    @State private var isHovered = false

    private var primaryResource: String {
        mood.wallpaper.resources.first ?? ""
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleAction) {
                ZStack(alignment: .bottomLeading) {
                    cardBackground
                        .frame(width: 140, height: 220)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Text(mood.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                        .padding(12)
                }
                .frame(width: 140, height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isSelected
                                ? Color.white.opacity(0.75)
                                : Color.white.opacity(0.28),
                            lineWidth: isSelected ? 2 : 1
                        )
                        .allowsHitTesting(false)
                }
                .overlay {
                    // Download Status Overlay
                    if mood.wallpaper.type != .time, !primaryResource.isEmpty {
                        let downloadState = DownloadManager.shared.downloadStates[primaryResource] ?? .notDownloaded
                        if downloadState == .notDownloaded {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Image(systemName: "icloud.and.arrow.down")
                                        .font(.system(size: 20, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
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
                                        .scaleEffect(0.8)
                                        .padding(14)
                                }
                            }
                        }
                    }
                }
                .shadow(
                    color: isSelected ? Color.white.opacity(0.22) : .black.opacity(0.2),
                    radius: isSelected ? 12 : 4,
                    y: 4
                )
                .scaleEffect(isHovered && !isSelected ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)

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
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .task {
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

    private func handleAction() {
        if mood.wallpaper.type == .time || primaryResource.isEmpty {
            action()
            return
        }
        
        let isDownloaded = DownloadManager.shared.isDownloaded(resource: primaryResource)
        if isDownloaded {
            action()
        } else {
            Task {
                await DownloadManager.shared.download(primaryResource)
                if DownloadManager.shared.isDownloaded(resource: primaryResource) {
                    await loadPreviewImage()
                    action()
                }
            }
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        if mood.wallpaper.type == .time {
            TimeWallpaperPreview(mood: mood, isPressed: false, targetSize: CGSize(width: 140, height: 220))
                .frame(width: 140, height: 220)
                .clipped()
        } else if isSelected,
                  let resource = mood.wallpaper.resources.first,
                  let url = MediaUtils.resolveResourceURL(resource),
                  ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            VideoBackgroundView(url: url)
                .frame(width: 140, height: 220)
                .clipped()
        } else if let image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.clear
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @MainActor
    private func loadPreviewImage() async {
        guard mood.wallpaper.type != .time,
              let resource = mood.wallpaper.resources.first else { return }

        if let cached = MoodCard.imageCache.object(forKey: resource as NSString) {
            self.image = cached
            return
        }

        let loaded = await Task(priority: .utility) { () -> NSImage? in
            if Task.isCancelled { return nil }
            guard let url = MediaUtils.resolveResourceURL(resource) else {
                return NSImage(named: resource)
            }
            if url.isFileURL {
                let ext = url.pathExtension.lowercased()
                if ["mp4", "mov"].contains(ext) {
                    let poster = await MediaUtils.videoPosterImage(from: url)
                    print("🟢 [Popover MoodCard] poster for \(resource) is \(poster == nil ? "nil" : "present")")
                    return poster ?? NSImage(named: resource)
                } else if let img = NSImage(contentsOf: url) {
                    return img
                }
                return NSImage(named: resource)
            } else {
                return NSImage(named: resource)
            }
        }.value

        if let loaded {
            print("🟢 [Popover MoodCard] Setting image for \(resource)")
            MoodCard.imageCache.setObject(loaded, forKey: resource as NSString)
            self.image = loaded
        } else {
            print("🟥 [Popover MoodCard] loadedImage is nil for \(resource)")
            self.image = nil
        }
    }
}