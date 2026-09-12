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

/// The protocol-violation counters Python raises outside `packet_filter`, and the one
/// behavioural gate that sits with them.
///
/// `protocol_violation` is an interface's one signal to the operator that a peer is putting
/// frames on the wire that the protocol doesn't allow. A guard precedes every call:
/// `if packet.receiving_interface`, and the five calls inside `packet_filter` can never
/// satisfy that guard, because the caller assigns `receiving_interface` only after the filter
/// returns (`Transport.py:1795-1799`). The sites covered here all sit below that assignment,
/// so they're the reachable ones.
final class ProtocolViolationSiteTests: XCTestCase {

    // MARK: - Harness

    /// Records what the node put on the wire, so relay assertions are about transmission
    /// rather than about an internal flag.
    private final class RecordingHop: Interface {
        var name: String
        var bitrate: Int = 0
        var isOnline: Bool = true
        var inboundHandler: ((Packet, any Interface) -> Void)?
        private(set) var sent: [Packet] = []
        init(name: String) { self.name = name }
        func start() throws {}
        func stop() {}
        func send(_ packet: Packet) throws { sent.append(packet) }
    }

    private func violations(_ t: Transport, on interface: any Interface) throws -> Int {
        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        for entry in interfaces {
            guard let dict = entry.asDictionary else { continue }
            // The payload keys rows by `displayName`, which is what `rnstatus` shows and
            // isn't always the raw name.
            if dict["name"]?.asString == interface.displayName {
                return dict["protocol_violations"]?.asInt ?? 0
            }
        }
        XCTFail("no stats row for \(interface.name)")
        return -1
    }

    private func stat(_ t: Transport, on interface: any Interface, key: String) throws -> Int {
        let payload = InterfaceStatsPayload.build(t)
        let interfaces = try XCTUnwrap(payload.asDictionary?["interfaces"]?.asArray)
        for entry in interfaces {
            guard let dict = entry.asDictionary else { continue }
            if dict["name"]?.asString == interface.displayName { return dict[key]?.asInt ?? 0 }
        }
        XCTFail("no stats row for \(interface.displayName)")
        return -1
    }

    private func pathRequest(body: Data) -> Packet {
        Packet(headerType: .type1,
               contextFlag: .unset,
               transportType: .broadcast,
               destinationType: .plain,
               packetType: .data,
               hops: 0,
               destinationHash: Transport.pathRequestDestinationHash,
               context: .none,
               data: body)
    }

    // MARK: - Path requests

    /// `Transport.py:1838-1840`. Nothing can deduplicate a path request with no tag at all, so
    /// upstream refuses to act on it and charges the sender a violation. The tag is what makes
    /// one request distinguishable from a replay of itself.
    func testATaglessPathRequestCountsAProtocolViolation() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-tagless")
        t.register(interface: hop)

        // Exactly a destination hash and nothing else: `tag_bytes` stays None.
        t.handleIncoming(packet: pathRequest(body: Data(repeating: 0xA1, count: 16)), from: hop)

