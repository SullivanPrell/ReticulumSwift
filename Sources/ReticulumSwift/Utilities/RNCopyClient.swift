import Foundation

// MARK: - Shared client vocabulary

/// The stages a client passes through, in the order rncp prints them.
public enum RNCopyStage: Equatable {
    /// "Path to <hash> requested". Python: rncp.py:397-399 / 652-654.
    case requestingPath(Data)
    /// "Establishing link with <hash>". Python: rncp.py:420-422 / 675-677.
    case establishingLink(Data)
    /// send: "Advertising file resource...". Python: rncp.py:710-712.
    case advertising
    /// send: "Transferring file". Python: rncp.py:741-743.
    case transferring
    /// fetch: "Requesting file from remote...". Python: rncp.py:449-451.
    case requestingFile
    /// fetch: "Waiting for transfer to start". Python: rncp.py:593.
    case waitingForTransfer
}

/// One sample of the progress display.
public struct RNCopyProgress: Equatable {
    /// `resource.get_progress()`, 0…1.
    public let fraction: Double
    /// `int(prg * total_size)`.
    public let transferredBytes: Int
    /// `resource.total_size`.
    public let totalBytes: Int
    /// Application-layer bytes/second over the rolling window.
    public let speed: Double
    /// Physical-layer bytes/second over the rolling window (`-P`).
    public let phySpeed: Double
    /// True on the terminal sample, which renders "Transfer complete".
    public let done: Bool
    /// Wall-clock transfer duration, set only on the terminal fetch-mode sample — that is
    /// the one line that inserts " in <prettytime>" (rncp.py:590).
    public let elapsed: TimeInterval?

    public init(fraction: Double, transferredBytes: Int, totalBytes: Int,
                speed: Double, phySpeed: Double, done: Bool, elapsed: TimeInterval? = nil) {
        self.fraction = fraction
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.speed = speed
        self.phySpeed = phySpeed
        self.done = done
        self.elapsed = elapsed
    }
}

// MARK: - Resource status ordinal mapping

/// Python's `RNS.Resource` status ordinals are compared with `<` and `>` throughout rncp
/// (rncp.py:353, 724, 733, 779). Swift's `ResourceTransfer.Status` is a non-ordinal enum,
/// so the three comparisons rncp actually performs are spelled out here.
///
/// Python ordinals: NONE 0, QUEUED 1, ADVERTISED 2, TRANSFERRING 3, AWAITING_PROOF 4,
/// ASSEMBLING 5, COMPLETE 6, FAILED 7, CORRUPT 8.
enum RNCopyResourceStatus {
    /// `status < RNS.Resource.TRANSFERRING`
    static func isBelowTransferring(_ status: ResourceTransfer.Status) -> Bool {
        switch status {
        case .idle, .advertised: return true
        default:                 return false
        }
    }

    /// `status > RNS.Resource.COMPLETE` — FAILED or CORRUPT.
    static func isAboveComplete(_ status: ResourceTransfer.Status) -> Bool {
        switch status {
        case .failed, .rejected: return true
        default:                 return false
        }
    }

    /// `status >= RNS.Resource.COMPLETE`
    static func isAtLeastComplete(_ status: ResourceTransfer.Status) -> Bool {
        switch status {
        case .complete, .failed, .rejected: return true
        default:                            return false
        }
    }
}

// MARK: - Link opener

/// The path-request → wait → `Link.initiate` → wait sequence shared by both client modes,
/// bounded by the single `estab_timeout` deadline Python captures once and reuses for both
/// waits (rncp.py:404 / 659).
///
/// Python's silent mode gates the `time.sleep(0.1)` behind `if not silent`, producing a hot
/// CPU spin. This implementation always sleeps and only suppresses output — a deliberate,
/// documented divergence that changes nothing observable.
final class RNCopyLinkOpener {

    enum Outcome {
        /// No path before the deadline. Python: "Path not found", exit 1.
        case pathNotFound
        /// A path exists but no identity was recalled, so an OUT destination cannot be
        /// built. Python raises an unhandled exception inside `Destination.__init__` here.
        case identityUnknown
        /// `Link.initiate` threw.
        case failed(String)
        /// A link object exists; the caller applies its own post-wait check, because
        /// `fetch()` tests `has_path` while `send()` tests the clock first.
        case opened(link: Link, deadlineExpired: Bool, hasPath: Bool)
    }

