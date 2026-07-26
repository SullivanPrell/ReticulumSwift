import Foundation
import CryptoKit

/// The RSG (Reticulum SiGnature) container.
///
/// Python reference: `RNS/Utilities/rnid.py` — `get_rsg_data` (:397), `extract_signed_rsg_data`
/// (:413), `get_rsg_hash` (:421), `rsg_is_legacy_format` (:431), `validate_rsg` (:436),
/// `create_rsg` (:488) and `check_release_rsm_structure` (:588).
///
/// Two on-disk layouts exist and the **only** discriminator between them is the file length:
///
/// - **Legacy** — exactly 64 bytes, containing nothing but `Ed25519_sign(entire target file)`.
///   Produced only by `rnid -s --raw`, and unverifiable without an explicitly supplied Identity.
/// - **Modern** — `[64-byte Ed25519 signature][msgpack envelope]`. The signature covers the
///   envelope bytes *exactly as stored*, so cross-implementation validation does not require
///   byte-identical msgpack — but ReticulumSwift's encoder is byte-identical to RNS's vendored
///   umsgpack for every type an envelope can hold, and ``SignedData/envelope()`` reproduces
///   Python's dict insertion order.
public enum RSG {

    /// Python: `siglen = RNS.Identity.SIGLENGTH//8` = 64.
    public static let signatureLength: Int = Constants.signatureLength

    // MARK: - SignedData

    /// The decoded msgpack envelope, with **ordered** entries.
    ///
    /// Order is load-bearing twice over: `create_rsg` relies on Python dict insertion order
    /// when merging `-E` metadata, and the `--meta` printer walks the map in that order.
    /// Never route this through `MsgPack.Value.asDictionary`, which flattens to an unordered
    /// `[String: Value]`.
    public struct SignedData: Equatable {

        /// Top-level entries exactly as they appear in the envelope.
        public let entries: [(String, MsgPack.Value)]

        /// Build the envelope `create_rsg` produces (rnid.py:492-506).
        ///
        /// Insertion order: `hashtype`, `hash`, `meta` (itself `signer`, `pubkey`, then any
        /// extras), and finally `message` when embedding — `message` is assigned after the
        /// `meta` key already exists, so it always lands last at top level.
        public init(hashType: String, hash: Data, meta: [(String, MsgPack.Value)], message: Data?) {
            var entries: [(String, MsgPack.Value)] = [
                ("hashtype", .string(hashType)),
                ("hash", .bytes(hash)),
                ("meta", .map(meta.map { (MsgPack.Value.string($0.0), $0.1) }))
            ]
            if let message { entries.append(("message", .bytes(message))) }
            self.entries = entries
        }

        /// Wrap already-ordered entries, e.g. from ``decode(envelope:)``.
        public init(entries: [(String, MsgPack.Value)]) {
            self.entries = entries
        }

        // MARK: Accessors

        /// Whether a top-level key is present. Python: `"hashtype" in signed_data`.
        public func has(_ key: String) -> Bool { entries.contains { $0.0 == key } }

        /// The raw value for a top-level key.
        public func value(_ key: String) -> MsgPack.Value? {
            entries.first { $0.0 == key }?.1
        }

        /// Python: `signed_data["hashtype"]`. Empty when absent or not a string.
        public var hashType: String { value("hashtype")?.asString ?? "" }

        /// Python: `signed_data["hash"]` — a 32-byte SHA-256 digest.
        public var hash: Data { value("hash")?.asData ?? Data() }

        /// Python: `signed_data["meta"]`, in insertion order.
        public var meta: [(String, MsgPack.Value)] {
            guard case .map(let pairs)? = value("meta") else { return [] }
            return pairs.compactMap { key, value in
                guard case .string(let name) = key else { return nil }
                return (name, value)
            }
        }

        /// Whether the envelope carries a `meta` map at all.
        public var hasMeta: Bool {
            if case .map? = value("meta") { return true }
            return false
        }

        /// Python: `signed_data["message"]` — present only in `.rsm` files.
        public var message: Data? { value("message")?.asData }

        /// Python: `signed_data["meta"]["signer"]` — the signer's 16-byte identity hash.
        public var signer: Data? { metaValue("signer")?.asData }

        /// Python: `signed_data["meta"]["pubkey"]` — the signer's 64-byte public blob.
        public var pubkey: Data? { metaValue("pubkey")?.asData }

        public func metaValue(_ key: String) -> MsgPack.Value? {
            meta.first { $0.0 == key }?.1
        }

        public func hasMetaKey(_ key: String) -> Bool { meta.contains { $0.0 == key } }

        // MARK: Codec

        /// Python: `mp.packb(signed_data)`.
        public func envelope() -> Data {
            MsgPack.encode(.map(entries.map { (MsgPack.Value.string($0.0), $0.1) }))
        }

