import Foundation

/// One card on the board. Fields mirror the Electron app's board item.
public struct BoardItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var url: String
    public var host: String
    public var port: Int
    public var ports: [Int]
    public var source: String
    public var status: String
    public var openable: Bool
    public var kind: String
    public var label: String
    public var pid: Int
    public var project: String
    public var framework: String
    public var cwd: String
    public var shortCwd: String
    public var command: String
    public var args: [String]
    public var startable: Bool
    public var restartable: Bool
    public var helperId: String
    public var launchAgent: String
    public var description: String
    public var address: String
    public var copyable: Bool
    public var attention: String
    public var htmlTitle: String
    public var instance: String

    public init(
        id: String = "",
        title: String = "",
        url: String = "",
        host: String = "",
        port: Int = 0,
        ports: [Int] = [],
        source: String = "",
        status: String = "up",
        openable: Bool = true,
        kind: String = "",
        label: String = "",
        pid: Int = 0,
        project: String = "",
        framework: String = "",
        cwd: String = "",
        shortCwd: String = "",
        command: String = "",
        args: [String] = [],
        startable: Bool = false,
        restartable: Bool = false,
        helperId: String = "",
        launchAgent: String = "",
        description: String = "",
        address: String = "",
        copyable: Bool = false,
        attention: String = "",
        htmlTitle: String = "",
        instance: String = ""
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.host = host
        self.port = port
        self.ports = ports
        self.source = source
        self.status = status
        self.openable = openable
        self.kind = kind
        self.label = label
        self.pid = pid
        self.project = project
        self.framework = framework
        self.cwd = cwd
        self.shortCwd = shortCwd
        self.command = command
        self.args = args
        self.startable = startable
        self.restartable = restartable
        self.helperId = helperId
        self.launchAgent = launchAgent
        self.description = description
        self.address = address
        self.copyable = copyable
        self.attention = attention
        self.htmlTitle = htmlTitle
        self.instance = instance
    }
}

/// A local listener before it becomes a board card.
public struct LocalServer: Equatable, Sendable {
    public var url: String
    public var pid: Int
    public var port: Int
    public var ports: [Int]
    public var project: String
    public var framework: String
    public var cwd: String
    public var shortCwd: String
    public var command: String
    public var args: [String]
    public var kind: String
    public var title: String
    public var htmlTitle: String
    public var host: String
    public var label: String
    public var launchAgent: String

    public init(
        url: String = "",
        pid: Int = 0,
        port: Int = 0,
        ports: [Int] = [],
        project: String = "",
        framework: String = "",
        cwd: String = "",
        shortCwd: String = "",
        command: String = "",
        args: [String] = [],
        kind: String = "",
        title: String = "",
        htmlTitle: String = "",
        host: String = "",
        label: String = "",
        launchAgent: String = ""
    ) {
        self.url = url
        self.pid = pid
        self.port = port
        self.ports = ports
        self.project = project
        self.framework = framework
        self.cwd = cwd
        self.shortCwd = shortCwd
        self.command = command
        self.args = args
        self.kind = kind
        self.title = title
        self.htmlTitle = htmlTitle
        self.host = host
        self.label = label
        self.launchAgent = launchAgent
    }
}

public enum BoardTab: String, CaseIterable, Sendable, Identifiable {
    case overview, all, local, lan, stopped, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .overview: return "Overview"
        case .all: return "All"
        case .local: return "Local"
        case .lan: return "LAN"
        case .stopped: return "Stopped"
        case .system: return "System"
        }
    }
}

public enum CardActions {
    public static func canOpen(_ item: BoardItem) -> Bool {
        item.openable && item.status != "down" && !item.url.isEmpty
    }

    public static func canKill(_ item: BoardItem) -> Bool {
        if item.kind == "system" { return false }
        return item.source == "local" && item.pid > 0
    }

    public static func canStart(_ item: BoardItem) -> Bool {
        item.startable && item.status == "down" && !canKill(item)
    }

    public static func canRestart(_ item: BoardItem) -> Bool {
        item.restartable && canKill(item)
    }
}
