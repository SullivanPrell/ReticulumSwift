import Foundation

// MARK: - Constants

/// Msgpack key byte values for discovery announce payloads.
/// Matches Python's `RNS/Discovery.py` module-level constants.
enum DiscoveryFieldKey: UInt64 {
    case interfaceType  = 0x00
    case transport      = 0x01
    case reachableOn    = 0x02
    case latitude       = 0x03
    case longitude      = 0x04
    case height         = 0x05
    case port           = 0x06
    case ifacNetname    = 0x07
    case ifacNetkey     = 0x08
    case frequency      = 0x09
    case bandwidth      = 0x0A
    case spreadingFactor = 0x0B
    case codingRate     = 0x0C
    case modulation     = 0x0D
    case channel        = 0x0E
    case name           = 0xFF
    case transportID    = 0xFE

    // Added in RNS 1.5.0. `TRANSPORT_IMPL`/`TRANSPORT_VERS` name the announcing
    // implementation and its build; 1.5.2 emits both but doesn't read either back, so they
    // are staged for a future consumer. `OP_ADDR` carries the operator's LXMF address and
    // *is* consumed on receive (`Discovery.py:427-430`).
    case transportImpl  = 0xFD
    case transportVers  = 0xFC
    case operatorAddress = 0xF0
}

/// String keys used when persisting `DiscoveredInterfaceInfo` as a msgpack map.
/// Matches the Python dict key names so files are cross-compatible.
private enum PersistKey {
    static let type         = "type"
    static let transport    = "transport"
    static let name         = "name"
    static let received     = "received"
    static let stamp        = "stamp"
    static let value        = "value"
    static let transportID  = "transport_id"
    static let networkID    = "network_id"
    static let hops         = "hops"
    static let latitude     = "latitude"
    static let longitude    = "longitude"
    static let height       = "height"
    static let ifacNetname  = "ifac_netname"
    static let ifacNetkey   = "ifac_netkey"
    static let reachableOn  = "reachable_on"
    static let port         = "port"
    static let frequency    = "frequency"
    static let bandwidth    = "bandwidth"
    static let sf           = "sf"
    static let cr           = "cr"
    static let modulation   = "modulation"
    static let channel      = "channel"
    static let configEntry  = "config_entry"
    static let discoveryHash = "discovery_hash"
    static let discovered   = "discovered"
    static let lastHeard    = "last_heard"
    static let heardCount   = "heard_count"
    static let operatorLxmfAddress = "operator_lxmf_address"
}

// MARK: - DiscoveryStampValidator

/// Protocol for validating proof-of-work stamps on discovery announces.
///
/// Allows `InterfaceAnnounceHandler` to be decoupled from the LXMF package.
/// In production, wrap `LXStamper` from LXMFSwift to conform.
/// In tests, use a passthrough implementation that always accepts any stamp.
public protocol DiscoveryStampValidator {
    /// Number of bytes in a valid stamp (typically 32).
    var stampSize: Int { get }
    /// Build the work block from `material` using `expandRounds` HKDF rounds.
    func stampWorkblock(material: Data, expandRounds: Int) -> Data
    /// Count leading zero bits of SHA256(workblock + stamp). Higher = stronger proof.
    func stampValue(workblock: Data, stamp: Data) -> Int
    /// Return true if SHA256(workblock + stamp) has ≥ `targetCost` leading zero bits.
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool
}

// MARK: - DiscoveredInterfaceInfo

/// Decoded information about a remotely discovered interface.
///
/// Mirrors the `info` dict Python's `InterfaceAnnounceHandler.received_announce` builds.
public struct DiscoveredInterfaceInfo {
    public var type: String
    public var transport: Bool
    public var name: String
    public var received: TimeInterval
    public var stamp: Data
    public var value: Int
    public var transportID: String     // hex, no delimiters
    public var networkID: String       // hex, no delimiters
    public var hops: Int
    public var latitude: Double?
    public var longitude: Double?
    public var height: Double?
    public var ifacNetname: String?
    public var ifacNetkey: String?
    public var reachableOn: String?
    public var port: Int?
    public var frequency: Double?
    public var bandwidth: Double?
    public var sf: Int?
    public var cr: Int?
    public var modulation: String?
    public var channel: Int?
    public var configEntry: String?
    public var discoveryHash: Data?
    /// The announcing operator's LXMF address as undelimited hex, when they published one.
    /// `info["operator_lxmf_address"]` (`Discovery.py:430`), added in RNS 1.5.0—optional, so
    /// every pre-1.5.0 announce and every 1.5.x node that hasn't configured one leaves it nil.
    public var operatorLxmfAddress: String? = nil

    // Persistence fields (written/read by InterfaceDiscovery)
    public var discovered: TimeInterval
    public var lastHeard: TimeInterval
    public var heardCount: Int
    public var status: String?
    public var statusCode: Int?
}

// MARK: - InterfaceDiscoveryHelpers

/// Pure helper functions used by the interface discovery subsystem.
public enum InterfaceDiscoveryHelpers {

    /// Short identifier for this implementation, published as `TRANSPORT_IMPL` (0xFD).
    ///
    /// Python hardcodes `IMPLEMENTATION_NAME = "RNS"`. The field exists precisely so a
    /// discovery consumer can tell one stack from another, so this port announces its own name
    /// rather than impersonating the reference.
    public static let implementationName = "RNSwift"

    /// Build tag published as `TRANSPORT_VERS` (0xFC).
    ///
    /// This is ``Reticulum/version``—the port's own release line—not
    /// ``Reticulum/rnsProtocolVersion``. The field identifies *a build of an implementation*,
    /// which is what a consumer needs to attribute a behaviour or a bug; the protocol level it
    /// matches is a separate, coarser fact.
    public static let implementationVersion = Reticulum.version

    /// Return true if `address` is a valid IPv4 or IPv6 address string.
    /// Mirrors Python `is_ip_address(address_string)` which uses `ipaddress.ip_address`.
    public static func isIPAddress(_ address: String) -> Bool {
        guard !address.isEmpty else { return false }
        var buf4 = in_addr()
        var buf6 = in6_addr()
        return address.withCString { p in
            inet_pton(AF_INET,  p, &buf4) == 1 ||
            inet_pton(AF_INET6, p, &buf6) == 1
        }
    }

