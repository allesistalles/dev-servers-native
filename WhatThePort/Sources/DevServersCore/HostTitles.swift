import Foundation

public enum HostTitles {
    public static let seedHosts = [
        "pixel.local",
        "8x8.local",
        "eight-by-eight.local",
        "eight.local",
        "climate.local",
        "droppic.local",
        "p1s.local",
        "shorty.local",
        "flip-clock-2.local",
        "solly.local",
        "monster.local",
        "print-on-eink.local",
        "stash-buddy.local",
        "homeassistant.local",
        "192.168.0.45",
    ]

    public static let helperPorts = [5177, 8765, 8787]

    public static let hostTitles: [String: String] = [
        "8x8.local": "8x8",
        "eight-by-eight.local": "8x8",
        "eight.local": "8x8",
        "pixel.local": "Pixel",
        "climate.local": "Climate",
        "droppic.local": "Droppic",
        "p1s.local": "P1S",
        "shorty.local": "Shorty",
        "flip-clock-2.local": "Flip clock",
        "solly.local": "Solly",
        "monster.local": "Monster Settings",
        "print-on-eink.local": "Print on e-ink",
        "stash-buddy.local": "Stash Buddy",
        "homeassistant.local": "Home Assistant",
    ]

    static let instanceTitles: [String: String] = [
        "8x8": "8x8",
        "eight-by-eight": "8x8",
        "eight": "8x8",
        "pixel": "Pixel",
        "climate": "Climate",
        "droppic": "Droppic",
        "p1s": "P1S",
        "p1s · live build": "P1S",
        "p1s live build": "P1S",
        "shorty": "Shorty",
        "solly": "Solly",
        "flip-clock-2": "Flip clock",
        "flip clock": "Flip clock",
        "flip clock 2": "Flip clock",
        "monster": "Monster Settings",
        "print-on-eink": "Print on e-ink",
        "print on e-ink": "Print on e-ink",
        "stash-buddy": "Stash Buddy",
        "stash buddy": "Stash Buddy",
        "homeassistant": "Home Assistant",
        "home assistant": "Home Assistant",
    ]

    static let genericTitles: Set<String> = ["web", "unknown", "app", "src", "mac", "www", "site", "roykorkomaz"]
    static let hostPattern = "^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*$"

    public static func normalizeHostname(_ value: String?) -> String? {
        guard var raw = value?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.range(of: "^https?://", options: .regularExpression) != nil {
            guard let host = URL(string: raw)?.host, !host.isEmpty else { return nil }
            raw = host
        }
        if raw.range(of: "\\s", options: .regularExpression) != nil { return nil }
        while raw.hasSuffix(".") { raw.removeLast() }
        raw = raw.lowercased()
        guard !raw.isEmpty, raw.range(of: hostPattern, options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return raw
    }

    public static func parseHostsConfig(_ raw: Any?) -> [String] {
        let list: [Any]?
        if let array = raw as? [Any] {
            list = array
        } else if let dict = raw as? [String: Any], let hosts = dict["hosts"] as? [Any] {
            list = hosts
        } else {
            list = nil
        }
        guard let list else { return [] }
        var seen = Set<String>()
        var hosts: [String] = []
        for item in list {
            guard let host = normalizeHostname(item as? String), seen.insert(host).inserted else { continue }
            hosts.append(host)
        }
        return hosts
    }

    public static func mergeSeedHosts(_ extra: [String] = []) -> [String] {
        parseHostsConfig(seedHosts + extra)
    }

    public static func prettyHostTitle(_ host: String) -> String {
        if let normalized = normalizeHostname(host), let title = hostTitles[normalized] { return title }
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasSuffix(".") { name.removeLast() }
        if name.lowercased().hasSuffix(".local") { name = String(name.dropLast(6)) }
        return name.isEmpty ? host : name
    }

    static func instanceTitle(_ value: String) -> String? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !raw.isEmpty else { return nil }
        if let title = instanceTitles[raw] { return title }
        let stripped = raw.replacingOccurrences(of: ".local", with: "", options: .caseInsensitive)
        if let title = instanceTitles[stripped] { return title }
        if raw.range(of: "^p1s\\b", options: .regularExpression) != nil { return "P1S" }
        return nil
    }

    static func titleHay(_ item: BoardItem, host: String) -> String {
        [item.command, item.args.joined(separator: " "), item.cwd, item.shortCwd, item.project, item.title, item.htmlTitle, host]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func isBlackberryWebDir(_ hay: String) -> Bool {
        hay.range(of: "blackberry(?:\\s+\\d+)?/mac/web|blackberry[^/]*/mac/web", options: .regularExpression) != nil
    }

    public static func friendlyTitleFor(_ item: BoardItem) -> String? {
        let host = normalizeHostname(item.host) ?? ""
        let port = item.port
        let hay = titleHay(item, host: host)
        let berryDir = isBlackberryWebDir(hay)
        if port == 8888 && berryDir { return "Blackberry web" }
        if port == 8899 && berryDir { return "Blackberry static" }
        if port == 8900 && (berryDir || hay.range(of: "\\bclip\\.py\\b", options: .regularExpression) != nil) {
            return "Blackberry clip"
        }
        if port == 7878 || hay.range(of: "dialdash|mac_bridge|mac-bridge", options: .regularExpression) != nil { return "DialDash" }
        if port == 37777 || (hay.contains("claude-mem") && hay.contains("worker-service.cjs")) { return "Claude-mem" }
        if port == 5177 || (hay.contains("led-round-dial") && hay.contains("companion")) { return "LED Round Dial" }
        if port == 8787 || host == "droppic.local" {
            if hay.range(of: "\\btranslat", options: .regularExpression) != nil { return "Translator" }
            return "Droppic"
        }
        if port == 8765 || host == "p1s.local" { return "P1S" }
        if port == 8123 && (host == "homeassistant.local" || host == "192.168.0.45") { return "Home Assistant" }
        if host == "monster.local" {
            if port == 3232 || port == 6053 { return "Monster" }
            return "Monster Settings"
        }
        if let fromInstance = instanceTitle(item.title) ?? instanceTitle(item.htmlTitle) { return fromInstance }
        if let title = hostTitles[host] { return title }
        return nil
    }

    static func cloneRootTitle(_ cwd: String) -> String? {
        let parts = cwd.split { $0 == "/" || $0 == "\\" }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "." && $0 != "~" }
        guard let marker = parts.firstIndex(where: { $0.range(of: "all cloned from github", options: .caseInsensitive) != nil }) else { return nil }
        let next = parts.index(after: marker)
        return next < parts.endIndex ? parts[next] : nil
    }

    public static func listenerTitle(_ item: BoardItem) -> String {
        if let friendly = friendlyTitleFor(item) { return friendly }
        if let fromClone = cloneRootTitle(item.cwd.isEmpty ? item.shortCwd : item.cwd) { return fromClone }
        let project = (item.project.isEmpty ? item.title : item.project).trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty && !genericTitles.contains(project.lowercased()) { return project }
        let command = item.command.split { $0 == "/" || $0 == "\\" }.last.map { String($0) }?
            .replacingOccurrences(of: "\\.(exe|cmd|bat)$", with: "", options: .regularExpression)
        if let command, !command.isEmpty { return command }
        let pretty = prettyHostTitle(item.host)
        return pretty.isEmpty ? "localhost" : pretty
    }
}
