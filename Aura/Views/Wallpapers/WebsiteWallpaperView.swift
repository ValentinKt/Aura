import SwiftUI
import WebKit

struct WebsiteWallpaperView: NSViewRepresentable {
    let urlString: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        // Improve performance and look for background
        webView.customUserAgent = "AuraWallpaper/1.0"
        
        if let url = URL(string: urlString) {
            let request = URLRequest(url: url)
            webView.load(request)
        }
        
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // If we want to support dynamic URL changes
        if let currentURL = nsView.url?.absoluteString, currentURL != urlString {
            if let url = URL(string: urlString) {
                nsView.load(URLRequest(url: url))
            }
        }
    }
}
