import Combine
import SwiftUI

struct ImmersiveModeView: View {
    @Bindable var appModel: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showControls = true
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var isHoveringControls = false

    var body: some View {
        ZStack {
            backgroundLayer
            contentLayer
        }
        .onContinuousHover { _ in
            if !showControls {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    showControls = true
                }
            }
            // Reset timer
            timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
        }
        .onReceive(timer) { _ in
            if showControls && !isHoveringControls {
                withAnimation(.easeInOut(duration: 1.5)) {
                    showControls = false
                }
            }
        }
    }
    
    @ViewBuilder
    private var backgroundLayer: some View {
        // Subtle tint over the wallpaper that aligns with the current mood
        if let mood = appModel.moodViewModel.currentMood {
            Color(
                red: mood.palette.primary.red,
                green: mood.palette.primary.green,
                blue: mood.palette.primary.blue
            )
            .opacity(0.15)
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 1.0), value: mood.id)
        } else {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
        }
    }
    
    @ViewBuilder
    private var contentLayer: some View {
        VStack {
            Spacer()
            clockSection
            Spacer()
            
            if showControls {
                Group {
                    controlsSection
                }
                .padding(.bottom, 60)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    @ViewBuilder
    private var clockSection: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(context.date, format: .dateTime.hour().minute())
                    .font(.system(size: 120, weight: .thin, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .tracking(4)
                
                Text(context.date, format: .dateTime.weekday(.wide).day().month(.wide))
                    .font(.title.weight(.light))
                    .foregroundStyle(.secondary)
                    .tracking(1)
            }
        }
        .opacity(showControls ? 0.8 : 1.0)
        .scaleEffect(showControls ? 0.95 : 1.0)
        .blur(radius: showControls ? 4 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: showControls)
    }
    
    @ViewBuilder
    private var controlsSection: some View {
        VStack(spacing: 24) {
            statusInfo
            mixerPanel
            exitButton
        }
    }
    
    @ViewBuilder
    private var statusInfo: some View {
        VStack(spacing: 8) {
            Text(currentStatusLabel)
                .font(.title3.weight(.medium))
                .foregroundStyle(.primary)
            
            if let travelPack = appModel.travelEngine.activePack {
                Text(travelPack.label)
                    .font(.headline.weight(.light))
                    .foregroundStyle(.secondary)
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    @ViewBuilder
    private var mixerPanel: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Ambient Mix")
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        appModel.playerViewModel.togglePlayback()
                    }
                } label: {
                    Image(systemName: appModel.playerViewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                        .liquidGlass(Circle(), interactive: true, variant: .regular)
                }
                .buttonStyle(.plain)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(SoundLayerID.allCases) { layer in
                        layerSlider(for: layer)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: 500)
        .padding(24)
        .liquidGlass(RoundedRectangle(cornerRadius: 16, style: .continuous), interactive: false, variant: .regular)
        .shadow(color: .black.opacity(0.15), radius: 30, y: 15)
        .onHover { isHoveringControls = $0 }
    }
    
    @ViewBuilder
    private func layerSlider(for layer: SoundLayerID) -> some View {
        VStack(spacing: 8) {
            Image(systemName: layerIcon(for: layer))
                .font(.title3)
                .foregroundStyle(appModel.playerViewModel.layerVolumes[layer.rawValue] ?? 0 > 0 ? Color.accentColor : .secondary)
            
            Slider(value: Binding(
                get: { Double(appModel.playerViewModel.layerVolumes[layer.rawValue] ?? 0) },
                set: { appModel.playerViewModel.setVolume(for: layer.rawValue, volume: Float($0)) }
            ), in: 0...1)
            .frame(width: 80)
            .controlSize(.mini)
        }
    }
    
    @ViewBuilder
    private var exitButton: some View {
        Button(action: { 
            withAnimation {
                appModel.showImmersive = false 
            }
        }) {
            Label("Exit Immersive Mode", systemImage: "arrow.down.right.and.arrow.up.left")
                .font(.subheadline.bold())
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .liquidGlass(RoundedRectangle(cornerRadius: 8, style: .continuous), interactive: true, variant: .clear)
        }
        .buttonStyle(.plain)
    }
    
    private var currentStatusLabel: String {
        if let playlist = appModel.playlistViewModel.statePlaylist {
            return "Playlist: \(playlist.name)"
        }
        return appModel.moodViewModel.currentMood?.name ?? "Aura"
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
        case .crickets: return "sparkles"
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

extension PlaylistViewModel {
    var statePlaylist: Playlist? {
        switch state {
        case .playing(let p, _), .paused(let p, _):
            return p
        default:
            return nil
        }
    }
}
