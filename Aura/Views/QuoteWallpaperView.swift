import SwiftUI
import Combine

struct QuoteWallpaperView: View {
    @Environment(\.colorScheme) private var colorScheme

    let style: String
    let palette: ThemePalette
    let quoteID: UUID?
    let selectedWallpaperURL: URL?
    var isPreview: Bool = false
    @State private var quoteTextValue: String = ""
    @State private var quoteTextColor = Color.white
    @State private var quoteFontSize: Double = 48
    @State private var quoteFontStyle: QuoteFontStyle = .serif
    @State private var backgroundImage: NSImage?

    private let quoteEngine = QuoteEngine(persistence: PersistenceController.shared)

    var secondaryColor: Color {
        Color(red: palette.secondary.red, green: palette.secondary.green, blue: palette.secondary.blue)
    }

    var accentColor: Color {
        Color(red: palette.accent.red, green: palette.accent.green, blue: palette.accent.blue)
    }

    init(style: String, palette: ThemePalette, quoteID: UUID? = nil, selectedWallpaperURL: URL? = nil, isPreview: Bool = false) {
        self.style = style
        self.palette = palette
        self.quoteID = quoteID
        self.selectedWallpaperURL = selectedWallpaperURL
        self.isPreview = isPreview
    }

    @State private var textOpacity = 0.0
    @State private var textOffset: CGFloat = 20

