import AVFoundation
import SwiftUI

struct TravelView: View {
    @Bindable var appModel: AppModel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                headerView
                
                TravelSelectorView(appModel: appModel)
                    .frame(height: 200)
                
                if appModel.travelEngine.activePack != nil {
                    SoundLayerMixerView(appModel: appModel, isScrollable: false)
                        .padding(24)
                        .padding(.top, 32)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 32)
                        .frame(maxWidth: 1200)
                } else {
                    ContentUnavailableView(
                        "Select a Destination",
                        systemImage: "airplane.circle",
                        description: Text("Choose a location above to start your journey.")
                    )
                    .padding(.top, 100)
                    .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    private var headerView: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Travel Mode")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .textCase(.uppercase)
                    .kerning(1.5)
                
                Text(appModel.travelEngine.activePack?.name ?? "Ready for Departure")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    Task { await appModel.travelEngine.shuffle() }
                }) {
                    Label("Random", systemImage: "shuffle")
                        .font(.headline)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background {
                            if reduceTransparency {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(.regularMaterial)
                            } else {
                                Color.clear
                                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                
                if appModel.travelEngine.activePack != nil {
                    Button(action: {
                        appModel.showImmersive = true
                    }) {
                        Label("Immersive", systemImage: "macwindow.on.rectangle")
                            .font(.headline)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background {
                                if reduceTransparency {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(.regularMaterial)
                                } else {
                                    Color.clear
                                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
        .padding(.bottom, 16)
    }
}
