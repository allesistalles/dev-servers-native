import Foundation
import Testing
@testable import DevServersCore

struct BoardTests {
    private func item(
        title: String = "",
        url: String = "",
        host: String = "",
        port: Int = 0,
        source: String = "lan",
        status: String = "up",
        openable: Bool = true,
        kind: String = "",
        label: String = "",
        pid: Int = 0,
        project: String = "",
        cwd: String = "",
        command: String = "",
        args: [String] = [],
        startable: Bool = false,
        helperId: String = "",
        launchAgent: String = ""
    ) -> BoardItem {
        BoardItem(
            title: title, url: url, host: host, port: port, source: source, status: status, openable: openable,
            kind: kind, label: label, pid: pid, project: project, cwd: cwd, command: command, args: args,
            startable: startable, helperId: helperId, launchAgent: launchAgent
        )
    }

    @Test func matchKnownHelperCases() {
        let web = LocalServer(url: "http://localhost:8888", pid: 4, port: 8888, cwd: "/Users/roy/all cloned from github/blackberry 1/mac/web", command: "python3", args: ["server.py"])
        let card = BoardMerge.localItem(web)
        #expect(KnownHelpers.matchKnownHelper(card)?.id == "blackberry-web")

        let clip = item(host: "localhost", port: 8900, cwd: "/tmp", command: "python3", args: ["clip.py"])
        #expect(KnownHelpers.matchKnownHelper(clip)?.id == "blackberry-clip")

        let vite = item(host: "localhost", port: 5177, project: "site", command: "node")
        #expect(KnownHelpers.matchKnownHelper(vite)?.id == "led-round-dial")

        let translator = item(host: "localhost", port: 8787, cwd: "/Users/roy/translator", command: "node")
        #expect(KnownHelpers.matchKnownHelper(translator) == nil)
        #expect(HostTitles.friendlyTitleFor(translator) == "Translator")

        let droppic = item(host: "localhost", port: 8787, cwd: "/Users/roy/all cloned from github/mx keys dial and screen/helper", command: "node")
        #expect(KnownHelpers.matchKnownHelper(droppic)?.id == "droppic")

        #expect(KnownHelpers.matchKnownHelper(item(host: "localhost", port: 8765))?.id == "p1s")
        #expect(KnownHelpers.matchKnownHelper(item(host: "localhost", port: 37777))?.id == "claude-mem")
        #expect(KnownHelpers.matchKnownHelper(item(host: "localhost", port: 7878))?.id == "dialdash")
    }

    @Test func firmwareAndLanItems() {
        let ota = DnsSdParse.lanItem(
            service: DnsSdService(instance: "dial", type: "_esphomelib._tcp", domain: "local.", kind: "esphome"),
            target: DnsSdTarget(host: "led-round-dial.local", port: 6053, address: "192.168.0.20")
        )
        #expect(ota?.openable == false)
        #expect(ota?.url.isEmpty == true)
        #expect(ota?.label == "ESPHome")
        #expect(Companions.isFirmwareOnlyPort(3232))
        #expect(Companions.isFirmwareOnlyPort(6053))

        let hap = DnsSdParse.lanItem(
            service: DnsSdService(instance: "Lamp", type: "_hap._tcp", domain: "local.", kind: "hap"),
            target: DnsSdTarget(host: "lamp.local", port: 49234)
        )
        #expect(hap == nil)

        let http = DnsSdParse.lanItem(
            service: DnsSdService(instance: "Monster Settings", type: "_http._tcp", domain: "local.", kind: "http", protocolName: "http"),
            target: DnsSdTarget(host: "monster.local", port: 80, address: "192.168.0.148")
        )
        #expect(http?.url == "http://monster.local")
        #expect(http?.openable == true)
        #expect(DnsSdParse.portalUrl("homeassistant.local", 8123, "http") == "http://homeassistant.local:8123")
        #expect(DnsSdParse.portalUrl("x.local", 443, "https") == "https://x.local")
    }

    @Test func dnsSdParsers() {
        let browse = """
        Timestamp     A/R    Flags  if Domain    Service Type   Instance Name
        12:00:00.100  Add        2  11 local.    _http._tcp.    Monster Settings
        12:00:01.100  Add        2  11 local.    _http._tcp.    Pixel
        12:00:02.100  Rmv        2  11 local.    _http._tcp.    Pixel
        """
        let live = DnsSdParse.parseBrowse(browse)
        #expect(live.map(\.instance) == ["Monster Settings"])

        let resolved = DnsSdParse.parseResolve("12:00:00.000 Monster Settings can be reached at monster.local.:80")
        #expect(resolved?.host == "monster.local")
        #expect(resolved?.port == 80)

        let ip = DnsSdParse.parseGetaddr("12:00:00.000  Add  2  0 monster.local. 192.168.0.148", host: "monster.local")
        #expect(ip == "192.168.0.148")
        #expect(DnsSdParse.chooseAddress(host: "monster.local", lookups: [nil, nil], dnsSd: nil, cached: "192.168.0.148") == "192.168.0.148")
        #expect(DnsSdParse.lookupAttempts(for: "monster.local") == 2)
        #expect(DnsSdParse.lookupBudgetMs(host: "monster.local") == 1200)
        #expect(DnsSdParse.chooseAddress(host: "monster.local", provided: "192.168.0.148") == "192.168.0.148")
    }

