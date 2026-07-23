import Foundation
import ReticulumSwift

// `rnstatus` — Reticulum Network Stack Status.
//
// Python reference: RNS/Utilities/rnstatus.py (main + program_setup).
//
// This target is deliberately thin: argument parsing, source selection, printing and exit
// codes only. Every rendering decision lives in ``RNStatusRenderer`` in the library, which
// is why the golden output can be asserted from XCTest with no terminal and no daemon.

// MARK: - Argument parsing

let parser = RNStatusApp.makeParser()
let arguments: ParsedArguments
do {
    arguments = try parser.parse(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("\(RNStatusApp.appName): \(error)\n".utf8))
    exit(2)
}

if arguments.wantsHelp {
    print(RNStatusApp.helpText)
    exit(RNStatusApp.Result.ok.rawValue)
}
if arguments.flag("--version") {
    // Python: argparse `version="rnstatus {version}".format(version=RNS.__version__)`.
    print("\(RNStatusApp.appName) \(Reticulum.version)")
    exit(RNStatusApp.Result.ok.rawValue)
}

let verbosity          = arguments.count("--verbose")
let showAll            = arguments.flag("--all")
let announceStats      = arguments.flag("--announce-stats")
let prStats            = arguments.flag("--pr-stats")
let linkStats          = arguments.flag("--link-stats")
let burstFilter        = arguments.flag("--burst")
let trafficTotals      = arguments.flag("--totals")
let sortReverse        = arguments.flag("--reverse")
let jsonOutput         = arguments.flag("--json")
let monitor            = arguments.flag("--monitor")
let detailsRequested   = arguments.flag("-D")
// Python: `if config_entries: discovered_interfaces = True; details = True` (rnstatus.py:178).
let discoveredMode     = arguments.flag("--discovered") || detailsRequested
let remoteHex          = arguments.value("-R")
let managementIdentity = arguments.value("-i")
let remoteTimeout      = arguments.double("-w") ?? RNStatusApp.defaultRemoteTimeout
let monitorInterval    = arguments.double("--monitor-interval") ?? RNStatusApp.defaultMonitorInterval
let nameFilter         = arguments.positionals.first
let configDirectory    = arguments.value("--config").map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }

var options = RNStatusRenderer.Options()
options.showAll       = showAll
options.announceStats = announceStats
options.prStats       = prStats
options.linkStats     = linkStats
options.burstFilter   = burstFilter
options.trafficTotals = trafficTotals
options.nameFilter    = nameFilter
options.sort          = arguments.value("--sort").flatMap { RNStatusApp.Sort(rawValue: $0.lowercased()) }
options.sortReverse   = sortReverse

// MARK: - Terminal helpers

func emit(_ text: String) {
    FileHandle.standardOutput.write(Data(text.utf8))
}

/// Python: `print("\r" + 58 spaces + "\r", end="")` then the banner, `end=" "`, flushed.
/// Suppressed entirely under `-j`, which doubles as Python's `no_output`.
func progressBanner(_ text: String) {
    guard !jsonOutput else { return }
    emit(RNStatusApp.eraseSequence + text + " ")
}

func fail(_ message: String, _ code: RNStatusApp.Result) -> Never {
    print(message)
    exit(code.rawValue)
}

// Python: `except KeyboardInterrupt: print(""); exit()` — exit code 0.
signal(SIGINT) { _ in
    FileHandle.standardOutput.write(Data("\n".utf8))
    exit(RNStatusApp.Result.ok.rawValue)
}

// MARK: - Stack

// Python: `if remote: require_shared = False else: require_shared = True` (rnstatus.py:159).
// Local status only ever reports on a daemon that is already running; remote status stands
// up its own stack in order to make the link.
let requireSharedInstance = (remoteHex == nil)

