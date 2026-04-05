import AVFoundation
import SwiftUI

struct IsolatedVideoBackgroundView: View, Equatable {
    let url: URL

    static func == (lhs: IsolatedVideoBackgroundView, rhs: IsolatedVideoBackgroundView) -> Bool {
        lhs.url == rhs.url
    }

    var body: some View {
        VideoBackgroundView(url: url)
            .allowsHitTesting(false)
    }
}

extension View {
    func auraPersistentSystemOverlaysHidden() -> some View {
        persistentSystemOverlays(.hidden)
    }
}

struct VideoBackgroundView: View {
    let url: URL

    var body: some View {
        DualVideoPlayerView(url: url)
            .allowsHitTesting(false)
    }
}

struct DualVideoPlayerView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> DualVideoPlayerSurfaceView {
        let view = DualVideoPlayerSurfaceView(frame: .zero)
        view.play(url: url)
        return view
    }

    func updateNSView(_ nsView: DualVideoPlayerSurfaceView, context: Context) {
        nsView.play(url: url)
    }

    static func dismantleNSView(_ nsView: DualVideoPlayerSurfaceView, coordinator: ()) {
        nsView.teardown()
    }
}

final class DualVideoPlayerSurfaceView: NSView {
    private final class PlayerSlot {
        let player: AVPlayer
        let layer: AVPlayerLayer

        init() {
            player = AVPlayer()
            player.automaticallyWaitsToMinimizeStalling = false
            player.allowsExternalPlayback = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            player.isMuted = true
            player.volume = 0
            player.actionAtItemEnd = .pause

            layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.isOpaque = true
            layer.drawsAsynchronously = true
            layer.opacity = 0
        }
    }

    private enum SlotPosition: Int {
        case a = 0
        case b = 1

        var other: SlotPosition {
            self == .a ? .b : .a
        }
    }

    private static let observerInterval = CMTime(value: 1, timescale: 30)
    private static let defaultOverlapDuration: Double = 1
    private static let minimumOverlapDuration: Double = 0.2

    private let slots = [PlayerSlot(), PlayerSlot()]
    private var activeSlot: SlotPosition = .a
    private var currentURL: URL?
    private var currentAsset: AVURLAsset?
    private var assetLoadTask: Task<Void, Never>?
    private var observedPlayer: AVPlayer?
    private var periodicObserver: Any?
    private var playbackGeneration = UUID()
    private var currentDurationSeconds: Double?
    private var currentOverlapDuration = 1.0
    private var isPlaybackPrepared = false
    private var isCrossfading = false
    private var isSecurityScoped = false
    private var usesAutomaticVisibilitySuspension = true
    private var isManuallySuspended = false
    private var imageLayer: CALayer?
    private var windowObservation: NSKeyValueObservation?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.drawsAsynchronously = true

        slots.forEach { slot in
            layer?.addSublayer(slot.layer)
        }
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.drawsAsynchronously = true

