import SwiftUI
import Combine

struct ZenWallpaperView: View {
    let style: String
    let palette: ThemePalette
    let selectedWallpaperURL: URL?
    var isPreview: Bool = false
    @State private var backgroundImage: NSImage?

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
            if !isPreview, let selectedWallpaperURL, Self.isVideoURL(selectedWallpaperURL) {
                VideoBackgroundView(url: selectedWallpaperURL)
                    .ignoresSafeArea()
            } else if let image = backgroundImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }

            // Render specific style
            switch style {
            case "breathing":
                BreathingZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "mandala":
                MandalaZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "ripple":
                RippleZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "orb":
                OrbZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "lotus":
                LotusZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "waves":
                WavesZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "eclipse":
                EclipseZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "particles":
                ParticlesZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "galaxy":
                GalaxyZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "pendulum":
                PendulumZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "infinity":
                InfinityZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "prism":
                PrismZenView(primaryColor: primaryColor, accentColor: accentColor)
            case "stardust":
                StardustZenView(primaryColor: primaryColor, accentColor: accentColor)
            default:
                BreathingZenView(primaryColor: primaryColor, accentColor: accentColor)
            }
        }
        .drawingGroup()
        .task(id: backgroundTaskKey) {
            await loadBackgroundImage()
        }
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

    private static func isVideoURL(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }
}

// 9. Galaxy Style
struct GalaxyZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Ellipse()
                        .stroke(
                            LinearGradient(colors: [primaryColor.opacity(0.4), accentColor.opacity(0.1)], startPoint: .top, endPoint: .bottom),
                            lineWidth: 2
                        )
                        .frame(width: 600 - CGFloat(i * 100), height: 200 - CGFloat(i * 30))
                        .rotationEffect(.degrees(Double(i) * 45))
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: 40, height: 40)
                    .blur(radius: 20)
            }
            .gpuAnimation([.rotation(duration: 60.0, clockwise: true)])
        }
    }
}

// 10. Pendulum Style
struct PendulumZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            VStack(spacing: 0) {
                Rectangle()
                    .fill(LinearGradient(colors: [primaryColor.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2, height: 300)

                Circle()
                    .fill(accentColor)
                    .frame(width: 60, height: 60)
                    .shadow(color: accentColor, radius: 20)
                    .overlay(
                        Circle()
                            .fill(.white.opacity(0.5))
                            .frame(width: 20, height: 20)
                            .offset(x: -10, y: -10)
                    )
            }
            .offset(y: -100)
            .gpuAnimation([.rotationTo(from: -.pi/6, to: .pi/6, duration: 2.0, autoreverses: true)])
        }
    }
}

// 11. Infinity Style
struct InfinityZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            HStack(spacing: -60) {
                Circle()
                    .stroke(
                        AngularGradient(colors: [primaryColor, accentColor, primaryColor], center: .center, angle: .zero),
                        lineWidth: 10
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
                    .gpuAnimation([.rotation(duration: 10.0, clockwise: true)])

                Circle()
                    .stroke(
                        AngularGradient(colors: [accentColor, primaryColor, accentColor], center: .center, angle: .zero),
                        lineWidth: 10
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
                    .gpuAnimation([.rotation(duration: 10.0, clockwise: false)])
            }
            .scaleEffect(1.2)
        }
    }
}

// 12. Prism Style
struct PrismZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            ZStack {
                let trianglePath = Path { path in
                    path.move(to: CGPoint(x: 200, y: 50))
                    path.addLine(to: CGPoint(x: 50, y: 350))
                    path.addLine(to: CGPoint(x: 350, y: 350))
                    path.closeSubpath()
                }

                trianglePath
                    .stroke(
                        LinearGradient(colors: [primaryColor, accentColor], startPoint: .top, endPoint: .bottom),
                        lineWidth: 4
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 1)

                trianglePath
                    .stroke(
                        LinearGradient(colors: [primaryColor, accentColor], startPoint: .top, endPoint: .bottom),
                        lineWidth: 4
                    )
                    .frame(width: 400, height: 400)
                    .blur(radius: 4)
                    .gpuAnimation([.opacity(from: 0.2, to: 1.0, duration: 4.0, autoreverses: true)])
            }
            .gpuAnimation([.scale(from: 0.95, to: 1.05, duration: 4.0, autoreverses: true)])
        }
    }
}

// 13. Stardust Style
struct StardustZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<50, id: \.self) { index in
                        let duration = Double.random(in: 2...5)
                        let delay = Double.random(in: 0...2)
                        let toOpacity = CGFloat.random(in: 0.3...1.0)
                        let toScale = CGFloat.random(in: 0.8...1.2)
                        
                        Circle()
                            .fill(index % 3 == 0 ? accentColor : primaryColor)
                            .frame(width: CGFloat.random(in: 2...6))
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: CGFloat.random(in: 0...geometry.size.height)
                            )
                            .opacity(0.1)
                            .scaleEffect(1.0)
                            .gpuAnimation([
                                .opacity(from: 0.1, to: toOpacity, duration: duration, autoreverses: true, delay: delay),
                                .scale(from: 1.0, to: toScale, duration: duration, autoreverses: true, delay: delay)
                            ])
                    }
                }
            }
        }
    }
}

