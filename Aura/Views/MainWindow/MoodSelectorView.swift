import SwiftUI
import AVFoundation
import os

struct MoodSelectorView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        ScrollViewReader { proxy in
            let subthemeSections = appModel.moodViewModel.subthemeSections
            VStack(alignment: .leading, spacing: 28) {
                ForEach(subthemeSections) { section in
                    VStack(alignment: .leading, spacing: 24) {
                        if subthemeSections.count > 1 {
                            Text(section.title.uppercased())
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white.opacity(0.55))
                                .kerning(1.2)
                                .padding(.horizontal, 40)
                        }

                        ForEach(section.subthemes, id: \.self) { subtheme in
                            SubthemeRow(subtheme: subtheme, appModel: appModel)
                                .id(subtheme)
                        }
                    }
                }
            }
            .padding(.vertical, 24)
            .onChange(of: appModel.moodViewModel.selectedSubtheme) { _, newSubtheme in
                if let subtheme = newSubtheme {
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            proxy.scrollTo(subtheme, anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                if let subtheme = appModel.moodViewModel.selectedSubtheme {
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            proxy.scrollTo(subtheme, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

struct SubthemeRow: View {
    let subtheme: String
    @Bindable var appModel: AppModel
    @State private var showingWebsiteManager = false
    @State private var showingImagePlaygroundDesigner = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(subtheme.uppercased())
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .kerning(1.2)
                .padding(.horizontal, 40)

            ScrollView(.horizontal, showsIndicators: false) {
                ScrollViewReader { horizontalProxy in
                    moodList
                        .onChange(of: appModel.moodViewModel.currentMood) { _, newMood in
                            if let mood = newMood, mood.subtheme == subtheme {
                                Task { @MainActor in
                                    await Task.yield()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        horizontalProxy.scrollTo(mood.id, anchor: .center)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // If this subtheme is currently selected but we are not currently playing a mood from it,
                            // scroll to the first mood of this subtheme.
                            if appModel.moodViewModel.selectedSubtheme == subtheme {
                                if let firstMood = appModel.moodViewModel.moodsBySubtheme[subtheme]?.first {
                                    Task { @MainActor in
                                        await Task.yield()
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            horizontalProxy.scrollTo(firstMood.id, anchor: .center)
                                        }
                                    }
                                }
                            } else if let currentMood = appModel.moodViewModel.currentMood, currentMood.subtheme == subtheme {
                                // If we are playing a mood from this subtheme, scroll to it.
                                Task { @MainActor in
                                    await Task.yield()
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        horizontalProxy.scrollTo(currentMood.id, anchor: .center)
                                    }
                                }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $showingWebsiteManager) {
            WebsiteManagerView(appModel: appModel)
        }
        .sheet(isPresented: $showingImagePlaygroundDesigner) {
            CreateMoodView(
                appModel: appModel,
                defaultTheme: "Dynamic",
                defaultSubtheme: subtheme.caseInsensitiveCompare("Create with AI") == .orderedSame ? "Create with AI" : (subtheme.caseInsensitiveCompare("Image Playground") == .orderedSame ? "Image Playground" : "Dynamic Desktop"),
                initialWallpaperSource: subtheme.caseInsensitiveCompare("Create with AI") == .orderedSame ? .aiGenerated : .imagePlayground
            )
        }
    }

    @ViewBuilder
    private var moodList: some View {
        LazyHStack(spacing: 16) {
            let subthemeMoods = appModel.moodViewModel.moodsBySubtheme[subtheme] ?? []
            ForEach(subthemeMoods, id: \.id) { mood in
                MoodCard(
                    mood: mood,
                    isSelected: appModel.moodViewModel.currentMood?.id == mood.id,
                    isFavorite: appModel.favoriteSceneIDs.contains(mood.id),
                    selectedWallpaperURL: appModel.wallpaperEngine.selectedWallpaperURL,
                    onToggleFavorite: {
                        appModel.toggleFavoriteScene(mood.id)
                    },
                    onDelete: UUID(uuidString: mood.id) != nil ? {
                        withAnimation {
                            appModel.moodViewModel.removeMood(mood)
                        }
                    } : nil,
                    action: { force in selectMood(mood, forceApply: force) }
                )
                .id(mood.id)
            }

            if ["Website", "Websites"].contains(where: { subtheme.caseInsensitiveCompare($0) == .orderedSame }) {
                CreateWebsiteCard {
                    showingWebsiteManager = true
                }
            }

            if ["Create with AI", "Dynamic Desktop", "Image Playground"].contains(where: { subtheme.caseInsensitiveCompare($0) == .orderedSame }) {
                CreateImagePlaygroundCard {
                    showingImagePlaygroundDesigner = true
                }
                .environment(
                    \.createImagePlaygroundCardStyle,
                    subtheme.caseInsensitiveCompare("Create with AI") == .orderedSame
                        ? .createWithAI
                        : (subtheme.caseInsensitiveCompare("Image Playground") == .orderedSame ? .imagePlayground : .dynamicDesktop)
                )
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 4)
    }

    private func selectMood(_ mood: Mood, forceApply: Bool = false) {
        if forceApply {
            // Only force apply if this mood is still the currently selected one
            guard appModel.moodViewModel.currentMood?.id == mood.id else { return }
        } else {
            guard appModel.moodViewModel.currentMood?.id != mood.id else { return }
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            appModel.moodViewModel.selectMood(mood)
            appModel.moodViewModel.selectedSubtheme = nil
        }
    }
}

struct CreateWebsiteCard: View {
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text("Create new\nWebsite")
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .padding(16)
            .frame(width: 120, height: 160)
            .liquidGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false, variant: .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.42 : 0.24), lineWidth: isHovered ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.24 : 0.16), radius: isHovered ? 14 : 10, y: 6)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel("Create a new website")
        .accessibilityAddTraits(.isButton)
    }
}

private enum CreateImagePlaygroundCardStyle {
    case createWithAI
    case dynamicDesktop
    case imagePlayground

    var title: String {
        switch self {
        case .createWithAI:
            return "Create\nwith AI"
        case .dynamicDesktop:
            return "Create\nDynamic Desktop"
        case .imagePlayground:
            return "Design with\nImage Playground"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .createWithAI:
            return "Create a wallpaper with Stable Diffusion"
        case .dynamicDesktop:
            return "Create a dynamic desktop wallpaper"
        case .imagePlayground:
            return "Design a wallpaper with Image Playground"
        }
    }
}

private struct CreateImagePlaygroundCardStyleKey: EnvironmentKey {
    static let defaultValue: CreateImagePlaygroundCardStyle = .dynamicDesktop
}

private extension EnvironmentValues {
    var createImagePlaygroundCardStyle: CreateImagePlaygroundCardStyle {
        get { self[CreateImagePlaygroundCardStyleKey.self] }
        set { self[CreateImagePlaygroundCardStyleKey.self] = newValue }
    }
}

struct CreateImagePlaygroundCard: View {
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.createImagePlaygroundCardStyle) private var style

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))

                Text(style.title)
                    .font(.system(size: 14, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
            }
            .padding(16)
            .frame(width: 140, height: 160)
            .liquidGlass(RoundedRectangle(cornerRadius: 20, style: .continuous), interactive: false, variant: .clear)
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.42 : 0.24), lineWidth: isHovered ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(isHovered ? 0.24 : 0.16), radius: isHovered ? 14 : 10, y: 6)
            .scaleEffect(isHovered ? 1.03 : 1.0)
            .scaleEffect(isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.68), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .accessibilityLabel(style.accessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }
}

