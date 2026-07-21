import Foundation

/// A Reticulum packet, with wire format identical to the reference
/// implementation.
///
/// Header byte layout (8 bits, big-endian):
///   bit 7   : reserved (0)
///   bit 6   : header type      (0 = HEADER_1, 1 = HEADER_2)
///   bit 5   : context flag     (0/1)
///   bit 4   : transport type   (0 = broadcast)
///   bits 3-2: destination type (single/group/plain/link)
///   bits 1-0: packet type      (data/announce/linkrequest/proof)
///
/// Followed by:
///   1 byte  : hops
///   16 bytes: transport id              [HEADER_2 only]
///   16 bytes: destination hash
///   1 byte  : context
///   N bytes : data (ciphertext or plaintext per packet rules)
public struct Packet: Equatable {
    public enum HeaderType: UInt8 { case type1 = 0, type2 = 1 }
    public enum TransportType: UInt8 { case broadcast = 0, transport = 1 }
    public enum PacketType: UInt8 { case data = 0, announce = 1, linkRequest = 2, proof = 3 }
    public enum DestinationType: UInt8 { case single = 0, group = 1, plain = 2, link = 3 }
    public enum ContextFlag: UInt8 { case unset = 0, set = 1 }

    /// Context byte values (the ones from Python `Packet.NONE`/`RESOURCE`/...).
    public enum Context: UInt8 {
        case none = 0x00
        case resource = 0x01
        case resourceAdvertisement = 0x02
        case resourceRequest = 0x03
        case resourceHashmapUpdate = 0x04
        case resourceProof = 0x05
        case resourceInitiatorCancel = 0x06
        case resourceReceiverCancel = 0x07
        case cacheRequest = 0x08
        case request = 0x09
        case response = 0x0A
        case pathResponse = 0x0B
        case command = 0x0C
        case commandStatus = 0x0D
        case channel = 0x0E
        case keepalive = 0xFA
        case linkIdentify = 0xFB
        case linkClose = 0xFC
        case linkProof = 0xFD
        case lrrtt = 0xFE
        case lrproof = 0xFF
    }

    public var headerType: HeaderType
    public var contextFlag: ContextFlag
    public var transportType: TransportType
    public var destinationType: DestinationType
    public var packetType: PacketType
    public var hops: UInt8
    public var transportID: Data?           // present only when headerType == .type2
    public var destinationHash: Data        // 16 bytes
    public var context: Context
    public var data: Data                   // payload (encrypted or plaintext per rules)

    // MARK: - Class-level MDU constants (mirrors Python Packet.ENCRYPTED_MDU / PLAIN_MDU)

    /// Maximum payload for encrypted (SINGLE) packets. Mirrors Python `Packet.ENCRYPTED_MDU = 383`.
    public static let encryptedMdu: Int = Constants.encryptedMdu

    /// Maximum payload for unencrypted (PLAIN) packets. Mirrors Python `Packet.PLAIN_MDU = 464`.
    public static let plainMdu: Int = Constants.plainMdu

    // MARK: - PHY stats (set by Transport on receipt from an interface with radio stats)
    // Mirrors Python Packet.rssi / Packet.snr / Packet.q.

    /// Received Signal Strength Indication in dBm, if available.
    public var rssi: Float?
    /// Signal-to-Noise Ratio in dB, if available.
    public var snr: Float?
    /// Link quality 0–100, if available.
    public var quality: Float?

    // MARK: - Delivery metadata (set by Transport; not part of the wire format)

    /// The interface this packet arrived on. Set by Transport when the packet
    /// is delivered to an application callback, enabling `prove()` to route
    /// the proof back through the correct interface.
    /// Mirrors Python's `Packet.receiving_interface`.
    public var receivingInterface: (any Interface)?

    /// Marks this packet as an *outbound* path request — used by Transport's
    /// egress-control logic to throttle recursive PR rebroadcasts. Set when
    /// Transport relays a PR onto an interface, cleared on receive.
    /// Mirrors Python's `Packet.is_outbound_pr` slot (RNS commit 60c440a3).
    public var isOutboundPR: Bool = false