        slots.forEach { slot in
            layer?.addSublayer(slot.layer)
        }
    }

    var isPlaying: Bool {
        slot(for: activeSlot).player.rate != 0
    }

    func setUsesAutomaticVisibilitySuspension(_ enabled: Bool) {
        guard usesAutomaticVisibilitySuspension != enabled else { return }
        usesAutomaticVisibilitySuspension = enabled
        refreshVisibilityObservation()
        updatePlaybackState()
    }

    func play(url: URL) {
        if currentURL != url {
            releaseSecurityScope()
            teardownPlayback()
            imageLayer?.removeFromSuperlayer()
            imageLayer = nil

            currentURL = url
            isSecurityScoped = url.startAccessingSecurityScopedResource()

            guard FileManager.default.fileExists(atPath: url.path) else {
                return
            }

            let ext = url.pathExtension.lowercased()
            if ["jpg", "jpeg", "png", "heic"].contains(ext) {
                let newImageLayer = CALayer()
                newImageLayer.contents = NSImage(contentsOf: url)
                newImageLayer.contentsGravity = .resizeAspectFill
                newImageLayer.drawsAsynchronously = true
                newImageLayer.opacity = 1
                layer?.addSublayer(newImageLayer)
                imageLayer = newImageLayer
            }
        }

        updatePlaybackState()
    }

    func setPlaybackSuspended(_ suspended: Bool) {
        guard isManuallySuspended != suspended else { return }
        isManuallySuspended = suspended
        updatePlaybackState()
    }

    func teardown() {
        teardownPlayback()
        imageLayer?.removeFromSuperlayer()
        imageLayer = nil
        currentURL = nil
        releaseSecurityScope()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshVisibilityObservation()
        updatePlaybackState()
    }

    override func layout() {
        super.layout()
        layer?.sublayers?.forEach { $0.frame = bounds }
    }

    deinit {
        windowObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
        assetLoadTask?.cancel()
        assetLoadTask = nil
        currentAsset?.cancelLoading()
        currentAsset = nil
        removePeriodicObserver()

        slots.forEach { slot in
            slot.layer.removeAllAnimations()
            slot.player.pause()
            slot.player.currentItem?.cancelPendingSeeks()
            slot.player.currentItem?.asset.cancelLoading()
            slot.player.replaceCurrentItem(with: nil)
        }

        if let currentURL, isSecurityScoped {
            currentURL.stopAccessingSecurityScopedResource()
        }
    }

    @objc private func visibilityChanged() {
        updatePlaybackState()
    }

    private func updatePlaybackState() {
        let shouldRender = !isManuallySuspended && (!usesAutomaticVisibilitySuspension || isWindowVisibleForRendering)
        imageLayer?.isHidden = !shouldRender

        if shouldRender {
            resumePlaybackIfNeeded()
        } else {
            freezePlayback()
        }
    }

    private var isWindowVisibleForRendering: Bool {
        guard let window else { return false }
        return window.isVisible &&
            !window.isMiniaturized &&
            window.occlusionState.contains(.visible) &&
            !NSApp.isHidden
    }

    private func slot(for position: SlotPosition) -> PlayerSlot {
        slots[position.rawValue]
    }

    private func refreshVisibilityObservation() {
        windowObservation?.invalidate()
        windowObservation = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didMiniaturizeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didDeminiaturizeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didHideNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didUnhideNotification, object: nil)

        guard usesAutomaticVisibilitySuspension else { return }

        if let window {
            windowObservation = window.observe(\.isVisible, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.updatePlaybackState()
                }
            }
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didMiniaturizeNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didDeminiaturizeNotification, object: window)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSApplication.didHideNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(visibilityChanged), name: NSApplication.didUnhideNotification, object: nil)
    }

    private func resumePlaybackIfNeeded() {
        guard imageLayer == nil else {
            imageLayer?.isHidden = false
            return
        }

        guard let currentURL else { return }

        if !isPlaybackPrepared {
            configureVideoPlayback(for: currentURL)
        }

        guard isPlaybackPrepared else {
            return
        }

        let activePlayer = slot(for: activeSlot).player
        slot(for: activeSlot).layer.isHidden = false
        installPeriodicObserver(on: activePlayer)
        activePlayer.playImmediately(atRate: 1)
    }

    private func configureVideoPlayback(for url: URL) {
        teardownPlayback()

        let generation = UUID()
        playbackGeneration = generation

        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        currentAsset = asset
        currentDurationSeconds = nil
        currentOverlapDuration = DualVideoPlayerSurfaceView.defaultOverlapDuration
        activeSlot = .a

        for position in [SlotPosition.a, .b] {
            let item = makePlayerItem(asset: asset)
            let slot = slot(for: position)
            slot.player.replaceCurrentItem(with: item)
            slot.player.seek(to: .zero)
            slot.layer.removeAllAnimations()
            slot.layer.opacity = position == activeSlot ? 1 : 0
            slot.layer.isHidden = false
            slot.layer.zPosition = position == activeSlot ? 0 : 1
        }

        isPlaybackPrepared = true
        isCrossfading = false

        assetLoadTask?.cancel()
        assetLoadTask = Task(priority: .utility) { [weak self] in
            do {
                async let loadedTracks = asset.load(.tracks)
                async let loadedDuration = asset.load(.duration)
                _ = try await loadedTracks
                let duration = try await loadedDuration

                await MainActor.run {
                    guard let self, self.playbackGeneration == generation else { return }
                    let seconds = duration.seconds
                    self.currentDurationSeconds = seconds.isFinite ? seconds : nil
                    self.currentOverlapDuration = self.resolvedOverlapDuration(for: self.currentDurationSeconds)
                }
            } catch {
                await MainActor.run {
                    guard let self, self.playbackGeneration == generation else { return }
                    self.currentDurationSeconds = nil
                    self.currentOverlapDuration = DualVideoPlayerSurfaceView.defaultOverlapDuration
                }
            }
        }
    }

    private func makePlayerItem(asset: AVURLAsset) -> AVPlayerItem {
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .varispeed
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
        item.preferredForwardBufferDuration = 0
        item.preferredPeakBitRate = 5_000_000

        if let screen = window?.screen ?? NSScreen.main {
            let scale = screen.backingScaleFactor
            item.preferredMaximumResolution = CGSize(
                width: screen.frame.width * scale,
                height: screen.frame.height * scale
            )
        } else {
            item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        }

        return item
    }

    private func freezePlayback() {
        guard isPlaybackPrepared || periodicObserver != nil else {
            return
        }

        teardownPlayback()
    }

    private func teardownPlayback() {
        assetLoadTask?.cancel()
        assetLoadTask = nil
        currentAsset?.cancelLoading()
        currentAsset = nil
        currentDurationSeconds = nil
        currentOverlapDuration = DualVideoPlayerSurfaceView.defaultOverlapDuration
        isPlaybackPrepared = false
        isCrossfading = false
        playbackGeneration = UUID()

        removePeriodicObserver()

        slots.forEach { slot in
            slot.layer.removeAllAnimations()
            slot.layer.opacity = 0
            slot.layer.isHidden = true
            slot.player.pause()
            slot.player.currentItem?.cancelPendingSeeks()
            slot.player.currentItem?.asset.cancelLoading()
            slot.player.replaceCurrentItem(with: nil)
        }
    }

    private func installPeriodicObserver(on player: AVPlayer) {
        guard observedPlayer !== player else {
            return
        }

        removePeriodicObserver()
        observedPlayer = player
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: Self.observerInterval,
            queue: .main
        ) { [weak self] time in
            self?.handlePlaybackTick(at: time)
        }
    }

    private func removePeriodicObserver() {
        if let periodicObserver, let observedPlayer {
            observedPlayer.removeTimeObserver(periodicObserver)
        }
        periodicObserver = nil
        observedPlayer = nil
    }

    private func handlePlaybackTick(at time: CMTime) {
        guard isPlaybackPrepared, !isCrossfading else {
            return
        }

        let currentSeconds = time.seconds
        guard currentSeconds.isFinite, let durationSeconds = resolvedDurationSeconds() else {
            return
        }

        let remainingSeconds = durationSeconds - currentSeconds
        guard remainingSeconds <= currentOverlapDuration, remainingSeconds > 0 else {
            return
        }

        beginCrossfade()
    }

    private func resolvedDurationSeconds() -> Double? {
        if let currentDurationSeconds, currentDurationSeconds.isFinite {
            return currentDurationSeconds
        }

        let seconds = slot(for: activeSlot).player.currentItem?.duration.seconds ?? .nan
        return seconds.isFinite ? seconds : nil
    }

    private func resolvedOverlapDuration(for durationSeconds: Double?) -> Double {
        guard let durationSeconds, durationSeconds.isFinite else {
            return DualVideoPlayerSurfaceView.defaultOverlapDuration
        }

        return min(
            DualVideoPlayerSurfaceView.defaultOverlapDuration,
            max(DualVideoPlayerSurfaceView.minimumOverlapDuration, durationSeconds / 2)
        )
    }

    private func beginCrossfade() {
        guard isPlaybackPrepared else { return }

        let generation = playbackGeneration
        let outgoingPosition = activeSlot
        let incomingPosition = outgoingPosition.other
        let outgoingSlot = slot(for: outgoingPosition)
        let incomingSlot = slot(for: incomingPosition)

        guard incomingSlot.player.currentItem != nil else {
            return
        }

        isCrossfading = true

        incomingSlot.layer.removeAllAnimations()
        outgoingSlot.layer.removeAllAnimations()
        incomingSlot.layer.opacity = 0
        incomingSlot.layer.isHidden = false
        incomingSlot.layer.zPosition = 1
        outgoingSlot.layer.zPosition = 0
        incomingSlot.player.pause()

        incomingSlot.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self, finished, self.playbackGeneration == generation, self.isPlaybackPrepared else {
                return
            }

            incomingSlot.player.playImmediately(atRate: 1)
            self.animateCrossfade(
                from: outgoingPosition,
                to: incomingPosition,
                overlapDuration: self.currentOverlapDuration,
                generation: generation
            )
        }
    }

    private func animateCrossfade(
        from outgoingPosition: SlotPosition,
        to incomingPosition: SlotPosition,
        overlapDuration: Double,
        generation: UUID
    ) {
        let outgoingSlot = slot(for: outgoingPosition)
        let incomingSlot = slot(for: incomingPosition)

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.playbackGeneration == generation else { return }
            self.completeCrossfade(from: outgoingPosition, to: incomingPosition)
        }

        let fadeIn = CABasicAnimation(keyPath: "opacity")
        fadeIn.fromValue = 0
        fadeIn.toValue = 1
        fadeIn.duration = overlapDuration
        fadeIn.timingFunction = CAMediaTimingFunction(name: .linear)

        let fadeOut = CABasicAnimation(keyPath: "opacity")
        fadeOut.fromValue = 1
        fadeOut.toValue = 0
        fadeOut.duration = overlapDuration
        fadeOut.timingFunction = CAMediaTimingFunction(name: .linear)

        incomingSlot.layer.add(fadeIn, forKey: "aura.crossfade.in")
        outgoingSlot.layer.add(fadeOut, forKey: "aura.crossfade.out")
        incomingSlot.layer.opacity = 1
        outgoingSlot.layer.opacity = 0

        CATransaction.commit()
    }

    private func completeCrossfade(from outgoingPosition: SlotPosition, to incomingPosition: SlotPosition) {
        let outgoingSlot = slot(for: outgoingPosition)
        let incomingSlot = slot(for: incomingPosition)

        outgoingSlot.layer.removeAllAnimations()
        incomingSlot.layer.removeAllAnimations()
        outgoingSlot.player.pause()
        outgoingSlot.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        outgoingSlot.layer.opacity = 0
        outgoingSlot.layer.isHidden = false
        outgoingSlot.layer.zPosition = 0
        incomingSlot.layer.zPosition = 1

        activeSlot = incomingPosition
        isCrossfading = false

        installPeriodicObserver(on: incomingSlot.player)
    }

    private func releaseSecurityScope() {
        if let currentURL, isSecurityScoped {
            currentURL.stopAccessingSecurityScopedResource()
        }

        isSecurityScoped = false
    }
}
