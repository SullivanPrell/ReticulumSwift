import XCTest
@testable import ReticulumSwift

final class AnnounceTests: XCTestCase {

    func testIsPathResponseFalseForFreshAnnounce() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test"
        )
        let packet = try Announce.make(for: destination)
        let decoded = try Announce.validate(packet)
        XCTAssertFalse(decoded.isPathResponse, "fresh announce is not a path response")
    }

    func testIsPathResponseTrueForPathResponseContext() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test"
        )
        var packet = try Announce.make(for: destination)
        packet.context = .pathResponse
        let decoded = try Announce.validate(packet)
        XCTAssertTrue(decoded.isPathResponse, "pathResponse context sets isPathResponse")
    }

    func testMakeAndValidate() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity,
            direction: .in,
            kind: .single,
            appName: "lxmf",
            aspects: ["delivery"]
        )
        let appData = Data("hello".utf8)
        let packet = try Announce.make(for: destination, appData: appData)
        XCTAssertEqual(packet.packetType, .announce)
        XCTAssertEqual(packet.destinationHash, destination.hash)

        let decoded = try Announce.validate(packet)
        XCTAssertEqual(decoded.identity.publicKeyBytes, identity.publicKeyBytes)
        XCTAssertEqual(decoded.appData, appData)
        XCTAssertEqual(decoded.destinationHash, destination.hash)
        XCTAssertNil(decoded.ratchet)
    }

    func testMakeAndValidateWithRatchet() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "rns", aspects: ["test"]
        )
        let ratchet = Data((0..<Constants.ratchetSize).map { _ in UInt8.random(in: 0...255) })
        let packet = try Announce.make(for: destination, ratchet: ratchet)
        XCTAssertEqual(packet.contextFlag, .set)
        let decoded = try Announce.validate(packet)
        XCTAssertEqual(decoded.ratchet, ratchet)
    }

    func testValidateRejectsTamperedSignature() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "rns"
        )
        var packet = try Announce.make(for: destination)
        // flip a bit in the signature region
        let sigOffset = Constants.keySize + Constants.nameHashLength + Constants.randomHashLength
        packet.data[sigOffset] ^= 0x01
        XCTAssertThrowsError(try Announce.validate(packet))
    }

    func testDestinationHashIsTruncatedSHA256OfNameHashAndIdentityHash() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single,
            appName: "lxmf", aspects: ["delivery"]
        )
        // Verify name hash matches Python: SHA256("lxmf.delivery")[:10]
        let expectedNameHash = Hashes
            .fullHash(Data("lxmf.delivery".utf8))
            .prefix(Constants.nameHashLength)
        XCTAssertEqual(destination.nameHash, expectedNameHash)
        // Destination hash matches: SHA256(name_hash + identity.hash)[:16]
        let expectedHash = Hashes.truncatedHash(destination.nameHash + identity.hash)
        XCTAssertEqual(destination.hash, expectedHash)
    }

    func testDecodedIncludesPacketHash() throws {
        let identity = Identity()
        let destination = try Destination(
            identity: identity, direction: .in, kind: .single, appName: "test"
        )
        let packet = try Announce.make(for: destination)
        let decoded = try Announce.validate(packet)
        // packetHash = truncatedHash(hashable_part) — must be 16 bytes
        XCTAssertEqual(decoded.packetHash.count, Constants.truncatedHashLength)
    }

    func testAnnounceHandlerReceivesPacketHash() throws {
        final class TestHandler: AnnounceHandler {
            var aspectFilter: String? = nil
            var gotHash: Data?
            func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                                  announcePacketHash: Data, isPathResponse: Bool) {
                gotHash = announcePacketHash
            }
        }

        let transport = Transport()
        let bIdentity = Identity()
        let bDest = try Destination(identity: bIdentity, direction: .in, kind: .single, appName: "test")
        transport.ownerIdentity = bIdentity
        transport.register(destination: bDest)

        let handler = TestHandler()
        transport.register(announceHandler: handler)

        let iface = AnnounceTestLoopback(name: "lo")
        transport.register(interface: iface)

        let packet = try Announce.make(for: bDest)
        iface.inboundHandler?(packet, iface)

        // Allow async dispatch to run.
        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertNotNil(handler.gotHash)
        XCTAssertEqual(handler.gotHash?.count, Constants.truncatedHashLength)
    }

    // MARK: - receivePathResponses filter

    func testHandlerWithDefaultReceivePathResponsesFalseSkipsPathResponses() throws {
        final class NoPathHandler: AnnounceHandler {
            var aspectFilter: String? = nil
            // receivePathResponses defaults to false
            var callCount = 0
            func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                                  announcePacketHash: Data, isPathResponse: Bool) {
                callCount += 1
            }
        }

        let transport = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "pr")
        transport.ownerIdentity = bId
        transport.register(destination: bDest)

        let handler = NoPathHandler()
        transport.register(announceHandler: handler)

        let iface = AnnounceTestLoopback(name: "lo2")
        transport.register(interface: iface)

        // Send a PATH_RESPONSE announce.
        var packet = try Announce.make(for: bDest)
        packet.context = .pathResponse
        iface.inboundHandler?(packet, iface)

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(handler.callCount, 0, "handler without receivePathResponses=true must not receive path responses")
    }

    func testHandlerWithReceivePathResponsesTrueReceivesPathResponses() throws {
        final class PathHandler: AnnounceHandler {
            var aspectFilter: String? = nil
            var receivePathResponses: Bool = true
            var callCount = 0
            func receivedAnnounce(destinationHash: Data, identity: Identity, appData: Data?,
                                  announcePacketHash: Data, isPathResponse: Bool) {
                callCount += 1
            }
        }

        let transport = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single, appName: "pr2")
        transport.ownerIdentity = bId
        transport.register(destination: bDest)

        let handler = PathHandler()
        transport.register(announceHandler: handler)

        let iface = AnnounceTestLoopback(name: "lo3")
        transport.register(interface: iface)

        var packet = try Announce.make(for: bDest)
        packet.context = .pathResponse
        iface.inboundHandler?(packet, iface)

        let exp = expectation(description: "tick")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(handler.callCount, 1)
    }
}

private final class AnnounceTestLoopback: Interface {
    var name: String; var bitrate: Int = 0; var isOnline: Bool = true
    var inboundHandler: ((Packet, any Interface) -> Void)?
    init(name: String) { self.name = name }
    func start() throws { isOnline = true }
    func stop() { isOnline = false }
    func send(_ packet: Packet) throws {}
}
