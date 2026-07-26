import Foundation

/// Errors surfaced while saving a received resource.
/// Python has no error type — each failure is a log line or a `print` — so the cases here
/// map one-to-one onto the messages in rncp.py:281-313 / 490-521.
public enum RNCopyError: Swift.Error, Equatable {
    /// `resource.metadata == None` → "Invalid data received, ignoring resource".
    case missingMetadata
    /// The resolved target escaped `--save` → "Invalid save path <path>, ignoring".
    case invalidSavePath(String)
    /// Any exception in the save block → "An error occurred while saving received resource: <e>".
    case writeFailed(String)
    /// `-O` was requested but the unlink threw → "Could not overwrite existing file <path>, renaming instead".
    /// Informational: Python falls through to the rename counter, and so do we.
    case overwriteFailed(String)

    /// The trailing text Python interpolates into
    /// "An error occurred while saving received resource: <e>".
    public var exceptionText: String {
        switch self {
        case .missingMetadata:          return "'name'"
        case .invalidSavePath(let p):   return p
        case .writeFailed(let m):       return m
        case .overwriteFailed(let p):   return p
        }
    }
}

public extension RNCopyApp {

    /// Write a completed inbound resource to disk, shared by the listener and the fetcher.
    ///
    /// Python duplicates this block verbatim in `receive_resource_concluded` (rncp.py:287-313)
    /// and `fetch_resource_concluded` (rncp.py:496-521); the only difference is that the
    /// listener logs while the fetcher `print`s, which is the caller's concern.
    ///
    /// Python moves the RNS temp file with `shutil.move(resource.data.name, …)`; Swift
    /// receives the plaintext as in-memory `Data`, so this writes it instead. Everything else
    /// — basename collapsing, `--save` containment, the `-O` unlink, the `.1`/`.2` rename
    /// counter — matches exactly.
    static func saveReceivedResource(payload: Data,
                                     metadata: Data?,
                                     savePath: String?,
                                     allowOverwrite: Bool,
                                     fileSystem: RNCopyFileSystem,
                                     onOverwriteFailure: ((String) -> Void)? = nil)
    -> Swift.Result<String, RNCopyError> {
        guard let metadata else { return .failure(.missingMetadata) }
        // Python raises KeyError('name') here, and the outer except reports it as
        // "An error occurred while saving received resource: 'name'".
        guard let name = decodeMetadataName(metadata) else {
            return .failure(.writeFailed("'name'"))
        }

        // Python: os.path.basename(...) — collapses a hostile "../../etc/passwd" to "passwd".
        let filename = basename(name)
        let resolution = resolveSaveTarget(filename: filename,
                                           savePath: savePath,
                                           allowOverwrite: allowOverwrite,
                                           fileSystem: fileSystem,
                                           onOverwriteFailure: onOverwriteFailure)

        switch resolution {
        case .rejected(let path):
            return .failure(.invalidSavePath(path))
        case .write(let path, _):
            do {
                try fileSystem.writeFile(payload, toPath: path)
                return .success(path)
            } catch {
                return .failure(.writeFailed("\(error)"))
            }
        }
    }
}

/// The receiving half of `rncp` — Python's `listen()` plus the module-level
/// `client_link_established` / `receive_sender_identified` / `receive_resource_*`
/// callbacks and the `fetch_request` handler (rncp.py:75-232, 234-316).
///
/// Everything that touches a terminal stays in `Sources/rncp/main.swift`; this type logs
/// through ``Reticulum/log(_:level:)`` exactly as Python logs through `RNS.log`, and also
/// publishes typed events so XCTest can assert without a console.
///
/// ## Deliberate parity quirks
///
/// * The fetch handler is registered **only** when `-F/--allow-fetch` is set. Python's
///   `if not allow_fetch: return REQ_FETCH_NOT_ALLOWED` opener (rncp.py:174) is dead code
///   for exactly that reason, so the only live emitter of `0xF0` is the jail-escape check.
///   A client fetching from a listener without `-F` gets *no response at all* and times
///   out into `unknown`.
/// * Path containment (both the fetch jail and `--save`) is lexical, never symlink
///   resolving — see ``RNCopyApp/absolutePath(_:cwd:)``.
/// * Python's allow-list gate uses `ALLOW_LIST`, which silently sends nothing when the
///   caller is not on the list. Swift's `Destination.registerNativeRequestHandler` takes
///   `[Identity]` and rncp only ever has bare hashes, so the handler is registered with
///   `.all` and the identity gate runs inside ``serveFetchRequest(requested:link:)``,
///   returning `nil` (= no response) on denial. Behaviourally and on the wire this is
///   identical to `ALLOW_LIST`.
public final class RNCopyListener {

