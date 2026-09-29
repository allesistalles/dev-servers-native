import Foundation

public struct LanSighting: Equatable, Sendable {
    public var instance: String
    public var host: String
    public var port: Int
    public var kind: String
    public var address: String

    public init(instance: String, host: String, port: Int, kind: String, address: String = "") {
        self.instance = instance
        self.host = host
        self.port = port
        self.kind = kind
        self.address = address
    }
}

public struct PortProbe: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var up: Bool
    public var htmlTitle: String
    public var address: String
    public var source: String

    public init(host: String, port: Int, up: Bool, htmlTitle: String = "", address: String = "", source: String = "") {
        self.host = host
        self.port = port
        self.up = up
        self.htmlTitle = htmlTitle
        self.address = address
        self.source = source
    }
}

/// One card per host advertised on `_http`, `_arduino`, `_esphomelib`, or Home Assistant.
/// The host is probed on every advertised port and on port 80. Any HTTP response is a portal.
public enum LanClassify {
    public static let deviceKinds: Set<String> = ["http", "https", "arduino", "esphome", "homeassistant"]

    public static func sighting(_ service: BonjourService) -> LanSighting? {
        let type = BonjourServiceType.normalize(service.type)
        guard let meta = DnsSdParse.browseTypes.first(where: { $0.type == type }), deviceKinds.contains(meta.kind) else { return nil }
        var host = BoardMerge.canonicalizeHost(service.host)
        if host.isEmpty {
            let name = service.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty else { return nil }
            host = name.hasSuffix(".local") ? BoardMerge.canonicalizeHost(name) : "\(name).local"
        }
        guard service.port > 0 else { return nil }
        return LanSighting(instance: service.name, host: host, port: service.port, kind: meta.kind, address: service.ipv4 ?? "")
    }

    /// Advertised ports plus port 80, one job per host. `_hap` and `_workstation` are not probed.
    public static func probePlan(_ sightings: [LanSighting]) -> [ProbeJob] {
        var grouped: [String: (ports: Set<Int>, address: String)] = [:]
        var order: [String] = []
        for sighting in sightings where deviceKinds.contains(sighting.kind) {
            let host = BoardMerge.canonicalizeHost(sighting.host)
            guard !host.isEmpty, sighting.port > 0 else { continue }
            if grouped[host] == nil {
                grouped[host] = ([], "")
                order.append(host)
            }
            grouped[host]?.ports.insert(sighting.port)
            grouped[host]?.ports.insert(80)
            if grouped[host]?.address.isEmpty == true, !sighting.address.isEmpty {
                grouped[host]?.address = sighting.address
            }
        }
        return order.flatMap { host in
            let entry = grouped[host]!
            return entry.ports.sorted().map { port in
                ProbeJob(host: host, port: port, source: "lan", address: entry.address)
            }
        }
    }

    public static func cards(sightings: [LanSighting], probes: [PortProbe]) -> [BoardItem] {
        var grouped: [String: [LanSighting]] = [:]
        var order: [String] = []
        for sighting in sightings where deviceKinds.contains(sighting.kind) {
            let host = BoardMerge.canonicalizeHost(sighting.host)
            guard !host.isEmpty else { continue }
            if grouped[host] == nil { order.append(host) }
            grouped[host, default: []].append(sighting)
        }
        return order.compactMap { host in
            card(host: host, sightings: grouped[host] ?? [], probes: probes.filter { BoardMerge.canonicalizeHost($0.host) == host })
        }
    }

    private static func card(host: String, sightings: [LanSighting], probes: [PortProbe]) -> BoardItem {
        let live = probes.filter(\.up).sorted { prefer($0.port, over: $1.port) }
        let address = live.first?.address ?? probes.first?.address ?? sightings.first?.address ?? ""
        let instance = sightings.first?.instance ?? ""
        if let portal = live.first {
            let html = live.compactMap { $0.htmlTitle.isEmpty ? nil : $0.htmlTitle }.first ?? portal.htmlTitle
            var item = BoardItem(
                url: DnsSdParse.portalUrl(host, portal.port, portal.port == 443 ? "https" : "http"),
                host: host,
                port: portal.port,
                source: "lan",
                status: "up",
                openable: true,
                address: address,
                htmlTitle: html,
                instance: instance
            )
            item.title = HostTitles.listenerTitle(item)
            item.id = "lan:\(host):\(portal.port)"
            return item
        }
        let kind = sightings.contains { $0.kind == "esphome" } ? "esphome" : (sightings.contains { $0.kind == "arduino" } ? "arduino" : sightings.first?.kind ?? "")
        let port = sightings.map(\.port).filter { $0 != 80 && $0 != 443 }.sorted().first ?? sightings.map(\.port).sorted().first ?? 0
        var item = BoardItem(
            host: host,
            port: port,
            source: "lan",
            status: "up",
            openable: false,
            kind: kind,
            label: DnsSdParse.serviceLabel(kind == "http" || kind == "https" ? "arduino" : kind),
            address: address,
            instance: instance
        )
        item.title = instance.isEmpty ? host : instance
        item.id = "lan:\(host):\(port)"
        return item
    }

    /// Port 80 wins when it answers. Otherwise the lowest other live port.
    private static func prefer(_ port: Int, over other: Int) -> Bool {
        if port == 80 { return true }
        if other == 80 { return false }
        return port < other
    }
}
