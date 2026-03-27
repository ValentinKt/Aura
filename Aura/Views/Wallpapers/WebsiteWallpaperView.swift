import SwiftUI
import WebKit

struct WebsiteWallpaperView: View {
    let urlString: String
    var isPreview: Bool = false

    var body: some View {
        WebsiteWebView(urlString: urlString)
    }
}

struct WebsiteWebView: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.applicationNameForUserAgent = "AuraWallpaper"
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false

        load(urlString, into: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let resolvedURL = Self.resolvedURL(from: urlString) else { return }

        if nsView.url?.absoluteString != resolvedURL.absoluteString {
            load(urlString, into: nsView)
        }
    }

    private func load(_ urlString: String, into webView: WKWebView) {
        guard let url = Self.resolvedURL(from: urlString) else { return }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        webView.load(request)
    }

    static func resolvedURL(from rawValue: String) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        if let url = URL(string: trimmedValue), url.scheme != nil {
            return url
        }

        return URL(string: "https://\(trimmedValue)")
    }
}
