import AVFoundation
import SwiftUI

struct VideoBackgroundView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSView {
        let view = VideoLoopView(frame: .zero)
        view.play(url: url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let loopView = nsView as? VideoLoopView {
            loopView.play(url: url)
        }
    }
}

private class VideoLoopView: NSView {
    private var playerLayer: AVPlayerLayer?
    private var imageLayer: CALayer?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var currentURL: URL?
    private var isSecurityScoped: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    func play(url: URL) {
        // Avoid restarting if the same URL is already playing
        if currentURL == url {
            if player != nil || imageLayer != nil {
                return
            }
        }

        // --- STEP 1: SHUTDOWN OLD PIPELINE ---
        teardown()

        print("🟢 [VideoBackgroundView] Loading: \(url.lastPathComponent)")

        currentURL = url
        isSecurityScoped = url.startAccessingSecurityScopedResource()

        // Ensure file exists and is reachable
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("🟥 [VideoBackgroundView] File not found at path: \(url.path)")
            return
        }

        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "heic"].contains(ext) {
            // --- IMAGE FALLBACK ---
            guard let image = NSImage(contentsOf: url) else {
                print("🟥 [VideoBackgroundView] Failed to load image at: \(url.path)")
                return
            }

            let layer = CALayer()
            layer.contents = image
            layer.contentsGravity = .resizeAspectFill
            layer.frame = self.bounds
            self.layer?.addSublayer(layer)
            self.imageLayer = layer
            return
        }

        // --- STEP 2: CONFIGURE ASSET (VIDEO) ---
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)

        item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        item.preferredPeakBitRate = 5_000_000
        item.preferredForwardBufferDuration = 2.0

        // Fix for HALC / SoundEngine overload: Disable audio processing
        item.audioTimePitchAlgorithm = .varispeed
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = false

        // --- STEP 3: INITIALIZE PLAYER ---
        let newPlayer = AVQueuePlayer(playerItem: item)
        newPlayer.automaticallyWaitsToMinimizeStalling = true
        newPlayer.allowsExternalPlayback = false
        newPlayer.isMuted = true // Critical: Prevents FigAirPlay_Route errors
        newPlayer.volume = 0

        self.player = newPlayer

        // --- STEP 4: SETUP LOOPER ---
        self.looper = AVPlayerLooper(player: newPlayer, templateItem: item)

        // --- STEP 5: VISUALS ---
        let newLayer = AVPlayerLayer(player: newPlayer)
        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = self.bounds
        self.layer?.addSublayer(newLayer)
        self.playerLayer = newLayer

        newPlayer.play()
    }

    func teardown() {
        // Stop playback
        player?.pause()

        // Break the loop and clear the queue
        looper?.disableLooping()
        looper = nil
        player?.removeAllItems()

        // CRITICAL: This line tells the macOS Hardware Decoder (VMC)
        // to immediately release the file handle and GPU buffers.
        player?.replaceCurrentItem(with: nil)

        // Remove the old visual layer so it doesn't draw "nothing"
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil

        imageLayer?.removeFromSuperlayer()
        imageLayer = nil

        player = nil

        if let url = currentURL, isSecurityScoped {
            url.stopAccessingSecurityScopedResource()
            currentURL = nil
            isSecurityScoped = false
        }
    }

    deinit {
        teardown()
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
        imageLayer?.frame = bounds
    }
}
