import Foundation
import Testing
@testable import DevServersCore

struct InventoryTests {
    private func agent(_ label: String, path: String, arguments: [String], loaded: Bool) -> LaunchAgentRecord {
        LaunchAgentRecord(label: label, plistPath: path, program: arguments.first ?? "", arguments: arguments, disabled: false, loaded: loaded)
    }

    @Test func stoppedHelpersStayVisibleAndRestartBootsOutThenBackIn() {
        let plist = "/Users/roy/Library/LaunchAgents/com.blackberry.server.plist"
        let input = InventoryInput(
            launchAgents: [agent("com.blackberry.server", path: plist, arguments: ["/usr/local/bin/blackberry", "--port", "8888"], loaded: false)]
        )
        let inventory = InventoryBuilder.build(input)
        let row = inventory.helpers.first { $0.id == "blackberry" }
        #expect(row?.state == .stopped)
        #expect(row?.attention == .stoppedHelper)
        #expect(inventory.needsAttention.contains { $0.helperID == "blackberry" && $0.kind == .stoppedHelper })

        let stop = row?.stopPlan(uid: 501)
        #expect(stop?.commands == [["launchctl", "bootout", "gui/501", plist]])
        let start = row?.startPlan(uid: 501)
        #expect(start?.commands == [
            ["launchctl", "bootstrap", "gui/501", plist],
            ["launchctl", "kickstart", "gui/501/com.blackberry.server"],
        ])
        let restart = row?.restartPlan(uid: 501)
        #expect(restart?.commands == [
            ["launchctl", "bootout", "gui/501", plist],
            ["launchctl", "bootstrap", "gui/501", plist],
            ["launchctl", "kickstart", "gui/501/com.blackberry.server"],
        ])
    }

    @Test func blackberryPortsCollapseToOneRunningHelper() {
        let input = InventoryInput(listeners: [
            Listener(port: 8888, pid: 1, processName: "node", command: "blackberry"),
            Listener(port: 8899, pid: 1, processName: "node", command: "blackberry api"),
            Listener(port: 8900, pid: 2, processName: "node", command: "blackberry worker"),
        ])
        let inventory = InventoryBuilder.build(input)
        let rows = inventory.helpers.filter { $0.id == "blackberry" }
        #expect(rows.count == 1)
        #expect(rows[0].state == .running)
        #expect(rows[0].runningPorts == [8888, 8899, 8900])
        #expect(rows[0].attention == nil)
        #expect(rows[0].openURL == "http://127.0.0.1:8888")
        #expect(inventory.hiddenPorts.isSuperset(of: [8888, 8899, 8900]))
        #expect(!inventory.needsAttention.contains { $0.helperID == "blackberry" })
    }

    @Test func missingCompanionOverlapsHelpersAndAttention() {
        let inventory = InventoryBuilder.build(InventoryInput())
        let row = inventory.helpers.first { $0.id == "led-round-dial" }
        #expect(row?.state == .stopped)
        #expect(row?.isCompanion == true)
        #expect(row?.attention == .missingCompanion)
        #expect(inventory.needsAttention.contains { $0.kind == .missingCompanion && $0.helperID == "led-round-dial" })
    }

    @Test func viteOn5177IsNotTheLedCompanion() {
        let input = InventoryInput(listeners: [
            Listener(port: 5177, pid: 9, processName: "node", command: "vite", cwd: "/tmp/blog"),
        ])
        let inventory = InventoryBuilder.build(input)
        #expect(!inventory.hiddenPorts.contains(5177))
        #expect(inventory.helpers.first { $0.id == "led-round-dial" }?.runningPorts.isEmpty == true)
    }

    @Test func ledCompanionClaimsItsOwnListener() {
        let input = InventoryInput(listeners: [
            Listener(port: 5177, pid: 9, processName: "node", command: "vite", cwd: "/Users/roy/led-round-dial"),
        ])
        let inventory = InventoryBuilder.build(input)
        #expect(inventory.hiddenPorts.contains(5177))
        #expect(inventory.helpers.first { $0.id == "led-round-dial" }?.state == .running)
        #expect(!inventory.needsAttention.contains { $0.helperID == "led-round-dial" })
    }

    @Test func sidecarsAreNamedAndKeptOutOfStoppedAndAttention() {
        let running = InventoryInput(listeners: [
            Listener(port: 4318, pid: 4, processName: "node", command: "claude-forwarder"),
            Listener(port: 4320, pid: 5, processName: "opencode-forwarder", command: "opencode forward"),
            Listener(port: 5353, pid: 6, processName: "p1s-mdns", command: "p1s mdns"),
            Listener(port: 5354, pid: 7, processName: "p1s-menubar", command: "p1s menubar"),
        ])
        let inventory = InventoryBuilder.build(running)
        #expect(Set(inventory.sidecars.map(\.name)) == ["Claude forwarder", "OpenCode forwarder", "P1S mDNS", "P1S menu bar"])
        #expect(inventory.needsAttention.allSatisfy { $0.kind == .missingCompanion || $0.kind == .stoppedHelper })
        #expect(!inventory.needsAttention.contains { $0.title.contains("forward") || $0.title.contains("P1S m") })
        #expect(inventory.hiddenPorts.isSuperset(of: [4318, 4320, 5353, 5354]))

        let stopped = InventoryBuilder.build(InventoryInput(launchAgents: [
            agent("com.p1s.mdns", path: "/tmp/p1s.mdns.plist", arguments: ["p1s-mdns"], loaded: false),
        ]))
        #expect(!stopped.sidecars.contains { $0.name == "P1S mDNS" })
        #expect(!stopped.helpers.contains { $0.name == "P1S mDNS" })
        #expect(!stopped.needsAttention.contains { $0.title == "P1S mDNS" || $0.title.contains("mdns") })
    }

    @Test func claudeMemIsAHelperNotAForwarder() {
        let input = InventoryInput(listeners: [
            Listener(port: 37777, pid: 3, processName: "bun", command: "claude-mem worker"),
        ])
        let inventory = InventoryBuilder.build(input)
        #expect(inventory.helpers.first { $0.id == "claude-mem" }?.state == .running)
        #expect(!inventory.sidecars.contains { $0.name == "Claude forwarder" })
    }

    @Test func spotifyAndRapportdCollapseToOneRowEach() {
        let input = InventoryInput(listeners: [
            Listener(port: 57621, pid: 10, processName: "Spotify", command: "Spotify"),
            Listener(port: 57622, pid: 11, processName: "Spotify Helper", command: "Spotify Helper"),
            Listener(port: 5353, pid: 12, processName: "rapportd", command: "rapportd"),
            Listener(port: 49152, pid: 12, processName: "rapportd", command: "rapportd"),
            Listener(port: 3000, pid: 13, processName: "node", command: "next dev"),
        ])
        let inventory = InventoryBuilder.build(input)
        let spotify = inventory.systemRows.first { $0.id == "spotify" }
        let helper = inventory.systemRows.first { $0.id == "spotify helper" }
        let rapport = inventory.systemRows.first { $0.id == "rapportd" }
        #expect(spotify?.ports == [57621])
        #expect(helper?.ports == [57622])
        #expect(rapport?.ports == [5353, 49152])
        #expect(rapport?.portsLabel == "5353, 49152")
        #expect(inventory.hiddenPorts.isSuperset(of: [57621, 57622, 5353, 49152]))
        #expect(!inventory.hiddenPorts.contains(3000))
        #expect(!inventory.needsAttention.contains { $0.title == "Spotify" || $0.title == "rapportd" })
    }

    @Test func discoveredLaunchAgentAppearsWhenStopped() {
        let input = InventoryInput(launchAgents: [
            agent("com.example.notes", path: "/Users/roy/Library/LaunchAgents/com.example.notes.plist", arguments: ["/usr/local/bin/notes"], loaded: false),
        ])
        let inventory = InventoryBuilder.build(input)
        let row = inventory.helpers.first { $0.id == "agent:com.example.notes" }
        #expect(row?.state == .stopped)
        #expect(inventory.needsAttention.contains { $0.helperID == "agent:com.example.notes" })
    }

    @Test func monsterOpensByCachedIPv4WhenLocalDNSFails() {
        let input = InventoryInput(
            probes: [ProbeResult(host: "192.168.0.148", port: 80, open: true)],
            nameLookup: ["monster.local": false]
        )
        let device = InventoryBuilder.build(input).lanDevices.first { $0.name == "Monster Settings" }
        #expect(device?.openURL == "http://192.168.0.148")
        #expect(device?.nameLookupFailed == true)
        #expect(device?.firmwareOnly == false)
    }

    @Test func monsterKeepsItsNameWhenLookupWorks() {
        let input = InventoryInput(
            probes: [ProbeResult(host: "monster.local", port: 80, open: true)],
            nameLookup: ["monster.local": true]
        )
        let device = InventoryBuilder.build(input).lanDevices.first { $0.name == "Monster Settings" }
        #expect(device?.openURL == "http://monster.local")
        #expect(device?.nameLookupFailed == false)
    }

    @Test func bonjourIPv4CacheIsUsedWhenTheSeedIsNotTheSource() {
        let input = InventoryInput(
            bonjour: [BonjourService(name: "Printer", type: "_http._tcp.", host: "printer.local.", port: 80)],
            probes: [ProbeResult(host: "192.168.0.20", port: 80, open: true)],
            nameLookup: ["printer.local": false],
            ipv4Cache: ["printer.local": "192.168.0.20"]
        )
        let device = InventoryBuilder.build(input, seeds: []).lanDevices.first { $0.name == "Printer" }
        #expect(device?.openURL == "http://192.168.0.20")
        #expect(device?.ipv4 == "192.168.0.20")
    }

    @Test func unreachableSeedStaysHidden() {
        let inventory = InventoryBuilder.build(InventoryInput(
            probes: [ProbeResult(host: "192.168.0.148", port: 80, open: false)],
            nameLookup: ["monster.local": false]
        ))
        #expect(!inventory.lanDevices.contains { $0.name == "Monster Settings" })
    }

    @Test func esphomeWithoutAPortalIsFirmwareOnlyAndStillShown() {
        let input = InventoryInput(
            bonjour: [BonjourService(name: "kitchen", type: "_esphomelib._tcp", host: "kitchen.local", port: 6053, ipv4: "192.168.0.50")],
            probes: PortalProbe.ports.map { ProbeResult(host: "192.168.0.50", port: $0, open: false) }
                + PortalProbe.ports.map { ProbeResult(host: "kitchen.local", port: $0, open: false) },
            nameLookup: ["kitchen.local": true]
        )
        let inventory = InventoryBuilder.build(input, seeds: [])
        let device = inventory.lanDevices.first { $0.name == "kitchen" }
        #expect(device?.firmwareOnly == true)
        #expect(device?.openURL == nil)
        #expect(inventory.needsAttention.contains { $0.deviceID == device?.id && $0.kind == .firmwareOnly })
    }

    @Test func esphomeWithAnOpenPortalIsAWebUI() {
        let input = InventoryInput(
            bonjour: [BonjourService(name: "kitchen", type: "_esphomelib._tcp", host: "kitchen.local", port: 6053, ipv4: "192.168.0.50")],
            probes: [ProbeResult(host: "192.168.0.50", port: 80, open: true)],
            nameLookup: ["kitchen.local": false]
        )
        let device = InventoryBuilder.build(input, seeds: []).lanDevices.first { $0.name == "kitchen" }
        #expect(device?.firmwareOnly == false)
        #expect(device?.openURL == "http://192.168.0.50")
    }

    @Test func homeAssistantAndHapAreNotFirmwareOnly() {
        let input = InventoryInput(
            bonjour: [
                BonjourService(name: "House", type: "_home-assistant._tcp", host: "ha.local", port: 8123, ipv4: "192.168.0.10"),
                BonjourService(name: "Lock", type: "_hap._tcp", host: "lock.local", port: 8080, ipv4: "192.168.0.11"),
            ],
            nameLookup: ["ha.local": true, "lock.local": true]
        )
        let inventory = InventoryBuilder.build(input, seeds: [])
        let house = inventory.lanDevices.first { $0.name == "House" }
        let lock = inventory.lanDevices.first { $0.name == "Lock" }
        #expect(house?.openURL == "http://ha.local:8123")
        #expect(house?.firmwareOnly == false)
        #expect(lock?.firmwareOnly == false)
        #expect(lock?.openURL == nil)
        #expect(!inventory.needsAttention.contains { $0.deviceID == lock?.id })
    }

    @Test func probePlanIncludesSeedFallbackAndBonjourTypes() {
        let targets = PortalProbe.targets(
            bonjour: [BonjourService(name: "kitchen", type: "_esphomelib._tcp", host: "kitchen.local", port: 6053, ipv4: "192.168.0.50")],
            seeds: [SeedHost.monsterSettings]
        )
        #expect(targets.contains { $0.host == "192.168.0.148" && $0.port == 80 })
        #expect(targets.contains { $0.host == "monster.local" && $0.port == 80 })
        #expect(targets.contains { $0.host == "192.168.0.50" && $0.port == 80 })
        #expect(targets.contains { $0.host == "kitchen.local" && $0.port == 6052 })
        #expect(!targets.contains { $0.port == 6053 })
        #expect(BonjourServiceType.browseTypes == [
            "_http._tcp", "_https._tcp", "_esphomelib._tcp", "_arduino._tcp", "_home-assistant._tcp", "_hap._tcp",
        ])
    }

    @Test func plistParseReadsLabelProgramAndDisabled() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>com.roy.dialdash</string>
        <key>Disabled</key><false/>
        <key>ProgramArguments</key>
        <array><string>/usr/local/bin/dialdash</string><string>--port</string><string>7878</string></array>
        </dict></plist>
        """
        let record = try #require(LaunchAgentPlist.parse(Data(xml.utf8), path: "/Users/roy/Library/LaunchAgents/com.roy.dialdash.plist", loaded: true))
        #expect(record.label == "com.roy.dialdash")
        #expect(record.program == "/usr/local/bin/dialdash")
        #expect(record.arguments == ["/usr/local/bin/dialdash", "--port", "7878"])
        #expect(record.disabled == false)
        #expect(record.loaded == true)
        #expect(KnownHelper.all.first { $0.id == "dialdash" }?.matches(agent: record) == true)
    }
}
