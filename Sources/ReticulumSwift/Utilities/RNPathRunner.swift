import Foundation

// MARK: - Options

/// Everything `main()` hands to `program_setup` (rnpath.py:101-104), one field per argument.
public struct RNPathOptions: Equatable {

    /// `--config` — a Reticulum *config directory*, not a config file.
    public var configDirectory: URL?
    /// `-t` / `--table`
    public var table: Bool = false
    /// `-m` / `--max`
    public var maxHops: UInt8?
    /// `-r` / `--rates`
    public var rates: Bool = false
    /// `-d` / `--drop`
    public var drop: Bool = false
    /// `-D` / `--drop-announces`
    public var dropAnnounces: Bool = false
    /// `-x` / `--drop-via`
    public var dropVia: Bool = false
    /// `-w` — spinner deadline in the default mode. Default 15.
    public var timeout: TimeInterval = RNPathApp.defaultTimeout
    /// `-R` — transport identity hash of the remote instance to manage.
    public var remote: String?
    /// `-i` — identity file used to authenticate remote management.
    public var managementIdentityPath: String?
    /// `-W` — timeout for the path request toward the remote instance. Default 15.
    public var remoteTimeout: TimeInterval = RNPathApp.defaultTimeout
    /// `-b` / `--blackholed`
    public var blackholed: Bool = false
    /// `-B` / `--blackhole`
    public var blackhole: Bool = false
    /// `-U` / `--unblackhole`
    public var unblackhole: Bool = false
    /// `--duration`, in **hours**. Python treats `0` as falsy, so `--duration 0` means
    /// "indefinite", not "expire immediately".
    public var blackholeDuration: Double?
    /// `--reason`
    public var blackholeReason: String?
    /// `-p` / `--blackholed-list`
    public var blackholedList: Bool = false
    /// `-j` / `--json` — read only by `-t` and `-r`.
    public var json: Bool = false
    /// First positional. Overloaded per mode: a destination hash for `-t`/`-r`/`-d`/`-x`
    /// and the default mode, an identity hash for `-B`/`-U`/`-p`, and a plain substring
    /// *filter* for `-b`.
    public var destination: String?
    /// Second positional — the filter for the remote blackhole list view.
    public var listFilter: String?
    /// `-v`, repeatable. Log level is `clamp(3 + verbosity, 0, 8)`.
    public var verbosity: Int = 0
    /// `program_setup(no_output=…)`. The CLI never sets it; kept because it gates a
    /// dozen prints in the original and the runner reproduces that gating.
    public var noOutput: Bool = false

    public init() {}

    /// Python: the `main()` guard at rnpath.py:511.
    ///
    /// ```
    /// if not args.drop_announces and not args.table and not args.rates
    ///    and not args.destination and not args.drop_via and not args.blackholed:
    /// ```
    ///
    /// Note which flags are *absent* from it: `-B`, `-U`, `-d`, `-p`, `-j`, `-m`, `-R`,
    /// `-i`, `-w`, `-W` and `-v` do not suppress the help block on their own — though the
    /// first four all need a positional destination, which does.
    public var shouldPrintHelp: Bool {
        !dropAnnounces && !table && !rates && destination == nil && !dropVia && !blackholed
    }

    /// Python's blackhole filter-source split (rnpath.py:194-197).
    ///
    /// The *fetch* source is chosen by `blackholed` first, but the *filter* is chosen by
    /// `blackholedList`. So `rnpath -b -p <x> <y>` fetches locally yet filters on `<y>`,
    /// and `<x>` is ignored entirely.
    public var activeBlackholeFilter: String? {
        blackholedList ? listFilter : destination
    }
}

// MARK: - Path resolution seam

