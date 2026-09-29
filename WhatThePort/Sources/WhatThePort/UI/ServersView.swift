import SwiftUI

/// The menu-bar popover is the board: helpers, listeners, and LAN devices.
struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openSettings: () -> Void
    @State private var boardHeight: CGFloat = 0

    /// Gear row (12pt padding, 26pt button, divider). Kept out of the scroller.
    private var maxBoardHeight: CGFloat { Theme.popoverMaxHeight - 52 }

    init(monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                BoardSections(monitor: monitor)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { boardHeight = $0 }
            }
            .frame(height: min(boardHeight > 0 ? boardHeight : maxBoardHeight, maxBoardHeight))
            SectionDivider()
            HStack {
                Spacer()
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(",", modifiers: .command)
                .help(L10n.text("Settings"))
            }
            .padding(12)
        }
    }
}
