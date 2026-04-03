import SwiftUI
import Combine

struct TimeWallpaperView: View {
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

    private var needsSeconds: Bool {
        ["analog", "binary", "orbit", "neon"].contains(style)
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

            if selectedWallpaperURL != nil {
                Color.black.opacity(0.18).ignoresSafeArea()
            }

            Group {
                if needsSeconds {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        timeContent(date: context.date)
                    }
                } else {
                    TimelineView(.everyMinute) { context in
                        timeContent(date: context.date)
                    }
                }
            }
            .drawingGroup()
        }
        .task(id: backgroundTaskKey) {
            await loadBackgroundImage()
        }
    }

    @ViewBuilder
    private func timeContent(date currentTime: Date) -> some View {
        switch style {
        case "minimal":
            MinimalTimeView(date: currentTime, color: accentColor)
        case "analog":
            AnalogTimeView(date: currentTime, color: accentColor, secondaryColor: secondaryColor)
        case "typographic":
            TypographicTimeView(date: currentTime, color: accentColor)
        case "binary":
            BinaryTimeView(date: currentTime, color: accentColor, inactiveColor: primaryColor.opacity(0.3))
        case "solar":
            SolarTimeView(date: currentTime, skyColor: primaryColor, sunColor: accentColor)
        case "glass_blocks":
            GlassBlocksTimeView(date: currentTime, color: accentColor)
        case "words":
            WordsTimeView(date: currentTime, color: accentColor)
        case "orbit":
            OrbitTimeView(date: currentTime, color: accentColor)
        case "neon":
            NeonTimeView(date: currentTime, color: accentColor)
        case "fluid":
            FluidTimeView(date: currentTime, color: accentColor)
        default:
            MinimalTimeView(date: currentTime, color: accentColor)
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

// 1. Minimal Style
struct MinimalTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var secondString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ss"
        return formatter.string(from: date)
    }

    var body: some View {
        Group {
            if !reduceTransparency {
                timeContent
                    .glassEffect(.regular.tint(color.opacity(0.15)), in: RoundedRectangle(cornerRadius: 60, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 60, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                    )
            } else {
                timeContent
                    .background {
                        RoundedRectangle(cornerRadius: 60, style: .continuous)
                            .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.2))
                            .overlay(RoundedRectangle(cornerRadius: 60, style: .continuous).stroke(color.opacity(0.4), lineWidth: 1))
                    }
            }
        }
        .scaleEffect(1.02)
    }

    private var timeContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(timeString)
                .font(.system(size: 220, weight: .ultraLight, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: color.opacity(0.4), radius: 20, x: 0, y: 10)

            Text(secondString)
                .font(.system(size: 80, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .shadow(color: color.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 50)
    }
}

// 2. Analog Style
struct AnalogTimeView: View {
    let date: Date
    let color: Color
    let secondaryColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.7
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
            let hour = Double(components.hour! % 12)
            let minute = Double(components.minute!)
            let second = Double(components.second!)

            ZStack {
                // Glass Base
                if !reduceTransparency {
                    Color.clear
                        .glassEffect(.regular.tint(secondaryColor.opacity(0.15)), in: Circle())
                        .frame(width: size, height: size)
                        .shadow(color: color.opacity(0.3), radius: 60, x: 0, y: 30)
                        .overlay(
                            Circle()
                                .stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                        )
                } else {
                    Circle()
                        .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : secondaryColor.opacity(0.2))
                        .frame(width: size, height: size)
                        .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
                }

                // Outer Glow Ring
                Circle()
                    .stroke(
                        LinearGradient(colors: [color.opacity(0.8), secondaryColor.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 2
                    )
                    .frame(width: size - 8, height: size - 8)
                    .blur(radius: 2)

                // Inner Glass Ring
                if !reduceTransparency {
                    Color.clear
                        .glassEffect(.regular, in: Circle())
                        .frame(width: size * 0.85, height: size * 0.85)
                        .opacity(0.6)
                }

                // Ticks
                ForEach(0..<60) { tick in
                    let isHour = tick % 5 == 0
                    Capsule()
                        .fill(isHour ? .primary : color.opacity(0.4))
                        .frame(width: isHour ? 4 : 2, height: isHour ? 24 : 8)
                        .offset(y: -size / 2 + (isHour ? 32 : 16))
                        .rotationEffect(.degrees(Double(tick) * 6))
                        .shadow(color: isHour ? color.opacity(0.6) : .clear, radius: isHour ? 6 : 0)
                }

                // Hour Hand
                Capsule()
                    .fill(LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 10, height: size * 0.25)
                    .offset(y: -size * 0.125)
                    .rotationEffect(.degrees((hour + minute / 60) * 30))
                    .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)

                // Minute Hand
                Capsule()
                    .fill(LinearGradient(colors: [.primary, .primary.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 6, height: size * 0.38)
                    .offset(y: -size * 0.19)
                    .rotationEffect(.degrees((minute + second / 60) * 6))
                    .shadow(color: color.opacity(0.5), radius: 8, x: 0, y: 4)

                // Second Hand (Sweeping)
                ZStack {
                    Capsule()
                        .fill(color)
                        .frame(width: 3, height: size * 0.45)
                        .offset(y: -size * 0.18)

                    // Counterweight
                    Circle()
                        .fill(color)
                        .frame(width: 12, height: 12)
                        .offset(y: size * 0.05)
                }
                .rotationEffect(.degrees(second * 6))
                .shadow(color: color, radius: 10, x: 0, y: 0)

                // Center dot
                Circle()
                    .fill(.primary)
                    .frame(width: 16, height: 16)
                    .overlay(Circle().stroke(color, lineWidth: 3))
                    .shadow(color: .black.opacity(0.3), radius: 5)
            }
            .position(center)
        }
    }
}

// 3. Typographic Style
struct TypographicTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        let parts = timeString.split(separator: ":")
        let hour = String(parts[0])
        let minute = String(parts[1])

        VStack(spacing: -120) {
            Text(hour)
                .font(.system(size: 340, weight: .heavy, design: .rounded))
                .foregroundStyle(.primary)
                .shadow(color: color.opacity(0.3), radius: 20, x: 0, y: 10)
                .zIndex(2)

            Text(minute)
                .font(.system(size: 340, weight: .black, design: .rounded))
                .foregroundStyle(.secondary)
                .blendMode(.overlay)
                .shadow(color: color.opacity(0.2), radius: 15, x: 0, y: 8)
                .zIndex(1)
        }
        .padding(80)
        .background {
            if !reduceTransparency {
                Color.clear
                    .glassEffect(.regular.tint(color.opacity(0.1)), in: RoundedRectangle(cornerRadius: 80, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 80, style: .continuous)
                            .stroke(LinearGradient(colors: [.white.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                    )
            } else {
                RoundedRectangle(cornerRadius: 80, style: .continuous)
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.15))
            }
        }
        .rotationEffect(.degrees(-4))
        .scaleEffect(1.05)
    }
}

