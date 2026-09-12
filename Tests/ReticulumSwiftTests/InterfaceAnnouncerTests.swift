//===----------------------------------------------------------------------===//
// Copyright (c) 2026 ReticulumSwift contributors.
//
// Licensed under the Reticulum License. See LICENSE in the repository root for
// the full license text, and NOTICE for attribution of the upstream project
// this file is derived from.
//
// SPDX-License-Identifier: LicenseRef-Reticulum
//===----------------------------------------------------------------------===//

import XCTest
@testable import ReticulumSwift

/// A generator that returns a fixed stamp, so a test never pays for proof-of-work.
///
/// It records the material and cost it was asked for, which is how the announce-data tests
/// check that the stamp is taken over the packed info rather than over something else.
private final class FixedStampGenerator: DiscoveryStampGenerator {
    private(set) var lastMaterial: Data?
    private(set) var lastTargetCost: Int?
    private(set) var lastExpandRounds: Int?
    var stamp: Data? = Data(repeating: 0xAB, count: 32)
    private(set) var callCount = 0

    func generateStamp(material: Data, targetCost: Int, expandRounds: Int) -> Data? {
        lastMaterial = material
        lastTargetCost = targetCost
        lastExpandRounds = expandRounds
        callCount += 1
        return stamp
    }
}

/// Accepts whatever it's given, so a round-trip test measures the payload rather than the
/// proof-of-work. `stampValue` reports well above any required value.
private final class AcceptAnyStamp: DiscoveryStampValidator {
    let stampSize: Int = 32
    func stampWorkblock(material: Data, expandRounds: Int) -> Data { material }
    func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
    func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
}

/// The interface-discovery publish side—Python's `Discovery.InterfaceAnnouncer`.
///
/// The receive side has been complete since RNS 1.4.0, so the strongest assertion available is
/// the round trip: a payload this class builds has to decode through this port's own
/// `InterfaceAnnounceHandler`, which was itself written against Python announces.
final class InterfaceAnnouncerTests: XCTestCase {

    private var transport: Transport!
    private var generator: FixedStampGenerator!

    override func setUp() {
        super.setUp()
        transport = Transport()
        transport.transportIdentity = Identity()
        generator = FixedStampGenerator()
    }

    private func announcer() throws -> InterfaceAnnouncer {
        try XCTUnwrap(InterfaceAnnouncer(transport: transport, stampGenerator: generator))
    }

    /// A discoverable TCP listener, configured the way the config path would leave it.
    private func discoverableServer(name: String = "hub",
                                    reachableOn: String? = "hub.example.net") -> TCPServerInterface {
        let server = TCPServerInterface(name: name, port: 4965)
        server.discoverable = true
        server.discoveryAnnounceInterval = 21_600
        server.discoveryName = "Example hub"
        server.reachableOn = reachableOn
        return server
    }

    /// Decode an announce payload back into its msgpack fields, dropping the flags byte and
    /// the trailing stamp the way the receive side does.
    private func fields(_ appData: Data,
                        stampSize: Int = 32) throws -> [UInt64: MsgPack.Value] {
        let payload = appData.dropFirst()
        let packed = Data(payload.dropLast(stampSize))
        guard case .map(let entries) = try MsgPack.decode(packed) else {
            XCTFail("announce payload is not a msgpack map")
            return [:]
        }
        var out: [UInt64: MsgPack.Value] = [:]
        for (k, v) in entries where { if case .uint = k { return true } else { return false } }() {
            if case .uint(let n) = k { out[n] = v }
        }
        return out
    }

    // MARK: - Destination

    /// `Destination(identity, IN, SINGLE, APP_NAME, "discovery", "interface")`
    /// (`Discovery.py:66-67`), which is the aspect the receive side filters on.
    func testTheDestinationMatchesTheReferenceAspects() throws {
        let a = try announcer()
        XCTAssertTrue(a.discoveryDestination.getName().hasPrefix("rnstransport.discovery.interface"),
                      a.discoveryDestination.getName())
        XCTAssertEqual(a.discoveryDestination.getType(), .single)
    }