    var body: some View {
        ZStack {
            if let selectedWallpaperURL {
                if Self.isVideoURL(selectedWallpaperURL) {
                    VideoBackgroundView(url: selectedWallpaperURL)
                        .ignoresSafeArea()
                } else if let backgroundImage {
                    Image(nsImage: backgroundImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                }
            }

            LinearGradient(
                colors: [
                    Color(red: palette.primary.red, green: palette.primary.green, blue: palette.primary.blue).opacity(colorScheme == .dark ? 0.4 : 0.9),
                    Color(red: palette.secondary.red, green: palette.secondary.green, blue: palette.secondary.blue).opacity(colorScheme == .dark ? 0.6 : 0.7),
                    Color(red: palette.accent.red, green: palette.accent.green, blue: palette.accent.blue).opacity(colorScheme == .dark ? 0.5 : 0.8)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .opacity(backgroundImage == nil && !isShowingVideoBackground ? 1 : 0.45)
            .gpuAnimation([.opacity(from: 0.8, to: 1.0, duration: 15.0, autoreverses: true)])
            .ignoresSafeArea()

            // Ambient floating orbs
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.2))
                    .frame(width: 400, height: 400)
                    .blur(radius: 100)
                    .offset(x: -200, y: 150)
                    .gpuAnimation([
                        .translationX(from: 0, to: 400, duration: 20.0, autoreverses: true),
                        .translationY(from: 0, to: -300, duration: 20.0, autoreverses: true)
                    ])

                Circle()
                    .fill(secondaryColor.opacity(0.2))
                    .frame(width: 300, height: 300)
                    .blur(radius: 80)
                    .offset(x: 250, y: -200)
                    .gpuAnimation([
                        .translationX(from: 0, to: -500, duration: 20.0, autoreverses: true),
                        .translationY(from: 0, to: 400, duration: 20.0, autoreverses: true)
                    ])
            }

            VStack(spacing: 24) {
                Image(systemName: "quote.opening")
                    .font(.system(size: quoteFontSize * 0.5, weight: .black, design: .serif))
                    .foregroundStyle(quoteTextColor.opacity(0.15))
                    .offset(x: -20, y: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 60)

                Text(quoteTextValue.isEmpty ? quoteText(for: style) : quoteTextValue)
                    .font(quoteFont)
                    .lineSpacing(8)
                    .kerning(quoteFontStyle == .monospaced ? 2 : 0)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                quoteTextColor,
                                quoteTextColor.opacity(0.6)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 10)
                    .shadow(color: accentColor.opacity(0.3), radius: 40, x: 0, y: 20)
                    .drawingGroup()
                    .padding(.horizontal, 80)
                    .minimumScaleFactor(0.3)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .gpuAnimation([.scale(from: 0.98, to: 1.02, duration: 8.0, autoreverses: true)])

                Image(systemName: "quote.closing")
                    .font(.system(size: quoteFontSize * 0.5, weight: .black, design: .serif))
                    .foregroundStyle(quoteTextColor.opacity(0.15))
                    .offset(x: 20, y: -10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 60)
            }
            .frame(maxWidth: 900)
            .padding(60)
            .liquidGlass(RoundedRectangle(cornerRadius: 40, style: .continuous), opacity: 0.1, interactive: false, variant: .regular)
            .shadow(color: .black.opacity(0.2), radius: 50, x: 0, y: 20)
        }
        .onAppear {
            loadCustomQuote()

            withAnimation(.easeOut(duration: 1.5)) {
                textOpacity = 1.0
                textOffset = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("quotesDidChange"))) { notification in
            guard let updatedStyle = notification.object as? String else {
                loadCustomQuote()
                return
            }

            if updatedStyle == style {
                loadCustomQuote()
            }
        }
        .task(id: backgroundTaskKey) {
            await loadBackgroundImage()
        }
    }

    private var isShowingVideoBackground: Bool {
        if isPreview { return false }
        guard let selectedWallpaperURL else { return false }
        return Self.isVideoURL(selectedWallpaperURL)
    }

    private static func isVideoURL(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    private var backgroundTaskKey: String {
        selectedWallpaperURL?.absoluteString ?? "system-wallpaper"
    }

    private func loadBackgroundImage() async {
        guard let url = selectedWallpaperURL else {
            if let screen = NSScreen.main, let desktopURL = NSWorkspace.shared.desktopImageURL(for: screen) {
                backgroundImage = await MediaUtils.loadImage(from: desktopURL)
            } else {
                backgroundImage = nil
            }
            return
        }

        if Self.isVideoURL(url) {
            backgroundImage = await MediaUtils.videoPosterImage(from: url)
        } else {
            backgroundImage = await MediaUtils.loadImage(from: url)
        }
    }

    private func loadCustomQuote() {
        let quotes = quoteEngine.loadQuotes(for: style)
        if let quoteID, let selectedQuote = quotes.first(where: { $0.id == quoteID }) {
            apply(quote: selectedQuote)
        } else if let randomQuote = quotes.randomElement() {
            apply(quote: randomQuote)
        } else {
            quoteTextValue = quoteText(for: style)
            quoteTextColor = colorScheme == .dark ? .white : .black

            // Apply dynamic default styles based on the quote theme
            switch style {
            case "motivational":
                quoteFontSize = 84
                quoteFontStyle = .rounded
            case "philosophical":
                quoteFontSize = 76
                quoteFontStyle = .serif
            case "minimal":
                quoteFontSize = 64
                quoteFontStyle = .system
            case "bold":
                quoteFontSize = 110
                quoteFontStyle = .monospaced
            default:
                quoteFontSize = 84
                quoteFontStyle = .serif
            }
        }
    }

    private var quoteFont: Font {
        switch quoteFontStyle {
        case .system:
            .system(size: quoteFontSize, weight: .light, design: .default)
        case .serif:
            .system(size: quoteFontSize, weight: .medium, design: .serif)
        case .rounded:
            .system(size: quoteFontSize, weight: .semibold, design: .rounded)
        case .monospaced:
            .system(size: quoteFontSize, weight: .heavy, design: .monospaced)
        }
    }

    private func apply(quote: CustomQuoteModel) {
        quoteTextValue = quote.text
        quoteTextColor = Color(
            red: quote.textColor.red,
            green: quote.textColor.green,
            blue: quote.textColor.blue,
            opacity: quote.textColor.alpha
        )
        quoteFontSize = quote.fontSize
        quoteFontStyle = quote.fontStyle
    }

    private func quoteText(for style: String) -> String {
        switch style {
        case "motivational": return "Keep pushing forward."
        case "philosophical": return "I think, therefore I am."
        case "minimal": return "Less is more."
        case "bold": return "BE BOLD."
        default: return "Stay inspired."
        }
    }
}
