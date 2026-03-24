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

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.black : Color.white)
                .ignoresSafeArea()

            VStack {
                Text(quoteTextValue.isEmpty ? quoteText(for: style) : quoteTextValue)
                    .font(quoteFont)
                    .foregroundStyle(quoteTextColor)
                    .multilineTextAlignment(.center)
                    .shadow(color: secondaryColor.opacity(0.5), radius: 10, x: 0, y: 5)
                    .padding()
                    .minimumScaleFactor(0.45)
            }
        }
        .onAppear {
            loadCustomQuote()
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
            quoteFontSize = 48
            quoteFontStyle = .serif
        }
    }

    private var quoteFont: Font {
        switch quoteFontStyle {
        case .system:
            .system(size: quoteFontSize, weight: .bold, design: .default)
        case .serif:
            .system(size: quoteFontSize, weight: .bold, design: .serif)
        case .rounded:
            .system(size: quoteFontSize, weight: .bold, design: .rounded)
        case .monospaced:
            .system(size: quoteFontSize, weight: .bold, design: .monospaced)
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
