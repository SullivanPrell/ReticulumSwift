import Foundation

/// Fetches status from a *remote* transport instance over a `Link`, the way
/// `rnstatus -R <hash> -i <identity>` does.
///
/// Python reference: `get_remote_status` (`RNS/Utilities/rnstatus.py:66-153`) and the
/// responder half, `Transport.remote_status_handler` (`RNS/Transport.py:2849-2864`).
///
/// Python keeps `remote_destination` / `remote_link` / `first_remote_req` in module
/// globals so monitor mode can reuse one established link across refreshes; here they are
/// instance state, and the executable holds the instance for the life of the loop.
///
/// The `transport` reference is deliberately **strong**: `Link.transport` is weak, so
/// something has to keep the stack alive or every send after the first refresh fails.
public final class RemoteStatusQuery {

    // MARK: - Errors

    public enum QueryError: Error, Equatable {
        /// No path to the management destination within the timeout. Python: exit 12.
        case noPath
        /// `RNS.Identity.recall(destination_hash)` returned nothing, so the outbound
        /// SINGLE destination cannot be built. Python: the `Destination(...)` raises.
        case noRemoteIdentity
        /// `Link.TIMEOUT`. Python: "The link timed out, exiting now", exit 10.
        case linkTimedOut
        /// `Link.DESTINATION_CLOSED`. Python: "The link was closed by the server…", exit 10.
        case linkClosedByServer
        /// Any other teardown reason. Python: "Link closed unexpectedly, exiting now", exit 10.
        case linkClosedUnexpectedly
        /// The responder refused the request — usually an authentication failure.
        /// Python: `request_failed`, which leaves `request_result` nil → exit 2.
        case requestFailed
        /// The response decoded, but slot 0 was not a stats dict.
        ///
        /// This is the guard that matters on the Swift side: `Link.handleIncomingResponse`
        /// transparently unwraps a `.bytes`-wrapped payload, so a Swift client cannot
        /// detect the double-wrapping the way Python's `isinstance(response, list)` does.
        /// The malformed check therefore has to be "does slot 0 contain an `interfaces`
        /// key", not "is it an array".
        case malformedResponse
    }

    // MARK: - State

    private let transport: Transport            // strong: Link.transport is weak
    private let destinationHash: Data
    private let managementIdentity: Identity
    private let timeout: TimeInterval

    /// The link reused across monitor refreshes. Python: the `remote_link` global.
    public private(set) var link: Link?
    private var destination: Destination?
    /// Python: the `first_remote_req` global — controls the "Sending request…" banner only.
    public private(set) var isFirstRequest: Bool = true

    private let lock = NSLock()

    public init(transport: Transport,
                destinationHash: Data,
                managementIdentity: Identity,
                timeout: TimeInterval = RNStatusApp.defaultRemoteTimeout) {
        self.transport = transport
        self.destinationHash = destinationHash
        self.managementIdentity = managementIdentity
        self.timeout = timeout
    }

    // MARK: - Destination derivation

    /// The `rnstransport.remote.management` destination hash for a transport identity hash.
    ///
    /// Python: `RNS.Destination.hash_from_name_and_identity("rnstransport.remote.management",
    /// identity_hash)` (rnstatus.py:319), where `Destination.hash` accepts raw 16-byte
    /// material in place of an `Identity` (Destination.py:122-127). That path is
    /// `SHA256(SHA256("rnstransport.remote.management")[:10] ‖ identity_hash)[:16]`.
    public static func destinationHash(forIdentityHash identityHash: Data) -> Data {
        let nameHash = Destination.computeNameHash(appName: RNStatusApp.remoteManagementAppName,
                                                   aspects: RNStatusApp.remoteManagementAspects)
        return Hashes.truncatedHash(nameHash + identityHash)
    }

    // MARK: - Path

    /// Python: rnstatus.py:70-82 — request a path if we have none and poll until it lands.
    ///
    /// DELIBERATE DIVERGENCE: Python's timeout message *and* its `exit(12)` both sit inside
    /// `if not no_output:`, so `rnstatus -j -R <unreachable>` spins forever. This always
    /// throws ``QueryError/noPath`` and lets the caller exit 12.
    ///
    /// Blocks. Never call this from a test — `Transport.awaitPath` sleeps on a real clock.
    public func ensurePath(progress: ((String) -> Void)? = nil) throws {
        if transport.hasPath(to: destinationHash) { return }
        progress?("Path to " + RNSUtilities.prettyhexrep(destinationHash) + " requested")
        try? transport.requestPath(for: destinationHash)

        let deadline = Date().timeIntervalSince1970 + timeout
        while !transport.hasPath(to: destinationHash) {
            Thread.sleep(forTimeInterval: 0.1)
            if Date().timeIntervalSince1970 > deadline { throw QueryError.noPath }
        }
    }

    // MARK: - Request

