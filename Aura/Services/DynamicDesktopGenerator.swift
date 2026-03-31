import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class DynamicDesktopGenerator {
    enum GeneratorError: LocalizedError, Sendable {
        case sourceImageLoadingFailed
        case metadataEncodingFailed
        case metadataInjectionFailed
        case destinationCreationFailed
        case cgImageCreationFailed
        case imageProcessingFailed

        var errorDescription: String? {
            switch self {
            case .sourceImageLoadingFailed: return "Failed to load the source image."
            case .metadataEncodingFailed: return "Failed to encode Dynamic Desktop metadata."
            case .metadataInjectionFailed: return "Failed to inject Dynamic Desktop metadata."
            case .destinationCreationFailed: return "Failed to create HEIC destination."
            case .cgImageCreationFailed: return "Failed to render Core Image to CGImage."
            case .imageProcessingFailed: return "Image filter processing failed."
            }
        }
    }

    private let upscaler: ImageUpscaler
    private let ciContext: CIContext

    convenience init() throws {
        try self.init(upscaler: ImageUpscaler())
    }

    init(upscaler: ImageUpscaler) {
        self.upscaler = upscaler
        self.ciContext = CIContext(options: [
            .cacheIntermediates: false,
            .priorityRequestLow: false
        ])
    }

    func generate(from sourceURL: URL, outputURL: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let sourceImage = try await loadImage(from: sourceURL)
        try await generate(from: sourceImage, outputURL: outputURL, progress: progress)
    }

    func generate(from sourceImage: NSImage, outputURL: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        let masterImage = try await upscaler.upscale(sourceImage)

        guard let cgMasterImage = masterImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw GeneratorError.cgImageCreationFailed
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let ciMasterImage = CIImage(cgImage: cgMasterImage, options: [.colorSpace: colorSpace])
        let totalFrames = 48

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.heic.identifier as CFString, totalFrames, nil) else {
            throw GeneratorError.destinationCreationFailed
        }

        defer {
            ciContext.clearCaches()
        }

        let metadata = try makeMetadata(totalFrames: totalFrames)
        let destinationOptions: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: 0.88,
            kCGImagePropertyColorModel as String: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName as String: "Display P3"
        ]

        for i in 0..<totalFrames {
            try Task.checkCancellation()

            let frameCGImage = try await generateFrame(
                from: ciMasterImage,
                frameIndex: i,
                totalFrames: totalFrames,
                colorSpace: colorSpace
            )

            if i == 0 {
                CGImageDestinationAddImageAndMetadata(destination, frameCGImage, metadata, destinationOptions as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, frameCGImage, destinationOptions as CFDictionary)
            }

            progress(Double(i + 1) / Double(totalFrames))
        }

        if !CGImageDestinationFinalize(destination) {
            throw GeneratorError.destinationCreationFailed
        }
    }

    private func loadImage(from sourceURL: URL) async throws -> NSImage {
        let imageData = try await Task.detached(priority: .userInitiated) { () throws -> Data in
            let isSecurityScoped = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    sourceURL.stopAccessingSecurityScopedResource()
                }
            }

            return try Data(contentsOf: sourceURL)
        }.value

        guard let image = NSImage(data: imageData) else {
            throw GeneratorError.sourceImageLoadingFailed
        }

        return image
    }

    private func makeMetadata(totalFrames: Int) throws -> CGImageMetadata {
        let metadata = CGImageMetadataCreateMutable()
        let namespace = "http://ns.apple.com/namespace/1.0/" as CFString
        let prefix = "apple_desktop" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil)

        let plistData: Data
        do {
            plistData = try PropertyListSerialization.data(
                fromPropertyList: generateTimePlist(frames: totalFrames),
                format: .binary,
                options: 0
            )
        } catch {
            throw GeneratorError.metadataEncodingFailed
        }
        let encodedPlist = plistData.base64EncodedString()

        guard let tag = CGImageMetadataTagCreate(
            namespace,
            prefix,
            "aprp" as CFString,
            .string,
            encodedPlist as CFString
        ) else {
            throw GeneratorError.metadataInjectionFailed
        }

        guard CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:aprp" as CFString, tag) else {
            throw GeneratorError.metadataInjectionFailed
        }

        return metadata
    }

    private func generateFrame(
        from masterImage: CIImage,
        frameIndex: Int,
        totalFrames: Int,
        colorSpace: CGColorSpace
    ) async throws -> CGImage {
        let context = self.ciContext
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool { () throws -> CGImage in
                let timeFraction = Double(frameIndex) / Double(totalFrames)
                let cycle = timeFraction * 2.0 * .pi
                let exposure = -0.75 - 1.25 * cos(cycle)
                let daylight = max(0.0, sin(timeFraction * .pi))
                let sunriseWarmth = Self.gaussianPeak(at: timeFraction, center: 0.25, width: 0.09) +
                Self.gaussianPeak(at: timeFraction, center: 0.75, width: 0.09)
                let nightBlend = max(0.0, cos(cycle))
                let saturation = 1.0 - (nightBlend * 0.35)
                let contrast = 1.0 + (nightBlend * 0.18)
                let temperature = min(8000.0, max(3000.0, 3500.0 + (daylight * 3000.0) + (sunriseWarmth * 1500.0)))

                guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { throw GeneratorError.imageProcessingFailed }
                exposureFilter.setValue(masterImage, forKey: kCIInputImageKey)
                exposureFilter.setValue(exposure, forKey: kCIInputEVKey)
                guard let exposedImage = exposureFilter.outputImage else { throw GeneratorError.imageProcessingFailed }

                guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { throw GeneratorError.imageProcessingFailed }
                tempFilter.setValue(exposedImage, forKey: kCIInputImageKey)
                tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                tempFilter.setValue(CIVector(x: temperature, y: 0), forKey: "inputTargetNeutral")
                guard let temperatureAdjustedImage = tempFilter.outputImage else { throw GeneratorError.imageProcessingFailed }

                guard let colorFilter = CIFilter(name: "CIColorControls") else { throw GeneratorError.imageProcessingFailed }
                colorFilter.setValue(temperatureAdjustedImage, forKey: kCIInputImageKey)
                colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
                colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
                guard let finalOutput = colorFilter.outputImage else { throw GeneratorError.imageProcessingFailed }

                guard let cgImage = context.createCGImage(finalOutput, from: finalOutput.extent, format: .RGBA8, colorSpace: colorSpace) else {
                    throw GeneratorError.cgImageCreationFailed
                }

                return cgImage
            }
        }.value
    }

    nonisolated private static func gaussianPeak(at value: Double, center: Double, width: Double) -> Double {
        let distance = (value - center) / width
        return exp(-(distance * distance))
    }

    private func generateTimePlist(frames: Int) -> [String: Any] {
        let tiArray = (0..<frames).map { frameIndex in
            [
                "i": frameIndex,
                "t": Double(frameIndex) / Double(frames)
            ]
        }

        return [
            "ap": [
                "d": 0,
                "l": frames / 2
            ],
            "ti": tiArray
        ]
    }
}
