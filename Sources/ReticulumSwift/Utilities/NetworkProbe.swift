import Foundation

// MARK: - Seams
//
// These five protocols are the injection points that let the whole of rnprobe run
// offline in XCTest: a scripted clock, deterministic entropy, a capturing output sink
// and a fake network. Live conformers are in `NetworkProbeEnvironment.swift`.
//
// They live at file scope rather than nested inside ``NetworkProbe`` on purpose:
// protocols nested in a type need SE-0404 (a Swift 5.10+ compiler) and `Package.swift`
// declares `swift-tools-version: 5.9`.

/// A `PacketReceipt` as the probe observes it.
///
/// Python: `RNS.PacketReceipt` — `status`, `get_rtt()` and `proof_packet` (rnprobe.py:136,
/// 157, 167-186).
public protocol ProbeReceipt: AnyObject {
    /// Python: `receipt.status` compared against `RNS.PacketReceipt.SENT` / `DELIVERED`.
    var status: PacketReceipt.Status { get }
    /// Python: `receipt.get_rtt()` (Packet.py:526-530).
    var rtt: TimeInterval? { get }
    /// Full 32-byte SHA-256 of the sent packet.
    var packetHash: Data { get }
    /// Truncated 16-byte packet hash.
    var truncatedHash: Data { get }
    /// Python: `receipt.proof_packet != None` (rnprobe.py:181).
    var hasProofPacket: Bool { get }
    /// Python: `receipt.proof_packet.rssi` (rnprobe.py:182).
    var proofRssi: Float? { get }
    /// Python: `receipt.proof_packet.snr` (rnprobe.py:185).
    var proofSnr: Float? { get }
    /// Python: `receipt.proof_packet.packet_hash` — the FULL 32-byte hash (Packet.py:342).
    var proofPacketFullHash: Data? { get }
    /// The 16-byte form of the same hash. Needed because a Swift daemon caches its PHY
    /// stats under the truncated hash while Python caches under the full one — see the
    /// fallback in ``TransportProbeNetwork``.
    var proofPacketTruncatedHash: Data? { get }
}

/// Wall clock + sleep, so the wait loops can be driven deterministically in tests.
/// Python: `time.time()` and `time.sleep()`.
public protocol ProbeClock: AnyObject {
    func now() -> TimeInterval
    func sleep(_ interval: TimeInterval)
}

/// Probe payload source. Python: `os.urandom(size)` (rnprobe.py:115).
public protocol ProbeEntropy: AnyObject {
    func randomBytes(_ count: Int) -> Data
}

/// Where the tool's bytes go. Everything rnprobe prints is routed through here so a test
/// can assert the exact byte stream, control characters and all.
public protocol ProbeOutput: AnyObject {
    func write(_ text: String)
    /// Swift-only. Python leaks the equivalent failures as uncaught tracebacks on stderr;
    /// the port prints one clean line instead.
    func writeError(_ text: String)
    func flush()
}

/// Everything rnprobe asks of the running stack.
///
/// Python reaches for `RNS.Transport.*` statics and `reticulum.get_*` instance methods,
/// the latter of which transparently switch to RPC when attached to a shared instance.
public protocol ProbeNetwork: AnyObject {
    /// Python: `RNS.Transport.has_path(destination_hash)` (rnprobe.py:79, 87).
    func hasPath(to destinationHash: Data) -> Bool
    /// Python: `RNS.Transport.request_path(destination_hash)` (rnprobe.py:80).
    /// Swallows the Swift `throws`; note `Transport.requestPath` silently no-ops for a
    /// hash that is not 16 bytes.
    func requestPath(for destinationHash: Data)
    /// Python: `RNS.Identity.recall(destination_hash)` (rnprobe.py:97).
    func recallIdentity(for destinationHash: Data) -> Identity?
    /// The 32-byte ratchet PUBLIC key for a destination, mirroring the
    /// `RNS.Identity.get_ratchet(self.hash)` lookup inside `Destination.encrypt`
    /// (Destination.py:594-600). Nil falls back to the identity's static X25519 key.
    func currentRatchetKey(for destinationHash: Data) -> Data?
    /// Build, MTU-check and send one probe packet.
    ///
    /// Python: `RNS.Packet(request_destination, payload)` + `pack()` + `send()`
    /// (rnprobe.py:114-121). Throws ``NetworkProbe/SendError/mtuExceeded(size:)`` so the
    /// caller can print Python's exact message and exit 3.
    func transmit(ciphertext: Data, to destinationHash: Data) throws -> (any ProbeReceipt)?
    /// Python: `RNS.Transport.hops_to(destination_hash)`, which returns
    /// `PATHFINDER_M` (128) when no path is known (Transport.py:2676-2683).
    func hops(to destinationHash: Data) -> Int
    /// Python: `reticulum.get_next_hop(destination_hash)` (rnprobe.py:125).
    func nextHop(to destinationHash: Data) -> Data?
    /// Python: `reticulum.get_next_hop_if_name(destination_hash)` (rnprobe.py:127), i.e.
    /// `str(Transport.next_hop_interface(dh))` — the interface's `__str__`, whose Swift
    /// analogue is ``Interface/displayName``, NOT `Interface.name`. Deliberately not
    /// spelled `nextHopInterfaceName` so it cannot be confused with
    /// `Transport.nextHopInterfaceName(for:)`, which returns the wrong string.
    func nextHopInterfaceDisplayName(for destinationHash: Data) -> String?
    /// Python: `reticulum.get_first_hop_timeout(destination_hash)` (rnprobe.py:84, 134).
    /// Must return `DEFAULT_PER_HOP_TIMEOUT` (6.0) if the shared-instance RPC fails,
    /// matching Reticulum.py:1570-1572.
    func firstHopTimeout(for destinationHash: Data) -> TimeInterval
    /// Python: `reticulum.is_connected_to_shared_instance` (rnprobe.py:166).
    var isConnectedToSharedInstance: Bool { get }
    /// Python: `reticulum.get_packet_rssi(packet_hash)` (rnprobe.py:167). Raw MsgPack so
    /// the int-vs-float distinction Python's `str()` depends on survives.
    func packetRSSI(packetHash: Data) -> MsgPack.Value?
    /// Python: `reticulum.get_packet_snr(packet_hash)` (rnprobe.py:168).
    func packetSNR(packetHash: Data) -> MsgPack.Value?
    /// Python: `reticulum.get_packet_q(packet_hash)` (rnprobe.py:169).
    func packetQ(packetHash: Data) -> MsgPack.Value?
}

