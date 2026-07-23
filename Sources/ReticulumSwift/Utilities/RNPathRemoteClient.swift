import Foundation

/// The `-R` / `-p` half of `rnpath`: linking to a remote transport instance and asking it
/// for its path table, rate table or published blackhole list.
///
/// Python reference: `connect_remote` (rnpath.py:43-91) plus the caller's
/// `while remote_link == None: time.sleep(0.1)` spin (rnpath.py:127, 151).
///
/// ``connect(destinationHash:authIdentity:purpose:progress:)`` and
/// ``request(over:path:value:timeout:)`` block by design — that is what a one-shot CLI
/// wants — so no XCTest drives them. Everything that *can* be asserted without a network
/// (the destination-hash derivation, the request payloads, the response decoders) is
/// `static` for exactly that reason.
public final class RNPathRemoteClient {

    // MARK: - Purpose

    /// Which of the two remote destinations to link to.
    public enum Purpose: Equatable {
        /// `rnstransport.remote.management` — requires `link.identify()`.
        case management
        /// `rnstransport.info.blackhole` — an ALLOW_ALL handler, so no identify is sent.
        case blackhole

        var aspects: [String] {
            switch self {
            case .management: return RNPathApp.managementAspects
            case .blackhole:  return RNPathApp.blackholeAspects
            }
        }
    }

    // MARK: - Errors

    public enum RemoteError: Error, Equatable, CustomStringConvertible {
        /// rnpath.py:56 — the `-W` deadline elapsed waiting for a path to the remote.
        case pathRequestTimedOut
        /// rnpath.py:66 — `Link.TIMEOUT`.
        case linkTimedOut
        /// rnpath.py:70 — `Link.DESTINATION_CLOSED`.
        case linkClosedByServer
        /// rnpath.py:74 — any other teardown reason.
        case linkClosedUnexpectedly
        /// The request concluded without a usable response. Python cannot tell this apart
        /// from an ACL rejection or an empty table; neither can we.
        case requestFailed
        /// `RNS.Identity.recall` returned nil. Python passes the None straight into
        /// `RNS.Destination(...)` and raises there.
        case unknownIdentity
        /// `-i` was missing, or the file did not contain an identity.
        case identityUnavailable(String)

        public var message: String {
            switch self {
            case .pathRequestTimedOut:    return "Path request timed out"
            case .linkTimedOut:           return "The link timed out, exiting now"
            case .linkClosedByServer:     return "The link was closed by the server, exiting now"
            case .linkClosedUnexpectedly: return "Link closed unexpectedly, exiting now"
            case .requestFailed:          return "The remote request failed."
            case .unknownIdentity:        return "Could not recall identity for remote instance"
            case .identityUnavailable(let path): return "Could not load management identity from \(path)"
            }
        }

        public var description: String { message }

        /// Python's exit code for this failure.
        public var result: RNPathApp.Result {
            switch self {
            case .pathRequestTimedOut:
                // rnpath.py:57. In Python the exit(12) is nested inside `if not no_output:`,
                // so `no_output=True` spins forever; Swift exits 12 unconditionally.
                return .remotePathTimeout
            case .linkTimedOut, .linkClosedByServer, .linkClosedUnexpectedly, .requestFailed:
                return .remoteFailure
            case .unknownIdentity, .identityUnavailable:
                return .setupFailure
            }
        }
    }

    // MARK: - Destination hashes

    /// Python: `RNS.Destination.hash_from_name_and_identity(full_name, identity_hash)`
    /// (rnpath.py:114, 149).
    ///
    /// Note that `-R` and `-p` do **not** use the recalled `Identity` object to derive the
    /// destination hash — they use the raw 16 bytes decoded from the hex argument. Python's
    /// `Destination.hash` accepts either an `RNS.Identity` or exactly `TRUNCATED_HASHLENGTH//8`
    /// raw bytes (Destination.py:116-131); Swift's overloads only take `Identity?`, so this
    /// reassembles the same digest from the pieces:
    ///
    /// ```
    /// SHA256( SHA256(full_name_utf8)[:10] ‖ identity_hash_16 )[:16]
    /// ```
    public static func destinationHash(purpose: Purpose, identityHash: Data) -> Data {
        let nameHash = Destination.computeNameHash(appName: RNPathApp.transportAppName,
                                                   aspects: purpose.aspects)
        return Hashes.truncatedHash(nameHash + identityHash)
    }

    // MARK: - Request payloads

    /// Python: `data = ["table", destination_hash, max_hops]` (rnpath.py:260) and
    /// `data = ["rates", destination_hash]` (rnpath.py:313).
    ///
    /// The rates form is deliberately **two** elements — `Transport.remote_path_handler`
    /// reads `data[2]` only when present, and appending a third element there would be a
    /// silent wire divergence.
    public static func pathRequestPayload(command: String,
                                          destinationHash: Data?,
                                          maxHops: UInt8?,
                                          includeMaxHops: Bool = true) -> MsgPack.Value {
        var elements: [MsgPack.Value] = [
            .string(command),
            destinationHash.map { .bytes($0) } ?? .nil,
        ]
        if includeMaxHops {
            elements.append(maxHops.map { .uint(UInt64($0)) } ?? .nil)
        }
        return .array(elements)
    }

    // MARK: - Response decoders

    /// Unwrap whatever ``Link`` handed back into a MsgPack value.
    ///
    /// `Link.handleIncomingResponse` normalises both wire shapes to `Data`: a Python server
    /// embeds a **native** msgpack array in the `[request_id, response]` envelope, while
    /// Swift's own `/path` handler currently returns a msgpack `bin`. Decoding the bytes and,
    /// if that yields a `bin`, decoding again covers both.
    static func decodeResponseValue(_ response: Data) -> MsgPack.Value? {
        guard let value = try? MsgPack.decode(response) else { return nil }
        if case .bytes(let inner) = value, let nested = try? MsgPack.decode(inner) { return nested }
        return value
    }

