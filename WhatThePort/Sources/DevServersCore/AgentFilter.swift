import Foundation

public struct ParsedLaunchAgent: Equatable, Sendable {
    public var label: String
    public var cwd: String
    public var args: [String]
    public var plistPath: String
    public var loaded: Bool

    public init(label: String = "", cwd: String = "", args: [String] = [], plistPath: String = "", loaded: Bool = false) {
        self.label = label
        self.cwd = cwd
        self.args = args
        self.plistPath = plistPath
        self.loaded = loaded
    }
}

public enum AgentFilter {
    static let agentTitles = [
        "com.cydanalytics.claude-forwarder": "Claude forwarder",
        "com.cydanalytics.opencode-forwarder": "OpenCode forwarder",
        "com.tinydeskthing.mdns": "P1S mdns",
        "com.tinydeskthing.menubar": "P1S menubar",
    ]
    static let productFolders: Set<String> = ["devdash", "tiny-desk-thing", "tinydeskthing", "blackberry", "blackberry 1", "dialdash", "claude-mem"]

    public static func parseXML(_ xml: String) -> ParsedLaunchAgent {
        ParsedLaunchAgent(label: matchString(xml, key: "Label"), cwd: matchString(xml, key: "WorkingDirectory"), args: matchArray(xml, key: "ProgramArguments"))
    }

    public static func isSystemAgentLabel(_ label: String) -> Bool {
        label.range(of: "^(com\\.apple\\.|com\\.spotify\\.|com\\.docker\\.|com\\.microsoft\\.|com\\.google\\.)", options: [.regularExpression, .caseInsensitive]) != nil
    }

    public static func portFromArgs(_ args: [String]) -> Int {
        for (index, token) in args.enumerated() {
            if token.range(of: "^--port(?:=|$)", options: .regularExpression) != nil {
                let inline = token.contains("=") ? String(token.split(separator: "=", maxSplits: 1).last ?? "") : (index + 1 < args.count ? args[index + 1] : "")
                if let port = Int(inline), port > 0 { return port }
            }
            if token.range(of: "^\\d{2,5}$", options: .regularExpression) != nil, let port = Int(token), port >= 80 { return port }
        }
        return 0
    }

    public static func looksHTTP(_ parsed: ParsedLaunchAgent) -> Bool {
        let hay = "\(parsed.args.joined(separator: " ")) \(parsed.cwd)".lowercased()
        if portFromArgs(parsed.args) > 0 { return true }
        return hay.range(of: "python|node|bun|uvicorn|http\\.server|vite|next|flask|gunicorn|server\\.py|clip\\.py", options: .regularExpression) != nil
    }

    static func cloneFolderName(_ cwd: String) -> String {
        let lower = cwd.lowercased()
        guard let marker = lower.range(of: "all cloned from github") else { return "" }
        let rest = String(cwd[marker.upperBound]).split { $0 == "/" || $0 == "\\" }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return rest.first ?? ""
    }

    static func scriptTitle(_ args: [String]) -> String {
        if let moduleAt = args.firstIndex(where: { $0 == "-m" || $0 == "--module" }), moduleAt + 1 < args.count {
            let parts = args[moduleAt + 1].split(separator: ".").map(String.init).filter { !$0.isEmpty }
            return (parts.last ?? "").replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
        }
        for token in args.reversed() {
            let base = token.split { $0 == "/" || $0 == "\\" }.last.map(String.init) ?? token
            if base.range(of: "\\.(py|js|mjs|cjs|ts)$", options: [.regularExpression, .caseInsensitive]) != nil {
                return base.replacingOccurrences(of: "\\.[a-z0-9]+$", with: "", options: [.regularExpression, .caseInsensitive])
                    .replacingOccurrences(of: "[_-]+", with: " ", options: .regularExpression)
            }
        }
        return ""
    }

