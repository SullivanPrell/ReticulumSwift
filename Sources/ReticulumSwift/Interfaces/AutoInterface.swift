import Foundation

#if canImport(Darwin)
import Darwin

/// Automatic LAN/WLAN peer discovery using IPv6 multicast.
///
/// Wire-compatible with `RNS.Interfaces.AutoInterface` (Python):
/// - Sends a 32-byte discovery beacon (`sha256(groupID + linkLocalAddr)`) to
///   the IPv6 multicast address every `announceInterval` seconds.
/// - Verifies received beacons and tracks peers by their link-local address.
/// - Exchanges raw Reticulum packet bytes with peers via unicast UDP on
///   `dataPort`. No HDLC framing — each datagram is one packet.
///
/// Default group: "reticulum" (matches Python default).
/// Default ports: discovery=29716, data=42671.
/// Default multicast address: ff12:0:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx
///   where the x-groups are derived from sha256("reticulum").
public final class AutoInterface: Interface {

    // MARK: - Protocol constants

    public static let defaultGroupID        = Data("reticulum".utf8)
    public static let defaultDiscoveryPort  = UInt16(29716)
    public static let defaultDataPort       = UInt16(42671)
    public static let announceInterval      = TimeInterval(1.6)
    public static let peeringTimeout        = TimeInterval(22.0)
    public static let peerJobInterval       = TimeInterval(4.0)

    /// Interfaces ignored on macOS (matching Python DARWIN_IGNORE_IFS).
    private static let darwinIgnoredIfs: Set<String> = ["awdl0", "llw0", "lo0", "en5"]

    // MARK: - Public interface conformance

    public let name: String
    public private(set) var bitrate: Int = 10_000_000
    public private(set) var isOnline: Bool = false

    // Python AutoInterface: HW_MTU = 1196, FIXED_MTU = True
    public let hwMtu: Int? = 1_196
    public let fixedMtu: Bool = true

    public var inboundHandler: ((Packet, any Interface) -> Void)?
    public var rawInboundHandler: ((Data, any Interface) -> Void)?
    public var recursivePrs: Bool = false
    public var announcesFromInternal: Bool = true

    public private(set) var rxBytes: Int = 0
    public private(set) var txBytes: Int = 0
    public var ifacIdentity: Identity?
    public var ifacKey: Data?
    public var ifacSize: Int = Constants.defaultIfacSize

    // MARK: - Configuration

    public let groupID: Data
    public let discoveryPort: UInt16
    public let dataPort: UInt16
    private let allowedInterfaces: Set<String>
    private let ignoredInterfaces: Set<String>

    // MARK: - State

    /// IPv6 link-local address per interface name.
    private var adoptedInterfaces: [String: String] = [:]
    /// All our own link-local addresses (to ignore our own beacons).
    private var ownLinkLocalAddresses: Set<String> = []
    /// Peer table: link-local addr → (ifname, lastHeard, lastOutbound).
    private var peers: [String: (ifname: String, lastHeard: Date, lastOutbound: Date)] = [:]
    private let peersLock = NSLock()

    private var discoverySocket: Int32 = -1
    private var dataSocket: Int32 = -1
    private let queue = DispatchQueue(label: "AutoInterface", attributes: .concurrent)
    private var announceTimers: [DispatchSourceTimer] = []
    private var peerJobTimer: DispatchSourceTimer?

    // MARK: - Derived

    /// IPv6 multicast address derived from groupID.
    private let mcastAddress: String

    // MARK: - Init

    /// Python `AutoInterface.__str__` returns `"AutoInterface[<name>]"`.
    public var displayName: String { "AutoInterface[\(name)]" }

    public init(
        name: String,
        groupID: Data = AutoInterface.defaultGroupID,
        discoveryPort: UInt16 = AutoInterface.defaultDiscoveryPort,
        dataPort: UInt16 = AutoInterface.defaultDataPort,
        allowedInterfaces: [String] = [],
        ignoredInterfaces: [String] = []
    ) {
        self.name = name
        self.groupID = groupID
        self.discoveryPort = discoveryPort
        self.dataPort = dataPort
        self.allowedInterfaces = Set(allowedInterfaces)
        self.ignoredInterfaces = Set(ignoredInterfaces)

        // Derive multicast address: ff12:0:xxxx:xxxx:xxxx:xxxx:xxxx:xxxx
        let h = Hashes.fullHash(groupID)
        let g = Array(h)
        func pair(_ lo: Int, _ hi: Int) -> String {
            String(format: "%04x", Int(g[lo]) + (Int(g[hi]) << 8))
        }
        let gt = "0:\(pair(3,2)):\(pair(5,4)):\(pair(7,6)):\(pair(9,8)):\(pair(11,10)):\(pair(13,12))"
        self.mcastAddress = "ff12:\(gt)"
    }

    // MARK: - Lifecycle

    public func start() throws {
        discoverInterfaces()
        guard !adoptedInterfaces.isEmpty else {
            return // No suitable IPv6 interfaces — stay offline but don't throw
        }
        try setupDataSocket()
        try setupDiscoverySocket()
        startBeaconLoops()
        startPeerJobLoop()
        startReceiveLoops()
        isOnline = true
    }

