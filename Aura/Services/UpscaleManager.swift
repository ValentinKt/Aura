import AppKit
import Foundation

actor UpscaleManager {
    struct ProgressUpdate: Sendable {
        let completedCount: Int
        let totalCount: Int
        let currentIndex: Int?

        var fractionCompleted: Double {
            guard totalCount > 0 else { return 1 }
            return Double(completedCount) / Double(totalCount)
        }

        var statusMessage: String {
            "\(completedCount)/\(totalCount) images done"
        }
    }

    enum UpscaleError: LocalizedError, Sendable {
        case imageLoadingFailed(url: URL)
        case cgImageCreationFailed(index: Int)
        case missingResult(index: Int)

        var errorDescription: String? {
            switch self {
            case .imageLoadingFailed(let url):
                return "Failed to load an image from \(url.lastPathComponent)."
            case .cgImageCreationFailed(let index):
                return "Failed to create a CGImage for item \(index + 1)."
            case .missingResult(let index):
                return "Upscaling finished without producing a result for item \(index + 1)."
            }
        }
    }

    fileprivate struct WorkItem: Sendable {
        let index: Int
        let loadImage: @Sendable () async throws -> CGImage
    }

    private let maxConcurrentOperations: Int
    private let workerFactory: @Sendable () throws -> ImageUpscaler
    private var sharedWorker: ImageUpscaler?

    init(
        maxConcurrentOperations: Int = 2,
        workerFactory: @Sendable @escaping () throws -> ImageUpscaler = {
            let modelURL = try UpscaleModelManager.shared.compiledModelURL
            return try ImageUpscaler(modelURL: modelURL)
        }
    ) {
        self.maxConcurrentOperations = max(1, min(3, maxConcurrentOperations))
        self.workerFactory = workerFactory
    }

    func upscale(
        _ images: [NSImage],
        progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }
    ) async throws -> [NSImage] {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Pause/skip high-res upscaling when on battery (Low Power Mode)
            progress(ProgressUpdate(completedCount: images.count, totalCount: images.count, currentIndex: nil))
            return images
        }

        let workItems = images.enumerated().map { index, image in
            return WorkItem(index: index) {
                try autoreleasepool { () throws -> CGImage in
                    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        throw UpscaleError.cgImageCreationFailed(index: index)
                    }

                    return cgImage
                }
            }
        }

        let cgImages = try await upscale(workItems, progress: progress)
        return cgImages.map { image in
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    func upscale(_ image: NSImage) async throws -> NSImage {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return image
        }

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw UpscaleError.cgImageCreationFailed(index: 0)
        }

        let upscaledImage = try await upscale(cgImage)
        return NSImage(cgImage: upscaledImage, size: NSSize(width: upscaledImage.width, height: upscaledImage.height))
    }

    func upscale(
        urls: [URL],
        progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }
    ) async throws -> [NSImage] {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            // Load original images without upscaling if in Low Power Mode
            let workItems = urls.enumerated().map { index, url in
                WorkItem(index: index) {
                    try await Self.loadCGImage(from: url)
                }
            }
            var resultImages: [NSImage] = []
            for item in workItems {
                let cgImage = try await item.loadImage()
                resultImages.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
                progress(ProgressUpdate(completedCount: resultImages.count, totalCount: urls.count, currentIndex: resultImages.count))
            }
            return resultImages
        }

        let workItems = urls.enumerated().map { index, url in
            WorkItem(index: index) {
                try await Self.loadCGImage(from: url)
            }
        }

        let cgImages = try await upscale(workItems, progress: progress)
        return cgImages.map { image in
            NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }

    func upscale(
        _ images: [CGImage],
        progress: @escaping @Sendable (ProgressUpdate) -> Void = { _ in }
    ) async throws -> [CGImage] {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            progress(ProgressUpdate(completedCount: images.count, totalCount: images.count, currentIndex: nil))
            return images
        }

        let workItems = images.enumerated().map { index, image in
            WorkItem(index: index) {
                image
            }
        }

        return try await upscale(workItems, progress: progress)
    }

    func upscale(_ image: CGImage) async throws -> CGImage {
        if ProcessInfo.processInfo.isLowPowerModeEnabled {
            return image
        }

        let worker = try makeSharedWorkerIfNeeded()
        return try await worker.upscaleCGImage(image)
    }

    private func upscale(
        _ workItems: [WorkItem],
        progress: @escaping @Sendable (ProgressUpdate) -> Void
    ) async throws -> [CGImage] {
        guard !workItems.isEmpty else {
            progress(ProgressUpdate(completedCount: 0, totalCount: 0, currentIndex: nil))
            return []
        }

        progress(ProgressUpdate(completedCount: 0, totalCount: workItems.count, currentIndex: nil))

        let taskQueue = TaskQueue(items: workItems)
        let progressTracker = ProgressTracker(totalCount: workItems.count)
        let resultStore = ResultStore(totalCount: workItems.count)
        let workerCount = min(maxConcurrentOperations, workItems.count)
        let workerFactory = self.workerFactory

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<workerCount {
                let worker = try workerFactory()

                group.addTask(priority: .userInitiated) {
                    while let workItem = await taskQueue.next() {
                        try Task.checkCancellation()
                        let sourceImage = try await workItem.loadImage()
                        let upscaledImage = try await worker.upscaleCGImage(sourceImage)
                        await resultStore.store(upscaledImage, at: workItem.index)
                        let update = await progressTracker.recordCompletion(for: workItem.index)
                        progress(update)
                    }
                }
            }

            try await group.waitForAll()
        }

        return try await resultStore.makeOrderedResults()
    }

    private static func loadCGImage(from url: URL) async throws -> CGImage {
        let data = try await Task.detached(priority: .userInitiated) {
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return try Data(contentsOf: url)
        }.value

        guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, [
                kCGImageSourceShouldCache: false
              ] as CFDictionary) else {
            throw UpscaleError.imageLoadingFailed(url: url)
        }

        return cgImage
    }

    private func makeSharedWorkerIfNeeded() throws -> ImageUpscaler {
        if let sharedWorker {
            return sharedWorker
        }

        let worker = try workerFactory()
        sharedWorker = worker
        return worker
    }
}

private actor TaskQueue {
    private let items: [UpscaleManager.WorkItem]
    private var nextIndex = 0

    init(items: [UpscaleManager.WorkItem]) {
        self.items = items
    }

    func next() -> UpscaleManager.WorkItem? {
        guard nextIndex < items.count else {
            return nil
        }

        defer {
            nextIndex += 1
        }

        return items[nextIndex]
    }
}

private actor ProgressTracker {
    private let totalCount: Int
    private var completedCount = 0

    init(totalCount: Int) {
        self.totalCount = totalCount
    }

    func recordCompletion(for index: Int) -> UpscaleManager.ProgressUpdate {
        completedCount += 1
        return UpscaleManager.ProgressUpdate(
            completedCount: completedCount,
            totalCount: totalCount,
            currentIndex: index + 1
        )
    }
}

private actor ResultStore {
    private var images: [CGImage?]

    init(totalCount: Int) {
        self.images = Array(repeating: nil, count: totalCount)
    }

    func store(_ image: CGImage, at index: Int) {
        images[index] = image
    }

    func makeOrderedResults() throws -> [CGImage] {
        try images.enumerated().map { index, image in
            guard let image else {
                throw UpscaleManager.UpscaleError.missingResult(index: index)
            }

            return image
        }
    }
}
