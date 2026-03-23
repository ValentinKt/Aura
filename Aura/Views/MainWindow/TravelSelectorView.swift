import SwiftUI
import AVFoundation

struct TravelSelectorView: View {
    @Bindable var appModel: AppModel
    
    var body: some View {
        ZStack {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer {
                        LazyHStack(spacing: 20) {
                            ForEach(appModel.travelEngine.packs, id: \.id) { pack in
                                TravelCard(
                                    pack: pack,
                                    isSelected: appModel.travelEngine.activePack?.id == pack.id,
                                    action: { selectPack(pack) }
                                )
                                .id(pack.id)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 10)
                    }
                }
                .scrollClipDisabled()
                .contentMargins(.horizontal, 40, for: .scrollContent)
                .onChange(of: appModel.travelEngine.activePack) { oldPack, newPack in
                    if let packId = newPack?.id {
                        withAnimation {
                            proxy.scrollTo(packId, anchor: .center)
                        }
                    }
                }
            }
            
            // Navigation Arrows
            HStack {
                // Previous Button
                Button(action: selectPreviousPack) {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.75))
                        .shadow(color: .black.opacity(0.3), radius: 10)
                }
                .buttonStyle(.plain)
                .padding(.leading, 12)
                .opacity(canSelectPrevious ? 1 : 0)
                .animation(.spring(), value: canSelectPrevious)
                
                Spacer()
                
                // Next Button
                Button(action: selectNextPack) {
                    Image(systemName: "chevron.right.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.white.opacity(0.75))
                        .shadow(color: .black.opacity(0.3), radius: 10)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
                .opacity(canSelectNext ? 1 : 0)
                .animation(.spring(), value: canSelectNext)
            }
            .allowsHitTesting(true)
        }
        .frame(maxWidth: .infinity)
        // Keyboard Navigation
        .background(
            Button("") {
                selectPreviousPack()
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            .opacity(0)
        )
        .background(
            Button("") {
                selectNextPack()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .opacity(0)
        )
    }
    
    private var currentIndex: Int? {
        guard let currentId = appModel.travelEngine.activePack?.id else { return nil }
        return appModel.travelEngine.packs.firstIndex { $0.id == currentId }
    }
    
    private var canSelectPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }
    
    private var canSelectNext: Bool {
        guard let index = currentIndex else { return false }
        return index < appModel.travelEngine.packs.count - 1
    }
    
    private func selectPreviousPack() {
        guard let index = currentIndex, index > 0 else { return }
        let prevPack = appModel.travelEngine.packs[index - 1]
        selectPack(prevPack)
    }
    
    private func selectNextPack() {
        guard let index = currentIndex, index < appModel.travelEngine.packs.count - 1 else { return }
        let nextPack = appModel.travelEngine.packs[index + 1]
        selectPack(nextPack)
    }
    
    private func selectPack(_ pack: TravelLocationPack) {
        guard appModel.travelEngine.activePack?.id != pack.id else { return }
        Task {
            await appModel.travelEngine.apply(pack)
        }
    }
}

struct TravelCard: View {
    let pack: TravelLocationPack
    let isSelected: Bool
    let action: () -> Void
    
    @State private var image: NSImage?
    @State private var isHovered = false
    @State private var isPressed = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                // Background Image
                if let image = image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 240, height: 160)
                        .clipped()
                } else {
                    Group {
                        if reduceTransparency {
                            Rectangle()
                                .fill(.regularMaterial)
                        } else {
                            Color.clear
                                .glassEffect(.regular, in: Rectangle())
                        }
                    }
                    .frame(width: 240, height: 160)
                    .overlay {
                        Circle()
                            .trim(from: 0, to: 0.7)
                            .stroke(Color.white.opacity(0.5), lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .rotationEffect(Angle(degrees: isPressed ? 360 : 0))
                            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: true)
                    }
                }
                
                // Selection and Hover Overlay
                LinearGradient(
                    colors: [
                        .clear,
                        .black.opacity(isSelected ? 0.3 : (isHovered ? 0.4 : 0.5))
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Selection highlight
                if isSelected {
                    Color.accentColor.opacity(0.1)
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if isSelected {
                                Image(systemName: "location.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color.accentColor)
                                    .symbolEffect(.bounce, value: isSelected)
                            }
                            
                            Text(pack.name)
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                        
                        if isSelected {
                            Text("Currently Exploring")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        } else {
                            Text(pack.label)
                                .font(.system(size: 9))
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(.white.opacity(0.1))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    }
                }
                .padding(14)
            }
            .frame(width: 240, height: 160)
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor.opacity(0.8), lineWidth: 2)
                }
            }
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.regularMaterial)
                } else {
                    Color.clear
                        .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(isSelected ? 0.3 : 0.15), radius: isSelected ? 20 : 10, y: 10)
            .scaleEffect(isPressed ? 0.95 : (isHovered ? 1.05 : 1.0))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .animation(.spring(response: 0.2, dampingFraction: 0.8), value: isPressed)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .task {
            await loadPreview()
        }
    }
    
    @MainActor
    private func loadPreview() async {
        guard let resource = pack.wallpaper.resources.first else { return }
        
        let loadedImage = await Task.detached(priority: .userInitiated) { () -> NSImage? in
            guard let url = MediaUtils.resolveResourceURL(resource) else {
                return NSImage(named: resource)
            }
            
            if ["mp4", "mov"].contains(url.pathExtension.lowercased()) {
                return await MediaUtils.videoPosterImage(from: url)
            } else if let img = NSImage(contentsOf: url) {
                return img
            }
            return NSImage(named: resource)
        }.value
        
        withAnimation {
            self.image = loadedImage
        }
    }
}
