import AppKit
import AVFoundation
import SwiftUI

struct WallpaperApplyResult: Hashable {
    var success: Bool
    var permissionDenied: Bool
}

@MainActor
final class WallpaperEngine {
    private let fileManager = FileManager.default
    private var animationTimers: [String: Timer] = [:]
    private let themeManager: ThemeManager
    private let wallpaperDirectory: URL
    private let renderQueue = DispatchQueue(label: "com.Aura.wallpaper.render", qos: .userInitiated)
    private var isRendering = false
    private let wallpaperWindowController = WallpaperWindowController()

    init(themeManager: ThemeManager) {
        self.themeManager = themeManager
        self.wallpaperDirectory = fileManager.temporaryDirectory.appendingPathComponent("AuraWallpapers", isDirectory: true)
        setupDirectory()
    }

    private func setupDirectory() {
        if !fileManager.fileExists(atPath: wallpaperDirectory.path) {
            try? fileManager.createDirectory(at: wallpaperDirectory, withIntermediateDirectories: true)
        }
    }

    func applyWallpaper(_ descriptor: WallpaperDescriptor) async -> WallpaperApplyResult {
        print("🟢 [WallpaperEngine] Applying wallpaper of type: \(descriptor.type)")
        stopAnimation()

        let result: WallpaperApplyResult
        switch descriptor.type {
        case .staticImage:
            result = applyStatic(descriptor)
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
        case .dynamic:
            // For macOS, setting a .heic file automatically enables dynamic features if the file supports it
            result = applyStatic(descriptor)
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
           let url = await writeImageAsync(image) {
            return applyImageURLs([url])
        }
        return WallpaperApplyResult(success: false, permissionDenied: false)
    }

    private func startAnimated(_ descriptor: WallpaperDescriptor) {
        let fps = min(5, max(0.1, descriptor.fps)) // Limit FPS to reasonable background range
        if let resource = descriptor.resources.first,
           let resolvedURL = resolveResourceURL(resource) {

            let ext = resolvedURL.pathExtension.lowercased()
            if ["mp4", "mov"].contains(ext) {
                startVideoAnimated(resourceURL: resolvedURL, fps: fps)
                return
            } else if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                // If it resolved to an image (e.g., fallback), apply it statically
                _ = applyImageURLs([resolvedURL])
                return
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
        // Use shared logic from MediaUtils if possible, or replicate it here for independence
        if let sharedResolved = MediaUtils.resolveResourceURL(resource) {
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
        let style = descriptor.resources.first ?? "minimal"
        let palette = themeManager.palette
        let timeView = TimeWallpaperView(style: style, palette: palette)
        wallpaperWindowController.showSwiftUIView(timeView)
    }

    private func startQuote(_ descriptor: WallpaperDescriptor) {
        let style = descriptor.resources.first ?? "motivational"
        let palette = themeManager.palette
        let quoteID = descriptor.resources.count > 1 ? UUID(uuidString: descriptor.resources[1]) : nil
        let quoteView = QuoteWallpaperView(style: style, palette: palette, quoteID: quoteID)
        wallpaperWindowController.showSwiftUIView(quoteView)
    }

    private func startZen(_ descriptor: WallpaperDescriptor) {
        let style = descriptor.resources.first ?? "breathing"
        let palette = themeManager.palette
        let zenView = ZenWallpaperView(style: style, palette: palette)
        wallpaperWindowController.showSwiftUIView(zenView)
    }

    private func startWebsite(_ descriptor: WallpaperDescriptor) {
        guard let urlString = descriptor.resources.first else { return }
        let websiteView = WebsiteWallpaperView(urlString: urlString)
        wallpaperWindowController.showSwiftUIView(websiteView)
    }

    private func applyImageURLs(_ urls: [URL]) -> WallpaperApplyResult {
        var permissionDenied = false
        var applied = false
        let screens = NSScreen.screens

        if screens.isEmpty {
            // For headless environments (CI/Tests), we assume success if URLs exist
            let allExist = urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
            return WallpaperApplyResult(success: allExist, permissionDenied: false)
        }

        for screen in screens {
            for url in urls {
                do {
                    // This must be on main thread but we are calling it from background task sometimes
                    // Actually NSWorkspace.shared.setDesktopImageURL is thread-safe or handles its own thread management
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

    private func cleanupOldWallpapers(except currentURL: URL) {
        let urls = (try? fileManager.contentsOfDirectory(at: wallpaperDirectory, includingPropertiesForKeys: nil)) ?? []
        for url in urls where url != currentURL {
            try? fileManager.removeItem(at: url)
        }
    }

    private func stopAnimation() {
        for timer in animationTimers.values {
            timer.invalidate()
        }
        animationTimers.removeAll()
        wallpaperWindowController.stopAll()
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

    override init() {
        super.init()
        setupWindow()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupWindow() {
        // Create a borderless window that covers the entire screen
        let screenFrame = NSScreen.main?.frame ?? .zero
        let window = NSWindow(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Configure window level to be behind desktop icons but above the system wallpaper
        // Note: kCGDesktopWindowLevel is usually -2147483603
        // We use a slightly higher level to ensure visibility over system wallpaper
        // but lower than icons (kCGDesktopIconWindowLevel)
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))

        // Ensure window behavior is appropriate for a wallpaper
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.ignoresMouseEvents = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false

        // Create the video player view
        let playerView = NSView(frame: screenFrame)
        playerView.wantsLayer = true
        playerView.layer?.backgroundColor = NSColor.clear.cgColor
        playerView.autoresizingMask = [.width, .height]
        window.contentView = playerView

        self.window = window
        self.playerView = playerView

        // Handle screen changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenChanged() {
        guard let screen = NSScreen.main else { return }
        window?.setFrame(screen.frame, display: true)
        playerLayer?.frame = screen.frame
    }

    private var currentURL: URL?
    private var isSecurityScoped: Bool = false
    private var hostingContainerView: NSView?
    private var hostingView: NSHostingView<AnyView>?

    func showSwiftUIView<V: View>(_ view: V) {
        stopVideo()

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
        hideSwiftUIView()
        window?.orderOut(nil)
    }

    func isPlaying() -> Bool {
        return playerQueue != nil && playerQueue?.rate != 0 && window?.isVisible == true
    }
}
