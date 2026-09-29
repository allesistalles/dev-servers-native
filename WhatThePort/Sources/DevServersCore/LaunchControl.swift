import Foundation

/// `launchctl` command lines from the Electron app.
/// Bootout uses the service target `gui/<uid>/<label>`.
/// Bootstrap uses `gui/<uid>` plus the plist path. Kickstart passes `-k`.
public enum LaunchControl {
    public static func guiDomain(uid: Int) -> String { "gui/\(uid)" }

    public static func serviceTarget(uid: Int, label: String) -> String { "gui/\(uid)/\(label)" }

    public static func bootout(uid: Int, label: String) -> [String] {
        ["launchctl", "bootout", serviceTarget(uid: uid, label: label)]
    }

    public static func bootstrap(uid: Int, plistPath: String) -> [String] {
        ["launchctl", "bootstrap", guiDomain(uid: uid), plistPath]
    }

    public static func kickstart(uid: Int, label: String) -> [String] {
        ["launchctl", "kickstart", "-k", serviceTarget(uid: uid, label: label)]
    }

    public static func lsofArgs(port: Int) -> [String] {
        ["lsof", "-tiTCP:\(port)", "-sTCP:LISTEN"]
    }

    public static func killDashNine(pid: Int) -> [String] {
        ["/bin/kill", "-9", String(pid)]
    }

    public static let termWaitMs = 400
    public static let killWaitMs = 200

    public static func stillListeningError(port: Int, pids: [Int]) -> String {
        "Port \(port) still in use (pid \(pids.map(String.init).joined(separator: ", "))). Try again or kill it from Activity Monitor."
    }

    public static func stop(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        let commands = agents.map { bootout(uid: uid, label: $0.label) }
        return commands.isEmpty ? nil : LaunchControlPlan(commands: commands)
    }

    public static func start(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        guard !agents.isEmpty else { return nil }
        var commands: [[String]] = []
        for agent in agents {
            commands.append(bootstrap(uid: uid, plistPath: agent.plistPath))
            commands.append(kickstart(uid: uid, label: agent.label))
        }
        return LaunchControlPlan(commands: commands)
    }

    public static func restart(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        guard !agents.isEmpty else { return nil }
        var commands: [[String]] = []
        for agent in agents {
            commands.append(bootout(uid: uid, label: agent.label))
            commands.append(bootstrap(uid: uid, plistPath: agent.plistPath))
            commands.append(kickstart(uid: uid, label: agent.label))
        }
        return LaunchControlPlan(commands: commands)
    }
}
