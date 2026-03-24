import AppKit
import Darwin

final class AppDelegate: NSObject, NSApplicationDelegate {
    var appModel: AppModel?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Disable state restoration early to avoid com.apple.appkit.restoration_storage errors
        UserDefaults.standard.register(defaults: [
            "NSQuitAlwaysKeepsWindows": false,
            "NSPersistentUIEnabled": false,
            "ApplePersistenceIgnoreState": true
        ])
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(false, forKey: "NSPersistentUIEnabled")
        UserDefaults.standard.set(true, forKey: "ApplePersistenceIgnoreState")

        print("🟢 [AppDelegate] applicationWillFinishLaunching")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🟢 [AppDelegate] applicationDidFinishLaunching")
        // Disable state restoration to prevent "com.apple.appkit.restoration_storage" errors
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        UserDefaults.standard.set(false, forKey: "NSPersistentUIEnabled")

        // Remove existing restoration data if any
        if let bundleID = Bundle.main.bundleIdentifier {
            let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            let restorationDir = library.appendingPathComponent("Saved Application State/\(bundleID).savedState")
            try? FileManager.default.removeItem(at: restorationDir)
        }

        // Ensure any existing windows are not restorable and handle transparency
        for window in NSApp.windows {
            window.isRestorable = false
            if window.identifier?.rawValue == "main" {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.titlebarAppearsTransparent = true
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        var didReopen = false

        for window in NSApp.windows where window.identifier?.rawValue == "main" {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            didReopen = true
        }

        // If the window was completely closed, we should broadcast a notification
        // so that AuraApp can catch it and use openWindow(id: "main")
        if !didReopen && !flag {
            NotificationCenter.default.post(name: Notification.Name("ReopenMainWindow"), object: nil)
        }

        return true
    }
}
