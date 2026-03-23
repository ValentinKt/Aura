import AVFoundation
import SwiftUI

struct WallpaperPreviewView: View {
    @Bindable var appModel: AppModel
    var showOverlay: Bool = true
    @State private var previewImage: NSImage? = nil
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
                          (mood.wallpaper.type == .staticImage || mood.wallpaper.type == .dynamic || mood.wallpaper.type == .animated) {
                    ZStack(alignment: .topTrailing) {
                        if mood.wallpaper.type == .animated, let resource = mood.wallpaper.resources.first, let url = MediaUtils.resolveResourceURL(resource) {
                            VideoBackgroundView(url: url)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let image = previewImage {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            // Fallback if image not found or loading
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
                    .task(id: mood.id) {
                        if let resource = mood.wallpaper.resources.first {
                            previewImage = await loadPreviewImageAsync(resource)
                        } else {
                            previewImage = nil
                        }
                    }
                } else if let mood = appModel.moodViewModel.currentMood, mood.wallpaper.type == .time {
                    if let style = mood.wallpaper.resources.first {
                        TimeWallpaperView(style: style, palette: mood.palette)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        TimeWallpaperView(style: "minimal", palette: mood.palette)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        
        return await Task.detached(priority: .userInitiated) {
            if let image = NSImage(contentsOf: url) {
                return image
            }
            return NSImage(named: resource)
        }.value
    }
}