// MARK: - NetworkProbe

/// Network probe utility — sends encrypted random-payload packets to a single destination
/// and reports per-probe RTT, hop count and physical-layer statistics.
///
/// Python reference: `RNS/Utilities/rnprobe.py` (RNS 1.4.0). ``run(options:)`` is the whole
/// of `program_setup` (rnprobe.py:44-206) and owns every byte the tool prints.
///
/// ### Deliberate divergences from Python
///
/// Each one is a case where Python crashes, hangs or leaks a traceback. They are listed
/// here so a future parity audit does not "restore" the defect:
///
/// - `-n 0`, `-n <negative>`, `-s <negative>` and `-w <negative>` are usage errors (exit 2).
///   Python raises `ZeroDivisionError`, loops forever, or raises `ValueError` out of
///   `os.urandom` / `time.sleep` — all uncaught tracebacks (rnprobe.py:109, 112, 115).
/// - `RNS.Identity.recall` returning `None` makes Python raise an uncaught `ValueError`
///   from `Destination.__init__` (Destination.py:179). The port prints one stderr line and
///   exits 1.
/// - Python's `Packet.send()` can return `False` when no interface accepted the packet,
///   after which `receipt.status` raises `AttributeError` (Packet.py:297-302). Swift's
///   `Transport.send` always mints the receipt, so that case degrades to an ordinary
///   probe timeout.
/// - The shared-instance PHY branch dereferences `receipt.proof_packet.packet_hash` with
///   no `None` guard (rnprobe.py:167). The port emits no PHY fragments instead of trapping.
/// - Python prints a literal `" on None"` when the daemon answers `next_hop_if_name` with
///   real `None` rather than the string `"None"` (`None != "None"` is true). The port
///   suppresses the fragment for both spellings.
///
/// ### Usage
/// ```swift
/// let probe = NetworkProbe(network: network, clock: clock, entropy: entropy, output: output)
/// let status = probe.run(options: options)   // status.rawValue is the process exit code
/// ```
public final class NetworkProbe {

    // MARK: - Class constants

    /// Default probe payload size in bytes.
    /// Python: `DEFAULT_PROBE_SIZE = 16` (rnprobe.py:41).
    public static let defaultProbeSize: Int = 16

    /// Default reply timeout in seconds. Base of both the path-wait and the per-probe
    /// deadline. Python: `DEFAULT_TIMEOUT = 12` (rnprobe.py:42).
    public static let defaultTimeout: TimeInterval = 12

    /// Application name (the utility has no `APP_NAME`, but is identified as "rnprobe").
    public static let appName: String = "rnprobe"

    /// Python: `syms = "⢄⢂⢁⡁⡈⡐⡠"` (rnprobe.py:86) — seven Braille code points,
    /// scalar values verified with `ord()`.
    public static let spinnerGlyphs: [String] = [
        "\u{2884}", "\u{2882}", "\u{2881}", "\u{2841}", "\u{2848}", "\u{2850}", "\u{2860}"
    ]

