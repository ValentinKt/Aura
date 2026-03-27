import Foundation
import os

extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura"

    /// Logs related to application lifecycle and general state
    static let app = Logger(subsystem: subsystem, category: "App")

    /// Logs related to mood transitions and management
    static let mood = Logger(subsystem: subsystem, category: "Mood")

    /// Logs related to sound engine and audio playback
    static let sound = Logger(subsystem: subsystem, category: "Sound")

    /// Logs related to wallpaper management and rendering
    static let wallpaper = Logger(subsystem: subsystem, category: "Wallpaper")

    /// Logs related to media resources and asset management
    static let media = Logger(subsystem: subsystem, category: "Media")

    /// Logs related to persistence and data management
    static let persistence = Logger(subsystem: subsystem, category: "Persistence")

    /// Logs related to weather and location services
    static let weather = Logger(subsystem: subsystem, category: "Weather")
}
