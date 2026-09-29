import Foundation

public struct LanCompanion: Equatable, Sendable {
    public var id: String
    public var match: String
    public var host: String
    public var port: Int
    public var path: String
    public var title: String
    public var description: String
    public var otaDescription: String
}

public enum Companions {
    public static let firmwareOnlyPorts = [3232, 6053]
    public static let lanCompanions: [LanCompanion] = [
        LanCompanion(
            id: "led-round-dial",
            match: "led-round-dial|led_round_dial",
            host: "localhost",
            port: 5177,
            path: "/",
            title: "LED Round Dial",
            description: "Browser twin for the LED Round Dial (moods/music via Home Assistant)",
            otaDescription: "Physical LED Round Dial on ESPHome API (:6053) — not a web page; open the companion on :5177 when it’s running"
        ),
    ]

    public static func isFirmwareOnlyPort(_ port: Int) -> Bool {
        firmwareOnlyPorts.contains(port)
    }

    static func companionHay(_ item: BoardItem) -> String {
        [item.host, item.title, item.label, item.kind, item.project, item.instance].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func matchLanCompanion(_ item: BoardItem) -> LanCompanion? {
        let text = companionHay(item)
        return lanCompanions.first { text.range(of: $0.match, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    public static func companionProbeTargets(_ items: [BoardItem]) -> [(host: String, port: Int)] {
        var seen = Set<String>()
        var out: [(host: String, port: Int)] = []
        for item in items {
            guard let hit = matchLanCompanion(item) else { continue }
            let key = "\(hit.host):\(hit.port)"
            guard seen.insert(key).inserted else { continue }
            out.append((hit.host, hit.port))
        }
        return out
    }

    public static func companionPortsFor(_ host: String) -> [Int] {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lanCompanions.filter { $0.host == value }.map(\.port)
    }

    static let haHosts: Set<String> = ["homeassistant.local", "192.168.0.45"]

    public static func isHomeAssistant(_ item: BoardItem) -> Bool {
        var host = item.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        let port = item.port
        if host == "climate.local" { return false }
        if item.kind.lowercased() == "homeassistant" { return true }
        if haHosts.contains(host) && (port == 8123 || port == 0) { return true }
        return item.title.range(of: "home\\s*assistant", options: [.regularExpression, .caseInsensitive]) != nil && port == 8123
    }
}
