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

/// The order in which the transport admits an inbound announce, and what each
/// rejection reports.
///
/// Python runs three gates in a fixed order (`Transport.py:1804-1811`): the frame-size
/// ceiling, then `validate_announce(only_validate_signature=True, signal_blackholed=True)`,
/// then `received_announce(size=)` for whatever survives. The middle gate carries the
/// ordering that matters, because upstream tests the blackhole list *inside*
/// `validate_announce`, after loading the announced public key and before checking the
/// signature (`Identity.py:551-556`).
///
/// The three outcomes differ in what an operator can observe. A blackholed identity returns
/// silently: no violation, no announce counted. An invalid signature is a counted protocol
/// violation. Only a valid, non-blackholed announce reaches `received_announce`, so
/// `rnstatus`'s announce columns describe traffic this node accepted rather than traffic
/// that merely arrived.
final class AnnounceAdmissionOrderTests: XCTestCase {

    private func statsForFirstInterface(_ t: Transport) throws -> [String: MsgPack.Value] {
        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        return try XCTUnwrap(interfaces.first?.asDictionary)
    }

    /// A real signed announce for a fresh identity, plus that identity's hash.
    private func announce(appName: String) throws -> (packet: Packet, identityHash: Data) {
        let id = Identity()
        let destination = try Destination(identity: id, direction: .in, kind: .single,
                                          appName: appName, aspects: ["admission"])
        return (try Announce.make(for: destination), id.hash)
    }

    /// The same announce with one signature byte flipped, so the frame stays structurally
    /// valid and only the signature fails.
    private func withBrokenSignature(_ packet: Packet) -> Packet {
        var data = packet.data
        let last = data.count - 1
        data[last] = data[last] ^ 0xFF
        return Packet(headerType: packet.headerType,
                      contextFlag: packet.contextFlag,
                      transportType: packet.transportType,
                      destinationType: packet.destinationType,
                      packetType: packet.packetType,
                      hops: packet.hops,
                      transportID: packet.transportID,
                      destinationHash: packet.destinationHash,
                      context: packet.context,
                      data: data)
    }

    private func transportWithInterface(port: UInt16) -> (Transport, UDPInterface) {
        let t = Transport()
        let iface = UDPInterface(name: "in", listenPort: port, forwardPort: port + 1)
        t.register(interface: iface)
        return (t, iface)
    }

    // MARK: - The accepted case

    func testAValidAnnounceCountsAsReceived() throws {
        let (t, iface) = transportWithInterface(port: 4362)
        defer { t.deregister(interface: iface) }
        let (packet, _) = try announce(appName: "valid")

        t.handleIncoming(packet: packet, from: iface)

        let stats = try statsForFirstInterface(t)
        XCTAssertEqual(stats["arxc"]?.asInt, 1, "a valid announce is a received announce")
        XCTAssertEqual(stats["protocol_violations"]?.asInt, 0)
    }

    /// `handleAnnounce` passes `Announce.validate` an already-verified mark, because
    /// its admission gate verified the signature.
    ///
    /// That short-circuit has to cover the
    /// signature and nothing else. Upstream still requires
    /// `destination_hash == truncated_hash(name_hash || identity_hash)`
    /// (`Identity.py:565-567`), and a signature proves nothing about that: it covers
    /// whatever destination hash the signer chose to sign over.
    func testAVerifiedSignatureDoesNotSkipTheDestinationHashCheck() throws {
        let (t, iface) = transportWithInterface(port: 4372)
        defer { t.deregister(interface: iface) }

        let id = Identity()
        let destination = try Destination(identity: id, direction: .in, kind: .single,
                                          appName: "mismatch", aspects: ["admission"])
        let parsed = try Announce.parse(try Announce.make(for: destination))

        // Sign a destination hash that isn't the one this identity's name hash implies.
        let claimedHash = Data(repeating: 0x11, count: 16)
        var signedData = Data()
        signedData.append(claimedHash)
        signedData.append(parsed.publicKey)
        signedData.append(parsed.nameHash)
        signedData.append(parsed.randomHash)

        var body = Data()
        body.append(parsed.publicKey)
        body.append(parsed.nameHash)
        body.append(parsed.randomHash)
        body.append(try id.sign(signedData))

        let forged = Packet(headerType: .type1, contextFlag: .unset, transportType: .broadcast,
                            destinationType: .single, packetType: .announce, hops: 0,
                            destinationHash: claimedHash, context: .none, data: body)

        // The signature really is good, so the admission gate lets it through.
        XCTAssertTrue(Identity.validateAnnounce(forged, onlyValidateSignature: true),
                      "fixture must carry a genuinely valid signature")

        t.handleIncoming(packet: forged, from: iface)

        XCTAssertFalse(t.hasPath(to: claimedHash),
                       "a destination hash the name hash doesn't imply must not learn a path")
    }