// 1. Breathing Style
struct BreathingZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // Dark overlay to focus
            Color.black.opacity(0.4).ignoresSafeArea()

            VStack(spacing: 60) {
                ZStack {
                    // Outer glow
                    Circle()
                        .fill(accentColor.opacity(0.2))
                        .frame(width: 300, height: 300)
                        .blur(radius: 40)
                        .gpuAnimation([.scale(from: 0.66, to: 1.33, duration: 4.0, autoreverses: true)])

                    // Main breathing circle
                    Circle()
                        .fill(LinearGradient(colors: [primaryColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 225, height: 225)
                        .shadow(color: accentColor.opacity(0.5), radius: 20)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 2)
                        )
                        .gpuAnimation([.scale(from: 0.66, to: 1.33, duration: 4.0, autoreverses: true)])
                }
                
                // Using a constant string for now to avoid CPU diffs on string updates, 
                // or we could use a TimelineView if the text MUST change. For zero CPU, a static text or no text is best.
                // Or we can just use "Breathe" and scale it.
                Text("Breathe")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .gpuAnimation([.opacity(from: 0.5, to: 1.0, duration: 4.0, autoreverses: true)])
            }
        }
    }
}

// 2. Mandala Style
struct MandalaZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<8, id: \.self) { index in
                    Circle()
                        .stroke(LinearGradient(colors: [primaryColor, accentColor], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                        .frame(width: 250, height: 250)
                        .offset(x: 80)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
            }
            .shadow(color: accentColor.opacity(0.3), radius: 20)
            .gpuAnimation([.rotation(duration: 40.0, clockwise: true)])
        }
    }
}

// 3. Ripple Style
struct RippleZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(accentColor, lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .gpuAnimation([
                        .scale(from: 0.1, to: 8.0, duration: 3.0, autoreverses: false),
                        .opacity(from: 1.0, to: 0.0, duration: 3.0, autoreverses: false)
                    ])

                Circle()
                    .fill(primaryColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: primaryColor, radius: 10)
            }
        }
    }
}

// 4. Orb Style
struct OrbZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                Circle()
                    .fill(primaryColor.opacity(0.5))
                    .frame(width: 300, height: 300)
                    .offset(x: -50, y: -50)
                    .blur(radius: 40)

                Circle()
                    .fill(accentColor.opacity(0.5))
                    .frame(width: 250, height: 250)
                    .offset(x: 60, y: 40)
                    .blur(radius: 50)

                Circle()
                    .fill(primaryColor)
                    .frame(width: 150, height: 150)
                    .blur(radius: 20)
            }
            .gpuAnimation([
                .rotation(duration: 20.0, clockwise: true),
                .scale(from: 0.8, to: 1.1, duration: 5.0, autoreverses: true)
            ])
        }
    }
}

// 5. Lotus Style
struct LotusZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<12, id: \.self) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [primaryColor.opacity(0.6), accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 60, height: 300)
                        .offset(y: 150)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: 80, height: 80)
                    .shadow(color: accentColor, radius: 20)
            }
            .gpuAnimation([
                .scale(from: 0.33, to: 1.0, duration: 8.0, autoreverses: true),
                .rotationTo(from: 0, to: .pi / 4, duration: 8.0, autoreverses: true)
            ])
        }
    }
}

// 6. Waves Style
struct WavesZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            GeometryReader { geometry in
                let wavelength = geometry.size.width / 2

                ZStack {
                    SineWave(phase: 0, amplitude: 60)
                        .stroke(primaryColor.opacity(0.6), lineWidth: 4)
                        .shadow(color: primaryColor, radius: 10)
                        .gpuAnimation([.translationX(from: 0, to: -wavelength, duration: 10.0, autoreverses: false)])

                    SineWave(phase: 0, amplitude: 80)
                        .stroke(accentColor.opacity(0.6), lineWidth: 3)
                        .shadow(color: accentColor, radius: 10)
                        .gpuAnimation([.translationX(from: 0, to: wavelength, duration: 15.0, autoreverses: false)])
                }
                .frame(height: geometry.size.height)
            }
        }
    }
}

struct SineWave: Shape {
    var phase: CGFloat
    var amplitude: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let midHeight = height / 2

        let wavelength = width / 2

        path.move(to: CGPoint(x: 0, y: midHeight))

        // Draw an extra wavelength so we can translate it seamlessly
        for x in stride(from: 0, through: width + wavelength, by: 1) {
            let relativeX = x / wavelength
            let y = midHeight + sin(relativeX * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
        }

        return path
    }
}

// 7. Eclipse Style
struct EclipseZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            ZStack {
                // Sun / Corona
                Circle()
                    .fill(accentColor)
                    .frame(width: 300, height: 300)
                    .shadow(color: accentColor, radius: 60)
                    .blur(radius: 5)

                // Moon
                Circle()
                    .fill(Color.black)
                    .frame(width: 295, height: 295)
                    .gpuAnimation([.translationX(from: -600, to: 600, duration: 15.0, autoreverses: true)])
            }
        }
    }
}

// 8. Particles Style
struct ParticlesZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<30, id: \.self) { index in
                        let startY = geometry.size.height + 50
                        let endY: CGFloat = -50
                        let duration = Double.random(in: 10...30)
                        let delay = Double.random(in: 0...10)
                        
                        Circle()
                            .fill(index % 2 == 0 ? primaryColor : accentColor)
                            .frame(width: CGFloat.random(in: 5...20))
                            .opacity(CGFloat.random(in: 0.1...0.8))
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: startY
                            )
                            .blur(radius: CGFloat.random(in: 1...4))
                            .gpuAnimation([
                                .translationY(from: 0, to: endY - startY, duration: duration, autoreverses: false, delay: delay)
                            ])
                    }
                }
            }
        }
    }
}
