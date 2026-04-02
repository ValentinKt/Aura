import AVFoundation
import SwiftUI

struct VideoBackgroundView: NSViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> VideoBackgroundSurfaceView {
        let view = VideoBackgroundSurfaceView(frame: .zero)
        context.coordinator.attach(to: view)
        context.coordinator.play(url: url, in: view)
        return view
    }

    func updateNSView(_ nsView: VideoBackgroundSurfaceView, context: Context) {
        context.coordinator.attach(to: nsView)
        context.coordinator.play(url: url, in: nsView)
    }

    static func dismantleNSView(_ nsView: VideoBackgroundSurfaceView, coordinator: Coordinator) {
        coordinator.detach(from: nsView)
        coordinator.teardown()
    }

    final class Coordinator {
        private var playerLayer: AVPlayerLayer?
        private var imageLayer: CALayer?
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var currentURL: URL?
        private var isSecurityScoped = false
        private weak var view: VideoBackgroundSurfaceView?
        private var assetLoadTask: Task<Void, Never>?

        init() {
            player.automaticallyWaitsToMinimizeStalling = false
            player.allowsExternalPlayback = false
            player.isMuted = true
            player.volume = 0
        }

        func attach(to view: VideoBackgroundSurfaceView) {
            guard self.view !== view else { return }
            self.view = view
            view.visibilityDidChange = { [weak self] in
                self?.updatePlaybackState()
            }
            if let playerLayer {
                view.attachVideoLayer(playerLayer)
            }
            if let imageLayer {
                view.attachImageLayer(imageLayer)
            }
            updatePlaybackState()
        }

        func detach(from view: VideoBackgroundSurfaceView) {
            guard self.view === view else { return }
            view.visibilityDidChange = nil
            self.view = nil
        }

        func play(url: URL, in view: VideoBackgroundSurfaceView) {
            attach(to: view)

            if currentURL == url, playerLayer != nil || imageLayer != nil {
                updatePlaybackState()
                return
            }

            teardown()

            currentURL = url
            isSecurityScoped = url.startAccessingSecurityScopedResource()

            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                let layer = CALayer()
                layer.contents = NSImage(contentsOf: url)
                layer.contentsGravity = .resizeAspectFill
                imageLayer = layer
                view.attachImageLayer(layer)
                updatePlaybackState()
                return
            }

            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
            let item = AVPlayerItem(asset: asset)

            assetLoadTask?.cancel()
            assetLoadTask = Task {
                _ = try? await asset.load(.tracks)
            }

            if let screen = view.window?.screen ?? NSScreen.main {
                let scale = screen.backingScaleFactor
                item.preferredMaximumResolution = CGSize(width: screen.frame.width * scale, height: screen.frame.height * scale)
            } else {
                item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
            }
            item.preferredPeakBitRate = 5_000_000
            item.preferredForwardBufferDuration = 0
            item.audioTimePitchAlgorithm = .varispeed
            item.canUseNetworkResourcesForLiveStreamingWhilePaused = false

            player.removeAllItems()
            player.replaceCurrentItem(with: nil)
            player.insert(item, after: nil)
            looper = AVPlayerLooper(player: player, templateItem: item)

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.drawsAsynchronously = true
            playerLayer = layer
            view.attachVideoLayer(layer)
            updatePlaybackState()
        }

        func teardown() {
            assetLoadTask?.cancel()
            assetLoadTask = nil
            player.pause()
            looper?.disableLooping()
            looper = nil
            player.removeAllItems()
            player.replaceCurrentItem(with: nil)
            playerLayer?.player = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil
            imageLayer?.removeFromSuperlayer()
            imageLayer = nil

            if let currentURL, isSecurityScoped {
                currentURL.stopAccessingSecurityScopedResource()
            }
            currentURL = nil
            isSecurityScoped = false
        }

        private func updatePlaybackState() {
            guard let view else {
                player.pause()
                playerLayer?.isHidden = true
                return
            }

            let shouldRender = view.shouldRender
            playerLayer?.isHidden = !shouldRender
            imageLayer?.isHidden = !shouldRender

            if shouldRender {
                player.play()
            } else {
                player.pause()
            }
        }
    }
}

final class VideoBackgroundSurfaceView: NSView {
    var visibilityDidChange: (() -> Void)?

    private var windowObservation: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.drawsAsynchronously = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.drawsAsynchronously = true
    }

    var shouldRender: Bool {
        guard let window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    func attachVideoLayer(_ layer: AVPlayerLayer) {
        self.layer?.addSublayer(layer)
        needsLayout = true
    }

    func attachImageLayer(_ layer: CALayer) {
        self.layer?.addSublayer(layer)
        needsLayout = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        windowObservation?.invalidate()
        windowObservation = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)

        if let window {
            windowObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
                self?.visibilityDidChange?()
            }
            NotificationCenter.default.addObserver(self, selector: #selector(windowOcclusionDidChange), name: NSWindow.didChangeOcclusionStateNotification, object: window)
        } else {
            visibilityDidChange?()
        }
    }

    @objc private func windowOcclusionDidChange() {
        visibilityDidChange?()
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    deinit {
        windowObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}
