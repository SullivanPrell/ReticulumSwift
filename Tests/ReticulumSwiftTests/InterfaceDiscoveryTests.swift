import XCTest
@testable import ReticulumSwift

// MARK: - Mock stamp validators

private final class PassthroughStampValidator: DiscoveryStampValidator {
    let stampSize: Int = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data {
        Data(repeating: 0, count: max(1, expandRounds) * 256)
    }
    func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
}

private final class RejectStampValidator: DiscoveryStampValidator {
    let stampSize: Int = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data {
        Data(repeating: 0, count: max(1, expandRounds) * 256)
    }
    func stampValue(workblock: Data, stamp: Data) -> Int { 0 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { false }
}

// MARK: - Helpers

private func makePayload(info: [(MsgPack.Value, MsgPack.Value)], stamp: Data = Data(repeating: 0xAB, count: 32)) -> Data {
    let packed = MsgPack.encode(.map(info))
    return Data([0x00]) + packed + stamp
}

private let fakeTransportID = Data(repeating: 0x11, count: 16)
private let fakeNetworkIDData = Data(repeating: 0x22, count: 16)

private func backboneInfo(name: String = "TEST SERVER", reachableOn: String = "192.168.1.100", port: Int = 4965) -> [(MsgPack.Value, MsgPack.Value)] {
    [
        (.uint(0x00), .string("BackboneInterface")),
        (.uint(0x01), .bool(true)),
        (.uint(0xFE), .bytes(fakeTransportID)),
        (.uint(0xFF), .string(name)),
        (.uint(0x02), .string(reachableOn)),
        (.uint(0x06), .int(Int64(port))),
        (.uint(0x03), .nil),
        (.uint(0x04), .nil),
        (.uint(0x05), .nil),
    ]
}

private func rnodeInfo() -> [(MsgPack.Value, MsgPack.Value)] {
    [
        (.uint(0x00), .string("RNodeInterface")),
        (.uint(0x01), .bool(false)),
        (.uint(0xFE), .bytes(fakeTransportID)),
        (.uint(0xFF), .string("MY RNODE")),
        (.uint(0x09), .double(868000000.0)),   // FREQUENCY
        (.uint(0x0A), .double(125000.0)),       // BANDWIDTH
        (.uint(0x0B), .int(8)),                 // SPREADINGFACTOR
        (.uint(0x0C), .int(5)),                 // CODINGRATE
        (.uint(0x03), .nil),
        (.uint(0x04), .nil),
        (.uint(0x05), .nil),
    ]
}

private func i2pInfo() -> [(MsgPack.Value, MsgPack.Value)] {
    [
        (.uint(0x00), .string("I2PInterface")),
        (.uint(0x01), .bool(true)),
        (.uint(0xFE), .bytes(fakeTransportID)),
        (.uint(0xFF), .string("MY I2P")),
        (.uint(0x02), .string("example.b32.i2p")),
        (.uint(0x03), .nil),
        (.uint(0x04), .nil),
        (.uint(0x05), .nil),
    ]
}

private func weaveInfo() -> [(MsgPack.Value, MsgPack.Value)] {
    [
        (.uint(0x00), .string("WeaveInterface")),
        (.uint(0x01), .bool(false)),
        (.uint(0xFE), .bytes(fakeTransportID)),
        (.uint(0xFF), .string("MY WEAVE")),
        (.uint(0x09), .double(868000000.0)),   // FREQUENCY
        (.uint(0x0A), .double(250000.0)),       // BANDWIDTH
        (.uint(0x0E), .int(1)),                 // CHANNEL
        (.uint(0x0D), .string("LoRa")),         // MODULATION
        (.uint(0x03), .nil),
        (.uint(0x04), .nil),
        (.uint(0x05), .nil),
    ]
}

private func kissInfo() -> [(MsgPack.Value, MsgPack.Value)] {
    [
        (.uint(0x00), .string("KISSInterface")),
        (.uint(0x01), .bool(false)),
        (.uint(0xFE), .bytes(fakeTransportID)),
        (.uint(0xFF), .string("MY KISS")),
        (.uint(0x09), .double(144200000.0)),   // FREQUENCY
        (.uint(0x0A), .double(12000.0)),        // BANDWIDTH
        (.uint(0x0D), .string("FSK")),          // MODULATION
        (.uint(0x03), .nil),
        (.uint(0x04), .nil),
        (.uint(0x05), .nil),
    ]
}

// MARK: - Utility tests

final class InterfaceDiscoveryUtilTests: XCTestCase {

