import SwiftUI

@main
enum Main {
    @MainActor static func main() {
        DevServersApp.main()
    }
}

struct DevServersApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var monitor: ServerMonitor

    init() {
        FontLoader.registerBundledFonts()
        Preferences.register()
        _ = NSApplication.shared
        let monitor = ServerMonitor()
        _monitor = StateObject(wrappedValue: monitor)
        if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
            let directory = CommandLine.arguments.dropFirst(index + 1).first ?? FileManager.default.currentDirectoryPath
            SnapshotRenderer.run(monitor: monitor, directory: directory)
        }
        HotKey.shared.setEnabled(UserDefaults.standard.bool(forKey: Preferences.hotkey))
        monitor.start()
    }

    var body: some Scene {
        MenuBarExtra {
            LocalizedView { PopoverRoot(monitor: monitor) }
        } label: {
            LocalizedView { MenuBarLabel(monitor: monitor) }
        }
        .menuBarExtraStyle(.window)

        Window(L10n.text("Settings"), id: "settings") {
            LocalizedView { SettingsView(monitor: monitor) }
        }
        .windowResizability(.contentSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set once the menu bar icon appears, since only views can open windows.
    @MainActor static var openSettings: (() -> Void)?

    /// Opening the app again (from Finder, Spotlight or Launchpad) opens the
    /// popover, or Settings when the menu bar is hiding the icon, so people
    /// who can't see it still reach the app.
    @MainActor
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if StatusItemOpener.isShowing {
            StatusItemOpener.open()
        } else if let openSettings = Self.openSettings {
            openSettings()
        }
        return false
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: ServerMonitor
    @AppStorage(Preferences.iconStyle) private var iconStyle = Preferences.IconStyle.colonCount.rawValue
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = monitor.board.filter { $0.kind != "system" }.count
        let style = Preferences.IconStyle(rawValue: iconStyle) ?? .colonCount
        let (glyph, label): (DotGlyph, Int?) = {
            if count == 0 { return (.colon, nil) }
            switch style {
            case .colon: return (.colon, nil)
            case .colonCount: return (.colon, count)
            case .count: return DotGlyph.digit(count).map { ($0, nil) } ?? (.colon, count)
            }
        }()
        Image(nsImage: MenuBarIcon.image(glyph: glyph, count: label))
            .accessibilityLabel(count == 0 ? L10n.text("Dev Servers, no servers") : L10n.format("Dev Servers, %d servers", count))
            .task {
                let openSettings = {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                }
                AppDelegate.openSettings = openSettings
                StatusItemMenu.install(monitor: monitor, openSettings: openSettings)
            }
    }
}