    private let transport: Transport
    private let destinationHash: Data
    private let timeout: TimeInterval
    private let tick: TimeInterval

    init(transport: Transport, destinationHash: Data,
         timeout: TimeInterval, tick: TimeInterval = 0.1) {
        self.transport = transport
        self.destinationHash = destinationHash
        self.timeout = timeout
        self.tick = tick
    }

    func open(onStage: ((RNCopyStage) -> Void)?, onTick: (() -> Void)?) -> Outcome {
        if !transport.hasPath(to: destinationHash) {
            try? transport.requestPath(for: destinationHash)
            onStage?(.requestingPath(destinationHash))
        }

        // Python captures estab_timeout AFTER the "Path to … requested" print and lets it
        // cover BOTH the path wait and the link wait.
        let deadline = Date().timeIntervalSince1970 + timeout
        while !transport.hasPath(to: destinationHash), Date().timeIntervalSince1970 < deadline {
            Thread.sleep(forTimeInterval: tick)
            onTick?()
        }
        guard transport.hasPath(to: destinationHash) else { return .pathNotFound }

        onStage?(.establishingLink(destinationHash))

        guard let listenerIdentity = transport.recall(identity: destinationHash) else {
            return .identityUnknown
        }

        do {
            let listenerDestination = try Destination(identity: listenerIdentity,
                                                      direction: .out,
                                                      kind: .single,
                                                      appName: RNCopyApp.appName,
                                                      aspects: [RNCopyApp.receiveAspect])
            let link = try Link.initiate(destination: listenerDestination, transport: transport)
            while link.status != .active, Date().timeIntervalSince1970 < deadline {
                Thread.sleep(forTimeInterval: tick)
                onTick?()
            }
            return .opened(link: link,
                           deadlineExpired: Date().timeIntervalSince1970 > deadline,
                           hasPath: transport.hasPath(to: destinationHash))
        } catch {
            return .failed("\(error)")
        }
    }
}

// MARK: - Sender

/// The sending half of `rncp` — Python's `send()` (rncp.py:617-792).
///
/// `run()` blocks until the transfer concludes and returns a typed outcome; all terminal
/// rendering happens in `Sources/rncp/main.swift` off the ``onStage``/``onProgress``
/// closures.
public final class RNCopySender {

    public typealias Stage = RNCopyStage
    public typealias Progress = RNCopyProgress

    public struct Configuration {
        public var identity: Identity
        public var destinationHash: Data
        /// The local path, exactly as typed. Python applies `expanduser` but **not**
        /// `abspath` (rncp.py:635), and prints this expanded form in the success line.
        public var filePath: String
        /// `-w seconds`, default `RNS.Transport.PATH_REQUEST_TIMEOUT` = 15.
        public var timeout: TimeInterval
        /// `not -C/--no-compress`.
        public var autoCompress: Bool

        public init(identity: Identity,
                    destinationHash: Data,
                    filePath: String,
                    timeout: TimeInterval = Transport.pathRequestTimeout,
                    autoCompress: Bool = true) {
            self.identity = identity
            self.destinationHash = destinationHash
            self.filePath = filePath
            self.timeout = timeout
            self.autoCompress = autoCompress
        }
    }

    public enum Outcome: Equatable {
        case completed(bytes: Int, duration: TimeInterval)
        /// "File not found", exit 1. Python: rncp.py:636-638 — checked before Reticulum starts.
        case fileNotFound
        /// "Path not found", exit 1. Python: rncp.py:667-672.
        case pathNotFound
        /// "Link establishment with <hash> timed out", exit 1. Python: rncp.py:696-701.
        case linkTimedOut
        /// "No path found to <hash>", exit 1. Python: rncp.py:702-707.
        case noPathFound
        /// A path exists but no identity is known for it; Python would raise here.
        case identityUnknown
        /// "File was not accepted by <hash>", exit 1 — the receiver replied RESOURCE_RCL.
        case notAccepted
        /// "The transfer failed", exit 1. Python: rncp.py:779-784.
        case transferFailed
        /// "Could not start transfer: <e>", exit 1. Python: rncp.py:718-720.
        case startFailed(String)
    }

