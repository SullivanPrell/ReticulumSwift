import Foundation

// MARK: - System message types (match Python SystemMessageTypes)

public enum SystemMessageTypes {
    public static let streamData: UInt16 = 0xFF00
}

// MARK: - Message state

public enum MessageState: Equatable {
    case new, sent, delivered, failed
}

// MARK: - Channel errors

public enum ChannelError: Error, Equatable {
    case noMsgType
    case invalidMsgType
    case notRegistered(UInt16)
    case linkNotReady
    case alreadySent
    case tooBig
}

// MARK: - MessageBase

/// Base for all Channel messages. Subclasses must override `typeID` with a
/// non-zero value (< 0xF000 for user types). Values ≥ 0xF000 are system-reserved.
open class MessageBase {
    public required init() {}

    open class var typeID: UInt16 { 0 }

    open func pack() throws -> Data { Data() }
    open func unpack(_ data: Data) throws {}
}

// MARK: - Message handler token (opaque cancellation handle)

public final class MessageHandlerToken {
    let callback: (MessageBase) -> Bool
    init(callback: @escaping (MessageBase) -> Bool) {
        self.callback = callback
    }
}

// MARK: - Channel packet handle

/// Tracks the lifecycle of one sent Channel envelope.
public final class ChannelPacketHandle {
    public enum State { case sent, delivered, failed }
    public private(set) var state: State = .sent
    let raw: Data
    var deliveredCallback: ((ChannelPacketHandle) -> Void)?
    var timeoutWork: DispatchWorkItem?
    private let lock = NSLock()

    init(raw: Data) { self.raw = raw }

    func markDelivered() {
        lock.lock()
        guard state == .sent else { lock.unlock(); return }
        state = .delivered
        timeoutWork?.cancel()
        timeoutWork = nil
        let cb = deliveredCallback
        deliveredCallback = nil
        lock.unlock()
        cb?(self)
    }

    func markFailed() {
        lock.lock()
        state = .failed
        timeoutWork?.cancel()
        timeoutWork = nil
        deliveredCallback = nil
        lock.unlock()
    }
}

// MARK: - ChannelOutlet protocol

public protocol ChannelOutlet: AnyObject {
    func send(_ raw: Data) -> ChannelPacketHandle
    func resend(_ handle: ChannelPacketHandle)
    var mdu: Int { get }
    var rtt: TimeInterval { get }
    var isUsable: Bool { get }
    func getPacketState(_ handle: ChannelPacketHandle) -> MessageState
    func timedOut()
    func setPacketTimeoutCallback(
        _ handle: ChannelPacketHandle,
        timeout: TimeInterval?,
        callback: ((ChannelPacketHandle) -> Void)?
    )
    func setPacketDeliveredCallback(
        _ handle: ChannelPacketHandle,
        callback: ((ChannelPacketHandle) -> Void)?
    )
    func getPacketID(_ handle: ChannelPacketHandle) -> ObjectIdentifier?
}

// MARK: - Envelope (internal wire wrapper)

final class Envelope {
    let outlet: ChannelOutlet
    var message: MessageBase?
    var raw: Data?
    var packet: ChannelPacketHandle?
    var sequence: UInt16
    var tries: Int = 0
    var tracked: Bool = false
    var unpacked: Bool = false

    init(outlet: ChannelOutlet, message: MessageBase? = nil, raw: Data? = nil, sequence: UInt16 = 0) {
        self.outlet = outlet
        self.message = message
        self.raw = raw
        self.sequence = sequence
    }

    /// Encode to wire bytes: [MSGTYPE:2][seq:2][len:2][body:N] (big-endian)
    func pack(messageFactories: [UInt16: () -> MessageBase]) throws -> Data {
        guard let message else { throw ChannelError.noMsgType }
        let tid = type(of: message).typeID
        guard tid != 0 else { throw ChannelError.noMsgType }
        let body = try message.pack()
        var out = Data(capacity: 6 + body.count)
        out.append(UInt8(tid >> 8));    out.append(UInt8(tid & 0xFF))
        out.append(UInt8(sequence >> 8)); out.append(UInt8(sequence & 0xFF))
        let len = UInt16(body.count)
        out.append(UInt8(len >> 8));    out.append(UInt8(len & 0xFF))
        out.append(body)
        raw = out
        return out
    }

