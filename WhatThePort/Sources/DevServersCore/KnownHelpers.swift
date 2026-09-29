import Foundation

public struct HelperSpec: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var port: Int
    public var cwdCandidates: [String]
    public var command: String
    public var args: [String]
    public var launch: String
    public var launchAgent: String

    public init(id: String, title: String, port: Int, cwdCandidates: [String] = [], command: String = "", args: [String] = [], launch: String = "", launchAgent: String = "") {
        self.id = id
        self.title = title
        self.port = port
        self.cwdCandidates = cwdCandidates
        self.command = command
        self.args = args
        self.launch = launch
        self.launchAgent = launchAgent
    }
}

public struct HelperOverride: Equatable, Sendable {
    public var cwd: String
    public var command: String
    public var args: [String]
    public var hasCwd: Bool
    public var hasCommand: Bool
    public var hasArgs: Bool

    public init(cwd: String = "", command: String = "", args: [String] = [], hasCwd: Bool = false, hasCommand: Bool = false, hasArgs: Bool = false) {
        self.cwd = cwd
        self.command = command
        self.args = args
        self.hasCwd = hasCwd
        self.hasCommand = hasCommand
        self.hasArgs = hasArgs
    }
}

public struct StartRecipe: Equatable, Sendable {
    public var command: String
    public var args: [String]
    public var cwd: String
    public var title: String
}

public enum StartRecipeError: Error, Equatable {
    case message(String)
}

public enum KnownHelpers {
    public static let all: [HelperSpec] = [
        HelperSpec(id: "blackberry-web", title: "Blackberry web", port: 8888, cwdCandidates: ["all cloned from github/blackberry 1/mac/web", "blackberry 1/mac/web"], command: "python3", args: ["server.py"], launch: "the Blackberry Mac web UI", launchAgent: "com.roy.bb-hub"),
        HelperSpec(id: "blackberry-static", title: "Blackberry static", port: 8899, cwdCandidates: ["all cloned from github/blackberry 1/mac/web", "blackberry 1/mac/web"], command: "python3", args: ["-m", "http.server", "8899", "--bind", "0.0.0.0", "--directory"], launch: "the Blackberry static file server", launchAgent: "com.roy.bb-pages"),
        HelperSpec(id: "blackberry-clip", title: "Blackberry clip", port: 8900, cwdCandidates: ["all cloned from github/blackberry 1/mac/web", "blackberry 1/mac/web"], command: "python3", args: ["clip.py"], launch: "the Blackberry clip helper", launchAgent: "com.roy.bb-clip"),
        HelperSpec(id: "dialdash", title: "DialDash", port: 7878, cwdCandidates: ["all cloned from github/DialDash/mac_bridge", "DialDash/mac_bridge"], command: "python3", args: ["-u", "bridge.py"], launch: "the DialDash Mac bridge", launchAgent: "com.screendial.tray"),
        HelperSpec(id: "droppic", title: "Droppic", port: 8787, cwdCandidates: ["all cloned from github/mx keys dial and screen/helper", "mx keys dial and screen/helper"], command: "node", args: ["--env-file=.env", "src/server.mjs"], launch: "the Droppic helper", launchAgent: "com.roykorkomaz.mx-keys-image-helper"),
        HelperSpec(id: "p1s", title: "P1S", port: 8765, cwdCandidates: ["all cloned from github/tiny-desk-thing/bridge", "tiny-desk-thing/bridge"], command: "uvicorn", args: ["main:app", "--host", "0.0.0.0", "--port", "8765"], launch: "the P1S Live Build helper", launchAgent: "com.tinydeskthing.bridge"),
        HelperSpec(id: "claude-mem", title: "Claude-mem", port: 37777, command: "bun", args: ["--daemon"], launch: "the Claude-mem worker daemon", launchAgent: "com.claude-mem.worker"),
        HelperSpec(id: "led-round-dial", title: "LED Round Dial", port: 5177, cwdCandidates: ["all cloned from github/led-round-dial/companion", "led-round-dial/companion"], command: "npm", args: ["run", "dev"], launch: "the LED Round Dial companion"),
    ]

    public static func byId(_ id: String) -> HelperSpec? { all.first { $0.id == id } }

    public static func isLocalHelperHost(_ host: String) -> Bool {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        return value.isEmpty || value == "localhost" || value == "127.0.0.1" || value == "::1"
    }

