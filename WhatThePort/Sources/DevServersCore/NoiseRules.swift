import Foundation

/// Non-HTTP sidecars. They keep a role name and never join Stopped or Needs attention.
public enum SidecarKind: String, Equatable, Sendable, CaseIterable {
    case claudeForwarder = "Claude forwarder"
    case openCodeForwarder = "OpenCode forwarder"
    case p1sMdns = "P1S mDNS"
    case p1sMenubar = "P1S menu bar"

    public var id: String { rawValue }

    public static func match(processName: String, command: String, label: String = "") -> SidecarKind? {
        let blob = "\(processName) \(command) \(label)".lowercased()
        if blob.contains("p1s") && blob.contains("mdns") { return .p1sMdns }
        if blob.contains("p1s") && (blob.contains("menubar") || blob.contains("menu-bar") || blob.contains("menu_bar")) {
            return .p1sMenubar
        }
        if blob.contains("opencode") && (blob.contains("forward") || blob.contains("sidecar")) {
            return .openCodeForwarder
        }
        let isClaudeMem = blob.contains("claude-mem") || blob.contains("claudemem") || blob.contains("claude_mem")
        if !isClaudeMem && blob.contains("claude") && (blob.contains("forward") || blob.contains("sidecar")) {
            return .claudeForwarder
        }
        return nil
    }
}

public enum SystemNoise {
    /// One row per process name. Spotify's helper processes collapse with Spotify.
    public static func isSystemListener(_ processName: String) -> Bool {
        let name = processName.lowercased()
        return name == "spotify" || name.hasPrefix("spotify ") || name == "rapportd"
    }

    public static func rows(from listeners: [Listener]) -> [SystemRow] {
        var grouped: [String: (name: String, ports: Set<Int>)] = [:]
        for listener in listeners where isSystemListener(listener.processName) {
            let key = listener.processName.lowercased()
            var entry = grouped[key] ?? (listener.processName, [])
            entry.ports.insert(listener.port)
            if entry.name.count < listener.processName.count { entry.name = listener.processName }
            grouped[key] = entry
        }
        return grouped.map { key, entry in
            SystemRow(id: key, processName: entry.name, ports: entry.ports.sorted())
        }
        .sorted { $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending }
    }
}