        XCTAssertEqual(try violations(t, on: hop), 1)
    }

    /// `Transport.py:1830`. A body too short to even hold a destination hash returns before the
    /// tag logic, with no violation. The two lengths are one byte apart and upstream treats them
    /// differently, so the boundary is worth pinning.
    func testAPathRequestTooShortForADestinationHashIsSilent() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-short")
        t.register(interface: hop)

        t.handleIncoming(packet: pathRequest(body: Data(repeating: 0xA1, count: 15)), from: hop)

        XCTAssertEqual(try violations(t, on: hop), 0)
    }

    /// `Transport.py:1843-1845`. Upstream truncates an oversized tag to the hash length and
    /// counts a violation, then carries on with the request. The truncation matters on its own
    /// (an untruncated tag in the dedup key lets a sender defeat deduplication by varying a
    /// tail nothing reads), and the counter is the only trace it leaves for the operator.
    func testAnExcessivePathRequestTagCountsAProtocolViolation() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-fat-tag")
        t.register(interface: hop)

        // Upstream reads a body past 32 bytes as [target || requesting transport ID || tag], so the
        // tag only starts at 32. 16 + 16 + 17 puts it one byte past the ceiling; a 33-byte
        // body would take the same branch and yield a one-byte tag, testing nothing.
        let body = Data(repeating: 0xA1, count: 16)
            + Data(repeating: 0xC3, count: 16)
            + Data(repeating: 0xB2, count: 17)
        t.handleIncoming(packet: pathRequest(body: body), from: hop)

        XCTAssertEqual(try violations(t, on: hop), 1)
    }

    /// A tag at exactly the hash length is ordinary traffic.
    func testAPathRequestWithATagAtTheCeilingIsSilent() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-exact-tag")
        t.register(interface: hop)

        let body = Data(repeating: 0xA1, count: 16) + Data(repeating: 0xB2, count: 16)
        t.handleIncoming(packet: pathRequest(body: body), from: hop)

        XCTAssertEqual(try violations(t, on: hop), 0)
    }

    /// `received_path_request` sits below the tag checks and the duplicate check
    /// (`Transport.py:1857`), so a request upstream refuses to act on never reaches the
    /// counter. Counting at the top instead makes the path-request column describe arrivals
    /// rather than requests this node served, the same shape as the announce counter.
    func testATaglessPathRequestIsNotCountedAsReceived() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-tagless-count")
        t.register(interface: hop)

        t.handleIncoming(packet: pathRequest(body: Data(repeating: 0xA1, count: 16)), from: hop)

        XCTAssertEqual(try stat(t, on: hop, key: "prxc"), 0)
    }

    /// A duplicate tag returns at `Transport.py:1855`, also ahead of the counter.
    func testADuplicatePathRequestIsCountedOnce() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-dup-count")
        t.register(interface: hop)

        let body = Data(repeating: 0xA1, count: 16) + Data(repeating: 0xB2, count: 16)
        t.handleIncoming(packet: pathRequest(body: body), from: hop)
        t.handleIncoming(packet: pathRequest(body: body), from: hop)

        XCTAssertEqual(try stat(t, on: hop, key: "prxc"), 1,
                       "the second copy is a duplicate upstream drops before counting")
    }

    /// The control: the counter still moves for a request this node serves.
    func testAServedPathRequestIsCountedAsReceived() throws {
        let t = Transport()
        let hop = RecordingHop(name: "pr-served-count")
        t.register(interface: hop)

        let body = Data(repeating: 0xA1, count: 16) + Data(repeating: 0xB2, count: 16)
        t.handleIncoming(packet: pathRequest(body: body), from: hop)

        XCTAssertEqual(try stat(t, on: hop, key: "prxc"), 1)
    }

    // MARK: - Link traffic ahead of route validation

    private struct Relay {
        let transport: Transport
        let towardInitiator: RecordingHop
        let towardResponder: RecordingHop
        let linkID: Data
    }

    private func makeRelay(validated: Bool) -> Relay {
        let t = Transport()
        let towardInitiator = RecordingHop(name: "R<-A")
        let towardResponder = RecordingHop(name: "R->B")
        t.register(interface: towardInitiator)
        t.register(interface: towardResponder)

        let linkID = Data(repeating: 0x71, count: Constants.truncatedHashLength)
        var route = Transport.LinkRoute(
            linkID: linkID,
            initiatorSideInterface: towardInitiator,
            responderSideInterface: towardResponder,
            initiatorSideInterfaceName: towardInitiator.name,
            responderSideInterfaceName: towardResponder.name,
            destinationHash: Data(repeating: 0x4D, count: Constants.truncatedHashLength),
            lastHeard: Date())
        route.validated = validated
        t.restore(linkRoute: route)

        return Relay(transport: t, towardInitiator: towardInitiator,
                     towardResponder: towardResponder, linkID: linkID)
    }

    private func linkData(_ linkID: Data) -> Packet {
        Packet(headerType: .type1,
               contextFlag: .unset,
               transportType: .broadcast,
               destinationType: .link,
               packetType: .data,
               hops: 0,
               destinationHash: linkID,
               context: .none,
               data: Data(repeating: 0xC3, count: 32))
    }

    /// `Transport.py:2124-2128`. A link-table entry starts unvalidated and becomes validated
    /// only when the relay verifies the responder's link-request proof. Until then, upstream
    /// refuses to carry traffic on that route and counts a violation.
    ///
    /// Relaying early is worth something to an attacker: anyone can push a link request through
    /// a transport node, and a node that carries traffic on the resulting half-open route
    /// forwards packets for a link that never completes.
    func testALinkPacketBeforeValidationIsNotRelayed() throws {
        let relay = makeRelay(validated: false)

        relay.transport.handleIncoming(packet: linkData(relay.linkID), from: relay.towardInitiator)

        XCTAssertEqual(relay.towardResponder.sent.count, 0,
                       "an unvalidated route must not carry link traffic")
        XCTAssertEqual(try violations(relay.transport, on: relay.towardInitiator), 1)
    }

    /// The control: once the proof has validated the route, the same packet relays.
    func testALinkPacketOnAValidatedRouteIsRelayed() throws {
        let relay = makeRelay(validated: true)

        relay.transport.handleIncoming(packet: linkData(relay.linkID), from: relay.towardInitiator)

        XCTAssertEqual(relay.towardResponder.sent.count, 1)
        XCTAssertEqual(try violations(relay.transport, on: relay.towardInitiator), 0)
    }

    /// Upstream's condition excludes `context == LRPROOF` (`Transport.py:2122`), because a
    /// link-request proof is what sets the validated flag in the first place. Relaying a proof
    /// through `handleLinkRequestProof` raises the flag before the forward, so on that path the
    /// exemption is redundant—but a proof reaching the gate any other way, such as a duplicate
    /// or one for a link already torn down, would otherwise charge a peer for a frame upstream
    /// waves through.
    func testALinkRequestProofIsExemptFromTheValidationGate() throws {
        let relay = makeRelay(validated: false)
        var proof = linkData(relay.linkID)
        proof.context = .lrproof

        relay.transport.handleIncoming(packet: proof, from: relay.towardResponder)

        XCTAssertEqual(try violations(relay.transport, on: relay.towardResponder), 0,
                       "a proof on an unvalidated route is the normal case, not a violation")
    }

    // MARK: - Tunnel synthesis

    private func tunnelSynthesis(publicKey: Data, signature: Data) -> Packet {
        let body = publicKey
            + Data(repeating: 0x11, count: 32)   // interface hash
            + Data(repeating: 0x22, count: 16)   // random hash
            + signature
        return Packet(headerType: .type1,
                      contextFlag: .unset,
                      transportType: .broadcast,
                      destinationType: .plain,
                      packetType: .data,
                      hops: 0,
                      destinationHash: Transport.tunnelSynthesizeHash,
                      context: .none,
                      data: body)
    }

    /// Pins the decision not to port `protocol_violation("Invalid tunnel synthesis packet")`
    /// (`Transport.py:2808-2810`). It fires from the handler's `except`, and once the length
    /// matches nothing inside can raise: `load_public_key` swallows its own exception, and
    /// neither curve rejects a 32-byte value at construction: Ed25519 defers point decoding
    /// to verification. Degenerate key bytes therefore load, fail `validate`, and go
    /// unremarked. Porting the counter would charge peers for frames upstream ignores.
    func testATunnelSynthesisPacketWithDegenerateKeyBytesIsSilent() throws {
        let t = Transport()
        let hop = RecordingHop(name: "tnl-badkey")
        t.register(interface: hop)

        for keyBytes in [Data(repeating: 0x00, count: 64), Data(repeating: 0xFF, count: 64)] {
            let packet = tunnelSynthesis(publicKey: keyBytes,
                                         signature: Data(repeating: 0x33, count: 64))
            t.handleIncoming(packet: packet, from: hop)
        }

        XCTAssertEqual(try violations(t, on: hop), 0)
    }

    /// The boundary on the other side: upstream reaches `validate` without raising, the
    /// signature simply fails, and the handler falls off the end. No exception, so no
    /// violation. A failed signature is an ordinary outcome on a shared medium.
    func testATunnelSynthesisPacketWithABadSignatureIsSilent() throws {
        let t = Transport()
        let hop = RecordingHop(name: "tnl-badsig")
        t.register(interface: hop)

        let packet = tunnelSynthesis(publicKey: Identity().publicKeyBytes,
                                     signature: Data(repeating: 0x33, count: 64))
        t.handleIncoming(packet: packet, from: hop)

        XCTAssertEqual(try violations(t, on: hop), 0)
    }

    /// A wrongly sized frame never enters upstream's `if`, so it raises nothing.
    func testATunnelSynthesisPacketOfTheWrongLengthIsSilent() throws {
        let t = Transport()
        let hop = RecordingHop(name: "tnl-short")
        t.register(interface: hop)

        var packet = tunnelSynthesis(publicKey: Data(repeating: 0x00, count: 64),
                                     signature: Data(repeating: 0x33, count: 64))
        packet.data = packet.data.prefix(100)
        t.handleIncoming(packet: packet, from: hop)

        XCTAssertEqual(try violations(t, on: hop), 0)
    }
}