// 4. Binary Style
struct BinaryTimeView: View {
    let date: Date
    let color: Color
    let inactiveColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)

        Group {
            if !reduceTransparency {
                HStack(spacing: 60) {
                    BinaryColumn(title: "HR", value: components.hour!, bits: 5, activeColor: color, inactiveColor: inactiveColor)
                    BinaryColumn(title: "MIN", value: components.minute!, bits: 6, activeColor: color, inactiveColor: inactiveColor)
                    BinaryColumn(title: "SEC", value: components.second!, bits: 6, activeColor: color, inactiveColor: inactiveColor)
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 80)
                .background {
                    Color.clear
                        .glassEffect(.regular.tint(color.opacity(0.1)), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .stroke(LinearGradient(colors: [color.opacity(0.6), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2)
                )
            } else {
                HStack(spacing: 60) {
                    BinaryColumn(title: "HR", value: components.hour!, bits: 5, activeColor: color, inactiveColor: inactiveColor)
                    BinaryColumn(title: "MIN", value: components.minute!, bits: 6, activeColor: color, inactiveColor: inactiveColor)
                    BinaryColumn(title: "SEC", value: components.second!, bits: 6, activeColor: color, inactiveColor: inactiveColor)
                }
                .padding(.horizontal, 100)
                .padding(.vertical, 80)
                .background {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.15))
                        .background(RoundedRectangle(cornerRadius: 40, style: .continuous).stroke(color.opacity(0.4), lineWidth: 1))
                }
            }
        }
    }
}

