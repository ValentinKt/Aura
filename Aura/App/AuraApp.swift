//
//  AuraApp.swift
//  Aura
//
//  Created by Valentin on 3/13/26.
//

import SwiftUI
import AppKit

@main
struct AuraApp: App {
    @State private var appModel = AppModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Disable os_log to fix "Logging Error: Failed to receive 1 log messages"
        setenv("OS_ACTIVITY_MODE", "disable", 1)

        print("🟢 [AuraApp] Initialization started")

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

        print("🟢 [AuraApp] State restoration disabled")

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

                // Ensure any existing windows are not restorable
                for window in NSApp.windows {
                    window.isRestorable = false
                }
            }
            .task {
                await appModel.start()
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
