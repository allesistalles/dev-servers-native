import Foundation

public enum InventoryBuilder {
    public static func build(_ input: InventoryInput, seeds: [SeedHost] = SeedHost.defaults) -> ServiceInventory {
        let systemRows = SystemNoise.rows(from: input.listeners)
        var hidden = Set(systemRows.flatMap(\.ports))

        let agents = input.launchAgents
        var listeners = input.listeners.filter { !hidden.contains($0.port) }

        var helpers: [HelperRow] = []
        var consumedAgentLabels = Set<String>()

        for known in KnownHelper.all {
            let matchedAgents = agents.filter { known.matches(agent: $0) }
            consumedAgentLabels.formUnion(matchedAgents.map(\.label))
            let matchedListeners = listeners.filter { known.matches(listener: $0) }
            let include = !matchedListeners.isEmpty || !matchedAgents.isEmpty || known.isCompanion
            guard include else { continue }
            let runningPorts = matchedListeners.map(\.port).sorted()
            hidden.formUnion(runningPorts)
            listeners.removeAll { known.matches(listener: $0) }

            let state: HelperRunState = runningPorts.isEmpty ? .stopped : .running
            let attention: AttentionKind? = state == .running ? nil : (known.isCompanion ? .missingCompanion : .stoppedHelper)
            let openPort = known.ports.first(where: runningPorts.contains) ?? runningPorts.first
            helpers.append(HelperRow(
                id: known.id,
                name: known.name,
                ports: known.ports,
                runningPorts: runningPorts,
                listenerPIDs: matchedListeners.map(\.pid),
                agents: matchedAgents,
                state: state,
                openURL: openPort.map { port in port == 80 ? "http://127.0.0.1" : "http://127.0.0.1:\(port)" },
                isCompanion: known.isCompanion,
                attention: attention
            ))
        }

        var sidecarsByKind: [SidecarKind: (ports: [Int], pids: [Int], agents: [LaunchAgentRecord])] = [:]
        var sidecarListenerIndexes = Set<Int>()
        for (index, listener) in listeners.enumerated() {
            guard let kind = SidecarKind.match(processName: listener.processName, command: listener.command) else { continue }
            sidecarListenerIndexes.insert(index)
            var entry = sidecarsByKind[kind] ?? ([], [], [])
            entry.ports.append(listener.port)
            entry.pids.append(listener.pid)
            sidecarsByKind[kind] = entry
        }
        listeners = listeners.enumerated().filter { !sidecarListenerIndexes.contains($0.offset) }.map(\.element)

        var leftoverAgents: [LaunchAgentRecord] = []
        for agent in agents where !consumedAgentLabels.contains(agent.label) {
            if let kind = SidecarKind.match(processName: "", command: agent.searchText, label: agent.label) {
                if agent.loaded {
                    var entry = sidecarsByKind[kind] ?? ([], [], [])
                    entry.agents.append(agent)
                    sidecarsByKind[kind] = entry
                }
                continue
            }
            leftoverAgents.append(agent)
        }

        for agent in leftoverAgents {
            let mentioned = PortMentions.ports(in: agent.arguments + [agent.program])
            let running = listeners.filter { mentioned.contains($0.port) }
            listeners.removeAll { mentioned.contains($0.port) }
            let runningPorts = running.map(\.port).sorted()
            hidden.formUnion(runningPorts)
            let runningState = agent.loaded || !runningPorts.isEmpty
            helpers.append(HelperRow(
                id: "agent:\(agent.label)",
                name: agent.label,
                ports: runningPorts.isEmpty ? mentioned : runningPorts,
                runningPorts: runningPorts,
                listenerPIDs: running.map(\.pid),
                agents: [agent],
                state: runningState ? .running : .stopped,
                openURL: runningPorts.first.map { "http://127.0.0.1:\($0)" },
                isCompanion: false,
                attention: runningState ? nil : .stoppedHelper
            ))
        }

        let sidecars = sidecarsByKind.map { kind, entry in
            hidden.formUnion(entry.ports)
            return SidecarRow(
                id: kind.id,
                name: kind.rawValue,
                ports: entry.ports.sorted(),
                listenerPIDs: entry.pids,
                agents: entry.agents
            )
        }
        .sorted { $0.name < $1.name }

        let lan = lanDevices(input, seeds: seeds)
        var attention: [AttentionItem] = []
        for helper in helpers {
            guard let kind = helper.attention else { continue }
            attention.append(AttentionItem(
                id: "helper:\(helper.id)",
                title: helper.name,
                detail: kind == .missingCompanion ? "Missing companion" : "Stopped",
                kind: kind,
                helperID: helper.id
            ))
        }
        for device in lan where device.firmwareOnly {
            attention.append(AttentionItem(
                id: "lan:\(device.id)",
                title: device.name,
                detail: "Firmware only",
                kind: .firmwareOnly,
                deviceID: device.id
            ))
        }

        return ServiceInventory(
            helpers: helpers,
            sidecars: sidecars,
            systemRows: systemRows,
            lanDevices: lan,
            needsAttention: attention,
            hiddenPorts: hidden
        )
    }

    private struct HostAcc {
        var names: [String] = []
        var hostname: String?
        var ipv4: String?
        var types: [String] = []
        var webPorts: [(port: Int, https: Bool)] = []
        var seed: SeedHost?
        var sawBonjour = false
    }

    private struct WebChoice {
        var port: Int
        var https: Bool
        var confirmedOpen: Bool
    }