    public var onStage: ((Stage) -> Void)?
    public var onProgress: ((Progress) -> Void)?
    /// Fires once per 0.1 s poll during a wait that has nothing else to show, so the CLI can
    /// advance the Braille spinner (`print("\b\b"+syms[i]+" ")`, rncp.py:663,692,727).
    public var onTick: (() -> Void)?

    /// The expanded local path, available after `run()` starts. Python prints this — not the
    /// raw argument — in the success line (rncp.py:787,789).
    public private(set) var expandedFilePath: String = ""

    private let transport: Transport
    private let fileSystem: RNCopyFileSystem
    private let configuration: Configuration
    private let tick: TimeInterval

    private let stateLock = NSLock()
    private var link: Link?
    private var transfer: ResourceTransfer?

    public init(transport: Transport,
                fileSystem: RNCopyFileSystem = RNCopyDiskFileSystem(),
                configuration: Configuration,
                tick: TimeInterval = 0.1) {
        self.transport = transport
        self.fileSystem = fileSystem
        self.configuration = configuration
        self.tick = tick
    }

    /// Cancel an in-flight transfer and tear the link down.
    ///
    /// Python's `KeyboardInterrupt` handler intends exactly this but references an
    /// undefined `resource` name and raises `NameError` (rncp.py:879-885); the intended
    /// behaviour is implemented here.
    public func cancel() {
        stateLock.lock(); let t = transfer; let l = link; stateLock.unlock()
        t?.cancel()
        try? l?.teardown()
    }

    /// Tear the link down, mirroring Python's `link.teardown()` before `RNS.exit(0)`
    /// (rncp.py:790).
    public func teardown() {
        stateLock.lock(); let l = link; stateLock.unlock()
        try? l?.teardown()
    }

    public func run() -> Outcome {
        // Python: file_path = os.path.expanduser(file) — no abspath.
        let filePath = RNCopyApp.expandUser(configuration.filePath, home: fileSystem.homeDirectoryPath)
        expandedFilePath = filePath
        guard fileSystem.fileExists(atPath: filePath) else { return .fileNotFound }

        let payload: Data
        do { payload = try fileSystem.readFile(atPath: filePath) }
        catch { return .startFailed("\(error)") }

        // Python: metadata = {"name": os.path.basename(file_path).encode("utf-8")}
        let metadata = RNCopyApp.encodeMetadata(name: RNCopyApp.basename(filePath))

        let opener = RNCopyLinkOpener(transport: transport,
                                      destinationHash: configuration.destinationHash,
                                      timeout: configuration.timeout,
                                      tick: tick)
        let link: Link
        switch opener.open(onStage: onStage, onTick: onTick) {
        case .pathNotFound:            return .pathNotFound
        case .identityUnknown:         return .identityUnknown
        case .failed(let message):     return .startFailed(message)
        case .opened(let opened, let deadlineExpired, let hasPath):
            stateLock.lock(); self.link = opened; stateLock.unlock()
            // Python checks the clock FIRST, then the path — the two produce different
            // messages and both exit 1 (rncp.py:696-707).
            if deadlineExpired { return .linkTimedOut }
            if !hasPath        { return .noPathFound }
            link = opened
        }

        onStage?(.advertising)

        do { try link.identify(as: configuration.identity) }
        catch { return .linkTimedOut }

        let transfer = ResourceTransfer(link: link)
        stateLock.lock(); self.transfer = transfer; stateLock.unlock()
        do {
            try transfer.send(payload: payload, metadata: metadata,
                              autoCompress: configuration.autoCompress)
        } catch {
            // Python: print(f"Could not start transfer: {e}"). A zero-byte file lands here
            // in both implementations (Swift: ResourceTransfer.Error.payloadEmpty;
            // Python: bz2.compress on a file handle).
            return .startFailed("\(error)")
        }

        // Python: while resource.status < RNS.Resource.TRANSFERRING
        while RNCopyResourceStatus.isBelowTransferring(transfer.status) {
            Thread.sleep(forTimeInterval: tick)
            onTick?()
        }
        let startedAt = Date()

        // Python: if resource.status > RNS.Resource.COMPLETE → not accepted.
        if RNCopyResourceStatus.isAboveComplete(transfer.status) { return .notAccepted }

        onStage?(.transferring)

        // Python: `while not resource_done: i = progress_update(i)`. The loop body ALWAYS
        // renders the "Transferring file" form — `resource_done` is only consulted by the
        // loop condition — and the single "Transfer complete" render is the separate
        // `progress_update(i, done=True)` after the loop (rncp.py:767-777).
        var meter = RNCopyProgressMeter()
        var done = RNCopyResourceStatus.isAtLeastComplete(transfer.status)
        while !done {
            Thread.sleep(forTimeInterval: tick)
            publish(transfer: transfer, meter: &meter, done: false, overrideSpeed: nil)
            done = RNCopyResourceStatus.isAtLeastComplete(transfer.status)
        }

        let transferTime = Date().timeIntervalSince(startedAt)
        let totalSize = transfer.dataSize

        // Python overwrites the global `speed` with the AVERAGE rate before the final
        // progress_update(done=True), so the completion line reports the average.
        let averageSpeed = transferTime > 0 ? Double(totalSize) / transferTime : 0
        publish(transfer: transfer, meter: &meter, done: true, overrideSpeed: averageSpeed)

        guard transfer.status == .complete else { return .transferFailed }
        return .completed(bytes: totalSize, duration: transferTime)
    }