/// The three `RNS.Transport` calls the default path-request mode makes.
///
/// Python keeps these **local** even when attached to a shared instance — only
/// `get_next_hop` / `get_next_hop_if_name` go over RPC (rnpath.py:447-474). Splitting them
/// out here keeps that asymmetry explicit, and lets the spinner loop be driven from tests
/// without a stack.
public protocol RNPathPathResolver: AnyObject {
    func hasPath(to destinationHash: Data) -> Bool
    func requestPath(for destinationHash: Data)
    /// Python's `hops_to` returns `PATHFINDER_M` (128) for an unknown destination;
    /// Swift returns `nil`, and the runner maps that to ``RNPathApp/unknownHops``.
    func hopsTo(_ destinationHash: Data) -> UInt8?
}

/// The production ``RNPathPathResolver``, backed by a live ``Transport``.
public final class TransportPathResolver: RNPathPathResolver {
    private let transport: Transport

    public init(transport: Transport) { self.transport = transport }

    public func hasPath(to destinationHash: Data) -> Bool { transport.hasPath(to: destinationHash) }
    public func requestPath(for destinationHash: Data) { try? transport.requestPath(for: destinationHash) }
    public func hopsTo(_ destinationHash: Data) -> UInt8? { transport.hopsTo(destinationHash) }
}

// MARK: - Runner

/// `program_setup` (rnpath.py:101-477) — the mode dispatcher.
///
/// Reproduces the `if`/`elif` chain in order, because the order is observable: `rnpath -t -d
/// <hash>` shows the table and drops nothing, and `rnpath -b -B <hash>` lists rather than
/// blackholes.
///
/// Never calls `exit()` or `print()`. Output goes to two sinks:
///
/// - `output` — Python's `print(x)`: one line, terminated.
/// - `progress` — Python's `print(x, end="")` / `end=" "`: raw, unterminated, flushed.
///   The trailing space `end=" "` adds is baked into the strings passed here.
///
/// The remote (`-R` / `-p`) half is injected as closures rather than a `Link`, so every
/// branch below is drivable from XCTest.
public final class RNPathRunner {

    /// Issues one request over the already-established management link and returns the raw
    /// response body. Python: `remote_link.request("/path", data=[...])` plus the
    /// `while not receipt.concluded()` spin.
    public typealias RemoteRequestHandler = (_ path: String, _ value: MsgPack.Value) throws -> Data

    /// Establishes a *fresh* blackhole link and issues `/list`.
    ///
    /// Returns `nil` when the response was not a map — Python's `if type(response) == dict`
    /// gate — and an empty array when the remote genuinely has nothing blackholed, which
    /// Python accepts and then reports as "No blackholed identity data available".
    public typealias BlackholeListFetcher = () throws -> [RNPathBlackholeEntry]?

    private let options: RNPathOptions
    private let management: RNPathManagementSource
    private let resolver: RNPathPathResolver?
    private let remoteLinkPresent: Bool
    private let remoteRequest: RemoteRequestHandler?
    private let blackholeListFetch: BlackholeListFetcher?
    private let now: () -> Date
    private let sleep: (TimeInterval) -> Void
    private let output: (String) -> Void
    private let progressSink: ((String) -> Void)?
    private let spinner: ((String) -> Void)?

    public init(options: RNPathOptions,
                management: RNPathManagementSource,
                resolver: RNPathPathResolver? = nil,
                remoteLinkPresent: Bool = false,
                remoteRequest: RemoteRequestHandler? = nil,
                blackholeListFetch: BlackholeListFetcher? = nil,
                now: @escaping () -> Date = Date.init,
                sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
                output: @escaping (String) -> Void,
                progress: ((String) -> Void)? = nil,
                spinner: ((String) -> Void)? = nil) {
        self.options = options
        self.management = management
        self.resolver = resolver
        self.remoteLinkPresent = remoteLinkPresent
        self.remoteRequest = remoteRequest
        self.blackholeListFetch = blackholeListFetch
        self.now = now
        self.sleep = sleep
        self.output = output
        self.progressSink = progress
        self.spinner = spinner
    }

    // MARK: Sinks

    /// Python's `if not no_output: print(x, end=…)`.
    private func progress(_ text: String) {
        guard !options.noOutput else { return }
        progressSink?(text)
    }

    /// The three success-path clear strings at rnpath.py:162, 265 and 319 are emitted
    /// **ungated** by `no_output`, unlike every failure-path print. Routing them through a
    /// gated sink would drop them and mis-align the following output.
    private func progressUngated(_ text: String) {
        progressSink?(text)
    }

