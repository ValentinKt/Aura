import AppKit
import AVFoundation
import ImageIO
import os

enum MediaUtils {
    nonisolated(unsafe) static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 200 // Increased from 50 to 200 to prevent cache thrashing during scroll
        cache.totalCostLimit = 1024 * 1024 * 200 // Increased to 200 MB max
        return cache
    }()

    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Aura", category: "MediaUtils")

    nonisolated static let thumbnailMaxPixelSize: CGFloat = 600

    nonisolated static func resolveImageFallback(for name: String) -> URL? {
        #if DEBUG
        // Try the local absolute path first for development
        let absolutePath = "/Users/valentin/XCode/Aura/Aura/Resources/Image/\(name).jpg"
        if FileManager.default.fileExists(atPath: absolutePath) {
            return URL(fileURLWithPath: absolutePath)
        }
        #endif

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

    // Cache for resolved URLs to avoid expensive bundle enumeration
    nonisolated(unsafe) private static let resolvedURLCache: NSCache<NSString, NSURL> = {
        let cache = NSCache<NSString, NSURL>()
        cache.countLimit = 200
        return cache
    }()

    nonisolated static func resolveResourceURL(_ resource: String) -> URL? {
        resolveResourceURL(resource, allowVideoFallback: true)
    }

    nonisolated private static let notFoundSentinel = NSURL(fileURLWithPath: "/dev/null")

    nonisolated static func clearCache(for resource: String) {
        resolvedURLCache.removeObject(forKey: "\(resource)_true" as NSString)
        resolvedURLCache.removeObject(forKey: "\(resource)_false" as NSString)
    }

    nonisolated static func purgeCaches() {
        imageCache.removeAllObjects()
        resolvedURLCache.removeAllObjects()
    }

    nonisolated static func resolveResourceURL(_ resource: String, allowVideoFallback: Bool) -> URL? {
        let cacheKey = "\(resource)_\(allowVideoFallback)" as NSString
        if let cached = resolvedURLCache.object(forKey: cacheKey) {
            if cached === notFoundSentinel {
                return nil
            }
            return cached as URL
        }

        let url = performResolveResourceURL(resource, allowVideoFallback: allowVideoFallback)
        if let url = url {
            resolvedURLCache.setObject(url as NSURL, forKey: cacheKey)
        } else {
            resolvedURLCache.setObject(notFoundSentinel, forKey: cacheKey)
        }
        return url
    }

    nonisolated private static func performResolveResourceURL(_ resource: String, allowVideoFallback: Bool) -> URL? {
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
                log.debug("Found downloaded resource at \(localResourceURL.path, privacy: .public)")
                return localResourceURL
            }

            let customDirectory = appSupport.appendingPathComponent("Aura/CustomWallpapers", isDirectory: true)
            if let customResourceURL = resolveDownloadedResourceURL(
                resource: resource,
                name: name,
                ext: ext,
                in: customDirectory
            ) {
                log.debug("Found custom resource at \(customResourceURL.path, privacy: .public)")
                return customResourceURL
            }
        }

        let bundle = Bundle.main
        if allowVideoFallback, isVideo {
            if let imageFallbackURL = resolveImageFallback(for: name) {
                log.debug("Returning image fallback for \(name, privacy: .public)")
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
                log.debug("Found zip for \(targetName, privacy: .public) at \(zipURL.path, privacy: .public)")
                if let extractedURL = extractZip(zipURL, originalResource: targetName) {
                    log.notice("Successfully extracted to \(extractedURL.path, privacy: .public)")
                    return extractedURL
                } else {
                    log.error("Failed to extract \(targetName, privacy: .public) from \(zipURL.path, privacy: .public)")
                }
            }
        }

        if let url = bundle.url(forResource: resource, withExtension: nil) {
            return url
        }

        if let resourceRoot = bundle.resourceURL {
            let candidate = resourceRoot.appendingPathComponent(resource)
            if FileManager.default.fileExists(atPath: candidate.path) {
                log.debug("Found candidate at \(candidate.path, privacy: .public)")
                return candidate
            }

            if let ext {
                let fileName = "\(name).\(ext)"
                let direct = resourceRoot.appendingPathComponent(fileName)
                if FileManager.default.fileExists(atPath: direct.path) {
                    log.debug("Found direct resource at \(direct.path, privacy: .public)")
                    return direct
                }
            }

            if let enumerator = FileManager.default.enumerator(at: resourceRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) {
                let targetName = ext == nil ? name : "\(name).\(ext!)"
                for case let fileURL as URL in enumerator where fileURL.lastPathComponent == targetName {
                    log.debug("Found enumerated resource at \(fileURL.path, privacy: .public)")
                    return fileURL
                }
            }
        }

        if allowVideoFallback, isVideo {
            if let imageFallbackURL = resolveImageFallback(for: name) {
                log.debug("Returning image fallback for missing video \(name, privacy: .public)")
                return imageFallbackURL
            }
        } else {
            log.error("Could not resolve resource \(resource, privacy: .public)")
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
                log.notice("Successfully extracted \(originalResource, privacy: .public)")
                return extractedURL
            }

            log.error("Failed to extract \(originalResource, privacy: .public). Status: \(process.terminationStatus)")
        } catch {
            log.error("Error running unzip: \(String(describing: error), privacy: .public)")
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
        let cacheKey = url as NSURL

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }

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
            log.debug("Generated thumbnail for \(url.lastPathComponent, privacy: .public)")
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            imageCache.setObject(image, forKey: cacheKey)
            return image
        } catch {
            log.error("Failed to generate thumbnail for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    nonisolated static func thumbnailImage(for resource: String, maxPixelSize: CGFloat = thumbnailMaxPixelSize) async -> NSImage? {
        if Task.isCancelled { return nil }
        
        if let url = resolveResourceURL(resource),
           let image = await thumbnailImage(from: url, maxPixelSize: maxPixelSize) {
            return image
        }

        if Task.isCancelled { return nil }

        let baseName = (resource as NSString).deletingPathExtension
        if let image = await MainActor.run(body: {
            renderedThumbnail(named: baseName, maxPixelSize: maxPixelSize)
                ?? renderedThumbnail(named: resource, maxPixelSize: maxPixelSize)
        }) {
            return image
        }

        return nil
    }

    nonisolated static func thumbnailImage(from url: URL, maxPixelSize: CGFloat = thumbnailMaxPixelSize) async -> NSImage? {
        if Task.isCancelled { return nil }
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "size", value: "\(maxPixelSize)")]
        let cacheKey = (components?.url ?? url) as NSURL

        if let cachedImage = imageCache.object(forKey: cacheKey) {
            return cachedImage
        }
        
        if Task.isCancelled { return nil }

        let ext = url.pathExtension.lowercased()
        if ["mp4", "mov", "m4v"].contains(ext) {
            if let image = await downsampledVideoPosterImage(from: url, maxPixelSize: maxPixelSize) {
                if Task.isCancelled { return nil }
                imageCache.setObject(image, forKey: cacheKey)
                return image
            }
            return nil
        }

        let task = Task.detached(priority: .utility) { () -> NSImage? in
            if Task.isCancelled { return nil }
            return autoreleasepool {
                downsampledImage(from: url, maxPixelSize: maxPixelSize)
            }
        }

        let result = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        if Task.isCancelled { return nil }

        if let image = result {
            imageCache.setObject(image, forKey: cacheKey)
        }
        return result
    }

    nonisolated static func loadImage(from url: URL) async -> NSImage? {
        let cacheKey = url as NSURL

        if let cachedImage = await MainActor.run(body: { imageCache.object(forKey: cacheKey) }) {
            return cachedImage
        }

        let image: NSImage? = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            return autoreleasepool {
                NSImage(contentsOf: url)
            }
        }.value

        if let image {
            await MainActor.run { imageCache.setObject(image, forKey: cacheKey) }
        }

        return image
    }

    nonisolated private static func downsampledVideoPosterImage(from url: URL, maxPixelSize: CGFloat) async -> NSImage? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let time = CMTime(seconds: 2, preferredTimescale: 600)

        return await withTaskCancellationHandler {
            do {
                let (cgImage, _) = try await generator.image(at: time)
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } catch {
                if !Task.isCancelled {
                    log.error("Failed to generate thumbnail for \(url.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                }
                return nil
            }
        } onCancel: {
            generator.cancelAllCGImageGeneration()
        }
    }

    nonisolated private static func downsampledImage(from url: URL, maxPixelSize: CGFloat) -> NSImage? {
        let isSecurityScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isSecurityScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let options: CFDictionary = [
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return nil
        }

        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, Int(maxPixelSize)),
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, downsampleOptions) else {
            return nil
        }

        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    @MainActor
    private static func renderedThumbnail(named name: String, maxPixelSize: CGFloat) -> NSImage? {
        guard let image = NSImage(named: name) else { return nil }

        let originalSize = image.size
        guard originalSize.width > 0, originalSize.height > 0 else { return image }

        let longestEdge = max(originalSize.width, originalSize.height)
        let scale = min(1, maxPixelSize / longestEdge)
        let targetSize = NSSize(width: max(1, originalSize.width * scale), height: max(1, originalSize.height * scale))
        let thumbnail = NSImage(size: targetSize)

        thumbnail.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: originalSize), operation: .copy, fraction: 1)
        thumbnail.unlockFocus()

        return thumbnail
    }
}
