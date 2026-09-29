import AppKit
import Combine
import Darwin
import DevServersCore
import Foundation

@MainActor
final class ServerMonitor: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published private(set) var hasScanned = false
    @Published private(set) var board: [BoardItem] = []
    @Published var actionError: String?
    @Published var boardTab: BoardTab = .overview
    @Published var allowlist: Set<String> = ServerMonitor.defaultAllowlist

    var minPort: Int = 3000
    var maxPort: Int = 65535

    static let defaultAllowlist: Set<String> = [
        "node", "npm", "npx", "deno", "bun",
        "Python", "python", "python3", "uvicorn", "gunicorn", "flask", "django",
        "ruby", "rails", "puma", "unicorn",
        "php", "php-fpm",
        "java", "gradle", "mvn",
        "go", "air",
        "cargo", "rustc",
        "dotnet",
        "beam.smp", "elixir", "mix",
        "nginx", "httpd", "apache",
        "postgres", "mysql", "redis-server", "mongod",
        "docker-proxy",
    ]

    private let engine = ScanEngine()
    private let bonjour = BonjourBrowser()
    private var remoteAt = Date.distantPast
    private var remoteLan: [BoardItem] = []
    private var remoteSeed: [BoardItem] = []
    private var addressCache: [String: String] = [:]
    private let queue = DispatchQueue(label: "website.vibed.devservers.scan", qos: .utility)
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isScanning = false
    private var defaultsObserver: AnyCancellable?

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.array(forKey: "allowlist") as? [String] { allowlist = Set(saved) }
        let min = defaults.integer(forKey: "minPort")
        let max = defaults.integer(forKey: "maxPort")
        if min > 0 { minPort = min }
        if max > 0 { maxPort = max }
    }

    // MARK: - Preferences

    private var defaults: UserDefaults { .standard }

    private var scanConfig: ScanConfig {
        ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist)
    }

    // MARK: - Scanning

    func start() {
        guard timer == nil else { return }
        bonjour.start()
        scan()
        scheduleTimer()
        // Settings changes (scan interval, thresholds, integrations) apply on the next scan.
        defaultsObserver = NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleTimer()
                    self?.objectWillChange.send()
                }
            }
    }

    private func scheduleTimer() {
        let interval = max(defaults.double(forKey: Preferences.scanInterval), 1)
        guard interval != timerInterval else { return }
        timerInterval = interval
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let config = scanConfig
        let services = bonjour.snapshot()
        let refreshRemote = Date().timeIntervalSince(remoteAt) > 20 || remoteLan.isEmpty && remoteSeed.isEmpty
        let cachedLan = remoteLan
        let cachedSeed = remoteSeed
        let addresses = addressCache.merging(bonjour.ipv4Cache()) { current, _ in current }
        queue.async { [engine] in
            let pass = Self.performScan(
                engine: engine, config: config,
                services: services, addresses: addresses, cachedLan: cachedLan, cachedSeed: cachedSeed,
                refreshRemote: refreshRemote
            )
            Task { @MainActor in
                self.apply(pass)
            }
        }
    }

    /// Runs a scan synchronously. Used by snapshot mode.
    func scanNow() {
        bonjour.start()
        if bonjour.snapshot().isEmpty { usleep(1_000_000) }
        let config = scanConfig
        let services = bonjour.snapshot()
        let addresses = addressCache.merging(bonjour.ipv4Cache()) { current, _ in current }
        let pass = queue.sync {
            Self.performScan(
                engine: engine, config: config,
                services: services, addresses: addresses, cachedLan: [], cachedSeed: [],
                refreshRemote: true
            )
        }
        apply(pass)
    }

    private func apply(_ pass: InventoryPass) {
        servers = pass.servers
        board = pass.board
        if pass.refreshedRemote {
            remoteAt = Date()
            remoteLan = pass.lan
            remoteSeed = pass.seed
            addressCache = pass.addresses
        }
        hasScanned = true
        isScanning = false
    }

    // MARK: - Actions

    func open(_ item: BoardItem) {
        guard CardActions.canOpen(item), let url = URL(string: item.url) else { return }
        NSWorkspace.shared.open(url)
    }

    func kill(_ item: BoardItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = BoardActions.kill(item)
            DispatchQueue.main.async {
                self?.actionError = error
                self?.scan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.scan() }
            }
        }
    }

    func start(_ item: BoardItem) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let error = BoardActions.start(item)
            DispatchQueue.main.async {
                self?.actionError = error
                self?.scan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.scan() }
            }
        }
    }

    func restart(_ item: BoardItem) {
        guard CardActions.canRestart(item) else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            if let error = BoardActions.kill(item) {
                DispatchQueue.main.async { self?.actionError = error }
                return
            }
            var down = item
            down.pid = 0
            down.status = "down"
            let error = BoardActions.start(down)
            DispatchQueue.main.async {
                self?.actionError = error
                self?.scan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.scan() }
            }
        }
    }

    private struct InventoryPass {
        var servers: [Server]
        var board: [BoardItem]
        var lan: [BoardItem]
        var seed: [BoardItem]
        var addresses: [String: String]
        var refreshedRemote: Bool
    }

    nonisolated private static func performScan(
        engine: ScanEngine,
        config: ScanConfig,
        services: [BonjourService],
        addresses: [String: String],
        cachedLan: [BoardItem],
        cachedSeed: [BoardItem],
        refreshRemote: Bool
    ) -> InventoryPass {
        let sockets = SocketScanner.scan()
        let result = engine.scan(config, sockets: sockets)
        let home = NSHomeDirectory()
        var locals = result.map { localServer(from: $0) }
        locals.append(contentsOf: systemLocals(sockets))
        let parsed = BoardDiscovery.agents(home: home)
        for agent in parsed where agent.loaded {
            guard let title = AgentFilter.sidecarTitle(label: agent.label, command: agent.args.first ?? "", args: agent.args, cwd: agent.cwd),
                  !AgentFilter.looksHTTP(agent) else { continue }
            locals.append(LocalServer(
                url: "http://\(agent.label).sidecar:9",
                cwd: agent.cwd,
                command: agent.args.first ?? "",
                args: Array(agent.args.dropFirst()),
                kind: "sidecar",
                title: title,
                launchAgent: agent.label
            ))
        }
        let helpers = AgentFilter.mergeRegistries(KnownHelpers.all, parsed.compactMap { AgentFilter.helperFromLaunchAgent($0, home: home) })
        var lan = cachedLan
        var seed = cachedSeed
        var nextAddresses = addresses
        if refreshRemote {
            let found = BoardDiscovery.discover(local: locals, bonjour: services, addressCache: addresses)
            lan = found.lan
            seed = found.seed
            nextAddresses = found.cache
        }
        let board = BoardMerge.merge(local: locals, lan: lan, seed: seed, helpers: helpers)
        let hidden = BoardMerge.hiddenPorts(in: board)
        let visible = result.filter { !hidden.contains($0.port) }
        return InventoryPass(
            servers: visible,
            board: board,
            lan: lan,
            seed: seed,
            addresses: nextAddresses,
            refreshedRemote: refreshRemote
        )
    }

    nonisolated private static func localServer(from server: Server) -> LocalServer {
        LocalServer(
            url: server.url.absoluteString,
            pid: Int(server.pid),
            port: server.port,
            project: server.project.name,
            framework: server.project.framework ?? "",
            cwd: server.cwd ?? "",
            command: server.command ?? server.processName,
            args: server.launch?.arguments ?? [],
            title: server.project.name
        )
    }

    nonisolated private static func systemLocals(_ sockets: SocketScan) -> [LocalServer] {
        var grouped: [String: (name: String, pid: Int, ports: Set<Int>)] = [:]
        for socket in sockets.listening where SystemNoise.isSystemListener(socket.command) {
            let key = socket.command.lowercased()
            var entry = grouped[key] ?? (socket.command, Int(socket.pid), [])
            entry.ports.insert(socket.port)
            if entry.pid == 0 { entry.pid = Int(socket.pid) }
            grouped[key] = entry
        }
        return grouped.values.map { entry in
            let port = entry.ports.sorted().first ?? 0
            return LocalServer(
                url: "http://localhost:\(port)",
                pid: entry.pid,
                port: port,
                ports: entry.ports.sorted(),
                command: entry.name,
                kind: "system",
                title: entry.name,
                host: "localhost"
            )
        }
    }
}
