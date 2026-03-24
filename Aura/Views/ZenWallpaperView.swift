import SwiftUI
import Combine

struct ZenWallpaperView: View {
    let style: String
    let palette: ThemePalette
    @State private var desktopImage: NSImage? = nil
    
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