struct MoodCard: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "MoodCard")

    let mood: Mood
    let isSelected: Bool
    let isFavorite: Bool
    let selectedWallpaperURL: URL?
    let onToggleFavorite: () -> Void
    var onDelete: (() -> Void)?
    let action: (Bool) -> Void

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showExportSuccess = false
    @State private var image: NSImage?
    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    static let imageCache = NSCache<NSString, NSImage>()

    private var primaryResource: String {
        mood.wallpaper.resources.first ?? ""
    }

    private var isDynamicDesktop: Bool {
        mood.wallpaper.type == .dynamic || (mood.wallpaper.resources.first?.lowercased().hasSuffix(".heic") ?? false)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleAction) {
                cardContent
                    .background {
                        if reduceTransparency {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.regularMaterial)
                        } else {
                            Color.clear
                                .glassEffect(isSelected ? .regular.interactive() : .clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .shadow(color: .black.opacity(isSelected ? 0.4 : 0.2), radius: isSelected ? 15 : 10, y: 5)
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .scaleEffect(isPressed ? 0.98 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isHovered)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if canToggleFavorite {
                VStack {
                    HStack {
                        Button(action: onToggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isFavorite ? Color.yellow : .white.opacity(0.92))
                                .padding(8)
                                .background(.black.opacity(0.28), in: Circle())
                                .shadow(radius: 4)
                        }
                        .buttonStyle(.plain)
                        .padding(10)

                        Spacer()
                    }

                    Spacer()
                }
                .transition(.scale.combined(with: .opacity))
            }

            if isDynamicDesktop {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        if isExporting {
                            ProgressView()
                                .controlSize(.small)
                                .padding(10)
                                .background(.black.opacity(0.4), in: Circle())
                                .padding(10)
                        } else {
                            Button(action: exportHEIC) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .padding(8)
                                    .background(.black.opacity(0.28), in: Circle())
                                    .shadow(radius: 4)
                            }
                            .buttonStyle(.plain)
                            .padding(10)
                            .help("Download .heic Dynamic Desktop")
                        }
                    }
                }
            }

            if let onDelete = onDelete, isHovered {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.red.opacity(0.8))
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white).padding(2))
                        .shadow(radius: 4)
                }
                .buttonStyle(.plain)
                .padding(8)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task {
            if !primaryResource.isEmpty {
                DownloadManager.shared.checkStatus(for: primaryResource)
            }
            await loadPreview()
        }
        .onChange(of: DownloadManager.shared.downloadStates[primaryResource]) { _, newState in
            if newState == .downloaded {
                Task {
                    await loadPreview()
                }
            }
        }
    }

    private var cardContent: some View {
        ZStack(alignment: .bottomLeading) {
            // Background Image
            if mood.wallpaper.type == .time {
                // Time wallpaper specific preview
                TimeWallpaperPreview(mood: mood, isPressed: isPressed, selectedWallpaperURL: selectedWallpaperURL)
            } else if mood.wallpaper.type == .website {
                WebsiteWallpaperPreview(mood: mood, isPressed: isPressed)
            } else if let image = image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 240, height: 160)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                Group {
                    if reduceTransparency {
                        Rectangle()
                            .fill(.regularMaterial)
                    } else {
                        Color.clear
                            .glassEffect(.regular, in: Rectangle())
                    }
                }
                .frame(width: 240, height: 160)
                .overlay {
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }

            if isHovered && !isSelected {
                Color.white.opacity(0.1)
            }

            Text(mood.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(14)

            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white, lineWidth: 2)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )
            }

            if mood.wallpaper.type != .time, mood.wallpaper.type != .website, !primaryResource.isEmpty {
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
                } else if case .failed = downloadState {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "exclamationmark.icloud")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.red)
                                .shadow(radius: 2)
                                .padding(14)
                        }
                    }
                }
            }
        }
        .frame(width: 240, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var canToggleFavorite: Bool {
        if mood.wallpaper.type == .time || mood.wallpaper.type == .website {
            return true
        }

        guard !primaryResource.isEmpty else {
            return isFavorite
        }

        return isFavorite || DownloadManager.shared.downloadStates[primaryResource] == .downloaded
    }

    private func handleAction() {
        if mood.wallpaper.type == .time || mood.wallpaper.type == .website || primaryResource.isEmpty {
            action(false)
            return
        }

        let isDownloaded = DownloadManager.shared.isDownloaded(resource: primaryResource)
        if isDownloaded {
            action(false)
        } else {
            // First call action to select the mood immediately and show fallback gradient
            action(false)

            Task {
                await DownloadManager.shared.download(primaryResource)
                if DownloadManager.shared.isDownloaded(resource: primaryResource) {
                    await loadPreview()
                    action(true) // Force re-apply to trigger wallpaper change
                }
            }
        }
    }

    private func exportHEIC() {
        guard !isExporting else { return }

        isExporting = true
        exportError = nil

        Task {
            do {
                let tempURL = try await MoodViewModel.exportDynamicDesktop(mood: mood)

                // Show save panel to let user choose where to save
                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.heic]
                savePanel.canCreateDirectories = true
                savePanel.nameFieldStringValue = "\(mood.name.replacingOccurrences(of: " ", with: "_")).heic"
                savePanel.title = "Save Dynamic Desktop"
                savePanel.message = "Choose a location to save your Dynamic Desktop wallpaper."

                if savePanel.runModal() == .OK, let destinationURL = savePanel.url {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try? FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: tempURL, to: destinationURL)
                    showExportSuccess = true
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                Self.logger.error("Export failed: \(error.localizedDescription, privacy: .public)")
                exportError = error.localizedDescription
            }
            isExporting = false
        }
    }

    @MainActor
    private func loadPreview() async {
        if mood.wallpaper.type == .time {
            // No preview image needed for programmatic wallpapers, they render directly
            return
        }

        guard let resource = mood.wallpaper.resources.first, !resource.isEmpty else { return }

        // Return cached image if available
        if let cached = MoodCard.imageCache.object(forKey: resource as NSString) {
            self.image = cached
            return
        }

        let loadedImage = await Task(priority: .utility) { () -> NSImage? in
            if Task.isCancelled { return nil }

            // First check if the resource is an un-downloaded file from the Github release.
            // Try to resolve the URL, but don't fail immediately if it's nil.
            let resolvedURL = MediaUtils.resolveResourceURL(resource)

            // Check if it's a known video file format that we might need to load from local cache or bundle
            let ext = (resolvedURL?.pathExtension ?? (resource as NSString).pathExtension).lowercased()
            let isVideo = ["mp4", "mov"].contains(ext)

            if let url = resolvedURL {
                if url.isFileURL {
                    let path = url.path
                    let exists = FileManager.default.fileExists(atPath: path)

                    if exists {
                        if isVideo {
                            let poster = await MediaUtils.videoPosterImage(from: url)
                            if let poster = poster {
                                return poster
                            }
                        } else if let img = NSImage(contentsOf: url) {
                            return img
                        }
                    }
                }
            }

            // Fallback: If URL resolution failed or file doesn't exist locally,
            // try to load an image with the same base name from the asset catalog (as a placeholder)
            let baseName = (resource as NSString).deletingPathExtension
            if let image = NSImage(named: baseName) {
                return image
            }

            // If we have an image in the asset catalog matching the exact resource name
            if let image = NSImage(named: resource) {
                return image
            }

            return nil
        }.value

        guard !Task.isCancelled else { return }

        if let loadedImage {
            Self.logger.debug("Setting image for \(resource, privacy: .public)")
            MoodCard.imageCache.setObject(loadedImage, forKey: resource as NSString)
            self.image = loadedImage
        } else {
            Self.logger.error("Loaded image is nil for \(resource, privacy: .public)")
            self.image = nil
        }
    }
}