let connection: InstanceConnection
do {
    connection = try InstanceConnection.attach(configDirectory: configDirectory,
                                               requireSharedInstance: requireSharedInstance,
                                               logLevel: .error,
                                               synthesizeInterfaces: !requireSharedInstance)
} catch {
    fail("No shared RNS instance available to get status from", .noSharedInstance)
}

// Python: `loglevel=3+verbosity`. This has to happen AFTER start(), because
// `Reticulum.applyConfig` overwrites globalLogLevel from the config file's `loglevel`.
if let level = Reticulum.LogLevel(rawValue: RNStatusApp.baseLogLevel + verbosity) {
    Reticulum.globalLogLevel = level
}

// MARK: - Discovered-interface mode (-d / -D)

if discoveredMode {
    let storage = InstanceConnection.storagePath(for: connection.configDirectory)
    let discoveryPath = storage
        .appendingPathComponent("discovery")
        .appendingPathComponent("interfaces")
        .path
    let discovery = InterfaceDiscovery(storagePath: discoveryPath)

    func renderDiscovered() -> String {
        // NOTE: listing is not a pure read — it unlinks discovery files older than seven
        // days or of a type that is no longer discoverable, exactly as Python's
        // `list_discovered_interfaces()` does. Under -m it re-lists every refresh, because
        // Python re-enters program_setup each interval.
        let discovered = discovery.listDiscoveredInterfaces()
        let renderer = RNStatusRenderer(options: options)
        if jsonOutput {
            // Python prints the blank line first, unconditionally, then the JSON array —
            // and does NOT apply the positional name filter in this mode.
            return "\n" + RNStatusJSON.encodeDiscovered(discovered) + "\n"
        }
        return detailsRequested ? renderer.renderDiscoveredDetails(discovered)
                                : renderer.renderDiscoveredTable(discovered)
    }

    if monitor {
        while true {
            // Python renders into a StringIO first, then clears and prints (rnstatus.py:741).
            let started = Date().timeIntervalSince1970
            let rendered = renderDiscovered()
            emit(RNStatusApp.clearScreen)
            emit(rendered)
            let elapsed = Date().timeIntervalSince1970 - started
            Thread.sleep(forTimeInterval: max(monitorInterval - elapsed, RNStatusApp.minimumMonitorSleep))
        }
    }
    emit(renderDiscovered())
    connection.stop()
    exit(RNStatusApp.Result.ok.rawValue)
}

// MARK: - Status source

/// Everything needed to render one refresh.
struct Snapshot {
    let stats: MsgPack.Value
    let linkCount: Int?
}

var remoteQuery: RemoteStatusQuery?
var remoteIdentityHash = Data()

if let remoteHex {
    // Python: rnstatus.py:311-333 — every failure here prints the message and exits 20.
    guard let identityPath = managementIdentity else {
        fail("Remote management requires an identity file. Use -i to specify the path to a management identity.",
             .remoteError)
    }
    guard remoteHex.count == RNStatusApp.destinationHexLength else {
        fail("Destination length is invalid, must be \(RNStatusApp.destinationHexLength) hexadecimal characters "
             + "(\(RNStatusApp.destinationHexLength / 2) bytes).", .remoteError)
    }
    guard let identityHash = Data(hex: remoteHex) else {
        fail("Invalid destination entered. Check your input.", .remoteError)
    }
    let expanded = URL(fileURLWithPath: (identityPath as NSString).expandingTildeInPath)
    guard let identity = Identity.fromFile(expanded) else {
        fail("Could not load management identity from \(identityPath)", .remoteError)
    }
    remoteIdentityHash = identityHash
    remoteQuery = RemoteStatusQuery(transport: connection.reticulum.transport,
                                    destinationHash: RemoteStatusQuery.destinationHash(forIdentityHash: identityHash),
                                    managementIdentity: identity,
                                    timeout: remoteTimeout)
}