        /// Python: `mp.unpackb(envelope)`.
        /// - Throws: ``RSG/RSGError/malformedEnvelope`` when the bytes are not a msgpack map.
        public static func decode(envelope: Data) throws -> SignedData {
            guard let decoded = try? MsgPack.decode(envelope), case .map(let pairs) = decoded else {
                throw RSGError.malformedEnvelope
            }
            let entries: [(String, MsgPack.Value)] = pairs.compactMap { key, value in
                guard case .string(let name) = key else { return nil }
                return (name, value)
            }
            return SignedData(entries: entries)
        }

        public static func == (lhs: SignedData, rhs: SignedData) -> Bool {
            guard lhs.entries.count == rhs.entries.count else { return false }
            for index in 0..<lhs.entries.count {
                if lhs.entries[index].0 != rhs.entries[index].0 { return false }
                if lhs.entries[index].1 != rhs.entries[index].1 { return false }
            }
            return true
        }
    }

    // MARK: - Inputs

    /// What `get_rsg_hash` accepts. Python: `bytes`, `str` or `io.BufferedReader`
    /// (rnid.py:421-429).
    public enum Message {
        case bytes(Data)
        case text(String)
        /// Python: an open file handle, hashed with `hashlib.file_digest`.
        case file(RNIDByteReader)

        /// Python truthiness of the `message` argument: an open file handle is always
        /// truthy, but `b""` and `""` are falsy and trip `validate_rsg`'s guard.
        var isTruthy: Bool {
            switch self {
            case .bytes(let data): return !data.isEmpty
            case .text(let text):  return !text.isEmpty
            case .file:            return true
            }
        }

        /// The bytes an embedded message is stored as. Python: `message.encode("utf-8")`
        /// for `str`, the bytes themselves otherwise.
        var embeddableBytes: Data? {
            switch self {
            case .bytes(let data): return data
            case .text(let text):  return Data(text.utf8)
            case .file:            return nil
            }
        }
    }

    /// Python: `required_signer` is an `RNS.Identity`, raw `bytes`, or `None`.
    public enum RequiredSigner {
        case identity(Identity)
        case hash(Data)
        case none

        /// Python: `required_signer_hash`.
        var hash: Data? {
            switch self {
            case .identity(let identity): return identity.hash
            case .hash(let value):        return value
            case .none:                   return nil
            }
        }

        /// Python: `if identity:` — used for the `signer_description` suffix.
        var isTruthy: Bool {
            switch self {
            case .identity: return true
            case .hash(let value): return !value.isEmpty
            case .none: return false
            }
        }
    }

    /// `create_rsg`'s return value. Python yields `bytes` for bin/hex/base32/base64 and a
    /// `str` for base256; the text forms are byte-identical either way, so the port models
    /// the four encoded formats as text.
    public enum Encoded: Equatable {
        case binary(Data)
        case text(String)

        /// The bytes Python would have produced.
        public var data: Data {
            switch self {
            case .binary(let data): return data
            case .text(let text):   return Data(text.utf8)
            }
        }
    }

    /// Python: `validate_rsg` returns the 3-tuple `(valid, signed_data, signing_identity)`.
    public struct ValidationResult {
        public let isValid: Bool
        public let signedData: SignedData?
        public let signingIdentity: Identity?

        public init(isValid: Bool, signedData: SignedData?, signingIdentity: Identity?) {
            self.isValid = isValid
            self.signedData = signedData
            self.signingIdentity = signingIdentity
        }

        /// Python: `return False, None, None`.
        static let rejected = ValidationResult(isValid: false, signedData: nil, signingIdentity: nil)
    }

    public enum RSGError: Error, Equatable {
        /// Python: `TypeError("Invalid output format for rsg creation")`.
        case invalidOutputFormat
        /// Python: `ValueError(f"{signer_identity} does not hold a private key")`.
        case missingPrivateKey
        /// Python: `ValueError("No message specified for rsg validation")`.
        case noMessage
        /// Python: `ValueError("Cannot validate legacy rsg format")`.
        case legacyFormat
        /// Python: `get_rsg_data` returned `None`, and the caller then subscripted it.
        case undecodableInput
        /// Python: `mp.unpackb(envelope)` raised.
        case malformedEnvelope
    }

    // MARK: - get_rsg_data

    /// Python: `get_rsg_data(rsg)` for `bytes` input — returned as-is.
    public static func data(from rsg: Data) -> Data? { rsg }

    /// Python: `get_rsg_data(rsg)` for `str` input, corrected — see
    /// ``RNIDEncoding/decodeLadder(_:)`` for why this diverges.
    public static func data(fromText rsg: String) -> Data? { RNIDEncoding.decodeLadder(rsg) }

    // MARK: - get_rsg_hash

