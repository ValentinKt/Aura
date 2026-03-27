import AppKit
import CoreImage
import CoreML
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

    private let visionModel: VNCoreMLModel
    private let ciContext: CIContext
    private let cropAndScaleOption: VNImageCropAndScaleOption
    private let modelInputSize: CGSize
    private let modelOutputSize: CGSize

    init(
        modelName: String = "SuperResolution",
        bundle: Bundle = .main,
        configuration: MLModelConfiguration = ImageUpscaler.defaultModelConfiguration(),
        cropAndScaleOption: VNImageCropAndScaleOption = .scaleFill
    ) throws {
        guard let modelURL = bundle.url(forResource: modelName, withExtension: "mlmodelc") else {
            throw UpscalingError.modelNotFound(name: modelName)
        }

        let mlModel = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.visionModel = try VNCoreMLModel(for: mlModel)
        self.ciContext = CIContext()
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
    }

    func upscale(_ image: NSImage) async throws -> NSImage {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UpscalingError.imageConversionFailed
        }

        return try await upscale(cgImage)
    }

    func upscale(_ image: CGImage) async throws -> NSImage {
        try Task.checkCancellation()

        let upscaledImage: CGImage

        if usesSinglePassInference(for: image) {
            upscaledImage = try performRequest(on: image)
        } else if supportsTiledInference(for: image) {
            upscaledImage = try await performTiledInference(on: image)
        } else {
            throw UpscalingError.unsupportedImageDimensions(
                width: image.width,
                height: image.height,
                tileWidth: Int(modelInputSize.width),
                tileHeight: Int(modelInputSize.height)
            )
        }

        try Task.checkCancellation()
        return NSImage(cgImage: upscaledImage, size: NSSize(width: upscaledImage.width, height: upscaledImage.height))
    }

    private func usesSinglePassInference(for image: CGImage) -> Bool {
        image.width == Int(modelInputSize.width) && image.height == Int(modelInputSize.height)
    }

    private func supportsTiledInference(for image: CGImage) -> Bool {
        image.width % Int(modelInputSize.width) == 0 &&
        image.height % Int(modelInputSize.height) == 0 &&
        (image.width > Int(modelInputSize.width) || image.height > Int(modelInputSize.height))
    }

    private func performRequest(on image: CGImage) throws -> CGImage {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = cropAndScaleOption

        let handler = VNImageRequestHandler(cgImage: image)

        do {
            try handler.perform([request])
            return try makeCGImage(from: request.results)
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

                    let tileImage = inputImage.cropped(to: cropRect)

                    guard let tileCGImage = ciContext.createCGImage(tileImage, from: tileImage.extent) else {
                        throw UpscalingError.imageConversionFailed
                    }

                    let upscaledTile = try performRequest(on: tileCGImage)
                    let translatedTile = CIImage(cgImage: upscaledTile).transformed(
                        by: CGAffineTransform(
                            translationX: CGFloat(column * outputTileWidth),
                            y: CGFloat(row * outputTileHeight)
                        )
                    )

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
        guard let results else {
            throw UpscalingError.unsupportedModelOutput
        }

        if let observation = results.compactMap({ $0 as? VNPixelBufferObservation }).first {
            return try makeCGImage(from: observation.pixelBuffer)
        }

        if let observation = results.compactMap({ $0 as? VNCoreMLFeatureValueObservation }).first,
           let pixelBuffer = observation.featureValue.imageBufferValue {
            return try makeCGImage(from: pixelBuffer)
        }

        throw UpscalingError.unsupportedModelOutput
    }

    private func makeCGImage(from pixelBuffer: CVPixelBuffer) throws -> CGImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent.integral

        guard let cgImage = ciContext.createCGImage(ciImage, from: extent) else {
            throw UpscalingError.imageConversionFailed
        }

        return cgImage
    }

    private static func defaultModelConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }
}
