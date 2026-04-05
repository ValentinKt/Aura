import SwiftUI

enum AuraHelpLinks {
    static let troubleshooting = URL(string: "https://github.com/ValentinKt/Aura/issues")!
}

struct AuraInlineFeedbackView: View {
    let title: String
    let message: String
    var symbolName = "exclamationmark.triangle.fill"
    var tint: Color = .orange
    var compact = false
    var retryTitle = "Retry"
    var retryAction: (() -> Void)?
    var helpURL: URL?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(alignment: .top, spacing: compact ? 10 : 12) {
                Image(systemName: symbolName)
                    .font(.system(size: compact ? 13 : 15, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: compact ? 18 : 22)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: compact ? 12 : 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(message)
                        .font(.system(size: compact ? 11 : 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                if let retryAction {
                    Button(action: retryAction) {
                        Text(retryTitle)
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .padding(.horizontal, compact ? 10 : 12)
                            .padding(.vertical, compact ? 7 : 8)
                            .frame(minWidth: compact ? 64 : 72)
                            .background {
                                Capsule()
                                    .fill(tint.opacity(reduceTransparency ? 0.24 : 0.18))
                            }
                    }
                    .buttonStyle(.plain)
                }

                if let helpURL {
                    Link(destination: helpURL) {
                        Text("Help")
                            .font(.system(size: compact ? 11 : 12, weight: .semibold))
                            .padding(.horizontal, compact ? 10 : 12)
                            .padding(.vertical, compact ? 7 : 8)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(reduceTransparency ? 0.16 : 0.12))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(compact ? 12 : 16)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 14 : 18, style: .continuous)
                .strokeBorder(tint.opacity(0.2), lineWidth: 1)
        }
    }
}

struct AuraEmptyStateView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    var symbolName = "sparkles.rectangle.stack"

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbolName)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 60, height: 60)
                .background {
                    Circle()
                        .fill(Color.accentColor.opacity(reduceTransparency ? 0.18 : 0.14))
                }

            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: action) {
                Text(actionTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background {
                        Capsule()
                            .fill(Color.accentColor)
                    }
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct AuraModelDownloadSheet: View {
    let progress: Double
    let statusMessage: String
    let isDownloading: Bool
    let errorMessage: String?
    let onCancel: () -> Void
    let onRetry: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Download Stable Diffusion")
                        .font(.system(size: 22, weight: .bold))

                    Text("Aura keeps image generation local. Download the Core ML model once to unlock private, on-device wallpaper generation.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(statusMessage)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    ProgressView(value: progress)
                        .controlSize(.regular)

                    Text(progress.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                if let errorMessage {
                    AuraInlineFeedbackView(
                        title: "Download interrupted",
                        message: errorMessage,
                        retryAction: onRetry,
                        helpURL: AuraHelpLinks.troubleshooting
                    )
                }

                HStack {
                    Spacer()

                    Button(action: onCancel) {
                        Text(isDownloading ? "Cancel Download" : "Close")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background {
                                Capsule()
                                    .fill(Color.white.opacity(reduceTransparency ? 0.14 : 0.1))
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(width: 420)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
        .presentationBackground(.clear)
        .shadow(color: .black.opacity(0.24), radius: 32, y: 18)
    }
}