    // MARK: - Invalid signature

    func testAnAnnounceWithABrokenSignatureCountsAProtocolViolation() throws {
        let (t, iface) = transportWithInterface(port: 4364)
        defer { t.deregister(interface: iface) }
        let (packet, _) = try announce(appName: "badsig")

        t.handleIncoming(packet: withBrokenSignature(packet), from: iface)

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 1,
                       """
                       Python answers an unverifiable announce with \
                       `protocol_violation("Invalid announce signature for …")` \
                       (`Transport.py:1809`). Dropping it silently leaves the operator with \
                       no signal that a peer is sending forgeries.
                       """)
    }

    func testAnAnnounceWithABrokenSignatureIsNotCountedAsReceived() throws {
        let (t, iface) = transportWithInterface(port: 4366)
        defer { t.deregister(interface: iface) }
        let (packet, _) = try announce(appName: "badsig2")

        t.handleIncoming(packet: withBrokenSignature(packet), from: iface)

        XCTAssertEqual(try statsForFirstInterface(t)["arxc"]?.asInt, 0,
                       """
                       `received_announce` sits below the signature gate (`Transport.py:1811`), \
                       so an announce that fails it never reaches the counter. Counting first \
                       makes the announce columns describe arrivals rather than acceptances.
                       """)
    }

    // MARK: - Blackholed identities

    func testABlackholedIdentityAnnounceIsDroppedSilently() throws {
        let (t, iface) = transportWithInterface(port: 4368)
        defer { t.deregister(interface: iface) }
        let (packet, identityHash) = try announce(appName: "blackholed")
        _ = t.blackholeIdentity(identityHash)

        t.handleIncoming(packet: packet, from: iface)

        let stats = try statsForFirstInterface(t)
        XCTAssertEqual(stats["protocol_violations"]?.asInt, 0,
                       """
                       `"blackholed"` returns `None` without touching a counter \
                       (`Transport.py:1808`). A blackholed peer isn't misbehaving on the wire, \
                       so charging it a protocol violation would misreport the link.
                       """)
        XCTAssertEqual(stats["arxc"]?.asInt, 0,
                       "and it is not an accepted announce either")
    }

    func testABlackholedIdentityIsTestedBeforeTheSignature() throws {
        // The ordering test. Upstream tests the blackhole list inside `validate_announce`,
        // after loading the public key and before verifying the signature
        // (`Identity.py:551-556`), so a blackholed identity drops silently even when its
        // announce would also have failed the signature check. Checking the signature
        // first turns this into a counted violation.
        let (t, iface) = transportWithInterface(port: 4370)
        defer { t.deregister(interface: iface) }
        let (packet, identityHash) = try announce(appName: "both")
        _ = t.blackholeIdentity(identityHash)

        t.handleIncoming(packet: withBrokenSignature(packet), from: iface)

        XCTAssertEqual(try statsForFirstInterface(t)["protocol_violations"]?.asInt, 0,
                       "blackholed wins over an invalid signature, because upstream tests "
                       + "it first")
    }

    func testABlackholedIdentityLearnsNoPath() throws {
        let (t, iface) = transportWithInterface(port: 4372)
        defer { t.deregister(interface: iface) }
        let (packet, identityHash) = try announce(appName: "nopath")
        _ = t.blackholeIdentity(identityHash)

        t.handleIncoming(packet: packet, from: iface)

        XCTAssertFalse(t.hasPath(to: packet.destinationHash),
                       "a blackholed announce must not reach the path table")
    }
}
