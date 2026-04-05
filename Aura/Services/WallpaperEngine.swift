import AppKit
import AVFoundation
import CoreImage
import Observation
import os
import SwiftUI
import WebKit

struct WallpaperApplyResult: Hashable {
    var success: Bool
    var permissionDenied: Bool
}

final class AnimatedGradientLayer: CAGradientLayer {
    private var isAnimating = false

    func startAnimation(with stops: [ColorComponents]) {
        guard !isAnimating else { return }

        let cgColors = stops.map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha).cgColor }

        // Shift colors slightly for the "to" value to create a breathing effect
        let shiftedColors = stops.map { stop in
            NSColor(
                red: max(0, min(1, stop.red + 0.1)),
                green: max(0, min(1, stop.green + 0.1)),
                blue: max(0, min(1, stop.blue + 0.1)),
                alpha: stop.alpha
            ).cgColor
        }

        self.colors = cgColors
        self.startPoint = CGPoint(x: 0.0, y: 0.0)
        self.endPoint = CGPoint(x: 1.0, y: 1.0)

        let anim = CABasicAnimation(keyPath: "colors")
        anim.fromValue = cgColors
        anim.toValue = shiftedColors
        anim.duration = 10.0
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        add(anim, forKey: "colorShift")
        isAnimating = true
    }

    func stopAnimation() {
        removeAnimation(forKey: "colorShift")
        isAnimating = false
    }
}

final class AnimatedGradientNSView: NSView {
    private let gradientLayer = AnimatedGradientLayer()

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        if layer?.sublayers?.contains(gradientLayer) == false {
            layer?.addSublayer(gradientLayer)
        }
        if window == nil {
            gradientLayer.stopAnimation()
        }
    }

    func setStops(_ stops: [ColorComponents]) {
        gradientLayer.startAnimation(with: stops)
    }
}

struct AnimatedGradientView: NSViewRepresentable {
    let stops: [ColorComponents]

    func makeNSView(context: Context) -> AnimatedGradientNSView {
        let view = AnimatedGradientNSView()
        view.setStops(stops)
        return view
    }

    func updateNSView(_ nsView: AnimatedGradientNSView, context: Context) {
        nsView.setStops(stops)
    }
}

struct AnimatedParticleView: View {
    var body: some View {
        Color.black.ignoresSafeArea()
    }
}

struct FallbackImageView: View {
    let url: URL?
    let fallbackImage: NSImage?

    @State private var loadedImage: NSImage?

    init(url: URL) {
        self.url = url
        self.fallbackImage = nil
    }

    init(image: NSImage) {
        self.url = nil
        self.fallbackImage = image
    }

