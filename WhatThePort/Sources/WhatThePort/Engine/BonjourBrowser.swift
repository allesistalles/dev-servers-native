import Darwin
import Foundation
import Network

/// Browses the Dev Servers service types and resolves each one to a hostname
/// and IPv4. The address comes from the Bonjour resolve, not from getaddrinfo,
/// so a flaky .local lookup can still open the host.
final class BonjourBrowser: NSObject, NetServiceDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "website.vibed.devservers.bonjour")
    private var browsers: [NWBrowser] = []
    private var resolvers: [String: NetService] = [:]
    private let lock = NSLock()
    private var services: [String: BonjourService] = [:]
    private var started = false

    func start() {
        lock.lock()
        let already = started
        started = true
        lock.unlock()
        guard !already else { return }
        queue.async { [weak self] in self?.startBrowsers() }
    }

    func snapshot() -> [BonjourService] {
        lock.lock()
        defer { lock.unlock() }
        return services.values.filter { !$0.host.isEmpty && $0.port > 0 }
    }

    /// Hostnames resolved by Bonjour, kept for the session so a later DNS miss
    /// can still use the address dns-sd -G v4 would have cached.
    func ipv4Cache() -> [String: String] {
        var cache: [String: String] = [:]
        for service in snapshot() {
            guard let ipv4 = service.ipv4 else { continue }
            cache[LanHost.normalize(service.host)] = ipv4
        }
        return cache
    }

    private func startBrowsers() {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true
        for type in BonjourServiceType.browseTypes {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."), using: parameters)
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                self?.apply(results, type: type)
            }
            browser.start(queue: queue)
            browsers.append(browser)
        }
    }

    private func serviceKey(name: String, type: String, domain: String) -> String {
        "\(name)|\(BonjourServiceType.normalize(type))|\(LanHost.normalize(domain))"
    }

    private func apply(_ results: Set<NWBrowser.Result>, type: String) {
        let normalized = BonjourServiceType.normalize(type)
        var seen = Set<String>()
        for result in results {
            guard case .service(let name, let serviceType, let domain, _) = result.endpoint else { continue }
            let key = serviceKey(name: name, type: serviceType.isEmpty ? type : serviceType, domain: domain)
            seen.insert(key)
            if resolvers[key] == nil {
                let service = NetService(domain: domain, type: serviceType.isEmpty ? type + "." : serviceType, name: name)
                service.delegate = self
                resolvers[key] = service
                DispatchQueue.main.async {
                    service.schedule(in: .main, forMode: .common)
                    service.resolve(withTimeout: 5)
                }
            }
        }
        lock.lock()
        var gone: [NetService] = []
        for key in Array(services.keys) + Array(resolvers.keys) {
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 2, String(parts[1]) == normalized, !seen.contains(key) else { continue }
            services[key] = nil
            if let resolver = resolvers.removeValue(forKey: key) {
                gone.append(resolver)
            }
        }
        lock.unlock()
        // NetService was scheduled on the main run loop.
        DispatchQueue.main.async {
            gone.forEach { $0.stop() }
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let host = LanHost.normalize(sender.hostName ?? sender.name)
        let ipv4 = Self.firstIPv4(sender.addresses)
        let type = BonjourServiceType.normalize(sender.type)
        let key = serviceKey(name: sender.name, type: sender.type, domain: sender.domain)
        let service = BonjourService(name: sender.name, type: type, host: host, port: sender.port, ipv4: ipv4)
        lock.lock()
        services[key] = service
        lock.unlock()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        _ = errorDict
        // Keep the unresolved name so a later pass can try again.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak sender] in
            sender?.resolve(withTimeout: 5)
        }
    }

    private static func firstIPv4(_ addresses: [Data]?) -> String? {
        guard let addresses else { return nil }
        for data in addresses {
            let ipv4: String? = data.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                let family = base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family
                guard family == sa_family_t(AF_INET) else { return nil }
                var address = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
                return String(cString: buffer)
            }
            if let ipv4 { return ipv4 }
        }
        return nil
    }
}