    private func publish(transfer: ResourceTransfer,
                         meter: inout RNCopyProgressMeter,
                         done: Bool,
                         overrideSpeed: Double?) {
        let fraction = transfer.progress
        let totalSize = transfer.dataSize
        meter.update(now: Date().timeIntervalSince1970,
                     got: fraction * Double(totalSize),
                     phyGot: transfer.segmentProgress * Double(transfer.transferSize))
        onProgress?(Progress(fraction: fraction,
                             transferredBytes: Int(fraction * Double(totalSize)),
                             totalBytes: totalSize,
                             speed: overrideSpeed ?? meter.speed,
                             phySpeed: meter.phySpeed,
                             done: done))
    }
}

// MARK: - Fetcher

/// The fetching half of `rncp` — Python's `fetch()` (rncp.py:359-614).
public final class RNCopyFetcher {

    public typealias Stage = RNCopyStage
    public typealias Progress = RNCopyProgress

    public struct Configuration {
        public var identity: Identity
        public var destinationHash: Data
        /// The path to ask the listener for. Travels as a msgpack **str** — Python's
        /// handler calls `str.startswith` on it, so a msgpack bin would raise remotely.
        public var remotePath: String
        public var timeout: TimeInterval
        /// `-s/--save`, already absolutised and validated.
        public var savePath: String?
        /// `-O/--overwrite`.
        public var allowOverwrite: Bool

        public init(identity: Identity,
                    destinationHash: Data,
                    remotePath: String,
                    timeout: TimeInterval = Transport.pathRequestTimeout,
                    savePath: String? = nil,
                    allowOverwrite: Bool = false) {
            self.identity = identity
            self.destinationHash = destinationHash
            self.remotePath = remotePath
            self.timeout = timeout
            self.savePath = savePath
            self.allowOverwrite = allowOverwrite
        }
    }

    public enum Outcome: Equatable {
        case completed(savedTo: String, bytes: Int, duration: TimeInterval)
        /// "Path not found", exit 1.
        case pathNotFound
        /// "Could not establish link with <hash>", exit 1. Python tests `has_path` rather
        /// than the link status here (rncp.py:441) — an upstream quirk, mirrored.
        case linkFailed
        /// A path exists but no identity is known for it.
        case identityUnknown
        /// One of the four request-outcome branches. **All four exit 0** in Python
        /// (rncp.py:547,553,559,565).
        case requestFailed(RNCopyFetchStatus)
        /// "The transfer failed", exit 1.
        case transferFailed
        /// The resource arrived but could not be written.
        case saveFailed(RNCopyError)
    }

    public var onStage: ((Stage) -> Void)?
    public var onProgress: ((Progress) -> Void)?
    /// Fires with the plain-`print` diagnostics Python emits from inside
    /// `fetch_resource_concluded` (rncp.py:491,501,511,520,524).
    public var onNotice: ((String) -> Void)?
    /// Fires once per tick while the request has been answered but no resource has begun,
    /// so the CLI can render "Waiting for transfer to start <spinner>" (rncp.py:593).
    public var onWaiting: (() -> Void)?
    /// Fires once per 0.1 s poll during a wait that has nothing else to show, so the CLI can
    /// advance the Braille spinner (rncp.py:408,437,538).
    public var onTick: (() -> Void)?