    var body: some View {
        if let fallbackImage = fallbackImage {
            Image(nsImage: fallbackImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else if let loadedImage = loadedImage {
            Image(nsImage: loadedImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
                .task {
                    if let url = url {
                        loadedImage = await loadAsyncImage(from: url)
                    }
                }
        }
    }

    private func loadAsyncImage(from url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            let isScoped = url.startAccessingSecurityScopedResource()
            defer { if isScoped { url.stopAccessingSecurityScopedResource() } }
            return NSImage(contentsOf: url)
        }.value
    }
}

struct WallpaperDisplayPreview: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let wallpaperURL: URL?
    let isPrimary: Bool
}

@MainActor
@Observable
final class WallpaperEngine {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "Wallpaper")
    private let fileManager = FileManager.default
    private let themeManager: ThemeManager
    private let wallpaperDirectory: URL
    private let imageProcessingContext: CIContext = {
        // Use the system Metal device for GPU-accelerated Core Image processing.
        // This offloads CIFilter chains (blur, colour correction) to the GPU,
        // freeing CPU cores for the audio engine and Swift concurrency runtime.
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device, options: [
                .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                .cacheIntermediates: false
            ])
        }
        return CIContext(options: [.cacheIntermediates: false])
    }()
    private let wallpaperWindowController = WallpaperWindowController()

    var selectedWallpaperURL: URL? {
        guard let selectedWallpaperResource else { return nil }
        return resolveResourceURL(selectedWallpaperResource)
    }

    /// The last resolved image/video URL from a static or animated wallpaper.
    /// Time views use this to render the Image Playground (or other) wallpaper as their background.
    var backgroundImageURL: URL?
    var currentPrimaryWallpaperURL: URL?
    var currentSecondaryWallpaperURL: URL?
    
    private var isPresentationSuppressed = false
    private var pendingDescriptor: WallpaperDescriptor?


    var displayWallpaperPreviews: [WallpaperDisplayPreview] {
        let screens = NSScreen.screens
        let primaryURL = currentPrimaryWallpaperURL ?? backgroundImageURL ?? selectedWallpaperURL
        let secondaryURL = currentSecondaryWallpaperURL ?? primaryURL

        if screens.isEmpty {
            return [
                WallpaperDisplayPreview(
                    id: "current-display",
                    title: "Current Display",
                    subtitle: "No external display metadata available",
                    wallpaperURL: primaryURL,
                    isPrimary: true
                )
            ]
        }

        let primaryScreenID = primaryScreenIdentifier(from: screens)
        var secondaryIndex = 1

        return screens.map { screen in
            let isPrimary = screen.localizedName == primaryScreenID
            let title: String
            if screens.count == 1 {
                title = "Current Display"
            } else if isPrimary {
                title = "Primary Display"
            } else {
                title = "Secondary Display \(secondaryIndex)"
                secondaryIndex += 1
            }

            return WallpaperDisplayPreview(
                id: screen.localizedName,
                title: title,
                subtitle: screen.localizedName,
                wallpaperURL: isPrimary ? primaryURL : secondaryURL,
                isPrimary: isPrimary
            )
        }
    }

    private var selectedWallpaperResource: String?

    func setPresentationSuppressed(_ suppressed: Bool) {
        let changed = isPresentationSuppressed != suppressed
        isPresentationSuppressed = suppressed
        
        if changed && !suppressed, let pending = pendingDescriptor {
            pendingDescriptor = nil
            Task {
                await applyWallpaper(pending)
            }
        }
    }

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self.wallpaperDirectory = fileManager.temporaryDirectory.appendingPathComponent("AuraWallpapers", isDirectory: true)
        setupDirectory()
    }

    func setWebsiteWallpaperInteractive(_ interactive: Bool) {
        wallpaperWindowController.setWebsiteInteractive(interactive)
    }

    private func setupDirectory() {
        if !fileManager.fileExists(atPath: wallpaperDirectory.path) {
            try? fileManager.createDirectory(at: wallpaperDirectory, withIntermediateDirectories: true)
        }
    }

    func applyWallpaper(_ descriptor: WallpaperDescriptor) async -> WallpaperApplyResult {
        logger.notice("Applying wallpaper of type \(String(describing: descriptor.type), privacy: .public)")

        let storesConcreteWallpaper = descriptor.type == .staticImage
            || descriptor.type == .animated
            || descriptor.type == .dynamic

        if storesConcreteWallpaper {
            selectedWallpaperResource = descriptor.resources.first
            if let resource = descriptor.resources.first {
                backgroundImageURL = resolveResourceURL(resource)
            }
        }

        if isPresentationSuppressed {
            logger.notice("Presentation suppressed, caching descriptor for later application")
            pendingDescriptor = descriptor
            return WallpaperApplyResult(success: true, permissionDenied: false)
        }


        let isStatic = descriptor.type == .staticImage || descriptor.type == .dynamic || descriptor.type == .current

        // For non-static types (animated, time, website, particle, gradient),
        // tear down the window-based overlay before installing the new one.
        // For static/dynamic/current, stopAll() is called after the image is applied
        // to avoid a blank flash during the transition.
        if !isStatic {
            wallpaperWindowController.stopAll()
        }

        let result: WallpaperApplyResult
        switch descriptor.type {
        case .staticImage:
            result = await applyStaticAsync(descriptor)
            wallpaperWindowController.stopAll()
        case .gradient:
            result = await applyGradientAsync(descriptor)
        case .animated:
            startAnimated(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .particle:
            startParticle(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .current:
            result = WallpaperApplyResult(success: true, permissionDenied: false)
            wallpaperWindowController.stopAll()
        case .dynamic:
            result = await applyStaticAsync(descriptor)
            wallpaperWindowController.stopAll()
        case .time:
            startTime(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .website:
            startWebsite(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        }

        return result
    }


    private func applyStaticAsync(_ descriptor: WallpaperDescriptor) async -> WallpaperApplyResult {
        guard let resource = descriptor.resources.first else {
            return WallpaperApplyResult(success: false, permissionDenied: false)
        }

        if let resolvedURL = resolveResourceURL(resource) {
            let secondaryURL = await renderSecondaryWallpaperVariantURL(from: resolvedURL)
            return await applyScreenWallpaperURLsAsync(primaryURL: resolvedURL, secondaryURL: secondaryURL)
        }

        logger.error("Could not find wallpaper resource \(resource, privacy: .public)")
        return WallpaperApplyResult(success: false, permissionDenied: false)
    }



    private func applyGradientAsync(_ descriptor: WallpaperDescriptor) async -> WallpaperApplyResult {
        if let image = await renderGradientImageAsync(stops: descriptor.gradientStops),
           let secondaryImage = await renderGradientImageAsync(stops: subduedGradientStops(from: descriptor.gradientStops)),
           let urls = await writeWallpaperImagesAsync([image, secondaryImage]) {
            return await applyScreenWallpaperURLsAsync(primaryURL: urls[0], secondaryURL: urls[1])
        }
        return WallpaperApplyResult(success: false, permissionDenied: false)
    }

    private func startAnimated(_ descriptor: WallpaperDescriptor) {
        if let resource = descriptor.resources.first {
            if let resolvedURL = resolveResourceURL(resource) {
                let ext = resolvedURL.pathExtension.lowercased()
                if ["mp4", "mov"].contains(ext) {
                    Task {
                        await self.applyOverlayBackdrops(primaryResourceURL: resolvedURL)
                    }
                    // Play directly via window controller — no separate wrapper function needed.
                    wallpaperWindowController.playVideo(url: resolvedURL)
                    return
                } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                    Task {
                        await self.applyOverlayBackdrops(primaryResourceURL: resolvedURL)
                    }
                    let imageView = FallbackImageView(url: resolvedURL)
                    wallpaperWindowController.showSwiftUIView(imageView)
                    return
                }
            } else {
                let resourceNameWithoutExtension = (resource as NSString).deletingPathExtension
                if let placeholderImage = NSImage(named: resource) ?? NSImage(named: resourceNameWithoutExtension) {
                    Task {
                        await self.applyOverlayBackdrops()
                    }
                    let imageView = FallbackImageView(image: placeholderImage)
                    wallpaperWindowController.showSwiftUIView(imageView)
                    return
                } else {
                    let palette = self.themeManager.palette
                    let stops = [palette.primary, palette.secondary]
                    let gradientView = AnimatedGradientView(stops: stops)
                    wallpaperWindowController.showSwiftUIView(gradientView)
                    return
                }
            }
        }

        let stops = descriptor.gradientStops
        let gradientView = AnimatedGradientView(stops: stops)
        wallpaperWindowController.showSwiftUIView(gradientView)
    }

    private func resolveResourceURL(_ resource: String) -> URL? {
        let fileManager = FileManager.default
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let videosDir = appSupport.appendingPathComponent("Aura/Videos", isDirectory: true)
            let videoURL = videosDir.appendingPathComponent(resource)
            if fileManager.fileExists(atPath: videoURL.path) {
                return videoURL
            }

            let customDir = appSupport.appendingPathComponent("Aura/CustomWallpapers", isDirectory: true)
            let customURL = customDir.appendingPathComponent(resource)
            if fileManager.fileExists(atPath: customURL.path) {
                return customURL
            }
        }

        // Use shared logic from MediaUtils if possible, or replicate it here for independence
        if let sharedResolved = MediaUtils.resolveExactResourceURL(resource) ?? MediaUtils.resolveResourceURL(resource) {
            return sharedResolved
        }

        // Additional local checks for WallpaperEngine (like the temp directory)
        let localURL = wallpaperDirectory.appendingPathComponent(resource)
        if fileManager.fileExists(atPath: localURL.path) {
            return localURL
        }

        return nil
    }

    private func startParticle(_ descriptor: WallpaperDescriptor) {
        wallpaperWindowController.showSwiftUIView(AnimatedParticleView())
    }

    private func startTime(_ descriptor: WallpaperDescriptor) {
        Task {
            await applyOverlayBackdrops()
        }
        let style = descriptor.resources.first ?? "minimal"
        let palette = themeManager.palette
        let timeView = TimeWallpaperView(style: style, palette: palette, selectedWallpaperURL: backgroundImageURL)
        wallpaperWindowController.showSwiftUIView(timeView)
    }

    private func startWebsite(_ descriptor: WallpaperDescriptor) {
        guard let urlString = descriptor.resources.first,
              let url = resolvedWebsiteURL(from: urlString) else { return }
        Task {
            await applyOverlayBackdrops()
        }
        wallpaperWindowController.showWebsite(url: url)
    }

    private func resolvedWebsiteURL(from urlString: String) -> URL? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // If it's already a valid URL with a scheme, use it as-is
        if let url = URL(string: trimmed), let scheme = url.scheme, !scheme.isEmpty {
            return url
        }

        // If it points to a local file path, return a file URL
        if FileManager.default.fileExists(atPath: trimmed) {
            return URL(fileURLWithPath: trimmed)
        }

        // Otherwise, try to assume https if no scheme provided
        if let url = URL(string: "https://\(trimmed)") {
            return url
        }

        return nil
    }

    @MainActor
    private func applyScreenWallpaperURLsAsync(primaryURL: URL, secondaryURL: URL?) async -> WallpaperApplyResult {
        var permissionDenied = false
        var applied = false
        let screens = NSScreen.screens
        updateCurrentWallpaperURLs(primaryURL: primaryURL, secondaryURL: secondaryURL)

        if screens.isEmpty {
            return WallpaperApplyResult(
                success: FileManager.default.fileExists(atPath: primaryURL.path),
                permissionDenied: false
            )
        }

        let primaryScreenID = primaryScreenIdentifier(from: screens)

        for screen in screens {
            let targetURL: URL
            if screen.localizedName == primaryScreenID {
                targetURL = primaryURL
            } else {
                targetURL = secondaryURL ?? primaryURL
            }

            do {
                try NSWorkspace.shared.setDesktopImageURL(targetURL, for: screen, options: [:])
                applied = true
            } catch let error as NSError {
                logger.error("Error setting desktop image URL: \(error.localizedDescription, privacy: .public)")
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                    permissionDenied = true
                }
            }
        }

        return WallpaperApplyResult(success: applied, permissionDenied: permissionDenied)
    }


    private func renderGradientImageAsync(stops: [ColorComponents]) async -> NSImage? {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        return await Task(priority: .userInitiated) { [imageProcessingContext] in
            var color0 = CIColor.black
            var color1 = CIColor.gray
            
            if stops.count >= 2 {
                color0 = CIColor(red: CGFloat(stops[0].red), green: CGFloat(stops[0].green), blue: CGFloat(stops[0].blue), alpha: CGFloat(stops[0].alpha))
                color1 = CIColor(red: CGFloat(stops.last!.red), green: CGFloat(stops.last!.green), blue: CGFloat(stops.last!.blue), alpha: CGFloat(stops.last!.alpha))
            } else if stops.count == 1 {
                let c = CIColor(red: CGFloat(stops[0].red), green: CGFloat(stops[0].green), blue: CGFloat(stops[0].blue), alpha: CGFloat(stops[0].alpha))
                color0 = c; color1 = c
            }
            
            guard let filter = CIFilter(name: "CILinearGradient") else { return nil }
            filter.setValue(CIVector(x: 0, y: 0), forKey: "inputPoint0")
            filter.setValue(CIVector(x: size.width, y: size.height), forKey: "inputPoint1")
            filter.setValue(color0, forKey: "inputColor0")
            filter.setValue(color1, forKey: "inputColor1")
            
            guard let outputImage = filter.outputImage?.cropped(to: CGRect(origin: .zero, size: size)),
                  let cgImage = imageProcessingContext.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }
            
            return NSImage(cgImage: cgImage, size: size)
        }.value
    }

    private func subduedGradientStops(from stops: [ColorComponents]) -> [ColorComponents] {
        guard !stops.isEmpty else {
            let palette = themeManager.palette
            return [
                palette.primary,
                palette.secondary
            ].map(subduedColor(_:))
        }

        return stops.map(subduedColor(_:))
    }

    private func subduedColor(_ color: ColorComponents) -> ColorComponents {
        let luminance = (color.red * 0.299) + (color.green * 0.587) + (color.blue * 0.114)
        return ColorComponents(
            red: max(0, min(1, (luminance * 0.78) + 0.06)),
            green: max(0, min(1, (luminance * 0.80) + 0.07)),
            blue: max(0, min(1, (luminance * 0.84) + 0.08)),
            alpha: color.alpha
        )
    }


    private func writeImageAsync(_ image: NSImage) async -> URL? {
        await withCheckedContinuation { continuation in
            Task(priority: .utility) {
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                    continuation.resume(returning: nil)
                    return
                }

                let url = self.wallpaperDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                do {
                    try jpeg.write(to: url, options: [.atomic])
                    await MainActor.run {
                        self.cleanupOldWallpapers(except: url)
                    }
                    continuation.resume(returning: url)
                } catch {
                    self.logger.error("Error writing image: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func writeWallpaperImagesAsync(_ images: [NSImage]) async -> [URL]? {
        await withCheckedContinuation { continuation in
            Task(priority: .utility) {
                var urls: [URL] = []

                for image in images {
                    guard let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff),
                          let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let url = self.wallpaperDirectory.appendingPathComponent(UUID().uuidString + ".jpg")

                    do {
                        try jpeg.write(to: url, options: [.atomic])
                        urls.append(url)
                    } catch {
                        self.logger.error("Error writing image: \(error.localizedDescription, privacy: .public)")
                        continuation.resume(returning: nil)
                        return
                    }
                }

                await MainActor.run {
                    self.cleanupOldWallpapers(except: Set(urls))
                }
                continuation.resume(returning: urls)
            }
        }
    }

    private func cleanupOldWallpapers(except currentURL: URL) {
        cleanupOldWallpapers(except: [currentURL])
    }

    private func cleanupOldWallpapers(except currentURLs: Set<URL>) {
        let urls = (try? fileManager.contentsOfDirectory(at: wallpaperDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where !currentURLs.contains(url) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func primaryScreenIdentifier(from screens: [NSScreen]) -> String {
        if let mainScreen = NSScreen.main,
           screens.contains(where: { $0.localizedName == mainScreen.localizedName }) {
            return mainScreen.localizedName
        }
        return screens.first?.localizedName ?? ""
    }

    private func applyOverlayBackdrops(primaryResourceURL: URL? = nil) async {
        let primaryURL: URL?

        if let primaryResourceURL {
            primaryURL = await preparedBackdropURL(from: primaryResourceURL)
        } else if let backgroundImageURL {
            primaryURL = await preparedBackdropURL(from: backgroundImageURL)
        } else if let selectedWallpaperURL {
            primaryURL = await preparedBackdropURL(from: selectedWallpaperURL)
        } else {
            primaryURL = await renderPaletteBackdropURL(secondary: false)
        }

        guard let primaryURL else { return }
        let secondaryURL = await renderSecondaryWallpaperVariantURL(from: primaryURL)
        let fallbackSecondaryURL = await renderPaletteBackdropURL(secondary: true)
        _ = await applyScreenWallpaperURLsAsync(
            primaryURL: primaryURL,
            secondaryURL: secondaryURL ?? fallbackSecondaryURL
        )
    }

    private func preparedBackdropURL(from url: URL) async -> URL? {
        let ext = url.pathExtension.lowercased()

        if ["mp4", "mov"].contains(ext) {
            return await renderVideoPosterURL(from: url)
        }

        return url
    }

    private func renderSecondaryWallpaperVariantURL(from url: URL) async -> URL? {
        let baseURL = await preparedBackdropURL(from: url) ?? url

        return await Task(priority: .userInitiated) { [wallpaperDirectory, imageProcessingContext] in
            guard let imageSource = CIImage(contentsOf: baseURL) else {
                return nil
            }

            let adjusted = imageSource
                .applyingFilter("CIColorControls", parameters: [
                    kCIInputSaturationKey: 0.45,
                    kCIInputBrightnessKey: -0.03,
                    kCIInputContrastKey: 0.88
                ])
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.8])
                .cropped(to: imageSource.extent)

            let overlay = CIImage(color: CIColor(red: 0.04, green: 0.05, blue: 0.06, alpha: 0.24))
                .cropped(to: adjusted.extent)
            let composited = overlay.composited(over: adjusted).cropped(to: adjusted.extent)

            guard let cgImage = imageProcessingContext.createCGImage(composited, from: composited.extent) else {
                return nil
            }

            let image = NSImage(cgImage: cgImage, size: NSSize(width: composited.extent.width, height: composited.extent.height))
            guard let tiff = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiff),
                  let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.74]) else {
                return nil
            }

            let outputURL = wallpaperDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            do {
                try jpeg.write(to: outputURL, options: [.atomic])
                return outputURL
            } catch {
                return nil
            }
        }.value
    }

    private func renderPaletteBackdropURL(secondary: Bool) async -> URL? {
        let palette = themeManager.palette
        let stops = secondary
            ? subduedGradientStops(from: [palette.primary, palette.secondary, palette.accent])
            : [palette.primary, palette.secondary, palette.accent]

        guard let image = await renderGradientImageAsync(stops: stops) else {
            return nil
        }

        return await writeImageAsync(image)
    }

    private func renderVideoPosterURL(from url: URL) async -> URL? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        let image: NSImage? = await withCheckedContinuation { continuation in
            generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, error in
                guard error == nil, let cgImage else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(
                    returning: NSImage(
                        cgImage: cgImage,
                        size: NSSize(width: cgImage.width, height: cgImage.height)
                    )
                )
            }
        }

        guard let image else { return nil }
        return await writeImageAsync(image)
    }


    private func updateCurrentWallpaperURLs(primaryURL: URL?, secondaryURL: URL?) {
        currentPrimaryWallpaperURL = primaryURL
        currentSecondaryWallpaperURL = secondaryURL ?? primaryURL
    }
}


