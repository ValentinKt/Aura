import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import AppKit

final class DynamicDesktopGenerator: Sendable {
    enum GeneratorError: LocalizedError, Sendable {
        case destinationCreationFailed
        case cgImageCreationFailed
        case imageProcessingFailed
        
        var errorDescription: String? {
            switch self {
            case .destinationCreationFailed: return "Failed to create HEIC destination."
            case .cgImageCreationFailed: return "Failed to render Core Image to CGImage."
            case .imageProcessingFailed: return "Image filter processing failed."
            }
        }
    }
    
    private let ciContext: CIContext
    
    init() {
        self.ciContext = CIContext(options: [.cacheIntermediates: false])
    }
    
    func generate(from baseImage: NSImage, outputURL: URL, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        guard let cgMasterImage = baseImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw GeneratorError.cgImageCreationFailed
        }
        
        let ciMasterImage = CIImage(cgImage: cgMasterImage)
        let totalFrames = 48
        
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.heic.identifier as CFString, totalFrames, nil) else {
            throw GeneratorError.destinationCreationFailed
        }
        
        let metadata = CGImageMetadataCreateMutable()
        let nsAppleDesktop = "http://ns.apple.com/namespace/1.0/" as CFString
        let prefix = "apple_desktop" as CFString
        CGImageMetadataRegisterNamespaceForPrefix(metadata, nsAppleDesktop, prefix, nil)
        
        let plistDict = generateTimePlist(frames: totalFrames)
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
        let base64Plist = plistData.base64EncodedString()
        
        CGImageMetadataSetValueWithPath(metadata, nil, "apple_desktop:aprp" as CFString, base64Plist as CFString)
        
        for i in 0..<totalFrames {
            try Task.checkCancellation()
            
            let timeFraction = Double(i) / Double(totalFrames)
            let frameCGImage = try await generateFrame(from: ciMasterImage, timeFraction: timeFraction)
            
            let options: [String: Any] = [
                kCGImageDestinationLossyCompressionQuality as String: 0.85
            ]
            
            if i == 0 {
                CGImageDestinationAddImageAndMetadata(destination, frameCGImage, metadata, options as CFDictionary)
            } else {
                CGImageDestinationAddImage(destination, frameCGImage, options as CFDictionary)
            }
            
            progress(Double(i + 1) / Double(totalFrames))
        }
        
        if !CGImageDestinationFinalize(destination) {
            throw GeneratorError.destinationCreationFailed
        }
    }
    
    private func generateFrame(from masterImage: CIImage, timeFraction: Double) async throws -> CGImage {
        let context = self.ciContext
        return try await Task.detached(priority: .userInitiated) {
            try autoreleasepool { () throws -> CGImage in
                let amplitude = (0.5 - (-2.0)) / 2.0
                let offset = (-2.0 + 0.5) / 2.0
                let exposure = offset - amplitude * cos(timeFraction * 2.0 * .pi)
                let saturation = 0.75 - 0.25 * cos(timeFraction * 2.0 * .pi)
                let contrast = 1.1 + 0.1 * cos(timeFraction * 2.0 * .pi)
                
                let temperature: Double
                if timeFraction < 0.25 {
                    temperature = 4000 + (8000 - 4000) * (timeFraction / 0.25)
                } else if timeFraction < 0.5 {
                    temperature = 8000 - (8000 - 6500) * ((timeFraction - 0.25) / 0.25)
                } else if timeFraction < 0.75 {
                    temperature = 6500 + (8000 - 6500) * ((timeFraction - 0.5) / 0.25)
                } else {
                    temperature = 8000 - (8000 - 4000) * ((timeFraction - 0.75) / 0.25)
                }
                
                guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { throw GeneratorError.imageProcessingFailed }
                exposureFilter.setValue(masterImage, forKey: kCIInputImageKey)
                exposureFilter.setValue(exposure, forKey: kCIInputEVKey)
                guard let output1 = exposureFilter.outputImage else { throw GeneratorError.imageProcessingFailed }
                
                guard let tempFilter = CIFilter(name: "CITemperatureAndTint") else { throw GeneratorError.imageProcessingFailed }
                tempFilter.setValue(output1, forKey: kCIInputImageKey)
                tempFilter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                tempFilter.setValue(CIVector(x: temperature, y: 0), forKey: "inputTargetNeutral")
                guard let output2 = tempFilter.outputImage else { throw GeneratorError.imageProcessingFailed }
                
                guard let colorFilter = CIFilter(name: "CIColorControls") else { throw GeneratorError.imageProcessingFailed }
                colorFilter.setValue(output2, forKey: kCIInputImageKey)
                colorFilter.setValue(saturation, forKey: kCIInputSaturationKey)
                colorFilter.setValue(contrast, forKey: kCIInputContrastKey)
                guard let finalOutput = colorFilter.outputImage else { throw GeneratorError.imageProcessingFailed }
                
                let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
                guard let cgImage = context.createCGImage(finalOutput, from: finalOutput.extent, format: .RGBA8, colorSpace: colorSpace) else {
                    throw GeneratorError.cgImageCreationFailed
                }
                
                return cgImage
            }
        }.value
    }
    
    private func generateTimePlist(frames: Int) -> [String: Any] {
        var tiArray: [[String: Any]] = []
        for i in 0..<frames {
            tiArray.append([
                "i": i,
                "t": Double(i) / Double(frames)
            ])
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