    public init(
        headerType: HeaderType = .type1,
        contextFlag: ContextFlag = .unset,
        transportType: TransportType = .broadcast,
        destinationType: DestinationType,
        packetType: PacketType,
        hops: UInt8 = 0,
        transportID: Data? = nil,
        destinationHash: Data,
        context: Context = .none,
        data: Data
    ) {
        self.headerType = headerType
        self.contextFlag = contextFlag
        self.transportType = transportType
        self.destinationType = destinationType
        self.packetType = packetType
        self.hops = hops
        self.transportID = transportID
        self.destinationHash = destinationHash
        self.context = context
        self.data = data
    }

    public var packedFlagsByte: UInt8 {
        (headerType.rawValue << 6)
            | (contextFlag.rawValue << 5)
            | (transportType.rawValue << 4)
            | (destinationType.rawValue << 2)
            | packetType.rawValue
    }

    /// Estimated wire byte count. Used by the announce rate limiter.
    /// Mirrors Python's `len(packet.raw)`.
    public var rawByteCount: Int {
        let headerSize = headerType == .type2
            ? 2 + Constants.truncatedHashLength * 2
            : 2 + Constants.truncatedHashLength
        return headerSize + data.count
    }

    // MARK: - Encode

    public enum PackError: Error { case missingTransportID, exceedsMTU(size: Int) }

    /// Build the raw wire bytes for this packet **without** enforcing the
    /// transmit MTU cap.
    ///
    /// A packet's identity (its hash) and byte size must be computable
    /// regardless of whether it fits the base `Constants.mtu` — a link packet
    /// can legitimately exceed 500 bytes once a larger link MTU has been
    /// negotiated via MTU discovery. Hashing, deduplication and traffic
    /// accounting therefore use this method, never the MTU-guarded `pack()`.
    ///
    /// Mirrors Python, where `Packet.get_hashable_part()` slices the
    /// already-packed `self.raw` and only `Packet.pack()` raises on
    /// `len(self.raw) > self.MTU`.
    public func packedBytes() throws -> Data {
        var raw = Data()
        raw.append(packedFlagsByte)
        raw.append(hops)

        switch headerType {
        case .type2:
            guard let transportID, transportID.count == Constants.truncatedHashLength else {
                throw PackError.missingTransportID
            }
            raw.append(transportID)
            raw.append(destinationHash)
        case .type1:
            raw.append(destinationHash)
        }

        raw.append(context.rawValue)
        raw.append(data)
        return raw
    }

    public func pack() throws -> Data {
        let raw = try packedBytes()
        if raw.count > Constants.mtu { throw PackError.exceedsMTU(size: raw.count) }
        return raw
    }

    // MARK: - Decode

    public enum UnpackError: Error { case malformed }

    public static func unpack(_ raw: Data) throws -> Packet {
        guard raw.count >= 2 + Constants.truncatedHashLength + 1 else {
            throw UnpackError.malformed
        }

        let flags = raw[raw.startIndex]
        let hops = raw[raw.startIndex + 1]

        // Reject packets whose hop count has reached or exceeded the maximum
        // propagation distance — a valid packet can never legitimately carry
        // hops >= PATHFINDER_M, so such a value indicates a corrupt/malformed
        // header. Python (RNS 1.3.8): raise ValueError(f"Invalid hop count {hops}").
        guard Int(hops) < Transport.pathfinderM else { throw UnpackError.malformed }

        guard
            let headerType = HeaderType(rawValue: (flags & 0b0100_0000) >> 6),
            let contextFlag = ContextFlag(rawValue: (flags & 0b0010_0000) >> 5),
            let transportType = TransportType(rawValue: (flags & 0b0001_0000) >> 4),
            let destinationType = DestinationType(rawValue: (flags & 0b0000_1100) >> 2),
            let packetType = PacketType(rawValue: flags & 0b0000_0011)
        else { throw UnpackError.malformed }

        let dstLen = Constants.truncatedHashLength
        var cursor = raw.startIndex + 2

        var transportID: Data? = nil
        if headerType == .type2 {
            guard raw.count >= 2 + dstLen + dstLen + 1 else { throw UnpackError.malformed }
            transportID = raw.subdata(in: cursor..<(cursor + dstLen))
            cursor += dstLen
        }

        let destinationHash = raw.subdata(in: cursor..<(cursor + dstLen))
        cursor += dstLen

        guard cursor < raw.endIndex else { throw UnpackError.malformed }
        guard let context = Context(rawValue: raw[cursor]) else { throw UnpackError.malformed }
        cursor += 1

        let data = raw.subdata(in: cursor..<raw.endIndex)

        return Packet(
            headerType: headerType,
            contextFlag: contextFlag,
            transportType: transportType,
            destinationType: destinationType,
            packetType: packetType,
            hops: hops,
            transportID: transportID,
            destinationHash: destinationHash,
            context: context,
            data: data
        )
    }

