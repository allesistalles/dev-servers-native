import SwiftUI

struct PopoverRoot: View {
    @ObservedObject var monitor: ServerMonitor
    @Environment(\.openWindow) private var openWindow
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ServersView(monitor: monitor, openSettings: openSettings)
            .frame(width: Theme.popoverWidth)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            .background(PopoverWindowFitter(height: contentHeight))
            .onAppear { monitor.start() }
    }

    private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openWindow(id: "settings")
    }
}

/// MenuBarExtra only resizes its window to fit the page in apps built with the
/// macOS 26 SDK. Otherwise the window keeps its first height and clips taller
/// pages. Resize it here in that case, keeping the top edge under the menu bar.
private struct PopoverWindowFitter: NSViewRepresentable {
    let height: CGFloat

    final class Coordinator {
        var height: CGFloat = 0
        /// Learned from the first page change: whether SwiftUI starts resizing the window itself.
        var swiftUIResizes: Bool?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.height = height
        DispatchQueue.main.async { [weak view] in
            guard let window = view?.window, Self.needsFit(window, coordinator) else { return }
            switch coordinator.swiftUIResizes {
            case true?:
                return
            case false?:
                Self.fit(window, coordinator)
            case nil:
                let start = window.frame
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    guard coordinator.swiftUIResizes == nil else { return }
                    coordinator.swiftUIResizes = window.frame != start
                    if coordinator.swiftUIResizes == false { Self.fit(window, coordinator) }
                }
            }
        }
    }

    private static func needsFit(_ window: NSWindow, _ coordinator: Coordinator) -> Bool {
        coordinator.height > 0 && abs(window.contentRect(forFrameRect: window.frame).height - coordinator.height) > 1
    }

    private static func fit(_ window: NSWindow, _ coordinator: Coordinator) {
        guard needsFit(window, coordinator) else { return }
        // MenuBarExtra's window is a nonactivating panel anchored to the status
        // item. setFrame detaches that panel: it stays on screen, outside clicks
        // and the icon stop dismissing it, and it stops delivering mouse events.
        // Apps built with the macOS 26 SDK get the resize from SwiftUI instead.
        guard !(window is NSPanel),
              !window.styleMask.contains(.nonactivatingPanel),
              window.level == .normal else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let target = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: content.width, height: coordinator.height)).height
        var frame = window.frame
        frame.origin.y = frame.maxY - target
        frame.size.height = target
        window.setFrame(frame, display: true)
    }
}