    /// `print(output_rst_str, end=""); print(message)` — the shape every remote failure uses.
    private func resetThen(_ message: String) {
        progress(RNPathApp.outputResetString)
        guard !options.noOutput else { return }
        output(message)
    }

    // MARK: Entry point

    /// Run the selected mode and return its exit code.
    public func run() -> RNPathApp.Result {
        // Python: rnpath.py:129, 205, 224, 242, 295, 379, 389, 410, 431 — a strict if/elif
        // chain whose order is user-visible.
        if options.blackholed || options.blackholedList { return runBlackholeList() }
        if options.blackhole      { return runBlackholeAdd() }
        if options.unblackhole    { return runBlackholeLift() }
        if options.table          { return runTable() }
        if options.rates          { return runRates() }
        if options.dropAnnounces  { return runDropAnnounceQueues() }
        if options.drop           { return runDropPath() }
        if options.dropVia        { return runDropVia() }
        return runPathRequest()
    }

    // MARK: - Blackhole listing (-b / -p)

    private func runBlackholeList() -> RNPathApp.Result {
        var list: [RNPathBlackholeEntry]?

        // Python: `if blackholed:` wins the FETCH even when -p is also given (rnpath.py:131).
        if options.blackholed {
            if remoteLinkPresent {
                resetThen("Listing blackholed identities on remote instances not yet implemented")
                return .notImplemented
            }
            do {
                list = try management.blackholedIdentities()
            } catch {
                output("Could not get blackholed identities from RNS instance: \(error)")
                return .setupFailure
            }
        } else {
            // -p: the FIRST positional is the remote's identity hash, parsed with the
            // "Hash …" wording; failures print the bare message and exit 20.
            do {
                _ = try RNPathApp.parseHash(options.destination ?? "")
            } catch let error as RNPathApp.ParseError {
                output(error.message)
                return .setupFailure
            } catch {
                output("\(error)")
                return .setupFailure
            }

            guard let fetch = blackholeListFetch else {
                resetThen("The remote request failed.")
                return .remoteFailure
            }
            progress(RNPathApp.outputResetString)
            progress("Sending request... ")
            do {
                guard let fetched = try fetch() else {
                    resetThen("The remote request failed.")
                    return .remoteFailure
                }
                list = fetched
                // Python: rnpath.py:162 — ungated.
                progressUngated(RNPathApp.outputResetString)
            } catch let error as RNPathRemoteClient.RemoteError {
                return report(error)
            } catch {
                resetThen("The remote request failed.")
                return .remoteFailure
            }
        }

        // Python: `if not blackholed_list:` catches both None and an empty dict, and the
        // message is NOT gated on no_output.
        guard let entries = list, !entries.isEmpty else {
            output("No blackholed identity data available")
            return .setupFailure
        }

        let reference = now().timeIntervalSince1970
        let localHash = management.localTransportIdentityHash
        let filter = options.activeBlackholeFilter

        for entry in entries {
            if let filter, !filter.isEmpty {
                // Python matches against filter_str, which is NOT the printed line.
                let haystack = RNPathFormatter.blackholeFilterString(
                    entry, now: reference, localTransportIdentityHash: localHash)
                guard RNPathFormatter.filterMatches(filter, in: haystack) else { continue }
            }
            output(RNPathFormatter.blackholeLine(entry, now: reference,
                                                 localTransportIdentityHash: localHash))
        }
        return .ok
    }

    // MARK: - Blackhole add (-B)

