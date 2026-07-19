import Foundation

/// Periodically broadcasts an Announce for an owned destination so peers
/// can discover and route to it.
///
/// Mirrors Python's `Reticulum.announce` polling logic. Call `start()` to
/// begin emitting announces on the given transport and `stop()` to cancel.
public final class InterfaceAnnouncer {
    public let destination: Destination
    public var interval: TimeInterval
    private weak var transport: Transport?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "InterfaceAnnouncer")

    public init(destination: Destination, interval: TimeInterval = 1800, transport: Transport? = nil) {
        self.destination = destination
        self.interval = interval
        self.transport = transport
    }

    /// Start emitting periodic announces. The first announce fires immediately.
    public func start(on transport: Transport? = nil) {
        if let t = transport { self.transport = t }
        guard self.transport != nil else { return }
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: interval)
        t.setEventHandler { [weak self] in self?.emit() }
        t.resume()
        timer = t
    }

    public func stop() {
        timer?.cancel()
        timer = nil
    }

    public func emit() {
        guard let transport else { return }
        try? transport.announce(destination: destination)
    }
}

// MARK: - BlackholeUpdater

/// Background service that periodically connects to trusted blackhole-list
/// sources and merges their lists into the local blackhole table.
///
/// Mirrors Python `RNS.Discovery.BlackholeUpdater`. Requires a live Transport
/// to perform network fetches; the `tick()` method is exported for unit tests.
public final class BlackholeUpdater {

    // MARK: - Constants (mirror Python)
    public static let initialWait:    TimeInterval = 20
    public static let jobInterval:    TimeInterval = 60
    public static let updateInterval: TimeInterval = 3600
    public static let sourceTimeout:  TimeInterval = 25

    // MARK: - State
    public private(set) var isRunning = false
    private var lastUpdates: [Data: Date] = [:]
    private let lock = NSLock()
    private weak var transport: Transport?

    public init(transport: Transport? = nil) {
        self.transport = transport
    }

    // MARK: - Lifecycle

    public func start() {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        lock.unlock()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + Self.initialWait) { [weak self] in
            self?.runJob()
        }
    }

    public func stop() {
        lock.lock(); isRunning = false; lock.unlock()
    }

    // MARK: - Job loop

    private func runJob() {
        while isRunning {
            tick()
            Thread.sleep(forTimeInterval: Self.jobInterval)
        }
    }

    /// Single iteration of the job loop. Checks each blackhole source and
    /// initiates a fetch when `updateInterval` has elapsed.
    /// Exported for unit tests (avoids needing a live background thread).
    public func tick() {
        let now = Date()
        let sources = Reticulum.blackholeSources()
        for identityHash in sources {
            lock.lock()
            let lastUpdate = lastUpdates[identityHash]
            lock.unlock()

            let elapsed = lastUpdate.map { now.timeIntervalSince($0) } ?? .infinity
            // Use the configurable update interval (RNS commit 02924656).
            guard elapsed >= Reticulum.blackholeUpdateInterval() else { continue }

            lock.lock(); lastUpdates[identityHash] = now; lock.unlock()
            scheduleUpdate(for: identityHash)
        }
    }

    // MARK: - Network fetch

    private func scheduleUpdate(for identityHash: Data) {
        guard let transport else { return }
        guard transport.hasPath(to: identityHash) else {
            try? transport.requestPath(for: identityHash)
            return
        }
        guard let remoteIdentity = transport.recall(identity: identityHash) else { return }
        guard let destination = try? Destination(
            identity: remoteIdentity,
            direction: .out,
            kind: .single,
            appName: "rnstransport",
            aspects: ["info", "blackhole"]
        ) else { return }
        guard let link = try? Link.initiate(destination: destination, transport: transport) else { return }
        link.onEstablished = { [weak self, weak transport] l in
            self?.fetchList(over: l, transport: transport, sourceIdentityHash: identityHash)
        }
    }

    private func fetchList(over link: Link, transport: Transport?, sourceIdentityHash: Data) {
        guard let receipt = try? link.request(
            path: "/list",
            data: nil,
            responseCallback: { [weak transport] data, _ in
                transport.map { BlackholeUpdater.mergeList(data, into: $0, source: sourceIdentityHash) }
                try? link.teardown()
            },
            failedCallback: { _, _ in try? link.teardown() }
        ) else {
            try? link.teardown()
            return
        }
        _ = receipt
    }

    private static func mergeList(_ data: Data, into transport: Transport, source: Data) {
        // The response is a msgpack map of { identity_hash_bytes -> entry_dict }.
        guard case .map(let entries) = (try? MsgPack.decode(data)) else { return }
        // This runs on a Link response-callback thread, concurrently with
        // Transport's own thread and the RPC server. Serialize the whole
        // check-then-insert under Transport's blackhole lock (the loop body has
        // no callouts, so holding the lock across it is deadlock-free).
        transport.blackholeLock.lock()
        defer { transport.blackholeLock.unlock() }
        for (k, v) in entries {
            guard case .bytes(let hashBytes) = k else { continue }
            guard transport.blackholedIdentities[hashBytes] == nil else { continue }
            var until: TimeInterval? = nil
            if case .map(let em) = v {
                for (ek, ev) in em {
                    if case .string(let key) = ek, key == "until",
                       case .double(let t) = ev { until = t }
                }
            }
            transport.blackholedIdentities[hashBytes] = Transport.BlackholeEntry(
                source: source,
                until: until,
                reason: "remote-source:\(RNSUtilities.hexrep(source, delimit: false))"
            )
        }
    }
}