    /// Decode from wire bytes. Populates `sequence` and `message`.
    func unpack(messageFactories: [UInt16: () -> MessageBase]) throws -> MessageBase {
        guard let raw, raw.count >= 6 else { throw ChannelError.invalidMsgType }
        let msgtype = UInt16(raw[0]) << 8 | UInt16(raw[1])
        sequence    = UInt16(raw[2]) << 8 | UInt16(raw[3])
        // bytes 4-5 are length (unused — body is remainder)
        let body    = raw.dropFirst(6)
        guard let ctor = messageFactories[msgtype] else {
            throw ChannelError.notRegistered(msgtype)
        }
        let msg = ctor()
        try msg.unpack(Data(body))
        message  = msg
        unpacked = true
        return msg
    }
}

// MARK: - Channel

/// Reliable, ordered, typed message stream over a Link.
/// Wire-compatible with Python's RNS.Channel.
public final class Channel {

    // Window constants (mirror Python Channel.py)
    public static let WINDOW:                  Int          = 2
    public static let WINDOW_MIN:              Int          = 2
    public static let WINDOW_MIN_LIMIT_SLOW:   Int          = 2
    public static let WINDOW_MIN_LIMIT_MEDIUM: Int          = 5
    public static let WINDOW_MIN_LIMIT_FAST:   Int          = 16
    public static let WINDOW_MAX_SLOW:         Int          = 5
    public static let WINDOW_MAX_MEDIUM:       Int          = 12
    public static let WINDOW_MAX_FAST:         Int          = 48
    public static let WINDOW_MAX:              Int          = WINDOW_MAX_FAST
    public static let FAST_RATE_THRESHOLD:     Int          = 10
    public static let RTT_FAST:                TimeInterval = 0.18
    public static let RTT_MEDIUM:              TimeInterval = 0.75
    public static let RTT_SLOW:                TimeInterval = 1.45
    public static let WINDOW_FLEXIBILITY:      Int          = 4
    public static let SEQ_MAX:                 UInt32       = 0xFFFF
    public static let SEQ_MODULUS:             UInt32       = 0x10000
    /// Bytes consumed by the channel envelope header (msgtype + sequence + length).
    /// Mirrors Python `Channel.MDU_OVERHEAD = 4 + 2` (actually 6).
    public static let MDU_OVERHEAD:            Int          = 6

    private let outlet: ChannelOutlet
    private let lock     = NSLock()
    /// Serialises the sequence-reservation + outlet.send() pair so that _tx_ring
    /// never holds an envelope without a valid packet handle. Mirrors Python's
    /// Channel._send_lock added in the 1.3.0 race-condition fix.
    private let sendLock = NSLock()

    private var txRing:           [Envelope] = []
    private var rxRing:           [Envelope] = []
    private var messageHandlers:  [MessageHandlerToken] = []
    private var messageFactories: [UInt16: () -> MessageBase] = [:]

    private var nextSequence:   UInt16 = 0
    private var nextRxSequence: UInt16 = 0
    private let maxTries:       Int    = 5

    public private(set) var window:          Int
    public private(set) var windowMax:       Int
    public private(set) var windowMin:       Int
    public private(set) var windowFlexibility: Int
    public private(set) var fastRateRounds:    Int = 0
    public private(set) var mediumRateRounds:  Int = 0

    public init(outlet: ChannelOutlet) {
        self.outlet = outlet
        if outlet.rtt > Channel.RTT_SLOW {
            window            = 1
            windowMax         = 1
            windowMin         = 1
            windowFlexibility = 1
        } else {
            window            = Channel.WINDOW
            windowMax         = Channel.WINDOW_MAX_SLOW
            windowMin         = Channel.WINDOW_MIN
            windowFlexibility = Channel.WINDOW_FLEXIBILITY
        }
    }

    // MARK: - Type registry

    public func registerMessageType(_ type: MessageBase.Type) throws {
        try _registerMessageType(type, isSystemType: false)
    }

    func _registerMessageType(_ type: MessageBase.Type, isSystemType: Bool = false) throws {
        lock.lock(); defer { lock.unlock() }
        guard type.typeID != 0 else { throw ChannelError.invalidMsgType }
        if type.typeID >= 0xF000 && !isSystemType { throw ChannelError.invalidMsgType }
        let tid = type.typeID
        messageFactories[tid] = { type.init() }
    }

    // MARK: - Message handlers

    @discardableResult
    public func addMessageHandler(_ callback: @escaping (MessageBase) -> Bool) -> MessageHandlerToken {
        let token = MessageHandlerToken(callback: callback)
        lock.lock(); defer { lock.unlock() }
        messageHandlers.append(token)
        return token
    }

