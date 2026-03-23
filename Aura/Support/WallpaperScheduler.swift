import Foundation

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

final class WallpaperScheduler {
    private var schedules: [WallpaperSchedule] = []
    private var timer: Timer?

    func updateSchedules(_ schedules: [WallpaperSchedule]) {
        self.schedules = schedules
    }

    func start(handler: @escaping (WallpaperDescriptor) -> Void) {
        timer?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.tick(handler: handler)
        }
        timer.tolerance = 15 // Increase tolerance to 15s for better energy efficiency
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