    // MARK: sanitizeName

    func testSanitizeNameNil() {
        XCTAssertNil(InterfaceAnnounceHandler.sanitizeName(nil))
    }

    func testSanitizeNameEmpty() {
        // Empty string → no valid chars → empty result
        let result = InterfaceAnnounceHandler.sanitizeName("")
        XCTAssertEqual(result, "")
    }

    func testSanitizeNameUppercasePreserved() {
        // All uppercase: start 'S' in A-Z, end '1' in 0-9
        XCTAssertEqual(InterfaceAnnounceHandler.sanitizeName("SERVER1"), "SERVER1")
    }

    func testSanitizeNameStripLeadingLower() {
        // "myServer": leading 'm','y' not in A-Z/0-9 → strip → "Server"
        // trailing: 'r','e','v','r','e' not in A-Z → strip → "S"
        XCTAssertEqual(InterfaceAnnounceHandler.sanitizeName("myServer"), "S")
    }

    func testSanitizeNameDigitStarts() {
        // "2 SERVER": '2' is in 0-9, kept; trailing 'R' in A-Z kept
        XCTAssertEqual(InterfaceAnnounceHandler.sanitizeName("2 SERVER"), "2 SERVER")
    }

    func testSanitizeNameCollapseMultipleSpaces() {
        // "A     B" → collapse to "A B"; both A and B are in A-Z
        XCTAssertEqual(InterfaceAnnounceHandler.sanitizeName("A     B"), "A B")
    }

    func testSanitizeNameStripNonASCII() {
        // "SÉRVEUR" → 'É' is non-ASCII → stripped → "SRVEUR"
        // S in A-Z, R in A-Z → "SRVEUR"
        let result = InterfaceAnnounceHandler.sanitizeName("SÉRVEUR")
        XCTAssertEqual(result, "SRVEUR")
    }

    func testSanitizeNameStripLeadingSpecial() {
        // "!@#SERVER" → strip '!','@','#' → "SERVER"
        XCTAssertEqual(InterfaceAnnounceHandler.sanitizeName("!@#SERVER"), "SERVER")
    }

    // MARK: isIPAddress

