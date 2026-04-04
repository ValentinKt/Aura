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
        .defaultSize(width: 1050, height: 900)
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
            intent: LaunchAuraSceneIntent(),
            phrases: [
                "Launch a scene in \(.applicationName)",
                "Start an Aura scene in \(.applicationName)"
            ],
            shortTitle: "Launch Scene",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: ResumeAuraSceneIntent(),
            phrases: [
                "Resume my last scene in \(.applicationName)",
                "Quick resume in \(.applicationName)"
            ],
            shortTitle: "Resume Scene",
            systemImageName: "arrow.clockwise"
        )
        AppShortcut(
            intent: StartAuraSleepTimerIntent(),
            phrases: [
                "Start an Aura sleep timer in \(.applicationName)",
                "Set Aura timer in \(.applicationName)"
            ],
            shortTitle: "Sleep Timer",
            systemImageName: "timer"
        )
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
    }
}

struct AuraSceneNameOptionsProvider: DynamicOptionsProvider {
    func results() async throws -> [String] {
        await MainActor.run {
            AppModel.shared.availableAutomationScenes().map(\.name)
        }
    }
}

struct LaunchAuraSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Launch Aura Scene"
    static let description = IntentDescription("Launches any Aura scene so it can be triggered from Shortcuts automations such as Focus, time, location, or calendar events.")
    static let openAppWhenRun = true

    @Parameter(title: "Scene", optionsProvider: AuraSceneNameOptionsProvider())
    var sceneName: String

    @Parameter(title: "Immersive Mode", default: true)
    var immersiveMode: Bool

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mood = try await AppModel.shared.launchScene(named: sceneName, immersive: immersiveMode, resumePlayback: true)
        return .result(dialog: "Aura launched \(mood.name).")
    }
}

struct ResumeAuraSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Resume Last Aura Scene"
    static let description = IntentDescription("Restarts the most recent Aura scene for quick resume from Shortcuts or Focus automations.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let mood = try await AppModel.shared.resumeLastScene()
        return .result(dialog: "Aura resumed \(mood.name).")
    }
}

struct StartAuraSleepTimerIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Aura Sleep Timer"
    static let description = IntentDescription("Starts or updates Aura's sleep timer so audio pauses automatically after the selected delay.")
    static let openAppWhenRun = true

    @Parameter(title: "Minutes", default: 30)
    var minutes: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        AppModel.shared.startSleepTimer(minutes: minutes)
        return .result(dialog: "Aura sleep timer set for \(minutes) minutes.")
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