    /// Python announces from the network identity when one is configured, so a segmented
    /// network's discovery announces are attributable to the segment (`Discovery.py:64-65`).
    func testTheNetworkIdentityOwnsTheDestinationWhenConfigured() throws {
        let network = Identity()
        transport.setNetworkIdentity(network)

        let a = try announcer()
        XCTAssertTrue(a.discoveryDestination.getName().hasSuffix(network.hash.hexString),
                      "the destination must belong to the network identity")
    }

    // MARK: - The type gate

    /// `DISCOVERABLE_INTERFACE_TYPES` (`Discovery.py:47-48`) gates the whole builder, and it
    /// holds the *published* type name—so a spawned TCP client is judged as the
    /// `TCPClientInterface` it presents as.
    func testAnUndiscoverableTypeProducesNothing() throws {
        let udp = UDPInterface(name: "udp", listenPort: 4244)
        udp.discoverable = true
        XCTAssertNil(try announcer().announceData(for: udp))
    }

    // MARK: - Payload contents

    /// RNS 1.5.0 added `TRANSPORT_IMPL` and `TRANSPORT_VERS` so a discovering node can tell
    /// which implementation is behind an endpoint (`Discovery.py:143-144`).
    ///
    /// This port names
    /// itself, rather than claiming to be the Python one.
    func testTheAnnounceNamesTheImplementationAndItsVersion() throws {
        let data = try XCTUnwrap(try announcer().announceData(for: discoverableServer()))
        let f = try fields(data)

        XCTAssertEqual(f[0xFD], .string(InterfaceDiscoveryHelpers.implementationName))
        XCTAssertEqual(f[0xFC], .string(InterfaceDiscoveryHelpers.implementationVersion))
        XCTAssertEqual(f[0xFE], .bytes(try XCTUnwrap(transport.transportIdentity).hash),
                       "TRANSPORT_ID is the transport identity's hash")
        XCTAssertEqual(f[0x01], .bool(Reticulum.transportEnabled()), "TRANSPORT")
        XCTAssertEqual(f[0x00], .string("TCPServerInterface"), "INTERFACE_TYPE")
        XCTAssertEqual(f[0xFF], .string("Example hub"), "NAME")
    }

    /// `OP_ADDR` carries the operator's LXMF address and is present only when one is
    /// configured (`Discovery.py:147`)—an absent key, not a nil value, so the payload of an
    /// operator who hasn't published an address is byte-identical to the pre-1.5.0 shape.
    func testTheOperatorAddressAppearsOnlyWhenConfigured() throws {
        let plain = try XCTUnwrap(try announcer().announceData(for: discoverableServer()))
        XCTAssertNil(try fields(plain)[0xF0])

        let server = discoverableServer()
        server.discoveryLxmfAddress = Data(repeating: 0x5A, count: 16)
        let withAddress = try XCTUnwrap(try announcer().announceData(for: server))
        XCTAssertEqual(try fields(withAddress)[0xF0],
                       .bytes(Data(repeating: 0x5A, count: 16)))
    }

    /// A listener is only reachable at an address its peers can dial, so an unset
    /// `reachable_on` aborts the announce rather than publishing an endpoint nobody can use
    /// (`Discovery.py:151-152`).
    func testAListenerWithNoReachableAddressDoesNotAnnounce() throws {
        XCTAssertNil(try announcer().announceData(for: discoverableServer(reachableOn: nil)))
    }

    /// The same guard rejects a value that's neither an IP address nor a hostname
    /// (`Discovery.py:177-180`).
    func testAMalformedReachableAddressDoesNotAnnounce() throws {
        XCTAssertNil(try announcer().announceData(
            for: discoverableServer(reachableOn: "not a hostname!")))
    }

