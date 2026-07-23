import Foundation

/// The `rnx <destination> <command>` half, as a non-blocking state machine.
///
/// Python reference: `RNS/Utilities/rnx.py:326-397` (`execute`, up to the point the
/// request is sent).
///
/// Every wait Python performs is a `spin()` loop that redraws a braille spinner every
/// 100 ms, so nothing here may block: the client exposes predicates and one-shot actions,
/// and the executable owns the loop. In particular this never calls
/// `Transport.awaitPath` or `Destination.awaitPath`, both of which `Thread.sleep`-poll.
public final class RNXClient {

    public enum ClientError: Error, Equatable {
        /// Python: "Allowed destination length is invalid, must be 32 hexadecimal
        /// characters (16 bytes)." → exit 241 (rnx.py:332).
        case invalidDestinationLength(Int)
        /// Python: "Invalid destination entered. Check your input." → exit 241 (rnx.py:336).
        case invalidDestinationHex
        /// `Identity.recall` returned nil. Python does not check, and silently builds a
        /// destination with the wrong hash; Swift's `Destination` init throws, which the
        /// executable maps onto the same exit as "Could not establish link" (243).
        case unknownListenerIdentity
        case linkNotActive
        case linkClosed
    }

    /// 16-byte listener destination hash.
    public let destinationHash: Data

    /// Python: the `link` module global — reused across an interactive session.
    public private(set) var link: Link?

    /// Python: `link.did_identify`, an ad-hoc attribute stapled onto the Link object.
    public private(set) var didIdentify: Bool = false

    /// Python: the `listener_destination` module global. Never rebuilt once set, so a
    /// failed first recall poisons the whole interactive session — reproduced.
    public private(set) var listenerDestination: Destination?

    private let transport: Transport
    private let identity: Identity

    public init(transport: Transport, identity: Identity, destinationHash: Data) {
        self.transport = transport
        self.identity = identity
        self.destinationHash = destinationHash
    }

    /// Python: rnx.py:329-339. The check is unconditional — it fires even under `-x`, and
    /// it runs *before* Reticulum is constructed, so an invalid destination never brings
    /// up the stack.
    public static func parseDestination(_ hex: String) throws -> Data {
        guard hex.count == RNXApp.destinationHexLength else {
            throw ClientError.invalidDestinationLength(hex.count)
        }
        guard let bytes = RNXHex.decode(hex) else {
            throw ClientError.invalidDestinationHex
        }
        return bytes
    }

    // MARK: - Path

    /// Python: `RNS.Transport.has_path(destination_hash)` — rnx.py:348.
    public var hasPath: Bool { transport.hasPath(to: destinationHash) }

    /// Python: `RNS.Transport.request_path(destination_hash)` — rnx.py:349. Fire and forget.
    public func requestPath() throws {
        try transport.requestPath(for: destinationHash)
    }

    // MARK: - Link

    /// Python: rnx.py:354-366.
    ///
    /// Builds the OUT destination once (recalling the listener identity through the
    /// injected transport, not `Identity.recall`, which routes via `Reticulum.shared` and
    /// silently returns nil when no stack was started), then creates a Link whenever the
    /// current one is nil, CLOSED or PENDING. ACTIVE / HANDSHAKE / STALE links are reused
    /// — including a STALE one that may well fail on the next send. Reproduced verbatim.
    public func openLinkIfNeeded() throws {
        if listenerDestination == nil {
            guard let listenerIdentity = transport.recall(identity: destinationHash) else {
                throw ClientError.unknownListenerIdentity
            }
            listenerDestination = try Destination(identity: listenerIdentity,
                                                  direction: .out,
                                                  kind: .single,
                                                  appName: RNXApp.appName,
                                                  aspects: [RNXApp.aspect])
        }
        guard let listenerDestination else { throw ClientError.unknownListenerIdentity }

        let status = link?.status
        if link == nil || status == .closed || status == .pending {
            // Link.initiate registers itself with the transport, so no separate
            // transport.register(link:) is needed.
            link = try Link.initiate(destination: listenerDestination, transport: transport)
            didIdentify = false
        }
    }

    public var linkStatus: Link.Status? { link?.status }

    /// Python: rnx.py:372-374 — skipped entirely under `-N/--noid`. Without identifying,
    /// an ALLOW_LIST listener silently ignores the request and the client times out at 245.
    public func identifyIfNeeded(noID: Bool) throws {
        guard !noID, !didIdentify, let link else { return }
        try link.identify(as: identity)
        didIdentify = true
    }

    // MARK: - Request

    /// Python: rnx.py:390-397.
    ///
    /// Uses `link.request(path:nativeValue:)`. The `data:` overload wraps the payload as
    /// msgpack `.bytes`, so a Python listener would index a bytes object, get an `int`,
    /// call `.decode` on it and raise inside its response generator — sending no response
    /// at all, which looks exactly like a network timeout.
    @discardableResult
    public func sendCommand(_ request: RNXRequest,
                            timeout: TimeInterval,
                            progressCallback: ((Double, RequestReceipt) -> Void)? = nil) throws -> RequestReceipt {
        guard let link else { throw ClientError.linkNotActive }
        return try link.request(path: RNXApp.requestPath,
                                nativeValue: request.packedValue(),
                                responseCallback: nil,     // Python's remote_execution_done is a no-op
                                failedCallback: nil,       // both callbacks point at the same no-op
                                progressCallback: progressCallback,
                                timeout: timeout)
    }

    /// Python: rnx.py:532-537 — exceptions are swallowed, and it is skipped in interactive mode.
    public func teardown() {
        try? link?.teardown()
    }

    /// Python: `rexec_timeout = timeout + link.rtt*4 + remote_exec_grace` — rnx.py:388.
    ///
    /// Must always be passed explicitly to `Link.request(timeout:)`: Swift otherwise
    /// substitutes `rtt * Link.trafficTimeoutFactor (6) + Link.requestTimeoutGrace`, or
    /// **no timeout at all** when the RTT is still nil.
    public static func rexecTimeout(commandTimeout: TimeInterval, rtt: TimeInterval?) -> TimeInterval {
        commandTimeout + (rtt ?? 0) * RNXApp.rexecRttFactor + RNXApp.remoteExecGrace
    }

    // MARK: - Status predicates

    // Python's RequestReceipt statuses are plain ints (Link.py:1289-1294) so `status !=
    // RECEIVING` is a scalar compare; ReticulumSwift's carry associated values, so each
    // spin predicate has to pattern-match.

    public static func isSent(_ status: RequestReceipt.Status) -> Bool {
        if case .sent = status { return true }
        return false
    }

    public static func isDelivered(_ status: RequestReceipt.Status) -> Bool {
        if case .delivered = status { return true }
        return false
    }

    public static func isReceiving(_ status: RequestReceipt.Status) -> Bool {
        if case .receiving = status { return true }
        return false
    }

    public static func isFailed(_ status: RequestReceipt.Status) -> Bool {
        if case .failed = status { return true }
        return false
    }
}