    /// Poll interval of both wait loops. Python: `time.sleep(0.1)` (rnprobe.py:88, 137).
    public static let pollInterval: TimeInterval = 0.1

    /// Erase-line width before "Path request timed out" and before the receipt-failed
    /// "Probe timed out". Python: rnprobe.py:94 and :197 — both literals measure 58 spaces.
    public static let shortEraseWidth: Int = 58

    /// Erase-line width used by the DEADLINE "Probe timed out".
    /// Python: rnprobe.py:143 — that literal measures 64 spaces. The two widths differ in
    /// the Python source; the discrepancy is reproduced rather than harmonised.
    public static let longEraseWidth: Int = 64

    /// Python: `dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2` = 32 (rnprobe.py:58).
    public static let destinationHexLength: Int = Constants.truncatedHashLength * 2

    // MARK: - Exit codes

    /// Process exit statuses. Python uses a bare `exit()` (0), `exit(1)`, `exit(2)` and
    /// `exit(3)`. Note that 2 is overloaded — argparse also exits 2 on a usage error, so a
    /// script cannot tell packet loss from a bad command line. Inherited, not "fixed".
    public enum Result: Int32, Equatable, CaseIterable {
        /// Python: `exit(0)` (rnprobe.py:206) and every bare `exit()`.
        case ok = 0
        /// Python: `exit(1)` (rnprobe.py:95), plus the Swift-only fatal cases.
        case pathTimeout = 1
        /// Python: `exit(2)` (rnprobe.py:204); also argparse's error status.
        case packetLoss = 2
        /// Python: `exit(3)` (rnprobe.py:119).
        case mtuExceeded = 3
    }

    // MARK: - Options

    /// One parsed invocation of the tool.
    public struct Options: Equatable {
        /// Python positional `full_name`, default `None`.
        public var fullName: String?
        /// Python positional `destination_hash`, default `None`.
        public var destinationHexhash: String?
        /// Python `--config`. A config *directory*, despite the flag's spelling.
        public var configDir: URL?
        /// Python `-s/--size`, default `None` → ``NetworkProbe/defaultProbeSize``.
        public var size: Int?
        /// Python `-n/--probes`, default 1.
        public var probes: Int
        /// Python `-t/--timeout`, default `None`.
        public var timeout: TimeInterval?
        /// Python `-w/--wait`, default 0.
        public var wait: TimeInterval
        /// Python `-v` count, default 0.
        public var verbosity: Int

        public init(fullName: String? = nil,
                    destinationHexhash: String? = nil,
                    configDir: URL? = nil,
                    size: Int? = nil,
                    probes: Int = 1,
                    timeout: TimeInterval? = nil,
                    wait: TimeInterval = 0,
                    verbosity: Int = 0) {
            self.fullName = fullName
            self.destinationHexhash = destinationHexhash
            self.configDir = configDir
            self.size = size
            self.probes = probes
            self.timeout = timeout
            self.wait = wait
            self.verbosity = verbosity
        }

        /// Python: `more_output = verbosity > 0` (rnprobe.py:69-74). Gates only the
        /// " via …/ on …" annotation on the "Sent probe" line.
        public var moreOutput: Bool { verbosity > 0 }

        /// Python: `RNS.Reticulum(loglevel = 3 + verbosity)` where `verbosity` has already
        /// been decremented once in *both* branches (rnprobe.py:69-77). So no `-v` gives
        /// LOG_WARNING (2) — quieter than the RNS default of 4 — and each extra `-v` adds
        /// one level.
        ///
        /// Clamped to `.extreme`: a bare `LogLevel(rawValue:) ?? .warning` would make
        /// `-vvvvvvv` *quieter* than `-vvvvvv`, because raw value 9 is out of range.
        public var logLevel: Reticulum.LogLevel {
            let raw = 3 + (verbosity - 1)
            if raw >= Reticulum.LogLevel.extreme.rawValue { return .extreme }
            return Reticulum.LogLevel(rawValue: raw) ?? .warning
        }
    }

    // MARK: - Validation

    /// The three failures Python reports with a message on stdout and a bare `exit()`
    /// — i.e. process status 0, not an error code.
    public enum ValidationError: Error, Equatable {
        /// Python: rnprobe.py:46-48.
        case missingFullName
        /// Python: rnprobe.py:59-60.
        case badHashLength
        /// Python: rnprobe.py:61-64.
        case badHashHex

        /// The exact stdout line Python prints before exiting.
        public var message: String {
            switch self {
            case .missingFullName:
                return "The full destination name including application name aspects must be specified for the destination"
            case .badHashLength:
                // Python interpolates dest_len and dest_len//2 into the same sentence.
                return "Destination length is invalid, must be \(NetworkProbe.destinationHexLength) hexadecimal characters (\(NetworkProbe.destinationHexLength / 2) bytes)."
            case .badHashHex:
                return "Invalid destination entered. Check your input."
            }
        }
    }

