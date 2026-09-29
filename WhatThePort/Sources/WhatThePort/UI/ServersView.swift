import SwiftUI

/// The menu-bar popover is the board: helpers, listeners, and LAN devices.
struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openSettings: () -> Void
    @State private var contentHeight: CGFloat = 0

    /// Gear row (12pt padding, 26pt button, divider). Kept out of the scroller.
    private var maxBoardHeight: CGFloat { Theme.popoverMaxHeight - 52 }

    init(monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if contentHeight > maxBoardHeight {
                    ScrollView {
                        boardContent
                    }
                    .frame(height: maxBoardHeight)
                } else {
                    boardContent
                }
            }
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

    private var boardContent: some View {
        BoardSections(monitor: monitor)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                guard height > 1 else { return }
                contentHeight = height
            }
    }
}
