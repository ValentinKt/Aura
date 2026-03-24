import SwiftUI
import Combine

struct SunsetWallpaperView: View {
    let style: String
    let palette: ThemePalette
    @State private var desktopImage: NSImage? = nil
    @State private var timeOffset: Double = 0.0
    let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()
    
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
            // Actual System Wallpaper Background (blurred)
            if let image = desktopImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .ignoresSafeArea()
                    .blur(radius: 50)
            } else {
                Color.black.ignoresSafeArea()
            }
            
            // Render specific style
            switch style {
            case "dusk":
                DuskSunsetView(primaryColor: primaryColor, secondaryColor: secondaryColor, accentColor: accentColor, timeOffset: timeOffset)
            case "horizon":
                HorizonSunsetView(primaryColor: primaryColor, secondaryColor: secondaryColor, accentColor: accentColor, timeOffset: timeOffset)
            default:
                DuskSunsetView(primaryColor: primaryColor, secondaryColor: secondaryColor, accentColor: accentColor, timeOffset: timeOffset)
            }
        }
        .onAppear {
            loadDesktopImage()
        }
        .onReceive(timer) { _ in
            timeOffset += 0.05
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

// 1. Dusk Style
struct DuskSunsetView: View {
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let timeOffset: Double
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let sunY = height * 0.6 + sin(timeOffset * 0.1) * 20
            
            ZStack {
                // Sky Gradient
                LinearGradient(
                    colors: [
                        primaryColor.opacity(0.8),
                        secondaryColor.opacity(0.6),
                        accentColor.opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Sun
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentColor,
                                accentColor.opacity(0.5),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: width * 0.3
                        )
                    )
                    .frame(width: width * 0.6, height: width * 0.6)
                    .position(x: width * 0.5, y: sunY)
                    .blur(radius: 30)
                
                // Ocean / Foreground reflection
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.4),
                                primaryColor.opacity(0.9)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(height: height * 0.4)
                    .position(x: width * 0.5, y: height * 0.8)
            }
        }
    }
}

// 2. Horizon Style
struct HorizonSunsetView: View {
    let primaryColor: Color
    let secondaryColor: Color
    let accentColor: Color
    let timeOffset: Double
    
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            
            ZStack {
                // Background
                Color.black.ignoresSafeArea()
                
                // Horizon Glow
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                accentColor.opacity(0.8),
                                secondaryColor.opacity(0.4),
                                .clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: width * 0.8
                        )
                    )
                    .frame(width: width * 1.5, height: height * 0.5)
                    .position(x: width * 0.5, y: height * 0.7 + sin(timeOffset * 0.05) * 15)
                    .blur(radius: 40)
                
                // Ground silhouette
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.7))
                    path.addCurve(
                        to: CGPoint(x: width, y: height * 0.65),
                        control1: CGPoint(x: width * 0.3, y: height * 0.6),
                        control2: CGPoint(x: width * 0.7, y: height * 0.75)
                    )
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.addLine(to: CGPoint(x: 0, y: height))
                    path.closeSubpath()
                }
                .fill(primaryColor)
                .opacity(0.9)
            }
        }
    }
}