    /// Failures of the send path.
    public enum SendError: Error, Equatable {
        /// Python: `IOError`/`OSError` out of `Packet.pack()` (Packet.py:236). The size is
        /// the real packed length, which Python reads back off `probe.raw`.
        case mtuExceeded(size: Int)
        /// Python: uncaught `ValueError` from `Destination.__init__` (Destination.py:179).
        case noIdentity
        /// Swift-only: the payload could not be encrypted for the destination.
        case encryptionFailed
        /// Swift-only and near-unreachable: `Transport.send` produced no receipt.
        case notSent
    }

    // MARK: - Outcome

    /// One probe's result, for programmatic callers and assertions.
    public struct Outcome: Equatable {
        public enum Conclusion: Equatable {
            /// Python: `receipt.status == DELIVERED` (rnprobe.py:149).
            case delivered
            /// Python: rnprobe's own deadline fired (rnprobe.py:142) — the 64-space branch.
            case deadlineExceeded
            /// Python: the receipt's own timeout fired (rnprobe.py:196) — the 58-space branch.
            case receiptFailed
        }
        public let index: Int
        public let conclusion: Conclusion
        public let rtt: TimeInterval?
        public let hops: Int?
        public let receptionStats: String
        /// Swift-only diagnostic Python lacks: true when the destination built from
        /// `full_name` + the recalled identity does not equal the typed
        /// `destination_hash`. Never printed — Python is silent about this, and reproducing
        /// the silence is what parity requires.
        public let destinationHashMismatch: Bool

        public init(index: Int,
                    conclusion: Conclusion,
                    rtt: TimeInterval?,
                    hops: Int?,
                    receptionStats: String,
                    destinationHashMismatch: Bool) {
            self.index = index
            self.conclusion = conclusion
            self.rtt = rtt
            self.hops = hops
            self.receptionStats = receptionStats
            self.destinationHashMismatch = destinationHashMismatch
        }
    }

    // MARK: - Instance state

    /// Number of random bytes sent as probe payload.
    public private(set) var size: Int

    /// Seconds to wait for a delivery receipt before declaring a timeout.
    public private(set) var timeout: TimeInterval

    /// One ``Outcome`` per probe actually sent, in order.
    public private(set) var outcomes: [Outcome] = []

    private weak var transport: Transport?
    private let network: (any ProbeNetwork)?
    private let clock: any ProbeClock
    private let entropy: any ProbeEntropy
    private let output: (any ProbeOutput)?

    private let cancelLock = NSLock()
    private var cancelled = false

    // MARK: - Initialisation

    /// Create a probe helper attached to `transport`.
    ///
    /// Retained for the single-shot ``send(to:size:)`` convenience; ``run(options:)`` uses
    /// the injectable initialiser below.
    ///
    /// - Parameters:
    ///   - transport: the `Transport` used to send packets.
    ///   - defaultSize: payload size in bytes. Defaults to ``defaultProbeSize``.
    ///   - timeout: reply timeout in seconds. Defaults to ``defaultTimeout``.
    ///   - entropy: payload source. Defaults to a CSPRNG, matching `os.urandom`.
    public init(transport: Transport,
                defaultSize: Int = NetworkProbe.defaultProbeSize,
                timeout: TimeInterval = NetworkProbe.defaultTimeout,
                entropy: any ProbeEntropy = SecureProbeEntropy()) {
        self.transport = transport
        self.size = defaultSize
        self.timeout = timeout
        self.network = nil
        self.clock = SystemProbeClock()
        self.entropy = entropy
        self.output = nil
    }

    /// The initialiser ``run(options:)`` and every unit test use.
    public init(network: any ProbeNetwork,
                clock: any ProbeClock,
                entropy: any ProbeEntropy,
                output: any ProbeOutput) {
        self.transport = nil
        self.network = network
        self.clock = clock
        self.entropy = entropy
        self.output = output
        self.size = NetworkProbe.defaultProbeSize
        self.timeout = NetworkProbe.defaultTimeout
    }

    // MARK: - Cancellation

    /// Cooperative cancellation for the executable's SIGINT handler.
    /// Python: `except KeyboardInterrupt: print(""); exit()` (rnprobe.py:247-249).
    ///
    /// Signal handling itself must stay in the executable target — the library has no
    /// signal machinery and must keep compiling for iOS, tvOS and watchOS.
    public func cancel() {
        cancelLock.lock(); cancelled = true; cancelLock.unlock()
    }

    private var isCancelled: Bool {
        cancelLock.lock(); defer { cancelLock.unlock() }; return cancelled
    }