    /// Return true if `address` falls in `200::/7`, the Yggdrasil address range.
    /// Mirrors Python `is_ygg_ipv6(address_string)` (`Discovery.py:877-879`).
    ///
    /// An address in this range is only reachable through a running Yggdrasil node, and nothing
    /// here can tell whether one is running—which is why autoconnect skips these rather than
    /// dialling and failing.
    public static func isYggIPv6(_ address: String) -> Bool {
        var buf6 = in6_addr()
        guard address.withCString({ inet_pton(AF_INET6, $0, &buf6) == 1 }) else { return false }
        // `200::/7` fixes the top seven bits, so the first byte is 0x02 or 0x03.
        let firstByte = withUnsafeBytes(of: &buf6) { $0[0] }
        return firstByte & 0xFE == 0x02
    }

    /// Return true if `address` is a Tor onion address.
    /// Mirrors Python `is_onion_address(address_string)` (`Discovery.py:881-883`)—a
    /// case-insensitive suffix match, not a validity check.
    public static func isOnionAddress(_ address: String) -> Bool {
        address.lowercased().hasSuffix(".onion")
    }

    /// Addresses that never name a reachable peer, because they name this node.
    /// Mirrors Python `INVALID_IP_ADDRESSES` (`Discovery.py:885`)—an exact two-entry deny
    /// list, so `127.0.0.2` is not on it.
    public static let invalidIPAddresses: Set<String> = ["127.0.0.1", "0.0.0.0"]

    /// Mirrors Python `is_invalid_ip_address(address_string)` (`Discovery.py:886-888`).
    public static func isInvalidIPAddress(_ address: String) -> Bool {
        invalidIPAddresses.contains(address)
    }

    /// Return true if `hostname` is a syntactically valid DNS hostname.
    /// Mirrors Python `is_hostname(hostname)`.
    public static func isHostname(_ hostname: String) -> Bool {
        var h = hostname
        if h.hasSuffix(".") { h = String(h.dropLast()) }
        guard h.count <= 253 else { return false }
        let components = h.split(separator: ".", omittingEmptySubsequences: false)
        guard let tld = components.last else { return false }
        // TLD must not be all digits
        if tld.allSatisfy({ $0.isNumber }) { return false }
        // Each label: 1-63 chars, alphanumeric and hyphen, not start/end with hyphen
        let labelPattern = try! NSRegularExpression(pattern: "^(?!-)[a-zA-Z0-9-]{1,63}(?<!-)$")
        for label in components {
            let s = String(label)
            let range = NSRange(s.startIndex..., in: s)
            if labelPattern.firstMatch(in: s, range: range) == nil { return false }
        }
        return true
    }
}

// MARK: - InterfaceAnnounceHandler

/// Receives discovery announces emitted by remote `InterfaceAnnouncer` nodes and
/// decodes them into `DiscoveredInterfaceInfo` values.
///
/// Mirrors Python `RNS.Discovery.InterfaceAnnounceHandler`.
/// Use together with `InterfaceDiscovery` to build a list of reachable interfaces.
public final class InterfaceAnnounceHandler: AnnounceHandler {

    // MARK: - Constants

    /// Announce payload flag: stamp has been signed with a Reticulum identity.
    public static let flagSigned:    UInt8 = 0b00000001
    /// Announce payload flag: payload is encrypted with the network identity.
    public static let flagEncrypted: UInt8 = 0b00000010
    /// PoW workblock expansion rounds for interface discovery stamps.
    /// Matches Python `InterfaceAnnouncer.WORKBLOCK_EXPAND_ROUNDS`.
    public static let workblockExpandRounds: Int = 20
    /// Default minimum stamp value required to accept a discovery announce.
    /// Mirrors Python `InterfaceAnnouncer.DEFAULT_STAMP_VALUE` (bumped 14 → 16 in
    /// RNS 1.4.0, commit be36abd8).
    public static let defaultRequiredValue: Int = 16

    private static let discoverableTypes: Set<String> = [
        "BackboneInterface", "TCPServerInterface", "TCPClientInterface",
        "RNodeInterface", "WeaveInterface", "I2PInterface", "KISSInterface"
    ]

    // MARK: - AnnounceHandler conformance

    public let aspectFilter: String? = "rnstransport.discovery.interface"
    public let receivePathResponses: Bool = false

    // MARK: - State

    public let requiredValue: Int
    private let stampValidator: DiscoveryStampValidator
    public var callback: ((DiscoveredInterfaceInfo) -> Void)?

    // MARK: - Init

    public init(requiredValue: Int = defaultRequiredValue,
                stampValidator: DiscoveryStampValidator,
                callback: ((DiscoveredInterfaceInfo) -> Void)? = nil) {
        self.requiredValue = requiredValue
        self.stampValidator = stampValidator
        self.callback = callback
    }

    // MARK: - AnnounceHandler

