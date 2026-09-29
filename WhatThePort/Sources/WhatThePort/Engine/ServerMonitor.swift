import Combine
import Darwin
import DevServersCore
import Foundation

@MainActor
final class ServerMonitor: ObservableObject {
    @Published private(set) var servers: [Server] = [] {
        didSet {
            for port in servers.map(\.port).sorted() where portColorIndices[port] == nil {
                portColorIndices[port] = portColorIndices.count
            }
        }
    }
    /// Keep port identities stable across reordering, filtering, and restarts.
    private var portColorIndices: [Int: Int] = [:]
    @Published private(set) var hasScanned = false
    @Published private(set) var systemMemory: SystemMemory?
    /// Whole-Mac CPU, as a share of all cores.
    @Published private(set) var systemCPU: Double?
    /// Memory by app for everything that isn't a dev server, largest first.
    @Published private(set) var otherApps: [AppMemory] = []
    @Published private(set) var serviceInventory = ServiceInventory.empty
    @Published var allowlist: Set<String> = ServerMonitor.defaultAllowlist
    /// Set from outside the popover (e.g. a notification's Details button).
    @Published var pendingRoute: PopoverRoute?

    /// Off in the `wtp` terminal UI, so it never duplicates the menu bar app's
    /// notifications or automatic clean up.
    var handlesAlerts = true

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

    let github = GitHubLookup()
    private let engine = ScanEngine()
    private let appUsage = AppUsageScanner()
    private let cpuSampler = SystemCPUSampler()
    private let bonjour = BonjourBrowser()
    private var probeCache: [ProbeResult] = []
    private var probeAt = Date.distantPast
    private var nameLookup: [String: Bool] = [:]
    private var nameLookupAt: [String: Date] = [:]
    private let queue = DispatchQueue(label: "website.vibed.devservers.scan", qos: .utility)
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var isScanning = false
    private var defaultsObserver: AnyCancellable?
    /// Servers we've already acted on in Clean up (notified or auto-stopped).
    private var handledCleanUps = Set<String>()

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

    /// Memory above which a server needs attention.
    var alertThreshold: UInt64 {
        let gigabytes = defaults.double(forKey: Preferences.thresholdGB)
        return UInt64((gigabytes > 0 ? gigabytes : 2) * Format.gigabyte)
    }