    func testAListenerPublishesItsAddressAndPort() throws {
        let data = try XCTUnwrap(try announcer().announceData(for: discoverableServer()))
        let f = try fields(data)
        XCTAssertEqual(f[0x02], .string("hub.example.net"), "REACHABLE_ON")
        XCTAssertEqual(f[0x06], .uint(4965), "PORT")
    }

    /// Whitespace and newlines are stripped from every published string, so a stray newline in
    /// a config value can't split a rendered config entry on the receiving node
    /// (`Discovery.py:99-104`).
    func testPublishedStringsAreSanitized() throws {
        let server = discoverableServer(reachableOn: "  hub.example.net\n")
        server.discoveryName = "Example hub\r\n"
        let f = try fields(try XCTUnwrap(try announcer().announceData(for: server)))
        XCTAssertEqual(f[0x02], .string("hub.example.net"))
        XCTAssertEqual(f[0xFF], .string("Example hub"))
    }

    func testAnRNodePublishesItsRadioParameters() throws {
        let rnode = RNodeInterface(name: "lora", transport: MockRNodeTransport())
        rnode.discoverable = true
        rnode.frequency = 867_200_000
        rnode.bandwidth = 125_000
        rnode.sf = 8
        rnode.cr = 5

        let f = try fields(try XCTUnwrap(try announcer().announceData(for: rnode)))
        XCTAssertEqual(f[0x09], .uint(867_200_000), "FREQUENCY")
        XCTAssertEqual(f[0x0A], .uint(125_000), "BANDWIDTH")
        XCTAssertEqual(f[0x0B], .uint(8), "SPREADINGFACTOR")
        XCTAssertEqual(f[0x0C], .uint(5), "CODINGRATE")
    }

    /// `publish_ifac` puts the segment's name and passphrase in the announce so a peer can
    /// generate a config entry that actually joins it (`Discovery.py:203-205`).
    ///
    /// Off by default,
    /// because the passphrase is the segment's shared secret.
    func testPublishIfacCarriesTheSegmentNameAndKey() throws {
        let server = discoverableServer()
        Reticulum.applyIfacConfiguration(to: server,
                                         from: .init(name: "hub", type: "TCPServerInterface",
                                                     enabled: true,
                                                     parameters: ["network_name": "segment",
                                                                  "passphrase": "hunter2"]))

        XCTAssertNil(try fields(try XCTUnwrap(try announcer().announceData(for: server)))[0x07],
                     "IFAC_NETNAME must stay off the wire until publish_ifac is set")

        server.discoveryPublishIfac = true
        let f = try fields(try XCTUnwrap(try announcer().announceData(for: server)))
        XCTAssertEqual(f[0x07], .string("segment"), "IFAC_NETNAME")
        XCTAssertEqual(f[0x08], .string("hunter2"), "IFAC_NETKEY")
    }

    // MARK: - Stamp

    /// The stamp is taken over the hash of the *packed* info, at this interface's configured
    /// cost, over the discovery expand rounds (`Discovery.py:207-212`).
    ///
    /// Measuring it over
    /// anything else makes every announce fail validation at the far end.
    func testTheStampCoversThePackedInfoAtTheConfiguredCost() throws {
        let server = discoverableServer()
        server.discoveryStampValue = 18

        let data = try XCTUnwrap(try announcer().announceData(for: server))
        let packed = Data(data.dropFirst().dropLast(32))

        XCTAssertEqual(generator.lastMaterial, Hashes.fullHash(packed))
        XCTAssertEqual(generator.lastTargetCost, 18)
        XCTAssertEqual(generator.lastExpandRounds, InterfaceAnnouncer.workblockExpandRounds)
        XCTAssertEqual(Data(data.suffix(32)), Data(repeating: 0xAB, count: 32))
    }