    public func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                                  announcePacketHash: Data, isPathResponse: Bool) {
        // `interface_discovery_sources` is an allowlist of announcing identities.
        // Python rejects at reception, before any of the work below
        // (Discovery.py:248-251)—enforcing it only when pruning stored records,
        // as this used to, means a non-authorised peer is still dialled for the
        // whole interval between its announce and the next prune.
        let discoverySources = Reticulum.interfaceDiscoverySources()
        if !discoverySources.isEmpty, !discoverySources.contains(identity.hash) {
            Reticulum.log("Interface discovered from non-authorized network identity \(identity.hash.hexString), ignoring",
                          level: .debug)
            return
        }
        guard let appData, appData.count > stampValidator.stampSize + 1 else { return }
        let flags   = appData[0]
        let payload = appData.dropFirst()

        let encrypted = (flags & Self.flagEncrypted) != 0
        if encrypted {
            // Encrypted discovery announces require the network identity for decryption;
            // without it decoding is impossible, so silently skip.
            return
        }

        guard payload.count > stampValidator.stampSize else { return }
        let stamp  = Data(payload.suffix(stampValidator.stampSize))
        let packed = Data(payload.dropLast(stampValidator.stampSize))

        let infohash  = Hashes.fullHash(packed)
        let workblock = stampValidator.stampWorkblock(material: infohash, expandRounds: Self.workblockExpandRounds)
        let value     = stampValidator.stampValue(workblock: workblock, stamp: stamp)
        let valid     = stampValidator.stampValid(stamp: stamp, targetCost: requiredValue, workblock: workblock)

        guard valid, value >= requiredValue else { return }

        guard case .map(let map) = (try? MsgPack.decode(packed)) else { return }
        guard let info = buildInfo(map: map, identity: identity,
                                   destinationHash: destinationHash,
                                   stamp: stamp, value: value) else { return }
        callback?(info)
    }

    // MARK: - Payload building

    private func buildInfo(map: [(MsgPack.Value, MsgPack.Value)],
                           identity: Identity,
                           destinationHash: Data,
                           stamp: Data, value: Int) -> DiscoveredInterfaceInfo? {
        // Build lookup dict from int key to value
        var d: [UInt64: MsgPack.Value] = [:]
        for (k, v) in map {
            if case .uint(let n) = k { d[n] = v }
        }

        guard let itV = d[DiscoveryFieldKey.interfaceType.rawValue],
              case .string(let interfaceType) = itV else { return nil }
        guard Self.discoverableTypes.contains(interfaceType) else { return nil }

        guard let transportV = d[DiscoveryFieldKey.transport.rawValue],
              case .bool(let transport) = transportV else { return nil }

        guard let tidV = d[DiscoveryFieldKey.transportID.rawValue],
              case .bytes(let tidBytes) = tidV,
              tidBytes.count == 16 else { return nil }

        // Latitude / longitude / height may be nil or double
        let latitude  = extractOptionalDouble(d[DiscoveryFieldKey.latitude.rawValue])
        let longitude = extractOptionalDouble(d[DiscoveryFieldKey.longitude.rawValue])
        let height    = extractOptionalDouble(d[DiscoveryFieldKey.height.rawValue])

        let rawName = extractOptionalString(d[DiscoveryFieldKey.name.rawValue])
        let transportIDHex = RNSUtilities.hexrep(tidBytes, delimit: false)
        let networkIDHex   = RNSUtilities.hexrep(identity.hash, delimit: false)

        let sanitized = Self.sanitizeName(rawName)
        let name      = sanitized ?? "Discovered \(interfaceType)"

        let now = Date().timeIntervalSince1970
        var info = DiscoveredInterfaceInfo(
            type: interfaceType, transport: transport, name: name,
            received: now, stamp: stamp, value: value,
            transportID: transportIDHex, networkID: networkIDHex,
            hops: 0,
            latitude: latitude, longitude: longitude, height: height,
            ifacNetname: nil, ifacNetkey: nil,
            reachableOn: nil, port: nil,
            frequency: nil, bandwidth: nil, sf: nil, cr: nil,
            modulation: nil, channel: nil,
            configEntry: nil, discoveryHash: nil,
            discovered: now, lastHeard: now, heardCount: 0
        )

        // IFAC fields (optional)
        if let nn = extractOptionalString(d[DiscoveryFieldKey.ifacNetname.rawValue]) { info.ifacNetname = nn }
        if let nk = extractOptionalString(d[DiscoveryFieldKey.ifacNetkey.rawValue])  { info.ifacNetkey  = nk }

        // Interface-type-specific fields
        switch interfaceType {

        case "BackboneInterface", "TCPServerInterface":
            guard let ron = extractOptionalString(d[DiscoveryFieldKey.reachableOn.rawValue]),
                  InterfaceDiscoveryHelpers.isIPAddress(ron) || InterfaceDiscoveryHelpers.isHostname(ron) else { return nil }
            guard let portV = d[DiscoveryFieldKey.port.rawValue] else { return nil }
            let portNum: Int
            switch portV {
            case .int(let n):  portNum = Int(n)
            case .uint(let n): portNum = Int(n)
            default: return nil
            }
            info.reachableOn = ron
            info.port        = portNum
            info.configEntry = buildBackboneConfigEntry(name: name, host: ron, port: portNum,
                                                        transportID: transportIDHex,
                                                        netname: info.ifacNetname, netkey: info.ifacNetkey,
                                                        interfaceType: interfaceType)

        case "I2PInterface":
            if let ron = extractOptionalString(d[DiscoveryFieldKey.reachableOn.rawValue]) {
                info.reachableOn = ron
                info.configEntry = buildI2PConfigEntry(name: name, b32: ron,
                                                       transportID: transportIDHex,
                                                       netname: info.ifacNetname, netkey: info.ifacNetkey)
            }

        case "RNodeInterface":
            let freq = extractOptionalDouble(d[DiscoveryFieldKey.frequency.rawValue])
            let bw   = extractOptionalDouble(d[DiscoveryFieldKey.bandwidth.rawValue])
            let sf   = extractOptionalInt(d[DiscoveryFieldKey.spreadingFactor.rawValue])
            let cr   = extractOptionalInt(d[DiscoveryFieldKey.codingRate.rawValue])
            info.frequency = freq
            info.bandwidth = bw
            info.sf        = sf
            info.cr        = cr
            info.configEntry = buildRNodeConfigEntry(name: name, freq: freq, bw: bw, sf: sf, cr: cr,
                                                     netname: info.ifacNetname, netkey: info.ifacNetkey)

        case "WeaveInterface":
            info.frequency  = extractOptionalDouble(d[DiscoveryFieldKey.frequency.rawValue])
            info.bandwidth  = extractOptionalDouble(d[DiscoveryFieldKey.bandwidth.rawValue])
            info.channel    = extractOptionalInt(d[DiscoveryFieldKey.channel.rawValue])
            info.modulation = extractOptionalString(d[DiscoveryFieldKey.modulation.rawValue])
            info.configEntry = buildWeaveConfigEntry(name: name, netname: info.ifacNetname, netkey: info.ifacNetkey)

        case "KISSInterface":
            info.frequency  = extractOptionalDouble(d[DiscoveryFieldKey.frequency.rawValue])
            info.bandwidth  = extractOptionalDouble(d[DiscoveryFieldKey.bandwidth.rawValue])
            info.modulation = extractOptionalString(d[DiscoveryFieldKey.modulation.rawValue])
            info.configEntry = buildKISSConfigEntry(name: name,
                                                    freq: info.frequency, bw: info.bandwidth,
                                                    mod: info.modulation,
                                                    transportID: transportIDHex,
                                                    netname: info.ifacNetname, netkey: info.ifacNetkey)

        default:
            break
        }

        // discovery_hash = SHA256(transportID_hex + name)
        let hashMaterial = (transportIDHex + name).data(using: .utf8) ?? Data()
        info.discoveryHash = Hashes.fullHash(hashMaterial)

        // `if info and OP_ADDR in unpacked` (`Discovery.py:427-430`). Two different failure
        // modes, deliberately: a *type* violation raises inside Python's try and abandons the
        // whole announce, while a merely wrong-*length* value just fails the `==` test and is
        // dropped on its own. The asymmetry matters—a bad optional field must not be able to
        // blackhole an otherwise reachable node, but a field of the wrong type means the sender
        // and this parser disagree about the payload's shape, which isn't recoverable.
        if let opAddr = d[DiscoveryFieldKey.operatorAddress.rawValue] {
            switch opAddr {
            case .nil:
                break
            case .bytes(let addr):
                if !addr.isEmpty, addr.count == Constants.truncatedHashLength {
                    info.operatorLxmfAddress = RNSUtilities.hexrep(addr, delimit: false)
                }
            default:
                return nil
            }
        }

        return info
    }

    // MARK: - Config entry builders

    private func buildBackboneConfigEntry(name: String, host: String, port: Int,
                                          transportID: String,
                                          netname: String?, netkey: String?,
                                          interfaceType: String) -> String {
        // RNS 1.4.1 (commit c25b56db) excludes Darwin from backbone support when
        // connecting to a discovered BackboneInterface/TCPServerInterface:
        //
        //     backbone_support = not is_windows() and not is_darwin()
        //     connection_interface = "BackboneInterface" if backbone_support else "TCPClientInterface"
        //
        // BackboneInterface's client side relies on epoll/kqueue semantics that
        // don't hold on Darwin, so a discovered peer must be dialled as a plain
        // TCPClientInterface instead. This is the whole platform ReticulumSwift
        // targets, so every discovered peer takes the TCP path here—and the
        // key changes with it: TCPClientInterface reads `target_host`, whereas
        // BackboneInterface reads `remote`.
        #if canImport(Darwin)
        let backboneSupport = false
        #else
        let backboneSupport = true
        #endif
        let connType  = backboneSupport ? "BackboneInterface" : "TCPClientInterface"
        let remoteKey = backboneSupport ? "remote" : "target_host"
        let idStr  = "\n  transport_identity = \(transportID)"
        let nnStr  = netname.map { "\n  network_name = \($0)" } ?? ""
        let nkStr  = netkey.map  { "\n  passphrase = \($0)" }   ?? ""
        return "[[\(name)]]\n  type = \(connType)\n  enabled = yes\n  \(remoteKey) = \(host)\n  target_port = \(port)\(idStr)\(nnStr)\(nkStr)"
    }

    private func buildI2PConfigEntry(name: String, b32: String,
                                     transportID: String,
                                     netname: String?, netkey: String?) -> String {
        let idStr = "\n  transport_identity = \(transportID)"
        let nnStr = netname.map { "\n  network_name = \($0)" } ?? ""
        let nkStr = netkey.map  { "\n  passphrase = \($0)" }   ?? ""
        return "[[\(name)]]\n  type = I2PInterface\n  enabled = yes\n  peers = \(b32)\(idStr)\(nnStr)\(nkStr)"
    }

    private func buildRNodeConfigEntry(name: String,
                                       freq: Double?, bw: Double?, sf: Int?, cr: Int?,
                                       netname: String?, netkey: String?) -> String {
        let freqStr = freq.map { "\(Int($0))" } ?? ""
        let bwStr   = bw.map   { "\(Int($0))" } ?? ""
        let sfStr   = sf.map   { "\($0)" }       ?? ""
        let crStr   = cr.map   { "\($0)" }       ?? ""
        let nnStr   = netname.map { "\n  network_name = \($0)" } ?? ""
        let nkStr   = netkey.map  { "\n  passphrase = \($0)" }   ?? ""
        return "[[\(name)]]\n  type = RNodeInterface\n  enabled = yes\n  port = \n  frequency = \(freqStr)\n  bandwidth = \(bwStr)\n  spreadingfactor = \(sfStr)\n  codingrate = \(crStr)\n  txpower = \(nnStr)\(nkStr)"
    }

    private func buildWeaveConfigEntry(name: String, netname: String?, netkey: String?) -> String {
        let nnStr = netname.map { "\n  network_name = \($0)" } ?? ""
        let nkStr = netkey.map  { "\n  passphrase = \($0)" }   ?? ""
        return "[[\(name)]]\n  type = WeaveInterface\n  enabled = yes\n  port = \(nnStr)\(nkStr)"
    }

    private func buildKISSConfigEntry(name: String,
                                      freq: Double?, bw: Double?, mod: String?,
                                      transportID: String,
                                      netname: String?, netkey: String?) -> String {
        let freqStr = freq.map { "\(Int($0))" } ?? ""
        let bwStr   = bw.map   { "\(Int($0))" } ?? ""
        let modStr  = mod ?? ""
        let idStr   = "\n  transport_identity = \(transportID)"
        let nnStr   = netname.map { "\n  network_name = \($0)" } ?? ""
        let nkStr   = netkey.map  { "\n  passphrase = \($0)" }   ?? ""
        return "[[\(name)]]\n  type = KISSInterface\n  enabled = yes\n  port = \n  # Frequency: \(freqStr)\n  # Bandwidth: \(bwStr)\n  # Modulation: \(modStr)\(idStr)\(nnStr)\(nkStr)"
    }

    // MARK: - Sanitize name (interface names)

    /// Strip a discovery interface name to ASCII, collapse spaces, and require start/end
    /// chars to be in the alphanumeric set (uppercase + digits) or ")" for the tail.
    ///
    /// Mirrors Python `InterfaceAnnounceHandler.sanitize_name(name)`.
    public static func sanitizeName(_ name: String?) -> String? {
        guard let name else { return nil }
        // ASCII-only: filter out all non-ASCII scalars (mirrors Python encode("ascii","ignore"))
        var s = String(name.unicodeScalars.filter { $0.value < 128 }.map(Character.init))
        s = s.trimmingCharacters(in: .whitespaces)
        // Collapse 5 → 3 → 2 spaces down to 1 (Python does this in order 5, 3, 2)
        for count in [5, 3, 2] {
            s = s.replacingOccurrences(of: String(repeating: " ", count: count), with: " ")
        }
        // Python builds san_map from three ASCII ranges: 48-57, 65-90 and 97-122
        // (`Discovery.py:898-901`), so digits, uppercase *and* lowercase all survive. Omitting
        // the lowercase range truncated every ordinary name to its first character:
        // "Example hub" arrived as "E".
        let sanSet = CharacterSet(charactersIn:
            "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
        // Strip leading chars not in san_map
        while !s.isEmpty, let first = s.unicodeScalars.first, !sanSet.contains(first) {
            s.removeFirst()
        }
        // Strip trailing chars not in san_map + ")"
        let sanTailSet = sanSet.union(CharacterSet(charactersIn: ")"))
        while !s.isEmpty, let last = s.unicodeScalars.last, !sanTailSet.contains(last) {
            s.removeLast()
        }
        return s
    }

    // MARK: - Value extraction helpers

    private func extractOptionalString(_ v: MsgPack.Value?) -> String? {
        guard let v else { return nil }
        if case .string(let s) = v { return s }
        return nil
    }

    private func extractOptionalDouble(_ v: MsgPack.Value?) -> Double? {
        guard let v else { return nil }
        switch v {
        case .double(let d): return d
        case .int(let n):    return Double(n)
        case .uint(let n):   return Double(n)
        default:             return nil
        }
    }

    private func extractOptionalInt(_ v: MsgPack.Value?) -> Int? {
        guard let v else { return nil }
        switch v {
        case .int(let n):  return Int(n)
        case .uint(let n): return Int(n)
        default:           return nil
        }
    }
}

