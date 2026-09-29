import SwiftUI

/// The menu-bar popover is the board: helpers, listeners, and LAN devices.
struct ServersView: View {
    @ObservedObject var monitor: ServerMonitor
    let openSettings: () -> Void

    init(monitor: ServerMonitor, openSettings: @escaping () -> Void) {
        self.monitor = monitor
        self.openSettings = openSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            BoardSections(monitor: monitor)
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
