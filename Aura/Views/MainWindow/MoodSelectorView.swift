import SwiftUI
import AVFoundation

struct MoodSelectorView: View {
    @Bindable var appModel: AppModel
    
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 24) {
                ForEach(appModel.moodViewModel.subthemes, id: \.self) { subtheme in
                    SubthemeRow(subtheme: subtheme, appModel: appModel)
                        .id(subtheme)
                }
            }
            .padding(.vertical, 24)
            .onChange(of: appModel.moodViewModel.selectedSubtheme) { _, newSubtheme in
                if let subtheme = newSubtheme {
                    DispatchQueue.main.async {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                            proxy.scrollTo(subtheme, anchor: .top)
                        }
                    }
                }
            }
            .onAppear {
                if let subtheme = appModel.moodViewModel.selectedSubtheme {
                    DispatchQueue.main.async {
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
                                DispatchQueue.main.async {
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
                                    DispatchQueue.main.async {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            horizontalProxy.scrollTo(firstMood.id, anchor: .center)
                                        }
                                    }
                                }
                            } else if let currentMood = appModel.moodViewModel.currentMood, currentMood.subtheme == subtheme {
                                // If we are playing a mood from this subtheme, scroll to it.
                                DispatchQueue.main.async {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                        horizontalProxy.scrollTo(currentMood.id, anchor: .center)
                                    }
                                }
                            }
                        }
                }
            }
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
                    onDelete: mood.id.count > 15 ? {
                        withAnimation {
                            appModel.moodViewModel.removeMood(mood)
                        }
                    } : nil,
                    action: { selectMood(mood) }
                )
                .id(mood.id)
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 4)
    }
    
    private func selectMood(_ mood: Mood) {
        guard appModel.moodViewModel.currentMood?.id != mood.id else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            appModel.moodViewModel.selectMood(mood)
            appModel.moodViewModel.selectedSubtheme = nil
        }
    }
}

struct MoodCard: View {
    let mood: Mood
    let isSelected: Bool
    var onDelete: (() -> Void)? = nil
    let action: () -> Void
    
    @State private var image: NSImage?
    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    static let imageCache = NSCache<NSString, NSImage>()

    private var primaryResource: String {
        mood.wallpaper.resources.first ?? ""
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: handleAction) {
                if #available(macOS 16.0, *) {
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
                } else {
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
            }
            .buttonStyle(.plain)
            .focusable(false)
            
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
                TimeWallpaperPreview(mood: mood, isPressed: isPressed)
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
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .rotationEffect(Angle(degrees: isPressed ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: true)
                    }
            }
            
            // Hover Effect Overlay
            if isHovered && !isSelected {
                Color.white.opacity(0.1)
            }
            
            // Small label at the bottom-left as shown in the image
            Text(mood.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(14)
            
            // Selection indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.1))
            }

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
                    await loadPreview()
                    action()
                }
            }
        }
    }
    
    @MainActor
    private func loadPreview() async {
        if mood.wallpaper.type == .time {
            // No preview image needed for time wallpapers, they render directly
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
            print("🟢 [MoodCard] Setting image for \(resource)")
            MoodCard.imageCache.setObject(loadedImage, forKey: resource as NSString)
            self.image = loadedImage
        } else {
            print("🟥 [MoodCard] loadedImage is nil for \(resource)")
            self.image = nil
        }
    }
}

struct TimeWallpaperPreview: View {
    let mood: Mood
    let isPressed: Bool
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
                
                TimeWallpaperView(style: style, palette: mood.palette)
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