    static func hayOf(_ item: BoardItem) -> String {
        ([item.command, item.args.joined(separator: " "), item.cwd, item.shortCwd, item.project, item.title, item.host] as [String])
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    public static func matchKnownHelper(_ item: BoardItem, helpers: [HelperSpec] = KnownHelpers.all) -> HelperSpec? {
        if !item.helperId.isEmpty, let found = helpers.first(where: { $0.id == item.helperId }) { return found }
        if !item.launchAgent.isEmpty, let byLabel = helpers.first(where: { $0.launchAgent == item.launchAgent }) { return byLabel }
        let port = item.port
        let hay = hayOf(item)
        let berry = HostTitles.isBlackberryWebDir(hay)
        if port == 8888 && berry { return helpers.first { $0.id == "blackberry-web" } }
        if port == 8899 && berry { return helpers.first { $0.id == "blackberry-static" } }
        if port == 8900 && (berry || hay.range(of: "\\bclip\\.py\\b", options: .regularExpression) != nil) {
            return helpers.first { $0.id == "blackberry-clip" }
        }
        if port == 7878 || hay.range(of: "dialdash|mac_bridge|mac-bridge", options: .regularExpression) != nil {
            return helpers.first { $0.id == "dialdash" }
        }
        if port == 37777 || (hay.contains("claude-mem") && hay.contains("worker-service.cjs")) {
            return helpers.first { $0.id == "claude-mem" }
        }
        if port == 5177 || (hay.contains("led-round-dial") && hay.contains("companion")) {
            return helpers.first { $0.id == "led-round-dial" }
        }
        if (port == 8787 || hay.range(of: "droppic|mx-keys-image-helper", options: .regularExpression) != nil) && hay.range(of: "translat", options: .regularExpression) == nil {
            return helpers.first { $0.id == "droppic" }
        }
        if port == 8765 { return helpers.first { $0.id == "p1s" } }
        return nil
    }

    public static func canStartItem(_ item: BoardItem?) -> Bool {
        guard let item else { return false }
        if item.pid > 0 { return false }
        if !item.status.isEmpty && item.status != "down" { return false }
        if !isLocalHelperHost(item.host) { return false }
        if item.kind == "system" { return false }
        return matchKnownHelper(item) != nil || !item.launchAgent.isEmpty
    }

    public static func offlineItem(_ helper: HelperSpec) -> BoardItem {
        var item = BoardItem(
            id: "known:\(helper.id)",
            title: helper.title,
            url: "http://localhost:\(helper.port)",
            host: "localhost",
            port: helper.port,
            source: "local",
            status: "down",
            openable: false,
            startable: !helper.launchAgent.isEmpty || !helper.command.isEmpty || !helper.id.isEmpty,
            helperId: helper.id
        )
        if !helper.launchAgent.isEmpty { item.launchAgent = helper.launchAgent }
        return item
    }

    public static func plistPath(_ label: String, home: String) -> String {
        joinPath(joinPath(joinPath(home, "Library"), "LaunchAgents"), "\(label).plist")
    }

    public static func resolveCwd(_ helper: HelperSpec, home: String, exists: (String) -> Bool, overrides: [String: HelperOverride] = [:]) -> String? {
        if let override = overrides[helper.id], override.hasCwd, !override.cwd.isEmpty { return override.cwd }
        for rel in helper.cwdCandidates {
            let abs = joinPath(home, rel)
            if exists(abs) { return abs }
        }
        return nil
    }

    static func resolvePython(_ cwd: String, exists: (String) -> Bool) -> String {
        for rel in [".venv/bin/python", "venv/bin/python", ".venv/bin/python3", "venv/bin/python3"] {
            let abs = joinPath(cwd, rel)
            if exists(abs) { return abs }
        }
        return "python3"
    }

    public static func resolveStartRecipe(
        _ item: BoardItem,
        home: String,
        exists: (String) -> Bool = { _ in false },
        overrides: [String: HelperOverride] = [:],
        workerPath: String? = nil,
        lastLaunch: [String: StartRecipe] = [:]
    ) throws -> StartRecipe {
        guard let helper = matchKnownHelper(item) else { throw StartRecipeError.message("Start is only available for known helpers") }
        let ov = overrides[helper.id] ?? HelperOverride()
        if helper.id == "claude-mem" {
            if ov.hasCommand || ov.hasArgs {
                return StartRecipe(command: ov.hasCommand ? ov.command : "bun", args: ov.hasArgs ? ov.args : [ov.cwd, "--daemon"].filter { !$0.isEmpty }, cwd: ov.hasCwd ? ov.cwd : home, title: helper.title)
            }
            if let last = lastLaunch[helper.id], !last.command.isEmpty {
                var args = last.args.isEmpty ? ["--daemon"] : last.args
                if !args.contains("--daemon") && args.contains(where: { $0.contains("worker-service.cjs") }) { args.append("--daemon") }
                return StartRecipe(command: last.command, args: args, cwd: last.cwd.isEmpty ? (ov.hasCwd ? ov.cwd : home) : last.cwd, title: helper.title)
            }
            guard let worker = workerPath, !worker.isEmpty else {
                throw StartRecipeError.message("Could not find claude-mem worker-service.cjs. Set it in ~/.config/dev-servers/helpers.json")
            }
            return StartRecipe(command: "bun", args: [worker, "--daemon"], cwd: ov.hasCwd ? ov.cwd : home, title: helper.title)
        }
        guard let cwd = ov.hasCwd ? ov.cwd : resolveCwd(helper, home: home, exists: exists, overrides: overrides) else {
            throw StartRecipeError.message("Missing working directory for \(helper.title). Set it in ~/.config/dev-servers/helpers.json")
        }
        var command = ov.hasCommand ? ov.command : helper.command
        var args = ov.hasArgs ? ov.args : helper.args
        if !ov.hasCommand && (helper.id == "blackberry-web" || helper.id == "blackberry-clip" || helper.id == "dialdash") {
            command = resolvePython(cwd, exists: exists)
        }
        if helper.id == "blackberry-static" && !ov.hasArgs {
            args = ["-m", "http.server", "8899", "--bind", "0.0.0.0", "--directory", cwd]
            if !ov.hasCommand { command = resolvePython(cwd, exists: exists) }
        }
        if helper.id == "p1s" && !ov.hasCommand {
            let venv = [joinPath(cwd, ".venv/bin/uvicorn"), joinPath(cwd, "venv/bin/uvicorn")].first { exists($0) }
            if let venv {
                command = venv
                args = ov.hasArgs ? ov.args : ["main:app", "--host", "0.0.0.0", "--port", "8765"]
            } else {
                command = resolvePython(cwd, exists: exists)
                args = ["-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8765"]
            }
        }
        return StartRecipe(command: command, args: args, cwd: cwd, title: helper.title)
    }

    public static func joinPath(_ base: String, _ rel: String) -> String {
        if rel.hasPrefix("/") { return rel }
        if base.hasSuffix("/") { return base + rel }
        return base + "/" + rel
    }
}
