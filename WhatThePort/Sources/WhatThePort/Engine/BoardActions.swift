import Darwin
import DevServersCore
import Foundation

/// Stop, start and restart for a board card. LaunchAgent jobs boot out before
/// the process is signalled, then bootstrap and `kickstart -k` on the way back.
enum BoardActions {
    static func kill(_ item: BoardItem, uid: Int = Int(getuid())) -> String? {
        let pid = item.pid
        let port = item.port
        guard pid > 0, port > 0 else { return "Invalid process id" }
        let helper = KnownHelpers.matchKnownHelper(item)
        let label = helper?.launchAgent.nilIfEmpty ?? item.launchAgent.nilIfEmpty
        if let label {
            _ = LaunchAgentController.run(LaunchControlPlan(commands: [LaunchControl.bootout(uid: uid, label: label)]))
        }
        var targets = Set(listening(port: port))
        targets.insert(pid)
        for target in targets { signal(target, SIGTERM) }
        Thread.sleep(forTimeInterval: Double(LaunchControl.termWaitMs) / 1000)
        for target in listening(port: port) { targets.insert(target) }
        for target in targets where alive(target) { signal(target, SIGKILL) }
        Thread.sleep(forTimeInterval: Double(LaunchControl.killWaitMs) / 1000)
        let remaining = listening(port: port)
        if !remaining.isEmpty {
            for target in remaining {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/kill")
                process.arguments = ["-9", String(target)]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
            Thread.sleep(forTimeInterval: Double(LaunchControl.killWaitMs) / 1000)
        }
        let still = listening(port: port)
        if !still.isEmpty { return LaunchControl.stillListeningError(port: port, pids: still.sorted()) }
        return nil
    }

    static func start(_ item: BoardItem, uid: Int = Int(getuid())) -> String? {
        let helper = KnownHelpers.matchKnownHelper(item)
        let label = helper?.launchAgent.nilIfEmpty ?? item.launchAgent.nilIfEmpty
        guard helper != nil || label != nil, KnownHelpers.isLocalHelperHost(item.host) else {
            return "Start is only available for known helpers"
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if let label {
            let plist = KnownHelpers.plistPath(label, home: home)
            if FileManager.default.fileExists(atPath: plist) {
                let bootstrap = LaunchControlPlan(commands: [LaunchControl.bootstrap(uid: uid, plistPath: plist)])
                if LaunchAgentController.run(bootstrap) {
                    _ = LaunchAgentController.run(LaunchControlPlan(commands: [LaunchControl.kickstart(uid: uid, label: label)]))
                    return nil
                }
            }
        }
        let recipe: StartRecipe
        do {
            recipe = try KnownHelpers.resolveStartRecipe(item, home: home, exists: { FileManager.default.fileExists(atPath: $0) })
        } catch let error as StartRecipeError {
            if case .message(let text) = error { return text }
            return "Start is only available for known helpers"
        } catch {
            return "Start is only available for known helpers"
        }
        let process = Process()
        if recipe.command.hasPrefix("/") {
            process.executableURL = URL(fileURLWithPath: recipe.command)
            process.arguments = recipe.args
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [recipe.command] + recipe.args
        }
        if !recipe.cwd.isEmpty { process.currentDirectoryURL = URL(fileURLWithPath: recipe.cwd) }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            DispatchQueue.global(qos: .utility).async { process.waitUntilExit() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func listening(port: Int) -> [Int] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = Array(LaunchControl.lsofArgs(port: port).dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isWhitespace).compactMap { Int($0) }.filter { $0 > 0 }
    }

    private static func signal(_ pid: Int, _ code: Int32) {
        guard pid > 1, pid != Int(getpid()) else { return }
        Darwin.kill(pid_t(pid), code)
    }

    private static func alive(_ pid: Int) -> Bool {
        Darwin.kill(pid_t(pid), 0) == 0
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
