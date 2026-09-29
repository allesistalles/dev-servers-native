import DevServersCore
import SwiftUI

struct GroupLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.caption)
            .foregroundStyle(Theme.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }
}

/// Helpers, LAN devices, collapsed system listeners, and the Needs attention
/// group. Attention rows also appear in their home section.
struct ServiceSections: View {
    @ObservedObject var monitor: ServerMonitor
    var showsAttention = true
    var showsRest = true

    var body: some View {
        let inventory = monitor.serviceInventory
        VStack(spacing: 0) {
            if showsAttention, !inventory.needsAttention.isEmpty {
                GroupLabel(title: L10n.text("Needs attention"))
                ForEach(inventory.needsAttention) { item in
                    attentionRow(item, inventory: inventory)
                }
            }
            if showsRest {
                if !inventory.helpers.isEmpty || !inventory.sidecars.isEmpty {
                    GroupLabel(title: L10n.text("Helpers"))
                    ForEach(inventory.helpers) { helper in
                        HelperLine(helper: helper, monitor: monitor)
                    }
                    ForEach(inventory.sidecars) { sidecar in
                        SidecarLine(sidecar: sidecar, monitor: monitor)
                    }
                }
                if !inventory.lanDevices.isEmpty {
                    GroupLabel(title: L10n.text("On the network"))
                    ForEach(inventory.lanDevices) { device in
                        LanLine(device: device)
                    }
                }
                if !inventory.systemRows.isEmpty {
                    GroupLabel(title: L10n.text("System"))
                    ForEach(inventory.systemRows) { row in
                        SystemLine(row: row)
                    }
                }
            }
        }
    }

    @ViewBuilder private func attentionRow(_ item: AttentionItem, inventory: ServiceInventory) -> some View {
        if let id = item.helperID, let helper = inventory.helpers.first(where: { $0.id == id }) {
            HelperLine(helper: helper, monitor: monitor, attention: item.kind)
        } else if let id = item.deviceID, let device = inventory.lanDevices.first(where: { $0.id == id }) {
            LanLine(device: device, attention: true)
        }
    }
}

private struct HelperLine: View {
    let helper: HelperRow
    @ObservedObject var monitor: ServerMonitor
    var attention: AttentionKind?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(portText)
                .font(Theme.mono)
                .foregroundStyle(helper.state == .running ? Theme.text2 : Theme.text3)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(helper.name).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
                Text(detail).font(Theme.caption).foregroundStyle(attention == nil ? Theme.text2 : Theme.amber).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered { actions }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .hoverHighlight(isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let url = helper.openURL.flatMap(URL.init(string:)) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private var portText: String {
        if helper.state == .running, let port = helper.runningPorts.first { return String(port) }
        if let port = helper.ports.first { return String(port) }
        return "—"
    }

    private var detail: String {
        switch attention {
        case .missingCompanion: return L10n.text("Missing companion")
        case .stoppedHelper: return L10n.text("Stopped")
        case .firmwareOnly, nil:
            if helper.state == .stopped { return L10n.text("Stopped") }
            if helper.runningPorts.count > 1 {
                return helper.runningPorts.map(String.init).joined(separator: ", ")
            }
            return helper.agents.first?.label ?? L10n.text("Running")
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 2) {
            if helper.state == .running, helper.openURL != nil {
                IconButton(systemName: "arrow.up.right", size: 22, help: L10n.text("Open in browser")) {
                    if let url = helper.openURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
                }
            }
            if helper.state == .stopped {
                IconButton(systemName: "play.fill", size: 22, help: L10n.text("Start")) {
                    monitor.startHelper(helper)
                }
                .disabled(helper.agents.isEmpty)
            } else {
                IconButton(systemName: "arrow.clockwise", size: 22, help: L10n.text("Restart")) {
                    monitor.restartHelper(helper)
                }
                .disabled(helper.agents.isEmpty && helper.listenerPIDs.isEmpty)
                IconButton(systemName: "stop.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 22, help: L10n.text("Stop")) {
                    monitor.stopHelper(helper)
                }
            }
        }
    }
}

private struct SidecarLine: View {
    let sidecar: SidecarRow
    @ObservedObject var monitor: ServerMonitor
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Text(sidecar.ports.first.map(String.init) ?? "—")
                .font(Theme.mono)
                .foregroundStyle(Theme.text2)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(sidecar.name).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
                Text(sidecar.ports.map(String.init).joined(separator: ", "))
                    .font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered, !sidecar.agents.isEmpty || !sidecar.listenerPIDs.isEmpty {
                IconButton(systemName: "stop.fill", tint: Theme.text1.opacity(0.8), background: .clear, size: 22, help: L10n.text("Stop")) {
                    monitor.stopSidecar(sidecar)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .hoverHighlight(isHovered)
        .onHover { isHovered = $0 }
    }
}

private struct LanLine: View {
    let device: LanDevice
    var attention = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: device.firmwareOnly ? "antenna.radiowaves.left.and.right" : "network")
                .font(.system(size: 11))
                .foregroundStyle(device.firmwareOnly ? Theme.amber : Theme.text2)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
                Text(detail).font(Theme.caption).foregroundStyle(device.firmwareOnly || attention ? Theme.amber : Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
            if isHovered, let url = device.openURL.flatMap(URL.init(string:)) {
                IconButton(systemName: "arrow.up.right", size: 22, help: L10n.text("Open in browser")) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .hoverHighlight(isHovered)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let url = device.openURL.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
        }
    }

    private var detail: String {
        if device.firmwareOnly { return L10n.text("Firmware only") }
        if device.nameLookupFailed, let ipv4 = device.ipv4 { return ipv4 }
        return device.openURL ?? device.host
    }
}

private struct SystemLine: View {
    let row: SystemRow

    var body: some View {
        HStack(spacing: 0) {
            Text(L10n.text("System"))
                .font(Theme.caption)
                .foregroundStyle(Theme.text3)
                .frame(width: 58, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.processName).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
                Text(row.portsLabel).font(Theme.caption).foregroundStyle(Theme.text2).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
    }
}
