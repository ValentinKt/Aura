import re
import sys

def main():
    with open('/Users/valentin/XCode/Aura/Aura/Views/ZenWallpaperView.swift', 'r') as f:
        content = f.read()

    # MandalaZenView
    content = re.sub(
        r'struct MandalaZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct MandalaZenView: View {
    let primaryColor: Color
    let accentColor: Color
    @Environment(\\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<8, id: \\.self) { index in
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
}''',
        content, flags=re.DOTALL
    )

    # RippleZenView
    content = re.sub(
        r'struct RippleZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct RippleZenView: View {
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
}''',
        content, flags=re.DOTALL
    )

    # OrbZenView
    content = re.sub(
        r'struct OrbZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct OrbZenView: View {
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
}''',
        content, flags=re.DOTALL
    )

    # LotusZenView
    content = re.sub(
        r'struct LotusZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct LotusZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()

            ZStack {
                ForEach(0..<12, id: \\.self) { index in
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
}''',
        content, flags=re.DOTALL
    )

    # EclipseZenView
    content = re.sub(
        r'struct EclipseZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct EclipseZenView: View {
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
}''',
        content, flags=re.DOTALL
    )

    # GalaxyZenView
    content = re.sub(
        r'struct GalaxyZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct GalaxyZenView: View {
    let primaryColor: Color
    let accentColor: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            ZStack {
                ForEach(0..<4, id: \\.self) { i in
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
}''',
        content, flags=re.DOTALL
    )

    # PendulumZenView
    content = re.sub(
        r'struct PendulumZenView.*?\.onAppear \{.*?\n\s*\}\n\s*\}\n\}',
        '''struct PendulumZenView: View {
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
}''',
        content, flags=re.DOTALL
    )
    
    with open('/Users/valentin/XCode/Aura/Aura/Views/ZenWallpaperView.swift', 'w') as f:
        f.write(content)

if __name__ == '__main__':
    main()