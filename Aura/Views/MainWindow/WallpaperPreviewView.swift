import AVFoundation
import SwiftUI

struct WallpaperPreviewView: View {
    @Bindable var appModel: AppModel
    var showOverlay: Bool = true
    @State private var previewImage: NSImage?
    /// Async-loaded placeholder shown while the next image loads — avoids any synchronous disk reads in the body.
    @State private var cachedPlaceholderImage: NSImage?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if appModel.settingsViewModel.settings.keepCurrentWallpaper {
                    // Show current wallpaper indicator
                    ZStack {
                        Color.black.opacity(0.8)
                        VStack(spacing: 8) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 32))
                            Text("System Wallpaper")
                                .font(.system(size: 14, weight: .medium))
                            Text("Aura is using your current desktop image.")
                                .font(.system(size: 11))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .foregroundStyle(.white.opacity(0.7))
                    }
                } else if let mood = appModel.moodViewModel.currentMood,
                          mood.wallpaper.type == .staticImage || mood.wallpaper.type == .dynamic || mood.wallpaper.type == .animated {
                    ZStack(alignment: .topTrailing) {
                        if let liveVideoURL = livePreviewVideoURL(for: mood) {
                            IsolatedVideoBackgroundView(url: liveVideoURL)
                                .equatable()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if mood.wallpaper.type == .animated,
                                  let resource = mood.wallpaper.resources.first,
                                  let url = MediaUtils.resolveResourceURL(resource) {
                            IsolatedVideoBackgroundView(url: url)
                                .equatable()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let image = previewImage {
                            GeometryReader { geo in
                                Image(nsImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            }
                            .transition(.opacity)
                        } else if let placeholder = cachedPlaceholderImage {
                            // Async-loaded placeholder so we never block the main thread
                            GeometryReader { geo in
                                Image(nsImage: placeholder)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: geo.size.width, height: geo.size.height)
                                    .clipped()
                            }
                            .opacity(0.6)
                        } else {
                            Color.black.opacity(0.3)
                        }

                        if mood.wallpaper.type == .dynamic && showOverlay {
                            HStack(spacing: 4) {
                                Image(systemName: "clock.arrow.2.circlepath")
                                Text("Dynamic")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
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
                            .padding(12)
                        }
                    }
                    .task(id: previewRefreshID(for: mood)) {
                        guard livePreviewVideoURL(for: mood) == nil else {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                previewImage = nil
                            }
                            return
                        }

                        if let resource = mood.wallpaper.resources.first {
                            let loaded = await loadPreviewImageAsync(resource)
                            withAnimation(.easeInOut(duration: 0.35)) {
                                previewImage = loaded
                            }
                        } else {
                            withAnimation(.easeInOut(duration: 0.35)) {
                                previewImage = nil
                            }
                        }
                    }
                    // Async-load the placeholder from backgroundImageURL so the body never blocks
                    .task(id: appModel.wallpaperEngine.backgroundImageURL) {
                        guard let bgURL = appModel.wallpaperEngine.backgroundImageURL,
                              !Self.isVideoURL(bgURL) else {
                            cachedPlaceholderImage = nil
                            return
                        }
                        cachedPlaceholderImage = await Task(priority: .utility) {
                            NSImage(contentsOf: bgURL)
                        }.value
                    }
                } else if let mood = appModel.moodViewModel.currentMood, mood.wallpaper.type == .time {
                    if let style = mood.wallpaper.resources.first {
                        TimeWallpaperView(style: style, palette: mood.palette, selectedWallpaperURL: appModel.wallpaperEngine.backgroundImageURL, isPreview: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TimeWallpaperView(style: "minimal", palette: mood.palette, selectedWallpaperURL: appModel.wallpaperEngine.backgroundImageURL, isPreview: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let mood = appModel.moodViewModel.currentMood, mood.wallpaper.type == .website {
                    if let urlString = mood.wallpaper.resources.first {
                        WebsiteWallpaperView(urlString: urlString)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    } else {
                        // Fallback to gradient
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [
                                appModel.themeManager.color(from: appModel.themeManager.palette.primary),
                                appModel.themeManager.color(from: appModel.themeManager.palette.secondary)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                } else {
                    // Fallback to gradient
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [
                            appModel.themeManager.color(from: appModel.themeManager.palette.primary),
                            appModel.themeManager.color(from: appModel.themeManager.palette.secondary)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Subtle border around the wallpaper
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)

            if showOverlay && !appModel.settingsViewModel.settings.keepCurrentWallpaper, appModel.moodViewModel.currentMood != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Atmosphere")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .kerning(1)
                        .textCase(.uppercase)

                    Text(appModel.moodViewModel.currentMood?.name ?? "Default")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(16)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                )
            }
        }
    }

    private func loadPreviewImageAsync(_ resource: String) async -> NSImage? {
        guard let url = MediaUtils.resolveResourceURL(resource) else {
            return NSImage(named: resource)
        }

        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
            return await MediaUtils.videoPosterImage(from: url)
        }

        return await Task(priority: .userInitiated) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
            return NSImage(named: resource)
        }.value
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    private func previewRefreshID(for mood: Mood) -> String {
        let resource = mood.wallpaper.resources.first ?? ""
        let downloadStateDescription = {
            switch DownloadManager.shared.downloadStates[resource] {
            case .notDownloaded, .none:
                return "not-downloaded"
            case .downloaded:
                return "downloaded"
            case .downloading(let progress):
                return "downloading-\(Int(progress * 1000))"
            case .failed(let error):
                return "failed-\(error)"
            }
        }()

        let liveVideoPath = livePreviewVideoURL(for: mood)?.path ?? "no-video"
        return "\(mood.id)|\(resource)|\(downloadStateDescription)|\(liveVideoPath)"
    }

    private func livePreviewVideoURL(for mood: Mood) -> URL? {
        guard let resource = mood.wallpaper.resources.first else {
            return nil
        }

        if let exactResourceURL = MediaUtils.resolveExactResourceURL(resource),
           Self.isVideoURL(exactResourceURL) {
            return exactResourceURL
        }

        if let currentPrimaryWallpaperURL = appModel.wallpaperEngine.currentPrimaryWallpaperURL,
           Self.isVideoURL(currentPrimaryWallpaperURL),
           matches(currentPrimaryWallpaperURL, resource: resource) {
            return currentPrimaryWallpaperURL
        }

        if let backgroundImageURL = appModel.wallpaperEngine.backgroundImageURL,
           Self.isVideoURL(backgroundImageURL),
           matches(backgroundImageURL, resource: resource) {
            return backgroundImageURL
        }

        return nil
    }

    private func matches(_ url: URL, resource: String) -> Bool {
        let resolvedName = url.deletingPathExtension().lastPathComponent.lowercased()
        let resourceName = URL(fileURLWithPath: resource).deletingPathExtension().lastPathComponent.lowercased()
        return !resolvedName.isEmpty && resolvedName == resourceName
    }
}
