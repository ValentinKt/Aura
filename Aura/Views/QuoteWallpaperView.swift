import SwiftUI
import Combine

struct QuoteWallpaperView: View {
    let style: String
    let palette: ThemePalette
    @State private var desktopImage: NSImage? = nil
    @State private var quoteTextValue: String = ""
    
    // We instantiate QuoteEngine locally or pass it down. Since it requires PersistenceController.shared, we can do it here.
    private let quoteEngine = QuoteEngine(persistence: PersistenceController.shared)
    
    var primaryColor: Color {
        Color(red: palette.primary.red, green: palette.primary.green, blue: palette.primary.blue)
    }
    
    var secondaryColor: Color {
        Color(red: palette.secondary.red, green: palette.secondary.green, blue: palette.secondary.blue)
    }
    
    var accentColor: Color {
        Color(red: palette.accent.red, green: palette.accent.green, blue: palette.accent.blue)
    }

    var body: some View {
        ZStack {
            if let image = desktopImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 20)
            } else {
                Color.black.ignoresSafeArea()
            }
            
            VStack {
                        Text(quoteTextValue.isEmpty ? quoteText(for: style) : quoteTextValue)
                            .font(.system(size: 48, weight: .bold, design: .serif))
                            .foregroundStyle(primaryColor)
                            .multilineTextAlignment(.center)
                            .shadow(color: secondaryColor.opacity(0.5), radius: 10, x: 0, y: 5)
                            .padding()
                    }
                }
                .onAppear {
                    loadDesktopImage()
                    loadCustomQuote()
                }
            }
            
            private func loadCustomQuote() {
                let quotes = quoteEngine.loadQuotes(for: style)
                if let randomQuote = quotes.randomElement() {
                    quoteTextValue = randomQuote.text
                } else {
                    quoteTextValue = quoteText(for: style)
                }
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
    
    private func loadDesktopImage() {
        if let screen = NSScreen.main,
           let url = NSWorkspace.shared.desktopImageURL(for: screen),
           let image = NSImage(contentsOf: url) {
            desktopImage = image
        }
    }
}