    /// An unconfigured cost falls back to `DEFAULT_STAMP_VALUE` (`Discovery.py:108`), which
    /// RNS 1.5.0 moved from 14 to 16.
    func testAnUnconfiguredCostUsesTheDefault() throws {
        _ = try announcer().announceData(for: discoverableServer())
        XCTAssertEqual(generator.lastTargetCost, InterfaceAnnouncer.defaultStampValue)
        XCTAssertEqual(InterfaceAnnouncer.defaultStampValue, 16)
    }

    /// Identical info hashes to the same material, so the second announce reuses the first
    /// stamp instead of paying for the work again (`Discovery.py:210-212`).
    func testAnUnchangedAnnounceReusesItsStamp() throws {
        let a = try announcer()
        let server = discoverableServer()
        _ = try a.announceData(for: server)
        _ = try a.announceData(for: server)
        XCTAssertEqual(generator.callCount, 1)
    }

    /// A generator that can't find a stamp aborts the announce (`Discovery.py:211`).
    func testAnUnfoundStampAbortsTheAnnounce() throws {
        generator.stamp = nil
        XCTAssertNil(try announcer().announceData(for: discoverableServer()))
    }

    // MARK: - Encryption

    /// `discovery_encrypt` seals the payload to the network identity, so only nodes holding it
    /// can read the endpoint (`Discovery.py:214-222`).
    func testEncryptionSetsTheFlagAndSealsThePayload() throws {
        let network = Identity()
        transport.setNetworkIdentity(network)

        let server = discoverableServer()
        server.discoveryEncrypt = true

        let data = try XCTUnwrap(try announcer().announceData(for: server))
        XCTAssertEqual(data[data.startIndex] & InterfaceAnnounceHandler.flagEncrypted,
                       InterfaceAnnounceHandler.flagEncrypted)

        let decrypted = try network.decrypt(Data(data.dropFirst()))
        let packed = Data(decrypted.dropLast(32))
        guard case .map = try MsgPack.decode(packed) else {
            return XCTFail("the sealed payload must be the packed info plus the stamp")
        }
    }

    /// Encryption without a network identity aborts rather than falling back to plaintext,
    /// which would publish an endpoint the operator asked to keep inside the segment
    /// (`Discovery.py:218-220`).
    func testEncryptionWithoutANetworkIdentityAbortsTheAnnounce() throws {
        let server = discoverableServer()
        server.discoveryEncrypt = true
        XCTAssertNil(try announcer().announceData(for: server))
    }

    // MARK: - The job

    /// The job takes the single most-overdue interface per pass and stamps it, so a node with
    /// several discoverable interfaces spreads their announces out (`Discovery.py:82-90`).
    func testTheJobAnnouncesTheMostOverdueInterface() throws {
        let now = Date().timeIntervalSince1970

        let recent = discoverableServer(name: "recent")
        recent.lastDiscoveryAnnounce = now - 21_601

        let overdue = discoverableServer(name: "overdue")
        overdue.lastDiscoveryAnnounce = now - 90_000

        transport.register(interface: recent)
        transport.register(interface: overdue)

        try announcer().tick()

        XCTAssertGreaterThan(overdue.lastDiscoveryAnnounce, now,
                             "the most overdue interface announces")
        XCTAssertLessThan(recent.lastDiscoveryAnnounce, now,
                          "and the others wait for a later pass")
    }

    /// Three independent gates, each of which alone keeps an interface quiet: the type
    /// capability, the operator's choice, and the interval (`Discovery.py:82`).
    func testTheJobSkipsInterfacesThatAreNotDue() throws {
        let now = Date().timeIntervalSince1970

        let notDiscoverable = discoverableServer()
        notDiscoverable.discoverable = false
        notDiscoverable.lastDiscoveryAnnounce = now - 90_000

        let unsupported = UDPInterface(name: "udp", listenPort: 4246)
        unsupported.discoverable = true
        unsupported.discoveryAnnounceInterval = 21_600
        unsupported.lastDiscoveryAnnounce = now - 90_000

        let notYetDue = discoverableServer()
        notYetDue.lastDiscoveryAnnounce = now - 60

        for iface in [notDiscoverable, unsupported, notYetDue] as [any Interface] {
            transport.register(interface: iface)
        }

        try announcer().tick()

        for iface in [notDiscoverable, unsupported, notYetDue] as [any Interface] {
            XCTAssertLessThan(iface.lastDiscoveryAnnounce, now, iface.name)
        }
    }