    @Test func titlesAndDescriptions() {
        let cases: [(BoardItem, String)] = [
            (item(title: "Home Assistant", url: "http://homeassistant.local:8123", host: "homeassistant.local", port: 8123),
             "Home Assistant on the LAN — lights, climate, and the desk — Kill not available (device)"),
            (running("DialDash", port: 7878, cwd: "/Users/roy/DialDash/mac_bridge", agent: "com.screendial.tray"),
             "Pushes DialDash / screen-dial data into the tray bridge — Kill unloads the LaunchAgent so it stays off until Start"),
            (running("Blackberry web", port: 8888, cwd: "/Users/roy/all cloned from github/blackberry 1/mac/web", command: "python3", args: ["server.py"], agent: "com.roy.bb-hub"),
             "Blackberry Mac web UI — Kill unloads the LaunchAgent so it stays off until Start"),
            (running("LED Round Dial", port: 5177, cwd: "/Users/roy/led-round-dial/companion", command: "npm", args: ["run", "dev"]),
             "Browser twin for the LED Round Dial (moods/music via Home Assistant) — Kill stops the companion if local; Start is available after Kill"),
            (item(title: "led-round-dial", host: "led-round-dial.local", port: 6053, openable: false, kind: "esphome", label: "ESPHome"),
             "Physical LED Round Dial on ESPHome API (:6053) — not a web page; open the companion on :5177 when it’s running"),
            (running("Claude-mem", port: 37777, command: "bun", args: ["worker-service.cjs"], agent: "com.claude-mem.worker"),
             "Background memory/worker daemon for Claude-mem — Kill unloads the LaunchAgent so it stays off until Start"),
            (running("Droppic", port: 8787, cwd: "/Users/roy/mx keys dial and screen/helper", agent: "com.roykorkomaz.mx-keys-image-helper"),
             "Builds and sends images to the MX keys dial screen — Kill unloads the LaunchAgent so it stays off until Start"),
            (item(title: "Translator", host: "localhost", port: 8787, source: "local", cwd: "/Users/roy/translator"),
             "Translates websites for the dial workflow — Kill not available (device)"),
            (item(title: "P1S", host: "p1s.local", port: 80, openable: false, kind: "arduino", label: "Arduino OTA"),
             "Firmware update endpoint for the P1S TFT only — no web UI here; nothing to kill"),
            (item(title: "P1S", url: "http://p1s.local:8765", host: "p1s.local", port: 8765),
             "Live Build page for the Bambu P1S printer on the desk — Kill not available (device)"),
            (item(title: "8x8", host: "8x8.local", port: 80),
             "Drive the 8×8 LED Desk Monster from the browser — Kill not available (device)"),
            (item(title: "8x8", host: "8x8.local", port: 3232, openable: false, kind: "arduino"),
             "Firmware update endpoint for the 8×8 Desk Monster only — no web UI here; nothing to kill"),
            (item(title: "Monster Settings", url: "http://monster.local", host: "monster.local", port: 80),
             "Wi-Fi / settings portal for monster — Kill not available (device)"),
            (item(title: "Monster", host: "monster.local", port: 3232, openable: false, kind: "arduino"),
             "Firmware update endpoint for monster only — no web UI here; nothing to kill"),
            (item(title: "Print on e-ink", host: "print-on-eink.local", port: 80),
             "Flash UI for the print-on-eink board — Kill not available (device)"),
            (item(title: "Stash Buddy", host: "stash-buddy.local", port: 80),
             "Stash files on the LAN and grab them from the desk — Kill not available (device)"),
            (item(title: "Pixel", host: "pixel.local", port: 80),
             "Control the CYD desk pixel display from the browser — Kill not available (device)"),
            (item(title: "Climate", host: "climate.local", port: 80),
             "Read/control the climate sensor board in the browser — Kill not available (device)"),
            (item(title: "Shorty", host: "shorty.local", port: 80),
             "Control the Shorty LED strip from the browser — Kill not available (device)"),
            (item(title: "Solly", host: "solly.local", port: 80),
             "Control the Solly board from the browser — Kill not available (device)"),
            (item(title: "Flip clock", host: "flip-clock-2.local", port: 80),
             "Drive the mechanical flip-clock face from the browser — Kill not available (device)"),
            (item(title: "bedside-dial", host: "bedside-dial.local", port: 6053, openable: false, kind: "esphome"),
             "Physical bedside dial on ESPHome API — not a web page; nothing to kill"),
            (item(title: "printstatus", host: "printstatus.local", port: 6053, openable: false, kind: "esphome"),
             "Reports printer status over ESPHome API — not a web page; nothing to kill"),
            (item(title: "sidecoffee-dial", host: "sidecoffee-dial.local", port: 3232, openable: false),
             "Firmware update endpoint for the side coffee dial only — no web UI here; nothing to kill"),
            (item(title: "blueclock", host: "blueclock.local", port: 3232, openable: false),
             "Firmware update endpoint for the blue clock only — no web UI here; nothing to kill"),
            (item(title: "staufenplatz-eink", host: "staufenplatz-eink.local", port: 3232, openable: false),
             "Firmware update endpoint for the Staufenplatz e-ink only — no web UI here; nothing to kill"),
            (item(title: "Spotify", host: "localhost", port: 57621, source: "local", kind: "system"),
             "Spotify is a macOS system listener — not a project helper — ports 57621"),
        ]
        for (sample, expected) in cases {
            let text = BoardMerge.description(for: sample)
            #expect(text == expected, "\(sample.host):\(sample.port) \(sample.title) got \(text)")
        }
        #expect(HostTitles.friendlyTitleFor(item(host: "monster.local", port: 80)) == "Monster Settings")
        #expect(HostTitles.listenerTitle(item(host: "pixel.local", port: 80, project: "web")) == "Pixel")
    }

