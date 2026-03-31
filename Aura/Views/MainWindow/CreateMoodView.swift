import SwiftUI
import ImagePlayground
import UniformTypeIdentifiers

struct CreateMoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.supportsImagePlayground) private var supportsImagePlayground
    @Bindable var appModel: AppModel
    let defaultTheme: String
    let defaultSubtheme: String
    let initialWallpaperSource: InitialWallpaperSource

    @State private var moodName: String = ""
    @State private var selectedFileURL: URL?
    @State private var isShowingFilePicker = false
    @State private var isShowingImagePlayground = false
    @State private var isCreatingMood = false
    @State private var creationProgress: Double = 0
    @State private var creationStatusMessage: String?
    @State private var errorMessage: String?

    init(
        appModel: AppModel,
        defaultTheme: String = "Custom",
        defaultSubtheme: String = "Personal",
        initialWallpaperSource: InitialWallpaperSource = .importedMedia
    ) {
        self.appModel = appModel
        self.defaultTheme = defaultTheme
        self.defaultSubtheme = defaultSubtheme
        self.initialWallpaperSource = initialWallpaperSource
    }

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 24) {
                header

                ScrollView {
                    VStack(spacing: 24) {
                        nameSection
                        videoSection
                        audioSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }

                footer
            }
            .frame(width: 480, height: 650)
            .background {
                if reduceTransparency {
                    sheetShape.fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.regular, in: sheetShape)
                }
            }
        }
        .presentationBackground(.clear)
        .shadow(color: .black.opacity(0.3), radius: 50, y: 25)
        .imagePlaygroundSheet(
            isPresented: $isShowingImagePlayground,
            concept: "",
            onCompletion: { url in
                selectedFileURL = url
                errorMessage = nil

                if trimmedMoodName.isEmpty {
                    moodName = "Image Playground Mood"
                }
            },
            onCancellation: nil
        )
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text(initialWallpaperSource == .imagePlayground ? "Create Dynamic Desktop Mood" : "Create Custom Mood")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(initialWallpaperSource == .imagePlayground ? "Design a wallpaper in Image Playground and Aura will build a .heic Dynamic Desktop from 24 Retina-sized JPEG frames that change throughout the day." : "Combine your favorite wallpaper with a custom audio mix.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.horizontal, 24)
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mood Name")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1)

            TextField("e.g. Rainy Night, Study Focus...", text: $moodName)
                .textFieldStyle(.plain)
                .padding(14)
                .background {
                    if reduceTransparency {
                        nameFieldShape.fill(.regularMaterial)
                    } else {
                        Color.clear
                            .glassEffect(.regular.interactive(), in: nameFieldShape)
                    }
                }
        }
    }

    private var videoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallpaper")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .kerning(1)

            mediaPickerSection
        }
    }

    private var mediaPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if initialWallpaperSource == .imagePlayground {
                imagePlaygroundSection
            } else {
                importedMediaSection
            }
        }
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie, .image, UTType("public.heic")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                    errorMessage = nil
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private var importedMediaSection: some View {
        Group {
            if let url = selectedFileURL {
                selectedWallpaperPreview(for: url)
            } else {
                Button {
                    isShowingFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.square.dashed")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Select Media (MP4 / HEIC / PNG)")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .background(Color.black.opacity(0.001))
                    .background {
                        if reduceTransparency {
                            buttonShape.fill(.regularMaterial)
                        } else {
                            Color.clear
                                .glassEffect(.regular.interactive(), in: buttonShape)
                        }
                    }
                    .contentShape(buttonShape)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var imagePlaygroundSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            dynamicDesktopInfoCard

            if supportsImagePlayground {
                Button {
                    isShowingImagePlayground = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 14, weight: .semibold))
                        Text(selectedFileURL == nil ? "Open Image Playground" : "Regenerate in Image Playground")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background {
                        buttonShape.fill(Color.blue)
                    }
                    .foregroundStyle(.white)
                    .contentShape(buttonShape)
                }
                .buttonStyle(.plain)

                if let url = selectedFileURL {
                    selectedWallpaperPreview(for: url)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image Playground isn’t available on this Mac.")
                        .font(.system(size: 13, weight: .medium))
                    Text("Aura still lets you create custom moods with your own imported wallpapers.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background {
                    if reduceTransparency {
                        buttonShape.fill(.regularMaterial)
                    } else {
                        Color.clear
                            .glassEffect(.regular, in: buttonShape)
                    }
                }
            }
        }
    }

    private var dynamicDesktopInfoCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text("Dynamic Desktop output")
                    .font(.system(size: 13, weight: .semibold))
                Text("Aura generates a unique dynamic HEIC wallpaper from the image you created with “Image Playground.” \n From this image, 24 images are generated to represent the changing hours throughout the day. \n All images are upscaled for display on Retina screens.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background {
            if reduceTransparency {
                buttonShape.fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: buttonShape)
            }
        }
    }

    private func selectedWallpaperPreview(for url: URL) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 12) {
                if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                    VideoBackgroundView(url: url)
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 140)
                        .overlay(Text("Unsupported format").foregroundStyle(.secondary))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Button {
                selectedFileURL = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white.opacity(0.6))
                    .font(.system(size: 24))
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.black.opacity(0.3)))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audio Mix")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text("Adjust the levels below to set the default mix for this mood.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            SoundLayerMixerView(appModel: appModel, isScrollable: false)
                .scaleEffect(0.9)
                .padding(.top, -10)
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            if isCreatingMood, let creationStatusMessage {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(creationStatusMessage)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer()

                        Text(creationProgress.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    ProgressView(value: creationProgress)
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
            }

            HStack(spacing: 16) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.001))
                        .background {
                            if reduceTransparency {
                                buttonShape.fill(.regularMaterial)
                            } else {
                                Color.clear
                                    .glassEffect(.regular.interactive(), in: buttonShape)
                            }
                        }
                        .contentShape(buttonShape)
                }
                .buttonStyle(.plain)
                .disabled(isCreatingMood)

                let isFormValid = !trimmedMoodName.isEmpty && selectedFileURL != nil && !isCreatingMood

                Button {
                    Task {
                        await createMood()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isCreatingMood {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }

                        Text(createButtonTitle)
                            .font(.headline)
                    }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.001))
                        .background {
                            if !isFormValid {
                                if reduceTransparency {
                                    buttonShape.fill(.regularMaterial)
                                } else {
                                    Color.clear
                                        .glassEffect(.regular, in: buttonShape)
                                }
                            } else {
                                Color.accentColor.opacity(0.8)
                            }
                        }
                        .foregroundStyle(!isFormValid ? .white.opacity(0.5) : .white)
                        .contentShape(buttonShape)
                }
                .buttonStyle(.plain)
                .disabled(!isFormValid)
            }
        }
        .padding(.bottom, 32)
    }

    private var sheetShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var nameFieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var buttonShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    private var trimmedMoodName: String {
        moodName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldUpscaleSelectedWallpaper: Bool {
        initialWallpaperSource == .imagePlayground
    }

    private var createButtonTitle: String {
        if isCreatingMood {
            return shouldUpscaleSelectedWallpaper ? "Creating Dynamic Desktop…" : "Creating…"
        }

        return "Create Mood"
    }

    @MainActor
    private func createMood() async {
        guard let url = selectedFileURL else { return }

        isCreatingMood = true
        creationProgress = shouldUpscaleSelectedWallpaper ? 0 : 0.1
        creationStatusMessage = shouldUpscaleSelectedWallpaper ? "Preparing Dynamic Desktop frames…" : "Creating mood…"
        errorMessage = nil

        defer {
            isCreatingMood = false
        }

        do {
            let wallpaperPath = try await saveWallpaper(from: url)

            appModel.moodViewModel.addCustomMood(
                name: trimmedMoodName,
                theme: defaultTheme,
                subtheme: defaultSubtheme,
                wallpaperPath: wallpaperPath,
                layerMix: appModel.playerViewModel.layerVolumes
            )

            dismiss()
        } catch {
            creationStatusMessage = nil
            print("🟥 [CreateMoodView] Failed to save wallpaper: \(error.localizedDescription)")
            errorMessage = "Failed to save wallpaper: \(error.localizedDescription)"
        }
    }

    private func saveWallpaper(from url: URL) async throws -> String {
        if shouldUpscaleSelectedWallpaper {
            return try await generateDynamicImagePlaygroundWallpaper(from: url)
        }

        return try CustomAssetManager.saveCustomWallpaper(from: url)
    }

    private func generateDynamicImagePlaygroundWallpaper(from url: URL) async throws -> String {
        let destinationURL = CustomAssetManager.makeCustomWallpaperURL(fileExtension: "heic")

        do {
            let generator = try DynamicDesktopGenerator()
            try await generator.generate(from: url, outputURL: destinationURL) { update in
                Task { @MainActor in
                    creationProgress = update.fractionCompleted
                    creationStatusMessage = update.statusMessage
                }
            }
            return destinationURL.path
        } catch {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try? FileManager.default.removeItem(at: destinationURL)
            }
            throw error
        }
    }

}

extension CreateMoodView {
    enum InitialWallpaperSource {
        case importedMedia
        case imagePlayground
    }
}