    // MARK: - Pure helpers

    /// Parse and validate the typed destination hash.
    /// Python: rnprobe.py:57-64. `bytes.fromhex` is case-insensitive, so `AABB…` is valid.
    public static func parseDestinationHash(_ hexhash: String) throws -> Data {
        guard hexhash.count == destinationHexLength else { throw ValidationError.badHashLength }
        var out = Data(capacity: destinationHexLength / 2)
        var index = hexhash.startIndex
        while index < hexhash.endIndex {
            let next = hexhash.index(index, offsetBy: 2)
            guard let byte = UInt8(hexhash[index..<next], radix: 16) else {
                throw ValidationError.badHashHex
            }
            out.append(byte)
            index = next
        }
        return out
    }

    /// Split a full dotted destination name the way Python's
    /// `Destination.app_and_aspects_from_name` does — a plain `full_name.split(".")`,
    /// which **keeps empty components**.
    ///
    /// `Destination.appAndAspects(fromFullName:)` uses `split(separator:".")`, whose
    /// `omittingEmptySubsequences` defaults to `true` and therefore drops them. That
    /// changes the name hash, and with it the destination hash, so this tool must not
    /// reuse it: Python maps `"lxmf..delivery"` to `("lxmf", ["", "delivery"])`.
    public static func appAndAspects(fromFullName fullName: String) -> (appName: String, aspects: [String]) {
        let components = fullName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard let first = components.first else { return ("", []) }
        return (first, Array(components.dropFirst()))
    }

    /// Python `str(float)` — shortest round-trip repr, always with at least one fractional
    /// digit (`0.5` → `"0.5"`, `1000.0` → `"1000.0"`). A `String(format: "%.3f")` would
    /// print `"0.500"` and diverge.
    public static func pythonFloatString(_ value: Double) -> String {
        "\(value)"
    }

    /// Python `round(value, digits)`.
    ///
    /// Python rounds the exact decimal expansion of the double (half-to-even via
    /// `_Py_dg_dtoa`); this multiplies first. The two differ only on exact ties at the
    /// rounding digit, which for an RTT is unobservable — but do not build a differential
    /// test on adversarial inputs.
    public static func pythonRound(_ value: Double, _ digits: Int) -> Double {
        let scale = pow(10.0, Double(digits))
        return (value * scale).rounded(.toNearestOrEven) / scale
    }

    /// Python `str(int)` — no decimal point. Used for RSSI, which is an int in Python.
    public static func pythonIntString(_ value: Int) -> String { "\(value)" }

    /// Python: rnprobe.py:157-163. The boundary is `rtt >= 1`.
    public static func rttString(_ rtt: TimeInterval) -> String {
        if rtt >= 1 {
            return pythonFloatString(pythonRound(rtt, 3)) + " seconds"
        }
        return pythonFloatString(pythonRound(rtt * 1000, 3)) + " milliseconds"
    }

    /// Render a MsgPack scalar the way Python's `str()` would.
    ///
    /// The int/float distinction is load-bearing: a Python daemon returns RSSI as an int
    /// (`RNodeInterface.py:878`) and SNR/quality as floats (:880, :890), so `str()` gives
    /// `-73` but `-2.5`. Going through `RPCClient`'s typed `asDouble` helpers would flatten
    /// that to `-73.0`.
    public static func pythonScalarString(_ value: MsgPack.Value) -> String? {
        switch value {
        case .int(let n):    return "\(n)"
        case .uint(let n):   return "\(n)"
        case .double(let d): return pythonFloatString(d)
        default:             return nil
        }
    }

    /// Run every check `program_setup` performs before it constructs a Reticulum instance.
    ///
    /// Python: rnprobe.py:45-67 all executes ahead of `RNS.Reticulum(...)` at :77, so a bad
    /// command line never brings a stack up and never touches a running daemon. The
    /// executable calls this before attaching for exactly that reason; ``run(options:)``
    /// repeats it so a direct library caller gets the same behaviour.
    ///
    /// - Returns: the failure Python would print before its bare `exit()`, or nil.
    public static func validate(options: Options) -> ValidationError? {
        // Note: the size default at rnprobe.py:45 is applied before this, and is not a
        // failure mode, so it is not represented here.
        guard options.fullName != nil else { return .missingFullName }
        do {
            _ = try parseDestinationHash(options.destinationHexhash ?? "")
            return nil
        } catch let error as ValidationError {
            return error
        } catch {
            return .badHashHex
        }
    }

