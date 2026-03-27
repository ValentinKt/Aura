//
//  AuraApp.swift
//  Aura
//
//  Created by Valentin on 3/13/26.
//

import SwiftUI
import AppKit
import AppIntents
import os

@main
struct AuraApp: App {
    @State private var appModel = AppModel.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.app.info("🟢 [AuraApp] Initialization started")

        // Disable state restoration to prevent NSPersistentUIRemoteStorage errors
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false,
            "NSPersistentUIEnabled": false,
            "ApplePersistenceIgnoreState": true,
            "CoreMediaAirPlayEnabled": false, // Try to disable AirPlay from CoreMedia
            "AVFoundationDisableAirPlay": true
        ])
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(false, forKey: "NSPersistentUIEnabled")
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")

        Logger.app.info("🟢 [AuraApp] State restoration disabled")

        // Remove any previously saved restoration data
        if let bundleID = Bundle.main.bundleIdentifier,
           let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
            let restorationDir = library.appendingPathComponent("Saved Application State/\(bundleID).savedState")
            try? FileManager.default.removeItem(at: restorationDir)
        }
    }

    var body: some Scene {
        Window("Aura", id: "main") {
            ZStack {
                if appModel.isReady {
                    ContentView()
                        .environment(appModel)
                } else {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading Aura...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // We need to provide the environment to the progress view too,
                    // or just the whole ZStack.
                }
            }
            .environment(appModel)
            .onAppear {
                appDelegate.appModel = appModel
                for window in NSApp.windows {
                    window.isRestorable = false
                }
            }
            .task {
                await appModel.startIfNeeded()
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Aura") {
                Button(appModel.playerViewModel.isPlaying ? "Pause" : "Play") {
                    appModel.playerViewModel.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: .command)

                Button("Next Mood") {
                    let moods = appModel.moodViewModel.moods
                    if let current = appModel.moodViewModel.currentMood,
                       let index = moods.firstIndex(where: { $0.id == current.id }) {
                        let next = moods[(index + 1) % moods.count]
                        appModel.moodViewModel.selectMood(next)
                    } else if let first = moods.first {
                        appModel.moodViewModel.selectMood(first)
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Mood") {
                    let moods = appModel.moodViewModel.moods
                    if let current = appModel.moodViewModel.currentMood,
                       let index = moods.firstIndex(where: { $0.id == current.id }) {
                        let previous = moods[(index - 1 + moods.count) % moods.count]
                        appModel.moodViewModel.selectMood(previous)
                    } else if let first = moods.first {
                        appModel.moodViewModel.selectMood(first)
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Button("Toggle Immersive Mode") {
                    appModel.showImmersive.toggle()
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Button("Open Command Palette") {
                    appModel.showCommandPalette.toggle()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarPopoverView(appModel: appModel)
        } label: {
            Image(systemName: "circle")
                .font(.system(size: 24))
        }
        .menuBarExtraStyle(.window)
    }
}

struct AuraShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor = .blue

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDeepFocusJourneyIntent(),
            phrases: [
                "Start Deep Focus Journey in \(.applicationName)",
                "Begin Deep Focus in \(.applicationName)"
            ],
            shortTitle: "Deep Focus Journey",
            systemImageName: "brain.head.profile"
        )
        AppShortcut(
            intent: SwitchToWindDownIntent(),
            phrases: [
                "Switch to Wind Down in \(.applicationName)",
                "Wind down with \(.applicationName)"
            ],
            shortTitle: "Switch to Wind Down",
            systemImageName: "moon.zzz.fill"
        )
        AppShortcut(
            intent: SetZenBreathModeIntent(),
            phrases: [
                "Set Zen Breath Mode in \(.applicationName)",
                "Start Zen Breath Mode in \(.applicationName)"
            ],
            shortTitle: "Zen Breath Mode",
            systemImageName: "wind"
        )
    }
}

struct StartDeepFocusJourneyIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Deep Focus Journey"
    static let description = IntentDescription("Starts Aura with the first Deep Focus mood and opens immersive mode.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.performShortcut(.deepFocusJourney)
        return .result(dialog: "Aura started your Deep Focus Journey.")
    }
}

struct SwitchToWindDownIntent: AppIntent {
    static let title: LocalizedStringResource = "Switch to Wind Down"
    static let description = IntentDescription("Switches Aura to the first Rest mood for a wind-down session.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.performShortcut(.windDown)
        return .result(dialog: "Aura switched to Wind Down.")
    }
}

struct SetZenBreathModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Zen Breath Mode"
    static let description = IntentDescription("Sets Aura to the breathing-based Zen mode and opens immersive mode.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await AppModel.shared.performShortcut(.zenBreathMode)
        return .result(dialog: "Aura is now in Zen Breath Mode.")
    }
}
