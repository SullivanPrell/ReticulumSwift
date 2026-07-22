import XCTest
@testable import ReticulumSwift

/// Tests for Resource compression behavior.
///
/// Note: The default compressor is `BZip2Compressor`, matching the Python
/// reference (which bz2-compresses resource-sized payloads). The `compressed`
/// flag is recorded per-resource in the advertisement, so this stays
/// wire-compatible — a resource is only marked compressed when bz2 actually
/// shrinks it. Install `NoCompressor()` to opt out.
final class ResourceCompressionTests: XCTestCase {

    func testCompressesByDefault() throws {
        let payload = Data(repeating: 0xAA, count: 1000)
        let resource = try Resource(link: dummyLink(), payload: payload, autoCompress: true)
        // With the default BZip2Compressor, a highly compressible payload is
        // sent compressed (compressed=true in the advertisement).
        XCTAssertTrue(resource.isCompressed, "default BZip2Compressor should compress a compressible payload")
    }

    func testNoCompressorOptOut() throws {
        let saved = Resource.compressor
        defer { Resource.compressor = saved }
        Resource.compressor = NoCompressor()
        let payload = Data(repeating: 0xAA, count: 1000)
        let resource = try Resource(link: dummyLink(), payload: payload, autoCompress: true)
        XCTAssertFalse(resource.isCompressed, "installing NoCompressor must send uncompressed")
    }

    func testAutoCompressCanBeDisabled() throws {
        let compressible = Data(repeating: 0xBB, count: 1000)
        let resource = try Resource(link: dummyLink(), payload: compressible, autoCompress: false)
        XCTAssertFalse(resource.isCompressed, "autoCompress=false should not compress")
    }

    func testDataSizeReflectsOriginalUncompressedSize() throws {
        let payload = Data(repeating: 0xCC, count: 500)
        let resource = try Resource(link: dummyLink(), payload: payload, autoCompress: true)
        XCTAssertEqual(resource.dataSize, payload.count)
    }

    func testTransferSizeReflectsEncryptedWireSize() throws {
        let payload = Data(repeating: 0xDD, count: 100)
        let resource = try Resource(link: dummyLink(), payload: payload, autoCompress: true)
        XCTAssertGreaterThan(resource.transferSize, 0)
    }

    func testCompressorIsPluggable() {
        let original = Resource.compressor
        defer { Resource.compressor = original }

        // A custom compressor can be injected
        struct IdentityCompressor: DataCompressor {
            func compress(_ data: Data) -> Data? { nil }  // still no compress
            func decompress(_ data: Data) -> Data? { nil }
        }
        Resource.compressor = IdentityCompressor()
        XCTAssertNotNil(Resource.compressor)  // just verify protocol conformance
    }

    // MARK: - Round-trip compression verification

    func testCompressedRoundTripPreservesData() throws {
        let (aLink, bLink) = try makeActiveLinks()
        let compressible = Data(repeating: 0xEE, count: 2000)

        let done = expectation(description: "transfer-complete")
        var received: Data?

        let sender = ResourceTransfer(link: aLink)
        sender.onComplete = { _ in done.fulfill() }
        let receiver = ResourceTransfer(link: bLink)
        receiver.bindAsReceiver()
        receiver.onPayloadReceived = { data, _ in received = data }

        try sender.send(payload: compressible)
        wait(for: [done], timeout: 3.0)

        XCTAssertEqual(received, compressible, "round-trip must preserve data even when compressed")
    }

    // MARK: - Helpers

    private func dummyLink() throws -> Link {
        let (a, _) = try makeActiveLinks()
        return a
    }

    var at: Transport!; var bt: Transport!

    private func makeActiveLinks() throws -> (Link, Link) {
        at = Transport(); bt = Transport()
        let bId = Identity()
        let bDest = try Destination(identity: bId, direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        bt.ownerIdentity = bId; bt.register(destination: bDest)
        let aI = LoopbackInterface(name: "A"); let bI = LoopbackInterface(name: "B")
        aI.paired = bI; bI.paired = aI
        at.register(interface: aI); bt.register(interface: bI)
        let aE = expectation(description: "a"); let bE = expectation(description: "b")
        at.onLinkEstablished = { _ in aE.fulfill() }; bt.onLinkEstablished = { _ in bE.fulfill() }
        let aLink = try Link.initiate(destination: bDest, transport: at)
        wait(for: [aE, bE], timeout: 1.0)
        let bLink = try XCTUnwrap(bt.links[aLink.linkID!])
        return (aLink, bLink)
    }

    final class LoopbackInterface: Interface {
        var name: String; var bitrate: Int = 0; var isOnline: Bool = true
        weak var paired: LoopbackInterface?
        var inboundHandler: ((Packet, any Interface) -> Void)?
        init(name: String) { self.name = name }
        func start() throws { isOnline = true }
        func stop() { isOnline = false }
        func send(_ packet: Packet) throws {
            let raw = try packet.pack(); let copy = try Packet.unpack(raw)
            paired?.inboundHandler?(copy, paired!)
        }
    }
}
