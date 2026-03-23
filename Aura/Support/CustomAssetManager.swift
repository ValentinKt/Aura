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
