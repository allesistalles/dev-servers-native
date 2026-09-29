import AppKit
import Combine
import SwiftUI

private let popoverEscapeKey: UInt16 = 53

/// The menu bar icon and the popover it toggles.
///
/// MenuBarExtra's window has no close API. This owns an NSStatusItem and an
/// NSPopover instead. The app stays LSUIElement / accessory: nothing here calls
/// setActivationPolicy.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var monitor: ServerMonitor?
    private var settingsWindow: NSWindow?
    private var boardCancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    /// Set when a click on the status button is what closed the popover, so the
    /// following mouseUp does not open it again.
    private var suppressNextOpen = false

    /// Whether the icon is on screen. The menu bar can hide it in the overflow,
    /// behind the notch, or from System Settings → Menu Bar.
    var isIconVisible: Bool {
        guard let window = statusItem?.button?.window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    func start(monitor: ServerMonitor) {
        guard statusItem == nil else { return }
        self.monitor = monitor
        monitor.onWillOpen = { [weak self] in
            self?.closePopover()
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let host = NSHostingController(rootView: LocalizedView {
            PopoverRoot(monitor: monitor, openSettings: { [weak self] in
                self?.openSettings()
            })
        })
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: Theme.popoverWidth, height: 320)

        boardCancellable = monitor.$board
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateIcon() }
            }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
        updateIcon()
    }

    /// ⌥⌘P and a plain click. Shown → close. Hidden → show.
    func togglePopover() {
        if popover.isShown {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        NSApp.activate()
        button.isHighlighted = true
        popover.behavior = .transient
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        guard popover.isShown else {
            button.isHighlighted = false
            return
        }
        installMonitors()
    }

    func closePopover() {
        guard popover.isShown else {
            removeMonitors()
            statusItem?.button?.isHighlighted = false
            return
        }
        popover.performClose(nil)
    }

    func openSettings() {
        closePopover()
        guard let monitor else { return }
        let window = settingsWindow ?? makeSettingsWindow(monitor: monitor)
        settingsWindow = window
        window.title = L10n.text("Settings")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        // AppKit calls this on the main thread, before the status button's mouseUp.
        MainActor.assumeIsolated {
            self.removeMonitors()
            self.statusItem?.button?.isHighlighted = false
            self.suppressIfStatusClick()
        }
    }

    private func makeSettingsWindow(monitor: ServerMonitor) -> NSWindow {
        let host = NSHostingController(rootView: LocalizedView {
            SettingsView(monitor: monitor)
        })
        host.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: host)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 740, height: 560))
        window.title = L10n.text("Settings")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.center()
        return window
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let secondary = isSecondaryClick
        if suppressNextOpen {
            suppressNextOpen = false
            if secondary { showMenu(from: sender) }
            return
        }
        if secondary {
            closePopover()
            showMenu(from: sender)
            return
        }
        togglePopover()
    }

    private var isSecondaryClick: Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.type == .rightMouseUp || event.type == .rightMouseDown || event.modifierFlags.contains(.control)
    }

    private func showMenu(from button: NSStatusBarButton) {
        guard let monitor else { return }
        closePopover()
        StatusItemMenu.show(from: button, monitor: monitor, openPopover: { [weak self] in
            self?.showPopover()
        }, openSettings: { [weak self] in
            self?.openSettings()
        })
    }

    /// A transient popover closes on mouseDown outside its window, including a
    /// mouseDown on this status button. The button's action is mouseUp, which
    /// would otherwise open the popover again.
    private func suppressIfStatusClick() {
        guard let event = NSApp.currentEvent else { return }
        guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return }
        guard let button = statusItem?.button, event.window === button.window else { return }
        let point = button.convert(event.locationInWindow, from: nil)
        if button.bounds.contains(point) {
            suppressNextOpen = true
        }
    }

    private func installMonitors() {
        removeMonitors()
        // Clicks in other apps never reach a transient popover of an accessory app.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.closePopover() }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == popoverEscapeKey else { return event }
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.popover.isShown else { return false }
                self.closePopover()
                return true
            }
            return closed ? nil : event
        }
    }

    private func removeMonitors() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func updateIcon() {
        guard let button = statusItem?.button, let monitor else { return }
        let count = monitor.board.filter { $0.kind != "system" }.count
        let raw = UserDefaults.standard.string(forKey: Preferences.iconStyle) ?? Preferences.IconStyle.colonCount.rawValue
        let style = Preferences.IconStyle(rawValue: raw) ?? .colonCount
        button.image = MenuBarLabel.image(count: count, style: style)
        button.setAccessibilityLabel(MenuBarLabel.accessibilityLabel(count: count))
    }
}