    public func removeMessageHandler(_ token: MessageHandlerToken) {
        lock.lock(); defer { lock.unlock() }
        messageHandlers.removeAll { $0 === token }
    }

    // MARK: - MDU

    public var mdu: Int {
        let m = outlet.mdu - Channel.MDU_OVERHEAD
        return min(m, Int(UInt16.max))
    }

    // MARK: - Ready check

    public func isReadyToSend() -> Bool {
        guard outlet.isUsable else { return false }
        lock.lock(); defer { lock.unlock() }
        return _isReadyToSendLocked()
    }

    /// Lock must already be held.
    private func _isReadyToSendLocked() -> Bool {
        let outstanding = txRing.filter { env in
            guard let pkt = env.packet else { return true }
            return outlet.getPacketState(pkt) != .delivered
        }.count
        return outstanding < window
    }

    // MARK: - Send

    /// Send a message over the channel.
    ///
    /// Mirrors the Python 1.3.0 race-condition fix: sequence reservation and
    /// `outlet.send()` are serialised by `sendLock` so that `_tx_ring` never
    /// holds an envelope whose `packet` is nil.  After registering callbacks we
    /// also check whether the packet was already delivered (proof arrived before
    /// the callback was installed) and synthesise the delivery call if so.
    public func send(_ message: MessageBase) throws {
        guard outlet.isUsable else { throw ChannelError.linkNotReady }

        sendLock.lock()
        defer { sendLock.unlock() }

        // --- Phase 1: reserve sequence, pack, and size-check (under main lock) ---
        let reservedSequence: UInt16
        let envelope: Envelope
        let raw: Data

        lock.lock()
        guard _isReadyToSendLocked() else {
            lock.unlock()
            throw ChannelError.linkNotReady
        }
        reservedSequence = nextSequence
        envelope = Envelope(outlet: outlet, message: message, sequence: reservedSequence)
        do {
            raw = try envelope.pack(messageFactories: messageFactories)
        } catch {
            lock.unlock()
            throw error
        }
        guard raw.count <= outlet.mdu else {
            lock.unlock()
            throw ChannelError.tooBig
        }
        nextSequence = UInt16((UInt32(reservedSequence) + 1) % Channel.SEQ_MODULUS)
        lock.unlock()

        // --- Phase 2: transmit (outside main lock to avoid re-entrancy) ---
        let pkt = outlet.send(raw)

        // If the outlet could not transmit (link dropped), rewind sequence.
        // In our Swift outlet, send() always returns a handle, but we guard
        // defensively to mirror Python's check for packet.raw == None.
        guard pkt.raw.count > 0 else {
            lock.lock()
            nextSequence = reservedSequence
            lock.unlock()
            throw ChannelError.linkNotReady
        }

        // --- Phase 3: register envelope and callbacks (back under main lock) ---
        var alreadyDelivered = false
        lock.lock()
        envelope.packet = pkt
        _emplaceEnvelope(envelope, in: &txRing)
        envelope.tries += 1
        outlet.setPacketDeliveredCallback(pkt, callback: { [weak self] p in
            self?._packetDelivered(p)
        })
        outlet.setPacketTimeoutCallback(pkt, timeout: _getPacketTimeout(tries: envelope.tries), callback: { [weak self] p in
            self?._packetTimeout(p)
        })
        _updatePacketTimeouts()
        // Proof may have arrived between outlet.send() and installing the callback.
        alreadyDelivered = (outlet.getPacketState(pkt) == .delivered)
        lock.unlock()

        // Synthesise delivery outside the lock (mirrors Python's already_delivered path).
        if alreadyDelivered { _packetDelivered(pkt) }
    }

    // MARK: - Receive (called by Link when a CHANNEL-context packet arrives)