    public static func agentTitle(_ parsed: ParsedLaunchAgent) -> String {
        if let title = agentTitles[parsed.label] { return title }
        let folder = cloneFolderName(parsed.cwd)
        let script = scriptTitle(parsed.args)
        if !folder.isEmpty && productFolders.contains(folder.lowercased()) && !script.isEmpty { return script }
        if !folder.isEmpty { return folder }
        if !script.isEmpty { return script }
        let tail = parsed.label.split(separator: ".").map(String.init).filter { !$0.isEmpty }.suffix(2).joined(separator: " ")
        return tail.isEmpty ? (parsed.label.isEmpty ? "LaunchAgent" : parsed.label) : tail
    }

    public static func helperFromLaunchAgent(_ parsed: ParsedLaunchAgent, home: String = "") -> HelperSpec? {
        guard !parsed.label.isEmpty else { return nil }
        if let known = KnownHelpers.all.first(where: { $0.launchAgent == parsed.label }) { return known }
        if isSystemAgentLabel(parsed.label) || !looksHTTP(parsed) { return nil }
        let port = portFromArgs(parsed.args)
        let title = agentTitle(parsed)
        var cwdCandidates: [String] = []
        if !parsed.cwd.isEmpty && !home.isEmpty && parsed.cwd.hasPrefix(home) {
            var rel = String(parsed.cwd.dropFirst(home.count))
            while rel.hasPrefix("/") || rel.hasPrefix("\\") { rel.removeFirst() }
            cwdCandidates = [rel]
        } else if !parsed.cwd.isEmpty {
            cwdCandidates = [parsed.cwd]
        }
        return HelperSpec(
            id: "agent:\(parsed.label)",
            title: title,
            port: port,
            cwdCandidates: cwdCandidates,
            command: parsed.args.first ?? "",
            args: Array(parsed.args.dropFirst()),
            launch: title,
            launchAgent: parsed.label
        )
    }

    public static func mergeRegistries(_ base: [HelperSpec] = KnownHelpers.all, _ extra: [HelperSpec]) -> [HelperSpec] {
        var seen = Set<String>()
        var out: [HelperSpec] = []
        for helper in base + extra {
            let key = helper.launchAgent.isEmpty ? helper.id : helper.launchAgent
            if key.isEmpty || seen.contains(key) || seen.contains(helper.id) { continue }
            seen.insert(key)
            seen.insert(helper.id)
            out.append(helper)
        }
        return out
    }

    public static func sidecarTitle(label: String = "", command: String = "", args: [String] = [], cwd: String = "") -> String? {
        if let title = agentTitles[label] { return title }
        let blob = "\(command) \(args.joined(separator: " ")) \(cwd) \(label)".lowercased()
        if blob.contains("p1s") && blob.contains("mdns") { return "P1S mdns" }
        if blob.contains("p1s") && (blob.contains("menubar") || blob.contains("menu-bar") || blob.contains("menu_bar")) { return "P1S menubar" }
        if blob.contains("opencode") && (blob.contains("forward") || blob.contains("sidecar")) { return "OpenCode forwarder" }
        let claudeMem = blob.contains("claude-mem") || blob.contains("claudemem") || blob.contains("claude_mem")
        if !claudeMem && blob.contains("claude") && (blob.contains("forward") || blob.contains("sidecar")) { return "Claude forwarder" }
        return nil
    }

    static func matchString(_ xml: String, key: String) -> String {
        let pattern = "<key>\(key)</key>\\s*<string>([^<]*)</string>"
        guard let match = DnsSdParse.firstMatch(pattern, in: xml, insensitive: true), match.count >= 2 else { return "" }
        return decode(match[1])
    }

    static func matchArray(_ xml: String, key: String) -> [String] {
        let pattern = "<key>\(key)</key>\\s*<array>([\\s\\S]*?)</array>"
        guard let match = DnsSdParse.firstMatch(pattern, in: xml, insensitive: true), match.count >= 2 else { return [] }
        guard let regex = try? NSRegularExpression(pattern: "<string>([^<]*)</string>", options: [.caseInsensitive]) else { return [] }
        let block = match[1]
        return regex.matches(in: block, range: NSRange(block.startIndex..., in: block)).compactMap { found in
            guard let slice = Range(found.range(at: 1), in: block) else { return nil }
            return decode(String(block[slice]))
        }
    }

    static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
