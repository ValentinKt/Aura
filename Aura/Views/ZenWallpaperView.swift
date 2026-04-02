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
    @State private var rotation: Double = 0

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
                        .rotationEffect(.degrees(Double(i) * 45 + rotation))
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: 40, height: 40)
                    .blur(radius: 20)
            }
            .rotationEffect(.degrees(rotation))
        }
        .onAppear {
            withAnimation(.linear(duration: 60).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// 10. Pendulum Style
struct PendulumZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var swing: Double = -30

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
                    .shadow(color: accentColor.opacity(0.6), radius: 20, x: 0, y: 10)
            }
            .rotationEffect(.degrees(swing), anchor: .top)
            .offset(y: -100)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                swing = 30
            }
        }
    }
}

// 11. Infinity Style
struct InfinityZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()

            HStack(spacing: -60) {
                Circle()
                    .stroke(
                        AngularGradient(colors: [primaryColor, accentColor, primaryColor], center: .center, angle: .degrees(phase * 360)),
                        lineWidth: 10
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)

                Circle()
                    .stroke(
                        AngularGradient(colors: [accentColor, primaryColor, accentColor], center: .center, angle: .degrees(-phase * 360)),
                        lineWidth: 10
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 2)
            }
            .scaleEffect(1.2)
        }
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

// 12. Prism Style
struct PrismZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 200, y: 50))
                    path.addLine(to: CGPoint(x: 50, y: 350))
                    path.addLine(to: CGPoint(x: 350, y: 350))
                    path.closeSubpath()
                }
                .stroke(
                    LinearGradient(colors: [primaryColor, accentColor], startPoint: isAnimating ? .top : .bottom, endPoint: isAnimating ? .bottom : .top),
                    lineWidth: 4
                )
                .frame(width: 400, height: 400)
                .blur(radius: isAnimating ? 4 : 1)
                .scaleEffect(isAnimating ? 1.05 : 0.95)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// 13. Stardust Style
struct StardustZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<50, id: \.self) { index in
                        Circle()
                            .fill(index % 3 == 0 ? accentColor : primaryColor)
                            .frame(width: CGFloat.random(in: 2...6))
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: CGFloat.random(in: 0...geometry.size.height)
                            )
                            .opacity(isAnimating ? CGFloat.random(in: 0.3...1.0) : 0.1)
                            .scaleEffect(isAnimating ? CGFloat.random(in: 0.8...1.2) : 1.0)
                            .animation(
                                .easeInOut(duration: Double.random(in: 2...5))
                                    .repeatForever(autoreverses: true)
                                    .delay(Double.random(in: 0...2)),
                                value: isAnimating
                            )
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}

// 1. Breathing Style
struct BreathingZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var isInhaling = false
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
                        .frame(width: isInhaling ? 400 : 200, height: isInhaling ? 400 : 200)
                        .blur(radius: 40)

                    // Main breathing circle
                    Circle()
                        .fill(LinearGradient(colors: [primaryColor, accentColor], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: isInhaling ? 300 : 150, height: isInhaling ? 300 : 150)
                        .shadow(color: accentColor.opacity(0.5), radius: isInhaling ? 30 : 10)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.3), lineWidth: 2)
                        )
                }

                Text(isInhaling ? "Inhale" : "Exhale")
                    .font(.system(size: 40, weight: .light, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                    .animation(.easeInOut(duration: 0.5), value: isInhaling)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                isInhaling.toggle()
            }
        }
    }
}

