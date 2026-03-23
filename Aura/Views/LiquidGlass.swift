import SwiftUI

struct LiquidGlassLayer<S: Shape>: View {
    let shape: S
    let opacity: Double
    let interactive: Bool
    let variant: GlassVariant
    let lensing: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    enum GlassVariant {
        case regular
        case clear
    }
    
    init(shape: S, opacity: Double = 0.7, interactive: Bool = true, variant: GlassVariant = .regular, lensing: Bool = true) {
        self.shape = shape
        self.opacity = opacity
        self.interactive = interactive
        self.variant = variant
        self.lensing = lensing
    }
    
    var body: some View {
        if reduceTransparency {
            shape.fill(.regularMaterial).opacity(opacity)
        } else {
            if #available(macOS 16.0, *) {
                Group {
                    if variant == .clear {
                        if interactive {
                            Color.clear.glassEffect(.clear.interactive(), in: shape)
                        } else {
                            Color.clear.glassEffect(.clear, in: shape)
                        }
                    } else {
                        if interactive {
                            Color.clear.glassEffect(.regular.interactive(), in: shape)
                        } else {
                            Color.clear.glassEffect(.regular, in: shape)
                        }
                    }
                }
                .overlay {
                    if variant == .regular {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.4),
                                        .white.opacity(0.1),
                                        .white.opacity(0.2)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                            .blendMode(.plusLighter)
                    } else if variant == .clear {
                        shape
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(0.2),
                                        .clear,
                                        .white.opacity(0.1)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                            .blendMode(.plusLighter)
                    }
                }
            } else {
                shape
                    .fill(.regularMaterial)
                    .opacity(opacity)
                    .overlay {
                        shape
                            .stroke(Color.white.opacity(0.1 * opacity), lineWidth: 0.5)
                    }
            }
        }
    }
}

struct GlassEffectContainer<Content: View, S: Shape>: View {
    let shape: S
    let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    init(shape: S, @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.content = content
    }
    
    var body: some View {
        content()
            .background {
                if reduceTransparency {
                    shape.fill(.regularMaterial)
                } else {
                    if #available(macOS 16.0, *) {
                        Color.clear
                            .glassEffect(.clear, in: shape)
                            .overlay {
                                shape
                                    .stroke(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .clear, .white.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 0.5
                                    )
                            }
                    } else {
                        shape
                            .fill(.regularMaterial)
                            .overlay {
                                shape.stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                            }
                    }
                }
            }
    }
}

extension GlassEffectContainer where S == RoundedRectangle {
    init(@ViewBuilder content: @escaping () -> Content) {
        self.init(shape: RoundedRectangle(cornerRadius: 8, style: .continuous), content: content)
    }
}

extension View {
    @ViewBuilder
    func liquidGlass<S: Shape>(_ shape: S, opacity: Double = 0.7, interactive: Bool = true, variant: LiquidGlassLayer<S>.GlassVariant = .regular, lensing: Bool = true, clip: Bool = true) -> some View {
        if clip {
            background {
                LiquidGlassLayer(shape: shape, opacity: opacity, interactive: interactive, variant: variant, lensing: lensing)
            }
            .clipShape(shape)
        } else {
            background {
                LiquidGlassLayer(shape: shape, opacity: opacity, interactive: interactive, variant: variant, lensing: lensing)
            }
        }
    }
}
