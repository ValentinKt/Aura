import AppKit
import AVFoundation
import os

enum MediaUtils {
    @MainActor private static let imageCache = NSCache<NSURL, NSImage>()
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Aura", category: "MediaUtils")

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

    nonisolated static func resolveExactResourceURL(_ resource: String) -> URL? {
        resolveResourceURL(resource, allowVideoFallback: false)
    }

    nonisolated static func resolveResourceURL(_ resource: String) -> URL? {
        resolveResourceURL(resource, allowVideoFallback: true)
    }

    nonisolated private static func resolveResourceURL(_ resource: String, allowVideoFallback: Bool) -> URL? {
        if resource.hasPrefix("/") {
            let url = URL(fileURLWithPath: resource)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }

        let fileManager = FileManager.default
        let resourceURL = URL(fileURLWithPath: resource)
        let name = resourceURL.deletingPathExtension().lastPathComponent
        let ext = resourceURL.pathExtension.isEmpty ? nil : resourceURL.pathExtension
        let isVideo = ext?.lowercased() == "mov" || ext?.lowercased() == "mp4"

        if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let videosDirectory = appSupport.appendingPathComponent("Aura/Videos", isDirectory: true)

            if let localResourceURL = resolveDownloadedResourceURL(
                resource: resource,
                name: name,
                ext: ext,
                in: videosDirectory
            ) {
                print("🟢 [MediaUtils] Found downloaded resource at \(localResourceURL.path)")
                return localResourceURL
            }
        }

        let bundle = Bundle.main
        if allowVideoFallback, isVideo && !name.hasSuffix("_1") {
            if let imageFallbackURL = resolveImageFallback(for: name) {
                print("🟢 [MediaUtils] Returning image fallback for \(name)")
                return imageFallbackURL
            }
            return nil
        }

        let subdirs = [
            "Assets/Submoods",
            "Submoods",
            "Audio"
        ]

        for subdir in subdirs {
            if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: subdir) {
                return url
            }

            let components = name.components(separatedBy: "_")
            if components.count > 1 {
                let potentialSubtheme = components[0]
                if let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "\(subdir)/\(potentialSubtheme)") {
                    return url
                }
            }
        }

        if let url = bundle.url(forResource: name, withExtension: ext) {
            return url
        }

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
                for case let fileURL as URL in enumerator where fileURL.lastPathComponent == targetName {
                    print("🟢 [MediaUtils] Found enumerator at \(fileURL.path)")
                    return fileURL
                }
            }
        }

        if allowVideoFallback, isVideo {
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

        if let existingURL = extractedResourceURL(for: originalResource, in: targetDir) {
            return existingURL
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", targetDir.path]

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0,
               let extractedURL = extractedResourceURL(for: originalResource, in: targetDir) {
                print("🟢 [MediaUtils] Successfully extracted \(originalResource)")
                return extractedURL
            }

            print("🟥 [MediaUtils] Failed to extract \(originalResource). Status: \(process.terminationStatus)")
        } catch {
            print("🟥 [MediaUtils] Error running unzip: \(error)")
        }

        return nil
    }

    nonisolated private static func resolveDownloadedResourceURL(
        resource: String,
        name: String,
        ext: String?,
        in directory: URL
    ) -> URL? {
        let fileManager = FileManager.default
        let directURL = directory.appendingPathComponent(resource)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        if let extractedURL = extractedResourceURL(for: resource, in: directory) {
            return extractedURL
        }

        if let alternateExtension = alternateVideoExtension(for: ext) {
            let alternateResource = "\(name).\(alternateExtension)"
            let alternateURL = directory.appendingPathComponent(alternateResource)
            if fileManager.fileExists(atPath: alternateURL.path) {
                return alternateURL
            }

            if let extractedURL = extractedResourceURL(for: alternateResource, in: directory) {
                return extractedURL
            }
        }

        return nil
    }

    nonisolated private static func extractedResourceURL(for resource: String, in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let directURL = directory.appendingPathComponent(resource)
        if fileManager.fileExists(atPath: directURL.path) {
            return directURL
        }

        let expectedName = URL(fileURLWithPath: resource).lastPathComponent.lowercased()
        if let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let candidateURL as URL in enumerator
                where candidateURL.lastPathComponent.lowercased() == expectedName {
                return candidateURL
            }
        }

        let originalURL = URL(fileURLWithPath: resource)
        let name = originalURL.deletingPathExtension().lastPathComponent
        let ext = originalURL.pathExtension.isEmpty ? nil : originalURL.pathExtension

        if let alternateExtension = alternateVideoExtension(for: ext) {
            let alternateName = "\(name).\(alternateExtension)".lowercased()

            if let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let candidateURL as URL in enumerator
                    where candidateURL.lastPathComponent.lowercased() == alternateName {
                    return candidateURL
                }
            }
        }

        return nil
    }

    nonisolated private static func alternateVideoExtension(for ext: String?) -> String? {
        switch ext?.lowercased() {
        case "mov":
            return "mp4"
        case "mp4":
            return "mov"
        default:
            return nil
        }
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

    nonisolated static func loadImage(from url: URL) async -> NSImage? {
        let cacheKey = url as NSURL

        if let cachedImage = await MainActor.run(body: { imageCache.object(forKey: cacheKey) }) {
            return cachedImage
        }

        let data: Data? = await Task.detached(priority: .userInitiated) { () -> Data? in
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return try? Data(contentsOf: url)
        }.value

        guard let data else { return nil }

        let image = await MainActor.run { NSImage(data: data) }

        if let image {
            await MainActor.run { imageCache.setObject(image, forKey: cacheKey) }
        }

        return image
    }
}