final class WallpaperWindowController: NSObject {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura", category: "WallpaperWindow")
    private var window: NSWindow?
    private var playerView: DualVideoPlayerSurfaceView?
    private var renderStateTask: Task<Void, Never>?
    private var websiteContainerView: NSView?
    private var websiteSnapshotView: NSImageView?
    private var websiteWebView: WKWebView?
    private var currentWebsiteURL: URL?
    private var isWebsiteInteractive = false
    private var isWebsiteSuspended = false
    private var websiteHoverProbeSequence: Int = 0
    private var websiteShouldReceiveMouseEvents = true
    private var websiteGlobalEventMonitor: Any?
    private var websiteLocalEventMonitor: Any?
    private var websiteHoverProbeWorkItem: DispatchWorkItem?

    override init() {
        super.init()
        setupWindow()
    }

    private func startWebsiteHoverProbing() {
        guard websiteGlobalEventMonitor == nil, websiteLocalEventMonitor == nil else { return }

        let eventTypes: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .rightMouseDragged]
        websiteGlobalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventTypes) { [weak self] _ in
            self?.scheduleWebsiteHoverProbe()
        }
        websiteLocalEventMonitor = NSEvent.addLocalMonitorForEvents(matching: eventTypes) { [weak self] event in
            self?.scheduleWebsiteHoverProbe()
            return event
        }
        probeWebsiteHoverState()
    }

    private func stopWebsiteHoverProbing() {
        websiteHoverProbeWorkItem?.cancel()
        websiteHoverProbeWorkItem = nil
        if let websiteGlobalEventMonitor {
            NSEvent.removeMonitor(websiteGlobalEventMonitor)
            self.websiteGlobalEventMonitor = nil
        }
        if let websiteLocalEventMonitor {
            NSEvent.removeMonitor(websiteLocalEventMonitor)
            self.websiteLocalEventMonitor = nil
        }
        websiteHoverProbeSequence += 1
    }

    private func scheduleWebsiteHoverProbe() {
        websiteHoverProbeWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.probeWebsiteHoverState()
        }

        websiteHoverProbeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
    }

    deinit {
        stopWebsiteHoverProbing()
        NotificationCenter.default.removeObserver(self)
    }

    private func setupWindow() {
        // Use a fallback frame if NSScreen.main is not yet available during early launch
        let screenFrame = NSScreen.main?.frame ?? NSScreen.screens.first?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = DesktopWallpaperWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        window.level = Self.passiveWallpaperLevel
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false

        let playerView = DualVideoPlayerSurfaceView(frame: screenFrame)
        playerView.setUsesAutomaticVisibilitySuspension(false)
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.autoresizingMask = [.width, .height]
        window.contentView = playerView

        self.window = window
        self.playerView = playerView

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: window
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceStateChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceStateChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceStateChanged),
            name: NSWorkspace.didDeactivateApplicationNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSApplication.didHideNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityChanged),
            name: NSApplication.didUnhideNotification,
            object: nil
        )
    }

    @objc private func screenChanged() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(screen.frame, display: true)
        playerView?.frame = window?.contentView?.bounds ?? screen.frame
        updatePerformanceState()
    }

    private var currentURL: URL?
    private var hostingContainerView: NSView?
    private var hostingView: NSHostingView<AnyView>?

    func showSwiftUIView<V: View>(_ view: V) {
        stopVideo()
        stopWebsite()

        // Ensure we have a dedicated hosting container and make it the window's contentView
        if hostingContainerView == nil {
            let frame = window?.contentView?.bounds ?? (NSScreen.main?.frame ?? .zero)
            let container = NSView(frame: frame)
            container.wantsLayer = false
            container.autoresizingMask = [.width, .height]
            hostingContainerView = container
        }

        if let container = hostingContainerView {
            window?.contentView = container
        }

        // Remove existing hosting view if any
        hostingView?.removeFromSuperview()
        
        ensureCorrectFrame()

        // Create and pin the SwiftUI hosting view
        let host = NSHostingView(rootView: AnyView(view))
        host.translatesAutoresizingMaskIntoConstraints = false
        host.wantsLayer = true

        guard let container = hostingContainerView else { return }
        container.addSubview(host)

        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        hostingView = host
        window?.orderFront(nil)
    }

    func hideSwiftUIView() {
        hostingView?.removeFromSuperview()
        hostingView = nil
        // Swap back to the video container if available
        if let videoView = playerView, window?.contentView !== videoView {
            window?.contentView = videoView
        }
    }

    func playVideo(url: URL) {
        if self.currentURL == url && self.isPlaying() {
            ensureCorrectFrame() // Still ensure frame is correct even if already playing
            return
        }
        
        ensureCorrectFrame()

        stopVideo()
        stopWebsite()
        hideSwiftUIView()
        if let pv = self.playerView, window?.contentView !== pv {
            window?.contentView = pv
        }
        currentURL = url
        configureVideoPlayback(for: url)
        window?.orderFront(nil)
        updatePerformanceState()
    }

    func setWebsiteInteractive(_ interactive: Bool) {
        isWebsiteInteractive = interactive
        if currentWebsiteURL != nil {
            applyWebsiteInteractionMode()
        }
    }

    func showWebsite(url: URL) {
        stopVideo()
        hideSwiftUIView()
        ensureCorrectFrame()
        ensureWebsiteContainerView()

        guard let container = websiteContainerView,
              let webView = websiteWebView else { return }

        window?.contentView = container

        if currentWebsiteURL != url || webView.url?.absoluteString != url.absoluteString {
            currentWebsiteURL = url
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            webView.load(request)
        } else {
            currentWebsiteURL = url
        }

        applyWebsiteInteractionMode()
        setWebsiteSuspended(false)
        window?.orderFront(nil)
        if isWebsiteInteractive {
            window?.makeFirstResponder(webView)
        }
        updatePerformanceState()
    }

    @objc private func videoPlayerItemFailedToPlayToEndTime(_ notification: Notification) {
        if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
            logger.error("Video playback failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stopAndCleanup() {
        playerView?.teardown()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.flush()
        CATransaction.commit()

        logger.debug("Hardware decoder released")
    }

    private func configureVideoPlayback(for url: URL) {
        playerView?.setPlaybackSuspended(false)
        playerView?.play(url: url)
    }

    private func freezeVideoPlayback() {
        playerView?.setPlaybackSuspended(true)
    }

    private func resumeVideoPlaybackIfNeeded() {
        guard currentURL != nil else { return }
        playerView?.setPlaybackSuspended(false)
    }

    private func ensureWebsiteContainerView() {
        if websiteContainerView != nil, websiteWebView != nil {
            return
        }

        let frame = window?.contentView?.bounds ?? (NSScreen.main?.frame ?? .zero)
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.autoresizingMask = [.width, .height]

        let snapshotView = NSImageView(frame: frame)
        snapshotView.translatesAutoresizingMaskIntoConstraints = false
        snapshotView.imageScaling = .scaleAxesIndependently
        snapshotView.isHidden = true

        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "AuraWallpaper"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        // macOS 12+ automatically pools WebKit processes — no explicit WKProcessPool needed.
        // The key memory savings come from loading about:blank on deactivation (see stopWebsite).

        let webView = InteractiveWallpaperWebView(frame: .zero, configuration: configuration)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false

        container.addSubview(snapshotView)
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            snapshotView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            snapshotView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            snapshotView.topAnchor.constraint(equalTo: container.topAnchor),
            snapshotView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        websiteContainerView = container
        websiteSnapshotView = snapshotView
        websiteWebView = webView
    }

    private func applyWebsiteInteractionMode() {
        updateWebsiteWindowLevel()

        if isWebsiteInteractive {
            websiteShouldReceiveMouseEvents = true
            window?.ignoresMouseEvents = false
            if !isWebsiteSuspended {
                startWebsiteHoverProbing()
            }
            if let websiteWebView {
                window?.makeFirstResponder(websiteWebView)
            }
        } else {
            stopWebsiteHoverProbing()
            websiteShouldReceiveMouseEvents = false
            window?.ignoresMouseEvents = true
        }

        window?.orderFront(nil)
    }

    @objc private func workspaceStateChanged(_ notification: Notification) {
        updatePerformanceState()
    }

    @objc private func windowVisibilityChanged(_ notification: Notification) {
        updatePerformanceState()
    }

    private func updatePerformanceState() {
        let isWindowVisible = window?.isVisible == true
        let isWindowMiniaturized = window?.isMiniaturized == true
        let isOccluded = window?.occlusionState.contains(.visible) == false
        let isFullscreenActive = isFullscreenApplicationActive()
        let isApplicationHidden = NSApp.isHidden
        let shouldSuspendDesktopMedia = !isWindowVisible || isWindowMiniaturized || isOccluded || isFullscreenActive || isApplicationHidden
        let shouldSuspendSwiftUI = !isWindowVisible || isWindowMiniaturized || isOccluded || isFullscreenActive || isApplicationHidden

        renderStateTask?.cancel()
        renderStateTask = Task(priority: .background) {
            await AuraBackgroundActor.setRenderingSuspended(shouldSuspendSwiftUI)
        }

        // Handle Website
        if currentWebsiteURL != nil {
            setWebsiteSuspended(shouldSuspendDesktopMedia)
        }

        // Handle Video
        if currentURL != nil {
            setVideoSuspended(shouldSuspendDesktopMedia)
        }

        // Handle SwiftUI
        if hostingView != nil {
            setSwiftUISuspended(shouldSuspendSwiftUI)
        }
    }

    private var isVideoSuspended = false
    private var isSwiftUISuspended = false

    private func setSwiftUISuspended(_ suspended: Bool) {
        guard suspended != isSwiftUISuspended else { return }
        isSwiftUISuspended = suspended

        if suspended {
            hostingView?.layer?.speed = 0.0
            hostingContainerView?.isHidden = true
        } else {
            hostingContainerView?.isHidden = false
            hostingView?.layer?.speed = 1.0
        }
    }

    private func setVideoSuspended(_ suspended: Bool) {
        guard suspended != isVideoSuspended else { return }
        isVideoSuspended = suspended

        if suspended {
            freezeVideoPlayback()
        } else {
            resumeVideoPlaybackIfNeeded()
        }
    }

    private func setWebsiteSuspended(_ suspended: Bool) {
        guard let webView = websiteWebView else { return }
        guard suspended != isWebsiteSuspended else { return }

        isWebsiteSuspended = suspended

        if suspended {
            stopWebsiteHoverProbing()
            captureWebsiteSnapshot()
            evaluateWebsiteJavaScript(Self.pauseWebsiteScript)
            webView.isHidden = true
        } else {
            websiteSnapshotView?.isHidden = true
            webView.isHidden = false
            evaluateWebsiteJavaScript(Self.resumeWebsiteScript)
            if isWebsiteInteractive {
                startWebsiteHoverProbing()
            }
        }
    }

    private func captureWebsiteSnapshot() {
        guard let webView = websiteWebView, !webView.isHidden else { return }

        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isWebsiteSuspended,
                      let image else { return }
                self.websiteSnapshotView?.image = image
                self.websiteSnapshotView?.isHidden = false
            }
        }
    }

    private func evaluateWebsiteJavaScript(_ script: String) {
        websiteWebView?.evaluateJavaScript(script, completionHandler: nil)
    }

    private func updateWebsiteWindowLevel() {
        guard let window else { return }
        window.level = isWebsiteInteractive ? Self.interactiveWallpaperLevel : Self.passiveWallpaperLevel
    }

    private func probeWebsiteHoverState() {
        guard isWebsiteInteractive,
              !isWebsiteSuspended,
              let window = window,
              let webView = websiteWebView,
              let currentWebsiteURL = currentWebsiteURL else {
            setWebsiteMouseEventInterception(enabled: isWebsiteInteractive)
            return
        }

        guard window.isVisible else {
            setWebsiteMouseEventInterception(enabled: false)
            return
        }

        let screenLocation = NSEvent.mouseLocation
        guard window.frame.contains(screenLocation) else {
            setWebsiteMouseEventInterception(enabled: true)
            return
        }

        let windowPoint = window.convertPoint(fromScreen: screenLocation)
        let viewPoint = webView.convert(windowPoint, from: nil as NSView?)
        guard webView.bounds.contains(viewPoint) else {
            setWebsiteMouseEventInterception(enabled: true)
            return
        }

        websiteHoverProbeSequence += 1
        let sequence = websiteHoverProbeSequence
        let javaScriptPoint = CGPoint(x: viewPoint.x, y: webView.bounds.height - viewPoint.y)
        let script = Self.hitTestScript(for: javaScriptPoint)

        webView.evaluateJavaScript(script) { [weak self] (result: Any?, _: Error?) in
            guard let self,
                  self.isWebsiteInteractive,
                  self.currentWebsiteURL == currentWebsiteURL,
                  self.websiteHoverProbeSequence == sequence else { return }

            let shouldIntercept = (result as? Bool) ?? true
            self.setWebsiteMouseEventInterception(enabled: shouldIntercept)
        }
    }

    private func setWebsiteMouseEventInterception(enabled: Bool) {
        websiteShouldReceiveMouseEvents = enabled
        window?.ignoresMouseEvents = !enabled
    }

    private func isFullscreenApplicationActive() -> Bool {
        guard let activeApplication = NSWorkspace.shared.frontmostApplication else {
            return false
        }

        let activePID = activeApplication.processIdentifier
        guard activePID != ProcessInfo.processInfo.processIdentifier,
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        let screens = NSScreen.screens.map(\.frame)

        for windowInfo in windowList {
            guard let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
                  ownerPID == activePID,
                  let layer = windowInfo[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let alpha = windowInfo[kCGWindowAlpha as String] as? Double,
                  alpha > 0.01,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  !bounds.isEmpty else {
                continue
            }

            if screens.contains(where: { screen in
                bounds.width >= screen.width * 0.95 &&
                bounds.height >= screen.height * 0.95 &&
                abs(bounds.minX - screen.minX) < 24 &&
                abs(bounds.minY - screen.minY) < 24
            }) {
                return true
            }
        }

        return false
    }

    private func stopWebsite() {
        stopWebsiteHoverProbing()
        currentWebsiteURL = nil
        isWebsiteSuspended = false
        websiteSnapshotView?.image = nil
        websiteSnapshotView?.isHidden = true
        websiteWebView?.stopLoading()
        // Bug 3 fix: navigate to about:blank instead of loading an empty HTML string.
        // about:blank causes WebKit to tear down the current JS context and GC its heap,
        // freeing ~200-300 MB that loadHTMLString("") does NOT release.
        websiteWebView?.load(URLRequest(url: URL(string: "about:blank")!))
        websiteWebView?.isHidden = false
        websiteShouldReceiveMouseEvents = false
        updateWebsiteWindowLevel()
        window?.ignoresMouseEvents = true
    }

    func stopVideo() {
        stopAndCleanup()

        currentURL = nil

        if hostingView == nil {
            window?.orderOut(nil)
        }
    }

    func stopAll() {
        stopVideo()
        stopWebsite()
        hideSwiftUIView()
        window?.orderOut(nil)
        
        if let pv = playerView {
            pv.layer?.backgroundColor = NSColor.clear.cgColor
        }
        
        if let scv = websiteContainerView {
            scv.isHidden = true
        }
    }

    private func ensureCorrectFrame() {
        guard let window = self.window, let screen = NSScreen.main else { return }
        
        // If the window is currently at (0,0,0,0) or incorrect for the main screen, update it
        if window.frame.size == .zero || window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
            playerView?.frame = window.contentView?.bounds ?? screen.frame
            logger.notice("Updated wallpaper window frame to match screen: \(String(describing: screen.frame))")
        }
    }

    func isPlaying() -> Bool {
        return playerView?.isPlaying == true && window?.isVisible == true
    }

    private static let pauseWebsiteScript = """
    (() => {
      const styleId = "aura-wallpaper-pause-style";
      let style = document.getElementById(styleId);
      if (!style) {
        style = document.createElement("style");
        style.id = styleId;
        document.head.appendChild(style);
      }
      style.textContent = "*, *::before, *::after { animation-play-state: paused !important; transition-property: none !important; }";
      document.querySelectorAll("video, audio").forEach((element) => {
        if (!element.hasAttribute("data-aura-was-paused")) {
          element.setAttribute("data-aura-was-paused", element.paused ? "true" : "false");
        }
        try { element.pause(); } catch (_) {}
      });
      return true;
    })();
    """

    private static let resumeWebsiteScript = """
    (() => {
      const style = document.getElementById("aura-wallpaper-pause-style");
      if (style) {
        style.remove();
      }
      document.querySelectorAll("video, audio").forEach((element) => {
        const wasPaused = element.getAttribute("data-aura-was-paused");
        element.removeAttribute("data-aura-was-paused");
        if (wasPaused === "false") {
          const playPromise = element.play();
          if (playPromise && typeof playPromise.catch === "function") {
            playPromise.catch(() => {});
          }
        }
      });
      return true;
    })();
    """

    private static func hitTestScript(for point: CGPoint) -> String {
        """
        (() => {
          const x = \(point.x);
          const y = \(point.y);
          const element = document.elementFromPoint(x, y);
          if (!element) { return false; }
          const style = window.getComputedStyle(element);
          if (style.pointerEvents === "none" || style.visibility === "hidden" || style.display === "none") {
            return false;
          }
          const background = style.backgroundColor || "";
          const hasBackground = !background.includes("rgba(0, 0, 0, 0)") && background !== "transparent";
          const hasBackgroundImage = style.backgroundImage && style.backgroundImage !== "none";
          const hasText = (element.innerText || element.textContent || "").trim().length > 0;
          const mediaTags = new Set(["A", "BUTTON", "CANVAS", "IFRAME", "IMG", "INPUT", "SELECT", "TEXTAREA", "VIDEO"]);
          const isInteractiveTag = mediaTags.has(element.tagName);
          const hasPointerCursor = style.cursor === "pointer";
          return hasBackground || hasBackgroundImage || hasText || isInteractiveTag || hasPointerCursor;
        })();
        """
    }

    private static let passiveWallpaperLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
    private static let interactiveWallpaperLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
}

final class DesktopWallpaperWindow: NSWindow {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

final class InteractiveWallpaperWebView: WKWebView {
    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
