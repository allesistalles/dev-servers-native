import SwiftUI

struct PopoverRoot: View {
    @ObservedObject var monitor: ServerMonitor
    let openSettings: () -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }

    var body: some View {
        ServersView(monitor: monitor, openSettings: openSettings)
            .frame(width: Theme.popoverWidth)
            .fixedSize(horizontal: false, vertical: true)
            .background(Theme.popoverBackground)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard height > 1 else { return }
                onContentHeight(min(height, Theme.popoverMaxHeight))
            }
            .onAppear { monitor.start() }
    }
}