    /// Python: `timeout or DEFAULT_TIMEOUT + reticulum.get_first_hop_timeout(dh)`
    /// (rnprobe.py:84, 134). `or` is falsy on `0` and `0.0`, so `-t 0` means "unset"; the
    /// precedence is `timeout or (12 + fht)`, not `(timeout or 12) + fht`.
    public static func effectiveTimeout(_ timeout: TimeInterval?, firstHopTimeout: TimeInterval) -> TimeInterval {
        if let timeout, timeout != 0 { return timeout }
        return defaultTimeout + firstHopTimeout
    }

    // MARK: - Run

    /// The whole of `rnprobe.py::program_setup`, emitting byte-identical output through
    /// the injected ``ProbeOutput`` and returning the process exit status.
    @discardableResult
    public func run(options: Options) -> Result {
        guard let network, let output else { return .ok }
        outcomes = []

        // Python: `if size == None: size = DEFAULT_PROBE_SIZE` (rnprobe.py:45) — applied
        // BEFORE the full_name check and before hash validation. Order preserved.
        let size = options.size ?? NetworkProbe.defaultProbeSize
        self.size = size

        // Python: rnprobe.py:46-48 and :57-67 — each failure prints one line on stdout and
        // then bare-exits, i.e. process status 0, not an error code.
        if let error = NetworkProbe.validate(options: options) {
            output.write(error.message + "\n")
            output.flush()
            return .ok
        }
        guard let fullName = options.fullName,
              let destinationHash = try? NetworkProbe.parseDestinationHash(options.destinationHexhash ?? "")
        else { return .ok }

        // Python: rnprobe.py:50-55. `str.split` never raises, so Python's try/except here
        // is dead code.
        let (appName, aspects) = NetworkProbe.appAndAspects(fromFullName: fullName)

        // ── Path phase (rnprobe.py:79-95) ──────────────────────────────────────────
        if !network.hasPath(to: destinationHash) {
            network.requestPath(for: destinationHash)
            // Python: print(… + " requested  ", end=" ") — two literal spaces plus
            // print's end=" " makes THREE, and there is no newline.
            output.write("Path to " + RNSUtilities.prettyhexrep(destinationHash) + " requested   ")
            output.flush()
        }

        // Python: rnprobe.py:84. Evaluated unconditionally, even when a path already
        // exists. With no path known, first_hop_timeout is DEFAULT_PER_HOP_TIMEOUT = 6,
        // making the usual deadline now + 18.
        var deadline = clock.now() + NetworkProbe.effectiveTimeout(
            options.timeout, firstHopTimeout: network.firstHopTimeout(for: destinationHash))

        var glyph = 0
        while !network.hasPath(to: destinationHash) && !(clock.now() > deadline) {
            if isCancelled { return finishCancelled(output) }
            clock.sleep(NetworkProbe.pollInterval)          // Python: sleep BEFORE the first frame
            output.write("\u{08}\u{08}" + NetworkProbe.spinnerGlyphs[glyph] + " ")
            output.flush()
            glyph = (glyph + 1) % NetworkProbe.spinnerGlyphs.count
        }

        if clock.now() > deadline {
            // Python: rnprobe.py:94 — \r, 58 spaces, \r, then the message plus print's \n.
            output.write("\r" + String(repeating: " ", count: NetworkProbe.shortEraseWidth)
                         + "\rPath request timed out\n")
            output.flush()
            return .pathTimeout
        }

        // ── Destination construction (rnprobe.py:97-105) ───────────────────────────
        guard let serverIdentity = network.recallIdentity(for: destinationHash) else {
            // Python: an uncaught ValueError from Destination.__init__ → traceback, exit 1.
            output.writeError("Can't create outbound SINGLE destination without an identity\n")
            output.flush()
            return .pathTimeout
        }

        let requestDestination: Destination
        do {
            requestDestination = try Destination(identity: serverIdentity,
                                                 direction: .out,
                                                 kind: .single,
                                                 appName: appName,
                                                 aspects: aspects)
        } catch {
            output.writeError("Can't create outbound SINGLE destination without an identity\n")
            output.flush()
            return .pathTimeout
        }
        // Python never compares the constructed hash against the typed one; the probe is
        // encrypted for one and the path was requested for the other. Surfaced on
        // Outcome, never printed. Note that Destination.__init__ registers only IN
        // destinations, so nothing is registered here either — registering would make
        // Transport.send take its local-delivery branch and self-prove every probe.
        let hashMismatch = requestDestination.hash != destinationHash

        // ── Probe loop (rnprobe.py:107-199) ────────────────────────────────────────
        var sent = 0
        var replies = 0
        var remaining = options.probes

        while remaining > 0 {
            if isCancelled { return finishCancelled(output) }

            // Python: `if sent > 0: time.sleep(wait)` — N probes incur (N-1) waits.
            if sent > 0 { clock.sleep(options.wait) }

            // Python: `RNS.Packet(request_destination, os.urandom(size)); probe.pack()`.
            // pack() is where the payload is encrypted, with the destination identity and
            // the current ratchet (Packet.py:216 → Destination.py:594-600). Python looks
            // the identity up by the TYPED hash and the ratchet up by the CONSTRUCTED one;
            // that split is reproduced exactly.
            let payload = entropy.randomBytes(size)
            let ratchet = network.currentRatchetKey(for: requestDestination.hash)
            let ciphertext: Data
            do {
                ciphertext = try serverIdentity.encrypt(payload, ratchetPublicKey: ratchet)
            } catch {
                output.writeError("Probe payload could not be encrypted for the destination\n")
                output.flush()
                return .pathTimeout
            }

            let receipt: (any ProbeReceipt)?
            do {
                receipt = try network.transmit(ciphertext: ciphertext, to: requestDestination.hash)
            } catch SendError.mtuExceeded(let packedSize) {
                // Python: rnprobe.py:117-119. The message is rnprobe's own — note the
                // grammar is "exceed", not "exceeds", unlike the one Packet.pack raises.
                output.write("Error: Probe packet size of \(packedSize) bytes exceed MTU of \(Reticulum.mtu) bytes\n")
                output.flush()
                return .mtuExceeded
            } catch {
                receipt = nil
            }
            sent += 1

            // Python: rnprobe.py:124-130.
            var more = ""
            if options.moreOutput {
                if let nextHop = network.nextHop(to: destinationHash) {
                    more += " via " + RNSUtilities.prettyhexrep(nextHop)
                }
                // Python evaluates get_next_hop_if_name TWICE in one expression; calling
                // once is behaviourally identical and halves the RPC traffic.
                if let name = network.nextHopInterfaceDisplayName(for: destinationHash), name != "None" {
                    more += " on " + name
                }
            }

            // Python: rnprobe.py:132 — leading \r, then two literal spaces plus print's
            // end=" " for THREE trailing, no newline. The hash shown is the TYPED one, and
            // `size` is the plaintext size, not the wire size.
            output.write("\rSent probe \(sent) (\(size) bytes) to "
                         + RNSUtilities.prettyhexrep(destinationHash) + more + "   ")
            output.flush()

            // Python: rnprobe.py:134 — recomputed for every probe, after the send, and
            // re-queried (never cached) so a now-known path changes the value.
            deadline = clock.now() + NetworkProbe.effectiveTimeout(
                options.timeout, firstHopTimeout: network.firstHopTimeout(for: destinationHash))

            glyph = 0
            while receipt?.status == .sent && !(clock.now() > deadline) {
                if isCancelled { return finishCancelled(output) }
                clock.sleep(NetworkProbe.pollInterval)
                output.write("\u{08}\u{08}" + NetworkProbe.spinnerGlyphs[glyph] + " ")
                output.flush()
                glyph = (glyph + 1) % NetworkProbe.spinnerGlyphs.count
            }

            if clock.now() > deadline {
                // Python: rnprobe.py:142-143. This branch never inspects receipt.status —
                // a probe delivered exactly as the deadline passes still counts as lost —
                // and it emits no \b\b spinner-clear. 64 spaces here, 58 below.
                output.write("\r" + String(repeating: " ", count: NetworkProbe.longEraseWidth)
                             + "\rProbe timed out\n")
                output.flush()
                outcomes.append(Outcome(index: sent, conclusion: .deadlineExceeded, rtt: nil,
                                        hops: nil, receptionStats: "",
                                        destinationHashMismatch: hashMismatch))
            } else {
                // Python: rnprobe.py:146 — print("\b\b ") overwrites the last glyph.
                output.write("\u{08}\u{08} \n")
                output.flush()

                if let receipt, receipt.status == .delivered {
                    replies += 1
                    let hops = network.hops(to: destinationHash)
                    let plural = hops != 1 ? "s" : ""      // Python: ms = "s" if hops != 1
                    let rtt = receipt.rtt ?? 0
                    let stats = receptionStats(for: receipt, network: network)

                    // Python: rnprobe.py:188-194. print appends its own newline, so the
                    // block ends in a BLANK LINE. The hash here is the CONSTRUCTED
                    // destination's (receipt.destination.hash), which can differ from the
                    // typed hash echoed on the "Sent probe" line.
                    output.write("Valid reply from " + RNSUtilities.prettyhexrep(requestDestination.hash)
                                 + "\nRound-trip time is " + NetworkProbe.rttString(rtt)
                                 + " over \(hops) hop" + plural + stats + "\n\n")
                    output.flush()
                    outcomes.append(Outcome(index: sent, conclusion: .delivered, rtt: rtt,
                                            hops: hops, receptionStats: stats,
                                            destinationHashMismatch: hashMismatch))
                } else {
                    // Python: rnprobe.py:196-197 — the receipt's own timeout won. 58
                    // spaces, and emitted AFTER the \b\b clear line.
                    output.write("\r" + String(repeating: " ", count: NetworkProbe.shortEraseWidth)
                                 + "\rProbe timed out\n")
                    output.flush()
                    outcomes.append(Outcome(index: sent, conclusion: .receiptFailed, rtt: nil,
                                            hops: nil, receptionStats: "",
                                            destinationHashMismatch: hashMismatch))
                }
            }

            remaining -= 1
        }

        // Python: rnprobe.py:201-206. `sent == 0` is only reachable from a direct library
        // call (`probes <= 0`); Python raises ZeroDivisionError there, the port reports a
        // vacuous zero loss rather than trapping. The CLI rejects `-n 0` up front.
        let loss = sent == 0 ? 0.0
            : NetworkProbe.pythonRound((1 - Double(replies) / Double(sent)) * 100, 2)
        output.write("Sent \(sent), received \(replies), packet loss "
                     + NetworkProbe.pythonFloatString(loss) + "%\n")
        output.flush()
        return loss > 0 ? .packetLoss : .ok
    }

