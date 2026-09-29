import AppKit
import DevServersCore

/// Right-click (or Control-click) menu for the status button. The button sends
/// leftMouseUp and rightMouseUp; this does not install an event monitor.
@MainActor
enum StatusItemMenu {
    static func show(from button: NSStatusBarButton, monitor: ServerMonitor, openPopover: @escaping () -> Void, openSettings: @escaping () -> Void) {
        let menu = NSMenu()
        menu.autoenablesItems = false

        menu.addItem(ActionItem(L10n.text("Open Dev Servers"), action: openPopover))

        let browser = NSMenuItem(title: L10n.text("Open in Browser"), action: nil, keyEquivalent: "")
        let servers = NSMenu()
        for item in monitor.board where CardActions.canOpen(item) {
            servers.addItem(ActionItem("\(item.title)  \(item.url)") {
                monitor.open(item)
            })
        }
        browser.submenu = servers
        browser.isEnabled = servers.numberOfItems > 0
        menu.addItem(browser)

        menu.addItem(.separator())
        let settings = ActionItem(L10n.text("Settings…"), action: openSettings)
        settings.keyEquivalent = ","
        menu.addItem(settings)

        let feedback = NSMenuItem(title: L10n.text("Send Feedback"), action: nil, keyEquivalent: "")
        feedback.submenu = NSMenu()
        feedback.submenu?.addItem(ActionItem(L10n.text("Report a Bug…")) { NSWorkspace.shared.open(FeedbackLink.issue(.bug)) })
        feedback.submenu?.addItem(ActionItem(L10n.text("Suggest a Feature…")) { NSWorkspace.shared.open(FeedbackLink.issue(.feature)) })
        menu.addItem(feedback)

        menu.addItem(.separator())
        let quit = ActionItem(L10n.text("Quit Dev Servers")) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)

        button.highlight(true)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.maxY + 5), in: button)
        button.highlight(false)
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, action handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