    private func runBlackholeAdd() -> RNPathApp.Result {
        if remoteLinkPresent {
            resetThen("Blackholing identity on remote instances not yet implemented")
            return .notImplemented
        }

        let raw = options.destination ?? ""
        do {
            let identityHash = try RNPathApp.parseHash(raw)
            // Python: `until = time.time()+duration*60*60 if blackhole_duration else None`
            // — `--duration 0` is falsy, so it means "indefinitely".
            let until: TimeInterval? = {
                guard let hours = options.blackholeDuration, hours != 0 else { return nil }
                return now().timeIntervalSince1970 + hours * 60 * 60
            }()
            let result = try management.blackholeIdentity(identityHash, until: until,
                                                          reason: options.blackholeReason)
            // The confirmations echo the RAW hex as typed, not prettyhexrep.
            if result == true      { output("Blackholed identity \(raw)") }
            else if result == nil  { output("Identity \(raw) already blackholed") }
            else                   { output("Could not blackhole identity \(raw)") }
            return .ok
        } catch {
            output("Could not blackhole identity: \(message(for: error))")
            return .setupFailure
        }
    }

    // MARK: - Blackhole lift (-U)

    private func runBlackholeLift() -> RNPathApp.Result {
        if remoteLinkPresent {
            // sic — rnpath.py:228 reuses the -B wording verbatim, with no "Unblackholing"
            // variant.
            resetThen("Blackholing identity on remote instances not yet implemented")
            return .notImplemented
        }

        let raw = options.destination ?? ""
        do {
            let identityHash = try RNPathApp.parseHash(raw)
            let result = try management.unblackholeIdentity(identityHash)
            if result == true      { output("Lifted blackhole for identity \(raw)") }
            else if result == nil  { output("Identity \(raw) not blackholed") }
            else                   { output("Could not unblackhole identity \(raw)") }
            return .ok
        } catch {
            output("Could not unblackhole identity: \(message(for: error))")
            return .setupFailure
        }
    }

    // MARK: - Path table (-t)

    private func runTable() -> RNPathApp.Result {
        var destinationHash: Data?
        if let hex = options.destination {
            do { destinationHash = try RNPathApp.parseDestination(hex) }
            catch { output(message(for: error)); return .generalFailure }
        }

        var table: [RNPathTableEntry]
        if !remoteLinkPresent {
            do {
                // Python sorts by (interface, hops); the interface string must already be
                // the display form, since it is the primary sort key.
                table = RNPathTableEntry.sortedForDisplay(try management.pathTable(maxHops: options.maxHops))
            } catch {
                output("\(message(for: error))")
                return .generalFailure
            }
        } else {
            progress(RNPathApp.outputResetString)
            progress("Sending request... ")
            let payload = RNPathRemoteClient.pathRequestPayload(command: RNPathApp.commandTable,
                                                               destinationHash: destinationHash,
                                                               maxHops: options.maxHops)
            do {
                let response = try requireRemoteRequest()(RNPathApp.pathRequestPath, payload)
                // Python: `if response:` — an EMPTY list is falsy, so a remote with no paths
                // is reported as a failure, indistinguishably from an ACL rejection or a
                // request timeout. Faithful, if confusing.
                guard let decoded = RNPathRemoteClient.decodePathTable(response), !decoded.isEmpty else {
                    resetThen("The remote request failed. Likely authentication failure.")
                    return .remoteFailure
                }
                // The remote table is NOT re-sorted — rnpath.py:254's sort is local-only.
                table = decoded
                progressUngated(RNPathApp.outputResetString)   // rnpath.py:265, ungated
            } catch let error as RNPathRemoteClient.RemoteError {
                return report(error)
            } catch {
                resetThen("The remote request failed. Likely authentication failure.")
                return .remoteFailure
            }
        }

        if options.json {
            // Python quirk: the destination filter is NOT applied in JSON mode for the local
            // case (max_hops IS). Reproduced.
            output(RNPathFormatter.pathTableJSON(table))
            return .ok
        }

        var displayed = 0
        for entry in table where destinationHash == nil || destinationHash == entry.destinationHash {
            displayed += 1
            output(RNPathFormatter.pathTableLine(entry))
        }
        if destinationHash != nil, displayed == 0 {
            output("No path known")
            return .generalFailure
        }
        return .ok
    }

    // MARK: - Rate table (-r)

