import XCTest
@testable import ReticulumSwift

/// Tests for Resource advertisement static inspection helpers.
///
/// Python reference (Resource.py — ResourceAdvertisement):
///   Resource.is_request(advertisement_packet)   → bool
///   Resource.is_response(advertisement_packet)  → bool
///   Resource.read_request_id(advertisement_packet) → bytes (10 bytes) | None
///   Resource.read_transfer_size(advertisement_packet) → int
///   Resource.read_size(advertisement_packet)        → int
///
/// These allow inspecting an advertisement DATA packet before deciding whether
/// to accept the resource.
final class ResourceAdvertisementInspectionTests: XCTestCase {

    // MARK: - Helpers

    /// Build a plain advertisement packet (DATA, no special flags).
    private func makeAdPacket(isRequest: Bool = false,
                               isResponse: Bool = false,
                               dataSize: Int = 1024,
                               requestID: Data? = nil) -> Packet {
        let ad = ResourceAdvertisement(
            transferSize: UInt64(dataSize),
            dataSize:     UInt64(dataSize),
            partCount:    1,
            resourceHash: Hashes.randomHash(),
            randomHash:   Hashes.randomHash().prefix(4),
            originalHash: Hashes.randomHash(),
            segmentIndex: 0,
            totalSegments: 1,
            requestID: requestID,
            isRequest:  isRequest,
            isResponse: isResponse
        )
        let packed = ad.pack()
        return Packet(
            destinationType: .single,
            packetType: .data,
            destinationHash: Data(repeating: 0xAA, count: 16),
            context: .resource,
            data: packed
        )
    }

    // MARK: - isRequest

    func testIsRequestTrueForRequestAd() {
        let packet = makeAdPacket(isRequest: true, requestID: Hashes.randomHash().prefix(10))
        XCTAssertTrue(Resource.isRequest(advertisementPacket: packet),
                      "isRequest must return true for a request advertisement")
    }

    func testIsRequestFalseForPlainAd() {
        let packet = makeAdPacket()
        XCTAssertFalse(Resource.isRequest(advertisementPacket: packet),
                       "isRequest must return false for a plain advertisement")
    }

    func testIsRequestFalseForResponseAd() {
        let packet = makeAdPacket(isResponse: true, requestID: Hashes.randomHash().prefix(10))
        XCTAssertFalse(Resource.isRequest(advertisementPacket: packet),
                       "isRequest must be false for a response advertisement")
    }

    // MARK: - isResponse

    func testIsResponseTrueForResponseAd() {
        let packet = makeAdPacket(isResponse: true, requestID: Hashes.randomHash().prefix(10))
        XCTAssertTrue(Resource.isResponse(advertisementPacket: packet),
                      "isResponse must return true for a response advertisement")
    }

    func testIsResponseFalseForPlainAd() {
        let packet = makeAdPacket()
        XCTAssertFalse(Resource.isResponse(advertisementPacket: packet),
                       "isResponse must return false for a plain advertisement")
    }

    // MARK: - readRequestID

    func testReadRequestIDReturnsIdForRequestAd() {
        let rid = Hashes.randomHash().prefix(10)
        let packet = makeAdPacket(isRequest: true, requestID: Data(rid))
        let result = Resource.readRequestID(advertisementPacket: packet)
        XCTAssertNotNil(result, "readRequestID must return a value for a request advertisement")
        XCTAssertEqual(result?.count, 10, "request ID must be 10 bytes")
        XCTAssertEqual(result, Data(rid))
    }

    func testReadRequestIDNilForPlainAd() {
        let packet = makeAdPacket()
        let result = Resource.readRequestID(advertisementPacket: packet)
        // Plain ad has no requestID — must be nil or empty
        if let r = result { XCTAssertTrue(r.isEmpty, "plain ad must not have a non-empty request ID") }
    }

    // MARK: - readTransferSize / readSize

    func testReadTransferSizeMatchesAdvertised() {
        let packet = makeAdPacket(dataSize: 2048)
        XCTAssertEqual(Resource.readTransferSize(advertisementPacket: packet), 2048,
                       "readTransferSize must match the advertised transfer size")
    }

    func testReadSizeMatchesAdvertised() {
        let packet = makeAdPacket(dataSize: 512)
        XCTAssertEqual(Resource.readSize(advertisementPacket: packet), 512,
                       "readSize must match the advertised data size")
    }

    func testReadSizePositive() {
        let packet = makeAdPacket(dataSize: 100)
        XCTAssertGreaterThan(Resource.readSize(advertisementPacket: packet), 0)
    }
}
