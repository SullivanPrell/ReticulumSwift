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

/// RNS 1.5.0 added three fields to the interface-discovery announce: an implementation
/// identifier (`TRANSPORT_IMPL 0xFD`), its version (`TRANSPORT_VERS 0xFC`), and the operator's
/// LXMF address (`OP_ADDR 0xF0`)—`Discovery.py:21,22,38`.
///
/// This port implements the discovery *receive* side only; the publish side is a documented gap
/// (`Reticulum.publishesInterfaceDiscovery == false`, `fix-013 §7.8`). So what's testable—and
/// what matters for interop today—is that a Swift node parses an announce from a Python
/// 1.5.x node correctly: it must surface the operator address and must not trip over the
/// two fields 1.5.2 writes but doesn't itself read back.
final class DiscoveryOperatorAddressTests: XCTestCase {

    /// These tests are about payload decoding, so the proof-of-work gate is stubbed out—a
    /// real stamp would make every fixture below depend on a mining run.
    ///
    /// Named locally rather
    /// than shared, matching the file-private doubles in the other discovery suites.
    private final class AcceptAnyStamp: DiscoveryStampValidator {
        let stampSize: Int = 32
        func stampWorkblock(material: Data, expandRounds: Int) -> Data {
            Data(repeating: 0, count: max(1, expandRounds) * 256)
        }
        func stampValue(workblock: Data, stamp: Data) -> Int { 99 }
        func stampValid(stamp: Data, targetCost: Int, workblock: Data) -> Bool { true }
    }

    private static let stamp = Data(repeating: 0xAB, count: 32)
    private static let transportID = Data(repeating: 0x11, count: 16)

    /// A 16-byte LXMF destination hash—`RNS.Identity.TRUNCATED_HASHLENGTH//8`, the only
    /// length `Discovery.py:429` accepts.
    private static let operatorAddress = Data((0..<16).map { UInt8(0xA0 + $0) })

    private func payload(_ fields: [(MsgPack.Value, MsgPack.Value)]) -> Data {
        Data([0x00]) + MsgPack.encode(.map(fields)) + Self.stamp
    }

    /// The shape a Python 1.5.x `BackboneInterface` announces, minus whichever field a given
    /// test is exercising.
    private func backbone(extra: [(MsgPack.Value, MsgPack.Value)] = []) -> [(MsgPack.Value, MsgPack.Value)] {
        [
            (.uint(0x00), .string("BackboneInterface")),
            (.uint(0x01), .bool(true)),
            (.uint(0xFE), .bytes(Self.transportID)),
            (.uint(0xFF), .string("PY 1.5.2 NODE")),
            (.uint(0x02), .string("192.168.1.100")),
            (.uint(0x06), .int(4965)),
            (.uint(0x03), .nil),
            (.uint(0x04), .nil),
            (.uint(0x05), .nil),
        ] + extra
    }

    private func decode(_ fields: [(MsgPack.Value, MsgPack.Value)]) -> DiscoveredInterfaceInfo? {
        var result: DiscoveredInterfaceInfo?
        let handler = InterfaceAnnounceHandler(requiredValue: 14,
                                               stampValidator: AcceptAnyStamp()) { result = $0 }
        handler.receivedAnnounce(destinationHash: Data(repeating: 0, count: 16),
                                 identity: Identity(),
                                 appData: payload(fields),
                                 announcePacketHash: Data(repeating: 0, count: 4),
                                 isPathResponse: false)
        return result
    }

    // MARK: - Field-key constants

    func testTheThreeNewFieldKeysMatchPython() {
        XCTAssertEqual(DiscoveryFieldKey.transportImpl.rawValue, 0xFD,
                       "TRANSPORT_IMPL = 0xFD (Discovery.py:21)")
        XCTAssertEqual(DiscoveryFieldKey.transportVers.rawValue, 0xFC,
                       "TRANSPORT_VERS = 0xFC (Discovery.py:22)")
        XCTAssertEqual(DiscoveryFieldKey.operatorAddress.rawValue, 0xF0,
                       "OP_ADDR = 0xF0 (Discovery.py:38)")
    }

    /// Python hardcodes `IMPLEMENTATION_NAME = "RNS"` and its own `__version__`.
    ///
    /// The field is
    /// documented as "a short, unique implementation-specific identifier and version tag", so
    /// this port announces its own rather than impersonating the reference—a discovery
    /// consumer must be able to tell a Swift node from a Python one.
    func testThisPortHasItsOwnImplementationIdentity() {
        XCTAssertEqual(InterfaceDiscoveryHelpers.implementationName, "RNSwift",
                       "the identifier is this port's own, not Python's \"RNS\"")
        XCTAssertEqual(InterfaceDiscoveryHelpers.implementationVersion, Reticulum.version,
                       """
                       the version tag tracks this port's own release line \
                       (Reticulum.version), not the RNS release it matches \
                       (rnsProtocolVersion) — the field identifies a build, not a protocol level
                       """)
        XCTAssertNotEqual(InterfaceDiscoveryHelpers.implementationName, "RNS",
                          "announcing \"RNS\" would make a Swift node indistinguishable from "
                          + "the reference implementation, defeating the field's purpose")
    }

