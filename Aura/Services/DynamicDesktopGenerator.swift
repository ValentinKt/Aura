import AppKit
import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class DynamicDesktopGenerator {
    private static let outputFrameCount = 24
    private static let maximumRetinaLongEdge: CGFloat = 3_840
    private static let intermediateJPEGCompressionQuality = 0.82
    private static let heicCompressionQuality = 0.76

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

    enum ProgressStep: Sendable {
        case preparing
        case generatingFrame(index: Int, total: Int)
        case upscalingFrame(index: Int, total: Int)
        case encodingFrame(index: Int, total: Int)
        case finalizing
    }

    struct ProgressUpdate: Sendable {
        let fractionCompleted: Double
        let step: ProgressStep

        var statusMessage: String {
            switch step {
            case .preparing:
                return "Preparing Dynamic Desktop frames…"
            case .generatingFrame(let index, let total):
                return "Generating frame \(index) of \(total)…"
            case .upscalingFrame(let index, let total):
                return "Upscaling frame \(index) of \(total)…"
            case .encodingFrame(let index, let total):
                return "Compressing frame \(index) of \(total) for the HEIC…"
            case .finalizing:
                return "Finalizing the \(DynamicDesktopGenerator.outputFrameCount)-image HEIC…"
            }
        }
    }

    private let upscaler: ImageUpscaler
    private let ciContext: CIContext
    private let totalFrames = DynamicDesktopGenerator.outputFrameCount

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

    func generate(from sourceURL: URL, outputURL: URL, progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }) async throws {
        let sourceImage = try await loadImage(from: sourceURL)
        try await generate(from: sourceImage, outputURL: outputURL, progress: progress)
    }

    func generate(from sourceImage: NSImage, outputURL: URL, progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }) async throws {
        progress(ProgressUpdate(fractionCompleted: 0, step: .preparing))

        guard let cgSourceImage = sourceImage.cgImage(forProposedRect: nil, context: nil, hints: [NSImageRep.HintKey: Any]()) else {
            throw GeneratorError.cgImageCreationFailed
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let ciSourceImage = CIImage(cgImage: cgSourceImage, options: [.colorSpace: colorSpace])

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.heic.identifier as CFString, totalFrames, nil) else {
            throw GeneratorError.destinationCreationFailed
        }

        defer {
            ciContext.clearCaches()
        }

        let metadata = try makeMetadata(totalFrames: totalFrames)
        let destinationOptions: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: Self.heicCompressionQuality,
            kCGImagePropertyColorModel as String: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName as String: "Display P3"
        ]
        let totalUnits = (totalFrames * 3) + 1
        var completedUnits = 0

        func progressFraction(for completedUnits: Int) -> Double {
            Double(completedUnits) / Double(totalUnits)
        }

        for i in 0..<totalFrames {
            try Task.checkCancellation()
            let frameNumber = i + 1

            progress(
                ProgressUpdate(
                    fractionCompleted: progressFraction(for: completedUnits),
                    step: .generatingFrame(index: frameNumber, total: totalFrames)
                )
            )

            let generatedFrame = try await generateFrame(
                from: ciSourceImage,
                frameIndex: i,
                totalFrames: totalFrames,
                colorSpace: colorSpace
            )
            completedUnits += 1

            progress(
                ProgressUpdate(
                    fractionCompleted: progressFraction(for: completedUnits),
                    step: .upscalingFrame(index: frameNumber, total: totalFrames)
                )
            )

            let upscaledFrame = try await upscaler.upscale(generatedFrame)

            guard let frameCGImage = upscaledFrame.cgImage(forProposedRect: nil, context: nil, hints: [NSImageRep.HintKey: Any]()) else {
                throw GeneratorError.cgImageCreationFailed
            }
            completedUnits += 1

            progress(
                ProgressUpdate(
                    fractionCompleted: progressFraction(for: completedUnits),
                    step: .encodingFrame(index: frameNumber, total: totalFrames)
                )
            )
            let optimizedFrame = try await optimizeFrameForStorage(frameCGImage, colorSpace: colorSpace)

            if i == 0 {
                CGImageDestinationAddImageAndMetadata(destination, optimizedFrame, metadata, destinationOptions as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, optimizedFrame, destinationOptions as CFDictionary)
            }
            completedUnits += 1
        }

        progress(
            ProgressUpdate(
                fractionCompleted: progressFraction(for: completedUnits),
                step: .finalizing
            )
        )

        if !CGImageDestinationFinalize(destination) {
            throw GeneratorError.destinationCreationFailed
        }

        progress(ProgressUpdate(fractionCompleted: 1, step: .finalizing))
    }

    private func optimizeFrameForStorage(_ image: CGImage, colorSpace: CGColorSpace) async throws -> CGImage {
        let context = self.ciContext
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool { () throws -> CGImage in
                let resizedImage = try Self.resizeForRetinaIfNeeded(image, colorSpace: colorSpace, context: context)
                return try Self.compressAsJPEG(resizedImage, colorSpace: colorSpace)
            }
        }.value
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

        // Time-based cycling metadata
        let timePlistData: Data
        do {
            timePlistData = try PropertyListSerialization.data(
                fromPropertyList: generateTimePlist(frames: totalFrames),
                format: .binary,
                options: 0
            )
        } catch {
            throw GeneratorError.metadataEncodingFailed
        }
        let encodedTimePlist = timePlistData.base64EncodedString()

        guard let timeTag = CGImageMetadataTagCreate(
            namespace,
            prefix,
            "aprp" as CFString,
            .string,
            encodedTimePlist as CFString
        ) else {
            throw GeneratorError.metadataInjectionFailed
        }

        // Solar-based cycling metadata (often required for better macOS integration)
        let solarPlistData: Data
        do {
            solarPlistData = try PropertyListSerialization.data(
                fromPropertyList: generateSolarPlist(frames: totalFrames),
                format: .binary,
                options: 0
            )
        } catch {
            throw GeneratorError.metadataEncodingFailed
        }
        let encodedSolarPlist = solarPlistData.base64EncodedString()

        guard let solarTag = CGImageMetadataTagCreate(
            namespace,
            prefix,
            "apls" as CFString,
            .string,
            encodedSolarPlist as CFString
        ) else {
            throw GeneratorError.metadataInjectionFailed
        }

        // Inject both tags
        guard CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:aprp" as CFString, timeTag),
              CGImageMetadataSetTagWithPath(metadata, nil, "apple_desktop:apls" as CFString, solarTag) else {
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

    private static func resizeForRetinaIfNeeded(
        _ image: CGImage,
        colorSpace: CGColorSpace,
        context: CIContext
    ) throws -> CGImage {
        let longEdge = max(image.width, image.height)
        guard CGFloat(longEdge) > maximumRetinaLongEdge else {
            return image
        }

        let scale = maximumRetinaLongEdge / CGFloat(longEdge)
        let ciImage = CIImage(cgImage: image, options: [.colorSpace: colorSpace])

        guard let scaleFilter = CIFilter(name: "CILanczosScaleTransform") else {
            throw GeneratorError.imageProcessingFailed
        }

        scaleFilter.setValue(ciImage, forKey: kCIInputImageKey)
        scaleFilter.setValue(scale, forKey: kCIInputScaleKey)
        scaleFilter.setValue(1.0, forKey: kCIInputAspectRatioKey)

        guard let outputImage = scaleFilter.outputImage,
              let resizedImage = context.createCGImage(outputImage, from: outputImage.extent.integral, format: .RGBA8, colorSpace: colorSpace) else {
            throw GeneratorError.cgImageCreationFailed
        }

        return resizedImage
    }

    private static func compressAsJPEG(_ image: CGImage, colorSpace: CGColorSpace) throws -> CGImage {
        let jpegData = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(jpegData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw GeneratorError.destinationCreationFailed
        }

        let destinationOptions: [String: Any] = [
            kCGImageDestinationLossyCompressionQuality as String: intermediateJPEGCompressionQuality,
            kCGImagePropertyColorModel as String: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName as String: "Display P3"
        ]

        CGImageDestinationAddImage(destination, image, destinationOptions as CFDictionary)

        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(jpegData, nil),
              let compressedImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: false,
                kCGImageSourceShouldAllowFloat: false
              ] as CFDictionary) else {
            throw GeneratorError.destinationCreationFailed
        }

        return compressedImage.copy(colorSpace: colorSpace) ?? compressedImage
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

    private func generateSolarPlist(frames: Int) -> [String: Any] {
        // Solar-based metadata uses altitude and azimuth
        // We simulate a 24h cycle
        let siArray = (0..<frames).map { frameIndex in
            let progress = Double(frameIndex) / Double(frames)
            let altitude = 90.0 * sin((progress * 2.0 * .pi) - (.pi / 2.0))
            let azimuth = progress * 360.0

            return [
                "i": frameIndex,
                "a": altitude,
                "z": azimuth
            ]
        }

        return [
            "ap": [
                "d": 0,
                "l": frames / 2
            ],
            "si": siArray
        ]
    }
}
