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

// MARK: - DiscoveryStampGenerator

/// Finds the proof-of-work stamp a discovery announce carries.
///
/// The publish-side counterpart to `DiscoveryStampValidator`, and injected for the same
/// reason: Python's announcer imports `LXMF.LXStamper` (`Discovery.py:52`), while in this port
/// LXMFSwift depends on ReticulumSwift rather than the other way round. Wrap `LXStamper` to
/// conform in production; in tests, return a fixed stamp so a suite never pays for the work.
///
/// Kept separate from the validator so each side declares only what it needs—a node that only
/// discovers never generates, and a test double for one isn't forced to implement the other.
public protocol DiscoveryStampGenerator {
    /// Search for a stamp over `material` reaching at least `targetCost` leading zero bits,
    /// against a work block expanded over `expandRounds` HKDF rounds.
    ///
    /// - Returns: the stamp, or `nil` when none was found. A `nil` aborts the announce.
    func generateStamp(material: Data, targetCost: Int, expandRounds: Int) -> Data?
}

// MARK: - InterfaceAnnouncer

/// Announces this node's own interfaces as discoverable endpoints.
///
/// The publish half of interface discovery, mirroring Python's `Discovery.InterfaceAnnouncer`.
/// The receive half—`InterfaceAnnounceHandler` and `InterfaceDiscovery`—has been complete since
/// RNS 1.4.0, so this port could find other people's endpoints and never offer its own.
///
/// One interface announces per pass, the one that's been waiting longest, so a node with
/// several discoverable interfaces spreads its announces across intervals rather than emitting
/// them in a burst (`Discovery.py:82-90`).
///
/// **Two of upstream's seven discoverable types can't reach the wire.** `KISSInterface` is in
/// `DISCOVERABLE_INTERFACE_TYPES` but no `KISSInterface` sets `supports_discovery`, and Weave's
/// only assignment lands on the WDCL serial transport object rather than the interface
/// (`WeaveInterface.py:102`, inside `class WDCL`). Their branches are ported because
/// `announceData(for:)` is reachable directly, but the job never selects either, which is what
/// a Python node does too.
public final class InterfaceAnnouncer {

    // MARK: - Constants

    /// Python: `InterfaceAnnouncer.JOB_INTERVAL`—how often the job wakes, not how often an
    /// interface announces.
    public static let jobInterval: TimeInterval = 60

    /// Python: `InterfaceAnnouncer.DEFAULT_STAMP_VALUE`, moved 14 → 16 in RNS 1.5.0.
    public static let defaultStampValue: Int = 16

    /// Python: `InterfaceAnnouncer.WORKBLOCK_EXPAND_ROUNDS`.
    public static let workblockExpandRounds: Int = 20

    /// Python: `InterfaceAnnouncer.DISCOVERABLE_INTERFACE_TYPES`, matched against the
    /// *published* type name so a spawned TCP client is judged as the `TCPClientInterface` it
    /// presents as.
    public static let discoverableInterfaceTypes: Set<String> = [
        "BackboneInterface", "TCPServerInterface", "TCPClientInterface",
        "RNodeInterface", "WeaveInterface", "I2PInterface", "KISSInterface",
    ]

    /// Python: `Discovery.APP_NAME`.
    public static let appName = "rnstransport"

    // MARK: - State

    /// The destination discovery announces are emitted from.
    ///
    /// Owned by the network identity when
    /// one is configured, so a segmented network's announces are attributable to the segment
    /// (`Discovery.py:64-67`).
    public let discoveryDestination: Destination

    private weak var transport: Transport?
    private let stampGenerator: any DiscoveryStampGenerator

    /// Keyed by the hash of the packed info, so an unchanged announce never pays for the work
    /// twice (`Discovery.py:210-212`).
    private var stampCache: [Data: Data] = [:]

    private let lock = NSLock()
    private var isRunning = false
    /// Incremented on every `start()`, so a `stop()` + `start()` can't leave two loops running.
    ///
    /// The same shape as `BlackholeUpdater`.
    private var generation = 0

    // MARK: - Init

    /// - Returns: `nil` when the transport has no identity to announce from, which is the state
    ///   before `Reticulum` finishes starting.
    public init?(transport: Transport, stampGenerator: any DiscoveryStampGenerator) {
        guard let identity = transport.networkIdentity ?? transport.transportIdentity,
              let destination = try? Destination(identity: identity, direction: .in, kind: .single,
                                                 appName: Self.appName,
                                                 aspects: ["discovery", "interface"])
        else { return nil }

        self.transport = transport
        self.stampGenerator = stampGenerator
        self.discoveryDestination = destination
    }

    // MARK: - Lifecycle