func snapshot() -> Snapshot? {
    if let remoteQuery {
        do {
            try remoteQuery.ensurePath(progress: progressBanner)
        } catch {
            // Python only prints and exits when no_output is false, so `-j -R` spins
            // forever. DELIBERATE DIVERGENCE: exit 12 unconditionally.
            if !jsonOutput { emit(RNStatusApp.eraseSequence) }
            print("Path request timed out")
            exit(RNStatusApp.Result.pathRequestTimeout.rawValue)
        }
        do {
            let (stats, linkCount) = try remoteQuery.requestBlocking(includeLinkStats: linkStats,
                                                                     progress: progressBanner)
            emit(RNStatusApp.eraseSequence)   // rnstatus.py:151 — not guarded by no_output
            return Snapshot(stats: stats, linkCount: linkCount)
        } catch RemoteStatusQuery.QueryError.linkTimedOut {
            if !jsonOutput { emit(RNStatusApp.eraseSequence); print("The link timed out, exiting now") }
            exit(RNStatusApp.Result.linkFailed.rawValue)
        } catch RemoteStatusQuery.QueryError.linkClosedByServer {
            if !jsonOutput { emit(RNStatusApp.eraseSequence); print("The link was closed by the server, exiting now") }
            exit(RNStatusApp.Result.linkFailed.rawValue)
        } catch RemoteStatusQuery.QueryError.linkClosedUnexpectedly {
            if !jsonOutput { emit(RNStatusApp.eraseSequence); print("Link closed unexpectedly, exiting now") }
            exit(RNStatusApp.Result.linkFailed.rawValue)
        } catch RemoteStatusQuery.QueryError.requestFailed {
            if !jsonOutput {
                emit(RNStatusApp.eraseSequence)
                print("The remote status request failed. Likely authentication failure.")
            }
            return nil            // Python falls through to "Could not get RNS status…", exit 2
        } catch {
            return nil
        }
    }

    // Python: `reticulum.get_link_count()` / `get_interface_stats()`, both wrapped in a
    // bare `except: pass` that leaves the value at None.
    var linkCount: Int? = nil
    if let rpc = connection.rpc {
        if linkStats { linkCount = try? rpc.linkCount() }
        guard let stats = try? rpc.interfaceStats() else { return nil }
        return Snapshot(stats: stats, linkCount: linkCount)
    }
    if linkStats { linkCount = connection.reticulum.transport.getLinkCount() }
    return Snapshot(stats: InterfaceStatsPayload.build(connection.reticulum.transport), linkCount: linkCount)
}

// MARK: - Render

func renderOnce() -> (text: String, code: RNStatusApp.Result) {
    guard let snapshot = snapshot(), let decoded = RNStatusStats(snapshot.stats) else {
        // Python: rnstatus.py:677-685. The remote form prints the -R argument's bytes
        // (`identity_hash`), not the derived management-destination hash.
        guard remoteHex == nil else {
            return ("Could not get RNS status from remote transport instance "
                    + RNSUtilities.prettyhexrep(remoteIdentityHash) + "\n", .noStatus)
        }
        return ("Could not get RNS status\n", .noStatus)
    }

    if jsonOutput {
        return (RNStatusJSON.encode(RNStatusJSON.normaliseStats(snapshot.stats)) + "\n", .ok)
    }

    let renderer = RNStatusRenderer(options: options)
    return (renderer.render(stats: decoded, linkCount: snapshot.linkCount), .ok)
}

if monitor {
    while true {
        let started = Date().timeIntervalSince1970
        let rendered = renderOnce()
        emit(RNStatusApp.clearScreen)
        emit(rendered.text)
        let elapsed = Date().timeIntervalSince1970 - started
        Thread.sleep(forTimeInterval: max(monitorInterval - elapsed, RNStatusApp.minimumMonitorSleep))
    }
}

let rendered = renderOnce()
emit(rendered.text)
remoteQuery?.teardown()
connection.stop()
exit(rendered.code.rawValue)
