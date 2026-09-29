import Foundation

public enum BonjourServiceType: String, CaseIterable, Sendable {
    case http = "_http._tcp"
    case https = "_https._tcp"
    case esphome = "_esphomelib._tcp"
    case arduino = "_arduino._tcp"
    case homeAssistant = "_home-assistant._tcp"
    case hap = "_hap._tcp"
    case workstation = "_workstation._tcp"

    public static var browseTypes: [String] { allCases.map(\.rawValue) }

    public static func normalize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }

    public init?(normalizing raw: String) {
        self.init(rawValue: Self.normalize(raw))
    }

    public var isFirmware: Bool { self == .esphome || self == .arduino }

    public var isWebAdvertisement: Bool { self == .http || self == .https || self == .homeAssistant }
}

public enum LanHost {
    public static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasSuffix(".") { value.removeLast() }
        return value
    }
}

public struct SeedHost: Equatable, Sendable {
    public var name: String
    public var host: String
    public var fallbackIPv4: String?
    public var port: Int
    public var https: Bool

    public init(name: String, host: String, fallbackIPv4: String?, port: Int, https: Bool) {
        self.name = name
        self.host = host
        self.fallbackIPv4 = fallbackIPv4
        self.port = port
        self.https = https
    }

    /// Monster Settings still opens when mDNS name lookup fails.
    public static let monsterSettings = SeedHost(
        name: "Monster Settings",
        host: "monster.local",
        fallbackIPv4: "192.168.0.148",
        port: 80,
        https: false
    )

    public static let defaults = [monsterSettings]
}

public struct ProbeTarget: Equatable, Sendable {
    public var host: String
    public var port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }
}

public enum PortalProbe {
    /// Ports that can host an openable web UI beyond the service Bonjour advertised.
    public static let ports = [80, 443, 8123, 6052, 8080]

    public static func targets(bonjour: [BonjourService], seeds: [SeedHost] = SeedHost.defaults, ipv4Cache: [String: String] = [:]) -> [ProbeTarget] {
        var seen = Set<String>()
        var targets: [ProbeTarget] = []

        func add(host: String?, ports: [Int]) {
            guard let host, !host.isEmpty else { return }
            for port in ports where (1...65535).contains(port) {
                let key = "\(LanHost.normalize(host)):\(port)"
                if seen.insert(key).inserted {
                    targets.append(ProbeTarget(host: host, port: port))
                }
            }
        }

        for service in bonjour {
            let hostname = LanHost.normalize(service.host)
            let ipv4 = service.ipv4 ?? ipv4Cache[hostname] ?? seeds.first { LanHost.normalize($0.host) == hostname }?.fallbackIPv4
            var ports = PortalProbe.ports
            if let type = BonjourServiceType(normalizing: service.type), type.isWebAdvertisement {
                ports.append(service.port)
            }
            add(host: hostname, ports: ports)
            add(host: ipv4, ports: ports)
        }

        for seed in seeds {
            let ports = PortalProbe.ports + [seed.port]
            add(host: seed.host, ports: ports)
            add(host: seed.fallbackIPv4, ports: ports)
        }
        return targets
    }

    public static func hostnames(bonjour: [BonjourService], seeds: [SeedHost] = SeedHost.defaults) -> [String] {
        var names: [String] = []
        var seen = Set<String>()
        for host in bonjour.map(\.host) + seeds.map(\.host) {
            let name = LanHost.normalize(host)
            guard name.contains("."), seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }
}

public enum LanURL {
    public static func format(host: String, port: Int, https: Bool) -> String {
        let scheme = https ? "https" : "http"
        let omit = (https && port == 443) || (!https && port == 80)
        return omit ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }
}
