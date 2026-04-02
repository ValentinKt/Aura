import Foundation
import Observation

@MainActor
@Observable
final class AIImageGenerationViewModel {
    private let generator: StableDiffusionImageGenerator

    var isModelReady = false
    var isDownloadingModel = false
    var modelProgress: Double = 0
    var modelStatusMessage = "Download the Stable Diffusion model to start generating wallpapers."

    var isGeneratingImage = false
    var generationProgress: Double = 0
    var generationStatusMessage: String?
    var generatedImageURL: URL?
    var errorMessage: String?

    init(generator: StableDiffusionImageGenerator = StableDiffusionImageGenerator()) {
        self.generator = generator

        Task {
            await refreshModelAvailability()
        }
    }

    func refreshModelAvailability() async {
        isModelReady = await generator.isModelDownloaded()
        if isModelReady {
            modelProgress = 1
            modelStatusMessage = "Stable Diffusion model ready."
        } else if !isDownloadingModel {
            modelProgress = 0
            modelStatusMessage = "Download the Stable Diffusion model to start generating wallpapers."
        }
    }

    func downloadModel() async {
        guard !isDownloadingModel else { return }

        errorMessage = nil
        isDownloadingModel = true
        modelProgress = 0
        modelStatusMessage = "Preparing model download…"

        defer {
            isDownloadingModel = false
        }

        do {
            try await generator.ensureModelDownloaded { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.modelProgress = update.fractionCompleted
                    self?.modelStatusMessage = update.statusMessage
                }
            }
            isModelReady = true
            modelProgress = 1
            modelStatusMessage = "Stable Diffusion model ready."
        } catch {
            errorMessage = error.localizedDescription
            await refreshModelAvailability()
        }
    }

    func generateImage(prompt: String) async -> URL? {
        guard !isGeneratingImage else {
            return generatedImageURL
        }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            errorMessage = "Enter a prompt before generating an image."
            return nil
        }

        guard isModelReady else {
            errorMessage = "Download the Stable Diffusion model before generating an image."
            return nil
        }

        errorMessage = nil
        isGeneratingImage = true
        generationProgress = 0
        generationStatusMessage = "Preparing Stable Diffusion…"

        defer {
            isGeneratingImage = false
        }

        do {
            let previousImageURL = generatedImageURL
            let generatedURL = try await generator.generateImage(prompt: trimmedPrompt) { [weak self] update in
                Task { @MainActor [weak self] in
                    self?.generationProgress = update.fractionCompleted
                    self?.generationStatusMessage = update.statusMessage
                }
            }

            if previousImageURL != generatedURL {
                await generator.removeGeneratedPreview(at: previousImageURL)
            }

            generatedImageURL = generatedURL
            generationProgress = 1
            generationStatusMessage = "AI wallpaper ready."
            return generatedURL
        } catch {
            errorMessage = error.localizedDescription
            generationStatusMessage = nil
            return nil
        }
    }

    func unloadModel() async {
        await generator.unloadResources()
        generationProgress = 0
        generationStatusMessage = nil
    }

    func clearGeneratedImage(removeFile: Bool = false) async {
        let currentURL = generatedImageURL
        generatedImageURL = nil
        generationProgress = 0
        generationStatusMessage = nil
        if removeFile {
            await generator.removeGeneratedPreview(at: currentURL)
        }
    }
}