    func testIsIPAddressIPv4Valid() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isIPAddress("192.168.1.1"))
    }

    func testIsIPAddressIPv6Valid() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isIPAddress("::1"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isIPAddress("2001:db8::1"))
    }

    func testIsIPAddressInvalid() {
        XCTAssertFalse(InterfaceDiscoveryHelpers.isIPAddress("not-an-ip"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isIPAddress("256.0.0.1"))
        XCTAssertFalse(InterfaceDiscoveryHelpers.isIPAddress(""))
    }

    // MARK: isHostname

    func testIsHostnameValid() {
        XCTAssertTrue(InterfaceDiscoveryHelpers.isHostname("example.com"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isHostname("my-server.local"))
        XCTAssertTrue(InterfaceDiscoveryHelpers.isHostname("a.b.c.example.org"))
    }

    func testIsHostnameAllNumericTLDRejected() {
        // TLD is all numeric → rejected (looks like bare IP component)
        XCTAssertFalse(InterfaceDiscoveryHelpers.isHostname("example.123"))
    }

    func testIsHostnameTooLong() {
        // > 253 chars → rejected
        let long = String(repeating: "a", count: 64) + "." + String(repeating: "b", count: 64) + "." + String(repeating: "c", count: 64) + "." + String(repeating: "d", count: 65) + ".com"
        XCTAssertFalse(InterfaceDiscoveryHelpers.isHostname(long))
    }
}

// MARK: - InterfaceAnnounceHandler decode tests

final class InterfaceAnnounceHandlerTests: XCTestCase {

    private func makeIdentity() -> Identity { Identity() }
    private var passthrough: PassthroughStampValidator { PassthroughStampValidator() }

    func testDecodeBackboneAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: backboneInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: makeIdentity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "BackboneInterface")
        XCTAssertEqual(result?.transport, true)
        XCTAssertEqual(result?.name, "TEST SERVER")
        XCTAssertEqual(result?.reachableOn, "192.168.1.100")
        XCTAssertEqual(result?.port, 4965)
    }

    func testDecodeRNodeAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: rnodeInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: makeIdentity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "RNodeInterface")
        XCTAssertEqual(result?.frequency ?? 0.0, 868000000.0, accuracy: 1.0)
        XCTAssertEqual(result?.bandwidth ?? 0.0, 125000.0, accuracy: 1.0)
        XCTAssertEqual(result?.sf, 8)
        XCTAssertEqual(result?.cr, 5)
    }

    func testDecodeI2PAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: i2pInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: makeIdentity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "I2PInterface")
        XCTAssertEqual(result?.reachableOn, "example.b32.i2p")
    }

    func testDecodeWeaveAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: weaveInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: makeIdentity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "WeaveInterface")
        XCTAssertEqual(result?.channel, 1)
        XCTAssertEqual(result?.modulation, "LoRa")
    }

    func testDecodeKISSAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: kissInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: makeIdentity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "KISSInterface")
        XCTAssertEqual(result?.modulation, "FSK")
        XCTAssertEqual(result?.frequency ?? 0.0, 144200000.0, accuracy: 1.0)
    }

    func testInvalidInterfaceTypeIgnored() {
        var called = false
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { _ in called = true }
        let badInfo: [(MsgPack.Value, MsgPack.Value)] = [
            (.uint(0x00), .string("GhostInterface")),
            (.uint(0x01), .bool(false)),
            (.uint(0xFE), .bytes(fakeTransportID)),
            (.uint(0xFF), .string("GHOST")),
            (.uint(0x03), .nil), (.uint(0x04), .nil), (.uint(0x05), .nil),
        ]
        let payload = makePayload(info: badInfo)
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertFalse(called, "callback must not fire for unknown interface type")
    }

    func testStampValidationFailureBlocksCallback() {
        var called = false
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: RejectStampValidator()) { _ in called = true }
        let payload = makePayload(info: backboneInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertFalse(called, "callback must not fire when stamp is invalid")
    }

    func testPayloadTooShortIgnored() {
        var called = false
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { _ in called = true }
        // Only 3 bytes — shorter than flags(1) + stamp(32)
        let shortPayload = Data([0x00, 0x01, 0x02])
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: shortPayload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertFalse(called)
    }

    func testNilAppDataIgnored() {
        var called = false
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { _ in called = true }
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: nil,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertFalse(called)
    }

    func testAspectFilter() {
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough)
        XCTAssertEqual(handler.aspectFilter, "rnstransport.discovery.interface")
    }

    func testTransportIDStoredAsHex() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: backboneInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        // fakeTransportID is 16 bytes of 0x11 → "11111111111111111111111111111111"
        XCTAssertEqual(result?.transportID, String(repeating: "11", count: 16))
    }

    func testDiscoveryHashComputed() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: backboneInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result?.discoveryHash)
        XCTAssertEqual(result?.discoveryHash?.count, 32)
        // discoveryHash = SHA256(transportID_hex + sanitized_name as UTF-8)
        let transportIDHex = String(repeating: "11", count: 16)
        let name = "TEST SERVER"
        let expected = Hashes.fullHash((transportIDHex + name).data(using: .utf8)!)
        XCTAssertEqual(result?.discoveryHash, expected)
    }

    func testBackboneConfigEntryContainsHost() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: backboneInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        let entry = result?.configEntry ?? ""
        XCTAssertTrue(entry.contains("BackboneInterface") || entry.contains("TCPClientInterface"),
                      "config_entry should specify connection interface")
        XCTAssertTrue(entry.contains("192.168.1.100"), "config_entry should include host")
        XCTAssertTrue(entry.contains("4965"), "config_entry should include port")
    }

    func testRNodeConfigEntryContainsFrequency() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        let payload = makePayload(info: rnodeInfo())
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        let entry = result?.configEntry ?? ""
        XCTAssertTrue(entry.contains("RNodeInterface"), "config_entry should specify type")
        XCTAssertTrue(entry.contains("868000000"), "config_entry should include frequency")
    }

    func testIFACNetNameStoredInInfo() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        var info = backboneInfo()
        info.append((.uint(0x07), .string("MyNetwork")))   // IFAC_NETNAME
        info.append((.uint(0x08), .string("secret123")))   // IFAC_NETKEY
        let payload = makePayload(info: info)
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertEqual(result?.ifacNetname, "MyNetwork")
        XCTAssertEqual(result?.ifacNetkey, "secret123")
    }

    func testTCPServerAnnounce() {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { result = $0 }
        var info = backboneInfo()
        // Change type to TCPServerInterface
        info[0] = (.uint(0x00), .string("TCPServerInterface"))
        let payload = makePayload(info: info)
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.type, "TCPServerInterface")
    }

    func testFlagEncryptedSkipped() {
        // Encrypted payloads without a network identity available should be silently skipped
        var called = false
        let handler = InterfaceAnnounceHandler(requiredValue: 14, stampValidator: passthrough) { _ in called = true }
        let packed = MsgPack.encode(.map(backboneInfo()))
        let stamp = Data(repeating: 0xAB, count: 32)
        let flagEncrypted: UInt8 = 0b00000010
        let payload = Data([flagEncrypted]) + packed + stamp
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(), appData: payload,
                                 announcePacketHash: Data(repeating: 0, count: 4), isPathResponse: false)
        XCTAssertFalse(called, "encrypted payloads without decrypt key must be silently skipped")
    }
}

