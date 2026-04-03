import SwiftUI
import WebKit

struct WebsiteWallpaperView: View {
    let urlString: String
    var isPreview: Bool = false

    var body: some View {
        Group {
            if isPreview {
                WebsitePreviewCard(urlString: urlString)
            } else {
                WebsiteWebView(urlString: urlString)
            }
        }
    }
}

private struct WebsitePreviewCard: View {
    let urlString: String

    private var resolvedURL: URL? {
        WebsiteWebView.resolvedURL(from: urlString)
    }

    private var hostText: String {
        resolvedURL?.host(percentEncoded: false) ?? "Website"
    }

    private var pathText: String? {
        guard let resolvedURL else { return nil }
        let path = resolvedURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : path
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.86),
                    Color.blue.opacity(0.36),
                    Color.cyan.opacity(0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .center, spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))

                Text(hostText)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                if let pathText {
                    Text(pathText)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
