import AVFoundation
import SwiftUI

struct WallpaperPreviewSnapshot: Equatable {
    let keepCurrentWallpaper: Bool
    let mood: Mood?
    let backgroundImageURL: URL?
    let currentPrimaryWallpaperURL: URL?
    let primaryColor: ColorComponents
    let secondaryColor: ColorComponents

    init(appModel: AppModel) {
        keepCurrentWallpaper = appModel.settingsViewModel.settings.keepCurrentWallpaper
        mood = appModel.moodViewModel.currentMood
        backgroundImageURL = appModel.wallpaperEngine.backgroundImageURL
        currentPrimaryWallpaperURL = appModel.wallpaperEngine.currentPrimaryWallpaperURL
        primaryColor = appModel.themeManager.palette.primary
        secondaryColor = appModel.themeManager.palette.secondary
    }
}

struct IsolatedWallpaperPreviewView: View, Equatable {
    let snapshot: WallpaperPreviewSnapshot
    var showOverlay: Bool = true

    static func == (lhs: IsolatedWallpaperPreviewView, rhs: IsolatedWallpaperPreviewView) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.showOverlay == rhs.showOverlay
    }

    var body: some View {
        WallpaperPreviewView(snapshot: snapshot, showOverlay: showOverlay)
    }
}

struct WallpaperPreviewView: View {
    let snapshot: WallpaperPreviewSnapshot
    var showOverlay: Bool = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if snapshot.keepCurrentWallpaper {
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
                } else if let mood = snapshot.mood,
                          mood.wallpaper.type == .staticImage || mood.wallpaper.type == .dynamic || mood.wallpaper.type == .animated {
                    ZStack(alignment: .topTrailing) {
                        if let liveVideoURL = livePreviewVideoURL(for: mood) {
                            IsolatedVideoBackgroundView(url: liveVideoURL)
                                .equatable()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if mood.wallpaper.type == .animated,
                                  let resource = mood.wallpaper.resources.first,
                                  let url = MediaUtils.resolveResourceURL(resource),
                                  Self.isVideoURL(url) {
                            IsolatedVideoBackgroundView(url: url)
                                .equatable()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ZStack {
                                if let backgroundImageURL = placeholderPreviewURL {
                                    AsyncWallpaperPreviewImageView(
                                        source: .url(backgroundImageURL),
                                        maxPixelSize: 900,
                                        idToken: backgroundImageURL.absoluteString
                                    )
                                    .opacity(0.6)
                                } else {
                                    Color.black.opacity(0.3)
                                }

                                if let resource = mood.wallpaper.resources.first {
                                    AsyncWallpaperPreviewImageView(
                                        source: .resource(resource),
                                        maxPixelSize: 1400,
                                        idToken: previewRefreshID(for: mood)
                                    )
                                }
                            }
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
                } else if let mood = snapshot.mood, mood.wallpaper.type == .time {
                    if let style = mood.wallpaper.resources.first {
                        TimeWallpaperView(style: style, palette: mood.palette, selectedWallpaperURL: snapshot.backgroundImageURL, isPreview: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TimeWallpaperView(style: "minimal", palette: mood.palette, selectedWallpaperURL: snapshot.backgroundImageURL, isPreview: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else if let mood = snapshot.mood, mood.wallpaper.type == .website {
                    if let urlString = mood.wallpaper.resources.first {
                        WebsiteWallpaperView(urlString: urlString)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(colors: [
                                color(from: snapshot.primaryColor),
                                color(from: snapshot.secondaryColor)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [
                            color(from: snapshot.primaryColor),
                            color(from: snapshot.secondaryColor)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))

            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)

            if showOverlay && !snapshot.keepCurrentWallpaper, snapshot.mood != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Atmosphere")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .kerning(1)
                        .textCase(.uppercase)

                    Text(snapshot.mood?.name ?? "Default")
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

    private var placeholderPreviewURL: URL? {
        guard let backgroundImageURL = snapshot.backgroundImageURL,
              !Self.isVideoURL(backgroundImageURL) else {
            return nil
        }
        return backgroundImageURL
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    private func color(from components: ColorComponents) -> Color {
        Color(
            red: components.red,
            green: components.green,
            blue: components.blue,
            opacity: components.alpha
        )
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

        if let currentPrimaryWallpaperURL = snapshot.currentPrimaryWallpaperURL,
           Self.isVideoURL(currentPrimaryWallpaperURL),
           matches(currentPrimaryWallpaperURL, resource: resource) {
            return currentPrimaryWallpaperURL
        }

        if let backgroundImageURL = snapshot.backgroundImageURL,
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

private enum WallpaperPreviewImageSource: Equatable {
    case resource(String)
    case url(URL)
}

private struct AsyncWallpaperPreviewImageView: View {
    let source: WallpaperPreviewImageSource
    let maxPixelSize: CGFloat
    let idToken: String

    @State private var image: NSImage?

    var body: some View {
        GeometryReader { geo in
            Group {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.black.opacity(0.3)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .task(id: idToken) {
            let loaded = await loadImage()
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                image = loaded
            }
        }
        .onDisappear {
            image = nil
        }
    }

    private func loadImage() async -> NSImage? {
        switch source {
        case .resource(let resource):
            return await MediaUtils.thumbnailImage(for: resource, maxPixelSize: maxPixelSize)
        case .url(let url):
            return await MediaUtils.thumbnailImage(from: url, maxPixelSize: maxPixelSize)
        }
    }
}