    /// Python: `get_rsg_hash(message)` (rnid.py:421-429) — always a 32-byte SHA-256 digest.
    ///
    /// The `.file` case streams, matching `hashlib.file_digest`; the digest is identical to
    /// the one-shot form.
    public static func hash(of message: Message) throws -> Data {
        switch message {
        case .bytes(let data): return Hashes.fullHash(data)
        case .text(let text):  return Hashes.fullHash(Data(text.utf8))
        case .file(let reader):
            var hasher = SHA256()
            // 1 MiB reads: large enough to keep syscall overhead negligible, small enough
            // that a multi-gigabyte signing target never lands in memory.
            let chunkSize = 1 << 20
            while true {
                let chunk = try reader.read(upTo: chunkSize)
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            return Data(hasher.finalize())
        }
    }

    // MARK: - Legacy detection

    /// Python: `rsg_is_legacy_format(rsg)` (rnid.py:431-434). Length is the only discriminator.
    public static func isLegacyFormat(_ rsgData: Data) -> Bool {
        guard !rsgData.isEmpty else { return false }   // Python: `if not rsg_data: return False`
        return rsgData.count == signatureLength
    }

    /// Python: the legacy branch of `validate` (rnid.py:660-671) —
    /// `identity.validate(signature, fh.read())` over the whole target file.
    public static func validateLegacy(signature: Data, fileData: Data, identity: Identity) -> Bool {
        identity.validate(signature: signature, for: fileData)
    }

    // MARK: - extract_signed_rsg_data

    /// Python: `extract_signed_rsg_data(rsg)` (rnid.py:413-419).
    ///
    /// Reads an `.rsm`'s embedded message *before* the signature is validated. Note the slice
    /// `rsg_data[siglen:]` sits **outside** the `try`, so a `None` from `get_rsg_data`
    /// propagates a `TypeError` to the caller rather than yielding `None` — modelled here as
    /// ``RSGError/undecodableInput``, which the operation layer maps to exit code 254.
    /// A truncated (<64 byte) input yields an empty envelope, which fails to unpack → `nil`.
    public static func extractSignedData(_ rsgData: Data?) throws -> SignedData? {
        guard let rsgData else { throw RSGError.undecodableInput }
        let envelope = rsgData.count > signatureLength
            ? rsgData.subdata(in: signatureLength..<rsgData.count)
            : Data()
        return try? SignedData.decode(envelope: envelope)
    }

    // MARK: - create_rsg

    /// Python: `create_rsg(signer_identity, message, embed, meta, output)` (rnid.py:488-516).
    public static func create(
        signer: Identity,
        message: Message,
        embed: Bool = false,
        meta: [(String, MsgPack.Value)]? = nil,
        output: RNIDApp.OutputFormat = .bin
    ) throws -> Encoded {
        guard signer.hasPrivateKey else { throw RSGError.missingPrivateKey }

        let messageHash = try hash(of: message)

        // Python: {"signer": …, "pubkey": …} then any extras that are not already present,
        // so the two canonical keys can never be overridden.
        var metaEntries: [(String, MsgPack.Value)] = [
            ("signer", .bytes(signer.hash)),
            ("pubkey", .bytes(signer.getPublicKey()))
        ]
        // Python: `if meta and type(meta) == dict:` — an empty mapping is silently ignored.
        if let meta, !meta.isEmpty {
            for (key, value) in meta where !metaEntries.contains(where: { $0.0 == key }) {
                metaEntries.append((key, value))
            }
        }

        let signedData = SignedData(
            hashType: RNIDApp.rsgHashTypes[0],
            hash: messageHash,
            meta: metaEntries,
            message: embed ? message.embeddableBytes : nil
        )

        let envelope = signedData.envelope()
        let signature = try signer.sign(envelope)
        let rsgData = signature + envelope

        switch output {
        case .bin:     return .binary(rsgData)
        case .hex:     return .text(RNIDEncoding.hexEncode(rsgData))
        case .base32:  return .text(RNIDEncoding.base32Encode(rsgData))
        case .base64:  return .text(RNIDEncoding.base64URLEncode(rsgData))
        case .base256: return .text(RNIDEncoding.base256Encode(rsgData))
        }
    }

    /// String-named overload for API parity with `create_rsg(..., output="hex")`.
    /// Python: `if not output in [...]: raise TypeError("Invalid output format for rsg creation")`.
    public static func create(
        signer: Identity,
        message: Message,
        embed: Bool = false,
        meta: [(String, MsgPack.Value)]? = nil,
        outputName: String
    ) throws -> Encoded {
        guard let format = RNIDApp.OutputFormat(rawValue: outputName) else {
            throw RSGError.invalidOutputFormat
        }
        return try create(signer: signer, message: message, embed: embed, meta: meta, output: format)
    }

    // MARK: - validate_rsg

    /// Python: `validate_rsg(rsg, message, required_signer)` (rnid.py:436-486).
    ///
    /// The gate order below is Python's, verbatim, including two quirks worth calling out:
    /// the message is hashed *before* the legacy-length check, and a signer-hash mismatch or
    /// hash mismatch returns `signed_data == nil` while a *tampered signature* returns it
    /// non-nil.
    public static func validate(
        rsgData: Data,
        message: Message,
        requiredSigner: RequiredSigner
    ) throws -> ValidationResult {

        // Python: `if not message: raise ValueError("No message specified for rsg validation")`.
        guard message.isTruthy else { throw RSGError.noMessage }

        var requiredSignerHash = requiredSigner.hash

        // Python hashes the message before the legacy check, so even a legacy rsg pays for
        // the full file hash.
        let messageHash = try hash(of: message)

        // Python: this precedes the `if not rsg_data` guard (rnid.py:448 before :450).
        if rsgData.count == signatureLength { throw RSGError.legacyFormat }
        if rsgData.isEmpty { return .rejected }
        if rsgData.count < signatureLength + 1 { return .rejected }

        let signature = rsgData.prefix(signatureLength)
        let envelope = rsgData.subdata(in: signatureLength..<rsgData.count)

        guard let signedData = try? SignedData.decode(envelope: envelope) else { return .rejected }

        guard signedData.has("hashtype"), signedData.has("hash") else { return .rejected }
        guard RNIDApp.rsgHashTypes.contains(signedData.hashType) else { return .rejected }
        guard signedData.hasMeta else { return .rejected }
        guard signedData.hasMetaKey("signer") else { return .rejected }
        guard signedData.hasMetaKey("pubkey") else { return .rejected }

        // Python: when an explicit Identity is required, the EMBEDDED pubkey is ignored.
        let signingIdentity: Identity
        switch requiredSigner {
        case .identity(let identity):
            signingIdentity = identity
        case .hash, .none:
            guard let pubkey = signedData.pubkey,
                  let loaded = try? Identity(publicKeyBytes: pubkey) else { return .rejected }
            signingIdentity = loaded
        }

        // Python: self-consistent validation when no signer was demanded.
        if requiredSignerHash == nil { requiredSignerHash = signingIdentity.hash }

        guard signingIdentity.hash == requiredSignerHash else {
            return ValidationResult(isValid: false, signedData: nil, signingIdentity: signingIdentity)
        }
        guard signedData.hash == messageHash else {
            return ValidationResult(isValid: false, signedData: nil, signingIdentity: signingIdentity)
        }

        let valid = signingIdentity.validate(signature: Data(signature), for: envelope)
        return ValidationResult(isValid: valid, signedData: signedData, signingIdentity: signingIdentity)
    }

    // MARK: - check_release_rsm_structure

    /// Python: `check_release_rsm_structure(signed_data)` (rnid.py:588-600).
    ///
    /// Returns `nil` where Python returns `True`, otherwise the human-readable error string.
    /// Not reachable from the `rnid` CLI — `RNS/Utilities/rngit/server.py:54` imports it.
    public static func checkReleaseRSMStructure(_ signedData: SignedData) -> String? {
        let meta = signedData.meta
        if meta.isEmpty { return "No release metadata in manifest" }

        func truthy(_ value: MsgPack.Value?) -> Bool {
            guard let value else { return false }
            switch value {
            case .nil:              return false
            case .bool(let flag):   return flag
            case .string(let text): return !text.isEmpty
            case .bytes(let data):  return !data.isEmpty
            case .array(let items): return !items.isEmpty
            case .map(let pairs):   return !pairs.isEmpty
            case .int(let n):       return n != 0
            case .uint(let n):      return n != 0
            case .double(let d):    return d != 0
            }
        }

        let name = signedData.metaValue("name")
        let version = signedData.metaValue("version")
        let origin = signedData.metaValue("origin")
        let path = signedData.metaValue("path")

        if !truthy(name) || !truthy(version) { return "Incomplete package data in manifest" }
        if !truthy(origin) || !truthy(path) { return "Incomplete release origin data in manifest" }

        let nameText = name?.asString ?? ""
        let versionText = version?.asString ?? ""
        if nameText.contains("/") || versionText.contains("/") { return "Invalid data in release manifest" }

        // Python checks the LENGTH before the TYPE, so a 16-character str origin passes the
        // length gate and fails the type gate.
        let originLength: Int
        switch origin {
        case .bytes(let data)?:  originLength = data.count
        case .string(let text)?: originLength = text.count
        case .array(let items)?: originLength = items.count
        default:                 originLength = -1
        }
        if originLength != Constants.truncatedHashLength { return "Invalid origin hash length in manifest" }
        if origin?.asData == nil { return "Invalid origin hash in manifest" }

        return nil
    }
}
