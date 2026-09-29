import AppKit

/// MenuBarExtra has no API to open its window, so find the status item button
/// and click it. Look in every window rather than a private window class:
/// macOS 27 draws the menu bar as one window instead of one per icon.
@MainActor
enum StatusItemOpener {
    /// Returns false when there's no icon to click.
    @discardableResult
    static func open() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        guard let button else { return false }
        button.performClick(nil)
        return true
    }

    /// Whether the icon is on screen. The menu bar can hide it: in its overflow
    /// on macOS 27, behind the notch, or when it's turned off in System
    /// Settings → Menu Bar.
    static var isShowing: Bool {
        guard let window = button?.window else { return false }
        return window.isVisible && window.occlusionState.contains(.visible)
    }

    private static var button: NSStatusBarButton? {
        NSApp.windows.lazy.compactMap { findButton(in: $0.contentView) }.first
    }

    static func findButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = findButton(in: subview) { return button }
        }
        return nil
    }
}