    /// Python: `except KeyboardInterrupt: print(""); exit()` — a blank line and status 0.
    private func finishCancelled(_ output: any ProbeOutput) -> Result {
        output.write("\n")
        output.flush()
        return .ok
    }

    /// Python: rnprobe.py:165-186.
    ///
    /// The two branches are deliberately asymmetric in Python — the shared-instance branch
    /// reports Link Quality, the local branch does not — and that asymmetry is reproduced.
    private func receptionStats(for receipt: any ProbeReceipt, network: any ProbeNetwork) -> String {
        var stats = ""
        if network.isConnectedToSharedInstance {
            // Python dereferences receipt.proof_packet.packet_hash with no None guard and
            // raises AttributeError when there is no proof packet; the port emits nothing.
            guard let hash = receipt.proofPacketFullHash else { return "" }
            if let rssi = network.packetRSSI(packetHash: hash),
               let text = NetworkProbe.pythonScalarString(rssi) {
                stats += " [RSSI \(text) dBm]"
            }
            if let snr = network.packetSNR(packetHash: hash),
               let text = NetworkProbe.pythonScalarString(snr) {
                stats += " [SNR \(text) dB]"
            }
            if let quality = network.packetQ(packetHash: hash),
               let text = NetworkProbe.pythonScalarString(quality) {
                stats += " [Link Quality \(text)%]"
            }
        } else if receipt.hasProofPacket {
            // Python reads the plain `Packet.rssi` / `Packet.snr` attributes set by the
            // receiving interface — never the RPC-backed get_rssi() methods. RSSI is an
            // int on the Python side (RNodeInterface.py:878) even though Swift stores a
            // Float, so it is rendered as one; SNR stays a float.
            if let rssi = receipt.proofRssi {
                stats += " [RSSI \(NetworkProbe.pythonIntString(Int(rssi))) dBm]"
            }
            if let snr = receipt.proofSnr {
                stats += " [SNR \(NetworkProbe.pythonFloatString(Double(snr))) dB]"
            }
            // No Link Quality here — deliberate in Python (rnprobe.py:180-186).
        }
        return stats
    }