    /// Issue one `/status` request, establishing or reusing the link as needed.
    ///
    /// Python: rnstatus.py:121-153. The link-reuse fast path skips `identify`, exactly as
    /// Python does when `remote_link.status == ACTIVE`.
    public func request(includeLinkStats: Bool,
                        progress: ((String) -> Void)? = nil,
                        completion: @escaping (Swift.Result<(MsgPack.Value, Int?), QueryError>) -> Void) {

        // Python: `if not remote_destination: remote_destination = RNS.Destination(...)`.
        // The recall is what supplies the responder's public key; without it the OUT
        // SINGLE destination cannot be constructed and Python raises out of get_remote_status.
        if destination == nil {
            guard let remoteIdentity = transport.recall(identity: destinationHash) else {
                completion(.failure(.noRemoteIdentity)); return
            }
            destination = try? Destination(identity: remoteIdentity,
                                           direction: .out, kind: .single,
                                           appName: RNStatusApp.remoteManagementAppName,
                                           aspects: RNStatusApp.remoteManagementAspects)
            guard destination != nil else { completion(.failure(.noRemoteIdentity)); return }
        }

        lock.lock()
        let existing = link
        lock.unlock()

        if let existing, existing.status == .active {
            send(on: existing, includeLinkStats: includeLinkStats, completion: completion)
            return
        }

        progress?("Establishing link with remote transport instance...")
        guard let destination, let fresh = try? Link.initiate(destination: destination, transport: transport) else {
            completion(.failure(.linkClosedUnexpectedly)); return
        }
        lock.lock(); link = fresh; lock.unlock()

        fresh.onClosed = { [weak self] closed in
            // Python: INITIATOR_CLOSED returns silently; every other reason exits 10 —
            // and that exit is outside the no_output guards, so it fires under -j too.
            switch closed.teardownReason {
            case .initiatorClosed: return
            case .timeout:            completion(.failure(.linkTimedOut))
            case .destinationClosed:  completion(.failure(.linkClosedByServer))
            case .none:               completion(.failure(.linkClosedUnexpectedly))
            }
            _ = self
        }
        fresh.onEstablished = { [weak self] established in
            guard let self else { return }
            if self.isFirstRequest { progress?("Sending request...") }
            // Python does not wait for the identify to be acknowledged.
            try? established.identify(as: self.managementIdentity)
            self.send(on: established, includeLinkStats: includeLinkStats, completion: completion)
            self.isFirstRequest = false
        }
    }

    private func send(on link: Link,
                      includeLinkStats: Bool,
                      completion: @escaping (Swift.Result<(MsgPack.Value, Int?), QueryError>) -> Void) {
        // Python: `link.request("/status", data=[include_lstats], …)`. The payload is a
        // NATIVE msgpack array holding one boolean — the `data: Data?` overload would wrap
        // it as msgpack BIN and the Python responder's `isinstance(data, list)` would fail.
        do {
            try link.request(path: RNStatusApp.statusRequestPath,
                             nativeValue: .array([.bool(includeLinkStats)]),
                             responseCallback: { payload, _ in
                                 completion(Self.decode(payload))
                             },
                             failedCallback: { _, _ in
                                 completion(.failure(.requestFailed))
                             },
                             timeout: timeout)
        } catch {
            completion(.failure(.requestFailed))
        }
    }

    /// Decode `[stats_dict]` or `[stats_dict, link_count]`.
    ///
    /// Python: `got_response` (rnstatus.py:109-119).
    public static func decode(_ payload: Data) -> Swift.Result<(MsgPack.Value, Int?), QueryError> {
        guard let value = try? MsgPack.decode(payload),
              case .array(let parts) = value,
              let first = parts.first,
              RNStatusStats(first) != nil else {
            return .failure(.malformedResponse)
        }
        let linkCount = parts.count > 1 ? parts[1].asInt : nil
        return .success((first, linkCount))
    }

    // MARK: - Blocking convenience

    /// Blocking wrapper for the CLI. Python busy-waits on `request_concluded`.
    public func requestBlocking(includeLinkStats: Bool,
                                progress: ((String) -> Void)? = nil) throws -> (MsgPack.Value, Int?) {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Swift.Result<(MsgPack.Value, Int?), QueryError>?
        var signalled = false
        let guardLock = NSLock()

        request(includeLinkStats: includeLinkStats, progress: progress) { result in
            guardLock.lock()
            defer { guardLock.unlock() }
            guard !signalled else { return }   // onClosed can fire after a delivered response
            signalled = true
            outcome = result
            semaphore.signal()
        }

        // Guard against a responder that never answers: Python relies on the link
        // watchdog, which also fires here, but the extra margin keeps monitor mode alive.
        if semaphore.wait(timeout: .now() + timeout + Link.establishmentTimeoutPerHop) == .timedOut {
            throw QueryError.linkTimedOut
        }
        switch outcome {
        case .success(let value): return value
        case .failure(let error): throw error
        case .none:               throw QueryError.requestFailed
        }
    }

    /// Close the reused link. Python never does this explicitly — the process exits.
    public func teardown() {
        lock.lock(); let current = link; link = nil; lock.unlock()
        try? current?.teardown()
    }
}
