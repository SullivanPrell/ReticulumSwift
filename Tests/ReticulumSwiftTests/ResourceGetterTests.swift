import XCTest
@testable import ReticulumSwift

final class ResourceGetterTests: XCTestCase {

    private func makeLink() throws -> Link {
        let identity = Identity()
        let dest = try Destination(identity: identity, direction: .in, kind: .single,
                                   appName: "test", aspects: ["rgt"])
        let transport = Transport()
        transport.register(interface: LoopbackInterface(name: "RGTTest"))
        return try Link.initiate(destination: dest, transport: transport)
    }

    // MARK: - Python getter method parity

    func testGetProgressInitiallyZero() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getProgress(), 0.0)
        XCTAssertEqual(rt.getProgress(), rt.progress)
    }

    func testGetTransferSizeMirrorsProperty() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getTransferSize(), rt.transferSize)
    }

    func testGetDataSizeMirrorsProperty() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getDataSize(), rt.dataSize)
    }

    func testGetPartsMirrorsPartCount() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getParts(), rt.partCount)
    }

    func testGetSegmentsMirrorsSegmentCount() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getSegments(), rt.segmentCount)
        XCTAssertEqual(rt.getSegments(), 1, "Single-segment resource starts at 1")
    }

    func testGetHashMirrorsHash() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertEqual(rt.getHash(), rt.hash)
    }

    func testIsCompressedDefaultsFalse() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertFalse(rt.isCompressed)
    }

    func testHasMetadataDefaultsFalse() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertFalse(rt.hasMetadata)
    }

    func testResourceLinkReturnsLink() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        XCTAssertTrue(rt.resourceLink === link)
    }

    // MARK: - setCallback / setProgressCallback

    func testSetCallbackAssignsOnComplete() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        var called = false
        rt.setCallback { _ in called = true }
        XCTAssertNotNil(rt.onComplete)
        rt.onComplete?(rt)
        XCTAssertTrue(called)
    }

    func testSetProgressCallbackAssignsOnProgress() throws {
        let link = try makeLink()
        let rt = ResourceTransfer(link: link)
        var receivedProgress: Double = -1
        rt.setProgressCallback { p, _ in receivedProgress = p }
        XCTAssertNotNil(rt.onProgress)
        rt.onProgress?(0.5, rt)
        XCTAssertEqual(receivedProgress, 0.5)
    }
}
