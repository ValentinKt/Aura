import AppKit
import CoreML
import Foundation
import StableDiffusion

actor StableDiffusionImageGenerator {
    struct ModelDownloadProgress: Sendable {
        let completedFileCount: Int
        let totalFileCount: Int
        let currentPath: String?

        var fractionCompleted: Double {
            guard totalFileCount > 0 else { return 1 }
            return Double(completedFileCount) / Double(totalFileCount)
        }

        var statusMessage: String {
            guard let currentPath else {
                return "\(completedFileCount)/\(totalFileCount) model files ready"
            }

            return "Downloading \(URL(fileURLWithPath: currentPath).lastPathComponent) (\(completedFileCount)/\(totalFileCount))"
        }
    }

    struct ImageGenerationProgress: Sendable {
        let step: Int
        let totalSteps: Int

        var fractionCompleted: Double {
            guard totalSteps > 0 else { return 0 }
            return Double(step) / Double(totalSteps)
        }

        var statusMessage: String {
            "Generating image… \(step)/\(totalSteps)"
        }
    }

    enum GeneratorError: LocalizedError, Sendable {
        case invalidResponse
        case manifestEmpty
        case modelNotDownloaded
        case generatedImageMissing
        case imageEncodingFailed

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The Stable Diffusion download returned an invalid response."
            case .manifestEmpty:
                return "Aura could not find any Stable Diffusion model files to download."
            case .modelNotDownloaded:
                return "Download the Stable Diffusion model before generating an image."
            case .generatedImageMissing:
                return "Stable Diffusion finished without producing an image."
            case .imageEncodingFailed:
                return "Aura couldn’t save the generated AI image preview."
            }
        }
    }

    private struct RemoteEntry: Decodable, Sendable {
        let type: String
        let size: Int?
        let path: String
    }

    private static let repository = "apple/coreml-stable-diffusion-2-1-base"
    private static let remoteCompiledPath = "original/compiled"
    private static let requiredRelativePaths = [
        "TextEncoder.mlmodelc",
        "Unet.mlmodelc",
        "UnetChunk1.mlmodelc",
        "UnetChunk2.mlmodelc",
        "VAEDecoder.mlmodelc",
        "VAEEncoder.mlmodelc",
        "merges.txt",
        "vocab.json"
    ]

    private let session: URLSession
    private let fileManager = FileManager.default
    private let modelDirectory: URL
    private let previewDirectory: URL
    private let modelConfiguration: MLModelConfiguration
    private var pipeline: StableDiffusionPipeline?

    init(session: URLSession = .shared) {
        self.session = session
        self.modelDirectory = CustomAssetManager.appSupportDirectory
            .appendingPathComponent("AIModels", isDirectory: true)
            .appendingPathComponent("StableDiffusion-2-1-Base", isDirectory: true)
        self.previewDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("AuraAIPreviews", isDirectory: true)
        self.modelConfiguration = Self.makeModelConfiguration()
    }

    func isModelDownloaded() -> Bool {
        Self.requiredRelativePaths.allSatisfy {
            fileManager.fileExists(atPath: modelDirectory.appendingPathComponent($0).path)
        }
    }

    func ensureModelDownloaded(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void = { _ in }
    ) async throws {
        let remoteFiles = try await fetchRemoteFiles(at: Self.remoteCompiledPath)
        guard !remoteFiles.isEmpty else {
            throw GeneratorError.manifestEmpty
        }

        try createDirectoryIfNeeded(at: modelDirectory)
        progress(ModelDownloadProgress(completedFileCount: 0, totalFileCount: remoteFiles.count, currentPath: nil))

        var completedFileCount = 0

        for file in remoteFiles {
            try Task.checkCancellation()

            let relativePath = relativePath(for: file.path)
            let destinationURL = modelDirectory.appendingPathComponent(relativePath)
            let parentDirectory = destinationURL.deletingLastPathComponent()

            try createDirectoryIfNeeded(at: parentDirectory)

            if let expectedSize = file.size,
               let existingSize = fileSize(at: destinationURL),
               existingSize == Int64(expectedSize) {
                completedFileCount += 1
                progress(ModelDownloadProgress(
                    completedFileCount: completedFileCount,
                    totalFileCount: remoteFiles.count,
                    currentPath: file.path
                ))
                continue
            }

            let requestURL = resolveURL(for: file.path)
            let (temporaryURL, response) = try await session.download(from: requestURL)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                throw GeneratorError.invalidResponse
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            completedFileCount += 1
            progress(ModelDownloadProgress(
                completedFileCount: completedFileCount,
                totalFileCount: remoteFiles.count,
                currentPath: file.path
            ))
        }
    }

    func generateImage(
        prompt: String,
        negativePrompt: String = "",
        stepCount: Int = 30,
        progress: @escaping @Sendable (ImageGenerationProgress) -> Void = { _ in }
    ) throws -> URL {
        guard isModelDownloaded() else {
            throw GeneratorError.modelNotDownloaded
        }

        let pipeline = try makePipelineIfNeeded()
        let resolvedStepCount = max(1, stepCount)
        progress(ImageGenerationProgress(step: 0, totalSteps: resolvedStepCount))

        try pipeline.loadResources()
        defer {
            pipeline.unloadResources()
        }

        var configuration = StableDiffusionPipeline.Configuration(prompt: prompt)
        configuration.negativePrompt = negativePrompt
        configuration.imageCount = 1
        configuration.stepCount = resolvedStepCount
        configuration.seed = UInt32.random(in: .min ... .max)
        configuration.guidanceScale = 7.5

        let generatedImages = try pipeline.generateImages(configuration: configuration) { update in
            let currentStep = min(update.step + 1, update.stepCount)
            progress(ImageGenerationProgress(step: currentStep, totalSteps: update.stepCount))
            return !Task.isCancelled
        }

        guard let generatedImage = generatedImages.compactMap({ $0 }).first else {
            throw GeneratorError.generatedImageMissing
        }

        return try savePreviewImage(generatedImage, prompt: prompt)
    }

    func unloadResources() {
        pipeline?.unloadResources()
        pipeline = nil
    }

    func removeGeneratedPreview(at url: URL?) {
        guard let url else { return }
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    private func makePipelineIfNeeded() throws -> StableDiffusionPipeline {
        if let pipeline {
            return pipeline
        }

        let pipeline = try StableDiffusionPipeline(
            resourcesAt: modelDirectory,
            controlNet: [],
            configuration: modelConfiguration,
            disableSafety: false,
            reduceMemory: true
        )
        self.pipeline = pipeline
        return pipeline
    }

    private func fetchRemoteFiles(at remotePath: String) async throws -> [RemoteEntry] {
        let entries = try await fetchRemoteEntries(at: remotePath)
        var files: [RemoteEntry] = []

        for entry in entries {
            if entry.type == "directory" {
                let nestedFiles = try await fetchRemoteFiles(at: entry.path)
                files.append(contentsOf: nestedFiles)
            } else if entry.type == "file" {
                files.append(entry)
            }
        }

        return files.sorted { $0.path < $1.path }
    }

    private func fetchRemoteEntries(at remotePath: String) async throws -> [RemoteEntry] {
        let (data, response) = try await session.data(from: treeURL(for: remotePath))

        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            throw GeneratorError.invalidResponse
        }

        return try JSONDecoder().decode([RemoteEntry].self, from: data)
    }

    private func relativePath(for remotePath: String) -> String {
        let prefix = Self.remoteCompiledPath + "/"
        guard remotePath.hasPrefix(prefix) else {
            return remotePath
        }

        return String(remotePath.dropFirst(prefix.count))
    }

    private func treeURL(for remotePath: String) -> URL {
        URL(string: "https://huggingface.co/api/models/\(Self.repository)/tree/main/\(remotePath)")!
    }

    private func resolveURL(for remotePath: String) -> URL {
        URL(string: "https://huggingface.co/\(Self.repository)/resolve/main/\(remotePath)?download=true")!
    }

    private func createDirectoryIfNeeded(at url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return nil
        }

        return Int64(fileSize)
    }

    private func savePreviewImage(_ image: CGImage, prompt: String) throws -> URL {
        try createDirectoryIfNeeded(at: previewDirectory)

        let filename = "\(sanitizedFilename(from: prompt))-\(UUID().uuidString).png"
        let destinationURL = previewDirectory.appendingPathComponent(filename)
        let representation = NSBitmapImageRep(cgImage: image)

        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw GeneratorError.imageEncodingFailed
        }

        try data.write(to: destinationURL, options: [.atomic])
        return destinationURL
    }

    private func sanitizedFilename(from prompt: String) -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedPrompt.isEmpty ? "AI-Wallpaper" : trimmedPrompt
        let filteredScalars = baseName.unicodeScalars.map { scalar -> Character in
            Character(CharacterSet.alphanumerics.contains(scalar) ? scalar : "-")
        }
        let candidate = String(filteredScalars)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return String((candidate.isEmpty ? "AI-Wallpaper" : candidate).prefix(40))
    }

    private static func makeModelConfiguration() -> MLModelConfiguration {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return configuration
    }
}
