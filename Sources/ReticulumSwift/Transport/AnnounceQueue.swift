import Foundation

/// Per-interface announce queue. Buffers forwarded announces when the
/// interface's bitrate cap would be exceeded, and drains them on a timer.
///
/// Mirrors Python's per-interface `announce_queue` + `announce_cap` /
/// `announce_allowed_at` attributes attached to Interface objects in
/// `Transport.outbound`.
final class AnnounceQueue {

    struct Entry {
        var destinationHash: Data
        var raw: Packet
        var hops: UInt8
        var emitted: TimeInterval   // timestamp from announce body
        var enqueuedAt: TimeInterval
    }

    /// Per-interface backlog cap. Matches Python's `Reticulum.MAX_QUEUED_ANNOUNCES
    /// = 16384`. The previous value of 16 silently dropped forwarded announces on
    /// any network with more than ~16 destinations announcing within one
    /// rate-limit window, which manifested as peers "not seeing" announces.
    static let maxQueued: Int = 16384
    /// Maximum lifetime for a queued announce in seconds.
    /// Mirrors Python's `Reticulum.QUEUED_ANNOUNCE_LIFE = 60*60*24`.
    static let maxQueuedLifetime: TimeInterval = 86400
    /// Fraction of interface bandwidth the announce queue may consume.
    /// Derived from `Reticulum.announceCap / 100.0`.
    /// Python: `announce_cap = Reticulum.ANNOUNCE_CAP / 100.0`  → 0.02 (2%).
    static let announceCap: Double = Double(Reticulum.announceCap) / 100.0
    /// Random jitter multiplier: Python adds `random() * tx_time / cap` to
    /// `allowed_at` on the fast path to spread out synchronized rebroadcasts.
    /// This mirrors Python `Transport.outbound`'s random jitter logic.
    /// Set to 0 in tests via `jitterMultiplierOverride` to keep tests deterministic.
    static var jitterMultiplierOverride: Double? = nil

    private(set) var entries: [Entry] = []
    /// Destination hashes currently queued, for O(1) duplicate detection. Kept in
    /// sync with `entries` — required now that `maxQueued` is 16384, where an
    /// O(n) linear dedup scan per enqueue would be O(n²) to fill the queue.
    private var queuedDests: Set<Data> = []
    var allowedAt: TimeInterval = 0   // wall clock when next announce may go out

    init() {}

    /// Attempt to transmit `packet` now. If the interface is rate-limited,
    /// enqueue it and return false; otherwise update `allowedAt` and return true.
    ///
    /// Mirrors the core of Python's `Transport.outbound` announce-handling block,
    /// including the random jitter on the fast path:
    ///   `allowed_at = now + tx_time/cap + random() * tx_time/cap`
    @discardableResult
    func shouldTransmit(
        packet: Packet,
        now: TimeInterval,
        bitrate: Int,
        emitted: TimeInterval
    ) -> Bool {
        // Zero/unknown bitrate: transmit immediately without rate limiting.
        guard bitrate > 0 else { return true }

        let hasQueued = !entries.isEmpty
        if !hasQueued && now >= allowedAt {
            // Fast path: no backlog, and we've passed the rate-limit window.
            let txTime = Double(packet.rawByteCount) * 8.0 / Double(bitrate)
            let capWindow = txTime / AnnounceQueue.announceCap
            // Random jitter (0 to capWindow) to prevent synchronized rebroadcast.
            // Mirrors Python: `interface.announce_allowed_at = now + wait + random() * wait`
            let jitter = (AnnounceQueue.jitterMultiplierOverride ?? Double.random(in: 0...1)) * capWindow
            allowedAt = now + capWindow + jitter
            return true
        }

        // Rate-limited — queue if room.
        enqueue(Entry(
            destinationHash: packet.destinationHash,
            raw: packet,
            hops: packet.hops,
            emitted: emitted,
            enqueuedAt: now
        ))
        return false
    }

    /// Add or replace an entry, keeping the queue bounded and deduped.
    private func enqueue(_ entry: Entry) {
        if queuedDests.contains(entry.destinationHash) {
            // Duplicate destination already queued — keep the fresher announce.
            // Rare path (only when the same destination re-queues), so the linear
            // scan to find it is acceptable.
            if let idx = entries.firstIndex(where: { $0.destinationHash == entry.destinationHash }),
               entry.emitted > entries[idx].emitted {
                entries[idx] = entry
            }
            return
        }
        guard entries.count < AnnounceQueue.maxQueued else { return }
        entries.append(entry)
        queuedDests.insert(entry.destinationHash)
    }

    /// Drain entries that are now within their transmission window.
    /// Returns packets that should be sent now, updating `allowedAt`.
    func drain(now: TimeInterval, bitrate: Int) -> [Packet] {
        guard bitrate > 0 else {
            let all = entries.map { $0.raw }
            entries.removeAll()
            queuedDests.removeAll()
            return all
        }
        // Prioritize announces with fewer hops (mirrors Python's announce prioritization:
        // "Reticulum will always prioritise propagating announces with fewer hops").
        entries.sort { $0.hops < $1.hops }

        var out: [Packet] = []
        while !entries.isEmpty && now >= allowedAt {
            let e = entries.removeFirst()
            queuedDests.remove(e.destinationHash)
            let txTime = Double(e.raw.rawByteCount) * 8.0 / Double(bitrate)
            let capWindow = txTime / AnnounceQueue.announceCap
            let jitter = (AnnounceQueue.jitterMultiplierOverride ?? Double.random(in: 0...1)) * capWindow
            allowedAt = now + capWindow + jitter
            out.append(e.raw)
        }
        return out
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }
}
