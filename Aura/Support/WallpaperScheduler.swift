import Foundation
import CoreVideo
import AppKit

@MainActor
final class GatedDisplayLink {
    private var displayLink: CVDisplayLink?
    private var isRunning = false
    var onFrame: (() -> Void)?

    func start() {
        guard !isRunning else { return }
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        guard let dl = displayLink else { return }

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, ctx in
            let self_ = Unmanaged<GatedDisplayLink>.fromOpaque(ctx!).takeUnretainedValue()
            Task { @MainActor in
                self_.onFrame?()
            }
            return kCVReturnSuccess
        }
        CVDisplayLinkSetOutputCallback(dl, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(dl)
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
        }
        displayLink = nil
        isRunning = false
    }

    deinit {
        if let dl = displayLink {
            CVDisplayLinkStop(dl)
        }
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
        schedulerTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                await AuraBackgroundActor.sleep(for: .seconds(60))
                guard let self = self else { return }
                await MainActor.run {
                    self.tick(handler: handler)
                }
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