    private func runRates() -> RNPathApp.Result {
        var destinationHash: Data?
        if let hex = options.destination {
            do { destinationHash = try RNPathApp.parseDestination(hex) }
            catch { output(message(for: error)); return .generalFailure }
        }

        var table: [RNPathRateEntry]
        if !remoteLinkPresent {
            do { table = try management.rateTable() }
            catch { output("\(message(for: error))"); return .generalFailure }
        } else {
            progress(RNPathApp.outputResetString)
            progress("Sending request... ")
            // Python: ["rates", destination_hash] — TWO elements, no max_hops.
            let payload = RNPathRemoteClient.pathRequestPayload(command: RNPathApp.commandRates,
                                                               destinationHash: destinationHash,
                                                               maxHops: nil,
                                                               includeMaxHops: false)
            do {
                let response = try requireRemoteRequest()(RNPathApp.pathRequestPath, payload)
                guard let decoded = RNPathRemoteClient.decodeRateTable(response), !decoded.isEmpty else {
                    resetThen("The remote request failed. Likely authentication failure.")
                    return .remoteFailure
                }
                table = decoded
                progressUngated(RNPathApp.outputResetString)   // rnpath.py:319, ungated
            } catch let error as RNPathRemoteClient.RemoteError {
                return report(error)
            } catch {
                resetThen("The remote request failed. Likely authentication failure.")
                return .remoteFailure
            }
        }

        // Python: this sort applies in BOTH the local and the remote case (rnpath.py:326) —
        // unlike the path table's, which is local-only.
        table = RNPathRateEntry.sortedByLast(table)

        if options.json {
            output(RNPathFormatter.rateTableJSON(table))
            return .ok
        }

        // Python: the `len(table) == 0` check lives inside the non-JSON else, so `-r -j` on
        // an empty table prints `[]` rather than this message.
        if table.isEmpty {
            output("No information available")
            return .ok
        }

        let reference = now().timeIntervalSince1970
        var displayed = 0
        for entry in table where destinationHash == nil || destinationHash == entry.destinationHash {
            displayed += 1
            if let line = RNPathFormatter.rateLine(entry, now: reference) {
                output(line)
            } else {
                // Python: a per-entry exception prints two lines and CONTINUES — contrast
                // the blackhole loop, whose single try wraps the whole thing and aborts.
                output(RNPathFormatter.rateErrorLine(entry))
                output(RNPathFormatter.emptyTimestampsErrorMessage)
            }
        }
        if destinationHash != nil, displayed == 0 {
            output("No information available")
            return .generalFailure
        }
        return .ok
    }

    // MARK: - Drop announce queues (-D)

    private func runDropAnnounceQueues() -> RNPathApp.Result {
        if remoteLinkPresent {
            resetThen("Dropping announce queues on remote instances not yet implemented")
            return .notImplemented
        }
        // Python prints this BEFORE the call, and ignores the return value.
        output("Dropping announce queues on all interfaces...")
        try? management.dropAnnounceQueues()
        return .ok
    }

    // MARK: - Drop path (-d)

    private func runDropPath() -> RNPathApp.Result {
        if remoteLinkPresent {
            resetThen("Dropping path on remote instances not yet implemented")
            return .notImplemented
        }
        guard let destinationHash = parsedDestinationOrFailure() else { return .generalFailure }

        // Python does not catch here; a thrown RPC error is reported as "unable to drop",
        // which is the same user-visible outcome.
        let dropped = (try? management.dropPath(destinationHash)) ?? false
        if dropped {
            output("Dropped path to " + RNSUtilities.prettyhexrep(destinationHash))
            return .ok
        }
        output("Unable to drop path to " + RNSUtilities.prettyhexrep(destinationHash) + ". Does it exist?")
        return .generalFailure
    }

    // MARK: - Drop all via (-x)

    private func runDropVia() -> RNPathApp.Result {
        if remoteLinkPresent {
            // sic — "yet not implemented", verbatim from rnpath.py:414.
            resetThen("Dropping all paths via specific transport instance on remote instances yet not implemented")
            return .notImplemented
        }
        guard let transportHash = parsedDestinationOrFailure() else { return .generalFailure }

        // Python: `if reticulum.drop_all_via(hash):` — an Int, and 0 is falsy.
        let dropped = (try? management.dropAllVia(transportHash)) ?? 0
        if dropped != 0 {
            output("Dropped all paths via " + RNSUtilities.prettyhexrep(transportHash))
            return .ok
        }
        output("Unable to drop paths via " + RNSUtilities.prettyhexrep(transportHash)
               + ". Does the transport instance exist?")
        return .generalFailure
    }