// MARK: - InterfaceDiscovery

/// Manages a persistent list of interfaces discovered via `InterfaceAnnounceHandler`.
///
/// Stores each discovered interface as a msgpack file (keyed by discovery_hash)
/// in `storagePath/discovery/interfaces/`.
/// Mirrors Python `RNS.Discovery.InterfaceDiscovery`.
public final class InterfaceDiscovery {

    // MARK: - Constants

    public static let thresholdUnknown: TimeInterval = 24 * 60 * 60       // 1 day
    public static let thresholdStale:   TimeInterval = 3 * 24 * 60 * 60   // 3 days
    public static let thresholdRemove:  TimeInterval = 7 * 24 * 60 * 60   // 7 days

    /// Python: `InterfaceDiscovery.MONITOR_INTERVAL`—how often the autoconnect monitor wakes.
    public static let monitorInterval: TimeInterval = 5

    /// Python: `InterfaceDiscovery.DETACH_THRESHOLD`—seconds an auto-connected interface may
    /// stay down before it's torn down and its slot freed.
    public static let detachThreshold: TimeInterval = 12

    /// The two types autoconnect will dial, matched against the announced type.
    /// Python: `InterfaceDiscovery.AUTOCONNECT_TYPES` (`Discovery.py:449`). Both are dialled as
    /// a Backbone client, because both describe a listening TCP endpoint.
    public static let autoconnectTypes: Set<String> = ["BackboneInterface", "TCPServerInterface"]