    private let transport: Transport
    private let fileSystem: RNCopyFileSystem
    private let configuration: Configuration
    private let tick: TimeInterval

    private let stateLock = NSLock()
    private var link: Link?
    private var transfer: ResourceTransfer?
    private var requestResolved = false
    private var requestStatus: RNCopyFetchStatus = .unknown
    private var resourceResolved = false
    private var transferStartedAt: Date?
    private var savedPath: String?
    private var saveError: RNCopyError?

    public init(transport: Transport,
                fileSystem: RNCopyFileSystem = RNCopyDiskFileSystem(),
                configuration: Configuration,
                tick: TimeInterval = 0.1) {
        self.transport = transport
        self.fileSystem = fileSystem
        self.configuration = configuration
        self.tick = tick
    }

    public func cancel() {
        stateLock.lock(); let t = transfer; let l = link; stateLock.unlock()
        t?.cancel()
        try? l?.teardown()
    }

    /// Tear the link down after an outcome, mirroring Python's `link.teardown()` before
    /// every `RNS.exit(...)` in `fetch()`.
    public func teardown() {
        stateLock.lock(); let l = link; stateLock.unlock()
        try? l?.teardown()
    }

    public func run() -> Outcome {
        let opener = RNCopyLinkOpener(transport: transport,
                                      destinationHash: configuration.destinationHash,
                                      timeout: configuration.timeout,
                                      tick: tick)
        let link: Link
        switch opener.open(onStage: onStage, onTick: onTick) {
        case .pathNotFound:     return .pathNotFound
        case .identityUnknown:  return .identityUnknown
        case .failed:           return .linkFailed
        case .opened(let opened, _, let hasPath):
            stateLock.lock(); self.link = opened; stateLock.unlock()
            // Python checks has_path here, NOT link.status (rncp.py:441). Mirrored.
            guard hasPath else { return .linkFailed }
            link = opened
        }

        onStage?(.requestingFile)

        do { try link.identify(as: configuration.identity) }
        catch { return .linkFailed }

        link.resourceStrategy = .acceptAll
        link.onResourceStarted = { [weak self] transfer in
            self?.handleResourceStarted(transfer)
        }
        link.onResourceConcluded = { [weak self] payload, advertisement, _ in
            self?.handleResourceConcluded(payload: payload, advertisement: advertisement)
        }

        // The request data MUST be a msgpack str: Python's fetch_request does
        // `data.startswith(...)` and `f"{fetch_jail}/{data}"` on it.
        //
        // The explicit timeout is a safety net only: Link.request derives its default from
        // the link RTT, which is always known after establishment, but a link that somehow
        // has no RTT would otherwise leave the receipt (and this loop) hanging forever.
        do {
            _ = try link.request(
                path: RNCopyApp.fetchRequestPath,
                nativeValue: .string(configuration.remotePath),
                responseCallback: { [weak self] payload, _ in
                    self?.resolveRequest(RNCopyApp.classifyFetchResponse(payload))
                },
                failedCallback: { [weak self] _, _ in
                    // Python: request_failed → request_status = "unknown". This is the
                    // branch reached when the listener has no fetch handler registered, or
                    // when ALLOW_LIST denied the request (Python then sends nothing).
                    self?.resolveRequest(.unknown)
                },
                timeout: link.rtt == nil ? configuration.timeout : nil
            )
        } catch {
            return .linkFailed
        }

        while !snapshotRequestResolved() {
            Thread.sleep(forTimeInterval: tick)
            onTick?()
        }

        let status = snapshotRequestStatus()
        guard status == .found else { return .requestFailed(status) }

        onStage?(.waitingForTransfer)

        // Python: `while not resource_resolved:` renders inside the loop and branches on
        // `prg != 1.0` — so the "Transfer complete" form (with the elapsed time and the
        // average rate) is emitted from within the loop, and there is no post-loop render
        // (rncp.py:569-595).
        var meter = RNCopyProgressMeter()
        while !snapshotResourceResolved() {
            Thread.sleep(forTimeInterval: tick)
            publish(meter: &meter)
        }

        stateLock.lock()
        let transfer = self.transfer
        let startedAt = transferStartedAt
        let savedPath = self.savedPath
        let saveError = self.saveError
        stateLock.unlock()

        // Python: if not current_resource or current_resource.status != COMPLETE.
        guard let transfer, transfer.status == .complete else { return .transferFailed }

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        if let saveError { return .saveFailed(saveError) }
        return .completed(savedTo: savedPath ?? "", bytes: transfer.dataSize, duration: duration)
    }

