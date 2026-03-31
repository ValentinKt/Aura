import AppKit
import Foundation

enum CustomAssetManager {
    static let fileManager = FileManager.default

    static var appSupportDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Aura", isDirectory: true)
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        return appDir
    }

    static var customWallpapersDirectory: URL {
        let customDir = appSupportDirectory.appendingPathComponent("CustomWallpapers", isDirectory: true)
        if !fileManager.fileExists(atPath: customDir.path) {
            try? fileManager.createDirectory(at: customDir, withIntermediateDirectories: true)
        }
        return customDir
    }

    static var subthemeAssetsDirectory: URL {
        let assetsDir = appSupportDirectory.appendingPathComponent("SubthemeAssets", isDirectory: true)
        if !fileManager.fileExists(atPath: assetsDir.path) {
            try? fileManager.createDirectory(at: assetsDir, withIntermediateDirectories: true)
        }
        return assetsDir
    }

    static var customAudioDirectory: URL {
        let audioDir = appSupportDirectory.appendingPathComponent("CustomAudio", isDirectory: true)
        if !fileManager.fileExists(atPath: audioDir.path) {
            try? fileManager.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        return audioDir
    }

    static func saveCustomWallpaper(from url: URL) throws -> String {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let filename = "\(UUID().uuidString).\(url.pathExtension)"
        let destination = customWallpapersDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: url, to: destination)
        return destination.path
    }

    static func makeCustomWallpaperURL(fileExtension: String) -> URL {
        let normalizedExtension = fileExtension.lowercased()
        let filename = "\(UUID().uuidString).\(normalizedExtension)"
        return customWallpapersDirectory.appendingPathComponent(filename)
    }

    static func saveCustomWallpaper(from image: NSImage, preferredFileExtension: String = "jpg") throws -> String {
        let maxDimension: CGFloat = 3840.0
        var finalImage = image

        let size = image.size
        if size.width > maxDimension || size.height > maxDimension {
            let ratio = min(maxDimension / size.width, maxDimension / size.height)
            let newSize = NSSize(width: round(size.width * ratio), height: round(size.height * ratio))

            let newImage = NSImage(size: newSize)
            newImage.lockFocus()
            NSGraphicsContext.current?.imageInterpolation = .high
            image.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
            newImage.unlockFocus()
            finalImage = newImage
        }

        guard let tiffRepresentation = finalImage.tiffRepresentation,
              let bitmapRepresentation = NSBitmapImageRep(data: tiffRepresentation) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let normalizedExtension = preferredFileExtension.lowercased()
        let imageFileType: NSBitmapImageRep.FileType
        let properties: [NSBitmapImageRep.PropertyKey: Any]

        switch normalizedExtension {
        case "jpg", "jpeg":
            imageFileType = .jpeg
            properties = [.compressionFactor: 0.8]
        default:
            imageFileType = .png
            properties = [:]
        }

        guard let imageData = bitmapRepresentation.representation(using: imageFileType, properties: properties) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let filename = "\(UUID().uuidString).\(normalizedExtension)"
        let destination = customWallpapersDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try imageData.write(to: destination, options: [.atomic])
        return destination.path
    }

    static func saveCustomAudio(from url: URL) throws -> String {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let filename = "\(UUID().uuidString).\(url.pathExtension)"
        let destination = customAudioDirectory.appendingPathComponent(filename)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        try fileManager.copyItem(at: url, to: destination)
        return destination.path
    }

    static func saveSubthemeAsset(from url: URL, subtheme: String) throws -> String {
        let subthemeDir = subthemeAssetsDirectory.appendingPathComponent(subtheme.lowercased().replacingOccurrences(of: " ", with: "_"), isDirectory: true)
        if !fileManager.fileExists(atPath: subthemeDir.path) {
            try fileManager.createDirectory(at: subthemeDir, withIntermediateDirectories: true)
        }

        let filename = "\(UUID().uuidString).\(url.pathExtension)"
        let destination = subthemeDir.appendingPathComponent(filename)

        try fileManager.copyItem(at: url, to: destination)
        return destination.path
    }

    static func removeCustomAudio(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    static func removeCustomWallpaper(atPath path: String) {
        let url = URL(fileURLWithPath: path)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}
