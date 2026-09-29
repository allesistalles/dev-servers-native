import Darwin
import DevServersCore
import Foundation

/// Short TCP connects used to find an openable web UI on a Bonjour host.
enum PortalProber {
    static func probe(_ targets: [ProbeTarget], timeout: TimeInterval = 0.4) -> [ProbeResult] {
        guard !targets.isEmpty else { return [] }
        let group = DispatchGroup()
        let box = ProbeBox()
        for target in targets {
            group.enter()
            DispatchQueue.global(qos: .utility).async {
                let open = Self.tcpOpen(host: target.host, port: target.port, timeout: timeout)
                box.append(ProbeResult(host: target.host, port: target.port, open: open))
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + timeout + 0.5)
        return box.snapshot()
    }

    static func tcpOpen(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &info) == 0, let info else { return false }
        defer { freeaddrinfo(info) }
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        let connected = connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen)
        if connected == 0 { return true }
        if errno != EINPROGRESS { return false }
        var pollfd = Darwin.pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pollfd, 1, Int32(timeout * 1000)) > 0 else { return false }
        var error: Int32 = 0
        var length = socklen_t(MemoryLayout<Int32>.size)
        let status = withUnsafeMutablePointer(to: &error) { pointer in
            getsockopt(fd, SOL_SOCKET, SO_ERROR, pointer, &length)
        }
        return status == 0 && error == 0
    }
}

/// getaddrinfo for .local, with a short timeout. A timeout counts as a miss so
/// the open URL can fall back to the Bonjour IPv4.
enum NameResolver {
    static func resolves(_ host: String, timeout: TimeInterval = 0.8) -> Bool {
        let box = ResultBox()
        DispatchQueue.global(qos: .utility).async {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_STREAM
            var info: UnsafeMutablePointer<addrinfo>?
            let code = getaddrinfo(host, nil, &hints, &info)
            if let info { freeaddrinfo(info) }
            box.set(code == 0)
        }
        return box.wait(timeout: timeout) ?? false
    }
}

private final class ProbeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [ProbeResult] = []

    func append(_ result: ProbeResult) {
        lock.lock()
        results.append(result)
        lock.unlock()
    }

    func snapshot() -> [ProbeResult] {
        lock.lock()
        defer { lock.unlock() }
        return results
    }
}

private final class ResultBox: @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private var value = false

    func set(_ value: Bool) {
        self.value = value
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Bool? {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
        return value
    }
}
