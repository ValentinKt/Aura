import Foundation
import CoreVideo
import AppKit

@MainActor
final class GatedDisplayLink {
    @available(macOS 15.0, *)
    private var nsDisplayLink: NSDisplayLink?
    private var legacyDisplayLink: CVDisplayLink?
    private var isRunning = false
    var onFrame: (() -> Void)?

    @objc private func handleDisplayLink(_ sender: Any) {
        onFrame?()
    }

    func start() {
        guard !isRunning else { return }
        if #available(macOS 15.0, *) {
            guard let screen = NSScreen.main else { return }
            nsDisplayLink = screen.displayLink(target: self, selector: #selector(handleDisplayLink(_:)))
            if let link = nsDisplayLink {
                link.add(to: .current, forMode: .common)
                isRunning = true
            }
        } else {
            CVDisplayLinkCreateWithActiveCGDisplays(&legacyDisplayLink)
            guard let dl = legacyDisplayLink else { return }

            let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, ctx in
                let self_ = Unmanaged<GatedDisplayLink>.fromOpaque(ctx!).takeUnretainedValue()
                DispatchQueue.main.async { self_.onFrame?() }
                return kCVReturnSuccess
            }
            CVDisplayLinkSetOutputCallback(dl, callback, Unmanaged.passUnretained(self).toOpaque())
            CVDisplayLinkStart(dl)
            isRunning = true
        }
    }

    func stop() {
        guard isRunning else { return }
        if #available(macOS 15.0, *) {
            nsDisplayLink?.invalidate()
            nsDisplayLink = nil
            isRunning = false
        } else {
            if let dl = legacyDisplayLink {
                CVDisplayLinkStop(dl)
            }
            legacyDisplayLink = nil
            isRunning = false
        }
    }

    deinit {
        stop()
    }
}

struct WallpaperSchedule: Hashable, Codable {
    var id: UUID
    var timeOfDay: DateComponents?
    var interval: TimeInterval?
    var wallpaper: WallpaperDescriptor

    init(id: UUID = UUID(), timeOfDay: DateComponents? = nil, interval: TimeInterval? = nil, wallpaper: WallpaperDescriptor) {
        self.id = id
        self.timeOfDay = timeOfDay
        self.interval = interval
        self.wallpaper = wallpaper
    }
}

@MainActor
final class WallpaperScheduler {
    private var schedules: [WallpaperSchedule] = []
    private var schedulerTask: Task<Void, Never>?
    private var lastTick: TimeInterval = 0

    func updateSchedules(_ schedules: [WallpaperSchedule]) {
        self.schedules = schedules
    }

    func start(handler: @escaping (WallpaperDescriptor) -> Void) {
        stop()
        schedulerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self = self else { break }
                self.tick(handler: handler)
            }
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    private func tick(handler: (WallpaperDescriptor) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        for schedule in schedules {
            if let time = schedule.timeOfDay {
                if calendar.dateComponents([.hour, .minute], from: now) == DateComponents(hour: time.hour, minute: time.minute) {
                    handler(schedule.wallpaper)
                    return
                }
            }
            if let interval = schedule.interval, interval > 0 {
                if Int(now.timeIntervalSince1970) % Int(interval) < 60 {
                    handler(schedule.wallpaper)
                    return
                }
            }
        }
    }
}
