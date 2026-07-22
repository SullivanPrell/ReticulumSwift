import Foundation

/// Thread-safe cumulative traffic counters for an `Interface`.
///
/// ## Why this exists
///
/// Every interface reports four running totals — `rxBytes`, `txBytes`,
/// `rxPackets`, `txPackets` (Python's `Interface.rxb`/`txb`/`rxp`/`txp`). They
/// are written from whichever queue that interface's I/O happens to run on:
/// CoreBluetooth's dispatch queue for `BLEMeshInterface`, an `NWConnection`
/// queue for the TCP/UDP family, a serial read thread for `SerialInterface`.
/// They are *read* from somewhere else entirely — the app polls them on the
/// main thread to draw the interface list, and `rnstatus`-style reporting reads
/// them from the caller's thread.
///
/// `Int` is not atomic in Swift, and `counter += 1` is a load-modify-store. Two
/// queues incrementing concurrently silently drop updates, and a reader racing
/// a writer can observe a torn value. That is undefined behaviour under the
/// Swift memory model — not merely an inaccurate statistic — and it is exactly
/// what the Thread Sanitizer flags on these properties.
///
/// Rather than bolt a lock onto each of the fourteen interfaces independently
/// (and leave the next interface to rediscover the problem), the counters live
/// here once. Interfaces hold one instance and expose the four values as
/// computed properties, so the `Interface` protocol is unchanged and the
/// reported numbers are identical.
///
/// ## Cost
///
/// One uncontended `NSLock` acquisition per packet — tens of nanoseconds
/// against packet handling measured in microseconds, and far below the cost of
/// the framing and crypto already on the same path. `NSLock` is the same
/// primitive the interfaces already use for their peer tables, so this
/// introduces no new synchronization mechanism.
/// A `Bool` that is safe to read and write from different threads.
///
/// Exists for `Interface.isOnline`, which every interface flips from its own
/// I/O queue (an `NWConnection` state handler, a CoreBluetooth callback, a
/// serial reader) while callers read it from elsewhere — `Transport` consults
/// it before routing, and apps read it for every row of an interface list.
/// A racing `Bool` is undefined behaviour just as a racing `Int` is.
///
/// Interfaces keep `isOnline` as a computed property over one of these, which
/// means every existing `isOnline = ...` assignment keeps working unchanged —
/// the setter is simply guarded now.
public final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Bool

    public init(_ value: Bool) { _value = value }

    public var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

public final class InterfaceCounters: @unchecked Sendable {

    /// A consistent view of all four counters, taken under a single lock
    /// acquisition. Reading the properties one at a time is safe but can
    /// straddle an update — a snapshot cannot, so `txBytes` and `txPackets`
    /// always describe the same set of packets.
    public struct Snapshot: Sendable, Equatable {
        public let rxBytes: Int
        public let txBytes: Int
        public let rxPackets: Int
        public let txPackets: Int
    }

    private let lock = NSLock()
    private var _rxBytes = 0
    private var _txBytes = 0
    private var _rxPackets = 0
    private var _txPackets = 0

    public init() {}

    // MARK: - Reading

    public var rxBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return _rxBytes
    }

    public var txBytes: Int {
        lock.lock(); defer { lock.unlock() }
        return _txBytes
    }

    public var rxPackets: Int {
        lock.lock(); defer { lock.unlock() }
        return _rxPackets
    }

    public var txPackets: Int {
        lock.lock(); defer { lock.unlock() }
        return _txPackets
    }

    public func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(rxBytes: _rxBytes, txBytes: _txBytes,
                        rxPackets: _rxPackets, txPackets: _txPackets)
    }

    // MARK: - Writing

    /// Records inbound traffic. `packets` defaults to 1 — pass 0 when adding
    /// bytes that do not correspond to a whole packet (e.g. counting raw
    /// stream bytes on an interface that tallies packets elsewhere).
    public func addRx(bytes: Int, packets: Int = 1) {
        lock.lock()
        _rxBytes += bytes
        _rxPackets += packets
        lock.unlock()
    }

    /// Records outbound traffic. See `addRx(bytes:packets:)`.
    public func addTx(bytes: Int, packets: Int = 1) {
        lock.lock()
        _txBytes += bytes
        _txPackets += packets
        lock.unlock()
    }

    public func reset() {
        lock.lock()
        _rxBytes = 0; _txBytes = 0; _rxPackets = 0; _txPackets = 0
        lock.unlock()
    }
}