    // MARK: - Single-shot convenience

    /// Send one probe packet to `destination` and return the `PacketReceipt`.
    ///
    /// Mirrors rnprobe.py:114-121 for a single probe. The payload is **encrypted** with the
    /// destination identity plus the freshest known ratchet, exactly as `Packet.pack()`
    /// does in Python (Packet.py:216 → Destination.py:594-600). `Destination.encrypt(_:)`
    /// is deliberately *not* used: it calls `identity.encrypt(plaintext)` with no ratchet
    /// and would produce a wire-valid but ratchet-blind probe.
    ///
    /// - Parameters:
    ///   - destination: an outbound `.single` destination.
    ///   - size: payload size override; `nil` uses ``size``.
    /// - Returns: the receipt, or `nil` if the packet exceeds the MTU or could not be
    ///   encrypted.
    @discardableResult
    public func send(to destination: Destination, size: Int? = nil) -> PacketReceipt? {
        guard let transport, let identity = destination.identity else { return nil }
        let payload = entropy.randomBytes(size ?? self.size)
        let ratchet = transport.currentRatchetKey(forDestination: destination.hash)
        guard let ciphertext = try? identity.encrypt(payload, ratchetPublicKey: ratchet) else {
            return nil
        }
        let packet = Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: destination.hash,
            data: ciphertext
        )
        // Enforce the MTU through pack() itself. `Packet.rawByteCount` omits the 1-byte
        // context field and is one short of the real packed length.
        guard (try? packet.pack()) != nil else { return nil }
        return try? transport.send(packet)
    }
}
