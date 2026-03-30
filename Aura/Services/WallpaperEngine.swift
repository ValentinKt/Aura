import AppKit
import AVFoundation
import CoreImage
import Observation
import SwiftUI
import WebKit

struct WallpaperApplyResult: Hashable {
    var success: Bool
    var permissionDenied: Bool
}

struct FallbackGradientView: View {
    let stops: [ColorComponents]
    var body: some View {
        let colors = stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue, opacity: $0.alpha) }
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()
    }
}

struct FallbackImageView: View {
    let url: URL?
    let image: NSImage?
    
    init(url: URL) {
        self.url = url
        self.image = nil
    }
    
    init(image: NSImage) {
        self.url = nil
        self.image = image
    }

    var body: some View {
        if let image = image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else if let url = url, let imageFromUrl = NSImage(contentsOf: url) {
            Image(nsImage: imageFromUrl)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            Color.black.ignoresSafeArea()
        }
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
    private let fileManager = FileManager.default
    private var animationTimers: [String: Timer] = [:]
    private let themeManager: ThemeManager
    private let wallpaperDirectory: URL
    private let renderQueue = DispatchQueue(label: "com.Aura.wallpaper.render", qos: .userInitiated)
    private let imageProcessingContext = CIContext()
    private var isRendering = false
    private var isPresentationSuppressed = false
    private let wallpaperWindowController = WallpaperWindowController()

    var selectedWallpaperURL: URL? {
        guard let selectedWallpaperResource else { return nil }
        return resolveResourceURL(selectedWallpaperResource)
    }

    /// The last resolved image/video URL from a static or animated wallpaper.
    /// Quote/Zen/Time views use this to render the Image Playground (or other) wallpaper as their background.
    var backgroundImageURL: URL?
    var currentPrimaryWallpaperURL: URL?
    var currentSecondaryWallpaperURL: URL?

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
        isPresentationSuppressed = suppressed
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
        print("🟢 [WallpaperEngine] Applying wallpaper of type: \(descriptor.type)")
        let storesConcreteWallpaper = descriptor.type == .staticImage || descriptor.type == .animated || descriptor.type == .dynamic
        if storesConcreteWallpaper {
            selectedWallpaperResource = descriptor.resources.first
        }

        // Update backgroundImageURL whenever we apply a concrete image/video wallpaper,
        // so dynamic views (Quote, Zen, Time) can use it as their background even after switching.
        if storesConcreteWallpaper {
            if let resource = descriptor.resources.first {
                backgroundImageURL = resolveResourceURL(resource)
            }
        }

        if isPresentationSuppressed {
            print("🟢 [WallpaperEngine] Presentation suppressed, skipping application")
            return WallpaperApplyResult(success: true, permissionDenied: false)
        }

        let isStatic = descriptor.type == WallpaperType.staticImage || descriptor.type == WallpaperType.dynamic
        if !isStatic {
            stopAnimation()
        } else {
            // Stop timers but keep the current view/video until the new desktop image is applied to avoid a flash
            for timer in animationTimers.values {
                timer.invalidate()
            }
            animationTimers.removeAll()
            isRendering = false
        }

        let result: WallpaperApplyResult
        switch descriptor.type {
        case .staticImage:
            result = await applyStaticAsync(descriptor)
            if isStatic { wallpaperWindowController.stopAll() }
        case .gradient:
            result = await applyGradientAsync(descriptor)
        case .animated:
            // Animation logic needs to be on main thread for Timer
            startAnimated(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .particle:
            // Animation logic needs to be on main thread for Timer
            startParticle(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .current:
            // Explicitly do nothing to keep current wallpaper
            result = WallpaperApplyResult(success: true, permissionDenied: false)
            if isStatic { wallpaperWindowController.stopAll() }
        case .dynamic:
            // For macOS, setting a .heic file automatically enables dynamic features if the file supports it
            result = await applyStaticAsync(descriptor)
            if isStatic { wallpaperWindowController.stopAll() }
        case .time:
            startTime(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .quote:
            startQuote(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .zen:
            startZen(descriptor)
            result = WallpaperApplyResult(success: true, permissionDenied: false)
        case .website:
            // Handle website wallpaper
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

        print("🟥 [WallpaperEngine] Error: Could not find wallpaper resource: \(resource)")
        return WallpaperApplyResult(success: false, permissionDenied: false)
    }

    private func applyStatic(_ descriptor: WallpaperDescriptor) -> WallpaperApplyResult {
        guard let resource = descriptor.resources.first else {
            return WallpaperApplyResult(success: false, permissionDenied: false)
        }

        if let resolvedURL = resolveResourceURL(resource) {
            return applyImageURLs([resolvedURL])
        }

        print("🟥 [WallpaperEngine] Error: Could not find wallpaper resource: \(resource)")
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
        let fps = min(5, max(0.1, descriptor.fps)) // Limit FPS to reasonable background range
        if let resource = descriptor.resources.first {
            if let resolvedURL = resolveResourceURL(resource) {
                let ext = resolvedURL.pathExtension.lowercased()
                if ["mp4", "mov"].contains(ext) {
                    Task {
                        await self.applyOverlayBackdrops(primaryResourceURL: resolvedURL)
                    }
                    startVideoAnimated(resourceURL: resolvedURL, fps: fps)
                    return
                } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                    // If it resolved to an image (e.g., fallback), show it in the window instead of changing the system wallpaper
                    Task {
                        await self.applyOverlayBackdrops(primaryResourceURL: resolvedURL)
                    }
                    let imageView = FallbackImageView(url: resolvedURL)
                    wallpaperWindowController.showSwiftUIView(imageView)
                    return
                }
            } else {
                // If the video isn't downloaded yet, check for a placeholder image from the asset catalog
                let resourceNameWithoutExtension = (resource as NSString).deletingPathExtension
                if let placeholderImage = NSImage(named: resource) ?? NSImage(named: resourceNameWithoutExtension) {
                    Task {
                        await self.applyOverlayBackdrops()
                    }
                    let imageView = FallbackImageView(image: placeholderImage)
                    wallpaperWindowController.showSwiftUIView(imageView)
                    return
                } else {
                    // Fallback to a gradient based on the theme palette instead of stopping the window
                    let palette = self.themeManager.palette
                    let stops = [palette.primary, palette.secondary]
                    let gradientView = FallbackGradientView(stops: stops)
                    wallpaperWindowController.showSwiftUIView(gradientView)
                    return
                }
            }
        }

        let stops = descriptor.gradientStops
        var index = 0

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            guard let self else { return }

            let currentIndex = index
            index += 1

            Task { @MainActor in
                if self.isRendering { return }
                self.isRendering = true

                let shift = Double(currentIndex) / 60.0
                let shiftedStops = stops.map { stop in
                    ColorComponents(
                        red: max(0, min(1, stop.red + sin(shift) * 0.1)),
                        green: max(0, min(1, stop.green + cos(shift) * 0.1)),
                        blue: max(0, min(1, stop.blue + sin(shift * 0.5) * 0.1)),
                        alpha: stop.alpha
                    )
                }

                if let image = await self.renderGradientImageAsync(stops: shiftedStops),
                   let url = await self.writeImageAsync(image) {
                    _ = self.applyImageURLs([url])
                }
                self.isRendering = false
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        animationTimers["animated"] = timer
    }

    private func startVideoAnimated(resourceURL: URL, fps: Double) {
        // Use the window-based player for smooth video playback
        wallpaperWindowController.playVideo(url: resourceURL)
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
        var index = 0
        let timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let currentIndex = index
            index += 1

            Task {
                if let image = await self.renderParticleImageAsync(seed: currentIndex),
                   let url = await self.writeImageAsync(image) {
                    _ = await self.applyImageURLs([url])
                }
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        animationTimers["particle"] = timer
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

    private func startQuote(_ descriptor: WallpaperDescriptor) {
        Task {
            await applyOverlayBackdrops()
        }
        let style = descriptor.resources.first ?? "motivational"
        let palette = themeManager.palette
        let quoteID = descriptor.resources.count > 1 ? UUID(uuidString: descriptor.resources[1]) : nil
        let quoteView = QuoteWallpaperView(style: style, palette: palette, quoteID: quoteID, selectedWallpaperURL: backgroundImageURL)
        wallpaperWindowController.showSwiftUIView(quoteView)
    }

    private func startZen(_ descriptor: WallpaperDescriptor) {
        Task {
            await applyOverlayBackdrops()
        }
        let style = descriptor.resources.first ?? "breathing"
        let palette = themeManager.palette
        let zenView = ZenWallpaperView(style: style, palette: palette, selectedWallpaperURL: backgroundImageURL)
        wallpaperWindowController.showSwiftUIView(zenView)
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
    private func applyImageURLsAsync(_ urls: [URL]) async -> WallpaperApplyResult {
        var permissionDenied = false
        var applied = false
        let screens = NSScreen.screens
        updateCurrentWallpaperURLs(
            primaryURL: urls.first,
            secondaryURL: urls.count > 1 ? urls[1] : nil
        )

        if screens.isEmpty {
            // For headless environments (CI/Tests), we assume success if URLs exist
            let allExist = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            return WallpaperApplyResult(success: allExist, permissionDenied: false)
        }

        for screen in screens {
            for url in urls {
                do {
                    // Running this inside a Task.detached to prevent blocking MainActor if possible
                    // But NSScreen is not Sendable. We can use setDesktopImageURL on MainActor.
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    applied = true
                } catch let error as NSError {
                    print("🟥 [WallpaperEngine] Error setting desktop image URL: \(error.localizedDescription)")
                    if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                        permissionDenied = true
                    }
                }
            }
        }
        return WallpaperApplyResult(success: applied, permissionDenied: permissionDenied)
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
                print("🟥 [WallpaperEngine] Error setting desktop image URL: \(error.localizedDescription)")
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                    permissionDenied = true
                }
            }
        }

        return WallpaperApplyResult(success: applied, permissionDenied: permissionDenied)
    }

    private func applyImageURLs(_ urls: [URL]) -> WallpaperApplyResult {
        // Fallback for synchronous calls if needed
        var permissionDenied = false
        var applied = false
        let screens = NSScreen.screens
        updateCurrentWallpaperURLs(
            primaryURL: urls.first,
            secondaryURL: urls.count > 1 ? urls[1] : nil
        )

        if screens.isEmpty {
            let allExist = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            return WallpaperApplyResult(success: allExist, permissionDenied: false)
        }

        for screen in screens {
            for url in urls {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    applied = true
                } catch let error as NSError {
                    print("🟥 [WallpaperEngine] Error setting desktop image URL: \(error.localizedDescription)")
                    if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                        permissionDenied = true
                    }
                }
            }
        }
        return WallpaperApplyResult(success: applied, permissionDenied: permissionDenied)
    }

    private func renderGradientImageAsync(stops: [ColorComponents]) async -> NSImage? {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        return await withCheckedContinuation { continuation in
            renderQueue.async {
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(data: nil,
                                              width: Int(size.width),
                                              height: Int(size.height),
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    continuation.resume(returning: nil)
                    return
                }

                let cgColors = stops.map { NSColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha).cgColor }
                let gradient = CGGradient(colorsSpace: colorSpace, colors: cgColors as CFArray, locations: nil)

                context.drawLinearGradient(
                    gradient ?? CGGradient(colorsSpace: colorSpace, colors: [NSColor.black.cgColor, NSColor.darkGray.cgColor] as CFArray, locations: nil)!,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )

                if let cgImage = context.makeImage() {
                    continuation.resume(returning: NSImage(cgImage: cgImage, size: size))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
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

    private func renderParticleImageAsync(seed: Int) async -> NSImage? {
        let size = NSScreen.main?.frame.size ?? CGSize(width: 1920, height: 1080)
        return await withCheckedContinuation { continuation in
            renderQueue.async {
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                guard let context = CGContext(data: nil,
                                              width: Int(size.width),
                                              height: Int(size.height),
                                              bitsPerComponent: 8,
                                              bytesPerRow: 0,
                                              space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                    continuation.resume(returning: nil)
                    return
                }

                context.setFillColor(NSColor.black.cgColor)
                context.fill(CGRect(origin: .zero, size: size))

                var rng = SeededGenerator(seed: UInt64(seed))
                let particleCount = 200

                for _ in 0..<particleCount {
                    let x = CGFloat.random(in: 0..<size.width, using: &rng.generator)
                    let y = CGFloat.random(in: 0..<size.height, using: &rng.generator)
                    let radius = CGFloat.random(in: 1...4, using: &rng.generator)

                    let color = NSColor(
                        calibratedRed: CGFloat.random(in: 0.4...0.9, using: &rng.generator),
                        green: CGFloat.random(in: 0.4...0.9, using: &rng.generator),
                        blue: CGFloat.random(in: 0.7...1.0, using: &rng.generator),
                        alpha: CGFloat.random(in: 0.3...0.8, using: &rng.generator)
                    )

                    context.setFillColor(color.cgColor)
                    context.setShadow(offset: .zero, blur: radius * 2, color: color.cgColor)
                    context.fillEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))
                }

                if let cgImage = context.makeImage() {
                    continuation.resume(returning: NSImage(cgImage: cgImage, size: size))
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func writeImageAsync(_ image: NSImage) async -> URL? {
        await withCheckedContinuation { continuation in
            renderQueue.async {
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff),
                      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                    continuation.resume(returning: nil)
                    return
                }

                let url = self.wallpaperDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
                do {
                    try jpeg.write(to: url, options: [.atomic])
                    DispatchQueue.main.async {
                        self.cleanupOldWallpapers(except: url)
                    }
                    continuation.resume(returning: url)
                } catch {
                    print("🟥 [WallpaperEngine] Error writing image: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private func writeWallpaperImagesAsync(_ images: [NSImage]) async -> [URL]? {
        await withCheckedContinuation { continuation in
            renderQueue.async {
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
                        print("🟥 [WallpaperEngine] Error writing image: \(error.localizedDescription)")
                        continuation.resume(returning: nil)
                        return
                    }
                }

                DispatchQueue.main.async {
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

        return await Task.detached(priority: .userInitiated) { [wallpaperDirectory, imageProcessingContext] in
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

    private func stopAnimation() {
        for timer in animationTimers.values {
            timer.invalidate()
        }
        animationTimers.removeAll()
    }

    private func updateCurrentWallpaperURLs(primaryURL: URL?, secondaryURL: URL?) {
        currentPrimaryWallpaperURL = primaryURL
        currentSecondaryWallpaperURL = secondaryURL ?? primaryURL
    }
}

private struct SeededGenerator {
    var generator: SeededRandomNumberGenerator

    init(seed: UInt64) {
        generator = SeededRandomNumberGenerator(seed: seed)
    }
}

private struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

final class WallpaperWindowController: NSObject {
    private var window: NSWindow?
    private var playerView: NSView?
    private var playerLayer: AVPlayerLayer?
    private var playerQueue: AVQueuePlayer?
    private var playerLooper: AVPlayerLooper?
    private var endObserver: NSObjectProtocol?
    private var websiteContainerView: NSView?
    private var websiteSnapshotView: NSImageView?
    private var websiteWebView: WKWebView?
    private var currentWebsiteURL: URL?
    private var isWebsiteInteractive = false
    private var isWebsiteSuspended = false
    private var websiteHoverProbeTimer: Timer?
    private var websiteHoverProbeSequence: Int = 0
    private var websiteShouldReceiveMouseEvents = true

    override init() {
        super.init()
        setupWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupWindow() {
        let screenFrame = NSScreen.main?.frame ?? .zero
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

        let playerView = NSView(frame: screenFrame)
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
    }

    @objc private func screenChanged() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(screen.frame, display: true)
        playerLayer?.frame = window?.contentView?.bounds ?? screen.frame
        updatePerformanceState()
    }

    private var currentURL: URL?
    private var isSecurityScoped: Bool = false
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
        // Vérification si la vidéo est déjà en cours de lecture
        if self.currentURL == url && self.isPlaying() {
            return
        }

        // Nettoyage complet
        stopVideo()
        stopWebsite()
        // Ensure the window is using the video container
        hideSwiftUIView()
        if let pv = self.playerView, window?.contentView !== pv {
            window?.contentView = pv
        }
        // Accès sécurisé
        let finalURL = url
        let isScoped = finalURL.startAccessingSecurityScopedResource()
        self.currentURL = finalURL
        self.isSecurityScoped = isScoped

        // CONFIGURATION SILENCIEUSE (Fix bootstrap_look_up)
        let asset = AVURLAsset(url: finalURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)

        // Désactiver le moteur audio au niveau de l'item (Fix AddInstanceForFactory)
        item.audioTimePitchAlgorithm = .varispeed

        let newPlayer = AVQueuePlayer(playerItem: item)
        newPlayer.isMuted = true
        newPlayer.allowsExternalPlayback = false // Désactive la recherche AirPlay (Fix err 1100)

        self.playerQueue = newPlayer
        self.playerLooper = AVPlayerLooper(player: newPlayer, templateItem: item)

        let newLayer = AVPlayerLayer(player: newPlayer)
        newLayer.videoGravity = .resizeAspectFill

        // Utilisation de CATransaction pour éviter les flashs noirs et assurer un rendu propre
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        newLayer.frame = self.playerView?.bounds ?? .zero
        self.playerView?.layer?.addSublayer(newLayer)
        self.playerLayer = newLayer
        CATransaction.commit()

        newPlayer.play()
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
            print("🟥 [WallpaperWindowController] Video playback failed: \(error.localizedDescription)")
        }
    }

    private func stopAndCleanup() {
        // 1. Arrêt immédiat de la lecture
        playerQueue?.pause()
        playerQueue?.isMuted = true

        // 2. Invalider le looper AVANT de toucher à la queue
        playerLooper?.disableLooping()
        playerLooper = nil

        // 3. Vider la queue pour libérer les buffers de fichiers (Fix FigFilePlayer)
        playerQueue?.removeAllItems()

        // 4. Détacher l'item du décodeur matériel (Fix VRP -12852)
        playerQueue?.replaceCurrentItem(with: nil)

        // 5. Nettoyage visuel et notification
        playerLayer?.player = nil // Très important : délier le player du layer
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        playerQueue = nil
        print("🟢 [WallpaperEngine] Hardware Decoder Released")
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
            startWebsiteHoverProbing()
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
        let shouldSuspend = window?.isVisible != true || isFullscreenApplicationActive()

        // Handle Website
        if currentWebsiteURL != nil {
            setWebsiteSuspended(shouldSuspend)
        }

        // Handle Video
        if currentURL != nil {
            setVideoSuspended(shouldSuspend)
        }

        // Handle SwiftUI
        if hostingView != nil {
            setSwiftUISuspended(shouldSuspend)
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
            playerQueue?.pause()
        } else {
            playerQueue?.play()
        }
    }

    private func setWebsiteSuspended(_ suspended: Bool) {
        guard let webView = websiteWebView else { return }
        guard suspended != isWebsiteSuspended else { return }

        isWebsiteSuspended = suspended

        if suspended {
            captureWebsiteSnapshot()
            evaluateWebsiteJavaScript(Self.pauseWebsiteScript)
            webView.isHidden = true
        } else {
            websiteSnapshotView?.isHidden = true
            webView.isHidden = false
            evaluateWebsiteJavaScript(Self.resumeWebsiteScript)
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

    private func startWebsiteHoverProbing() {
        guard websiteHoverProbeTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.probeWebsiteHoverState()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        websiteHoverProbeTimer = timer
        probeWebsiteHoverState()
    }

    private func stopWebsiteHoverProbing() {
        websiteHoverProbeTimer?.invalidate()
        websiteHoverProbeTimer = nil
        websiteHoverProbeSequence += 1
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
        websiteWebView?.loadHTMLString("", baseURL: nil)
        websiteWebView?.isHidden = false
        websiteShouldReceiveMouseEvents = false
        updateWebsiteWindowLevel()
        window?.ignoresMouseEvents = true
    }

    func stopVideo() {
        stopAndCleanup()

        // On libère le droit d'accès AU DERNIER MOMENT
        if isSecurityScoped, let url = currentURL {
            url.stopAccessingSecurityScopedResource()
            print("🟢 [WallpaperEngine] Security Scope Released")
        }

        currentURL = nil
        isSecurityScoped = false

        if hostingView == nil {
            window?.orderOut(nil)
        }
    }

    func stopAll() {
        stopVideo()
        stopWebsite()
        hideSwiftUIView()
        window?.orderOut(nil)
    }

    func isPlaying() -> Bool {
        return playerQueue != nil && playerQueue?.rate != 0 && window?.isVisible == true
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
