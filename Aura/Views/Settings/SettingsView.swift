import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var showingQuotesManager = false
    @State private var selectedFavoriteWallpaperID: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 28, weight: .bold))
                    .padding(.bottom, 8)

                SectionView(title: "Adaptive Environment") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: Binding(
                            get: { appModel.settingsViewModel.settings.weatherSyncEnabled },
                            set: { appModel.toggleWeatherSync($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Weather Sync")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Automatically adjust mood based on local weather conditions.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Divider()

                        Toggle(isOn: Binding(
                            get: { appModel.settingsViewModel.settings.keepCurrentWallpaper },
                            set: { appModel.settingsViewModel.updateKeepCurrentWallpaper($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Keep Current Wallpaper")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Do not change the desktop wallpaper when switching moods.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)

                        Divider()

                        Toggle(isOn: Binding(
                            get: { appModel.settingsViewModel.settings.websiteWallpaperInteractive },
                            set: { appModel.setWebsiteWallpaperInteractive($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Website Interaction Mode")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Brings website wallpapers just above desktop icons so clicks and scrolling work. Turn it off to restore full desktop click-through.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        Divider()

                        Toggle(isOn: Binding(
                            get: { appModel.settingsViewModel.settings.smartDuckingEnabled },
                            set: { appModel.setSmartDuckingEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Pause & Smart Ducking")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Automatically fade out volume when you are on a call or playing media, and fade it back in afterwards.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                SectionView(title: "Custom Content") {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Manage Custom Quotes")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Create and edit your own quotes for the Quotes theme.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Manage") {
                                showingQuotesManager = true
                            }
                        }
                    }
                }

                SectionView(title: "Wallpaper Library") {
                    FavoriteWallpapersManagerView(
                        appModel: appModel,
                        selectedMoodID: $selectedFavoriteWallpaperID
                    )
                }

                SectionView(title: "Transitions & Ambience") {
                    VStack(spacing: 20) {
                        SettingSlider(
                            label: "Transition Duration",
                            description: "How long it takes to fade between moods.",
                            value: Binding(
                                get: { appModel.settingsViewModel.settings.transitionDuration },
                                set: { appModel.settingsViewModel.updateTransitionDuration($0) }
                            ),
                            range: 0.5...10,
                            format: "%.1fs"
                        )

                        SettingSlider(
                            label: "Random Ambience",
                            description: "Randomly adjust layer volumes for a more natural feel.",
                            value: Binding(
                                get: { appModel.settingsViewModel.settings.randomAmbienceInterval },
                                set: { value in
                                    appModel.settingsViewModel.updateRandomAmbienceInterval(value)
                                    appModel.playerViewModel.updateRandomizeInterval(value)
                                }
                            ),
                            range: 0...900,
                            format: "%.0fs",
                            zeroLabel: "Off"
                        )
                    }
                }

                SectionView(title: "About") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aura v1.0.0")
                            .font(.system(size: 14, weight: .bold))
                        Text("A premium ambient workspace for macOS.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(40)
        }
        .sheet(isPresented: $showingQuotesManager) {
            QuotesManagerView(appModel: appModel)
        }
    }
}

struct QuotesManagerView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var quotes: [CustomQuoteModel] = []
    @State private var newQuoteText: String = ""
    @State private var selectedStyle: String = "motivational"
    @State private var selectedTextColor: Color = .white
    @State private var selectedFontSize: Double = 48
    @State private var selectedFontStyle: QuoteFontStyle = .serif

    let availableStyles = ["motivational", "philosophical", "minimal", "bold"]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Manage Custom Quotes")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer()
                Button {
                    appModel.moodViewModel.refreshQuoteMoods()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .liquidGlass(Circle(), interactive: true, variant: .regular)
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 24)

            HStack(alignment: .top, spacing: 32) {
                // Left Column: Editor
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quote Text")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                        TextField("Enter your quote...", text: $newQuoteText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15))
                            .padding(14)
                            .liquidGlass(RoundedRectangle(cornerRadius: 12), opacity: 0.1, interactive: true, variant: .regular)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Style")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $selectedStyle) {
                                ForEach(availableStyles, id: \.self) { style in
                                    Text(style.capitalized).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        HStack {
                            Text("Font")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $selectedFontStyle) {
                                ForEach(QuoteFontStyle.allCases, id: \.self) { fontStyle in
                                    Text(fontStyle.displayName).tag(fontStyle)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 150)
                        }

                        HStack {
                            Text("Text Color")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            ColorPicker("", selection: $selectedTextColor, supportsOpacity: true)
                                .labelsHidden()
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Font Size")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(Int(selectedFontSize)) pt")
                                    .font(.system(size: 13).monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $selectedFontSize, in: 28...96, step: 1)
                                .controlSize(.regular)
                        }
                    }
                    .padding(20)
                    .liquidGlass(RoundedRectangle(cornerRadius: 16), opacity: 0.15, interactive: false, variant: .regular)

                    Button(action: addQuote) {
                        HStack {
                            Spacer()
                            Image(systemName: "plus")
                            Text("Add Quote")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                        .font(.system(size: 15))
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .liquidGlass(RoundedRectangle(cornerRadius: 12), interactive: true, variant: .regular)
                    }
                    .buttonStyle(.plain)
                    .disabled(newQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .frame(width: 300)

                // Right Column: Preview and List
                VStack(alignment: .leading, spacing: 24) {
                    // Preview
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Preview")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        quotePreview
                            .liquidGlass(RoundedRectangle(cornerRadius: 16), opacity: 0.1, interactive: false, variant: .regular)
                    }

                    // List
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Saved Quotes")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if quotes.isEmpty {
                            VStack {
                                Spacer()
                                Text("No quotes yet.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .liquidGlass(RoundedRectangle(cornerRadius: 16), opacity: 0.1, interactive: false, variant: .regular)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 12) {
                                    ForEach(quotes, id: \.id) { quote in
                                        HStack(spacing: 16) {
                                            VStack(alignment: .leading, spacing: 6) {
                                                Text(quote.text)
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .lineLimit(1)

                                                HStack(spacing: 8) {
                                                    Text(quote.style.capitalized)
                                                    Text("•")
                                                    Text("\(quote.fontStyle.displayName)")
                                                    Text("•")
                                                    Text("\(Int(quote.fontSize))pt")
                                                }
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Circle()
                                                .fill(Color(
                                                    red: quote.textColor.red,
                                                    green: quote.textColor.green,
                                                    blue: quote.textColor.blue,
                                                    opacity: quote.textColor.alpha
                                                ))
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))

                                            Button {
                                                deleteQuote(quote)
                                            } label: {
                                                Image(systemName: "trash")
                                                    .foregroundStyle(.red.opacity(0.8))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(8)
                                            .liquidGlass(RoundedRectangle(cornerRadius: 6), interactive: true, variant: .regular)
                                        }
                                        .padding(12)
                                        .liquidGlass(RoundedRectangle(cornerRadius: 12), opacity: 0.1, interactive: true, variant: .regular)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 340)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
        .frame(width: 740, height: 580)
        .liquidGlass(RoundedRectangle(cornerRadius: 24, style: .continuous), interactive: true, variant: .regular)
        .presentationBackground(.clear)
        .shadow(color: .black.opacity(0.3), radius: 50, y: 25)
        .onAppear(perform: loadQuotes)
        .onDisappear {
            appModel.moodViewModel.refreshQuoteMoods()
        }
    }

    private func loadQuotes() {
        quotes = appModel.quoteEngine.loadQuotes()
    }

    private var quotePreview: some View {
        ZStack {
            Color.clear

            Text(newQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your quote preview" : newQuoteText)
                .font(previewFont)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            selectedTextColor,
                            selectedTextColor.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .multilineTextAlignment(.center)
                .padding(24)
                .minimumScaleFactor(0.5)
                .shadow(color: selectedTextColor.opacity(0.2), radius: 10, x: 0, y: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), opacity: 0.1, interactive: false)
    }

    private var previewFont: Font {
        switch selectedFontStyle {
        case .system:
            .system(size: selectedFontSize, weight: .light, design: .default)
        case .serif:
            .system(size: selectedFontSize, weight: .medium, design: .serif)
        case .rounded:
            .system(size: selectedFontSize, weight: .semibold, design: .rounded)
        case .monospaced:
            .system(size: selectedFontSize, weight: .heavy, design: .monospaced)
        }
    }

    private func addQuote() {
        let trimmed = newQuoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newQuote = CustomQuoteModel(
            text: trimmed,
            style: selectedStyle,
            textColor: colorComponents(from: selectedTextColor),
            fontSize: selectedFontSize,
            fontStyle: selectedFontStyle
        )
        appModel.quoteEngine.saveQuote(newQuote)
        newQuoteText = ""
        loadQuotes()
        appModel.moodViewModel.refreshQuoteMoods()
    }

    private func deleteQuote(_ quote: CustomQuoteModel) {
        appModel.quoteEngine.deleteQuote(id: quote.id)
        loadQuotes()
        appModel.moodViewModel.refreshQuoteMoods()
    }

    private func colorComponents(from color: Color) -> ColorComponents {
        let nsColor = NSColor(color).usingColorSpace(.deviceRGB) ?? .white
        return ColorComponents(
            red: Double(nsColor.redComponent),
            green: Double(nsColor.greenComponent),
            blue: Double(nsColor.blueComponent),
            alpha: Double(nsColor.alphaComponent)
        )
    }
}

struct FavoriteWallpapersManagerView: View {
    @Bindable var appModel: AppModel
    @Binding var selectedMoodID: String?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 20) {
                FavoriteWallpaperHeroView(
                    appModel: appModel,
                    mood: selectedMood
                )

                if let selectedMood {
                    HStack(spacing: 12) {
                        Button {
                            Task {
                                try? await appModel.launchScene(
                                    id: selectedMood.id,
                                    immersive: false,
                                    resumePlayback: false
                                )
                            }
                        } label: {
                            Label("Apply to Desktop", systemImage: "sparkles.rectangle.stack")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .foregroundStyle(.white)
                        .liquidGlass(RoundedRectangle(cornerRadius: 12), interactive: true, variant: .regular)

                        Button {
                            removeFavorite(selectedMood)
                        } label: {
                            Label("Remove Favorite", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .foregroundStyle(.red.opacity(0.9))
                        .liquidGlass(RoundedRectangle(cornerRadius: 12), interactive: true, variant: .regular)
                    }

                    if let resourceURL = selectedMood.previewResourceURL {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([resourceURL])
                        } label: {
                            Label("Reveal Source in Finder", systemImage: "folder")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .liquidGlass(RoundedRectangle(cornerRadius: 12), interactive: true, variant: .regular)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Favorite Wallpapers")
                                .font(.system(size: 16, weight: .semibold))
                            Text("\(favoriteScenes.count) saved")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !favoriteScenes.isEmpty {
                            Button("Clear All") {
                                appModel.removeAllFavoriteScenes()
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red.opacity(0.9))
                        }
                    }

                    if favoriteScenes.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "star.slash")
                                .font(.system(size: 32))
                                .foregroundStyle(.secondary)
                            
                            VStack(spacing: 8) {
                                Text("No favorite wallpapers yet")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Star atmospheres from Aura to build a reusable wallpaper library.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 280)
                        .padding(24)
                        .background(Color.clear)
                        .settingsLiquidGlassCard(cornerRadius: 24)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(favoriteScenes, id: \.id) { mood in
                                    FavoriteWallpaperRow(
                                        mood: mood,
                                        isSelected: mood.id == selectedMood?.id,
                                        isCurrent: mood.id == appModel.moodViewModel.currentMood?.id,
                                        onSelect: {
                                            selectedMoodID = mood.id
                                        },
                                        onDelete: {
                                            removeFavorite(mood)
                                        }
                                    )
                                }
                            }
                        }
                        .frame(maxHeight: 280)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(displayPreviews.count > 1 ? "Current Desktops" : "Current Desktop")
                        .font(.system(size: 16, weight: .semibold))

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(displayPreviews) { preview in
                            DisplayWallpaperPreviewCard(preview: preview)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: favoriteScenes.map { $0.id }) {
            syncSelection()
        }
    }

    private var favoriteScenes: [Mood] {
        appModel.favoriteScenes
    }

    private var selectedMood: Mood? {
        if let selectedMoodID,
           let mood = favoriteScenes.first(where: { $0.id == selectedMoodID }) {
            return mood
        }
        return favoriteScenes.first
    }

    private var displayPreviews: [WallpaperDisplayPreview] {
        let previews = appModel.wallpaperEngine.displayWallpaperPreviews
        if previews.count == 1 {
            return previews
        }
        return previews.sorted { lhs, rhs in
            if lhs.isPrimary == rhs.isPrimary {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            return lhs.isPrimary && !rhs.isPrimary
        }
    }

    private func removeFavorite(_ mood: Mood) {
        appModel.toggleFavoriteScene(mood.id)
        syncSelection()
    }

    private func syncSelection() {
        guard !favoriteScenes.isEmpty else {
            selectedMoodID = nil
            return
        }

        if let selectedMoodID,
           favoriteScenes.contains(where: { $0.id == selectedMoodID }) {
            return
        }

        selectedMoodID = favoriteScenes.first?.id
    }
}

struct FavoriteWallpaperHeroView: View {
    @Bindable var appModel: AppModel
    let mood: Mood?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WallpaperThumbnailView(
                mood: mood,
                url: mood?.previewResourceURL,
                cornerRadius: 18,
                minHeight: 250
            )

            if let mood {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(mood.name)
                                .font(.system(size: 22, weight: .bold))
                            Text("\(mood.subtheme) • \(mood.wallpaper.type.settingsLabel)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if mood.id == appModel.moodViewModel.currentMood?.id {
                            Text("Current")
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .liquidGlass(Capsule(), interactive: false, variant: .regular)
                        }
                    }

                    Text(mood.wallpaper.settingsDescription)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Label(mood.theme, systemImage: "paintpalette")
                        Label(mood.wallpaper.resourceSummary, systemImage: "photo.on.rectangle")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Select a favorite wallpaper")
                        .font(.system(size: 20, weight: .bold))
                    Text("Use favorites to keep your best desktop setups ready for one-click access.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct FavoriteWallpaperRow: View {
    let mood: Mood
    let isSelected: Bool
    let isCurrent: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            WallpaperThumbnailView(
                mood: mood,
                url: mood.previewResourceURL,
                cornerRadius: 12,
                minHeight: 72
            )
            .frame(width: 120, height: 72)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(mood.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.85), in: Capsule())
                    }
                }
                Text("\(mood.subtheme) • \(mood.wallpaper.type.settingsLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(mood.wallpaper.resourceSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.85))
                    .padding(8)
                    .liquidGlass(RoundedRectangle(cornerRadius: 8), interactive: true, variant: .regular)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.white.opacity(0.04))
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
    }
}

struct DisplayWallpaperPreviewCard: View {
    let preview: WallpaperDisplayPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WallpaperThumbnailView(
                mood: nil,
                url: preview.wallpaperURL,
                cornerRadius: 14,
                minHeight: 120
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(preview.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .background(Color.clear)
        .settingsLiquidGlassCard(cornerRadius: 22)
    }
}

struct SettingsLiquidGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .background {
                if reduceTransparency {
                    shape.fill(.regularMaterial)
                } else {
                    if #available(macOS 16.0, *) {
                        Color.clear
                            .glassEffect(.regular.tint(.black.opacity(0.25)), in: shape)
                    } else {
                        shape.fill(.black.opacity(0.2))
                            .background(.ultraThinMaterial, in: shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.35),
                            .white.opacity(0.05),
                            .white.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
    }
}

struct WallpaperThumbnailView: View {
    let mood: Mood?
    let url: URL?
    let cornerRadius: CGFloat
    let minHeight: CGFloat

    @State private var image: NSImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            previewContent

            if let mood {
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                Text(mood.wallpaper.type.settingsLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .task(id: taskKey) {
            image = await loadImage()
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        if let image {
            GeometryReader { proxy in
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
            }
        } else if let mood {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: mood.wallpaper.previewColors(fallback: mood.palette),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: mood.wallpaper.type.symbolName)
                            .font(.system(size: minHeight > 140 ? 32 : 22, weight: .medium))
                        Text(mood.wallpaper.resourceSummary)
                            .font(.system(size: 12, weight: .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding()
                }
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.black.opacity(0.12)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    if #available(macOS 16.0, *) {
                        Color.clear
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    }
                }
                .overlay {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
        }
    }

    private var taskKey: String {
        if let url {
            return url.absoluteString
        }
        if let mood {
            return mood.id
        }
        return "empty"
    }

    private func loadImage() async -> NSImage? {
        guard let url else { return nil }
        let pathExtension = url.pathExtension.lowercased()

        if ["mp4", "mov"].contains(pathExtension) {
            return await MediaUtils.videoPosterImage(from: url)
        }

        return await MediaUtils.loadImage(from: url)
    }
}

extension Mood {
    var previewResourceURL: URL? {
        wallpaper.resources.first.flatMap(MediaUtils.resolveResourceURL(_:))
    }
}

extension WallpaperDescriptor {
    var resourceSummary: String {
        if resources.isEmpty {
            return "Generated wallpaper"
        }

        if type == .website {
            return resources.first ?? "Website wallpaper"
        }

        if type == .quote,
           let first = resources.first {
            return first.capitalized
        }

        if let first = resources.first {
            let path = URL(fileURLWithPath: first)
            let fileName = path.lastPathComponent
            if fileName.isEmpty || fileName == "/" {
                return first
            }
            return fileName
        }

        return "Generated wallpaper"
    }

    var settingsDescription: String {
        switch type {
        case .staticImage:
            return "A still wallpaper that keeps the desktop calm and focused."
        case .animated:
            return "A motion-based wallpaper that adds ambient movement to the desktop."
        case .gradient:
            return "A generated gradient wallpaper based on the scene palette."
        case .particle:
            return "A generated particle wallpaper with subtle animated depth."
        case .current:
            return "Aura keeps your current macOS wallpaper while still applying audio and theme changes."
        case .dynamic:
            return "A dynamic wallpaper that adapts its appearance over time."
        case .time:
            return "A live time wallpaper that uses the current hour as the focal point."
        case .quote:
            return "A quote wallpaper layered over a backdrop for inspiration."
        case .zen:
            return "A guided visual wallpaper designed for slow breathing and calm focus."
        case .website:
            return "A live website wallpaper rendered directly on the desktop."
        }
    }

    func previewColors(fallback palette: ThemePalette) -> [Color] {
        let colors = gradientStops.map {
            Color(
                red: $0.red,
                green: $0.green,
                blue: $0.blue,
                opacity: $0.alpha
            )
        }

        if !colors.isEmpty {
            return colors
        }

        return [
            Color(
                red: palette.primary.red,
                green: palette.primary.green,
                blue: palette.primary.blue,
                opacity: palette.primary.alpha
            ),
            Color(
                red: palette.secondary.red,
                green: palette.secondary.green,
                blue: palette.secondary.blue,
                opacity: palette.secondary.alpha
            )
        ]
    }
}

extension WallpaperType {
    var settingsLabel: String {
        switch self {
        case .staticImage:
            return "Still"
        case .animated:
            return "Motion"
        case .gradient:
            return "Gradient"
        case .particle:
            return "Particles"
        case .current:
            return "System"
        case .dynamic:
            return "Dynamic"
        case .time:
            return "Time"
        case .quote:
            return "Quote"
        case .zen:
            return "Zen"
        case .website:
            return "Website"
        }
    }

    var symbolName: String {
        switch self {
        case .staticImage:
            return "photo"
        case .animated:
            return "play.rectangle"
        case .gradient:
            return "square.stack.3d.down.right"
        case .particle:
            return "sparkles"
        case .current:
            return "desktopcomputer"
        case .dynamic:
            return "clock.arrow.2.circlepath"
        case .time:
            return "clock"
        case .quote:
            return "quote.opening"
        case .zen:
            return "figure.mind.and.body"
        case .website:
            return "globe"
        }
    }
}

extension View {
    func settingsLiquidGlassCard(cornerRadius: CGFloat) -> some View {
        modifier(SettingsLiquidGlassCardModifier(cornerRadius: cornerRadius))
    }
}

struct SectionView<Content: View>: View {
    let title: String
    let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.5))
                .kerning(1.2)
                .padding(.leading, 4)

            content
                .padding(20)
                .background {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.regularMaterial)
                    } else {
                        Color.clear
                            .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
        }
    }
}

struct SettingSlider: View {
    let label: String
    let description: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    var zeroLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                Spacer()
                Text(value == 0 && zeroLabel != nil ? zeroLabel! : String(format: format, value))
                    .font(.system(size: 12).monospaced())
                    .foregroundStyle(Color.accentColor)
            }

            Slider(value: $value, in: range)
                .controlSize(.small)

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }
}

extension String {
    func uppercaseed() -> String {
        self.uppercased()
    }
}