    // MARK: - Hashing

    /// "Hashable part" of the packet — used to derive a stable packet hash
    /// regardless of header type 1 vs 2 (transport ID is excluded).
    /// Mirrors `Packet.get_hashable_part` in Python.
    public func hashablePart() throws -> Data {
        // Use packedBytes(), NOT pack(): a packet's hash is independent of the
        // transmit MTU. Routing a link packet that legitimately exceeds the base
        // MTU (larger negotiated link MTU) must still hash/dedup correctly on
        // receive — pack()'s MTU guard here would throw and cause Transport's
        // dedup (filterAndRecord) to silently drop every oversize inbound packet.
        let raw = try packedBytes()
        var part = Data()
        part.append(raw[raw.startIndex] & 0b0000_1111)
        switch headerType {
        case .type1:
            part.append(raw.suffix(from: raw.startIndex + 2))
        case .type2:
            part.append(raw.suffix(from: raw.startIndex + 2 + Constants.truncatedHashLength))
        }
        return part
    }

    public func packetHash() throws -> Data {
        Hashes.fullHash(try hashablePart())
    }

    /// Truncated 16-byte hash of this packet (first 16 bytes of SHA-256 of hashable part).
    /// Mirrors Python's `Packet.getTruncatedHash()`.
    public func truncatedPacketHash() throws -> Data {
        Hashes.truncatedHash(try hashablePart())
    }

    /// Send this packet via the shared Reticulum instance.
    /// Mirrors Python's `Packet.send()` (which calls `Transport.outbound(self)`).
    /// Requires `Reticulum.start()` to have been called.
    @discardableResult
    public func sendViaShared() throws -> PacketReceipt? {
        try Reticulum.shared?.transport.send(self)
    }

    /// Re-send this packet via the shared Reticulum instance.
    /// Identical to `sendViaShared()` but semantically signals intent to
    /// retransmit an already-constructed packet.
    /// Mirrors Python's `Packet.resend()`.
    @discardableResult
    public func resend() throws -> PacketReceipt? {
        try sendViaShared()
    }

    /// Generate and send a delivery proof for this packet.
    ///
    /// Requires that `receivingInterface` is set (done automatically when the
    /// packet is delivered via an application packet callback).
    /// Mirrors Python's `Packet.prove(destination)`.
    ///
    /// - Parameter destination: The local destination that received the packet,
    ///   used to sign the proof with the correct identity.
    public func prove(destination: Destination) {
        guard let iface = receivingInterface else { return }
        Reticulum.shared?.transport.provePacket(self, from: iface, destination: destination)
    }

    // MARK: - Equatable

    /// Packet equality is based on wire content only; `receivingInterface` is
    /// transient runtime metadata and is excluded from comparison.
    public static func == (lhs: Packet, rhs: Packet) -> Bool {
        lhs.headerType == rhs.headerType &&
        lhs.contextFlag == rhs.contextFlag &&
        lhs.transportType == rhs.transportType &&
        lhs.destinationType == rhs.destinationType &&
        lhs.packetType == rhs.packetType &&
        lhs.hops == rhs.hops &&
        lhs.transportID == rhs.transportID &&
        lhs.destinationHash == rhs.destinationHash &&
        lhs.context == rhs.context &&
        lhs.data == rhs.data
    }
}
