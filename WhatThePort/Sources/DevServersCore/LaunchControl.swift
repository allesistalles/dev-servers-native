import Foundation

/// `launchctl` command lines. Stop is bootout so launchd does not respawn the job.
/// Start is bootstrap then kickstart. Restart is both, in that order.
public enum LaunchControl {
    public static func guiDomain(uid: Int) -> String { "gui/\(uid)" }

    public static func serviceTarget(uid: Int, label: String) -> String { "gui/\(uid)/\(label)" }

    public static func stop(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        let commands = agents.map { agent in
            ["launchctl", "bootout", guiDomain(uid: uid), agent.plistPath]
        }
        return commands.isEmpty ? nil : LaunchControlPlan(commands: commands)
    }

    public static func start(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        guard !agents.isEmpty else { return nil }
        var commands: [[String]] = []
        for agent in agents {
            commands.append(["launchctl", "bootstrap", guiDomain(uid: uid), agent.plistPath])
            commands.append(["launchctl", "kickstart", serviceTarget(uid: uid, label: agent.label)])
        }
        return LaunchControlPlan(commands: commands)
    }

    public static func restart(uid: Int, agents: [LaunchAgentRecord]) -> LaunchControlPlan? {
        guard !agents.isEmpty else { return nil }
        var commands: [[String]] = []
        for agent in agents {
            commands.append(["launchctl", "bootout", guiDomain(uid: uid), agent.plistPath])
            commands.append(["launchctl", "bootstrap", guiDomain(uid: uid), agent.plistPath])
            commands.append(["launchctl", "kickstart", serviceTarget(uid: uid, label: agent.label)])
        }
        return LaunchControlPlan(commands: commands)
    }
}
