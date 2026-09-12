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

/// RNS 1.5.0's "early protocol violation checks for invalid frames" (`Packet.py:266-274`)
/// and the outbound hop gate it added to `Packet.send()` (`Packet.py:292`).
///
/// Both are wire-visible: a 1.5.x peer now *drops* frames this port previously accepted and
/// forwarded, and refuses to originate a packet whose hop count already sits at the pathfinder
/// limit. Without them the port keeps admitting frames the rest of the network has agreed are
/// malformed, and keeps emitting packets every 1.5.x peer discards on receipt.
final class PacketProtocolViolationTests: XCTestCase {

    // MARK: - Frame construction
    //
    // Built byte-by-byte rather than through `pack()`, because `pack()` can't produce these
    // frames—that's the point. A HEADER_1 frame is
    //   [0] flags, [1] hops, [2..17] destination hash, [18] context, [19...] data
    // so a 19-byte frame is structurally complete with a zero-length data field.

    private static let dstLen = Constants.truncatedHashLength

    /// Flags byte for a plain HEADER_1 / BROADCAST / SINGLE / DATA packet—the shape that
    /// carries application payloads, so the shape an attacker would truncate.
    private static let header1DataFlags: UInt8 = 0x00

    private func frame(flags: UInt8 = header1DataFlags,
                       hops: UInt8 = 0,
                       transportID: Data? = nil,
                       destinationHash: Data? = nil,
                       context: UInt8 = 0x00,
                       data: Data) -> Data {
        var raw = Data([flags, hops])
        if let transportID { raw.append(transportID) }
        raw.append(destinationHash ?? Data(repeating: 0xAB, count: Self.dstLen))
        raw.append(context)
        raw.append(data)
        return raw
    }

    // MARK: - Zero-length data field (`Packet.py:274`)

    func testAFrameWithAZeroLengthDataFieldIsRejected() {
        let raw = frame(data: Data())
        XCTAssertEqual(raw.count, 2 + Self.dstLen + 1,
                       "the frame must be structurally complete — this test is about an empty "
                       + "data field, not a truncated header")
        XCTAssertThrowsError(try Packet.unpack(raw),
                             """
                             `if len(self.data) == 0: raise ValueError("Zero-length data field")` \
                             (Packet.py:274). Every 1.5.x peer drops this frame; accepting it \
                             admits a packet the rest of the network has already discarded, and \
                             a transport-mode node would forward it onward.
                             """)
    }

    func testAHeader2FrameWithAZeroLengthDataFieldIsRejected() {
        // HEADER_2 sets bit 6 of the flags byte and carries a transport ID before the
        // destination hash—the relayed shape, which is exactly what a transport node forwards.
        let raw = frame(flags: 0x40,
                        transportID: Data(repeating: 0xCD, count: Self.dstLen),
                        data: Data())
        XCTAssertThrowsError(try Packet.unpack(raw),
                             "the zero-length check is on the data field, so it must fire "
                             + "identically for a HEADER_2 frame (Packet.py:274)")
    }

    func testAFrameWithASingleDataByteIsStillAccepted() throws {
        // The boundary on the other side: one byte of payload is legal, and RESOURCE_ICL /
        // RESOURCE_RCL and the keepalive contexts do send very short payloads. A check written
        // as `<= 0` rather than `== 0` would be indistinguishable here, which is why the case
        // is pinned rather than assumed.
        let packet = try Packet.unpack(frame(data: Data([0x7F])))
        XCTAssertEqual(packet.data, Data([0x7F]),
                       "a one-byte data field is a valid frame and must survive the new check")
    }

    // MARK: - Field-length validation (`Packet.py:266-272`)

    func testAHeader2FrameTruncatedInsideItsTransportIDIsRejected() {
        // Flags claim HEADER_2, so the parser expects transport ID + destination hash + context
        // + data. Supply one byte less than two full hashes and the transport ID or destination
        // hash can't both be whole.
        var raw = Data([0x40, 0x00])
        raw.append(Data(repeating: 0xCD, count: Self.dstLen))
        raw.append(Data(repeating: 0xAB, count: Self.dstLen - 1))
        raw.append(Data([0x00, 0x01]))
        XCTAssertThrowsError(try Packet.unpack(raw),
                             "`if len(self.transport_id) != DST_LEN` / `if "
                             + "len(self.destination_hash) != DST_LEN` (Packet.py:266-272)")
    }

    // MARK: - The outbound hop gate (`Packet.py:292`)

    func testTheHopCeilingIsThePathfinderLimit() {
        XCTAssertEqual(Transport.pathfinderM, 128,
                       "PATHFINDER_M is the ceiling both the send gate and unpack compare "
                       + "against; the gate is meaningless if this drifts")
    }

    private func outboundPacket(hops: UInt8) -> Packet {
        Packet(destinationType: .single,
               packetType: .data,
               hops: hops,
               destinationHash: Data(repeating: 0x11, count: Self.dstLen),
               data: Data([0x01, 0x02, 0x03]))
    }

    func testAPacketAtThePathfinderLimitIsNotTransmitted() throws {
        let t = Transport()
        let iface = RecordingInterface(name: "out")
        t.register(interface: iface)

        let receipt = try t.send(outboundPacket(hops: UInt8(Transport.pathfinderM)))

        XCTAssertNil(receipt,
                     "`if self.hops >= RNS.Transport.PATHFINDER_M: return False` "
                     + "(Packet.py:292) — the send is refused outright, so there is no receipt")
        XCTAssertEqual(iface.sent.count, 0,
                       """
                       nothing may reach the wire: every 1.5.x peer discards a packet at or past \
                       the pathfinder limit on unpack, so transmitting it is pure waste and, on \
                       a transport node, an amplification path.
                       """)
    }

    func testAPacketOneHopBelowTheLimitIsStillTransmitted() throws {
        let t = Transport()
        let iface = RecordingInterface(name: "out")
        t.register(interface: iface)

        _ = try t.send(outboundPacket(hops: UInt8(Transport.pathfinderM - 1)))

        XCTAssertEqual(iface.sent.count, 1,
                       """
                       the gate is `>=`, not `>`: one hop below the limit is still deliverable \
                       and must go out. A gate written `>` would pass the test above and \
                       silently drop nothing — this is the case that tells the two apart.
                       """)
    }

    /// Records what reached the wire, so the preceding assertions are about transmission rather
    /// than about an internal flag. Same shape as the doubles in the announce-forwarding tests.
    private final class RecordingInterface: Interface {
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
}