    /// Python: the `"table"` reply — a list of path dicts.
    public static func decodePathTable(_ response: Data) -> [RNPathTableEntry]? {
        guard let value = decodeResponseValue(response) else { return nil }
        return RNPathTableEntry.decodeTable(value)
    }

    /// Python: the `"rates"` reply — a list of rate dicts.
    public static func decodeRateTable(_ response: Data) -> [RNPathRateEntry]? {
        guard let value = decodeResponseValue(response) else { return nil }
        return RNPathRateEntry.decodeTable(value)
    }

    /// Python: the `/list` reply — `Transport.blackholed_identities` verbatim, a map keyed
    /// by 16-byte identity hash. `nil` here is Python's `type(response) != dict`.
    public static func decodeBlackholeList(_ response: Data) -> [RNPathBlackholeEntry]? {
        guard let value = decodeResponseValue(response) else { return nil }
        return RNPathBlackholeEntry.decodeList(value)
    }

    // MARK: - Live link

    private let transport: Transport
    private let pathRequestTimeout: TimeInterval

    /// - Parameter pathRequestTimeout: the `-W` value, bounding only the wait for a *path*
    ///   to the remote. Python leaves both the link-establishment spin and the request spin
    ///   unbounded (the Link watchdog is what eventually breaks them).
    public init(transport: Transport, pathRequestTimeout: TimeInterval = RNPathApp.defaultTimeout) {
        self.transport = transport
        self.pathRequestTimeout = pathRequestTimeout
    }

    /// `connect_remote` plus the caller's spin-wait, collapsed into one blocking call.
    ///
    /// - Parameter progress: receives Python's unterminated progress strings, already
    ///   carrying the trailing space `end=" "` would have added.
    public func connect(destinationHash: Data,
                        authIdentity: Identity?,
                        purpose: Purpose,
                        progress: ((String) -> Void)? = nil) throws -> Link {

        if !transport.hasPath(to: destinationHash) {
            // Python: ONE trailing space here — contrast the default branch's three.
            progress?("Path to " + RNSUtilities.prettyhexrep(destinationHash) + " requested ")
            try? transport.requestPath(for: destinationHash)
            let deadline = Date().timeIntervalSince1970 + pathRequestTimeout
            while !transport.hasPath(to: destinationHash) {
                Thread.sleep(forTimeInterval: 0.1)
                if Date().timeIntervalSince1970 > deadline { throw RemoteError.pathRequestTimedOut }
            }
        }

        guard let remoteIdentity = transport.recall(identity: destinationHash) else {
            throw RemoteError.unknownIdentity
        }

        progress?(RNPathApp.outputResetString)
        progress?("Establishing link with remote transport instance... ")

        let destination = try Destination(identity: remoteIdentity,
                                          direction: .out,
                                          kind: .single,
                                          appName: RNPathApp.transportAppName,
                                          aspects: purpose.aspects)
        let link = try Link.initiate(destination: destination, transport: transport)
        transport.register(link: link)

        let gate = DispatchSemaphore(value: 0)
        let state = LinkOutcome()

        link.onClosed = { closed in
            // Python: INITIATOR_CLOSED returns silently; every other reason exits 10.
            // `teardownReason` is nil while the link is still active, which maps to the
            // `else` branch — Python's `teardown_reason` is likewise None there.
            switch closed.teardownReason {
            case .some(.initiatorClosed):   break
            case .some(.timeout):           state.set(.linkTimedOut)
            case .some(.destinationClosed): state.set(.linkClosedByServer)
            default:                        state.set(.linkClosedUnexpectedly)
            }
            gate.signal()
        }
        link.onEstablished = { established in
            if purpose == .management, let authIdentity {
                try? established.identify(as: authIdentity)
            }
            state.set(nil)
            gate.signal()
        }

        gate.wait()
        if let failure = state.failure { throw failure }
        return link
    }

    /// Issue one request and block until it concludes.
    ///
    /// Python spins on `receipt.concluded()`, which becomes true for FAILED as well as
    /// READY while `get_response()` stays None — so a timeout and an ACL rejection are
    /// indistinguishable. Both land on ``RemoteError/requestFailed`` here.
    public func request(over link: Link,
                        path: String,
                        value: MsgPack.Value,
                        timeout: TimeInterval) throws -> Data {
        let gate = DispatchSemaphore(value: 0)
        let box = ResponseBox()

        _ = try link.request(path: path,
                             nativeValue: value,
                             responseCallback: { data, _ in box.set(data); gate.signal() },
                             failedCallback:   { _, _ in gate.signal() },
                             timeout: timeout)

        // Guard the blocking wait so a link that never calls back cannot hang the CLI.
        if gate.wait(timeout: .now() + timeout + 5) == .timedOut { throw RemoteError.requestFailed }
        guard let response = box.value else { throw RemoteError.requestFailed }
        return response
    }

    // MARK: - Small thread-safe boxes

    /// Link callbacks arrive on Transport's thread; the CLI thread reads the result.
    private final class LinkOutcome {
        private let lock = NSLock()
        private var stored: RemoteError?
        private var settled = false

        func set(_ error: RemoteError?) {
            lock.lock(); defer { lock.unlock() }
            guard !settled else { return }
            settled = true
            stored = error
        }

        var failure: RemoteError? {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }

    private final class ResponseBox {
        private let lock = NSLock()
        private var stored: Data?

        func set(_ data: Data) { lock.lock(); stored = data; lock.unlock() }
        var value: Data? { lock.lock(); defer { lock.unlock() }; return stored }
    }
}
