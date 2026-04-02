import Foundation
import CoreML
import SwiftUI

enum UpscaleModelError: LocalizedError {
    case downloadFailed(String)
    case extractionFailed(String)
    case compilationFailed(String)
    case fileSystemError(String)
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let reason): return "Download failed: \(reason)"
        case .extractionFailed(let reason): return "Extraction failed: \(reason)"
        case .compilationFailed(let reason): return "Compilation failed: \(reason)"
        case .fileSystemError(let reason): return "File system error: \(reason)"
        case .invalidURL: return "Invalid download URL."
        }
    }
}

/// Delegate to track download progress using modern URLSession APIs
final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            // Scale download progress to 0.0...0.8 to leave room for extraction & compilation
            progressHandler(progress * 0.8)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Handled by the await session.download(from:delegate:) return value
    }
}

actor UpscaleModelManager {
    static let shared = UpscaleModelManager()

    private let fileManager = FileManager.default
    private let modelName = "realesrgan512"
    private let downloadURLString = "https://huggingface.co/TheMurusTeam/coreml-upscaler-realesrgan512/resolve/main/realesrgan512.mlmodel.zip?download=true"

    private var appSupportDirectory: URL {
        get throws {
            let url = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Aura", isDirectory: true)
            if !fileManager.fileExists(atPath: url.path) {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url
        }
    }

    nonisolated var compiledModelURL: URL {
        get throws {
            let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("Aura", isDirectory: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            }
            return url.appendingPathComponent("\(modelName).mlmodelc")
        }
    }

    /// Checks if the compiled model already exists in the local cache.
    func checkLocalCache() throws -> URL? {
        let url = try compiledModelURL
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return url
        }
        return nil
    }

    /// Downloads, extracts, compiles and caches the model.
    /// Yields progress between 0.0 and 1.0.
    func fetchModel(progressHandler: @Sendable @escaping (Double) -> Void) async throws -> URL {
        // 1. Check Local Cache
        if let cachedURL = try checkLocalCache() {
            progressHandler(1.0)
            return cachedURL
        }

        // 2. Download & Track
        guard let url = URL(string: downloadURLString) else {
            throw UpscaleModelError.invalidURL
        }

        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let zipFileURL = tempDir.appendingPathComponent("\(modelName).zip")

        let delegate = DownloadProgressDelegate(progressHandler: progressHandler)

        let (downloadedURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw UpscaleModelError.downloadFailed("Invalid response from server: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        try fileManager.moveItem(at: downloadedURL, to: zipFileURL)
        progressHandler(0.85) // Download complete

        // 3. Native Extraction (macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipFileURL.path, "-d", tempDir.path]

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw UpscaleModelError.extractionFailed("unzip terminated with status \(process.terminationStatus)")
        }

        // Delete zip immediately to prevent disk space leaks
        try? fileManager.removeItem(at: zipFileURL)
        progressHandler(0.9) // Extraction complete

        // 4. Compile on Device
        let unzippedModelURL = tempDir.appendingPathComponent("\(modelName).mlmodel")
        guard fileManager.fileExists(atPath: unzippedModelURL.path) else {
            throw UpscaleModelError.extractionFailed("Extracted .mlmodel not found at \(unzippedModelURL.path)")
        }

        // Compile model in a detached task to keep the actor unblocked
        let compiledTempURL = try await Task.detached {
            try MLModel.compileModel(at: unzippedModelURL)
        }.value

        progressHandler(0.95) // Compilation complete

        // 5. Store & Cleanup
        let finalURL = try compiledModelURL

        // Remove existing compiled model if it somehow exists but wasn't detected
        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        try fileManager.moveItem(at: compiledTempURL, to: finalURL)

        // Cleanup temporary directory (including raw .mlmodel)
        try? fileManager.removeItem(at: tempDir)

        progressHandler(1.0)
        return finalURL
    }
}

/// A MainActor observable wrapper for easy SwiftUI consumption and UI progress streaming
@Observable @MainActor
final class UpscaleModelState {
    var progress: Double = 0.0
    var isDownloading: Bool = false
    var isReady: Bool = false
    var error: Error?

    func loadModel() async {
        guard !isDownloading && !isReady else { return }

        isDownloading = true
        error = nil

        do {
            if let _ = try await UpscaleModelManager.shared.checkLocalCache() {
                self.progress = 1.0
                self.isReady = true
                self.isDownloading = false
                return
            }

            // Use an AsyncStream to bridge the closure-based progress to modern async sequence
            let stream = AsyncStream<Double> { continuation in
                Task {
                    do {
                        _ = try await UpscaleModelManager.shared.fetchModel { progress in
                            continuation.yield(progress)
                        }
                        continuation.finish()
                    } catch {
                        // Error handling is done below by calling fetchModel again directly if needed,
                        // or we can handle it cleanly:
                        continuation.finish()
                    }
                }
            }

            // Start updating UI with progress
            Task {
                for await p in stream {
                    self.progress = p
                }
            }

            // Await the actual fetch to handle throwing correctly
            _ = try await UpscaleModelManager.shared.fetchModel { _ in }
            self.isReady = true
        } catch {
            self.error = error
        }

        self.isDownloading = false
    }
}