struct BinaryColumn: View {
    let title: String
    let value: Int
    let bits: Int
    let activeColor: Color
    let inactiveColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 20) {
            Text(title)
                .font(.system(size: 24, weight: .black, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(.bottom, 16)
                .shadow(color: activeColor.opacity(0.4), radius: 8)

            ForEach((0..<bits).reversed(), id: \.self) { bit in
                let isOn = (value & (1 << bit)) != 0

                if reduceTransparency {
                    Capsule()
                        .fill(isOn ? activeColor : inactiveColor)
                        .frame(width: 60, height: 24)
                } else {
                    ZStack {
                        Capsule()
                            .fill(isOn ? activeColor.opacity(0.8) : inactiveColor.opacity(0.2))
                            .frame(width: 64, height: 24)
                            .overlay(
                                Capsule()
                                    .stroke(isOn ? .white.opacity(0.8) : inactiveColor.opacity(0.3), lineWidth: isOn ? 1.5 : 1)
                            )
                            .shadow(color: isOn ? activeColor.opacity(0.6) : .clear, radius: 10)

                        if isOn {
                            Capsule()
                                .fill(.white)
                                .frame(width: 40, height: 6)
                                .blur(radius: 3)
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
                }
            }
        }
    }
}

// 5. Solar Style
struct SolarTimeView: View {
    let date: Date
    let skyColor: Color
    let sunColor: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute], from: date)
            let hour = Double(components.hour!)
            let minute = Double(components.minute!)
            let totalHours = hour + minute / 60.0

            let isDay = totalHours > 6 && totalHours < 18
            let activeSunColor = isDay ? sunColor : .white

            // Map 0-24 hours to a horizontal position
            let xPos = geometry.size.width * CGFloat(totalHours / 24.0)

            // Map 0-24 hours to a vertical arc (highest at 12:00)
            let normalizedTime = (totalHours - 12.0) / 12.0 // -1 to 1
            let yPos = geometry.size.height * 0.8 - (geometry.size.height * 0.6 * CGFloat(1.0 - pow(normalizedTime, 2)))

            ZStack {
                // Dynamic Sky Background
                LinearGradient(
                    colors: [
                        isDay ? skyColor.opacity(0.9) : .black.opacity(0.95),
                        isDay ? sunColor.opacity(0.6) : skyColor.opacity(0.4),
                        isDay ? sunColor.opacity(0.2) : skyColor.opacity(0.1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Stars (only visible at night)
                if !isDay {
                    StarsView()
                }

                // Solar/Lunar Path Arc (Subtle)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height * 0.8))
                    path.addQuadCurve(
                        to: CGPoint(x: geometry.size.width, y: geometry.size.height * 0.8),
                        control: CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.2)
                    )
                }
                .stroke(style: StrokeStyle(lineWidth: 2, dash: [10, 20]))
                .foregroundStyle(LinearGradient(colors: [.clear, .white.opacity(0.3), .clear], startPoint: .leading, endPoint: .trailing))

                // The Sun / Moon
                ZStack {
                    Circle()
                        .fill(activeSunColor)
                        .frame(width: 160, height: 160)
                        .shadow(color: activeSunColor.opacity(0.6), radius: 40, x: 0, y: 0)
                        .shadow(color: activeSunColor.opacity(0.3), radius: 80, x: 0, y: 0)

                    if isDay {
                        Circle()
                            .fill(.white.opacity(0.8))
                            .frame(width: 120, height: 120)
                            .blur(radius: 15)
                            .blendMode(.screen)
                    } else {
                        // Moon craters/texture suggestion
                        Circle()
                            .fill(.white.opacity(0.15))
                            .frame(width: 30, height: 30)
                            .offset(x: -25, y: -15)
                            .blur(radius: 4)
                        Circle()
                            .fill(.white.opacity(0.1))
                            .frame(width: 45, height: 45)
                            .offset(x: 15, y: 20)
                            .blur(radius: 6)
                    }
                }
                .position(x: xPos, y: yPos)

                // Horizon line (Glass Shelf)
                if !reduceTransparency {
                    Color.clear
                        .glassEffect(.regular.tint(skyColor.opacity(0.2)), in: Rectangle())
                        .frame(height: geometry.size.height * 0.35)
                        .overlay(
                            Rectangle()
                                .fill(LinearGradient(colors: [.white.opacity(0.3), .clear], startPoint: .top, endPoint: .bottom))
                                .frame(height: 2)
                            , alignment: .top
                        )
                        .shadow(color: skyColor.opacity(0.3), radius: 20, x: 0, y: -5)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.825)
                } else {
                    Rectangle()
                        .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : skyColor.opacity(0.4))
                        .frame(height: geometry.size.height * 0.35)
                        .overlay(Rectangle().fill(.white.opacity(0.15)).frame(height: 1), alignment: .top)
                        .position(x: geometry.size.width / 2, y: geometry.size.height * 0.825)
                }
            }
        }
    }
}

struct StarsView: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(0..<80, id: \.self) { i in
                    let seed = UInt64(i + 42)
                    let size = CGFloat(pseudoRandom(seed: seed, range: 1.0...3.0))
                    let opacity = pseudoRandom(seed: seed + 100, range: 0.3...0.8)
                    let x = CGFloat(pseudoRandom(seed: seed + 200, range: 0.0...Double(geometry.size.width)))
                    let y = CGFloat(pseudoRandom(seed: seed + 300, range: 0.0...Double(geometry.size.height * 0.6)))