    /// Starts the periodic announce loop.
    public func start() {
        lock.lock()
        guard !isRunning else { lock.unlock(); return }
        isRunning = true
        generation &+= 1
        let myGeneration = generation
        lock.unlock()

        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.runJob(generation: myGeneration)
        }
    }

    /// Stops the periodic announce loop.
    public func stop() {
        lock.lock(); isRunning = false; lock.unlock()
    }

    private func runJob(generation myGeneration: Int) {
        while true {
            // Python sleeps *before* its first pass (`Discovery.py:78-79`), so a node that has
            // just started doesn't announce into a transport whose interfaces are still coming
            // up.
            Thread.sleep(forTimeInterval: Self.jobInterval)

            lock.lock()
            let keepRunning = isRunning && generation == myGeneration
            lock.unlock()
            guard keepRunning else { return }

            tick()
        }
    }

    // MARK: - Job

    /// One pass of the job loop: announce the interface that's been waiting longest, if any.
    ///
    /// Never throws. Python wraps the whole body in `try/except` and logs (`Discovery.py:93-95`),
    /// because a single interface with a broken `location_cmd` must not stop the loop that
    /// serves every other interface.
    public func tick() {
        guard let transport else { return }
        let now = Date().timeIntervalSince1970

        let due = transport.interfaces.filter {
            $0.supportsDiscovery && $0.discoverable
                && now > ($0.lastDiscoveryAnnounce + ($0.discoveryAnnounceInterval ?? 0))
        }
        guard let selected = due.max(by: { $0.lastDiscoveryAnnounce > $1.lastDiscoveryAnnounce })
        else { return }

        // Stamped before the payload is built, so a build that fails still costs the interval
        // rather than being retried every 60 seconds (`Discovery.py:86`).
        selected.lastDiscoveryAnnounce = Date().timeIntervalSince1970

        guard let appData = announceData(for: selected) else {
            Reticulum.log("Could not generate interface discovery announce data for "
                          + selected.name, level: .error)
            return
        }

        Reticulum.log("Sending interface discovery announce for \(selected.name) with "
                      + "\(appData.count)B payload", level: .debug)
        do { _ = try transport.announce(destination: discoveryDestination, appData: appData) }
        catch { Reticulum.log("Error while sending interface discovery announce: \(error)",
                              level: .error) }
    }

    // MARK: - Announce data

    /// Build one interface's announce payload: a flags byte, the msgpack-packed info, and the
    /// stamp—encrypted to the network identity when the interface asks for it.
    ///
    /// Mirrors `Discovery.get_interface_announce_data` (`Discovery.py:106-228`). Returns `nil`
    /// wherever Python aborts the announce, which it does rather than publishing an endpoint
    /// that's wrong or unusable.
    public func announceData(for interface: any Interface) -> Data? {
        let interfaceType = interface.statsTypeName
        guard Self.discoverableInterfaceTypes.contains(interfaceType) else { return nil }

        // A `location_cmd` script overwrites the three location values before they're read
        // (`Discovery.py:110-134`). A script that's configured and fails aborts the announce.
        if interface.discoveryLocation != nil, !applyLocationCommand(to: interface) { return nil }

        var flags: UInt8 = 0
        var info: [(MsgPack.Value, MsgPack.Value)] = [
            (.uint(DiscoveryFieldKey.interfaceType.rawValue), .string(interfaceType)),
            (.uint(DiscoveryFieldKey.transport.rawValue), .bool(Reticulum.transportEnabled())),
            (.uint(DiscoveryFieldKey.transportID.rawValue),
             transport?.transportIdentity.map { .bytes($0.hash) } ?? .nil),
            (.uint(DiscoveryFieldKey.transportImpl.rawValue),
             .string(InterfaceDiscoveryHelpers.implementationName)),
            (.uint(DiscoveryFieldKey.transportVers.rawValue),
             .string(InterfaceDiscoveryHelpers.implementationVersion)),
            (.uint(DiscoveryFieldKey.name.rawValue), Self.optionalString(interface.discoveryName)),
            (.uint(DiscoveryFieldKey.latitude.rawValue), Self.optionalDouble(interface.discoveryLatitude)),
            (.uint(DiscoveryFieldKey.longitude.rawValue), Self.optionalDouble(interface.discoveryLongitude)),
            (.uint(DiscoveryFieldKey.height.rawValue), Self.optionalDouble(interface.discoveryHeight)),
        ]

        // Present only when configured, so an operator who hasn't published an address emits
        // the pre-1.5.0 payload byte for byte (`Discovery.py:147`).
        if let address = interface.discoveryLxmfAddress {
            info.append((.uint(DiscoveryFieldKey.operatorAddress.rawValue), .bytes(address)))
        }

        // A TCP client is only discoverable as a KISS-over-TCP endpoint, and this port has no
        // KISS framing on `TCPClientInterface`, so the guard always fires here
        // (`Discovery.py:149-151`). Ported rather than dropped: the day framing lands, the
        // branch below is already waiting for it.
        if interfaceType == "TCPClientInterface" {
            Reticulum.log("Invalid interface discovery configuration for \(interface.displayName), "
                          + "aborting discovery announce", level: .error)
            return nil
        }

        switch interfaceType {
        case "BackboneInterface", "TCPServerInterface":
            // A listener nobody can dial is not an endpoint, so an unset or malformed
            // `reachable_on` aborts rather than publishing one (`Discovery.py:153-183`).
            guard let configured = interface.reachableOn else { return nil }
            guard let resolved = resolveReachableAddress(configured) else { return nil }
            guard InterfaceDiscoveryHelpers.isIPAddress(resolved)
                    || InterfaceDiscoveryHelpers.isHostname(resolved) else {
                Reticulum.log("The configured reachable_on parameter \"\(resolved)\" for "
                              + "\(interface.displayName) is not a valid IP address or hostname",
                              level: .error)
                return nil
            }
            info.append((.uint(DiscoveryFieldKey.reachableOn.rawValue), .string(resolved)))
            info.append((.uint(DiscoveryFieldKey.port.rawValue),
                         interface.discoveryListenPort.map { .uint(UInt64($0)) } ?? .nil))

        case "I2PInterface":
            if let b32 = interface.discoveryEndpointAddress {
                info.append((.uint(DiscoveryFieldKey.reachableOn.rawValue), .string(b32)))
            }

        case "RNodeInterface":
            let radio = interface.discoveryRadioParameters
            info.append((.uint(DiscoveryFieldKey.frequency.rawValue),
                         Self.optionalInt(radio?.frequency)))
            info.append((.uint(DiscoveryFieldKey.bandwidth.rawValue),
                         Self.optionalInt(radio?.bandwidth)))
            info.append((.uint(DiscoveryFieldKey.spreadingFactor.rawValue),
                         Self.optionalInt(radio?.spreadingFactor)))
            info.append((.uint(DiscoveryFieldKey.codingRate.rawValue),
                         Self.optionalInt(radio?.codingRate)))

        case "WeaveInterface":
            info.append((.uint(DiscoveryFieldKey.frequency.rawValue),
                         Self.optionalInt(interface.discoveryFrequency)))
            info.append((.uint(DiscoveryFieldKey.bandwidth.rawValue),
                         Self.optionalInt(interface.discoveryBandwidth)))
            info.append((.uint(DiscoveryFieldKey.channel.rawValue),
                         Self.optionalInt(interface.discoveryChannel)))
            info.append((.uint(DiscoveryFieldKey.modulation.rawValue),
                         Self.optionalInt(interface.discoveryModulation)))

        case "KISSInterface":
            info.append((.uint(DiscoveryFieldKey.frequency.rawValue),
                         Self.optionalInt(interface.discoveryFrequency)))
            info.append((.uint(DiscoveryFieldKey.bandwidth.rawValue),
                         Self.optionalInt(interface.discoveryBandwidth)))
            // Python passes the modulation through `sanitize()` here (`Discovery.py:201`),
            // which raises on the int its own config parser produced—so upstream's KISS branch
            // only survives an *unset* modulation. A decimal string is what `sanitize` would
            // have yielded, reads correctly on both receive sides, and renders into the config
            // entry a discovering node builds.
            info.append((.uint(DiscoveryFieldKey.modulation.rawValue),
                         interface.discoveryModulation.map { .string(String($0)) } ?? .nil))

        default:
            break
        }

        // The segment's shared secret, so it's off the wire unless the operator asks
        // (`Discovery.py:203-205`).
        if interface.discoveryPublishIfac {
            info.append((.uint(DiscoveryFieldKey.ifacNetname.rawValue),
                         Self.optionalString(interface.ifacNetname)))
            info.append((.uint(DiscoveryFieldKey.ifacNetkey.rawValue),
                         Self.optionalString(interface.ifacNetkey)))
        }

        let packed = MsgPack.encode(.map(info))
        let infohash = Hashes.fullHash(packed)
        let cost = interface.discoveryStampValue ?? Self.defaultStampValue

        let stamp: Data
        lock.lock()
        let cached = stampCache[infohash]
        lock.unlock()
        if let cached {
            stamp = cached
        } else {
            guard let found = stampGenerator.generateStamp(material: infohash, targetCost: cost,
                                                           expandRounds: Self.workblockExpandRounds)
            else { return nil }
            stamp = found
            lock.lock(); stampCache[infohash] = found; lock.unlock()
        }

        if interface.discoveryEncrypt {
            flags |= InterfaceAnnounceHandler.flagEncrypted
            guard let networkIdentity = transport?.networkIdentity else {
                Reticulum.log("Discovery encryption requested for \(interface.displayName), but "
                              + "no network identity configured. Aborting discovery announce.",
                              level: .error)
                return nil
            }
            guard let sealed = try? networkIdentity.encrypt(packed + stamp) else { return nil }
            return Data([flags]) + sealed
        }

        return Data([flags]) + packed + stamp
    }

    // MARK: - Sanitize

    /// Python: `InterfaceAnnouncer.sanitize` (`Discovery.py:99-104`)—newlines out, then trim.
    ///
    /// Every published string goes through it, so a stray newline in a config value can't split
    /// the config entry a discovering node renders.
    static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        return value.replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func optionalString(_ value: String?) -> MsgPack.Value {
        sanitize(value).map { .string($0) } ?? .nil
    }

    private static func optionalDouble(_ value: Double?) -> MsgPack.Value {
        value.map { .double($0) } ?? .nil
    }

    private static func optionalInt(_ value: Int?) -> MsgPack.Value {
        value.map { $0 < 0 ? .int(Int64($0)) : .uint(UInt64($0)) } ?? .nil
    }

    // MARK: - Externally supplied values

    /// Resolve a configured `reachable_on`: run it when it names an executable, otherwise take
    /// it literally (`Discovery.py:155-176`).
    ///
    /// - Returns: `nil` when a script was found and failed, which aborts the announce.
    private func resolveReachableAddress(_ configured: String) -> String? {
        guard let sanitized = Self.sanitize(configured) else { return nil }
        switch Self.runIfExecutable(sanitized) {
        case .notAScript:        return sanitized
        case .output(let value): return Self.sanitize(value)
        case .failed(let error):
            Reticulum.log("Error while getting reachable_on from executable at \(sanitized): "
                          + "\(error). Aborting discovery announce", level: .error)
            return nil
        }
    }

    /// Run a configured `location_cmd` and write its three values onto the interface.
    ///
    /// Python overwrites `discovery_latitude`/`longitude`/`height` in place before packing
    /// (`Discovery.py:127-129`), so a node with a moving antenna publishes where it is now.
    ///
    /// - Returns: `false` when the script failed or printed something unusable, which aborts the
    ///   announce rather than publishing a stale position.
    private func applyLocationCommand(to interface: any Interface) -> Bool {
        guard let configured = Self.sanitize(interface.discoveryLocation) else { return true }

        let output: String
        switch Self.runIfExecutable(configured) {
        case .notAScript: return true
        case .output(let value): output = value
        case .failed(let error):
            Reticulum.log("Error while getting discovery location from executable at "
                          + "\(configured): \(error). Aborting discovery announce", level: .error)
            return false
        }

        let parts = (Self.sanitize(output) ?? "")
            .replacingOccurrences(of: " ", with: "")
            .split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              let height = Double(parts[2]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude),
              (-4000...1e6).contains(height)
        else {
            Reticulum.log("Error while getting discovery location from executable at "
                          + "\(configured): unusable output. Aborting discovery announce",
                          level: .error)
            return false
        }

        interface.discoveryLatitude = latitude
        interface.discoveryLongitude = longitude
        interface.discoveryHeight = height
        return true
    }

    enum ScriptResult {
        /// The path doesn't name an executable file, so the configured value is a literal.
        case notAScript
        case output(String)
        case failed(String)
    }

    /// Run `path` when it names an executable file, capturing stdout.
    ///
    /// Python gates the whole mechanism on `not is_windows()` (`Discovery.py:111`, `:157`).
    /// The equivalent gate here is `os(macOS)`: `Foundation.Process` doesn't exist on iOS,
    /// tvOS or watchOS, which is the same reason `PipeInterface` is deferred. On those
    /// platforms a configured value is always taken literally—and a config that points at a
    /// script there couldn't have worked anyway.
    static func runIfExecutable(_ path: String) -> ScriptResult {
        #if os(macOS)
        // `$HOME`, not the account's real home. Python resolves both of these paths through
        // `os.path.expanduser` (`Discovery.py:115`, `:159`), and a sandboxed run that ignores
        // `$HOME` reaches outside its sandbox (`bugs/024`).
        let expanded = DaemonBootstrap.expandTilde(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: expanded)
        else { return .notAScript }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: expanded)
        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                return .failed("Non-zero exit code from subprocess")
            }
            return .output(String(decoding: data, as: UTF8.self))
        } catch {
            return .failed("\(error)")
        }
        #else
        return .notAScript
        #endif
    }
}
