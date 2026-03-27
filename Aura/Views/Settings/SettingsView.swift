import SwiftUI

struct SettingsView: View {
    @Bindable var appModel: AppModel
    @State private var showingQuotesManager = false

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
