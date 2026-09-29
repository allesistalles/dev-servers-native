import Darwin
import DevServersCore
import Foundation

/// macOS half of LAN discovery: dns-sd address fallback and HTTP probes that
/// connect to a pinned IPv4 while sending the original Host header.
enum BoardDiscovery {
    static func seedHosts() -> [String] {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/dev-servers/hosts.json").path
        var extra: [String] = []
        if let data = FileManager.default.contents(atPath: path),
           let json = try? JSONSerialization.jsonObject(with: data) {
            extra = HostTitles.parseHostsConfig(json)
        }
        return HostTitles.mergeSeedHosts(extra)
    }

    static func agents(home: String) -> [ParsedLaunchAgent] {
        let directory = URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents")
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard url.pathExtension == "plist", let data = try? Data(contentsOf: url) else { return nil }
            if let text = String(data: data, encoding: .utf8), text.range(of: "<plist|<\\?xml", options: .regularExpression) != nil {
                var parsed = AgentFilter.parseXML(text)
                guard !parsed.label.isEmpty else { return nil }
                parsed.plistPath = url.path
                parsed.loaded = LaunchAgentController.isLoaded(uid: Int(getuid()), label: parsed.label)
                return parsed
            }
            guard let raw = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let label = raw["Label"] as? String, !label.isEmpty else { return nil }
            let args = (raw["ProgramArguments"] as? [Any])?.compactMap { $0 as? String } ?? []
            return ParsedLaunchAgent(
                label: label,
                cwd: raw["WorkingDirectory"] as? String ?? "",
                args: args,
                plistPath: url.path,
                loaded: LaunchAgentController.isLoaded(uid: Int(getuid()), label: label)
            )
        }
    }

    static func discover(local: [LocalServer], bonjour: [BonjourService], addressCache: [String: String]) -> (lan: [BoardItem], seed: [BoardItem], cache: [String: String]) {
        var cache = addressCache
        let lanFromBrowse = bonjour.compactMap { BoardMerge.bonjourItem($0) }
        for item in lanFromBrowse where !item.address.isEmpty {
            cache[BoardMerge.canonicalizeHost(item.host)] = item.address
        }
        let seeds = seedHosts()
        let jobs = BoardMerge.probeJobs(local: local, lan: lanFromBrowse, seeds: seeds)
        var lan = lanFromBrowse
        var seed: [BoardItem] = []
        let group = DispatchGroup()
        let box = ItemBox()
        let gate = DispatchSemaphore(value: 6)
        for job in jobs {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                gate.wait()
                defer { gate.signal(); group.leave() }
                guard let found = probe(job, cache: cache) else { return }
                box.append(found.item, address: found.address)
            }
        }
        _ = group.wait(timeout: .now() + 8)
        for (item, address) in box.snapshot() {
            if !address.isEmpty { cache[BoardMerge.canonicalizeHost(item.host)] = address }
            if item.source == "lan" { lan.append(item) } else { seed.append(item) }
        }
        return (lan, seed, cache)
    }

    private static func probe(_ job: ProbeJob, cache: [String: String]) -> (item: BoardItem, address: String)? {
        let budget = TimeInterval(DnsSdParse.lookupBudgetMs(host: job.host)) / 1000
        let lookups = (0..<DnsSdParse.lookupAttempts(for: job.host)).map { _ in lookupIPv4(job.host, timeout: budget) }
        let dns = lookups.contains(where: { $0 != nil }) ? nil : dnsSdIPv4(job.host)
        guard let address = DnsSdParse.chooseAddress(host: job.host, provided: job.address.nilIfEmpty, lookups: lookups, dnsSd: dns, cached: cache[BoardMerge.canonicalizeHost(job.host)]) else { return nil }
        let https = job.port == 443
        guard httpUp(host: job.host, address: address, port: job.port, https: https) else { return nil }
        let item = BoardItem(
            url: DnsSdParse.portalUrl(job.host, job.port, https ? "https" : "http"),
            host: job.host,
            port: job.port,
            source: job.source,
            status: "up",
            address: address
        )
        return (item, address)
    }

    private static func lookupIPv4(_ host: String, timeout: TimeInterval) -> String? {
        if DnsSdParse.isIpv4(host) { return host }
        let box = StringBox()
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var info: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(host, nil, &hints, &info) == 0, let info, let addrPointer = info.pointee.ai_addr {
                var address = addrPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let text: String? = inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)).map { _ in String(cString: buffer) }
                freeaddrinfo(info)
                box.set(text)
            } else {
                box.set(nil)
            }
        }
        return box.wait(timeout: timeout) ?? nil
    }

    private static func dnsSdIPv4(_ host: String) -> String? {
        let output = collect(args: ["-G", "v4", host], timeout: 1.2)
        return DnsSdParse.parseGetaddr(output, host: host)
    }

    static func collect(args: [String], timeout: TimeInterval) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return "" }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = done.wait(timeout: .now() + 0.3)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func httpUp(host: String, address: String, port: Int, https: Bool) -> Bool {
        if https { return tlsUp(host: host, address: address, port: port) }
        for method in ["HEAD", "GET"] {
            if rawHTTP(method: method, host: host, address: address, port: port) { return true }
        }
        return false
    }

    private static func rawHTTP(method: String, host: String, address: String, port: Int) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, String(port), &hints, &info) == 0, let info else { return false }
        defer { freeaddrinfo(info) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else { return false }
        let request = "\(method) / HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
        _ = request.withCString { send(fd, $0, strlen($0), 0) }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return false }
        let text = String(bytes: buffer.prefix(count), encoding: .utf8) ?? ""
        return text.hasPrefix("HTTP/")
    }

    private static func tlsUp(host: String, address: String, port: Int) -> Bool {
        let url = URL(string: "https://\(address):\(port)/")!
        var request = URLRequest(url: url, timeoutInterval: 0.4)
        request.httpMethod = "HEAD"
        request.setValue(host, forHTTPHeaderField: "Host")
        let done = DispatchSemaphore(value: 0)
        let box = FlagBox()
        let session = URLSession(configuration: .ephemeral, delegate: TrustAll(), delegateQueue: nil)
        let task = session.dataTask(with: request) { _, response, _ in
            box.set((response as? HTTPURLResponse) != nil)
            done.signal()
        }
        task.resume()
        _ = done.wait(timeout: .now() + 0.5)
        session.invalidateAndCancel()
        return box.value
    }
}

private final class TrustAll: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

private final class ItemBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(BoardItem, String)] = []
    func append(_ item: BoardItem, address: String) {
        lock.lock(); items.append((item, address)); lock.unlock()
    }
    func snapshot() -> [(BoardItem, String)] {
        lock.lock(); defer { lock.unlock() }; return items
    }
}

private final class StringBox: @unchecked Sendable {
    private let lock = NSLock()
    private let done = DispatchSemaphore(value: 0)
    private var value: String?
    private var ready = false
    func set(_ value: String?) {
        lock.lock(); self.value = value; ready = true; lock.unlock(); done.signal()
    }
    func wait(timeout: TimeInterval) -> String?? {
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

private final class FlagBox: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return flag }
    func set(_ flag: Bool) { lock.lock(); self.flag = flag; lock.unlock() }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
