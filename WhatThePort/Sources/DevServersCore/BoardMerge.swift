import Foundation

public struct OverviewStats: Equatable, Sendable {
    public var localUp: Int
    public var lanUp: Int
    public var stopped: Int
    public var system: Int

    public init(localUp: Int = 0, lanUp: Int = 0, stopped: Int = 0, system: Int = 0) {
        self.localUp = localUp
        self.lanUp = lanUp
        self.stopped = stopped
        self.system = system
    }
}

public struct OverviewBoard: Equatable, Sendable {
    public var stats: OverviewStats
    public var pinned: [BoardItem]
    public var fleet: [BoardItem]
    public var attention: [BoardItem]
}

public struct ProbeJob: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var source: String
    public var address: String

    public init(host: String, port: Int, source: String, address: String = "") {
        self.host = host
        self.port = port
        self.source = source
        self.address = address
    }
}

public enum BoardMerge {
    public static let pinnedTitles = [
        "Blackberry web", "Blackberry static", "Blackberry clip", "DialDash", "Claude-mem",
        "Droppic", "P1S", "LED Round Dial", "Home Assistant",
    ]
    public static let fleetTitles = [
        "Pixel", "Climate", "Shorty", "Solly", "Flip clock", "8x8", "Monster Settings", "Monster", "Home Assistant",
    ]

