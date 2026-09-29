import Foundation

/// A listening TCP socket, stripped of process-table types so classification
/// can run in tests without libproc.
public struct Listener: Equatable, Sendable {
    public var port: Int
    public var pid: Int
    public var processName: String
    public var command: String
    public var cwd: String?

    public init(port: Int, pid: Int, processName: String, command: String, cwd: String? = nil) {
        self.port = port
        self.pid = pid
        self.processName = processName
        self.command = command
        self.cwd = cwd
    }
}

/// A plist from ~/Library/LaunchAgents, plus whether launchd currently has it loaded.
public struct LaunchAgentRecord: Equatable, Sendable, Identifiable {
    public var label: String
    public var plistPath: String
    public var program: String
    public var arguments: [String]
    public var disabled: Bool
    public var loaded: Bool

    public var id: String { label }

    public init(label: String, plistPath: String, program: String, arguments: [String], disabled: Bool, loaded: Bool) {
        self.label = label
        self.plistPath = plistPath
        self.program = program
        self.arguments = arguments
        self.disabled = disabled
        self.loaded = loaded
    }

    /// Label, program and arguments in one string for registry and noise matching.
    public var searchText: String {
        ([label, program] + arguments).joined(separator: " ")
    }
}

public struct BonjourService: Equatable, Sendable {
    public var name: String
    public var type: String
    public var host: String
    public var port: Int
    public var ipv4: String?

    public init(name: String, type: String, host: String, port: Int, ipv4: String? = nil) {
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.ipv4 = ipv4
    }
}

public struct ProbeResult: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var open: Bool

    public init(host: String, port: Int, open: Bool) {
        self.host = host
        self.port = port
        self.open = open
    }
}

public struct InventoryInput: Equatable, Sendable {
    public var listeners: [Listener]
    public var launchAgents: [LaunchAgentRecord]
    public var bonjour: [BonjourService]
    public var probes: [ProbeResult]
    public var nameLookup: [String: Bool]
    public var ipv4Cache: [String: String]

    public init(
        listeners: [Listener] = [],
        launchAgents: [LaunchAgentRecord] = [],
        bonjour: [BonjourService] = [],
        probes: [ProbeResult] = [],
        nameLookup: [String: Bool] = [:],
        ipv4Cache: [String: String] = [:]
    ) {
        self.listeners = listeners
        self.launchAgents = launchAgents
        self.bonjour = bonjour
        self.probes = probes
        self.nameLookup = nameLookup
        self.ipv4Cache = ipv4Cache
    }
}

public enum HelperRunState: String, Equatable, Sendable {
    case running
    case stopped
}

public struct HelperRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ports: [Int]
    public var runningPorts: [Int]
    public var listenerPIDs: [Int]
    public var agents: [LaunchAgentRecord]
    public var state: HelperRunState
    public var openURL: String?
    public var isCompanion: Bool
    /// Set when this row also belongs in Needs attention. Sidecars never set it.
    public var attention: AttentionKind?

    public init(
        id: String,
        name: String,
        ports: [Int],
        runningPorts: [Int],
        listenerPIDs: [Int],
        agents: [LaunchAgentRecord],
        state: HelperRunState,
        openURL: String?,
        isCompanion: Bool,
        attention: AttentionKind?
    ) {
        self.id = id
        self.name = name
        self.ports = ports
        self.runningPorts = runningPorts
        self.listenerPIDs = listenerPIDs
        self.agents = agents
        self.state = state
        self.openURL = openURL
        self.isCompanion = isCompanion
        self.attention = attention
    }

    public func stopPlan(uid: Int) -> LaunchControlPlan? { LaunchControl.stop(uid: uid, agents: agents) }
    public func startPlan(uid: Int) -> LaunchControlPlan? { LaunchControl.start(uid: uid, agents: agents) }
    public func restartPlan(uid: Int) -> LaunchControlPlan? { LaunchControl.restart(uid: uid, agents: agents) }
}

/// A non-HTTP sidecar that is running. Stopped sidecars are omitted entirely.
public struct SidecarRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var ports: [Int]
    public var listenerPIDs: [Int]
    public var agents: [LaunchAgentRecord]

    public init(id: String, name: String, ports: [Int], listenerPIDs: [Int], agents: [LaunchAgentRecord]) {
        self.id = id
        self.name = name
        self.ports = ports
        self.listenerPIDs = listenerPIDs
        self.agents = agents
    }

    public func stopPlan(uid: Int) -> LaunchControlPlan? { LaunchControl.stop(uid: uid, agents: agents) }
}

public struct SystemRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var processName: String
    public var ports: [Int]

    public init(id: String, processName: String, ports: [Int]) {
        self.id = id
        self.processName = processName
        self.ports = ports
    }

    public var portsLabel: String { ports.map(String.init).joined(separator: ", ") }
}

public struct LanDevice: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var host: String
    public var ipv4: String?
    public var serviceTypes: [String]
    public var openURL: String?
    public var firmwareOnly: Bool
    public var nameLookupFailed: Bool

    public init(
        id: String,
        name: String,
        host: String,
        ipv4: String?,
        serviceTypes: [String],
        openURL: String?,
        firmwareOnly: Bool,
        nameLookupFailed: Bool
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.ipv4 = ipv4
        self.serviceTypes = serviceTypes
        self.openURL = openURL
        self.firmwareOnly = firmwareOnly
        self.nameLookupFailed = nameLookupFailed
    }
}

public enum AttentionKind: String, Equatable, Sendable {
    case stoppedHelper
    case firmwareOnly
    case missingCompanion
}

public struct AttentionItem: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var kind: AttentionKind
    public var helperID: String?
    public var deviceID: String?

    public init(id: String, title: String, detail: String, kind: AttentionKind, helperID: String? = nil, deviceID: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
        self.kind = kind
        self.helperID = helperID
        self.deviceID = deviceID
    }
}

public struct ServiceInventory: Equatable, Sendable {
    public var helpers: [HelperRow]
    public var sidecars: [SidecarRow]
    public var systemRows: [SystemRow]
    public var lanDevices: [LanDevice]
    public var needsAttention: [AttentionItem]
    /// Ports that belong to a helper, sidecar or collapsed system listener,
    /// so the dev-server list does not show them again.
    public var hiddenPorts: Set<Int>

    public init(
        helpers: [HelperRow] = [],
        sidecars: [SidecarRow] = [],
        systemRows: [SystemRow] = [],
        lanDevices: [LanDevice] = [],
        needsAttention: [AttentionItem] = [],
        hiddenPorts: Set<Int> = []
    ) {
        self.helpers = helpers
        self.sidecars = sidecars
        self.systemRows = systemRows
        self.lanDevices = lanDevices
        self.needsAttention = needsAttention
        self.hiddenPorts = hiddenPorts
    }

    public static let empty = ServiceInventory()

    public var isEmpty: Bool {
        helpers.isEmpty && sidecars.isEmpty && systemRows.isEmpty && lanDevices.isEmpty && needsAttention.isEmpty
    }

    public var showsSectionHeaders: Bool {
        !needsAttention.isEmpty || !helpers.isEmpty || !sidecars.isEmpty || !lanDevices.isEmpty || !systemRows.isEmpty
    }
}

public struct LaunchControlPlan: Equatable, Sendable {
    public var commands: [[String]]

    public init(commands: [[String]]) {
        self.commands = commands
    }
}
