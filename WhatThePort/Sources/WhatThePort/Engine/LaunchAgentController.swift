import Darwin
import DevServersCore
import Foundation

/// Reads ~/Library/LaunchAgents and runs the launchctl plans from DevServersCore.
enum LaunchAgentController {
    static func load(uid: Int = Int(getuid())) -> [LaunchAgentRecord] {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "plist", let data = try? Data(contentsOf: url) else { return nil }
            let parsed = LaunchAgentPlist.parse(data, path: url.path, loaded: false)
            guard let parsed else { return nil }
            return LaunchAgentRecord(
                label: parsed.label,
                plistPath: url.path,
                program: parsed.program,
                arguments: parsed.arguments,
                disabled: parsed.disabled,
                loaded: isLoaded(uid: uid, label: parsed.label)
            )
        }
    }

    static func isLoaded(uid: Int, label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", LaunchControl.serviceTarget(uid: uid, label: label)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Runs each command. `bootout` is allowed to fail (the job may already be unloaded)
    /// so restart can continue into bootstrap and kickstart.
    @discardableResult
    static func run(_ plan: LaunchControlPlan) -> Bool {
        var requiredOK = true
        for command in plan.commands {
            guard command.count >= 2, command[0] == "launchctl" else { continue }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            process.arguments = Array(command.dropFirst())
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 && command[1] != "bootout" {
                    requiredOK = false
                }
            } catch {
                if command[1] != "bootout" { requiredOK = false }
            }
        }
        return requiredOK
    }

    static func signal(_ pids: [Int]) {
        for pid in pids where pid > 1 && pid != Int(getpid()) {
            kill(pid_t(pid), SIGTERM)
        }
    }
}