    /// The mode a transport node adopts a discovered peer under.
    /// Python: `InterfaceDiscovery.AC_TRANSPORT_MODE` (`Discovery.py:452`).
    public static let acTransportMode: InterfaceMode = .gateway

    /// Python: `InterfaceDiscovery.AC_GRAVITY` (`Discovery.py:453`)—zero, so an auto-connected
    /// peer never outranks a configured one in path selection.
    public static let acGravity = 0

    public static let statusAvailable = "available"
    public static let statusUnknown   = "unknown"
    public static let statusStale     = "stale"

    public static let statusCodeAvailable = 1000
    public static let statusCodeUnknown   = 100
    public static let statusCodeStale     = 0

    private static let discoverableTypes: Set<String> = [
        "BackboneInterface", "TCPServerInterface", "I2PInterface",
        "RNodeInterface", "WeaveInterface", "KISSInterface"
    ]

    // MARK: - State

    private let storagePath: URL
    private let lock = NSLock()

    /// Predicate used to drop persisted discoveries belonging to blackholed
    /// identities. Python reaches its `Reticulum` singleton
    /// (`self.rns_instance.is_blackholed(...)`); Swift has no such singleton, so
    /// the owner injects the check. Left `nil` the blackhole clauses are skipped,
    /// which is the pre-1.4.1 behaviour.
    ///
    /// Hold this weakly at the call site—`Transport.isBlackholed` is the
    /// intended implementation and `Transport` may outlive nothing here.
    public var isBlackholed: ((Data) -> Bool)?

    // MARK: - Autoconnect collaborators

    /// The transport autoconnect attaches to and reads the interface list from. Python reaches
    /// the `RNS.Transport` global; here the owner sets it, so a test can drive autoconnect
    /// against a bare transport.
    ///
    /// Weak: `Transport` owns this object through `discoveryHandler`.
    public weak var transport: Transport?

    /// Re-create the interfaces marked `bootstrap_only`, called when every auto-connected peer
    /// has gone and none is left to find new ones (`Discovery.py:650-654`).
    ///
    /// Injected because it needs the parsed config, which lives on `Reticulum` rather than on
    /// `Transport`. Left nil the re-enable clause is skipped—a node that never configured a
    /// bootstrap interface has nothing to bring back.
    public var reenableBootstrapInterfaces: (() -> Void)?

    /// Interfaces this object dialled and is watching. Python: `monitored_interfaces`.
    private var monitoredInterfaces: [any Interface] = []
    private var monitoringAutoconnects = false
    private var monitorGeneration = 0

    /// Whether the startup reconnect pass has run. The opportunistic top-up in the monitor job
    /// waits for it, so a node doesn't dial a random discovered peer before it has tried the
    /// ones it already knew about (`Discovery.py:655`).
    public private(set) var initialAutoconnectRan = false

    // MARK: - Init

    /// - Parameter storagePath: Directory URL used for persistence.
    ///   Files are stored directly in this directory (one per interface, named by discovery_hash hex).
    public init(storagePath: String) {
        self.storagePath = URL(fileURLWithPath: storagePath)
        try? FileManager.default.createDirectory(at: self.storagePath, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Record a newly discovered interface. Persists to disk.
    /// Matches Python `InterfaceDiscovery.interface_discovered(info)`.
    public func interfaceDiscovered(_ info: DiscoveredInterfaceInfo) {
        guard let discoveryHash = info.discoveryHash else { return }
        guard InterfaceDiscovery.discoverableTypes.contains(info.type) else { return }
        let filename = RNSUtilities.hexrep(discoveryHash, delimit: false)
        let filepath = storagePath.appendingPathComponent(filename)

        lock.lock()
        defer { lock.unlock() }

        var persistedInfo = info
        if FileManager.default.fileExists(atPath: filepath.path) {
            // Update existing entry—preserve discovered timestamp, increment heard_count
            if let existing = loadFile(at: filepath) {
                persistedInfo.discovered  = existing.discovered
                persistedInfo.heardCount  = (existing.heardCount) + 1
            }
        }
        persistedInfo.lastHeard = info.received
        writeFile(persistedInfo, to: filepath)
    }

    /// List all valid discovered interfaces, applying age-based status and filtering.
    /// Matches Python `InterfaceDiscovery.list_discovered_interfaces(only_available:only_transport:)`.
    public func listDiscoveredInterfaces(onlyAvailable: Bool = false,
                                         onlyTransport: Bool = false) -> [DiscoveredInterfaceInfo] {
        let now = Date().timeIntervalSince1970
        var result: [DiscoveredInterfaceInfo] = []

        lock.lock()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: storagePath.path)) ?? []
        lock.unlock()

        for filename in files {
            let filepath = storagePath.appendingPathComponent(filename)
            lock.lock()
            let info = loadFile(at: filepath)
            lock.unlock()

            guard var entry = info else { continue }

            // Age filtering, plus the RNS 1.4.1 hygiene clauses (commit e29b8394).
            // Order follows Python's elif chain exactly.
            let heardDelta = now - entry.lastHeard
            let discoverySources = Reticulum.interfaceDiscoverySources()
            let shouldRemove: Bool = {
                if heardDelta > Self.thresholdRemove { return true }
                // A record without a transport or network identity can never be
                // matched against the discovery-source allowlist or the blackhole
                // list, so it's unusable rather than merely unverified.
                if entry.transportID.isEmpty { return true }
                if entry.networkID.isEmpty   { return true }
                guard let networkIDData = Data(hex: entry.networkID) else { return true }
                if !discoverySources.isEmpty, !discoverySources.contains(networkIDData) { return true }
                if !Self.discoverableTypes.contains(entry.type) { return true }
                // Historical discoveries must be re-checked against the blackhole
                // list: an identity blackholed after its record was written would
                // otherwise stay connectable forever.
                if let isBlackholed {
                    if isBlackholed(networkIDData) { return true }
                    if let transportIDData = Data(hex: entry.transportID),
                       isBlackholed(transportIDData) { return true }
                }
                return false
            }()

            if shouldRemove {
                try? FileManager.default.removeItem(at: filepath)
                continue
            }

            // Assign status
            let status: String
            if      heardDelta > Self.thresholdStale   { status = Self.statusStale }
            else if heardDelta > Self.thresholdUnknown { status = Self.statusUnknown }
            else                                        { status = Self.statusAvailable }

            entry.status     = status
            entry.statusCode = statusCode(for: status)

            // Apply filters
            if onlyAvailable && status != Self.statusAvailable { continue }
            if onlyTransport  && !entry.transport              { continue }

            result.append(entry)
        }

        // Sort: status_code desc, value desc, last_heard desc (mirrors Python sort)
        result.sort {
            if $0.statusCode != $1.statusCode { return ($0.statusCode ?? 0) > ($1.statusCode ?? 0) }
            if $0.value      != $1.value      { return $0.value > $1.value }
            return $0.lastHeard > $1.lastHeard
        }
        return result
    }

