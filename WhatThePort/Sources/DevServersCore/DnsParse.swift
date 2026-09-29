import Foundation

public struct DnsSdService: Equatable, Sendable {
    public var instance: String
    public var type: String
    public var domain: String
    public var kind: String
    public var protocolName: String

    public init(instance: String, type: String, domain: String, kind: String = "", protocolName: String = "") {
        self.instance = instance
        self.type = type
        self.domain = domain
        self.kind = kind
        self.protocolName = protocolName
    }
}

public struct DnsSdTarget: Equatable, Sendable {
    public var host: String
    public var port: Int
    public var address: String

    public init(host: String, port: Int, address: String = "") {
        self.host = host
        self.port = port
        self.address = address
    }
}

public enum DnsSdParse {
    public static let browseTypes: [(type: String, kind: String, protocolName: String)] = [
        ("_http._tcp", "http", "http"),
        ("_https._tcp", "https", "https"),
        ("_arduino._tcp", "arduino", ""),
        ("_esphomelib._tcp", "esphome", ""),
        ("_home-assistant._tcp", "homeassistant", "http"),
        ("_hap._tcp", "hap", ""),
    ]

    public static let portalPorts = [80, 443, 3000, 5173, 5177, 8000, 8080, 8123, 8765, 8787, 9000]

    static let browseLine = "^\\s*(\\d{1,2}:\\d{2}:\\d{2}\\.\\d+)\\s+(Add|Rmv)\\s+\\d+\\s+\\d+\\s+(\\S+)\\s+(\\S+)\\s+(.+?)\\s*$"
    static let resolveLine = "can be reached at (\\S+?):(\\d+)"

    public static func isHttpishPort(_ port: Int) -> Bool { portalPorts.contains(port) }

    public static func serviceLabel(_ kind: String) -> String {
        if kind == "arduino" { return "Arduino OTA" }
        if kind == "esphome" { return "ESPHome" }
        return "Non-HTTP"
    }

    public static func portalUrl(_ host: String, _ port: Int, _ protocolName: String? = nil) -> String {
        let scheme = protocolName ?? (port == 443 ? "https" : "http")
        let hide = (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
        return hide ? "\(scheme)://\(host)" : "\(scheme)://\(host):\(port)"
    }

    public static func parseBrowse(_ stdout: String) -> [DnsSdService] {
        var live: [String: DnsSdService] = [:]
        var order: [String] = []
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            guard let match = firstMatch(browseLine, in: String(line)), match.count >= 6 else { continue }
            let action = match[2]
            let domain = match[3]
            let type = match[4]
            let name = match[5].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let key = "\(name)\u{0}\(type)\u{0}\(domain)"
            if action == "Add" {
                if live[key] == nil { order.append(key) }
                live[key] = DnsSdService(instance: name, type: type, domain: domain)
            } else {
                live.removeValue(forKey: key)
            }
        }
        return order.compactMap { live[$0] }
    }

    public static func parseResolve(_ stdout: String) -> DnsSdTarget? {
        guard let match = firstMatch(resolveLine, in: stdout, insensitive: true), match.count >= 3 else { return nil }
        var host = match[1].lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        let port = Int(match[2]) ?? 0
        guard !host.isEmpty, port > 0 else { return nil }
        return DnsSdTarget(host: host, port: port)
    }

    public static func normalizeLookupHost(_ host: String) -> String {
        var name = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while name.hasSuffix(".") { name.removeLast() }
        return name
    }

    public static func isIpv4(_ value: String) -> Bool {
        value.range(of: "^\\d{1,3}(?:\\.\\d{1,3}){3}$", options: .regularExpression) != nil
    }

    public static func parseGetaddr(_ stdout: String, host: String) -> String? {
        let want = normalizeLookupHost(host)
        for line in stdout.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            guard let match = firstMatch("\\b(\\d{1,3}(?:\\.\\d{1,3}){3})\\b", in: text), match.count >= 2 else { continue }
            let ip = match[1]
            if ip == "0.0.0.0" { continue }
            if !want.isEmpty && !text.lowercased().contains(want) { continue }
            return ip
        }
        return nil
    }

    public static func lanItem(service: DnsSdService, target: DnsSdTarget) -> BoardItem? {
        guard !target.host.isEmpty, target.port > 0 else { return nil }
        if Companions.isFirmwareOnlyPort(target.port) {
            let kind = service.kind == "esphome" ? "esphome" : service.kind == "arduino" ? "arduino" : service.kind
            let labelKind = (service.kind == "http" || service.kind == "https") ? "arduino" : service.kind
            return BoardItem(
                id: "lan:\(target.host):\(target.port)",
                title: service.instance,
                url: "",
                host: target.host,
                port: target.port,
                source: "lan",
                status: "up",
                openable: false,
                kind: kind,
                label: serviceLabel(labelKind),
                address: target.address,
                instance: service.instance
            )
        }
        if service.kind == "hap" && !isHttpishPort(target.port) { return nil }
        let httpish = service.kind == "http" || service.kind == "https" || service.kind == "homeassistant"
            || (service.kind == "hap" && isHttpishPort(target.port))
            || isHttpishPort(target.port)
        if httpish {
            let https = service.protocolName == "https" || service.kind == "https" || target.port == 443
            return BoardItem(
                id: "lan:\(target.host):\(target.port)",
                title: service.instance,
                url: portalUrl(target.host, target.port, https ? "https" : "http"),
                host: target.host,
                port: target.port,
                source: "lan",
                status: "up",
                address: target.address,
                instance: service.instance
            )
        }
        return BoardItem(
            id: "lan:\(target.host):\(target.port)",
            title: service.instance,
            url: "",
            host: target.host,
            port: target.port,
            source: "lan",
            status: "up",
            openable: false,
            kind: service.kind,
            label: serviceLabel(service.kind),
            address: target.address,
            instance: service.instance
        )
    }

    public static func lookupAttempts(for host: String) -> Int {
        normalizeLookupHost(host).hasSuffix(".local") ? 2 : 1
    }

    public static func lookupBudgetMs(host: String, timeoutMs: Int = 400, mockedHTTP: Bool = false) -> Int {
        let name = normalizeLookupHost(host)
        if name.hasSuffix(".local") && !mockedHTTP { return max(timeoutMs, 1200) }
        return timeoutMs
    }

    /// The IPv4 `resolveProbeAddress` would return, given each step's result.
    public static func chooseAddress(host: String, provided: String? = nil, lookups: [String?] = [], dnsSd: String? = nil, cached: String? = nil) -> String? {
        let name = normalizeLookupHost(host)
        if let provided, isIpv4(provided) { return provided }
        if isIpv4(name) { return name }
        if name == "localhost" || name == "127.0.0.1" || name == "::1" { return "127.0.0.1" }
        for ip in lookups {
            if let ip, isIpv4(ip) { return ip }
        }
        if let dnsSd, isIpv4(dnsSd) { return dnsSd }
        if let cached, isIpv4(cached) { return cached }
        return nil
    }

    static func firstMatch(_ pattern: String, in text: String, insensitive: Bool = false) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: insensitive ? [.caseInsensitive] : []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let slice = Range(match.range(at: index), in: text) else { return "" }
            return String(text[slice])
        }
    }
}
