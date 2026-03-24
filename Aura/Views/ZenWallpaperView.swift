import SwiftUI
import Combine

struct ZenWallpaperView: View {
    let style: String
    let palette: ThemePalette
    @State private var desktopImage: NSImage?

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
            // Actual System Wallpaper Background
            if let image = desktopImage {
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
            default:
                BreathingZenView(primaryColor: primaryColor, accentColor: accentColor)
            }
        }
        .onAppear {
            loadDesktopImage()
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
