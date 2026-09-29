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
        for (host, ip) in HostTitles.knownAddresses {
            let key = BoardMerge.canonicalizeHost(host)
            if cache[key] == nil { cache[key] = ip }
        }
        let sightings = bonjour.compactMap(LanClassify.sighting)
        for sighting in sightings where !sighting.address.isEmpty {
            let key = BoardMerge.canonicalizeHost(sighting.host)
            if cache[key] == nil { cache[key] = sighting.address }
        }
        // An empty or failed browse still probes seeds and these sightings.
        var jobs = BoardMerge.probeJobs(local: local, lan: [], seeds: seedHosts())
        var seen = Set(jobs.map { "\(BoardMerge.canonicalizeHost($0.host)):\($0.port)" })
        for job in LanClassify.probePlan(sightings) where seen.insert("\(job.host):\(job.port)").inserted {
            jobs.append(job)
        }
        let group = DispatchGroup()
        let box = ProbeBox()
        let gate = DispatchSemaphore(value: 6)
        for job in jobs {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                gate.wait()
                defer { gate.signal(); group.leave() }
                box.append(probe(job, cache: cache))
            }
        }
        _ = group.wait(timeout: .now() + 30)
        let probes = box.snapshot()
        for probe in probes where !probe.address.isEmpty {
            cache[BoardMerge.canonicalizeHost(probe.host)] = probe.address
        }
        let fromBrowse = LanClassify.cards(sightings: sightings, probes: probes)
        let browsedHosts = Set(fromBrowse.map { BoardMerge.canonicalizeHost($0.host) })
        var seedByHost: [String: BoardItem] = [:]
        for probe in probes where probe.up && probe.source != "local" {
            let host = BoardMerge.canonicalizeHost(probe.host)
            if browsedHosts.contains(host) { continue }
            var item = BoardItem(
                url: DnsSdParse.portalUrl(host, probe.port, probe.port == 443 ? "https" : "http"),
                host: host,
                port: probe.port,
                source: "seed",
                status: "up",
                address: probe.address,
                htmlTitle: probe.htmlTitle
            )
            item.title = HostTitles.listenerTitle(item)
            item.id = "seed:\(host):\(probe.port)"
            if let existing = seedByHost[host], existing.port == 80 || (probe.port != 80 && probe.port >= existing.port) { continue }
            seedByHost[host] = item
        }
        return (fromBrowse, Array(seedByHost.values), cache)
    }

    private static func probe(_ job: ProbeJob, cache: [String: String]) -> PortProbe {
        let address: String?
        if let pinned = job.address.nilIfEmpty, DnsSdParse.isIpv4(pinned) {
            address = pinned
        } else {
            let budget = TimeInterval(DnsSdParse.lookupBudgetMs(host: job.host)) / 1000
            let lookups = (0..<DnsSdParse.lookupAttempts(for: job.host)).map { _ in lookupIPv4(job.host, timeout: budget) }
            let dns = lookups.contains(where: { $0 != nil }) ? nil : dnsSdIPv4(job.host)
            address = DnsSdParse.chooseAddress(host: job.host, provided: nil, lookups: lookups, dnsSd: dns, cached: cache[BoardMerge.canonicalizeHost(job.host)])
        }
        guard let address else {
            return PortProbe(host: job.host, port: job.port, up: false, source: job.source)
        }
        let https = job.port == 443
        let result = httpUp(host: job.host, address: address, port: job.port, https: https)
        return PortProbe(host: job.host, port: job.port, up: result.up, htmlTitle: result.title, address: address, source: job.source)
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

    private static func httpUp(host: String, address: String, port: Int, https: Bool) -> (up: Bool, title: String) {
        if https { return (tlsUp(host: host, address: address, port: port), "") }
        var up = false
        var title = ""
        for method in ["HEAD", "GET"] {
            let result = rawHTTP(method: method, host: host, address: address, port: port)
            if result.up {
                up = true
                if title.isEmpty { title = result.title }
            }
            if method == "GET" { break }
        }
        return (up, title)
    }

    private static func rawHTTP(method: String, host: String, address: String, port: Int) -> (up: Bool, title: String) {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(address, String(port), &hints, &info) == 0, let info else { return (false, "") }
        defer { freeaddrinfo(info) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return (false, "") }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        guard connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else { return (false, "") }
        let request = "\(method) / HTTP/1.0\r\nHost: \(host)\r\nConnection: close\r\n\r\n"
        _ = request.withCString { send(fd, $0, strlen($0), 0) }
        var collected = Data()
        while collected.count < 8192 {
            var buffer = [UInt8](repeating: 0, count: 1024)
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            collected.append(buffer, count: count)
            if method == "HEAD" { break }
            if let text = String(data: collected, encoding: .utf8), text.contains("</title>") { break }
        }
        let text = String(data: collected, encoding: .utf8) ?? ""
        let up = DnsSdParse.isHTTPResponse(text)
        return (up, up ? DnsSdParse.htmlTitle(in: text) : "")
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

private final class ProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [PortProbe] = []
    func append(_ item: PortProbe) {
        lock.lock(); items.append(item); lock.unlock()
    }
    func snapshot() -> [PortProbe] {
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