    // MARK: - Autoconnect

    /// Dial a discovered endpoint and attach it to the stack.
    ///
    /// Mirrors Python's `InterfaceDiscovery.autoconnect(info)` (`Discovery.py:714-781`). Silent
    /// on every declined path, because most arriving announces describe endpoints this node
    /// either already has, can't reach, or has no slot for—and the job runs on every announce.
    public func autoconnect(_ info: DiscoveredInterfaceInfo) {
        guard Reticulum.shouldAutoconnectDiscoveredInterfaces() else { return }
        guard autoconnectCount() < Reticulum.maxAutoconnectedInterfaces() else { return }
        guard Self.autoconnectTypes.contains(info.type) else { return }
        guard let transport else { return }
        guard !interfaceExists(info) else {
            Reticulum.log("Discovered \(info.type) already exists, not auto-connecting",
                          level: .debug)
            return
        }

        // Each of these needs a daemon or a route this node can't confirm from here, so Python
        // declines rather than dialling into a failure (`Discovery.py:738-747`).
        guard let reachableOn = info.reachableOn else { return }
        if InterfaceDiscoveryHelpers.isYggIPv6(reachableOn) { return }
        if InterfaceDiscoveryHelpers.isOnionAddress(reachableOn) { return }
        if InterfaceDiscoveryHelpers.isIPAddress(reachableOn),
           InterfaceDiscoveryHelpers.isInvalidIPAddress(reachableOn) {
            Reticulum.log("Not auto-connecting discovered interface with invalid IP address: "
                          + reachableOn, level: .debug)
            return
        }
        guard let port = info.port else { return }

        // Both announced types describe a listening TCP endpoint, and the client for one is a
        // Backbone client (`Discovery.py:730-758`). This port's `BackboneInterface` *is* that
        // client—it has no server side—so the same construction serves both.
        let interface = BackboneInterface(name: info.name, host: reachableOn,
                                          port: UInt16(truncatingIfNeeded: port))

        Reticulum.log("Auto-connecting discovered \(info.type) \(info.name)", level: .notice)
        interface.autoconnectHash = endpointHash(info)
        interface.autoconnectSource = info.networkID

        // Python's `_add_interface` keyword arguments, applied here directly
        // (`Discovery.py:767-776`). A non-transport node leaves the mode at its default rather
        // than adopting the peer as a gateway.
        // The transport this object is attached to, rather than `Reticulum.transportEnabled()`:
        // the global reads through `Reticulum.shared`, and autoconnect answers to the stack that
        // owns it.
        let transportEnabled = transport.transportEnabled
        if let configured = Reticulum.autoconnectInterfaceMode() {
            interface.mode = configured
        } else if transportEnabled {
            interface.mode = Self.acTransportMode
        }
        interface.gravity = Reticulum.autoconnectInterfaceGravity() ?? Self.acGravity
        if Reticulum.autoconnectAnnouncesToInternal() == true {
            interface.announcesToInternal = true
        }
        interface.bitrate = 5_000_000
        if transportEnabled {
            if let target = Reticulum.defaultArTarget() {
                interface.announceRateTarget = TimeInterval(target)
            }
            interface.announceRatePenalty = TimeInterval(Reticulum.defaultArPenalty())
            interface.announceRateGrace = Reticulum.defaultArGrace()
        }

        // A discovered endpoint that published its segment credentials is joined on that
        // segment, which is the whole point of `publish_ifac` (`Discovery.py:753-754`). The same
        // derivation the config path uses, so a discovered peer and a configured one land on
        // identical keys.
        if info.ifacNetname != nil || info.ifacNetkey != nil {
            interface.ifacNetname = info.ifacNetname
            interface.ifacNetkey = info.ifacNetkey
            Transport.configureIfac(on: interface, netname: info.ifacNetname,
                                    netkey: info.ifacNetkey, size: interface.ifacSize)
        }

        transport.register(interface: interface)
        try? interface.start()
        monitorInterface(interface)
    }

    /// Dial everything already persisted, so a restart doesn't have to re-hear every peer.
    /// Mirrors Python's `connect_discovered` (`Discovery.py:678-689`).
    public func connectDiscovered() {
        guard Reticulum.shouldAutoconnectDiscoveredInterfaces() else { return }
        for info in listDiscoveredInterfaces(onlyTransport: true) {
            if autoconnectCount() >= Reticulum.maxAutoconnectedInterfaces() { break }
            autoconnect(info)
        }
        initialAutoconnectRan = true
    }

