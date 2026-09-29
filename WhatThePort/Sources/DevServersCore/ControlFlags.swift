import Foundation

/// Button rules. `apply` sets flags the way control.js does.
/// `CardActions` is what the card row actually shows.
public enum ControlFlags {
    public static func canKillItem(_ item: BoardItem) -> Bool {
        if item.kind == "system" { return false }
        if !item.source.isEmpty && item.source != "local" { return false }
        if !KnownHelpers.isLocalHelperHost(item.host) && item.source != "local" { return false }
        return item.pid > 0
    }

    public static func canRestartItem(_ item: BoardItem) -> Bool {
        if !canKillItem(item) || item.status == "down" { return false }
        return KnownHelpers.matchKnownHelper(item) != nil || !item.launchAgent.isEmpty
    }

    public static func canCopyUrl(_ item: BoardItem) -> Bool {
        item.url.range(of: "^https?://", options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func matchRegistry(_ item: BoardItem, helpers: [HelperSpec]) -> HelperSpec? {
        if let known = KnownHelpers.matchKnownHelper(item, helpers: helpers) { return known }
        guard KnownHelpers.isLocalHelperHost(item.host) else { return nil }
        if !item.launchAgent.isEmpty, let byLabel = helpers.first(where: { $0.launchAgent == item.launchAgent }) {
            return byLabel
        }
        guard item.port > 0 else { return nil }
        return helpers.first { !$0.launchAgent.isEmpty && $0.port == item.port }
    }

    public static func apply(_ item: BoardItem, helpers: [HelperSpec] = KnownHelpers.all) -> BoardItem {
        var item = item
        if let known = matchRegistry(item, helpers: helpers) {
            if item.helperId.isEmpty { item.helperId = known.id }
            if item.launchAgent.isEmpty, !known.launchAgent.isEmpty { item.launchAgent = known.launchAgent }
            if KnownHelpers.isLocalHelperHost(item.host) { item.startable = true }
        }
        if canCopyUrl(item) { item.copyable = true }
        if canRestartItem(item) { item.restartable = true }
        return item
    }
}
