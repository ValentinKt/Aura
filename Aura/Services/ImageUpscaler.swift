import AppKit
import CoreImage
import CoreML
import CoreVideo
import Metal
import Vision

actor ImageUpscaler {
    enum UpscalingError: LocalizedError, Sendable {
        case modelNotFound(name: String)
        case imageConversionFailed
        case unsupportedModelOutput
        case unsupportedImageDimensions(width: Int, height: Int, tileWidth: Int, tileHeight: Int)
        case requestFailed(description: String)

        var errorDescription: String? {
            switch self {
            case .modelNotFound(let name):
                return "The Core ML model \(name) could not be found in the app bundle."
            case .imageConversionFailed:
                return "The source image could not be converted into a format supported by Vision."
            case .unsupportedModelOutput:
                return "The super-resolution model did not return an image output."
            case .unsupportedImageDimensions(let width, let height, let tileWidth, let tileHeight):
                return "The selected image size \(width)×\(height) is not supported by the bundled super-resolution model. Aura expects \(tileWidth)×\(tileHeight) tiles or images composed from that tile size."
            case .requestFailed(let description):
                return "Image upscaling failed: \(description)"
            }
        }
    }

    private let visionModel: VNCoreMLModel?
    private let mtlDevice: MTLDevice?
    private let textureCache: CVMetalTextureCache?
    private let ciContext: CIContext
    private let inputPixelBufferPool: CVPixelBufferPool?
    private let cropAndScaleOption: VNImageCropAndScaleOption
    private let modelInputSize: CGSize
    private let modelOutputSize: CGSize

    init(
        modelURL: URL,
        configuration: MLModelConfiguration = ImageUpscaler.defaultModelConfiguration(),
        cropAndScaleOption: VNImageCropAndScaleOption = .scaleFill
    ) throws {
        let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.visionModel = try VNCoreMLModel(for: mlModel)
        self.mtlDevice = MTLCreateSystemDefaultDevice()
        if let device = mtlDevice {
            var cache: CVMetalTextureCache?
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
            self.textureCache = cache
        } else {
            self.textureCache = nil
        }
        if let device = mtlDevice {
            self.ciContext = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
        } else {
            self.ciContext = CIContext(options: [.cacheIntermediates: false])
        }
        self.cropAndScaleOption = cropAndScaleOption

        guard
            let inputDescription = mlModel.modelDescription.inputDescriptionsByName.values.first(where: { $0.type == .image }),
            let inputConstraint = inputDescription.imageConstraint,
            let outputDescription = mlModel.modelDescription.outputDescriptionsByName.values.first(where: { $0.type == .image }),
            let outputConstraint = outputDescription.imageConstraint
        else {
            throw UpscalingError.unsupportedModelOutput
        }

        self.modelInputSize = CGSize(width: inputConstraint.pixelsWide, height: inputConstraint.pixelsHigh)
        self.modelOutputSize = CGSize(width: outputConstraint.pixelsWide, height: outputConstraint.pixelsHigh)
        self.inputPixelBufferPool = ImageUpscaler.makePixelBufferPool(
            width: inputConstraint.pixelsWide,
            height: inputConstraint.pixelsHigh
        )
    }

    private init(dummy: Bool) {
        self.visionModel = nil
        self.mtlDevice = nil
        self.textureCache = nil
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
        self.inputPixelBufferPool = nil
        self.cropAndScaleOption = .scaleFill
        self.modelInputSize = CGSize(width: 512, height: 512)
        self.modelOutputSize = CGSize(width: 512, height: 512)
    }

    func upscale(_ image: NSImage) async throws -> NSImage {
        guard visionModel != nil else {
            return image
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UpscalingError.imageConversionFailed
        }

        let upscaledImage = try await upscaleCGImage(cgImage)
        return NSImage(cgImage: upscaledImage, size: NSSize(width: upscaledImage.width, height: upscaledImage.height))
    }

    func upscale(_ image: CGImage) async throws -> NSImage {
        let upscaledImage = try await upscaleCGImage(image)
        return NSImage(cgImage: upscaledImage, size: NSSize(width: upscaledImage.width, height: upscaledImage.height))
    }

    func upscalePixelBuffer(_ pixelBuffer: CVPixelBuffer) async throws -> CVPixelBuffer {
        guard let visionModel = visionModel else {
            return pixelBuffer
        }

        defer {
            ciContext.clearCaches()
        }

        try Task.checkCancellation()

        return try autoreleasepool { () throws -> CVPixelBuffer in
            let request = VNCoreMLRequest(model: visionModel)
            request.imageCropAndScaleOption = cropAndScaleOption

            // Use zero-copy GPU execution by avoiding CoreImage conversions
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            try handler.perform([request])

            guard let results = request.results else {
                throw UpscalingError.unsupportedModelOutput
            }

            if let observation = results.compactMap({ $0 as? VNPixelBufferObservation }).first {
                return observation.pixelBuffer
            }

            if let observation = results.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
               let outBuffer = observation.featureValue.imageBufferValue {
                return outBuffer
            }

            throw UpscalingError.unsupportedModelOutput
        }
    }

    func upscaleCGImage(_ image: CGImage) async throws -> CGImage {
        guard visionModel != nil else {
            return image
        }

        defer {
            ciContext.clearCaches()
        }

        try Task.checkCancellation()

        if usesSinglePassInference(for: image) {
            return try performRequest(on: image)
        }

        if supportsTiledInference(for: image) {
            return try await performTiledInference(on: image)
        }

        throw UpscalingError.unsupportedImageDimensions(
            width: image.width,
            height: image.height,
            tileWidth: Int(modelInputSize.width),
            tileHeight: Int(modelInputSize.height)
        )
    }

    private func usesSinglePassInference(for image: CGImage) -> Bool {
        image.width == Int(modelInputSize.width) && image.height == Int(modelInputSize.height)
    }

    private func supportsTiledInference(for image: CGImage) -> Bool {
        image.width % Int(modelInputSize.width) == 0 &&
        image.height % Int(modelInputSize.height) == 0 &&
        (image.width > Int(modelInputSize.width) || image.height > Int(modelInputSize.height))
    }

    private func makeIOSurfacePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes = Self.pixelBufferAttributes(width: width, height: height)
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            throw UpscalingError.imageConversionFailed
        }

        return buffer
    }

    private func makeInputPixelBuffer(from ciImage: CIImage) throws -> CVPixelBuffer {
        let extent = ciImage.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        let buffer = try makePooledPixelBuffer(width: width, height: height)

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        ciContext.render(ciImage, to: buffer, bounds: extent, colorSpace: CGColorSpaceCreateDeviceRGB())
        primeTextureCache(for: buffer)
        return buffer
    }

    private func performRequest(on image: CGImage) throws -> CGImage {
        guard let visionModel = visionModel else {
            return image
        }

        do {
            return try autoreleasepool { () throws -> CGImage in
                defer { ciContext.clearCaches() }

                let inputImage = CIImage(cgImage: image)
                let pixelBuffer = try makeInputPixelBuffer(from: inputImage)
                let outputImage = try performRequest(on: pixelBuffer, model: visionModel)
                return try makeCGImage(from: outputImage)
            }
        } catch let error as UpscalingError {
            throw error
        } catch {
            throw UpscalingError.requestFailed(description: error.localizedDescription)
        }
    }

    private func performTiledInference(on image: CGImage) async throws -> CGImage {
        let inputImage = CIImage(cgImage: image)
        let tileWidth = Int(modelInputSize.width)
        let tileHeight = Int(modelInputSize.height)
        let outputTileWidth = Int(modelOutputSize.width)
        let outputTileHeight = Int(modelOutputSize.height)
        let columns = image.width / tileWidth
        let rows = image.height / tileHeight
        let outputExtent = CGRect(
            x: 0,
            y: 0,
            width: columns * outputTileWidth,
            height: rows * outputTileHeight
        )
        var composedImage = CIImage(color: .clear).cropped(to: outputExtent)

        do {
            for row in 0..<rows {
                for column in 0..<columns {
                    try Task.checkCancellation()

                    let cropRect = CGRect(
                        x: column * tileWidth,
                        y: row * tileHeight,
                        width: tileWidth,
                        height: tileHeight
                    )

                    let translatedTile = try autoreleasepool { () throws -> CIImage in
                        let tileImage = inputImage.cropped(to: cropRect)
                        let pixelBuffer = try makeInputPixelBuffer(from: tileImage)
                        let upscaledTile = try performRequest(on: pixelBuffer)
                        return upscaledTile.transformed(
                            by: CGAffineTransform(
                                translationX: CGFloat(column * outputTileWidth),
                                y: CGFloat(row * outputTileHeight)
                            )
                        )
                    }

                    composedImage = translatedTile.composited(over: composedImage).cropped(to: outputExtent)
                }
            }

            guard let outputImage = ciContext.createCGImage(composedImage, from: outputExtent) else {
                throw UpscalingError.imageConversionFailed
            }

            return outputImage
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as UpscalingError {
            throw error
        } catch {
            throw UpscalingError.requestFailed(description: error.localizedDescription)
        }
    }

    private func makeCGImage(from results: [Any]?) throws -> CGImage {
        try makeCGImage(from: makeCIImage(from: results))
    }

    private func performRequest(on pixelBuffer: CVPixelBuffer) throws -> CIImage {
        guard let visionModel = visionModel else {
            throw UpscalingError.unsupportedModelOutput
        }

        return try performRequest(on: pixelBuffer, model: visionModel)
    }

    private func performRequest(on pixelBuffer: CVPixelBuffer, model visionModel: VNCoreMLModel) throws -> CIImage {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = cropAndScaleOption
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        try handler.perform([request])
        return try makeCIImage(from: request.results)
    }

    private func makeCIImage(from results: [Any]?) throws -> CIImage {
        guard let results else {
            throw UpscalingError.unsupportedModelOutput
        }

        if let observation = results.compactMap({ $0 as? VNPixelBufferObservation }).first {
            return CIImage(cvPixelBuffer: observation.pixelBuffer)
        }

        if let observation = results.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
           let pixelBuffer = observation.featureValue.imageBufferValue {
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        throw UpscalingError.unsupportedModelOutput
    }

    private func makeCGImage(from image: CIImage) throws -> CGImage {
        let extent = image.extent.integral

        guard let cgImage = ciContext.createCGImage(image, from: extent) else {
            throw UpscalingError.imageConversionFailed
        }

        return cgImage
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent.integral

        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw UpscalingError.imageConversionFailed
        }

        return cgImage
    }

    private func makePooledPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        if width == Int(modelInputSize.width),
           height == Int(modelInputSize.height),
           let pool = inputPixelBufferPool {
            var pixelBuffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            if status == kCVReturnSuccess, let pixelBuffer {
                return pixelBuffer
            }
        }

        return try makeIOSurfacePixelBuffer(width: width, height: height)
    }

    private func primeTextureCache(for pixelBuffer: CVPixelBuffer) {
        guard let textureCache, let device = mtlDevice else { return }

        let pixelFormat: MTLPixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_OneComponent8 ? .r8Unorm : .bgra8Unorm
        var texture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &texture
        )
        _ = device
        _ = texture
    }

    private static func pixelBufferAttributes(width: Int, height: Int) -> CFDictionary {
        [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary
    }

    private static func makePixelBufferPool(width: Int, height: Int) -> CVPixelBufferPool? {
        let poolAttributes: [String: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey as String: 3
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            pixelBufferAttributes(width: width, height: height),
            &pool
        )
        return pool
    }

    static func defaultModelConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }

    static func createDummy() -> ImageUpscaler {
        // This is a dummy upscaler that doesn't actually do anything, but fulfills the type requirement.
        // It's used when the super-resolution model is missing or cannot be loaded.
        return ImageUpscaler(dummy: true)
    }
}
