import SwiftUI

struct PopoverRoot: View {
    @ObservedObject var monitor: ServerMonitor
    let openSettings: () -> Void

    var body: some View {
        ServersView(monitor: monitor, openSettings: openSettings)
            .frame(width: Theme.popoverWidth)
            .background(Theme.popoverBackground)
            .onAppear { monitor.start() }
    }
}
