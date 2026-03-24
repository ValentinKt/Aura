import SwiftUI
import UniformTypeIdentifiers

struct CreateMoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Bindable var appModel: AppModel
    
    @State private var moodName: String = ""
    @State private var wallpaperTypeSelection: Int = 0 // 0 = Media, 1 = Time
    @State private var selectedFileURL: URL?
    @State private var selectedTimeStyle: String = "minimal"
    @State private var isShowingFilePicker = false
    @State private var errorMessage: String?
    
    private let timeStyles = ["minimal", "analog", "typographic", "binary", "solar", "glass_blocks", "words", "orbit", "neon", "fluid"]
    
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
    }
    
    private var header: some View {
        VStack(spacing: 4) {
            Text("Create Custom Mood")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text("Combine your favorite wallpaper with a custom audio mix.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 24)
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
            HStack {
                Text("Wallpaper Type")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(1)
                
                Spacer()
                
                Picker("", selection: $wallpaperTypeSelection) {
                    Text("Media").tag(0)
                    Text("Time").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }
            
            if wallpaperTypeSelection == 0 {
                mediaPickerSection
            } else {
                timeStylePickerSection
            }
        }
    }
    
    private var timeStylePickerSection: some View {
        VStack(spacing: 12) {
            Picker("Time Style", selection: $selectedTimeStyle) {
                ForEach(timeStyles, id: \.self) { style in
                    Text(style.capitalized).tag(style)
                }
            }
            .pickerStyle(.menu)
            .padding()
            .background {
                if reduceTransparency {
                    buttonShape.fill(.regularMaterial)
                } else {
                    Color.clear.glassEffect(.regular.interactive(), in: buttonShape)
                }
            }
            
            // Preview
            TimeWallpaperView(style: selectedTimeStyle, palette: ThemePalette(primary: ColorComponents(red: 0.1, green: 0.1, blue: 0.1), secondary: ColorComponents(red: 0.2, green: 0.2, blue: 0.2), accent: ColorComponents(red: 0.9, green: 0.9, blue: 0.9)))
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
    
    private var mediaPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let url = selectedFileURL {
                ZStack(alignment: .topTrailing) {
                    VStack(spacing: 12) {
                        if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                            VideoBackgroundView(url: url)
                                .aspectRatio(16/9, contentMode: .fill)
                                .frame(height: 140)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        } else if let image = NSImage(contentsOf: url) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(16/9, contentMode: .fill)
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
            } else {
                Button {
                    isShowingFilePicker = true
                } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "plus.square.dashed")
                            .font(.system(size: 32))
                            .foregroundStyle(Color.accentColor)
                        Text("Select Media (MP4 / HEIC)")
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
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.movie, .quickTimeMovie, .mpeg4Movie, .image, UTType("public.heic")].compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedFileURL = url
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
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
                
                let isFormValid = !moodName.isEmpty && (wallpaperTypeSelection == 1 || selectedFileURL != nil)
                
                Button(action: createMood) {
                    Text("Create Mood")
                        .font(.headline)
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
    
    private func createMood() {
        do {
            let wallpaperPath: String
            let type: WallpaperType?
            
            if wallpaperTypeSelection == 0 {
                guard let url = selectedFileURL else { return }
                wallpaperPath = try CustomAssetManager.saveCustomWallpaper(from: url)
                type = nil // Let MoodViewModel infer type
            } else {
                wallpaperPath = selectedTimeStyle
                type = .time
            }
            
            // Add the mood to the model
            appModel.moodViewModel.addCustomMood(
                name: moodName,
                wallpaperPath: wallpaperPath,
                layerMix: appModel.playerViewModel.layerVolumes,
                type: type
            )
            
            dismiss()
        } catch {
            print("🟥 [CreateMoodView] Failed to save wallpaper: \(error.localizedDescription)")
            errorMessage = "Failed to save wallpaper: \(error.localizedDescription)"
        }
    }
}
