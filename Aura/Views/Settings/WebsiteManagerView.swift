import SwiftUI

struct WebsiteManagerView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @State private var websiteName: String = ""
    @State private var websiteURL: String = "https://"

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Add Custom Website")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(24)

                ScrollView {
                    VStack(spacing: 24) {
                        // Input section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Website Name")
                                .font(.headline)
                            
                            TextField("e.g. My Dashboard", text: $websiteName)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )

                            Text("Website URL")
                                .font(.headline)
                                .padding(.top, 8)
                            
                            TextField("https://...", text: $websiteURL)
                                .textFieldStyle(.plain)
                                .padding(12)
                                .background(Color.white.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 24)

                        // Add Button
                        Button(action: addWebsite) {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add Website")
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .disabled(websiteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isValidURL(websiteURL))
                        .opacity((websiteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isValidURL(websiteURL)) ? 0.5 : 1.0)
                    }
                    .padding(.bottom, 24)
                }
            }
            .frame(width: 480, height: 420)
            .background {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    Color.clear
                }
            }
        }
    }

    private func isValidURL(_ urlString: String) -> Bool {
        if let url = URL(string: urlString), url.scheme != nil, url.host != nil {
            return true
        }
        return false
    }

    private func addWebsite() {
        let trimmedName = websiteName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = websiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, isValidURL(trimmedURL) else { return }

        // Add to MoodViewModel
        appModel.moodViewModel.addCustomMood(
            name: trimmedName,
            theme: "Dynamic",
            subtheme: "Website",
            wallpaperPath: trimmedURL,
            layerMix: ["hum": 0.1], // Default ambient sound
            type: WallpaperType.website
        )

        websiteName = ""
        websiteURL = "https://"
        
        dismiss()
    }
}
