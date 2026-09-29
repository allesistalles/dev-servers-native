import AppKit
import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        DevServersApp.main()
    }
}

struct DevServersApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        FontLoader.registerBundledFonts()
        Preferences.register()
        _ = NSApplication.shared
        let monitor = ServerMonitor()
        AppDelegate.monitor = monitor
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let directory = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
            SnapshotRenderer.run(monitor: monitor, directory: directory)
        }
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Preferences.hotkey))
        monitor.start()
    }

    var body: some Scene {
        // SwiftUI requires a scene. Settings is an NSWindow owned by the status
        // item, so this scene is never shown and never becomes the menu bar panel.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static var monitor: ServerMonitor?

    @MainActor
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--snapshot"), let monitor = Self.monitor else { return }
        StatusItemController.shared.start(monitor: monitor)
    }

    /// Opening the app again (from Finder, Spotlight or Launchpad) toggles the
    /// popover, or Settings when the menu bar is hiding the icon.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if StatusItemController.shared.isIconVisible {
            StatusItemController.shared.togglePopover()
        } else {
            StatusItemController.shared.openSettings()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
