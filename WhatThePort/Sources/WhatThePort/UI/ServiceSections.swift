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

/// Overview, All, Local, LAN, Stopped and System. Open, Start, Restart and Kill
/// stay on the card, the same way the Electron board draws them.
struct BoardSections: View {
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        VStack(spacing: 0) {
            tabs
            if let error = monitor.actionError, !error.isEmpty {
                Text(error)
                    .font(Theme.caption)
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
            if monitor.boardTab == .overview {
                overview
            } else {
                let cards = BoardMerge.filter(monitor.board, tab: monitor.boardTab.rawValue)
                if cards.isEmpty {
                    Text(L10n.text("Nothing here"))
                        .font(Theme.caption)
                        .foregroundStyle(Theme.text3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                } else {
                    ForEach(cards) { card in
                        BoardCard(item: card, monitor: monitor)
                    }
                }
            }
        }
    }

    private var tabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(BoardTab.allCases) { tab in
                    Button(tab.title) { monitor.boardTab = tab }
                        .buttonStyle(.plain)
                        .font(Theme.caption)
                        .foregroundStyle(monitor.boardTab == tab ? Theme.text1 : Theme.text3)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(monitor.boardTab == tab ? Theme.text1.opacity(0.08) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var overview: some View {
        let view = BoardMerge.overview(monitor.board)
        if !view.attention.isEmpty {
            GroupLabel(title: L10n.text("Needs attention"))
            ForEach(view.attention) { card in
                BoardCard(item: card, monitor: monitor)
            }
        }
        if !view.running.isEmpty {
            GroupLabel(title: L10n.text("Running"))
            ForEach(view.running) { card in
                BoardCard(item: card, monitor: monitor)
            }
        }
        if !view.pinned.isEmpty {
            GroupLabel(title: L10n.text("Pinned"))
            ForEach(view.pinned) { card in
                BoardCard(item: card, monitor: monitor)
            }
        }
        if !view.fleet.isEmpty {
            GroupLabel(title: L10n.text("On the network"))
            ForEach(view.fleet) { card in
                BoardCard(item: card, monitor: monitor)
            }
        }
        if view.attention.isEmpty && view.pinned.isEmpty && view.fleet.isEmpty && view.running.isEmpty {
            Text(L10n.text("Nothing here"))
                .font(Theme.caption)
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
        }
    }
}

private struct BoardCard: View {
    let item: BoardItem
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(portText)
                    .font(Theme.mono)
                    .foregroundStyle(item.status == "down" ? Theme.text3 : Theme.text2)
                    .frame(width: 58, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(Theme.bodyMedium).foregroundStyle(Theme.text1).lineLimit(1)
                    Text(detail).font(Theme.caption).foregroundStyle(firmware ? Theme.amber : Theme.text2).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { activate() }
            actions
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var firmware: Bool {
        !item.openable && (item.kind == "arduino" || item.kind == "esphome" || Companions.isFirmwareOnlyPort(item.port))
    }

    private var portText: String {
        if item.port > 0 { return String(item.port) }
        if let port = item.ports.first { return String(port) }
        return "—"
    }

    private var detail: String {
        if !item.attention.isEmpty { return item.attention }
        if firmware { return item.label.isEmpty ? L10n.text("Firmware only") : item.label }
        if item.status == "down" { return L10n.text("Stopped") }
        if !item.description.isEmpty { return item.description }
        return item.url.isEmpty ? item.host : item.url
    }

    @ViewBuilder private var actions: some View {
        if CardActions.canOpen(item) || CardActions.canStart(item) || CardActions.canRestart(item) || CardActions.canKill(item) {
            HStack(spacing: 8) {
                if CardActions.canOpen(item) {
                    Button(L10n.text("Open")) { monitor.open(item) }.buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.text1)
                }
                if CardActions.canStart(item) {
                    Button(L10n.text("Start")) { monitor.start(item) }.buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.text1)
                }
                if CardActions.canRestart(item) {
                    Button(L10n.text("Restart")) { monitor.restart(item) }.buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.text1)
                }
                if CardActions.canKill(item) {
                    Button(L10n.text("Kill")) { monitor.kill(item) }.buttonStyle(.plain).font(Theme.caption).foregroundStyle(Theme.amber)
                }
            }
        }
    }

    private func activate() {
        monitor.open(item)
    }
}