                    Circle()
                        .fill(.white.opacity(opacity))
                        .frame(width: size, height: size)
                        .position(x: x, y: y)
                }
            }
        }
    }

    private func pseudoRandom(seed: UInt64, range: ClosedRange<Double>) -> Double {
        // Simple hash-based pseudo-random generator
        var x = seed
        x ^= x &<< 21
        x ^= x &>> 35
        x ^= x &<< 4
        let fraction = Double(x) / Double(UInt64.max)
        return range.lowerBound + fraction * (range.upperBound - range.lowerBound)
    }
}

// 6. Glass Blocks Style
struct GlassBlocksTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmm"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Array(timeString.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: 160, height: 220)
                    .background {
                        if !reduceTransparency {
                            Color.clear
                                .glassEffect(.regular.tint(color.opacity(0.15)), in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .stroke(LinearGradient(colors: [.white.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: 30, style: .continuous)
                                .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.2))
                                .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(color.opacity(0.4), lineWidth: 1))
                        }
                    }
                    .shadow(color: color.opacity(0.3), radius: 15, x: 0, y: 10)

                if index == 1 {
                    VStack(spacing: 30) {
                        Circle().fill(.primary).frame(width: 20, height: 20)
                        Circle().fill(.primary).frame(width: 20, height: 20)
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
    }
}

// 7. Words Style
struct WordsTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    var body: some View {
        Text(timeString.uppercased())
            .font(.system(size: 180, weight: .black, design: .serif))
            .foregroundStyle(LinearGradient(colors: [.primary, color], startPoint: .topLeading, endPoint: .bottomTrailing))
            .shadow(color: color.opacity(0.5), radius: 30, x: 0, y: 15)
            .padding(60)
            .background {
                if !reduceTransparency {
                    Color.clear
                        .glassEffect(.regular.tint(color.opacity(0.1)), in: RoundedRectangle(cornerRadius: 40, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 40, style: .continuous)
                        .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.15))
                }
            }
    }
}

// 8. Orbit Style
struct OrbitTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) * 0.6
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            let calendar = Calendar.current
            let components = calendar.dateComponents([.hour, .minute, .second], from: date)
            let hour = Double(components.hour! % 12)
            let minute = Double(components.minute!)
            let second = Double(components.second!)

            ZStack {
                // Sun (Center)
                Circle()
                    .fill(LinearGradient(colors: [color, .white], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 80, height: 80)
                    .shadow(color: color, radius: 40)

                // Hour Orbit
                OrbitRing(radius: size * 0.4, color: color)
                OrbitPlanet(radius: size * 0.4, angle: (hour + minute / 60) * 30, size: 40, color: color.opacity(0.8))

                // Minute Orbit
                OrbitRing(radius: size * 0.7, color: color)
                OrbitPlanet(radius: size * 0.7, angle: (minute + second / 60) * 6, size: 25, color: color.opacity(0.6))

                // Second Orbit
                OrbitRing(radius: size, color: color)
                OrbitPlanet(radius: size, angle: second * 6, size: 15, color: color.opacity(0.4))
            }
            .position(center)
        }
    }
}

struct OrbitRing: View {
    let radius: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: 2, dash: [5, 10]))
            .frame(width: radius * 2, height: radius * 2)
    }
}

struct OrbitPlanet: View {
    let radius: CGFloat
    let angle: Double
    let size: CGFloat
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .shadow(color: color, radius: 10)
            .offset(y: -radius)
            .rotationEffect(.degrees(angle))
    }
}

// 9. Neon Style
struct NeonTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    var body: some View {
        Text(timeString)
            .font(.system(size: 160, weight: .light, design: .monospaced))
            .foregroundStyle(.white)
            .shadow(color: color, radius: 5, x: 0, y: 0)
            .shadow(color: color, radius: 20, x: 0, y: 0)
            .shadow(color: color, radius: 40, x: 0, y: 0)
            .padding(60)
            .background {
                if !reduceTransparency {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(color, lineWidth: 4)
                        .shadow(color: color, radius: 20)
                        .glassEffect(.regular.tint(color.opacity(0.05)), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(color, lineWidth: 4)
                        .background(Color.black.opacity(0.5))
                        .shadow(color: color, radius: 20)
                }
            }
    }
}

// 10. Fluid Style
struct FluidTimeView: View {
    let date: Date
    let color: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            if !reduceTransparency {
                Color.clear
                    .glassEffect(.regular.tint(color.opacity(0.2)), in: Capsule())
                    .frame(width: 600, height: 250)
                    .shadow(color: color.opacity(0.4), radius: 50, x: 0, y: 20)
            } else {
                Capsule()
                    .fill(reduceTransparency ? Color(nsColor: .windowBackgroundColor) : color.opacity(0.3))
                    .frame(width: 600, height: 250)
            }

            Text(timeString)
                .font(.system(size: 180, weight: .medium, design: .rounded))
                .foregroundStyle(LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                .blendMode(.overlay)
        }
    }
}