// MARK: - InterfaceDiscovery persistence tests

final class InterfaceDiscoveryPersistenceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("iface_disc_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    private func makeInfo(
        type: String = "BackboneInterface",
        name: String = "TEST SERVER",
        transport: Bool = true,
        lastHeard: TimeInterval = Date().timeIntervalSince1970,
        heardCount: Int = 0
    ) -> DiscoveredInterfaceInfo {
        let transportIDHex = String(repeating: "aa", count: 16)
        let discoveryHash = Hashes.fullHash((transportIDHex + name).data(using: .utf8)!)
        return DiscoveredInterfaceInfo(
            type: type, transport: transport, name: name,
            received: lastHeard, stamp: Data(repeating: 0, count: 32), value: 14,
            transportID: transportIDHex,
            networkID: String(repeating: "bb", count: 16),
            hops: 1,
            latitude: nil, longitude: nil, height: nil,
            ifacNetname: nil, ifacNetkey: nil,
            reachableOn: "10.0.0.1", port: 4965,
            frequency: nil, bandwidth: nil, sf: nil, cr: nil,
            modulation: nil, channel: nil,
            configEntry: "[[TEST SERVER]]\n  type = BackboneInterface",
            discoveryHash: discoveryHash,
            discovered: lastHeard, lastHeard: lastHeard, heardCount: heardCount,
            status: nil, statusCode: nil
        )
    }

    func testInterfaceDiscoveredCreatesFile() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let info = makeInfo()
        disc.interfaceDiscovered(info)

        let hexHash = RNSUtilities.hexrep(info.discoveryHash!, delimit: false)
        let filePath = tempDir.appendingPathComponent(hexHash).path
        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath),
                      "Discovered interface file should be created at \(filePath)")
    }

    func testInterfaceDiscoveredIncrementsHeardCount() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let info = makeInfo()
        disc.interfaceDiscovered(info)
        disc.interfaceDiscovered(info)

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed.first?.heardCount, 1, "second discovery should increment heardCount to 1")
    }

    func testListDiscoveredInterfacesStatusAvailable() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let info = makeInfo(lastHeard: Date().timeIntervalSince1970)
        disc.interfaceDiscovered(info)

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertEqual(listed.first?.status, "available")
    }

    func testListDiscoveredInterfacesStatusUnknown() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        // 25 hours ago
        let oldTime = Date().timeIntervalSince1970 - 25 * 3600
        let info = makeInfo(lastHeard: oldTime)
        disc.interfaceDiscovered(info)

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertEqual(listed.first?.status, "unknown")
    }

    func testListDiscoveredInterfacesStatusStale() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        // 4 days ago
        let oldTime = Date().timeIntervalSince1970 - 4 * 24 * 3600
        let info = makeInfo(lastHeard: oldTime)
        disc.interfaceDiscovered(info)

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertEqual(listed.first?.status, "stale")
    }

    func testListDiscoveredInterfacesRemovesVeryOld() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        // 8 days ago — beyond THRESHOLD_REMOVE
        let veryOld = Date().timeIntervalSince1970 - 8 * 24 * 3600
        let info = makeInfo(lastHeard: veryOld)
        disc.interfaceDiscovered(info)

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertTrue(listed.isEmpty, "Interfaces older than 7d should be removed and not listed")
    }

    func testListOnlyAvailableFilters() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let now = Date().timeIntervalSince1970
        // Add two interfaces: one recent (available), one old (unknown)
        disc.interfaceDiscovered(makeInfo(name: "AVAIL", lastHeard: now))
        disc.interfaceDiscovered(makeInfo(name: "OLD", lastHeard: now - 25 * 3600))

        let available = disc.listDiscoveredInterfaces(onlyAvailable: true)
        XCTAssertEqual(available.count, 1)
        XCTAssertEqual(available.first?.name, "AVAIL")
    }

    func testListOnlyTransportFilters() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let now = Date().timeIntervalSince1970
        disc.interfaceDiscovered(makeInfo(name: "TRANSPORT", transport: true, lastHeard: now))
        disc.interfaceDiscovered(makeInfo(name: "NOTRANSPORT", transport: false, lastHeard: now))

        let transportOnly = disc.listDiscoveredInterfaces(onlyTransport: true)
        XCTAssertEqual(transportOnly.count, 1)
        XCTAssertEqual(transportOnly.first?.name, "TRANSPORT")
    }

    func testListSortedByStatusCode() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        let now = Date().timeIntervalSince1970
        disc.interfaceDiscovered(makeInfo(name: "STALE", lastHeard: now - 4 * 24 * 3600))
        disc.interfaceDiscovered(makeInfo(name: "AVAIL", lastHeard: now))
        disc.interfaceDiscovered(makeInfo(name: "UNKNOWN", lastHeard: now - 25 * 3600))

        let listed = disc.listDiscoveredInterfaces()
        XCTAssertEqual(listed.count, 3)
        // Available first (highest status code), then unknown, then stale
        XCTAssertEqual(listed[0].name, "AVAIL")
        XCTAssertEqual(listed[1].name, "UNKNOWN")
        XCTAssertEqual(listed[2].name, "STALE")
    }

    func testEndpointHashConsistency() {
        let disc = InterfaceDiscovery(storagePath: tempDir.path)
        var info1 = makeInfo()
        var info2 = makeInfo()
        info2.reachableOn = "10.0.0.2"

        let hash1a = disc.endpointHash(info1)
        let hash1b = disc.endpointHash(info1)
        let hash2  = disc.endpointHash(info2)

        XCTAssertEqual(hash1a, hash1b, "Same info → same endpoint hash")
        XCTAssertNotEqual(hash1a, hash2, "Different host → different endpoint hash")
    }
}
