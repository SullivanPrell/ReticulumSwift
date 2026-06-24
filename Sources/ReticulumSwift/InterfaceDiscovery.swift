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
    public static let defaultRequiredValue: Int = 14

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
        guard let appData, appData.count > stampValidator.stampSize + 1 else { return }
        let flags   = appData[0]
        let payload = appData.dropFirst()

        let encrypted = (flags & Self.flagEncrypted) != 0
        if encrypted {
            // Encrypted discovery announces require the network identity for decryption;
            // without it we can't decode, so silently skip.
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

        return info
    }

    // MARK: - Config entry builders

    private func buildBackboneConfigEntry(name: String, host: String, port: Int,
                                          transportID: String,
                                          netname: String?, netkey: String?,
                                          interfaceType: String) -> String {
        // On Apple platforms use BackboneInterface; TCP fallback would need separate logic
        let connType = "BackboneInterface"
        let remoteKey = "remote"
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
        // san_map = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        let sanSet = CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
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
            // Update existing entry — preserve discovered timestamp, increment heard_count
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

            // Age filtering
            let heardDelta = now - entry.lastHeard
            let shouldRemove: Bool = {
                if heardDelta > Self.thresholdRemove { return true }
                if !Self.discoverableTypes.contains(entry.type) { return true }
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
