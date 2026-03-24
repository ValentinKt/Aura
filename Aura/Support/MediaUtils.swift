import AVFoundation
import SwiftUI

enum MediaUtils {
    nonisolated static func resolveImageFallback(for name: String) -> URL? {
        // Try the local absolute path first
        let absolutePath = "/Users/valentin/XCode/Aura/Aura/Resources/Image/\(name).jpg"
        if FileManager.default.fileExists(atPath: absolutePath) {
            return URL(fileURLWithPath: absolutePath)
        }
        
        // Then try bundle
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/Image") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "Image") {
            return url
        }
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg") {
            return url
        }
        return nil
    }
    
    nonisolated static func resolveResourceURL(_ resource: String) -> URL? {
        print("🟢 [MediaUtils] Resolving resource: \(resource)")
        // 1. Check if it's already an absolute path and exists
        if resource.hasPrefix("/") {
            let url = URL(fileURLWithPath: resource)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        let fileManager = FileManager.default
        
        // 1.5 Check if it's already downloaded in Application Support
        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let videoURL = appSupport.appendingPathComponent("Aura/Videos").appendingPathComponent(resource)
            if fileManager.fileExists(atPath: videoURL.path) {
                print("🟢 [MediaUtils] Found downloaded resource at \(videoURL.path)")
                return videoURL
            }
        }
        
        let bundle = Bundle.main
        
        // Split name and extension if needed
        let resourceURL = URL(fileURLWithPath: resource)
        let name = resourceURL.deletingPathExtension().lastPathComponent
        let ext = resourceURL.pathExtension.isEmpty ? nil : resourceURL.pathExtension
        
        // Force download for non-first wallpapers (videos)
        let isVideo = ext?.lowercased() == "mov" || ext?.lowercased() == "mp4"
        if isVideo && !name.hasSuffix("_1") {
            // No warning here, this is expected for non-first items
            // If the video is not downloaded, we should still try to return a placeholder image
            if let imageFallbackURL = resolveImageFallback(for: name) {
                print("🟢 [MediaUtils] Returning image fallback for \(name)")
                return imageFallbackURL
            }
            return nil
        }
        
        // 2. Check in various potential subdirectories
        let subdirs = [
            "Assets/Submoods",
            "Submoods",
            "Audio"
        ]
        
        for subdir in subdirs {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                return url
            }
            
            // Try sub-theme structure: Submoods/Waterfall/Waterfall_1.mp4
            let components = name.components(separatedBy: "_")
            if components.count > 1 {
                let potentialSubtheme = components[0]
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "\(subdir)/\(potentialSubtheme)") {
                    return url
                }
            }
        }
        
        // 3. Check in bundle root
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }
        
        // 3.5 Check if there is a zipped version
        let targetName = ext == nil ? name : "\(name).\(ext!)"
        let zipSubdirs = subdirs + [""]
        for subdir in zipSubdirs {
            let potentialZipURL: URL?
            if subdir.isEmpty {
                potentialZipURL = bundle.url(forResource: targetName, withExtension: "zip") ??
                                  bundle.url(forResource: name, withExtension: "zip")
            } else {
                potentialZipURL = bundle.url(forResource: targetName, withExtension: "zip", subdirectory: subdir) ??
                                  bundle.url(forResource: name, withExtension: "zip", subdirectory: subdir)
                
                if potentialZipURL == nil {
                    let components = name.components(separatedBy: "_")
                    if components.count > 1 {
                        let potentialSubtheme = components[0]
                        if let zurl = bundle.url(forResource: targetName, withExtension: "zip", subdirectory: "\(subdir)/\(potentialSubtheme)") {
                            if let extractedURL = extractZip(zurl, originalResource: targetName) {
                                return extractedURL
                            }
                        }
                    }
                }
            }
            
            if let zipURL = potentialZipURL {
                print("🟢 [MediaUtils] Found zip for \(targetName) at \(zipURL.path)")
                if let extractedURL = extractZip(zipURL, originalResource: targetName) {
                    print("🟢 [MediaUtils] Successfully extracted to \(extractedURL.path)")
                    return extractedURL
                } else {
                    print("🟥 [MediaUtils] Failed to extract \(targetName) from \(zipURL.path)")
                }
            }
        }
        
        // 4. Fallback: try with full resource name as forResource (sometimes works for full filenames)
        if let url = bundle.url(forResource: resource, withExtension: nil) {
            return url
        }

        if let resourceRoot = bundle.resourceURL {
            let candidate = resourceRoot.appendingPathComponent(resource)
            if FileManager.default.fileExists(atPath: candidate.path) {
                print("🟢 [MediaUtils] Found candidate at \(candidate.path)")
                return candidate
            }
            
            if let ext {
                let fileName = "\(name).\(ext)"
                let direct = resourceRoot.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: direct.path) {
                    print("🟢 [MediaUtils] Found direct at \(direct.path)")
                    return direct
                }
            }
            
            if let enumerator = FileManager.default.enumerator(at: resourceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                let targetName = ext == nil ? name : "\(name).\(ext!)"
                for case let fileURL as URL in enumerator {
                    if fileURL.lastPathComponent == targetName {
                        print("🟢 [MediaUtils] Found enumerator at \(fileURL.path)")
                        return fileURL
                    }
                }
            }
        }
        
        if isVideo {
            if let imageFallbackURL = resolveImageFallback(for: name) {
                print("🟢 [MediaUtils] Returning image fallback for missing video \(name)")
                return imageFallbackURL
            }
        } else {
            print("🟥 [MediaUtils] Warning - Could not resolve resource: \(resource)")
        }
        return nil
    }
    
    nonisolated static func extractZip(_ zipURL: URL, originalResource: String, destinationDir: URL? = nil) -> URL? {
        let fileManager = FileManager.default
        
        let targetDir: URL
        if let providedDir = destinationDir {
            targetDir = providedDir
        } else {
            let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
            targetDir = cachesDirectory.appendingPathComponent("AuraExtractedMedia")
        }
        
        if !fileManager.fileExists(atPath: targetDir.path) {
            try? fileManager.createDirectory(at: targetDir, withIntermediateDirectories: true)
        }
        
        let destinationURL = targetDir.appendingPathComponent(originalResource)
        
        // If already extracted, just return it
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        
        // Use Process to unzip
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", targetDir.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 && fileManager.fileExists(atPath: destinationURL.path) {
                print("🟢 [MediaUtils] Successfully extracted \(originalResource)")
                return destinationURL
            } else {
                print("🟥 [MediaUtils] Failed to extract \(originalResource). Status: \(process.terminationStatus)")
            }
        } catch {
            print("🟥 [MediaUtils] Error running unzip: \(error)")
        }
        
        return nil
    }

    nonisolated static func videoPosterImage(from url: URL) async -> NSImage? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // Grab frame at 2 seconds to avoid black start frames
        let time = CMTime(seconds: 2, preferredTimescale: 600)
        
        do {
            let (cgImage, _) = try await generator.image(at: time)
            print("🟢 [MediaUtils] Generated thumbnail for \(url.lastPathComponent)")
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("🟥 [MediaUtils] Failed to generate thumbnail for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