    // MARK: - Configuration

    public struct Configuration {
        /// The identity the `rncp.receive` destination is built on.
        public var identity: Identity
        /// 16-byte IDENTITY hashes permitted to send/fetch. Python: `allowed_identity_hashes`.
        public var allowedIdentityHashes: Set<Data>
        /// `-n/--no-auth`. Python: `allow_all`.
        public var allowAll: Bool
        /// `-F/--allow-fetch`. Python: `allow_fetch`.
        public var allowFetch: Bool
        /// `not -C`. Python: `fetch_auto_compress`.
        public var fetchAutoCompress: Bool
        /// `-O/--overwrite`. Python: `allow_overwrite_on_receive`.
        public var allowOverwriteOnReceive: Bool
        /// `-j/--jail`, already absolutised. Python: `fetch_jail`.
        public var fetchJail: String?
        /// `-s/--save`, already absolutised and validated. Python: `save_path`.
        public var savePath: String?

        public init(identity: Identity,
                    allowedIdentityHashes: Set<Data> = [],
                    allowAll: Bool = false,
                    allowFetch: Bool = false,
                    fetchAutoCompress: Bool = true,
                    allowOverwriteOnReceive: Bool = false,
                    fetchJail: String? = nil,
                    savePath: String? = nil) {
            self.identity = identity
            self.allowedIdentityHashes = allowedIdentityHashes
            self.allowAll = allowAll
            self.allowFetch = allowFetch
            self.fetchAutoCompress = fetchAutoCompress
            self.allowOverwriteOnReceive = allowOverwriteOnReceive
            self.fetchJail = fetchJail
            self.savePath = savePath
        }
    }

    // MARK: - State

    /// `RNS.Destination(identity, IN, SINGLE, "rncp", "receive")`. Python: rncp.py:112.
    public let destination: Destination

    public var configuration: Configuration

    private let transport: Transport
    private let fileSystem: RNCopyFileSystem

    /// Guards the small amount of cross-thread bookkeeping below. Resource callbacks fire
    /// on the Link receive thread and on the ResourceTransfer watchdog queue.
    private let stateLock = NSLock()
    /// Transfers accepted but not yet concluded, so the conclusion callback (which is only
    /// handed the advertisement) can recover `receivedMetadata`.
    private var activeTransfers: [ResourceTransfer] = []
    /// The advertisement most recently accepted by ``acceptResource(advertisement:link:)``.
    /// `Link.acceptIncomingResource` fires `onResourceStarted` *before*
    /// `receiveAdvertisement`, so the transfer's own `resourceHash` is still empty at that
    /// instant; this is where the hash for the "Starting resource transfer" line comes from.
    private var lastAcceptedAdvertisement: ResourceAdvertisement?

    // MARK: - Observable events (for tests and embedders)

    /// Fires with the full path each time a received file lands on disk.
    public var onSavedFile: ((String) -> Void)?
    /// `(resourceHash, senderIdentity)` when an inbound transfer starts.
    public var onTransferStarted: ((Data, Identity?) -> Void)?
    /// `(completed, resourceHash, linkID)` when an inbound transfer ends.
    public var onTransferConcluded: ((Bool, Data, Data) -> Void)?
    /// Fires when a sender that is not on the allow-list has its link torn down.
    public var onSenderRejected: ((Identity) -> Void)?

    // MARK: - Init

    public init(transport: Transport,
                fileSystem: RNCopyFileSystem = RNCopyDiskFileSystem(),
                configuration: Configuration) throws {
        self.transport = transport
        self.fileSystem = fileSystem
        self.configuration = configuration
        self.destination = try Destination(identity: configuration.identity,
                                           direction: .in,
                                           kind: .single,
                                           appName: RNCopyApp.appName,
                                           aspects: [RNCopyApp.receiveAspect])
    }

    // MARK: - Lifecycle

    /// Register the destination and wire every callback. Python: rncp.py:212-220.
    public func start() {
        transport.register(destination: destination)
        destination.setLinkEstablishedCallback { [weak self] link in
            self?.handleLinkEstablished(link)
        }

        if configuration.allowFetch {
            if configuration.allowAll {
                Reticulum.log("Allowing unauthenticated fetch requests", level: .warning)
            }
            // See the type doc: `.all` here, with the ALLOW_LIST gate inside the handler.
            destination.registerNativeRequestHandler(
                path: RNCopyApp.fetchRequestPath,
                allow: .all,
                autoCompress: configuration.fetchAutoCompress
            ) { [weak self] _, requestData, _, link, _ in
                guard let self else { return nil }
                // Python's request data is a str, and `fetch_request` calls
                // `data.startswith(...)` on it — anything else is a remote-side error.
                guard let requested = requestData.asString else { return nil }
                return self.serveFetchRequest(requested: requested, link: link)
            }
        }

        Reticulum.log("rncp listening on " + RNSUtilities.prettyhexrep(destination.hash), level: .info)
    }