    /// Whether any attached interface already reaches this endpoint.
    ///
    /// Mirrors `interface_exists` (`Discovery.py:700-712`): the autoconnect hash catches one this
    /// object dialled, and the host/port comparison catches one the operator configured by
    /// hand—which carries no hash.
    public func interfaceExists(_ info: DiscoveredInterfaceInfo) -> Bool {
        guard let transport else { return false }
        let hash = endpointHash(info)
        for interface in transport.interfaces {
            if let existing = interface.autoconnectHash, existing == hash { return true }

            guard let reachableOn = info.reachableOn else { continue }
            if let backbone = interface as? BackboneInterface {
                let hostMatch = backbone.host == reachableOn
                let portMatch = info.port == nil || Int(backbone.port) == info.port
                if hostMatch && portMatch { return true }
            }
            if let tcp = interface as? TCPClientInterface {
                let hostMatch = tcp.host == reachableOn
                let portMatch = info.port == nil || Int(tcp.port) == info.port
                if hostMatch && portMatch { return true }
            }
            if let i2p = interface as? I2PInterface, i2p.b32 == reachableOn { return true }
        }
        return false
    }

    /// How many attached interfaces this object dialled. Python: `autoconnect_count`.
    public func autoconnectCount() -> Int {
        transport?.interfaces.filter { $0.autoconnectHash != nil }.count ?? 0
    }

    /// How many attached interfaces exist only to bootstrap. Python: `bootstrap_interface_count`.
    public func bootstrapInterfaceCount() -> Int {
        transport?.interfaces.filter(\.bootstrapOnly).count ?? 0
    }

    // MARK: - Monitoring

    /// Start watching an auto-connected interface, starting the monitor job on the first one.
    /// Mirrors `monitor_interface` (`Discovery.py:602-609`).
    public func monitorInterface(_ interface: any Interface) {
        lock.lock()
        if !monitoredInterfaces.contains(where: { $0 === interface }) {
            monitoredInterfaces.append(interface)
        }
        let shouldStart = !monitoringAutoconnects
        if shouldStart {
            monitoringAutoconnects = true
            monitorGeneration &+= 1
        }
        let generation = monitorGeneration
        lock.unlock()

        guard shouldStart else { return }
        DispatchQueue.global(qos: .background).async { [weak self] in
            while true {
                Thread.sleep(forTimeInterval: Self.monitorInterval)
                guard let self else { return }
                self.lock.lock()
                let keepRunning = self.monitoringAutoconnects && self.monitorGeneration == generation
                self.lock.unlock()
                guard keepRunning else { return }
                self.monitorTick()
            }
        }
    }

    /// Stop the monitor job and forget every watched interface.
    public func stopMonitoring() {
        lock.lock()
        monitoringAutoconnects = false
        monitoredInterfaces.removeAll()
        lock.unlock()
    }

    /// One pass of the monitor job: stamp what went down, clear what came back, tear down what
    /// stayed down, and keep the slot count where the operator asked for it.
    ///
    /// Mirrors the body of `__monitor_job` (`Discovery.py:611-668`). Split out from the loop so
    /// it can be driven directly—a job that only runs on a five-second timer is a job no test
    /// observes.
    public func monitorTick() {
        guard let transport else { return }

        lock.lock()
        let watched = monitoredInterfaces
        lock.unlock()

        var detached: [any Interface] = []
        var onlineInterfaces = 0
        let now = Date().timeIntervalSince1970

        for interface in watched {
            if interface.isOnline {
                onlineInterfaces += 1
                if interface.autoconnectDown != nil {
                    Reticulum.log("Auto-discovered interface \(interface.name) reconnected",
                                  level: .notice)
                    interface.autoconnectDown = nil
                }
            } else if let downSince = interface.autoconnectDown {
                if now - downSince >= Self.detachThreshold { detached.append(interface) }
            } else {
                Reticulum.log("Auto-discovered interface \(interface.name) disconnected",
                              level: .debug)
                interface.autoconnectDown = now
            }
        }

        let maxAutoconnected = Reticulum.maxAutoconnectedInterfaces()
        let freeSlots = max(0, maxAutoconnected - autoconnectCount())
        let reservedSlots = maxAutoconnected / 4

        // A bootstrap interface exists to get a node its first peers. Once it has them, it is
        // one more attached interface carrying the same traffic (`Discovery.py:643-648`).
        if onlineInterfaces >= maxAutoconnected {
            for interface in transport.interfaces where interface.bootstrapOnly {
                Reticulum.log("Tearing down bootstrap-only \(interface.name) since target "
                              + "connected auto-discovered interface count has been reached",
                              level: .info)
                if !detached.contains(where: { $0 === interface }) { detached.append(interface) }
            }
        }

        // And back the other way: with no peers and no bootstrap interface, a node has no way
        // to find any (`Discovery.py:650-654`).
        if onlineInterfaces == 0, bootstrapInterfaceCount() == 0 {
            Reticulum.log("No auto-discovered interfaces connected, re-enabling bootstrap "
                          + "interfaces", level: .notice)
            reenableBootstrapInterfaces?()
        }

        // Top up toward the target, but leave a quarter of the slots free so a peer heard for
        // the first time still has somewhere to land (`Discovery.py:655-661`).
        if initialAutoconnectRan, freeSlots > reservedSlots {
            let candidates = listDiscoveredInterfaces(onlyAvailable: true, onlyTransport: true)
            if let selected = candidates.randomElement(), !interfaceExists(selected) {
                autoconnect(selected)
            }
        }

        for interface in detached { teardownInterface(interface) }
    }

    /// Detach an interface and stop watching it. Mirrors `teardown_interface`
    /// (`Discovery.py:670-673`).
    public func teardownInterface(_ interface: any Interface) {
        interface.stop()
        transport?.deregister(interface: interface)
        lock.lock()
        monitoredInterfaces.removeAll { $0 === interface }
        lock.unlock()
    }

    /// Compute a stable hash for the network endpoint described by `info`.
    /// Matches Python `InterfaceDiscovery.endpoint_hash(info)`.
    public func endpointHash(_ info: DiscoveredInterfaceInfo) -> Data {
        var specifier = ""
        if let ron  = info.reachableOn { specifier += ron }
        if let port = info.port        { specifier += ":\(port)" }
        return Hashes.fullHash(specifier.data(using: .utf8) ?? Data())
    }

    // MARK: - Helpers

    private func statusCode(for status: String) -> Int {
        switch status {
        case Self.statusAvailable: return Self.statusCodeAvailable
        case Self.statusUnknown:   return Self.statusCodeUnknown
        default:                   return Self.statusCodeStale
        }
    }

    // MARK: - Persistence

    private func writeFile(_ info: DiscoveredInterfaceInfo, to url: URL) {
        let packed = MsgPack.encode(packInfo(info))
        try? packed.write(to: url, options: .atomic)
    }

