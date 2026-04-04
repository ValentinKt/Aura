import AVFoundation
import Foundation
import os

/// Resolves audio layer file URLs from the app bundle.
/// Does NOT load any audio data into memory — callers open files on demand.
actor AssetManager {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.valentinkt.Aura",
        category: "Asset"
    )

    // Cache only the resolved URL, never the decoded audio data.
    private var urlCache: [String: URL] = [:]

    /// Returns the on-disk URL for a named audio layer, or nil if not found.
    /// Callers are responsible for opening AVAudioFile from this URL when needed.
    func resolveAudioURL(named name: String) -> URL? {
        if let cached = urlCache[name] {
            return cached
        }

        let url = Self.findAudioFile(named: name)
        if let url {
            urlCache[name] = url
        } else {
            Self.logger.warning("Audio file not found for layer: \(name, privacy: .public)")
        }
        return url
    }

    private static func findAudioFile(named name: String) -> URL? {
        let bundle = Bundle.main
        return
            bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Resources/Audio") ??
            bundle.url(forResource: name, withExtension: "m4a", subdirectory: "Audio") ??
            bundle.url(forResource: name, withExtension: "m4a")
    }
}