struct TimeWallpaperPreview: View {
    let mood: Mood
    let isPressed: Bool
    let selectedWallpaperURL: URL?
    var targetSize: CGSize = CGSize(width: 240, height: 160)

    var body: some View {
        ZStack {
            if let style = mood.wallpaper.resources.first {
                // Always render at a standard 16:9 landscape resolution
                let baseSize = CGSize(width: 1920, height: 1080)

                // Calculate scale to aspect-fill the target size
                let scaleX = targetSize.width / baseSize.width
                let scaleY = targetSize.height / baseSize.height
                let scale = max(scaleX, scaleY)

                TimeWallpaperView(style: style, palette: mood.palette, selectedWallpaperURL: selectedWallpaperURL, isPreview: true)
                    .frame(width: baseSize.width, height: baseSize.height)
                    .scaleEffect(scale)
                    .frame(width: targetSize.width, height: targetSize.height)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct WebsiteWallpaperPreview: View {
    let mood: Mood
    let isPressed: Bool
    var targetSize: CGSize = CGSize(width: 240, height: 160)

    var body: some View {
        ZStack {
            if let urlString = mood.wallpaper.resources.first {
                WebsiteWallpaperView(urlString: urlString, isPreview: true)
                    .frame(width: targetSize.width, height: targetSize.height)
                    .clipped()
                    .allowsHitTesting(false)
            }
        }
        .frame(width: targetSize.width, height: targetSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