    public func stop() {
        destination.deregisterRequestHandler(path: RNCopyApp.fetchRequestPath)
        transport.deregister(destination: destination)
    }

    /// Announce the listening destination.
    ///
    /// **Upstream quirk, reproduced deliberately.** `-b` defaults to `-1`; `listen()` then
    /// does `if announce < 0: announce = False`, and the following gate `if announce >= 0:`
    /// evaluates `False >= 0` → **True** in Python. So rncp always emits one announce at
    /// listener startup even with the default that the help text implies means "never"
    /// (rncp.py:86-87, 222-230). The CLI mirrors that: announce once unconditionally, then
    /// repeat every `-b N` seconds when `N > 0`.
    @discardableResult
    public func announce() throws -> PacketReceipt? {
        try transport.announce(destination: destination)
    }

    // MARK: - Link callbacks

    /// Python: `client_link_established` (rncp.py:234-240).
    public func handleLinkEstablished(_ link: Link) {
        Reticulum.log("Incoming link established", level: .verbose)
        link.onRemoteIdentified = { [weak self] link, identity in
            self?.handleRemoteIdentified(link, identity: identity)
        }
        // Swift's default is `.acceptNone`, which actively replies RESOURCE_RCL — this
        // assignment is mandatory, not cosmetic.
        link.resourceStrategy = .acceptApp
        link.onResourceAdvertised = { [weak self] advertisement, link in
            self?.acceptResource(advertisement: advertisement, from: link) ?? false
        }
        link.onResourceStarted = { [weak self] transfer in
            self?.handleResourceStarted(transfer)
        }
        link.onResourceConcluded = { [weak self] payload, advertisement, link in
            self?.handleResourceConcluded(payload: payload, advertisement: advertisement, link: link)
        }
    }

    /// Python: `receive_sender_identified` (rncp.py:242-252).
    public func handleRemoteIdentified(_ link: Link, identity: Identity) {
        if configuration.allowedIdentityHashes.contains(identity.hash) {
            Reticulum.log("Authenticated sender", level: .verbose)
        } else if !configuration.allowAll {
            Reticulum.log("Sender not allowed, tearing down link", level: .verbose)
            try? link.teardown()
            onSenderRejected?(identity)
        }
        // allow_all → Python's explicit `pass`.
    }

    /// The `ACCEPT_APP` decision. Python: `receive_resource_callback` (rncp.py:254-266).
    /// Returning false makes RNS reject the resource with RESOURCE_RCL.
    public func acceptResource(from link: Link) -> Bool {
        if let senderIdentity = link.getRemoteIdentity(),
           configuration.allowedIdentityHashes.contains(senderIdentity.hash) {
            return true
        }
        return configuration.allowAll
    }

    private func acceptResource(advertisement: ResourceAdvertisement, from link: Link) -> Bool {
        let accepted = acceptResource(from: link)
        if accepted {
            stateLock.lock(); lastAcceptedAdvertisement = advertisement; stateLock.unlock()
        }
        return accepted
    }

    /// Python: `receive_resource_started` (rncp.py:268-274).
    private func handleResourceStarted(_ transfer: ResourceTransfer) {
        stateLock.lock()
        activeTransfers.append(transfer)
        let advertisement = lastAcceptedAdvertisement
        stateLock.unlock()

        let resourceHash = advertisement?.resourceHash ?? transfer.resourceHash
        let remoteIdentity = transfer.link.getRemoteIdentity()
        // Python: id_str = " from "+prettyhexrep(identity.hash) when the peer identified.
        let idString = remoteIdentity.map { " from " + RNSUtilities.prettyhexrep($0.hash) } ?? ""
        Reticulum.log("Starting resource transfer " + RNSUtilities.prettyhexrep(resourceHash) + idString,
                      level: .info)
        onTransferStarted?(resourceHash, remoteIdentity)

        // Python's receive_resource_concluded also runs on failure; Link only routes the
        // success path through onResourceConcluded, so the failure branch is hooked here.
        transfer.onFailed = { [weak self] failed, _ in
            guard let self else { return }
            // Python: RNS.log("Resource failed", RNS.LOG_INFO)
            Reticulum.log("Resource failed", level: .info)
            self.forget(failed)
            self.onTransferConcluded?(false, failed.resourceHash, failed.link.linkID ?? Data())
        }
    }

