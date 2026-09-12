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
        /// Mirrors Python's `packet.packet_hash` (also known as `packet.getTruncatedHash()`).
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
    ///   announces aren't forwarded to other interfaces.
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

        var randomHash = SecureRandom.bytes(5)
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

    /// The fields of an announce body, read off the wire with no signature check.
    ///
    /// Python parses these inline at the top of `Identity.validate_announce`
    /// (`Identity.py:510-548`) and reuses the result for both its signature-only
    /// and its full-validation path. Splitting the parse out keeps the Swift port
    /// to a single reader of the announce layout: `Announce.validate(_:)` and
    /// `Identity.validateAnnounce(_:onlyValidateSignature:isBlackholed:)` both go
    /// through here, so a change to the wire format can't reach one and miss the
    /// other. They previously carried separate hand-rolled parsers that had
    /// already drifted apart over the ratchet field.
    public struct Parsed {
        /// The announced identity, loaded from the announce's public key. Loading
        /// it lets a caller test the blackhole list before spending a signature
        /// verification, which is the order Python uses
        /// (`Identity.py:551-556`).
        public let identity: Identity
        public let publicKey: Data
        public let nameHash: Data
        public let randomHash: Data
        public let ratchet: Data?
        public let signature: Data
        public let appData: Data?
        /// `destination_hash + public_key + name_hash + random_hash + ratchet + app_data`,
        /// the buffer the announce signature covers (`Identity.py:539`).
        public let signedData: Data
    }

    /// Read an announce body into its fields without verifying the signature.
    ///
    /// Mirrors the parse at the top of Python's `Identity.validate_announce`
    /// (`Identity.py:510-548`), including its treatment of the optional fields:
    /// the announce carries a ratchet exactly when it sets the packet's context
    /// flag, and app data is whatever follows the signature.
    ///
    /// - Throws: ``AnnounceError/wrongPacketType`` if the packet isn't an
    ///   announce, or ``AnnounceError/malformed`` if the body is too short to
    ///   hold the fixed fields.
    public static func parse(_ packet: Packet) throws -> Parsed {
        guard packet.packetType == .announce else { throw AnnounceError.wrongPacketType }

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

        return Parsed(
            identity: try Identity(publicKeyBytes: publicKey),
            publicKey: publicKey,
            nameHash: nameHash,
            randomHash: randomHash,
            ratchet: ratchet,
            signature: signature,
            appData: appData,
            signedData: signedData
        )
    }

    /// Validate an announce packet, returning the announced identity and
    /// associated metadata. Verifies the Ed25519 signature *and* that the
    /// destination hash matches `truncated_hash(name_hash || identity_hash)`.
    public static func validate(_ packet: Packet) throws -> Decoded {
        try validate(packet, signatureVerified: false)
    }

    /// The same validation, with the option to skip the signature because the
    /// caller has already verified it over the same bytes.
    ///
    /// This is Python's `packet.announce_signature_validated` short-circuit
    /// (`Identity.py:559-560`): the transport verifies an announce signature at
    /// its admission gate, marks the packet, and the full validation later in
    /// the same pass reads the mark instead of paying for a second Ed25519
    /// verification. This port carries the mark as an argument rather than a
    /// field on `Packet`, and keeps it internal so no caller outside the module
    /// can ask to skip a signature check.
    ///
    /// `signatureVerified` scopes to the signature alone. Everything else still
    /// runs, the destination-hash check included: a signature is valid over
    /// whatever destination hash the signer chose, so it says nothing about
    /// whether that hash is the one this announce claims.
    static func validate(_ packet: Packet, signatureVerified: Bool) throws -> Decoded {
        // Only SINGLE destination announces are valid (Python drops PLAIN/GROUP announces).
        guard packet.destinationType == .single else {
            throw AnnounceError.wrongPacketType
        }

        let parsed = try parse(packet)
        let identity = parsed.identity
        let nameHash = parsed.nameHash
        let randomHash = parsed.randomHash
        let ratchet = parsed.ratchet
        let appData = parsed.appData

        if !signatureVerified {
            guard identity.validate(signature: parsed.signature, for: parsed.signedData) else {
                throw AnnounceError.signatureInvalid
            }
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