    // MARK: - Default: path request

    private func runPathRequest() -> RNPathApp.Result {
        if remoteLinkPresent {
            // sic — no "yet" in this one (rnpath.py:435).
            resetThen("Requesting paths on remote instances not implemented")
            return .notImplemented
        }
        guard let destinationHash = parsedDestinationOrFailure() else { return .generalFailure }

        guard let resolver else {
            output(RNPathApp.lineClearString + "Path not found")
            return .generalFailure
        }

        if !resolver.hasPath(to: destinationHash) {
            // Python requests the path FIRST, then prints (rnpath.py:448-450).
            resolver.requestPath(for: destinationHash)
            // Two literal trailing spaces plus argparse's end=" " → three in total.
            progress("Path to " + RNSUtilities.prettyhexrep(destinationHash) + " requested   ")
        }

        var index = 0
        let deadline = now().timeIntervalSince1970 + options.timeout
        while !resolver.hasPath(to: destinationHash), now().timeIntervalSince1970 < deadline {
            sleep(0.1)
            spinner?("\u{8}\u{8}" + String(RNPathApp.spinnerSymbols[index % RNPathApp.spinnerSymbols.count]) + " ")
            index = (index + 1) % RNPathApp.spinnerSymbols.count
        }

        guard resolver.hasPath(to: destinationHash) else {
            output(RNPathApp.lineClearString + "Path not found")
            return .generalFailure
        }

        // hops_to is LOCAL even when attached to a shared instance; get_next_hop is not.
        let hops = resolver.hopsTo(destinationHash) ?? RNPathApp.unknownHops

        let nextHopBytes: Data?
        do { nextHopBytes = try management.nextHop(for: destinationHash) }
        catch {
            output(RNPathApp.lineClearString + "Error: Invalid path data returned")
            return .generalFailure
        }

        // Python's next hop is never None for a known path — Transport.py:1796 stores the
        // destination hash itself for a direct peer, where Swift stores nil. Substitute it
        // rather than reporting invalid path data.
        let nextHop = nextHopBytes ?? destinationHash

        // Python's local get_next_hop_if_name is str(...), so an unknown interface is the
        // literal string "None", never a real None.
        let interfaceName = ((try? management.nextHopInterfaceName(for: destinationHash)) ?? nil) ?? "None"

        output(RNPathFormatter.pathFoundLine(destinationHash: destinationHash,
                                             hops: hops,
                                             nextHop: nextHop,
                                             interfaceName: interfaceName))
        return .ok
    }

    // MARK: - Helpers

    /// The inline destination parse shared by `-d`, `-x` and the default mode: the
    /// "Destination …" wording, and `sys.exit(1)` rather than 20.
    private func parsedDestinationOrFailure() -> Data? {
        do { return try RNPathApp.parseDestination(options.destination ?? "") }
        catch { output(message(for: error)); return nil }
    }

    private func requireRemoteRequest() throws -> RemoteRequestHandler {
        guard let remoteRequest else { throw RNPathRemoteClient.RemoteError.requestFailed }
        return remoteRequest
    }

    /// Python's teardown-reason → exit-code mapping (rnpath.py:61-75, 53-57).
    private func report(_ error: RNPathRemoteClient.RemoteError) -> RNPathApp.Result {
        resetThen(error.message)
        return error.result
    }

    /// `str(e)` — ``RNPathApp/ParseError`` carries the exact Python wording; anything else
    /// falls back to the Swift description.
    private func message(for error: Error) -> String {
        if let parseError = error as? RNPathApp.ParseError { return parseError.message }
        if let described = error as? CustomStringConvertible { return described.description }
        return "\(error)"
    }
}
