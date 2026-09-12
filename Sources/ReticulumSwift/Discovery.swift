//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import Foundation

/// Periodically broadcasts an Announce for an owned destination so peers
/// can discover and route to it.
///
/// Call `start()` to begin emitting announces on the given transport and `stop()` to cancel.
///
/// Renamed from `InterfaceAnnouncer` when the discovery publish side landed. That name belongs
/// to Python's `Discovery.InterfaceAnnouncer`, which announces *interfaces* as discoverable
/// endpoints and is a different thing entirely; this one re-announces one destination on a
/// timer. Every `InterfaceAnnouncer.DEFAULT_STAMP_VALUE`-style citation in this package means
/// the Python class, so the collision made each of them read as a reference to this type.
public final class DestinationAnnouncer {
    /// Destination announced on each emit.
    public let destination: Destination
    /// Seconds between announces.
    public var interval: TimeInterval
    private weak var transport: Transport?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "DestinationAnnouncer")

    /// Creates an announcer for a destination.
    public init(destination: Destination, interval: TimeInterval = 1800, transport: Transport? = nil) {
        self.destination = destination
        self.interval = interval
        self.transport = transport
    }

    /// Start emitting periodic announces.
    ///
    /// The first announce fires immediately.
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

    /// Stops announcing.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Sends one announce now.
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
    /// Seconds to wait before the first update.
    public static let initialWait:    TimeInterval = 20
    /// Seconds between runs of the update job.
    public static let jobInterval:    TimeInterval = 60
    /// Seconds between blackhole list updates.
    public static let updateInterval: TimeInterval = 3600
    /// Seconds to wait for a source to answer.
    public static let sourceTimeout:  TimeInterval = 25

    // MARK: - State
    /// Whether the updater is running.
    public private(set) var isRunning = false
    /// Incremented on every start(); a job loop exits when its captured
    /// generation no longer matches, so a stop()+start() can't leave two loops
    /// running.
    ///
    /// Guarded by `lock`.
    private var generation = 0
    private var lastUpdates: [Data: Date] = [:]
    private let lock = NSLock()
    private weak var transport: Transport?

    /// Creates an updater that fetches blackhole lists over `transport`.
    public init(transport: Transport? = nil) {
        self.transport = transport
    }

    // MARK: - Lifecycle

    /// Starts the periodic update job.
    public func start() {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        generation &+= 1
        let myGeneration = generation
        lock.unlock()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + Self.initialWait) { [weak self] in
            self?.runJob(generation: myGeneration)
        }
    }

    /// Stops the periodic update job.
    public func stop() {
        lock.lock(); isRunning = false; lock.unlock()
    }

    // MARK: - Job loop

    private func runJob(generation myGeneration: Int) {
        while true {
            // Read the run flag AND this loop's generation under the lock, so a
            // stop() (or a stop()+start() that spawned a newer loop) makes this
            // one exit cleanly.
            lock.lock()
            let keepRunning = isRunning && generation == myGeneration
            lock.unlock()
            guard keepRunning else { return }
            tick()
            Thread.sleep(forTimeInterval: Self.jobInterval)
        }
    }

    /// Single iteration of the job loop.
    ///
    /// Checks each blackhole source and
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
        // no callouts, so holding the lock across it's deadlock-free).
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