    var idleThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpIdleHours), 1)) * 3600 }
    var longRunningThreshold: TimeInterval { TimeInterval(max(defaults.integer(forKey: Preferences.cleanUpRunningDays), 1)) * 86400 }
    var cleanUpMode: Preferences.CleanUpMode { Preferences.CleanUpMode(rawValue: defaults.string(forKey: Preferences.cleanUpMode) ?? "") ?? .ask }

    private var scanConfig: ScanConfig {
        ScanConfig(minPort: minPort, maxPort: maxPort, allowlist: allowlist,
                   protected: Set(defaults.stringArray(forKey: Preferences.protectedProcesses) ?? Preferences.defaultProtected),
                   linkClaude: defaults.bool(forKey: Preferences.linkClaude),
                   linkCodex: defaults.bool(forKey: Preferences.linkCodex),
                   linkConductor: defaults.bool(forKey: Preferences.linkConductor),
                   showBranches: defaults.bool(forKey: Preferences.showBranches))
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
        let cache = bonjour.ipv4Cache()
        let lookups = nameLookup
        let lookupAt = nameLookupAt
        let probes = probeCache
        let refreshProbes = Date().timeIntervalSince(probeAt) > 12 || probeCache.isEmpty
        queue.async { [engine, appUsage, cpuSampler] in
            let pass = Self.performScan(
                engine: engine, appUsage: appUsage, cpuSampler: cpuSampler, config: config,
                services: services, ipv4Cache: cache, lookups: lookups, lookupAt: lookupAt,
                probes: probes, refreshProbes: refreshProbes
            )
            Task { @MainActor in
                self.apply(pass)
            }
        }
    }

    /// Runs a scan synchronously. Used by snapshot mode and `wtp list`.
    func scanNow() {
        bonjour.start()
        if bonjour.snapshot().isEmpty { usleep(1_000_000) }
        let config = scanConfig
        let services = bonjour.snapshot()
        let cache = bonjour.ipv4Cache()
        let lookups = nameLookup
        let lookupAt = nameLookupAt
        let probes = probeCache
        let pass = queue.sync {
            Self.performScan(
                engine: engine, appUsage: appUsage, cpuSampler: cpuSampler, config: config,
                services: services, ipv4Cache: cache, lookups: lookups, lookupAt: lookupAt,
                probes: probes, refreshProbes: true
            )
        }
        apply(pass)
    }

    private func apply(_ pass: InventoryPass) {
        servers = pass.servers
        serviceInventory = pass.inventory
        probeCache = pass.probes
        if pass.refreshedProbes { probeAt = Date() }
        nameLookup = pass.lookups
        nameLookupAt = pass.lookupAt
        systemMemory = pass.system
        if let cpu = pass.cpu { systemCPU = cpu }
        otherApps = pass.apps
        hasScanned = true
        isScanning = false
        if handlesAlerts {
            AlertCenter.shared.evaluate(pass.servers, threshold: alertThreshold)
            handleCleanUp()
        }
        pass.servers.forEach { github.refresh($0, maxAge: 300) }
    }

    // MARK: - Derived

    var totalMemory: UInt64 { servers.reduce(0) { $0 + $1.memory } }
    var totalCPU: Double { servers.reduce(0) { $0 + $1.cpu } }
    /// Servers' CPU as a share of the whole Mac, comparable with `systemCPU`.
    var serversShareOfCPU: Double { totalCPU / Double(max(ProcessInfo.processInfo.activeProcessorCount, 1)) }
    var needsAttention: Bool { servers.contains { $0.status(alertThreshold: alertThreshold) == .attention } }

    func server(port: Int) -> Server? { servers.first { $0.port == port } }

    func colorIndex(for port: Int) -> Int { portColorIndices[port] ?? 0 }

    func status(of server: Server) -> ServerStatus { server.status(alertThreshold: alertThreshold) }

    func cleanUpReason(for server: Server) -> CleanUpReason? {
        guard !server.isProtected, cleanUpMode != .off else { return nil }
        if !server.cwdExists {
            return defaults.bool(forKey: Preferences.cleanUpDeletedWorktree) ? .worktreeDeleted : nil
        }
        if server.idleFor >= idleThreshold { return .idle(server.idleFor) }
        if let uptime = server.uptime, uptime >= longRunningThreshold { return .longRunning(uptime) }
        if server.isLeaking() { return .leaking(UInt64(max(server.memoryGrowth, 0))) }
        return nil
    }

    /// Servers worth suggesting in Clean up. Leaking ones are listed but not
    /// preselected, since they're usually still in use.
    var cleanUpCandidates: [(server: Server, reason: CleanUpReason)] {
        servers.compactMap { server in cleanUpReason(for: server).map { (server, $0) } }
    }

    var suggestedCleanUpCount: Int {
        cleanUpCandidates.filter { !$0.reason.isLeak }.count
    }

    // MARK: - Automatic clean up

    /// In Ask mode, tells you once when servers start qualifying. In Automatic
    /// mode, stops them. Leaking servers are never stopped automatically.
    private func handleCleanUp() {
        let candidates = cleanUpCandidates.filter { !$0.reason.isLeak }
        let keys = Set(candidates.map { key(for: $0.server) })
        let fresh = candidates.filter { !handledCleanUps.contains(key(for: $0.server)) }
        handledCleanUps.formIntersection(keys)
        guard !fresh.isEmpty else { return }
        fresh.forEach { handledCleanUps.insert(key(for: $0.server)) }

        let notify = defaults.bool(forKey: Preferences.cleanUpNotify)
        switch cleanUpMode {
        case .off:
            return
        case .ask:
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: false) }
        case .automatic:
            Usage.record(.autoCleanUp)
            fresh.forEach { stop($0.server) }
            if notify { AlertCenter.shared.announceCleanUp(fresh.map(\.server), stopped: true) }
        }
    }

    private func key(for server: Server) -> String { "\(server.port)-\(server.rootPid)" }

    // MARK: - Actions

    func stop(_ server: Server) {
        ProcessControl.stop(server) { [weak self] in self?.scan() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.scan() }
    }

    func restart(_ server: Server) {
        ProcessControl.restart(server) { [weak self] _ in self?.scan() }
    }

    func startHelper(_ helper: HelperRow) {
        runLaunchPlan(helper.startPlan(uid: Int(getuid())), fallbackPIDs: [])
    }

    func stopHelper(_ helper: HelperRow) {
        runLaunchPlan(helper.stopPlan(uid: Int(getuid())), fallbackPIDs: helper.listenerPIDs)
    }

    func restartHelper(_ helper: HelperRow) {
        runLaunchPlan(helper.restartPlan(uid: Int(getuid())), fallbackPIDs: helper.listenerPIDs)
    }

    func stopSidecar(_ sidecar: SidecarRow) {
        runLaunchPlan(sidecar.stopPlan(uid: Int(getuid())), fallbackPIDs: sidecar.listenerPIDs)
    }

    private func runLaunchPlan(_ plan: LaunchControlPlan?, fallbackPIDs: [Int]) {
        let uidPlan = plan
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ok = uidPlan.map { LaunchAgentController.run($0) } ?? false
            if !ok { LaunchAgentController.signal(fallbackPIDs) }
            DispatchQueue.main.async {
                self?.scan()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.scan() }
            }
        }
    }

    // MARK: - Ports and processes

    func setPortRange(min: Int, max: Int) {
        minPort = min
        maxPort = max
        defaults.set(min, forKey: "minPort")
        defaults.set(max, forKey: "maxPort")
        scan()
    }

    func addToAllowlist(_ process: String) {
        allowlist.insert(process)
        saveAllowlist()
    }

    func removeFromAllowlist(_ process: String) {
        allowlist.remove(process)
        saveAllowlist()
    }

    func resetAllowlist() {
        allowlist = Self.defaultAllowlist
        saveAllowlist()
    }

    private func saveAllowlist() {
        defaults.set(Array(allowlist), forKey: "allowlist")
        scan()
    }

    private struct InventoryPass {
        var servers: [Server]
        var inventory: ServiceInventory
        var probes: [ProbeResult]
        var refreshedProbes: Bool
        var lookups: [String: Bool]
        var lookupAt: [String: Date]
        var system: SystemMemory?
        var cpu: Double?
        var apps: [AppMemory]
    }

    private static func performScan(
        engine: ScanEngine,
        appUsage: AppUsageScanner,
        cpuSampler: SystemCPUSampler,
        config: ScanConfig,
        services: [BonjourService],
        ipv4Cache: [String: String],
        lookups: [String: Bool],
        lookupAt: [String: Date],
        probes: [ProbeResult],
        refreshProbes: Bool
    ) -> InventoryPass {
        let sockets = SocketScanner.scan()
        let result = engine.scan(config, sockets: sockets)
        let agents = LaunchAgentController.load()

        var nextLookups = lookups
        var nextLookupAt = lookupAt
        let now = Date()
        var budget = 6
        for host in PortalProbe.hostnames(bonjour: services) {
            let stale = nextLookupAt[host].map { now.timeIntervalSince($0) > 30 } ?? true
            guard stale, budget > 0 else { continue }
            budget -= 1
            nextLookups[host] = NameResolver.resolves(host)
            nextLookupAt[host] = now
        }

        var nextProbes = probes
        if refreshProbes {
            nextProbes = PortalProber.probe(PortalProbe.targets(bonjour: services, ipv4Cache: ipv4Cache))
        }
        let listeners = listeners(from: sockets, servers: result)
        let inventory = InventoryBuilder.build(InventoryInput(
            listeners: listeners,
            launchAgents: agents,
            bonjour: services,
            probes: nextProbes,
            nameLookup: nextLookups,
            ipv4Cache: ipv4Cache
        ))
        let visible = result.filter { !inventory.hiddenPorts.contains($0.port) }
        return InventoryPass(
            servers: visible,
            inventory: inventory,
            probes: nextProbes,
            refreshedProbes: refreshProbes,
            lookups: nextLookups,
            lookupAt: nextLookupAt,
            system: ProcessInspector.systemMemory(),
            cpu: cpuSampler.sample(),
            apps: appUsage.scan(excluding: Set(visible.flatMap { $0.processStarts.keys }))
        )
    }

    private static func listeners(from sockets: SocketScan, servers: [Server]) -> [Listener] {
        sockets.listening.map { socket in
            let server = servers.first { $0.port == socket.port }
            return Listener(
                port: socket.port,
                pid: Int(socket.pid),
                processName: socket.command,
                command: server?.command ?? socket.command,
                cwd: server?.cwd
            )
        }
    }
}