    @Test func mergeDedupeAliasAndOfflineHelpers() {
        let local = LocalServer(url: "http://localhost:3000", pid: 9, port: 3000, project: "site", command: "node")
        let lanHA = item(title: "Home Assistant", url: "http://192.168.0.45:8123", host: "192.168.0.45", port: 8123, source: "lan")
        let seedHA = item(title: "Home Assistant", url: "http://homeassistant.local:8123", host: "homeassistant.local", port: 8123, source: "seed")
        let device = item(title: "bare", url: "", host: "pixel.local", port: 0, openable: false, kind: "esphome")
        let portal = item(title: "Pixel", url: "http://pixel.local", host: "pixel.local", port: 80, source: "lan")
        let worse = item(title: "site", url: "http://localhost:3000", host: "localhost", port: 3000, source: "seed")
        let items = BoardMerge.merge(local: [local], lan: [lanHA, device, portal, worse], seed: [seedHA])
        let ha = items.filter { Companions.isHomeAssistant($0) }
        #expect(ha.count == 1)
        #expect(ha.first?.host == "homeassistant.local")
        #expect(items.contains { $0.host == "pixel.local" && $0.port == 0 } == false)
        #expect(items.contains { $0.url == "http://pixel.local" })
        let site = items.first { $0.port == 3000 && $0.host == "localhost" }
        #expect(site?.source == "local")
        let stopped = items.first { $0.helperId == "blackberry-web" }
        #expect(stopped?.status == "down")
        #expect(stopped?.startable == true)
        #expect(items.filter { $0.helperId == "blackberry-web" }.count == 1)
        #expect(items.filter { $0.helperId.hasPrefix("blackberry-") }.count == 3)
        #expect(BoardMerge.probeJobs(local: [local], lan: [portal], seeds: ["monster.local"]).contains { $0.host == "monster.local" && $0.port == 80 && $0.source == "seed" })
    }

    @Test func cardActions() {
        let openable = item(url: "http://pixel.local", host: "pixel.local", port: 80, source: "lan")
        #expect(CardActions.canOpen(openable))
        #expect(!CardActions.canKill(openable))
        let down = KnownHelpers.offlineItem(KnownHelpers.byId("led-round-dial")!)
        let flagged = ControlFlags.apply(down)
        #expect(CardActions.canStart(flagged))
        #expect(!CardActions.canOpen(flagged))
        #expect(!CardActions.canKill(flagged))
        var running = running("DialDash", port: 7878, agent: "com.screendial.tray")
        running = ControlFlags.apply(running)
        #expect(CardActions.canKill(running))
        #expect(CardActions.canRestart(running))
        #expect(!CardActions.canStart(running))
        let system = item(title: "Spotify", host: "localhost", port: 1, source: "local", kind: "system", pid: 3)
        #expect(!CardActions.canKill(system))
        let firmware = item(url: "", host: "monster.local", port: 3232, openable: false)
        #expect(!CardActions.canOpen(firmware))
    }