    static let loopback: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]
    static let sourceRank = ["local": 0, "lan": 1, "seed": 2]

    public static func canonicalizeHost(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasPrefix("["), value.hasSuffix("]") { value = String(value.dropFirst().dropLast()) }
        while value.hasSuffix(".") { value.removeLast() }
        if loopback.contains(value) || value == "::1" { return "localhost" }
        return value
    }

    public static func boardUrlKey(_ url: String) -> String {
        guard let parsed = URL(string: url), let scheme = parsed.scheme, !scheme.isEmpty, let rawHost = parsed.host, !rawHost.isEmpty else { return "" }
        let host = canonicalizeHost(rawHost)
        let port = parsed.port ?? (scheme == "https" ? 443 : 80)
        return "\(scheme)://\(host):\(port)"
    }

    public static func isStoppedHelper(_ item: BoardItem) -> Bool {
        item.status == "down" && (item.startable || !item.helperId.isEmpty)
    }

    public static func isSystemCard(_ item: BoardItem) -> Bool { item.kind == "system" }

    public static func matches(_ item: BoardItem, tab: String) -> Bool {
        if tab == "overview" { return false }
        let stopped = isStoppedHelper(item)
        if tab == "stopped" { return stopped }
        if stopped { return false }
        let system = isSystemCard(item)
        if tab == "system" { return system }
        if system { return false }
        if tab == "all" { return true }
        if tab == "local" { return item.source == "local" }
        if tab == "lan" { return item.source == "lan" || item.source == "seed" }
        return true
    }

    public static func filter(_ items: [BoardItem], query: String = "", tab: String? = nil) -> [BoardItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.filter { item in
            if let tab, !tab.isEmpty, !matches(item, tab: tab) { return false }
            if q.isEmpty { return true }
            let hay = [item.title, item.host, item.url, item.project, item.description, item.label, String(item.port)]
                .joined(separator: " ").lowercased()
            return hay.contains(q)
        }
    }

    public static func description(for item: BoardItem) -> String {
        let killable = item.source == "local" && item.pid > 0
        let hay = identityHay(item)
        let slugs = slugSet(item)
        let ota = isOtaLike(item)
        let esphome = isEspHome(item)
        let helper = HostTitles.friendlyTitleFor(item)
        let known = KnownHelpers.matchKnownHelper(item)
        let restartable = known != nil && killable
        let hasAgent = !(known?.launchAgent ?? "").isEmpty || !item.launchAgent.isEmpty
        let bits = KillBits(restartable: restartable, launchAgent: hasAgent)

        if item.kind == "system" {
            let ports = item.ports.isEmpty ? (item.port > 0 ? [item.port] : []) : item.ports
            let portBit = ports.isEmpty ? "" : " — ports \(ports.map(String.init).joined(separator: ", "))"
            return "\(item.title.isEmpty ? "This" : item.title) is a macOS system listener — not a project helper\(portBit)"
        }
        if Companions.isHomeAssistant(item) {
            return withKill("Home Assistant on the LAN — lights, climate, and the desk", killable)
        }
        if item.status == "down" && !killable && (known != nil || item.startable || !item.launchAgent.isEmpty) {
            let who = (known?.launch.isEmpty == false ? known?.launch : nil) ?? item.title
            if hasAgent { return "Stopped — Start launches \(who) (loads the LaunchAgent)" }
            return "Stopped — Start launches \(who)"
        }
        if isDialDeutschTest(item, hay) { return "Stuck Dial Deutsch unit test — safe to Kill" }
        if isDialDeutschRelay(hay) { return withKill("Relays Dial Deutsch desk-voice requests to Vercel", killable) }
        if helper == "DialDash" || isMacBridge(item, slugs, hay) {
            return withKill("Pushes DialDash / screen-dial data into the tray bridge", killable, KillBits(bridge: true, restartable: restartable, launchAgent: hasAgent))
        }
        if helper == "Blackberry web" {
            return withKill("Blackberry Mac web UI", killable, bits)
        }
        if helper == "Blackberry static" {
            return withKill("Serves static files for the Blackberry Mac web dir", killable, bits)
        }
        if helper == "Blackberry clip" {
            return withKill("Clipboard helper for the Blackberry Mac workflow", killable, bits)
        }
        let ledRound = hasSlug(slugs, "led-round-dial", "led_round_dial") || hay.range(of: "led-round-dial", options: .regularExpression) != nil
        let lanCompanion = Companions.matchLanCompanion(item)
        let companion = item.port == 5177 || helper == "LED Round Dial" || (ledRound && hay.range(of: "companion", options: .regularExpression) != nil)
        if companion && !ota {
            return withKill(lanCompanion?.description ?? "Browser twin for the LED Round Dial (moods/music via Home Assistant)", killable, KillBits(companion: true, restartable: restartable, launchAgent: hasAgent))
        }
        if lanCompanion != nil && (ota || Companions.isFirmwareOnlyPort(item.port)) {
            return lanCompanion?.otaDescription ?? ""
        }
        if ledRound {
            return "Physical LED Round Dial on ESPHome API (:6053) — not a web page; open the companion on :5177 when it’s running"
        }
        if helper == "Claude-mem" || hasSlug(slugs, "claude-mem", "claude_mem") || hay.range(of: "claude-mem", options: .regularExpression) != nil || item.port == 37777 {
            return withKill("Background memory/worker daemon for Claude-mem", killable, KillBits(worker: true, restartable: restartable, launchAgent: hasAgent))
        }
        if helper == "Droppic" || (isDroppic(item, slugs, hay) && item.port == 8787 && hay.range(of: "translat", options: .regularExpression) == nil) {
            return withKill("Builds and sends images to the MX keys dial screen", killable, KillBits(helper: true, restartable: restartable, launchAgent: hasAgent))
        }
        if helper == "Translator" || (isTranslator(item, slugs, hay) && item.port == 8787) {
            return withKill("Translates websites for the dial workflow", killable, KillBits(helper: true))
        }
        if isP1sTft(slugs, hay) || (ota && (hasSlug(slugs, "p1s", "p1s.local") || hay.range(of: "p1s", options: .regularExpression) != nil)) {
            return firmwareOnly("the P1S TFT")
        }
        if isP1s(item, slugs) && helper == "P1S" {
            if killable {
                if hasAgent { return "Live Build page for the Bambu P1S printer on the desk — Kill unloads the LaunchAgent so it stays off until Start" }
                let extra = restartable ? "; Start is available after Kill" : ""
                return "Live Build page for the Bambu P1S printer on the desk — Kill stops the local helper\(extra)"
            }
            return "Live Build page for the Bambu P1S printer on the desk — Kill not available (device)"
        }
        if isEight(slugs, hay) {
            if ota { return firmwareOnly("the 8×8 Desk Monster") }
            return withKill("Drive the 8×8 LED Desk Monster from the browser", killable)
        }
        if canonicalizeHost(item.host) == "monster.local" {
            if ota || Companions.isFirmwareOnlyPort(item.port) { return firmwareOnly("monster") }
            return withKill("Wi-Fi / settings portal for monster", killable)
        }
        if hasSlug(slugs, "print-on-eink", "print_on_eink") || hay.range(of: "print-on-eink", options: .regularExpression) != nil {
            return withKill("Flash UI for the print-on-eink board", killable)
        }
        if hasSlug(slugs, "stash-buddy", "stash_buddy") || hay.range(of: "stash-buddy", options: .regularExpression) != nil {
            return withKill("Stash files on the LAN and grab them from the desk", killable)
        }
        if hasSlug(slugs, "monster") || hay.range(of: "\\bmonster\\b", options: .regularExpression) != nil {
            if ota { return firmwareOnly("the Desk Monster") }
            if !killable { return withKill("Drive the 8×8 LED Desk Monster from the browser", false) }
        }
        if hasSlug(slugs, "pixel") || helper == "Pixel" {
            return withKill("Control the CYD desk pixel display from the browser", killable)
        }
        if hasSlug(slugs, "climate") || helper == "Climate" {
            return withKill("Read/control the climate sensor board in the browser", killable)
        }
        if hasSlug(slugs, "shorty") || helper == "Shorty" {
            return withKill("Control the Shorty LED strip from the browser", killable)
        }
        if hasSlug(slugs, "solly") || helper == "Solly" {
            return withKill("Control the Solly board from the browser", killable)
        }
        if hasSlug(slugs, "flip-clock", "flip-clock-2", "flip_clock") || helper == "Flip clock" || hay.range(of: "flip.?clock", options: .regularExpression) != nil {
            return withKill("Drive the mechanical flip-clock face from the browser", killable)
        }
        if hasSlug(slugs, "bedside-dial", "bedside_dial") {
            return "Physical bedside dial on ESPHome API — not a web page; nothing to kill"
        }
        if hasSlug(slugs, "printstatus", "print-status") {
            return "Reports printer status over ESPHome API — not a web page; nothing to kill"
        }
        if hasSlug(slugs, "sidecoffee-dial", "sidecoffee_dial") { return firmwareOnly("the side coffee dial") }
        if hasSlug(slugs, "blueclock", "blue-clock") { return firmwareOnly("the blue clock") }
        if hasSlug(slugs, "staufenplatz-eink", "staufenplatz_eink") { return firmwareOnly("the Staufenplatz e-ink") }
        if ota {
            if esphome {
                let name = item.title.isEmpty ? HostTitles.prettyHostTitle(item.host) : item.title
                let who = name.isEmpty ? "this device" : name
                return "Physical \(who) on ESPHome API — not a web page; nothing to kill"
            }
            return firmwareOnly()
        }
        let project = item.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = project.range(of: "^(web|unknown|app|src|mac|www|site|roykorkomaz)$", options: [.regularExpression, .caseInsensitive]) != nil
        let who = (!generic && !project.isEmpty ? project : nil) ?? lastPathHint(item).nilIfEmpty ?? item.title.nilIfEmpty ?? HostTitles.prettyHostTitle(item.host).nilIfEmpty ?? ""
        let portBit = item.port > 0 && item.port != 80 && item.port != 443 ? " on :\(item.port)" : ""
        if killable { return "\(who)\(portBit) — Kill stops this process" }
        return "\(who)\(portBit) — Kill not available (device)"
    }

    public static func localItem(_ server: LocalServer) -> BoardItem {
        let host = hostFromURL(server.url).nilIfEmpty ?? "localhost"
        let ports = server.ports.isEmpty ? (server.port > 0 ? [server.port] : []) : Array(Set(server.ports)).sorted()
        var item = BoardItem(
            id: "local:\(server.pid):\(server.port)",
            title: server.title,
            url: server.url,
            host: host,
            port: server.port,
            ports: ports,
            source: "local",
            status: "up",
            openable: server.kind != "system" && server.kind != "sidecar",
            kind: server.kind,
            label: server.label,
            pid: server.pid,
            project: server.project,
            framework: server.framework,
            cwd: server.cwd,
            shortCwd: server.shortCwd,
            command: server.command,
            args: server.args,
            launchAgent: server.launchAgent
        )
        item.title = HostTitles.listenerTitle(item)
        if server.kind == "sidecar" { item.openable = false }
        if let known = KnownHelpers.matchKnownHelper(item), KnownHelpers.isLocalHelperHost(item.host) {
            item.startable = true
            item.helperId = known.id
            if !known.launchAgent.isEmpty { item.launchAgent = known.launchAgent }
        }
        item = ControlFlags.apply(item)
        item.description = description(for: item)
        return item
    }

    public static func mapped(_ item: BoardItem, source fallback: String) -> BoardItem {
        let host = canonicalizeHost(item.host.isEmpty ? hostFromURL(item.url) : item.host)
        let port = item.port
        let source = item.source.isEmpty ? fallback : item.source
        let openable = isOpenable(item)
        var mapped = BoardItem(
            id: item.id.isEmpty ? "\(source):\(host):\(port)" : item.id,
            title: "",
            url: openable ? item.url : "",
            host: host,
            port: port,
            ports: item.ports,
            source: source,
            status: item.status.isEmpty ? "up" : item.status,
            openable: openable,
            kind: item.kind,
            label: item.label,
            pid: item.pid,
            project: item.project,
            framework: item.framework,
            cwd: item.cwd,
            shortCwd: item.shortCwd,
            command: item.command,
            args: item.args,
            startable: item.startable,
            helperId: item.helperId,
            launchAgent: item.launchAgent,
            address: item.address,
            htmlTitle: item.htmlTitle,
            instance: item.instance
        )
        let titled = HostTitles.listenerTitle(mapped)
        mapped.title = titled.isEmpty ? HostTitles.prettyHostTitle(host) : titled
        if let known = KnownHelpers.matchKnownHelper(mapped), KnownHelpers.isLocalHelperHost(mapped.host), mapped.status != "down" {
            mapped.startable = true
            mapped.helperId = known.id
            if !known.launchAgent.isEmpty { mapped.launchAgent = known.launchAgent }
        }
        mapped = ControlFlags.apply(mapped)
        mapped.description = description(for: mapped)
        return mapped
    }

    public static func isOpenable(_ item: BoardItem) -> Bool {
        if Companions.isFirmwareOnlyPort(item.port) { return false }
        return item.openable && !item.url.isEmpty
    }

    public static func merge(local: [LocalServer] = [], lan: [BoardItem] = [], seed: [BoardItem] = [], helpers: [HelperSpec] = KnownHelpers.all) -> [BoardItem] {
        var byKey: [String: BoardItem] = [:]
        var order: [String] = []
        var httpHosts = Set<String>()

        func put(_ key: String, _ item: BoardItem) {
            if byKey[key] == nil { order.append(key) }
            byKey[key] = item
        }

        func add(_ item: BoardItem) {
            let urlKey = item.url.isEmpty ? "" : boardUrlKey(item.url)
            if !urlKey.isEmpty {
                let host = canonicalizeHost(item.host.isEmpty ? hostFromURL(item.url) : item.host)
                if !host.isEmpty && isOpenable(item) {
                    httpHosts.insert(host)
                    byKey.removeValue(forKey: "device:\(host)")
                }
                if let existing = byKey[urlKey] {
                    let incoming = sourceRank[item.source] ?? 9
                    let current = sourceRank[existing.source] ?? 9
                    if incoming < current { put(urlKey, item) }
                    return
                }
                put(urlKey, item)
                return
            }
            let host = canonicalizeHost(item.host)
            if host.isEmpty || httpHosts.contains(host) { return }
            let key = "device:\(host)"
            if byKey[key] == nil { put(key, item) }
        }

        for server in collapseLocal(local) {
            add(ControlFlags.apply(localItem(server), helpers: helpers))
        }
        for item in lan { add(ControlFlags.apply(mapped(item, source: "lan"), helpers: helpers)) }
        for item in seed { add(ControlFlags.apply(mapped(item, source: "seed"), helpers: helpers)) }

        var items = collapseAliases(order.compactMap { byKey[$0] })
        var taken = Set<Int>()
        for item in items where KnownHelpers.isLocalHelperHost(item.host) && item.status != "down" && item.port > 0 {
            taken.insert(item.port)
        }
        for helper in helpers where helper.port > 0 && !taken.contains(helper.port) {
            var card = ControlFlags.apply(KnownHelpers.offlineItem(helper), helpers: helpers)
            card.description = description(for: card)
            items.append(card)
        }
        return items.sorted { a, b in
            let rank = (sourceRank[a.source] ?? 9) - (sourceRank[b.source] ?? 9)
            if rank != 0 { return rank < 0 }
            let pin = (isPinned(b) ? 1 : 0) - (isPinned(a) ? 1 : 0)
            if pin != 0 { return pin < 0 }
            let title = a.title.localizedCaseInsensitiveCompare(b.title)
            if title != .orderedSame { return title == .orderedAscending }
            return a.port < b.port
        }
    }

    public static func hiddenPorts(in items: [BoardItem]) -> Set<Int> {
        var ports = Set<Int>()
        for item in items where item.source == "local" && (!item.helperId.isEmpty || item.kind == "system" || item.kind == "sidecar") {
            if item.port > 0 { ports.insert(item.port) }
            ports.formUnion(item.ports)
        }
        return ports
    }

    public static func overview(_ items: [BoardItem], query: String = "") -> OverviewBoard {
        let searched = filter(items, query: query, tab: nil)
        return OverviewBoard(stats: stats(items), pinned: pinned(searched), fleet: fleet(searched), attention: attention(items))
    }

    public static func stats(_ items: [BoardItem]) -> OverviewStats {
        var stats = OverviewStats()
        for item in items {
            if isStoppedHelper(item) { stats.stopped += 1; continue }
            if isSystemCard(item) { stats.system += 1; continue }
            if !item.status.isEmpty && item.status != "up" { continue }
            if item.source == "local" { stats.localUp += 1 }
            else if item.source == "lan" || item.source == "seed" { stats.lanUp += 1 }
        }
        return stats
    }

    public static func pinned(_ items: [BoardItem]) -> [BoardItem] {
        var byTitle: [String: BoardItem] = [:]
        for card in items {
            let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard pinnedTitles.contains(title) else { continue }
            if let existing = byTitle[title], !(card.status == "up" && existing.status != "up") { continue }
            byTitle[title] = card
        }
        return pinnedTitles.compactMap { byTitle[$0] }
    }

    public static func fleet(_ items: [BoardItem]) -> [BoardItem] {
        var seen = Set<String>()
        var out: [BoardItem] = []
        for card in items {
            if isStoppedHelper(card) || isSystemCard(card) { continue }
            if card.source != "lan" && card.source != "seed" { continue }
            let key = canonicalizeHost(card.host)
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(card)
        }
        return out.sorted { a, b in
            let ia = fleetTitles.firstIndex(of: a.title.trimmingCharacters(in: .whitespaces)) ?? 99
            let ib = fleetTitles.firstIndex(of: b.title.trimmingCharacters(in: .whitespaces)) ?? 99
            return ia < ib
        }
    }

    public static func attention(_ items: [BoardItem]) -> [BoardItem] {
        var out: [BoardItem] = []
        var seen = Set<String>()
        func add(_ card: BoardItem, _ reason: String) {
            let key = card.id.isEmpty ? "\(card.title):\(card.port)" : card.id
            guard seen.insert(key).inserted else { return }
            var copy = card
            copy.attention = reason
            out.append(copy)
        }
        for card in items where isStoppedHelper(card) {
            let title = card.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.range(of: "led round dial", options: [.regularExpression, .caseInsensitive]) != nil {
                add(card, "Start the LED companion on :5177 to drive the dial from the browser")
            } else {
                add(card, "Stopped — Start when you need it")
            }
        }
        for card in items {
            if isStoppedHelper(card) || isSystemCard(card) { continue }
            let ota = !card.openable && (card.kind == "arduino" || card.kind == "esphome" || Companions.isFirmwareOnlyPort(card.port))
            if !ota { continue }
            if let companion = Companions.matchLanCompanion(card) {
                if companionIsUp(items, companion) { continue }
                add(card, companion.id == "led-round-dial"
                    ? "Start the LED companion on :5177 to drive the dial from the browser"
                    : "Companion not listening on :\(companion.port)")
                continue
            }
            add(card, "Firmware only — no web portal on this host")
        }
        return out
    }

    /// Hosts and portal ports the remote refresh probes, skipping ports already known.
    public static func probeJobs(local: [LocalServer], lan: [BoardItem], seeds: [String]) -> [ProbeJob] {
        var skip: [String: Set<Int>] = [:]
        var address: [String: String] = [:]
        func remember(_ host: String, _ port: Int) {
            let key = canonicalizeHost(host)
            guard !key.isEmpty, port > 0 else { return }
            skip[key, default: []].insert(port)
        }
        for server in local {
            remember(hostFromURL(server.url).nilIfEmpty ?? "localhost", server.port)
        }
        for item in lan {
            remember(item.host, item.port)
            if !item.address.isEmpty { address[canonicalizeHost(item.host)] = item.address }
        }
        var hosts: [String] = []
        var seen = Set<String>()
        func addHost(_ host: String) {
            let key = canonicalizeHost(host)
            guard !key.isEmpty, seen.insert(key).inserted else { return }
            hosts.append(key)
        }
        addHost("localhost")
        seeds.forEach(addHost)
        lan.forEach { addHost($0.host) }
        Companions.companionProbeTargets(lan).forEach { addHost($0.host) }
        let seedSet = Set(seeds.map(canonicalizeHost))
        var jobs: [ProbeJob] = []
        for host in hosts {
            let extra = Companions.companionPortsFor(host) + Companions.companionProbeTargets(lan).filter { canonicalizeHost($0.host) == host }.map(\.port)
            let ports = Array(Set(DnsSdParse.portalPorts + extra)).sorted()
            let source = host == "localhost" ? "local" : (seedSet.contains(host) ? "seed" : "lan")
            for port in ports where !(skip[host]?.contains(port) ?? false) {
                jobs.append(ProbeJob(host: host, port: port, source: source, address: address[host] ?? ""))
            }
        }
        return jobs
    }

    public static func bonjourItem(_ service: BonjourService) -> BoardItem? {
        let type = service.type.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "\\.+$", with: "", options: .regularExpression)
        let meta = DnsSdParse.browseTypes.first { $0.type == type }
        let dns = DnsSdService(
            instance: service.name,
            type: service.type,
            domain: "local",
            kind: meta?.kind ?? "",
            protocolName: meta?.protocolName ?? ""
        )
        let target = DnsSdTarget(host: service.host, port: service.port, address: service.ipv4 ?? "")
        return DnsSdParse.lanItem(service: dns, target: target)
    }

    static func collapseLocal(_ servers: [LocalServer]) -> [LocalServer] {
        var grouped: [String: LocalServer] = [:]
        var order: [String] = []
        for server in servers {
            let key = server.pid > 0 ? "pid:\(server.pid):\(server.kind)" : "row:\(server.url):\(server.port):\(order.count)"
            if var existing = grouped[key] {
                var ports = Set(existing.ports)
                if existing.port > 0 { ports.insert(existing.port) }
                if server.port > 0 { ports.insert(server.port) }
                existing.ports = ports.sorted()
                if existing.port == 0 { existing.port = server.port }
                grouped[key] = existing
            } else {
                var copy = server
                if copy.ports.isEmpty, copy.port > 0 { copy.ports = [copy.port] }
                grouped[key] = copy
                order.append(key)
            }
        }
        return order.compactMap { grouped[$0] }
    }

    static func isPinned(_ item: BoardItem) -> Bool {
        item.title.range(of: "^(Blackberry |DialDash|Claude-mem|LED Round Dial|Droppic|Translator|P1S|Home Assistant)", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func aliasKey(_ item: BoardItem) -> String {
        Companions.isHomeAssistant(item) ? "homeassistant" : ""
    }

    static func preferAlias(_ incoming: BoardItem, _ existing: BoardItem) -> BoardItem {
        let incomingLocal = incoming.host.hasSuffix(".local")
        let existingLocal = existing.host.hasSuffix(".local")
        if incomingLocal != existingLocal { return incomingLocal ? incoming : existing }
        let incomingRank = sourceRank[incoming.source] ?? 9
        let existingRank = sourceRank[existing.source] ?? 9
        return incomingRank < existingRank ? incoming : existing
    }

    static func collapseAliases(_ items: [BoardItem]) -> [BoardItem] {
        var byAlias: [String: BoardItem] = [:]
        var rest: [BoardItem] = []
        for item in items {
            let alias = aliasKey(item)
            if alias.isEmpty { rest.append(item); continue }
            if let existing = byAlias[alias] { byAlias[alias] = preferAlias(item, existing) }
            else { byAlias[alias] = item }
        }
        return rest + byAlias.values
    }

    static func companionIsUp(_ items: [BoardItem], _ companion: LanCompanion) -> Bool {
        items.contains { card in
            card.port == companion.port && KnownHelpers.isLocalHelperHost(card.host) && card.status != "down" && card.openable
        }
    }

    static func hostFromURL(_ url: String) -> String {
        guard let host = URL(string: url)?.host else { return "" }
        return canonicalizeHost(host)
    }

    static func identityHay(_ item: BoardItem) -> String {
        [item.host, item.title, item.project, item.cwd, item.shortCwd, item.command, item.args.joined(separator: ","), item.label, item.kind]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    static func pathSegments(_ item: BoardItem) -> [String] {
        let raw = item.cwd.isEmpty ? item.shortCwd : item.cwd
        return raw.split { $0 == "/" || $0 == "\\" }.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && $0 != "." && $0 != "~" }
    }

    static func slugSet(_ item: BoardItem) -> Set<String> {
        var slugs = Set<String>()
        func add(_ value: String?) {
            var raw = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            while raw.hasSuffix(".") { raw.removeLast() }
            guard !raw.isEmpty else { return }
            slugs.insert(raw)
            slugs.insert(raw.replacingOccurrences(of: ".local", with: ""))
            slugs.insert(raw.replacingOccurrences(of: "_", with: "-"))
            slugs.insert(raw.replacingOccurrences(of: "-", with: "_"))
        }
        add(item.host)
        add(canonicalizeHost(item.host))
        add(item.title)
        add(item.project)
        add(HostTitles.friendlyTitleFor(item))
        pathSegments(item).forEach { add($0) }
        return slugs
    }

    static func hasSlug(_ slugs: Set<String>, _ names: String...) -> Bool {
        names.contains { slugs.contains($0.lowercased()) }
    }

    static func isOtaLike(_ item: BoardItem) -> Bool {
        if item.kind == "sidecar" || item.kind == "system" { return false }
        let kind = item.kind.lowercased()
        return !item.openable || kind == "arduino" || kind == "esphome" || item.label.range(of: "arduino|ota", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isEspHome(_ item: BoardItem) -> Bool {
        item.kind.lowercased() == "esphome" || item.label.range(of: "esphome", options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isDialDeutschTest(_ item: BoardItem, _ hay: String) -> Bool {
        let relay = hay.range(of: "dial-deutsch-relay|live with gpt/relay|live with gpt/.*/relay", options: .regularExpression) != nil
        guard relay else { return false }
        let testShaped = hay.range(of: "test/server\\.test\\.js|server\\.test\\.js", options: .regularExpression) != nil
        return testShaped || item.port >= 10000
    }

    static func isDialDeutschRelay(_ hay: String) -> Bool {
        hay.range(of: "dial-deutsch-relay|live with gpt/relay|dial deutsch", options: .regularExpression) != nil
    }

    static func isMacBridge(_ item: BoardItem, _ slugs: Set<String>, _ hay: String) -> Bool {
        hasSlug(slugs, "mac_bridge", "mac-bridge", "dialdash") || hay.range(of: "dialdash|mac_bridge|mac-bridge", options: .regularExpression) != nil || item.port == 7878
    }

    static func isDroppic(_ item: BoardItem, _ slugs: Set<String>, _ hay: String) -> Bool {
        HostTitles.friendlyTitleFor(item) == "Droppic" || hasSlug(slugs, "droppic", "mx-keys-image-helper") || (item.port == 8787 && hay.range(of: "translat", options: .regularExpression) == nil)
    }

    static func isTranslator(_ item: BoardItem, _ slugs: Set<String>, _ hay: String) -> Bool {
        HostTitles.friendlyTitleFor(item) == "Translator" || hasSlug(slugs, "translator") || (item.port == 8787 && hay.range(of: "translat", options: .regularExpression) != nil)
    }

    static func isP1sTft(_ slugs: Set<String>, _ hay: String) -> Bool {
        hasSlug(slugs, "p1s-tft", "p1s_tft") || hay.range(of: "p1s-tft|p1s_tft", options: .regularExpression) != nil
    }

    static func isP1s(_ item: BoardItem, _ slugs: Set<String>) -> Bool {
        HostTitles.friendlyTitleFor(item) == "P1S" || hasSlug(slugs, "p1s", "p1s.local") || item.port == 8765 || identityHay(item).range(of: "tiny-desk-thing/bridge", options: .regularExpression) != nil
    }

    static func isEight(_ slugs: Set<String>, _ hay: String) -> Bool {
        hasSlug(slugs, "8x8", "eight", "eight-by-eight", "eight.local") || hay.range(of: "8x8|eight-by-eight|\\bdesk monster\\b", options: .regularExpression) != nil
    }

    static func lastPathHint(_ item: BoardItem) -> String {
        let segs = pathSegments(item)
        if segs.count >= 2 { return "\(segs[segs.count - 2])/\(segs[segs.count - 1])" }
        return segs.last ?? ""
    }

    static func firmwareOnly(_ extra: String = "") -> String {
        let who = extra.isEmpty ? "" : " for \(extra)"
        return "Firmware update endpoint\(who) only — no web UI here; nothing to kill"
    }

    fileprivate static func withKill(_ lead: String, _ killable: Bool, _ bits: KillBits = KillBits()) -> String {
        let startBit = bits.restartable ? "; Start is available after Kill" : ""
        if killable && bits.launchAgent { return "\(lead) — Kill unloads the LaunchAgent so it stays off until Start" }
        if killable {
            if bits.helper { return "\(lead) — Kill stops this helper\(startBit)" }
            if bits.bridge { return "\(lead) — Kill stops the Mac bridge\(startBit)" }
            if bits.companion { return "\(lead) — Kill stops the companion if local\(startBit)" }
            if bits.worker { return "\(lead) — Kill stops the daemon\(startBit)" }
            return "\(lead) — Kill stops this process\(startBit)"
        }
        return "\(lead) — Kill not available (device)"
    }
}

fileprivate struct KillBits {
    var helper = false
    var bridge = false
    var companion = false
    var worker = false
    var restartable = false
    var launchAgent = false
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