// 2. Mandala Style
struct MandalaZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var rotation: Double = 0
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<8) { index in
                    Circle()
                        .stroke(LinearGradient(colors: [primaryColor, accentColor], startPoint: .top, endPoint: .bottom), lineWidth: 2)
                        .frame(width: 250, height: 250)
                        .offset(x: 80)
                        .rotationEffect(.degrees(Double(index) * 45))
                }
            }
            .rotationEffect(.degrees(rotation))
            .shadow(color: accentColor.opacity(0.3), radius: 20)
        }
        .onAppear {
            withAnimation(.linear(duration: 40.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// 3. Ripple Style
struct RippleZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var rippleScale: CGFloat = 0.1
    @State private var rippleOpacity: Double = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()

            ZStack {
                Circle()
                    .stroke(accentColor, lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(rippleScale)
                    .opacity(rippleOpacity)

                Circle()
                    .fill(primaryColor)
                    .frame(width: 20, height: 20)
                    .shadow(color: primaryColor, radius: 10)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 3.0).repeatForever(autoreverses: false)) {
                rippleScale = 8.0
                rippleOpacity = 0.0
            }
        }
    }
}

// 4. Orb Style
struct OrbZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var rotation: Double = 0
    @State private var scale: CGFloat = 0.8

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
            .rotationEffect(.degrees(rotation))
            .scaleEffect(scale)
        }
        .onAppear {
            withAnimation(.linear(duration: 20.0).repeatForever(autoreverses: false)) {
                rotation = 360
            }
            withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
                scale = 1.1
            }
        }
    }
}

// 5. Lotus Style
struct LotusZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var isBlooming = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<12) { index in
                    Capsule()
                        .fill(LinearGradient(colors: [primaryColor.opacity(0.6), accentColor.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(width: isBlooming ? 60 : 20, height: isBlooming ? 300 : 100)
                        .offset(y: isBlooming ? 150 : 50)
                        .rotationEffect(.degrees(Double(index) * 30))
                }

                Circle()
                    .fill(accentColor)
                    .frame(width: isBlooming ? 80 : 40, height: isBlooming ? 80 : 40)
                    .shadow(color: accentColor, radius: 20)
            }
            .rotationEffect(.degrees(isBlooming ? 45 : 0))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 8.0).repeatForever(autoreverses: true)) {
                isBlooming.toggle()
            }
        }
    }
}

// 6. Waves Style
struct WavesZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var phase1: CGFloat = 0
    @State private var phase2: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    SineWave(phase: phase1, amplitude: 60)
                        .stroke(primaryColor.opacity(0.6), lineWidth: 4)
                        .shadow(color: primaryColor, radius: 10)

                    SineWave(phase: phase2, amplitude: 80)
                        .stroke(accentColor.opacity(0.6), lineWidth: 3)
                        .shadow(color: accentColor, radius: 10)
                }
                .frame(height: geometry.size.height)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 10.0).repeatForever(autoreverses: false)) {
                phase1 = .pi * 2
            }
            withAnimation(.linear(duration: 15.0).repeatForever(autoreverses: false)) {
                phase2 = -.pi * 2
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

        for x in stride(from: 0, through: width, by: 1) {
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
    @State private var eclipseProgress: CGFloat = -1.5

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
                    .offset(x: eclipseProgress * 400)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 15.0).repeatForever(autoreverses: true)) {
                eclipseProgress = 1.5
            }
        }
    }
}

// 8. Particles Style
struct ParticlesZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @State private var isAnimating = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            GeometryReader { geometry in
                ZStack {
                    ForEach(0..<30, id: \.self) { index in
                        Circle()
                            .fill(index % 2 == 0 ? primaryColor : accentColor)
                            .frame(width: CGFloat.random(in: 5...20))
                            .opacity(isAnimating ? CGFloat.random(in: 0.1...0.8) : 0)
                            .position(
                                x: CGFloat.random(in: 0...geometry.size.width),
                                y: isAnimating ? -50 : geometry.size.height + 50
                            )
                            .animation(
                                .linear(duration: Double.random(in: 10...30))
                                    .repeatForever(autoreverses: false)
                                    .delay(Double.random(in: 0...10)),
                                value: isAnimating
                            )
                            .blur(radius: CGFloat.random(in: 1...4))
                    }
                }
            }
        }
        .onAppear {
            isAnimating = true
        }
    }
}