    @Test func launchctlArguments() {
        let plist = "/Users/roy/Library/LaunchAgents/com.roy.bb-hub.plist"
        let agent = LaunchAgentRecord(label: "com.roy.bb-hub", plistPath: plist, program: "python3", arguments: ["server.py"], disabled: false, loaded: true)
        #expect(LaunchControl.bootout(uid: 501, label: agent.label) == ["launchctl", "bootout", "gui/501/com.roy.bb-hub"])
        #expect(LaunchControl.bootstrap(uid: 501, plistPath: plist) == ["launchctl", "bootstrap", "gui/501", plist])
        #expect(LaunchControl.kickstart(uid: 501, label: agent.label) == ["launchctl", "kickstart", "-k", "gui/501/com.roy.bb-hub"])
        #expect(LaunchControl.start(uid: 501, agents: [agent])?.commands == [
            ["launchctl", "bootstrap", "gui/501", plist],
            ["launchctl", "kickstart", "-k", "gui/501/com.roy.bb-hub"],
        ])
        #expect(LaunchControl.stop(uid: 501, agents: [agent])?.commands == [["launchctl", "bootout", "gui/501/com.roy.bb-hub"]])
        #expect(LaunchControl.lsofArgs(port: 8888) == ["lsof", "-tiTCP:8888", "-sTCP:LISTEN"])
        #expect(LaunchControl.stillListeningError(port: 8888, pids: [4, 5]) == "Port 8888 still in use (pid 4, 5). Try again or kill it from Activity Monitor.")
        #expect(LaunchControl.termWaitMs == 400)
        #expect(LaunchControl.killWaitMs == 200)
    }

    @Test func plistParsingAndAgentFilter() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict>
        <key>Label</key><string>com.apple.backupd-helper</string>
        <key>WorkingDirectory</key><string>/tmp</string>
        <key>ProgramArguments</key><array><string>python3</string><string>server.py</string><string>--port</string><string>9999</string></array>
        </dict></plist>
        """
        let apple = AgentFilter.parseXML(xml)
        #expect(apple.label == "com.apple.backupd-helper")
        #expect(apple.args == ["python3", "server.py", "--port", "9999"])
        #expect(AgentFilter.isSystemAgentLabel(apple.label))
        #expect(AgentFilter.helperFromLaunchAgent(apple) == nil)
        #expect(AgentFilter.portFromArgs(apple.args) == 9999)

        let http = ParsedLaunchAgent(label: "com.example.pages", cwd: "/Users/roy/site", args: ["python3", "-m", "http.server", "8766"], loaded: false)
        let helper = AgentFilter.helperFromLaunchAgent(http, home: "/Users/roy")
        #expect(helper?.port == 8766)
        #expect(helper?.launchAgent == "com.example.pages")
        let merged = AgentFilter.mergeRegistries(KnownHelpers.all, helper.map { [$0] } ?? [])
        #expect(merged.contains { $0.launchAgent == "com.example.pages" })

        let sidecar = ParsedLaunchAgent(label: "com.tinydeskthing.mdns", cwd: "", args: ["mdns"], loaded: true)
        #expect(AgentFilter.looksHTTP(sidecar) == false)
        #expect(AgentFilter.sidecarTitle(label: sidecar.label) == "P1S mdns")
        #expect(AgentFilter.helperFromLaunchAgent(sidecar) == nil)
        #expect(AgentFilter.agentTitle(ParsedLaunchAgent(label: "com.cydanalytics.opencode-forwarder")) == "OpenCode forwarder")
    }

    @Test func tabsOverviewAndSort() {
        let items = BoardMerge.merge(local: [], lan: [
            item(title: "Pixel", url: "http://pixel.local", host: "pixel.local", port: 80),
        ], seed: [
            item(title: "Monster Settings", url: "http://monster.local", host: "monster.local", port: 80, source: "seed"),
        ])
        #expect(BoardMerge.matches(items.first { $0.helperId == "dialdash" }!, tab: "stopped"))
        #expect(!BoardMerge.matches(items.first { $0.host == "pixel.local" }!, tab: "stopped"))
        #expect(BoardMerge.matches(items.first { $0.host == "monster.local" }!, tab: "lan"))
        let view = BoardMerge.overview(items)
        #expect(view.pinned.contains { $0.title == "Home Assistant" } == false)
        #expect(view.fleet.contains { $0.title == "Pixel" })
        #expect(view.fleet.contains { $0.title == "Monster Settings" })
        #expect(view.stats.stopped >= 8)
        let system = BoardMerge.localItem(LocalServer(url: "http://localhost:57621", pid: 2, port: 57621, kind: "system", title: "Spotify"))
        #expect(BoardMerge.matches(system, tab: "system"))
        #expect(!BoardMerge.isStoppedHelper(system))
    }

    private func running(_ title: String, port: Int, cwd: String = "", command: String = "", args: [String] = [], agent: String = "") -> BoardItem {
        item(title: title, url: "http://localhost:\(port)", host: "localhost", port: port, source: "local", pid: 42, cwd: cwd, command: command, args: args, launchAgent: agent)
    }
}
