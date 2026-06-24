import Foundation

/// Build and validate Announce packets.
///
/// Wire format of an announce's `data` payload (matches Python):
///   * Without ratchet (context_flag = 0):
///     [public_key 64] [name_hash 10] [random_hash 10] [signature 64] [app_data?]
///   * With ratchet    (context_flag = 1):
///     [public_key 64] [name_hash 10] [random_hash 10] [ratchet 32] [signature 64] [app_data?]
///
/// Where:
///   random_hash = 5 random bytes || 5-byte big-endian unix timestamp
///   signature   = Ed25519(destination_hash || public_key || name_hash
///                        || random_hash || ratchet || app_data)
public enum Announce {

    public struct Decoded: Equatable {
        public let identity: Identity
        public let destinationHash: Data
        public let nameHash: Data
        public let randomHash: Data
        public let ratchet: Data?
        public let appData: Data?
        /// True when this announce was received in response to a path request
        /// (Python: `packet.context == Packet.PATH_RESPONSE`).
        public let isPathResponse: Bool
        /// 16-byte (128-bit) truncated hash of the announce packet.
        /// Mirrors Python's `packet.packet_hash` (aka `packet.getTruncatedHash()`).
        public let packetHash: Data
    }

    public enum AnnounceError: Error {
        case wrongPacketType
        case malformed
        case signatureInvalid
        case destinationHashMismatch
    }

    /// Build an announce packet for an inbound `single` destination.
    /// - Parameter isPathResponse: If true, the packet context is set to `.pathResponse`,
    ///   indicating this announce was emitted in response to a path request. Path response
    ///   announces are not forwarded to other interfaces.
    ///   Mirrors Python's `Destination.announce(path_response=True)`.
    public static func make(
        for destination: Destination,
        appData: Data? = nil,
        ratchet: Data? = nil,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        isPathResponse: Bool = false
    ) throws -> Packet {
        guard destination.kind == .single, destination.direction == .in else {
            throw AnnounceError.wrongPacketType
        }
        guard let identity = destination.identity, identity.hasPrivateKey else {
            throw Destination.DestinationError.missingIdentity
        }

        // Python-parity: when ratchets are enabled on this destination,
        // lazily rotate (interval-gated), embed the active ratchet's
        // public bytes, and persist the privates to the destination's
        // configured sidecar.
        // Resolve effective app data: explicit arg takes precedence, then
        // destination.effectiveAppData (callable or static), matching
        // Python's Destination.announce() behaviour.
        let appData = appData ?? destination.effectiveAppData

        var ratchetBytes = ratchet
        if destination.ratchetsEnabled {
            if identity.activeRatchetPrivateKey == nil {
                identity.rotateRatchet()
            } else {
                _ = identity.rotateRatchetIfNeeded()
            }
            destination.persistRatchets()
            if ratchetBytes == nil {
                ratchetBytes = identity.activeRatchetPublicKey
            }
        }

        var randomHash = Data(count: 5)
        _ = randomHash.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 5, $0.baseAddress!)
        }
        let ts = UInt64(timestamp)
        var tsBytes = Data(count: 5)
        for i in 0..<5 { tsBytes[i] = UInt8((ts >> (8 * (4 - i))) & 0xFF) }
        randomHash.append(tsBytes)

        let pub = identity.publicKeyBytes

        var signedData = Data()
        signedData.append(destination.hash)
        signedData.append(pub)
        signedData.append(destination.nameHash)
        signedData.append(randomHash)
        if let ratchetBytes { signedData.append(ratchetBytes) }
        if let appData { signedData.append(appData) }

        let signature = try identity.sign(signedData)

        var announceData = Data()
        announceData.append(pub)
        announceData.append(destination.nameHash)
        announceData.append(randomHash)
        if let ratchetBytes { announceData.append(ratchetBytes) }
        announceData.append(signature)
        if let appData { announceData.append(appData) }

        return Packet(
            headerType: .type1,
            contextFlag: ratchetBytes == nil ? .unset : .set,
            transportType: .broadcast,
            destinationType: .single,
            packetType: .announce,
            hops: 0,
            destinationHash: destination.hash,
            context: isPathResponse ? .pathResponse : .none,
            data: announceData
        )
    }

    /// Validate an announce packet, returning the announced identity and
    /// associated metadata. Verifies the Ed25519 signature *and* that the
    /// destination hash matches `truncated_hash(name_hash || identity_hash)`.
    public static func validate(_ packet: Packet) throws -> Decoded {
        // Only SINGLE destination announces are valid (Python drops PLAIN/GROUP announces).
        guard packet.packetType == .announce, packet.destinationType == .single else {
            throw AnnounceError.wrongPacketType
        }

        let keysize = Constants.keySize
        let nameHashLen = Constants.nameHashLength
        let randLen = Constants.randomHashLength
        let sigLen = Constants.signatureLength
        let ratchetLen = Constants.ratchetSize
        let body = packet.data

        let baseRequired = keysize + nameHashLen + randLen + sigLen
        let withRatchetRequired = baseRequired + ratchetLen
        let hasRatchet = packet.contextFlag == .set
        guard body.count >= (hasRatchet ? withRatchetRequired : baseRequired) else {
            throw AnnounceError.malformed
        }

        var cursor = 0
        let publicKey = body.subdata(in: cursor..<(cursor + keysize)); cursor += keysize
        let nameHash = body.subdata(in: cursor..<(cursor + nameHashLen)); cursor += nameHashLen
        let randomHash = body.subdata(in: cursor..<(cursor + randLen)); cursor += randLen

        var ratchet: Data? = nil
        if hasRatchet {
            ratchet = body.subdata(in: cursor..<(cursor + ratchetLen))
            cursor += ratchetLen
        }

        let signature = body.subdata(in: cursor..<(cursor + sigLen)); cursor += sigLen
        let appData: Data? = cursor < body.count ? body.subdata(in: cursor..<body.count) : nil

        var signedData = Data()
        signedData.append(packet.destinationHash)
        signedData.append(publicKey)
        signedData.append(nameHash)
        signedData.append(randomHash)
        if let ratchet { signedData.append(ratchet) }
        if let appData { signedData.append(appData) }

        let identity = try Identity(publicKeyBytes: publicKey)
        guard identity.validate(signature: signature, for: signedData) else {
            throw AnnounceError.signatureInvalid
        }

        var hashMaterial = Data()
        hashMaterial.append(nameHash)
        hashMaterial.append(identity.hash)
        let expectedDestinationHash = Hashes.truncatedHash(hashMaterial)
        guard expectedDestinationHash == packet.destinationHash else {
            throw AnnounceError.destinationHashMismatch
        }

        identity.appData = appData

        let packetHash = Hashes.truncatedHash((try? packet.hashablePart()) ?? Data())

        return Decoded(
            identity: identity,
            destinationHash: packet.destinationHash,
            nameHash: nameHash,
            randomHash: randomHash,
            ratchet: ratchet,
            appData: appData,
            isPathResponse: packet.context == .pathResponse,
            packetHash: packetHash
        )
    }
}
