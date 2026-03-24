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

    @State private var quotes: [CustomQuoteModel] = []
    @State private var newQuoteText: String = ""
    @State private var selectedStyle: String = "motivational"
    @State private var selectedTextColor: Color = .white
    @State private var selectedFontSize: Double = 48
    @State private var selectedFontStyle: QuoteFontStyle = .serif

    let availableStyles = ["motivational", "philosophical", "minimal", "bold"]

    var body: some View {
        VStack(spacing: 20) {
            Text("Manage Custom Quotes")
                .font(.title2.weight(.bold))
                .padding(.top, 20)

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add New Quote")
                        .font(.headline)

                    TextField("Quote text...", text: $newQuoteText)
                        .textFieldStyle(.roundedBorder)

                    Picker("Style", selection: $selectedStyle) {
                        ForEach(availableStyles, id: \.self) { style in
                            Text(style.capitalized).tag(style)
                        }
                    }
                    .pickerStyle(.menu)

                    ColorPicker("Text Color", selection: $selectedTextColor, supportsOpacity: true)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Font Size")
                            Spacer()
                            Text("\(Int(selectedFontSize)) pt")
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: $selectedFontSize, in: 28...96, step: 1)
                    }

                    Picker("Font", selection: $selectedFontStyle) {
                        ForEach(QuoteFontStyle.allCases, id: \.self) { fontStyle in
                            Text(fontStyle.displayName).tag(fontStyle)
                        }
                    }
                    .pickerStyle(.menu)

                    quotePreview
                        .padding(.top, 4)

                    Button("Add Quote") {
                        addQuote()
                    }
                    .disabled(newQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(NSColor.controlBackgroundColor)))

                VStack(alignment: .leading) {
                    Text("Your Quotes")
                        .font(.headline)

                    List {
                        ForEach(quotes, id: \.id) { quote in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(quote.text)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(quote.style.capitalized)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(
                                                red: quote.textColor.red,
                                                green: quote.textColor.green,
                                                blue: quote.textColor.blue,
                                                opacity: quote.textColor.alpha
                                            ))
                                            .frame(width: 10, height: 10)
                                        Text("\(quote.fontStyle.displayName) • \(Int(quote.fontSize)) pt")
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Button {
                                    deleteQuote(quote)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.bordered)
                    .cornerRadius(8)
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Done") {
                    appModel.moodViewModel.refreshQuoteMoods()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .padding()
            }
        }
        .frame(width: 600, height: 400)
        .onAppear {
            loadQuotes()
        }
        .onDisappear {
            appModel.moodViewModel.refreshQuoteMoods()
        }
    }

    private func loadQuotes() {
        quotes = appModel.quoteEngine.loadQuotes()
    }

    private var quotePreview: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)

            Text(newQuoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your quote preview" : newQuoteText)
                .font(previewFont)
                .foregroundStyle(selectedTextColor)
                .multilineTextAlignment(.center)
                .padding(24)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, minHeight: 170)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private var previewFont: Font {
        switch selectedFontStyle {
        case .system:
            .system(size: selectedFontSize, weight: .bold, design: .default)
        case .serif:
            .system(size: selectedFontSize, weight: .bold, design: .serif)
        case .rounded:
            .system(size: selectedFontSize, weight: .bold, design: .rounded)
        case .monospaced:
            .system(size: selectedFontSize, weight: .bold, design: .monospaced)
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