    // MARK: - Operator LXMF address (`Discovery.py:427-430`)

    func testAnOperatorAddressIsSurfaced() throws {
        let info = try XCTUnwrap(decode(backbone(extra: [
            (.uint(0xF0), .bytes(Self.operatorAddress)),
        ])), "a well-formed announce carrying OP_ADDR must still decode")

        XCTAssertEqual(info.operatorLxmfAddress,
                       RNSUtilities.hexrep(Self.operatorAddress, delimit: false),
                       """
                       `info["operator_lxmf_address"] = RNS.hexrep(unpacked[OP_ADDR], \
                       delimit=False)` (Discovery.py:430) — undelimited hex, matching the \
                       transport_id representation beside it
                       """)
    }

    func testAnAnnounceWithoutAnOperatorAddressLeavesItUnset() throws {
        let info = try XCTUnwrap(decode(backbone()))
        XCTAssertNil(info.operatorLxmfAddress,
                     "the field is optional — every pre-1.5.0 announce omits it entirely "
                     + "(`if info and OP_ADDR in unpacked`, Discovery.py:427)")
    }

    func testAnExplicitlyNilOperatorAddressIsAccepted() throws {
        // `type(unpacked[OP_ADDR]) not in [type(None), bytes]` (Discovery.py:428)—None is
        // explicitly permitted, so a nil here must not reject the whole announce.
        let info = try XCTUnwrap(decode(backbone(extra: [(.uint(0xF0), .nil)])),
                                 "an explicit nil OP_ADDR is legal and must not drop the announce")
        XCTAssertNil(info.operatorLxmfAddress)
    }

    func testAWrongLengthOperatorAddressIsIgnoredButTheAnnounceSurvives() throws {
        // `if unpacked[OP_ADDR] and len(unpacked[OP_ADDR]) == TRUNCATED_HASHLENGTH//8`
        // (Discovery.py:429): a short or long value simply fails the length test. The
        // surrounding announce is still valid and must still be discovered—dropping it would
        // let one malformed optional field blackhole an otherwise reachable node.
        for wrong in [Data(repeating: 0x0F, count: 15), Data(repeating: 0x0F, count: 17), Data()] {
            let info = try XCTUnwrap(decode(backbone(extra: [(.uint(0xF0), .bytes(wrong))])),
                                     "a \(wrong.count)-byte OP_ADDR must not drop the announce")
            XCTAssertNil(info.operatorLxmfAddress,
                         "only a \(Constants.truncatedHashLength)-byte value is an address; "
                         + "\(wrong.count) bytes must be ignored")
        }
    }

    func testANonBytesOperatorAddressRejectsTheAnnounce() {
        // `raise ValueError("Invalid data in operator LXMF address field of announce")`
        // (Discovery.py:428). Python raises *inside* the handler's try, so the announce is
        // abandoned—a type violation is treated as a malformed announce, unlike a merely
        // wrong-length one.
        XCTAssertNil(decode(backbone(extra: [(.uint(0xF0), .string("deadbeef"))])),
                     "a non-bytes OP_ADDR is a type violation and abandons the announce "
                     + "(Discovery.py:428), which is stricter than the length check above")
    }

    // MARK: - Forward compatibility with the two write-only fields

    func testTheImplementationFieldsDoNotDisturbDecoding() throws {
        // 1.5.2 writes TRANSPORT_IMPL and TRANSPORT_VERS but doesn't read them back—they're
        // staged for a future consumer. Every real 1.5.x announce carries them, so decoding must
        // be unaffected by their presence whether or not this port ever surfaces them.
        let info = try XCTUnwrap(decode(backbone(extra: [
            (.uint(0xFD), .string("RNS")),
            (.uint(0xFC), .string("1.5.2")),
            (.uint(0xF0), .bytes(Self.operatorAddress)),
        ])), "an announce from a real Python 1.5.2 node must decode unchanged")

        XCTAssertEqual(info.name, "PY 1.5.2 NODE")
        XCTAssertEqual(info.reachableOn, "192.168.1.100")
        XCTAssertEqual(info.port, 4965)
        XCTAssertEqual(info.operatorLxmfAddress,
                       RNSUtilities.hexrep(Self.operatorAddress, delimit: false))
    }
}