    /// Python: `receive_resource_concluded`, COMPLETE branch (rncp.py:276-313).
    private func handleResourceConcluded(payload: Data,
                                         advertisement: ResourceAdvertisement,
                                         link: Link) {
        stateLock.lock()
        let transfer = activeTransfers.first { $0.resourceHash == advertisement.resourceHash }
        stateLock.unlock()

        // Python: RNS.log(f"Incoming resource {resource} completed") where str(resource) is
        // "<" + resource_hash hex + "/" + link_id hex + ">".
        let linkID = link.linkID ?? Data()
        Reticulum.log("Incoming resource <\(advertisement.resourceHash.hexString)/\(linkID.hexString)> completed",
                      level: .info)

        switch saveReceivedResource(payload: payload, metadata: transfer?.receivedMetadata) {
        case .success(let path):
            // Python: RNS.log("Saved received file to "+full_save_path, RNS.LOG_NOTICE)
            Reticulum.log("Saved received file to " + path, level: .notice)
            onSavedFile?(path)
        case .failure(let error):
            switch error {
            case .missingMetadata:
                Reticulum.log("Invalid data received, ignoring resource", level: .warning)
            case .invalidSavePath(let path):
                Reticulum.log("Invalid save path \(path), ignoring", level: .error)
            case .writeFailed, .overwriteFailed:
                Reticulum.log("An error occurred while saving received resource: \(error.exceptionText)",
                              level: .error)
            }
        }

        if let transfer { forget(transfer) }
        onTransferConcluded?(true, advertisement.resourceHash, linkID)
    }

    private func forget(_ transfer: ResourceTransfer) {
        stateLock.lock()
        activeTransfers.removeAll { $0 === transfer }
        stateLock.unlock()
    }

    // MARK: - Saving

    /// Write a completed inbound resource to disk.
    ///
    /// Python moves the RNS temp file with `shutil.move(resource.data.name, …)`; Swift
    /// receives the plaintext as in-memory `Data`, so this writes it instead. Everything
    /// else — basename collapsing, `--save` containment, `-O` unlink, the `.1`/`.2` rename
    /// counter — matches rncp.py:287-309 exactly.
    public func saveReceivedResource(payload: Data, metadata: Data?) -> Swift.Result<String, RNCopyError> {
        RNCopyApp.saveReceivedResource(
            payload: payload,
            metadata: metadata,
            savePath: configuration.savePath,
            allowOverwrite: configuration.allowOverwriteOnReceive,
            fileSystem: fileSystem,
            onOverwriteFailure: { path in
                // Python logs this and then falls through to the rename counter.
                Reticulum.log("Could not overwrite existing file \(path), renaming instead",
                              level: .error)
            }
        )
    }

    // MARK: - Fetch handler

    /// Serve a `fetch_file` request. Python: `fetch_request` (rncp.py:172-209).
    ///
    /// Returns the scalar that goes into the response envelope
    /// `msgpack([request_id, <value>])`, or `nil` to send no response at all — which is
    /// what Python's `ALLOW_LIST` denial and its `target_link == None` branch both do.
    ///
    /// The file itself is advertised as an **ordinary** resource on the link (not a
    /// response resource, no request id), so the RESOURCE_ADV goes out *before* the scalar
    /// response packet — same ordering as Python.
    public func serveFetchRequest(requested: String, link: Link) -> MsgPack.Value? {
        // Python's ALLOW_LIST gate, relocated into the handler (see the type doc).
        if !configuration.allowAll {
            guard let remoteHash = link.getRemoteIdentity()?.hash,
                  configuration.allowedIdentityHashes.contains(remoteHash) else { return nil }
        }

        switch RNCopyApp.resolveFetchPath(requested: requested,
                                          jail: configuration.fetchJail,
                                          fileSystem: fileSystem) {
        case .notAllowed(let path):
            Reticulum.log("Disallowing fetch request for \(path) outside of fetch jail \(configuration.fetchJail ?? "")",
                          level: .warning)
            return .uint(UInt64(RNCopyApp.reqFetchNotAllowed))

        case .notFound(let path):
            Reticulum.log("Client-requested file not found: \(path)", level: .verbose)
            return .bool(false)

        case .serve(let path):
            Reticulum.log("Sending file \(path) to client", level: .verbose)
            do {
                let payload = try fileSystem.readFile(atPath: path)
                let transfer = ResourceTransfer(link: link)
                try transfer.send(payload: payload,
                                  metadata: RNCopyApp.encodeMetadata(name: RNCopyApp.basename(path)),
                                  autoCompress: configuration.fetchAutoCompress)
                return .bool(true)
            } catch {
                Reticulum.log("Could not send file to client. The contained exception was: \(error)",
                              level: .error)
                return .bool(false)
            }
        }
    }
}
