import SwiftUI

struct SoundLayerMixerView: View {
    @Bindable var appModel: AppModel
    var isScrollable: Bool = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)
    ]

    var body: some View {
        mixerContent
    }

    @ViewBuilder
    private var mixerContent: some View {
        innerContent
    }

    private var innerContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Ambient Mix", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .textCase(.uppercase)
                        .kerning(1.5)

                    if appModel.playerViewModel.isPlaying {
                        Text("Actively Sculpting Sound")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            appModel.playerViewModel.togglePlayback()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: appModel.playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 14, weight: .bold))

                            if !appModel.playerViewModel.isPlaying {
                                Text("Resume")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background {
                            if reduceTransparency {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.regularMaterial)
                            } else {
                                Color.clear
                                    .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if isScrollable {
                ScrollView {
                    layersGrid
                        .padding(.bottom, 24)
                }
                .scrollIndicators(.visible)
            } else {
                layersGrid
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 24)
        .padding(.top, 8)
    }

    private var layersGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(SoundLayerID.allCases) { layer in
                LayerCard(
                    id: layer.rawValue,
                    volume: Binding(
                        get: { Double(appModel.playerViewModel.layerVolumes[layer.rawValue] ?? 0) },
                        set: { appModel.playerViewModel.setVolume(for: layer.rawValue, volume: Float($0)) }
                    ),
                    icon: layerIcon(for: layer)
                )
            }
        }
    }

    private func layerIcon(for layer: SoundLayerID) -> String {
        switch layer {
        case .rain: return "cloud.rain.fill"
        case .forest: return "leaf.fill"
        case .ocean: return "water.waves"
        case .wind: return "wind"
        case .cafe: return "cup.and.saucer.fill"
        case .brownnoise: return "waveform.path.ecg"
        case .stream: return "drop.fill"
        case .night: return "moon.stars.fill"
        case .crickets: return "ant.fill"
        case .fan: return "fan.fill"
        case .hum: return "cpu"
        case .piano: return "pianokeys"
        case .fire: return "flame.fill"
        case .thunder: return "cloud.bolt.fill"
        case .birds: return "bird.fill"
        case .seaside: return "water.waves"
        case .mountainstream: return "drop.triangle.fill"
        case .tropicalbeach: return "sun.max.fill"
        case .heavyrain: return "cloud.heavyrain.fill"
        }
    }
}

struct LayerCard: View {
    let id: String
    @Binding var volume: Double
    let icon: String

    @State private var isHovered = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        cardContent
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(isHovered ? .regular.interactive() : .clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .onHover { isHovered = $0 }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: volume > 0)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                // Icon without redundant background
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(volume > 0 ? Color.accentColor : .white.opacity(0.4))
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(id.capitalized)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(volume > 0 ? .white : .white.opacity(0.8))
                        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)

                    if volume > 0 {
                        Text("\(Int(volume * 100))%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentColor)
                            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }

                Spacer()
            }

            CustomSlider(value: $volume)
                .frame(height: 6)
        }
        .padding(16)
    }
}

struct CustomSlider: View {
    @Binding var value: Double
    @State private var isDragging = false
    @State private var trackWidth: CGFloat = 0

    private let thumbSize: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            // Track with subtle background
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(0.1))
                .frame(height: 6)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { trackWidth = geometry.size.width }
                            .onChange(of: geometry.size.width) { _, newWidth in
                                trackWidth = newWidth
                            }
                    }
                )

            if trackWidth > 0 {
                let availableWidth = max(0, trackWidth - thumbSize)
                let currentOffset = availableWidth * CGFloat(value)

                // Progress with accent and glow
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: currentOffset + (thumbSize / 2), height: 6)
                    .shadow(color: Color.accentColor.opacity(0.5), radius: 6)

                // Glass Thumb
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(.white)
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .offset(x: currentOffset)
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
                    .scaleEffect(isDragging ? 1.3 : 1.0)
                    .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isDragging)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    isDragging = true
                    if trackWidth > thumbSize {
                        let availableWidth = trackWidth - thumbSize
                        let adjustedX = gesture.location.x - (thumbSize / 2)
                        let newValue = Double(adjustedX / availableWidth)
                        value = min(max(newValue, 0), 1)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
}