    // MARK: - Resource callbacks

    /// Python: `fetch_resource_started` (rncp.py:479-484).
    ///
    /// Upstream assigns `current_resource` without a `nonlocal`/`global` declaration, so the
    /// module global is only populated as a side effect of the progress callback. The
    /// transfer is tracked directly here — observably identical.
    private func handleResourceStarted(_ transfer: ResourceTransfer) {
        stateLock.lock()
        self.transfer = transfer
        if transferStartedAt == nil { transferStartedAt = Date() }
        stateLock.unlock()

        transfer.onFailed = { [weak self] _, _ in
            guard let self else { return }
            self.onNotice?("Resource failed")
            self.stateLock.lock(); self.resourceResolved = true; self.stateLock.unlock()
        }
    }

    /// Python: `fetch_resource_concluded` (rncp.py:486-527).
    ///
    /// Upstream's early `return`s on invalid metadata / bad save path / write exception skip
    /// `resource_resolved = True`, hanging the client in its progress loop. This always
    /// resolves — a deliberate, documented divergence.
    private func handleResourceConcluded(payload: Data, advertisement: ResourceAdvertisement) {
        stateLock.lock()
        let transfer = self.transfer
        stateLock.unlock()

        let result = RNCopyApp.saveReceivedResource(
            payload: payload,
            metadata: transfer?.receivedMetadata,
            savePath: configuration.savePath,
            allowOverwrite: configuration.allowOverwrite,
            fileSystem: fileSystem,
            onOverwriteFailure: { [weak self] path in
                self?.onNotice?("Could not overwrite existing file \(path), renaming instead")
            }
        )

        stateLock.lock()
        switch result {
        case .success(let path):
            savedPath = path
        case .failure(let error):
            saveError = error
            switch error {
            case .missingMetadata:
                onNotice?("Invalid data received, ignoring resource")
            case .invalidSavePath(let path):
                onNotice?("Invalid save path \(path), ignoring")
            case .writeFailed, .overwriteFailed:
                onNotice?("An error occurred while saving received resource: \(error.exceptionText)")
            }
        }
        resourceResolved = true
        stateLock.unlock()
        _ = advertisement
    }

    // MARK: - Helpers

    private func resolveRequest(_ status: RNCopyFetchStatus) {
        stateLock.lock()
        if !requestResolved {
            requestStatus = status
            requestResolved = true
        }
        stateLock.unlock()
    }

    private func snapshotRequestResolved() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return requestResolved
    }

    private func snapshotRequestStatus() -> RNCopyFetchStatus {
        stateLock.lock(); defer { stateLock.unlock() }; return requestStatus
    }

    private func snapshotResourceResolved() -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }; return resourceResolved
    }

    private func publish(meter: inout RNCopyProgressMeter) {
        stateLock.lock()
        let transfer = self.transfer
        let startedAt = transferStartedAt
        stateLock.unlock()

        guard let transfer else {
            // Python: "Waiting for transfer to start <sym>" — no Progress sample yet.
            onWaiting?()
            return
        }

        let fraction = transfer.progress
        let totalSize = transfer.dataSize
        meter.update(now: Date().timeIntervalSince1970,
                     got: fraction * Double(totalSize),
                     phyGot: transfer.segmentProgress * Double(transfer.transferSize))

        // Python: `if prg != 1.0:` renders "Transferring file"; the else branch recomputes
        // the elapsed time and reports the AVERAGE rate on a "Transfer complete" line.
        if fraction != 1.0 {
            onProgress?(Progress(fraction: fraction,
                                 transferredBytes: Int(fraction * Double(totalSize)),
                                 totalBytes: totalSize,
                                 speed: meter.speed,
                                 phySpeed: meter.phySpeed,
                                 done: false))
        } else {
            let elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? 0
            let averageSpeed = elapsed > 0 ? Double(totalSize) / elapsed : 0
            onProgress?(Progress(fraction: fraction,
                                 transferredBytes: Int(fraction * Double(totalSize)),
                                 totalBytes: totalSize,
                                 speed: averageSpeed,
                                 phySpeed: meter.phySpeed,
                                 done: true,
                                 elapsed: elapsed))
        }
    }
}