    /// An interface that has never announced has `last_discovery_announce == 0`, so it's
    /// overdue by the whole Unix epoch and goes out on the first pass.
    func testAnInterfaceThatHasNeverAnnouncedIsDueImmediately() throws {
        let server = discoverableServer()
        transport.register(interface: server)

        try announcer().tick()

        XCTAssertGreaterThan(server.lastDiscoveryAnnounce, 0)
    }

    // MARK: - Transport lifecycle

    /// Python: `Transport.enable_discovery()` (`Transport.py:574-577`)—create the announcer once
    /// and start it.
    ///
    /// The second call is a no-op, so a stack that reloads its config doesn't end
    /// up with two announcers racing over `last_discovery_announce`.
    func testEnablingDiscoveryIsIdempotent() throws {
        transport.enableDiscovery(stampGenerator: generator)
        let first = try XCTUnwrap(transport.interfaceAnnouncer)

        transport.enableDiscovery(stampGenerator: generator)
        XCTAssertTrue(transport.interfaceAnnouncer === first,
                      "a second enable must keep the running announcer")
    }

    /// A transport with no identity has nothing to announce from, so enabling discovery leaves
    /// the announcer unset rather than trapping. `Reticulum.start()` only reaches this after the
    /// transport identity is loaded, but the RPC and test paths can call it earlier.
    func testEnablingDiscoveryWithoutAnIdentityIsSafe() {
        let bare = Transport()
        bare.enableDiscovery(stampGenerator: generator)
        XCTAssertNil(bare.interfaceAnnouncer)
    }

    func testDisablingDiscoveryReleasesTheAnnouncer() {
        transport.enableDiscovery(stampGenerator: generator)
        XCTAssertNotNil(transport.interfaceAnnouncer)
        transport.disableDiscovery()
        XCTAssertNil(transport.interfaceAnnouncer)
    }

    // MARK: - Round trip

    /// The whole point of the publish side: a payload built here has to decode through the
    /// receive side, which was written against Python's announces.
    ///
    /// Anything that disagrees
    /// about key numbering, value types or the stamp's position fails here.
    func testTheEmittedPayloadDecodesThroughThisPortsReceiveSide() throws {
        let server = discoverableServer()
        server.discoveryLxmfAddress = Data(repeating: 0x5A, count: 16)
        server.discoveryLatitude = 55.6761
        server.discoveryLongitude = 12.5683
        server.discoveryHeight = 12

        let data = try XCTUnwrap(try announcer().announceData(for: server))

        var received: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 16,
                                               stampValidator: AcceptAnyStamp(),
                                               callback: { received = $0 })
        let announcing = Identity()
        handler.receivedAnnounce(destinationHash: Data(repeating: 0x01, count: 16),
                                 identity: announcing, appData: data,
                                 announcePacketHash: Data(repeating: 0x02, count: 32),
                                 isPathResponse: false)

        let info = try XCTUnwrap(received, "the receive side rejected this port's own announce")
        XCTAssertEqual(info.type, "TCPServerInterface")
        XCTAssertEqual(info.name, "Example hub")
        XCTAssertEqual(info.reachableOn, "hub.example.net")
        XCTAssertEqual(info.port, 4965)
        XCTAssertEqual(info.transportID,
                       try XCTUnwrap(transport.transportIdentity).hash.hexString)
        XCTAssertEqual(info.operatorLxmfAddress, Data(repeating: 0x5A, count: 16).hexString)
        XCTAssertEqual(try XCTUnwrap(info.latitude), 55.6761, accuracy: 1e-9)
    }
}
