import AppKit
import Combine
import SwiftUI

private let popoverEscapeKey: UInt16 = 53

/// The menu bar icon and the popover it toggles.
///
/// MenuBarExtra's window has no close API. This owns an NSStatusItem and a
/// transient panel instead. The app stays LSUIElement / accessory: nothing here
/// calls setActivationPolicy.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var boardPanel: NSPanel?
    private var boardHost: NSHostingController<LocalizedView<PopoverRoot>>?
    private var monitor: ServerMonitor?
    private var settingsWindow: NSWindow?
    private var boardCancellable: AnyCancellable?
    private var defaultsObserver: NSObjectProtocol?
    private var activateObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var dismissPollTimer: Timer?
    private var boardOpen = false
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

        attachBoardHost(monitor: monitor)

        boardCancellable = monitor.$board
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.updateIcon()
                    self?.remeasureBoardIfShown()
                }
            }
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIcon() }
        }
        updateIcon()
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePopover() }
        }
        activateObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.boardOpen else { return }
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self.closePopover()
                }
            }
        }
    }

    private func attachBoardHost(monitor: ServerMonitor) {
        let host = NSHostingController(rootView: LocalizedView {
            PopoverRoot(monitor: monitor, openSettings: { [weak self] in
                self?.openSettings()
            }, closePopover: { [weak self] in
                self?.closePopover()
            }, onContentHeight: { [weak self] height in
                self?.applyBoardHeight(height)
            })
        })
        host.sizingOptions = [.preferredContentSize]
        host.view.clipsToBounds = true
        boardHost = host
    }

    private func remeasureBoardIfShown() {
        guard boardOpen, let host = boardHost else { return }
        host.view.layoutSubtreeIfNeeded()
        let height = host.view.fittingSize.height
        guard height > 1 else { return }
        applyBoardHeight(height)
    }

    /// Width stays 400. Height tracks the board and never passes the popover cap.
    private func applyBoardHeight(_ height: CGFloat) {
        let clamped = min(max(height, 1), Theme.popoverMaxHeight)
        let size = NSSize(width: Theme.popoverWidth, height: clamped)
        boardHost?.preferredContentSize = size
        guard let panel = boardPanel else { return }
        guard abs(panel.frame.width - size.width) > 0.5 || abs(panel.frame.height - size.height) > 0.5 else { return }
        positionBoardPanel(size: size)
    }

    private func positionBoardPanel(size: NSSize) {
        guard let button = statusItem?.button, let barWindow = button.window, let panel = boardPanel else { return }
        let buttonOnScreen = barWindow.convertToScreen(button.frame)
        var frame = panel.frame
        frame.size = size
        frame.origin.x = buttonOnScreen.midX - size.width / 2
        frame.origin.y = buttonOnScreen.minY - size.height - 4
        panel.setFrame(frame, display: true)
    }

    private func makeBoardPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.popoverWidth, height: 320),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        if let host = boardHost {
            panel.contentViewController = host
        }
        return panel
    }

    func togglePopover() {
        if boardOpen {
            closePopover()
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard let button = statusItem?.button, !boardOpen else { return }
        NSApp.activate(ignoringOtherApps: true)
        button.isHighlighted = true
        if boardPanel == nil {
            boardPanel = makeBoardPanel()
        }
        positionBoardPanel(size: NSSize(width: Theme.popoverWidth, height: 320))
        boardPanel?.orderFrontRegardless()
        boardOpen = true
        installMonitors()
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.remeasureBoardIfShown() }
        }
    }

    func closePopover() {
        guard boardOpen else {
            removeMonitors()
            statusItem?.button?.isHighlighted = false
            return
        }
        boardPanel?.orderOut(nil)
        finishPopoverClose()
    }

    private func finishPopoverClose() {
        boardOpen = false
        removeMonitors()
        statusItem?.button?.isHighlighted = false
        suppressIfStatusClick()
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
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.boardOpen else { return }
                if NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    self.closePopover()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dismissPollTimer = timer
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.boardOpen, let panel = self.boardPanel else { return }
                if !panel.frame.contains(NSEvent.mouseLocation) {
                    self.closePopover()
                }
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == popoverEscapeKey else { return event }
            let closed = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.boardOpen else { return false }
                self.closePopover()
                return true
            }
            return closed ? nil : event
        }
    }

    private func removeMonitors() {
        dismissPollTimer?.invalidate()
        dismissPollTimer = nil
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
