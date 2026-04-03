import Foundation
import CoreVideo
import AppKit
import QuartzCore

@MainActor
final class GatedDisplayLink {
    private var displayLink: CADisplayLink?
    private var isRunning = false
    var onFrame: (() -> Void)?

    func start() {
        guard !isRunning else { return }
        guard let screen = NSScreen.main else { return }

        displayLink = screen.displayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .current, forMode: .default)
        isRunning = true
    }

    @objc private func tick() {
        onFrame?()
    }

    func stop() {
        guard isRunning else { return }
        displayLink?.invalidate()
        displayLink = nil
        isRunning = false
    }

    deinit {
        displayLink?.invalidate()
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
    private var handler: ((WallpaperDescriptor) -> Void)?
    private var lastTriggerByScheduleID: [UUID: Date] = [:]

    func updateSchedules(_ schedules: [WallpaperSchedule]) {
        self.schedules = schedules
        guard let handler else { return }
        start(handler: handler)
    }

    func start(handler: @escaping (WallpaperDescriptor) -> Void) {
        stop()
        self.handler = handler
        guard let nextTrigger = nextTrigger() else { return }

        let delay = max(0, nextTrigger.fireDate.timeIntervalSinceNow)
        schedulerTask = Task(priority: .background) { [weak self] in
            await AuraBackgroundActor.sleep(for: .seconds(delay))
            await AuraBackgroundActor.waitUntilRenderingActive()
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.lastTriggerByScheduleID[nextTrigger.schedule.id] = nextTrigger.fireDate
                handler(nextTrigger.schedule.wallpaper)
                self.start(handler: handler)
            }
        }
    }

    func stop() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    private func nextTrigger(referenceDate: Date = Date()) -> (schedule: WallpaperSchedule, fireDate: Date)? {
        let calendar = Calendar.current

        return schedules.compactMap { schedule -> (schedule: WallpaperSchedule, fireDate: Date)? in
            var candidates: [Date] = []

            if let time = schedule.timeOfDay,
               let nextDate = calendar.nextDate(
                   after: referenceDate.addingTimeInterval(-1),
                   matching: time,
                   matchingPolicy: .nextTime,
                   repeatedTimePolicy: .first,
                   direction: .forward
               ) {
                candidates.append(nextDate)
            }

            if let interval = schedule.interval, interval > 0 {
                let referenceTimestamp = referenceDate.timeIntervalSince1970
                let nextTimestamp = ceil(referenceTimestamp / interval) * interval
                candidates.append(Date(timeIntervalSince1970: nextTimestamp))
            }

            guard let fireDate = candidates.min() else { return nil }

            if let lastTrigger = lastTriggerByScheduleID[schedule.id],
               abs(fireDate.timeIntervalSince(lastTrigger)) < 1 {
                return nil
            }

            return (schedule, fireDate)
        }
        .min(by: { $0.fireDate < $1.fireDate })
    }
}