    public func stop() {
        isOnline = false
        announceTimers.forEach { $0.cancel() }
        announceTimers.removeAll()
        peerJobTimer?.cancel()
        peerJobTimer = nil
        if discoverySocket >= 0 { Darwin.close(discoverySocket); discoverySocket = -1 }
        if dataSocket >= 0 { Darwin.close(dataSocket); dataSocket = -1 }
    }

    public func send(_ packet: Packet) throws {
        guard isOnline else { return }
        let raw = wrapIfac(try packet.pack())
        txBytes += raw.count
        peersLock.lock()
        let currentPeers = peers
        peersLock.unlock()
        for (addr, info) in currentPeers {
            sendDataToPeer(addr: addr, ifname: info.ifname, data: raw)
        }
    }

    // MARK: - Interface discovery

    private func discoverInterfaces() {
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifap) == 0, let first = ifap else { return }
        defer { freeifaddrs(first) }

        var ifa = Optional(first)
        while let current = ifa {
            defer { ifa = current.pointee.ifa_next }
            let ifname = String(cString: current.pointee.ifa_name)
            guard current.pointee.ifa_addr != nil else { continue }
            let family = Int32(current.pointee.ifa_addr.pointee.sa_family)
            guard family == AF_INET6 else { continue }

            // Apply filter rules.
            if Self.darwinIgnoredIfs.contains(ifname) && !allowedInterfaces.contains(ifname) { continue }
            if ignoredInterfaces.contains(ifname) { continue }
            if !allowedInterfaces.isEmpty && !allowedInterfaces.contains(ifname) { continue }

            // Extract the IPv6 address.
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            current.pointee.ifa_addr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                _ = getnameinfo(sa, socklen_t(MemoryLayout<sockaddr_in6>.size),
                                &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            }
            var addr = String(cString: host)

            // We only want link-local addresses (fe80::).
            guard addr.lowercased().hasPrefix("fe80:") else { continue }

            // Strip the scope suffix (e.g. %en0) for storage.
            if let pct = addr.firstIndex(of: "%") {
                addr = String(addr[..<pct])
            }

            adoptedInterfaces[ifname] = addr
            ownLinkLocalAddresses.insert(addr)
        }
    }

    // MARK: - Socket setup

    private func setupDataSocket() throws {
        let s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { throw AutoInterfaceError.socketError("data socket") }
        var reuseVal: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &reuseVal, socklen_t(MemoryLayout.size(ofValue: reuseVal)))
        setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &reuseVal, socklen_t(MemoryLayout.size(ofValue: reuseVal)))
        var addr = sockaddr_in6()
        addr.sin6_family = UInt8(AF_INET6)
        addr.sin6_port = dataPort.bigEndian
        addr.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(s, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bound == 0 else { Darwin.close(s); throw AutoInterfaceError.socketError("bind data") }
        dataSocket = s
    }

    private func setupDiscoverySocket() throws {
        let s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { throw AutoInterfaceError.socketError("discovery socket") }
        var reuseVal: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &reuseVal, socklen_t(MemoryLayout.size(ofValue: reuseVal)))
        setsockopt(s, SOL_SOCKET, SO_REUSEPORT, &reuseVal, socklen_t(MemoryLayout.size(ofValue: reuseVal)))

        var addr6 = sockaddr_in6()
        addr6.sin6_family = UInt8(AF_INET6)
        addr6.sin6_port = discoveryPort.bigEndian
        addr6.sin6_addr = in6addr_any
        let bound = withUnsafePointer(to: &addr6) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(s, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
        guard bound == 0 else { Darwin.close(s); throw AutoInterfaceError.socketError("bind discovery") }

        // Join multicast group on each adopted interface.
        for (ifname, _) in adoptedInterfaces {
            joinMulticast(socket: s, mcastAddr: mcastAddress, ifname: ifname)
        }
        discoverySocket = s
    }

    private func joinMulticast(socket s: Int32, mcastAddr: String, ifname: String) {
        var mreq = ipv6_mreq()
        guard inet_pton(AF_INET6, mcastAddr, &mreq.ipv6mr_multiaddr) == 1 else { return }
        mreq.ipv6mr_interface = UInt32(if_nametoindex(ifname))
        setsockopt(s, IPPROTO_IPV6, IPV6_JOIN_GROUP, &mreq, socklen_t(MemoryLayout<ipv6_mreq>.size))
    }

    // MARK: - Beacon sending

    private func startBeaconLoops() {
        for (ifname, linkLocal) in adoptedInterfaces {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now(), repeating: AutoInterface.announceInterval)
            timer.setEventHandler { [weak self] in
                self?.sendBeacon(ifname: ifname, linkLocal: linkLocal)
            }
            timer.resume()
            announceTimers.append(timer)
        }
    }

    private func sendBeacon(ifname: String, linkLocal: String) {
        let token = Hashes.fullHash(groupID + Data(linkLocal.utf8))
        let s = socket(AF_INET6, SOCK_DGRAM, IPPROTO_UDP)
        guard s >= 0 else { return }
        defer { Darwin.close(s) }

        var mcastIfIdx = UInt32(if_nametoindex(ifname))
        setsockopt(s, IPPROTO_IPV6, IPV6_MULTICAST_IF, &mcastIfIdx, socklen_t(MemoryLayout<UInt32>.size))

        var dst = sockaddr_in6()
        dst.sin6_family = UInt8(AF_INET6)
        dst.sin6_port = discoveryPort.bigEndian
        guard inet_pton(AF_INET6, mcastAddress, &dst.sin6_addr) == 1 else { return }

        token.withUnsafeBytes { ptr in
            _ = withUnsafePointer(to: &dst) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(s, ptr.baseAddress, ptr.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }

    // MARK: - Receive loops

    private func startReceiveLoops() {
        // Discovery socket — receive peer beacons.
        queue.async { [weak self] in
            self?.discoveryReceiveLoop()
        }
        // Data socket — receive packet datagrams.
        queue.async { [weak self] in
            self?.dataReceiveLoop()
        }
    }

    private func discoveryReceiveLoop() {
        var buf = [UInt8](repeating: 0, count: 64)
        var src = sockaddr_in6()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
        while isOnline, discoverySocket >= 0 {
            let n = withUnsafeMutablePointer(to: &src) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(discoverySocket, &buf, buf.count, 0, sa, &srcLen)
                }
            }
            guard n == 32 else { continue }
            var srcStr = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            withUnsafePointer(to: &src) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    _ = getnameinfo(sa, srcLen, &srcStr, socklen_t(srcStr.count), nil, 0, NI_NUMERICHOST)
                }
            }
            var addrStr = String(cString: srcStr)
            // Strip scope suffix.
            if let pct = addrStr.firstIndex(of: "%") { addrStr = String(addrStr[..<pct]) }

            let receivedToken = Data(buf[0..<32])
            let expected = Hashes.fullHash(groupID + Data(addrStr.utf8))
            guard receivedToken == expected else { continue }

            // Don't add ourselves.
            if ownLinkLocalAddresses.contains(addrStr) { continue }

            // Find which of our interfaces is on the same link.
            let ifIdx = src.sin6_scope_id
            let ifname = findInterface(byIndex: ifIdx) ?? adoptedInterfaces.keys.first ?? ""
            addPeer(addr: addrStr, ifname: ifname)
        }
    }

    private func dataReceiveLoop() {
        var buf = [UInt8](repeating: 0, count: 65536)
        var src = sockaddr_in6()
        var srcLen = socklen_t(MemoryLayout<sockaddr_in6>.size)
        while isOnline, dataSocket >= 0 {
            let n = withUnsafeMutablePointer(to: &src) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    recvfrom(dataSocket, &buf, buf.count, 0, sa, &srcLen)
                }
            }
            guard n > 0 else { continue }
            let raw = Data(buf[0..<n])
            rxBytes += raw.count
            if let h = rawInboundHandler {
                h(raw, self)
            } else if let packet = try? Packet.unpack(raw) {
                inboundHandler?(packet, self)
            }
        }
    }

    // MARK: - Peer management

    private func addPeer(addr: String, ifname: String) {
        peersLock.lock()
        defer { peersLock.unlock() }
        if peers[addr] == nil {
            peers[addr] = (ifname: ifname, lastHeard: Date(), lastOutbound: Date())
        } else {
            let existing = peers[addr]!
            peers[addr] = (ifname: existing.ifname, lastHeard: Date(), lastOutbound: existing.lastOutbound)
        }
    }

    private func startPeerJobLoop() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + AutoInterface.peerJobInterval,
                       repeating: AutoInterface.peerJobInterval)
        timer.setEventHandler { [weak self] in
            self?.peerJob()
        }
        timer.resume()
        peerJobTimer = timer
    }

    private func peerJob() {
        let now = Date()
        peersLock.lock()
        peers = peers.filter { now.timeIntervalSince($0.value.lastHeard) < AutoInterface.peeringTimeout }
        peersLock.unlock()
    }

    private func sendDataToPeer(addr: String, ifname: String, data: Data) {
        guard dataSocket >= 0 else { return }
        let scopedAddr = "\(addr)%\(ifname)"
        var hints = addrinfo()
        hints.ai_family = AF_INET6
        hints.ai_socktype = SOCK_DGRAM
        var res: UnsafeMutablePointer<addrinfo>? = nil
        let portStr = String(dataPort)
        guard getaddrinfo(scopedAddr, portStr, &hints, &res) == 0, let first = res else { return }
        defer { freeaddrinfo(first) }
        data.withUnsafeBytes { ptr in
            _ = sendto(dataSocket, ptr.baseAddress, ptr.count, 0,
                       first.pointee.ai_addr, first.pointee.ai_addrlen)
        }
    }

    private func findInterface(byIndex idx: UInt32) -> String? {
        guard idx > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
        guard if_indextoname(idx, &buf) != nil else { return nil }
        return String(cString: buf)
    }
}

// MARK: - Error

public enum AutoInterfaceError: Error {
    case socketError(String)
}

#endif // canImport(Darwin)