    public func receive(_ raw: Data) {
        do {
            let envelope = Envelope(outlet: outlet, raw: raw)

            // Unpack BEFORE taking the lock. `unpack` is fallible (unknown msgtype,
            // short frame, decompression failure — all remotely triggerable) and
            // only reads the registry-stable `messageFactories` while mutating the
            // envelope's own local state. Decoding outside the lock guarantees a
            // malformed or unknown frame can NEVER unwind to the catch with the
            // Channel's non-recursive lock still held — previously that leaked the
            // lock permanently, deadlocking every subsequent send/receive/shutdown
            // (a single unknown-msgtype packet from a peer was enough).
            _ = try envelope.unpack(messageFactories: messageFactories)

            lock.lock()
            // Drop stale sequences (before the current RX window).
            if _isStaleSequence(envelope.sequence) {
                lock.unlock()
                return
            }
            let isNew = _emplaceEnvelope(envelope, in: &rxRing)
            lock.unlock()

            guard isNew else { return }

            // Deliver all contiguous envelopes from nextRxSequence onward. A `defer`
            // releases the lock even if an envelope's lazy unpack throws (defensive:
            // envelopes are already unpacked above before emplacement, so the else
            // branch is effectively unreachable, but the lock must never leak).
            var toDeliver: [MessageBase] = []
            lock.lock()
            do {
                defer { lock.unlock() }
                while true {
                    guard let idx = rxRing.firstIndex(where: { $0.sequence == nextRxSequence }) else { break }
                    let e = rxRing.remove(at: idx)
                    let m: MessageBase
                    if e.unpacked, let em = e.message { m = em } else { m = try e.unpack(messageFactories: messageFactories) }
                    nextRxSequence = UInt16((UInt32(nextRxSequence) + 1) % Channel.SEQ_MODULUS)
                    toDeliver.append(m)
                }
            }

            for m in toDeliver { _runCallbacks(m) }

        } catch {
            // Unknown message type or decode failure — drop silently.
        }
    }

    // MARK: - Shutdown

    public func shutdown() {
        lock.lock()
        messageHandlers.removeAll()
        for env in txRing {
            env.tracked = false
            if let pkt = env.packet {
                outlet.setPacketTimeoutCallback(pkt, timeout: nil, callback: nil)
                outlet.setPacketDeliveredCallback(pkt, callback: nil)
            }
        }
        for env in rxRing { env.tracked = false }
        txRing.removeAll()
        rxRing.removeAll()
        lock.unlock()
    }

    // MARK: - Private helpers

    private func _isStaleSequence(_ seq: UInt16) -> Bool {
        let nrx = UInt32(nextRxSequence)
        let s   = UInt32(seq)
        if s < nrx {
            let overflow = (nrx + Channel.SEQ_MODULUS/2) % Channel.SEQ_MODULUS
            if overflow < nrx {
                return s <= overflow
            }
            return true
        }
        return false
    }

    /// Insert `envelope` into `ring` in ascending sequence order.
    /// Returns false if a duplicate sequence is already present.
    @discardableResult
    private func _emplaceEnvelope(_ envelope: Envelope, in ring: inout [Envelope]) -> Bool {
        for (i, existing) in ring.enumerated() {
            if envelope.sequence == existing.sequence { return false }
            if envelope.sequence < existing.sequence &&
               !(_isWraparound(envelope.sequence, reference: nextRxSequence)) {
                ring.insert(envelope, at: i)
                envelope.tracked = true
                return true
            }
        }
        envelope.tracked = true
        ring.append(envelope)
        return true
    }

    /// Mirrors Python's `(next_rx_sequence - envelope.sequence) > SEQ_MAX//2`,
    /// which is computed in *signed* integer arithmetic. Returns true when
    /// `seq` is wrapped-around-future relative to `reference`.
    private func _isWraparound(_ seq: UInt16, reference: UInt16) -> Bool {
        let diff = Int(reference) - Int(seq)
        return diff > Int(Channel.SEQ_MAX) / 2
    }

    private func _runCallbacks(_ message: MessageBase) {
        lock.lock()
        let handlers = messageHandlers
        lock.unlock()
        for token in handlers {
            if token.callback(message) { return }
        }
    }

    private func _getPacketTimeout(tries: Int) -> TimeInterval {
        let t = max(tries, 1)
        return pow(1.5, Double(t - 1)) * max(outlet.rtt * 2.5, 0.025) * Double(txRing.count + 1)
    }

    private func _updatePacketTimeouts() {
        for env in txRing {
            guard let pkt = env.packet else { continue }
            let updated = _getPacketTimeout(tries: env.tries)
            outlet.setPacketTimeoutCallback(pkt, timeout: updated, callback: { [weak self] p in
                self?._packetTimeout(p)
            })
        }
    }