    private func loadFile(at url: URL) -> DiscoveredInterfaceInfo? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard case .map(let map) = (try? MsgPack.decode(data)) else { return nil }
        return unpackInfo(map)
    }

    private func packInfo(_ info: DiscoveredInterfaceInfo) -> MsgPack.Value {
        var pairs: [(MsgPack.Value, MsgPack.Value)] = [
            (.string(PersistKey.type),        .string(info.type)),
            (.string(PersistKey.transport),   .bool(info.transport)),
            (.string(PersistKey.name),        .string(info.name)),
            (.string(PersistKey.received),    .double(info.received)),
            (.string(PersistKey.stamp),       .bytes(info.stamp)),
            (.string(PersistKey.value),       .int(Int64(info.value))),
            (.string(PersistKey.transportID), .string(info.transportID)),
            (.string(PersistKey.networkID),   .string(info.networkID)),
            (.string(PersistKey.hops),        .int(Int64(info.hops))),
            (.string(PersistKey.latitude),    info.latitude.map { .double($0) } ?? .nil),
            (.string(PersistKey.longitude),   info.longitude.map { .double($0) } ?? .nil),
            (.string(PersistKey.height),      info.height.map { .double($0) } ?? .nil),
            (.string(PersistKey.discovered),  .double(info.discovered)),
            (.string(PersistKey.lastHeard),   .double(info.lastHeard)),
            (.string(PersistKey.heardCount),  .int(Int64(info.heardCount))),
        ]
        if let v = info.ifacNetname  { pairs.append((.string(PersistKey.ifacNetname), .string(v))) }
        if let v = info.ifacNetkey   { pairs.append((.string(PersistKey.ifacNetkey),  .string(v))) }
        if let v = info.reachableOn  { pairs.append((.string(PersistKey.reachableOn), .string(v))) }
        if let v = info.port         { pairs.append((.string(PersistKey.port),        .int(Int64(v)))) }
        if let v = info.frequency    { pairs.append((.string(PersistKey.frequency),   .double(v))) }
        if let v = info.bandwidth    { pairs.append((.string(PersistKey.bandwidth),   .double(v))) }
        if let v = info.sf           { pairs.append((.string(PersistKey.sf),          .int(Int64(v)))) }
        if let v = info.cr           { pairs.append((.string(PersistKey.cr),          .int(Int64(v)))) }
        if let v = info.modulation   { pairs.append((.string(PersistKey.modulation),  .string(v))) }
        if let v = info.channel      { pairs.append((.string(PersistKey.channel),     .int(Int64(v)))) }
        if let v = info.configEntry  { pairs.append((.string(PersistKey.configEntry), .string(v))) }
        if let v = info.discoveryHash { pairs.append((.string(PersistKey.discoveryHash), .bytes(v))) }
        if let v = info.operatorLxmfAddress { pairs.append((.string(PersistKey.operatorLxmfAddress), .string(v))) }
        return .map(pairs)
    }

    private func unpackInfo(_ map: [(MsgPack.Value, MsgPack.Value)]) -> DiscoveredInterfaceInfo? {
        var d: [String: MsgPack.Value] = [:]
        for (k, v) in map {
            if case .string(let key) = k { d[key] = v }
        }
        guard let type      = stringVal(d[PersistKey.type]),
              let transport  = boolVal(d[PersistKey.transport]),
              let name       = stringVal(d[PersistKey.name]),
              let received   = doubleVal(d[PersistKey.received]),
              let stamp      = bytesVal(d[PersistKey.stamp]),
              let value      = intVal(d[PersistKey.value]),
              let transportID = stringVal(d[PersistKey.transportID]),
              let networkID  = stringVal(d[PersistKey.networkID]),
              let hops       = intVal(d[PersistKey.hops]),
              let discovered = doubleVal(d[PersistKey.discovered]),
              let lastHeard  = doubleVal(d[PersistKey.lastHeard]),
              let heardCount = intVal(d[PersistKey.heardCount])
        else { return nil }

        return DiscoveredInterfaceInfo(
            type: type, transport: transport, name: name,
            received: received, stamp: stamp, value: value,
            transportID: transportID, networkID: networkID, hops: hops,
            latitude:  doubleValOpt(d[PersistKey.latitude]),
            longitude: doubleValOpt(d[PersistKey.longitude]),
            height:    doubleValOpt(d[PersistKey.height]),
            ifacNetname:  stringVal(d[PersistKey.ifacNetname]),
            ifacNetkey:   stringVal(d[PersistKey.ifacNetkey]),
            reachableOn:  stringVal(d[PersistKey.reachableOn]),
            port:         intVal(d[PersistKey.port]),
            frequency:    doubleValOpt(d[PersistKey.frequency]),
            bandwidth:    doubleValOpt(d[PersistKey.bandwidth]),
            sf:           intVal(d[PersistKey.sf]),
            cr:           intVal(d[PersistKey.cr]),
            modulation:   stringVal(d[PersistKey.modulation]),
            channel:      intVal(d[PersistKey.channel]),
            configEntry:  stringVal(d[PersistKey.configEntry]),
            discoveryHash: bytesVal(d[PersistKey.discoveryHash]),
            operatorLxmfAddress: stringVal(d[PersistKey.operatorLxmfAddress]),
            discovered: discovered, lastHeard: lastHeard, heardCount: heardCount
        )
    }

    // MARK: - Unpack helpers

    private func stringVal(_ v: MsgPack.Value?) -> String? {
        guard let v, case .string(let s) = v else { return nil }
        return s
    }
    private func boolVal(_ v: MsgPack.Value?) -> Bool? {
        guard let v, case .bool(let b) = v else { return nil }
        return b
    }
    private func doubleVal(_ v: MsgPack.Value?) -> TimeInterval? {
        guard let v else { return nil }
        switch v {
        case .double(let d): return d
        case .int(let n):    return Double(n)
        case .uint(let n):   return Double(n)
        default: return nil
        }
    }
    private func doubleValOpt(_ v: MsgPack.Value?) -> Double? {
        guard let v else { return nil }
        switch v {
        case .double(let d): return d
        case .int(let n):    return Double(n)
        case .uint(let n):   return Double(n)
        case .nil:           return nil
        default: return nil
        }
    }
    private func intVal(_ v: MsgPack.Value?) -> Int? {
        guard let v else { return nil }
        switch v {
        case .int(let n):  return Int(n)
        case .uint(let n): return Int(n)
        default: return nil
        }
    }
    private func bytesVal(_ v: MsgPack.Value?) -> Data? {
        guard let v, case .bytes(let d) = v else { return nil }
        return d
    }
}