    private static func lanDevices(_ input: InventoryInput, seeds: [SeedHost]) -> [LanDevice] {
        var hosts: [String: HostAcc] = [:]

        func key(hostname: String?, ipv4: String?) -> String {
            if let ipv4, !ipv4.isEmpty { return "ip:\(ipv4)" }
            return "host:\(hostname ?? "")"
        }

        func merge(_ acc: HostAcc, into id: String) {
            var current = hosts[id] ?? HostAcc()
            current.names.append(contentsOf: acc.names)
            if current.hostname == nil { current.hostname = acc.hostname }
            if current.ipv4 == nil { current.ipv4 = acc.ipv4 }
            for type in acc.types where !current.types.contains(type) { current.types.append(type) }
            current.webPorts.append(contentsOf: acc.webPorts)
            if current.seed == nil { current.seed = acc.seed }
            current.sawBonjour = current.sawBonjour || acc.sawBonjour
            hosts[id] = current
        }

        var cache: [String: String] = [:]
        for (key, value) in input.ipv4Cache { cache[LanHost.normalize(key)] = value }
        var lookup: [String: Bool] = [:]
        for (key, value) in input.nameLookup { lookup[LanHost.normalize(key)] = value }

        for service in input.bonjour {
            let hostname = LanHost.normalize(service.host)
            let seed = seeds.first { LanHost.normalize($0.host) == hostname }
            let ipv4 = service.ipv4 ?? cache[hostname] ?? seed?.fallbackIPv4
            let type = BonjourServiceType.normalize(service.type)
            var web: [(port: Int, https: Bool)] = []
            if let parsed = BonjourServiceType(normalizing: type), parsed.isWebAdvertisement {
                web.append((port: service.port, https: parsed == .https || service.port == 443))
            }
            merge(HostAcc(
                names: [service.name],
                hostname: hostname,
                ipv4: ipv4,
                types: [type],
                webPorts: web,
                seed: seed,
                sawBonjour: true
            ), into: key(hostname: hostname, ipv4: ipv4))
        }

        for seed in seeds {
            let hostname = LanHost.normalize(seed.host)
            let ipv4 = cache[hostname] ?? seed.fallbackIPv4
            let id = key(hostname: hostname, ipv4: ipv4)
            if hosts[id] == nil {
                merge(HostAcc(names: [seed.name], hostname: hostname, ipv4: ipv4, seed: seed), into: id)
            } else if var current = hosts[id] {
                current.seed = current.seed ?? seed
                if current.ipv4 == nil { current.ipv4 = ipv4 }
                if !current.names.contains(seed.name) { current.names.insert(seed.name, at: 0) }
                hosts[id] = current
            }
        }

        let probes = probeIndex(input.probes)
        var devices: [LanDevice] = []
        for (id, acc) in hosts {
            let choice = chooseWeb(acc: acc, probes: probes)
            let seededOnly = acc.seed != nil && !acc.sawBonjour
            if seededOnly && choice?.confirmedOpen != true { continue }
            if !acc.sawBonjour && acc.seed == nil { continue }

            let hostname = acc.hostname
            let lookupFailed = hostname.map { lookup[$0] == false } ?? false
            let endpoint = lookupFailed ? (acc.ipv4 ?? hostname) : (hostname ?? acc.ipv4)
            guard let endpoint else { continue }

            let firmware = isFirmwareOnly(types: acc.types, hasWeb: choice != nil)
            let url = choice.map { LanURL.format(host: endpoint, port: $0.port, https: $0.https) }
            let name = acc.seed?.name ?? acc.names.first { !$0.isEmpty } ?? endpoint
            devices.append(LanDevice(
                id: id,
                name: name,
                host: hostname ?? endpoint,
                ipv4: acc.ipv4,
                serviceTypes: acc.types,
                openURL: firmware ? nil : url,
                firmwareOnly: firmware,
                nameLookupFailed: lookupFailed
            ))
        }
        return devices.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func chooseWeb(acc: HostAcc, probes: [String: Bool]) -> WebChoice? {
        let hosts = [acc.ipv4, acc.hostname].compactMap { $0 }
        func openness(_ port: Int) -> Bool? {
            var saw = false
            var open = false
            for host in hosts {
                if let value = probes["\(LanHost.normalize(host)):\(port)"] {
                    saw = true
                    open = open || value
                }
            }
            return saw ? open : nil
        }

        var ordered: [(port: Int, https: Bool, advertised: Bool)] = []
        for web in acc.webPorts {
            ordered.append((web.port, web.https || web.port == 443, true))
        }
        if let seed = acc.seed {
            ordered.append((seed.port, seed.https, true))
        }
        for port in PortalProbe.ports where !ordered.contains(where: { $0.port == port }) {
            ordered.append((port, port == 443, false))
        }

        var unconfirmed: WebChoice?
        for candidate in ordered {
            switch openness(candidate.port) {
            case .some(true):
                return WebChoice(port: candidate.port, https: candidate.https, confirmedOpen: true)
            case nil where candidate.advertised && unconfirmed == nil:
                unconfirmed = WebChoice(port: candidate.port, https: candidate.https, confirmedOpen: false)
            default:
                continue
            }
        }
        return unconfirmed
    }

    private static func isFirmwareOnly(types: [String], hasWeb: Bool) -> Bool {
        guard !hasWeb else { return false }
        let parsed = types.compactMap { BonjourServiceType(normalizing: $0) }
        return parsed.contains { $0.isFirmware } && !parsed.contains { $0.isWebAdvertisement }
    }

    private static func probeIndex(_ probes: [ProbeResult]) -> [String: Bool] {
        var index: [String: Bool] = [:]
        for probe in probes {
            let key = "\(LanHost.normalize(probe.host)):\(probe.port)"
            index[key] = (index[key] ?? false) || probe.open
        }
        return index
    }
}