    private func _packetDelivered(_ packet: ChannelPacketHandle) {
        lock.lock()
        guard let idx = txRing.firstIndex(where: {
            guard let p = $0.packet else { return false }
            return outlet.getPacketID(p) == outlet.getPacketID(packet)
        }) else { lock.unlock(); return }
        let env = txRing.remove(at: idx)
        env.tracked = false
        // Advance window on successful delivery.
        if window < windowMax { window += 1 }
        // Update window tier based on RTT.
        let rtt = outlet.rtt
        if rtt != 0 {
            if rtt > Channel.RTT_FAST {
                fastRateRounds = 0
                if rtt > Channel.RTT_MEDIUM {
                    mediumRateRounds = 0
                } else {
                    mediumRateRounds += 1
                    if windowMax < Channel.WINDOW_MAX_MEDIUM && mediumRateRounds == Channel.FAST_RATE_THRESHOLD {
                        windowMax = Channel.WINDOW_MAX_MEDIUM
                        windowMin = Channel.WINDOW_MIN_LIMIT_MEDIUM
                    }
                }
            } else {
                fastRateRounds += 1
                if windowMax < Channel.WINDOW_MAX_FAST && fastRateRounds == Channel.FAST_RATE_THRESHOLD {
                    windowMax = Channel.WINDOW_MAX_FAST
                    windowMin = Channel.WINDOW_MIN_LIMIT_FAST
                }
            }
        }
        lock.unlock()
    }

    private func _packetTimeout(_ packet: ChannelPacketHandle) {
        // Bail early if proof already arrived (avoids spurious retransmits).
        guard outlet.getPacketState(packet) != .delivered else { return }

        let targetID = outlet.getPacketID(packet)

        var shouldTeardown   = false
        var envelopeToResend: Envelope? = nil

        lock.lock()
        // Guard: skip envelopes whose packet is nil (not yet assigned or already torn down).
        guard let idx = txRing.firstIndex(where: {
            guard let p = $0.packet else { return false }
            return outlet.getPacketID(p) == targetID
        }) else { lock.unlock(); return }
        let env = txRing[idx]

        if env.tries >= maxTries {
            shouldTeardown = true
        } else {
            env.tries += 1
            envelopeToResend = env
            if window > windowMin {
                window -= 1
                if windowMax > windowMin + windowFlexibility { windowMax -= 1 }
            }
        }
        lock.unlock()

        if shouldTeardown {
            shutdown()
            outlet.timedOut()
            return
        }

        if let env = envelopeToResend, let pkt = env.packet {
            outlet.resend(pkt)

            var alreadyDelivered = false
            lock.lock()
            outlet.setPacketDeliveredCallback(pkt, callback: { [weak self] p in self?._packetDelivered(p) })
            outlet.setPacketTimeoutCallback(pkt, timeout: _getPacketTimeout(tries: env.tries), callback: { [weak self] p in self?._packetTimeout(p) })
            _updatePacketTimeouts()
            alreadyDelivered = (outlet.getPacketState(pkt) == .delivered)
            lock.unlock()

            if alreadyDelivered { _packetDelivered(pkt) }
        }
    }
}

// MARK: - LinkChannelOutlet

/// Adapts a Link into a ChannelOutlet. Wire-compatible with Python's
/// RNS.Channel.LinkChannelOutlet.
public final class LinkChannelOutlet: ChannelOutlet {
    public let link: Link
    private var queue = DispatchQueue(label: "rns.channel.outlet", attributes: .concurrent)

    public init(link: Link) { self.link = link }

    public func send(_ raw: Data) -> ChannelPacketHandle {
        let handle = ChannelPacketHandle(raw: raw)
        try? link.send(raw, context: .channel)
        return handle
    }

    public func resend(_ handle: ChannelPacketHandle) {
        try? link.send(handle.raw, context: .channel)
    }

    public var mdu: Int { Constants.linkMdu }

    public var rtt: TimeInterval { link.rtt ?? 0 }

    public var isUsable: Bool { link.status == .active }

    public func getPacketState(_ handle: ChannelPacketHandle) -> MessageState {
        switch handle.state {
        case .sent:      return .sent
        case .delivered: return .delivered
        case .failed:    return .failed
        }
    }

    public func timedOut() { try? link.teardown() }

    public func setPacketTimeoutCallback(
        _ handle: ChannelPacketHandle,
        timeout: TimeInterval?,
        callback: ((ChannelPacketHandle) -> Void)?
    ) {
        handle.timeoutWork?.cancel()
        handle.timeoutWork = nil
        guard let timeout, let callback else { return }
        let work = DispatchWorkItem { [weak handle] in
            guard let handle else { return }
            callback(handle)
        }
        handle.timeoutWork = work
        queue.asyncAfter(deadline: .now() + timeout, execute: work)
    }

    public func setPacketDeliveredCallback(
        _ handle: ChannelPacketHandle,
        callback: ((ChannelPacketHandle) -> Void)?
    ) {
        handle.deliveredCallback = callback
    }

    public func getPacketID(_ handle: ChannelPacketHandle) -> ObjectIdentifier? {
        ObjectIdentifier(handle)
    }
}
