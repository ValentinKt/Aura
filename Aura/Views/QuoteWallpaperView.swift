import SwiftUI
import Combine

struct QuoteWallpaperView: View {
    @Environment(\.colorScheme) private var colorScheme

    let style: String
    let palette: ThemePalette
    let quoteID: UUID?
    @State private var quoteTextValue: String = ""
    @State private var quoteTextColor = Color.white
    @State private var quoteFontSize: Double = 48
    @State private var quoteFontStyle: QuoteFontStyle = .serif

    private let quoteEngine = QuoteEngine(persistence: PersistenceController.shared)

    var secondaryColor: Color {
        Color(red: palette.secondary.red, green: palette.secondary.green, blue: palette.secondary.blue)
    }

    var accentColor: Color {
        Color(red: palette.accent.red, green: palette.accent.green, blue: palette.accent.blue)
    }

    init(style: String, palette: ThemePalette, quoteID: UUID? = nil) {
        self.style = style
        self.palette = palette
        self.quoteID = quoteID
    }

    @State private var isAnimating = false
    @State private var textOpacity = 0.0
    @State private var textOffset: CGFloat = 20

    var body: some View {
        ZStack {
            // Dynamic animated gradient background
            LinearGradient(
                colors: [
                    Color(red: palette.primary.red, green: palette.primary.green, blue: palette.primary.blue).opacity(colorScheme == .dark ? 0.3 : 0.8),
                    Color(red: palette.secondary.red, green: palette.secondary.green, blue: palette.secondary.blue).opacity(colorScheme == .dark ? 0.5 : 0.6),
                    Color(red: palette.accent.red, green: palette.accent.green, blue: palette.accent.blue).opacity(colorScheme == .dark ? 0.4 : 0.7)
                ],
                startPoint: isAnimating ? .topLeading : .bottomTrailing,
                endPoint: isAnimating ? .bottomTrailing : .topLeading
            )
            .animation(.easeInOut(duration: 10).repeatForever(autoreverses: true), value: isAnimating)
            .ignoresSafeArea()

            // Subtle glowing orb behind text
            Circle()
                .fill(accentColor.opacity(0.15))
                .blur(radius: 120)
                .scaleEffect(isAnimating ? 1.2 : 0.8)
                .animation(.easeInOut(duration: 8).repeatForever(autoreverses: true), value: isAnimating)
            
            VStack {
                Text(quoteTextValue.isEmpty ? quoteText(for: style) : quoteTextValue)
                    .font(quoteFont)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                quoteTextColor,
                                quoteTextColor.opacity(0.7)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .multilineTextAlignment(.center)
                    .shadow(color: quoteTextColor.opacity(0.2), radius: 15, x: 0, y: 5)
                    .shadow(color: accentColor.opacity(0.4), radius: 30, x: 0, y: 15)
                    .padding(40)
                    .minimumScaleFactor(0.3)
                    .opacity(textOpacity)
                    .offset(y: textOffset)
                    .scaleEffect(isAnimating ? 1.03 : 0.97)
                    .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: isAnimating)
            }
        }
        .onAppear {
            isAnimating = true
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
