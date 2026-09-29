import Foundation

/// A helper the Electron app already knew by port. `matchByPort` is off for
/// :5177 so an unrelated Vite server on that port stays a dev server.
public struct KnownHelper: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ports: [Int]
    public var matchTokens: [String]
    public var matchByPort: Bool
    public var isCompanion: Bool

    public init(id: String, name: String, ports: [Int], matchTokens: [String], matchByPort: Bool, isCompanion: Bool) {
        self.id = id
        self.name = name
        self.ports = ports
        self.matchTokens = matchTokens
        self.matchByPort = matchByPort
        self.isCompanion = isCompanion
    }

    public static let all: [KnownHelper] = [
        KnownHelper(
            id: "blackberry",
            name: "Blackberry",
            ports: [8888, 8899, 8900],
            matchTokens: ["blackberry"],
            matchByPort: true,
            isCompanion: false
        ),
        KnownHelper(
            id: "dialdash",
            name: "DialDash",
            ports: [7878],
            matchTokens: ["dialdash", "dial-dash"],
            matchByPort: true,
            isCompanion: false
        ),
        KnownHelper(
            id: "droppic",
            name: "Droppic",
            ports: [8787],
            matchTokens: ["droppic"],
            matchByPort: true,
            isCompanion: false
        ),
        KnownHelper(
            id: "p1s-bridge",
            name: "P1S bridge",
            ports: [8765],
            matchTokens: ["p1s-bridge", "p1sbridge", "p1s_bridge"],
            matchByPort: true,
            isCompanion: false
        ),
        KnownHelper(
            id: "claude-mem",
            name: "Claude-mem",
            ports: [37777],
            matchTokens: ["claude-mem", "claudemem", "claude_mem"],
            matchByPort: true,
            isCompanion: false
        ),
        KnownHelper(
            id: "led-round-dial",
            name: "LED Round Dial",
            ports: [5177],
            matchTokens: ["led-round-dial", "ledrounddial", "led round dial"],
            matchByPort: false,
            isCompanion: true
        ),
    ]

    public static func matching(port: Int) -> KnownHelper? {
        all.first { $0.matchByPort && $0.ports.contains(port) }
    }

    public func matches(agent: LaunchAgentRecord) -> Bool {
        if matches(text: agent.searchText) { return true }
        if matchByPort {
            let mentioned = PortMentions.ports(in: agent.arguments + [agent.program])
            return !Set(mentioned).isDisjoint(with: Set(ports))
        }
        return false
    }

    public func matches(listener: Listener) -> Bool {
        if matchByPort && ports.contains(listener.port) { return true }
        let text = [listener.processName, listener.command, listener.cwd ?? ""].joined(separator: " ")
        return matches(text: text)
    }

    private func matches(text: String) -> Bool {
        let haystack = text.lowercased()
        return matchTokens.contains { haystack.contains($0) }
    }
}

enum PortMentions {
    static func ports(in arguments: [String]) -> [Int] {
        var ports: [Int] = []
        var index = 0
        while index < arguments.count {
            let token = arguments[index]
            if token == "--port" || token == "-p" || token == "-port", index + 1 < arguments.count {
                if let port = Int(arguments[index + 1]) { ports.append(port) }
                index += 2
                continue
            }
            for flag in ["--port=", "-p", "-port="] where token.hasPrefix(flag) {
                let rest = token.dropFirst(flag.count)
                if let port = Int(rest) { ports.append(port) }
            }
            if let range = token.range(of: ":") {
                let tail = token[range.upperBound...]
                let digits = tail.prefix { $0.isNumber }
                if let port = Int(digits), (1...65535).contains(port), digits.count == tail.filter(\.isNumber).count || token.contains("://") {
                    if token.contains("://") || token.hasPrefix(":") {
                        ports.append(port)
                    }
                }
            }
            index += 1
        }
        return ports
    }
}
