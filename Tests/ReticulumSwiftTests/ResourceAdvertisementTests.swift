import XCTest
@testable import ReticulumSwift

final class ResourceAdvertisementTests: XCTestCase {

    func makeSample(requestID: Data? = nil, isResponse: Bool = false) -> ResourceAdvertisement {
        ResourceAdvertisement(
            transferSize: 1024,
            dataSize: 2048,
            partCount: 8,
            resourceHash: Data(repeating: 0xA1, count: 32),
            randomHash: Data(repeating: 0xB2, count: 32),
            originalHash: Data(repeating: 0xC3, count: 32),
            segmentIndex: 1,
            totalSegments: 4,
            requestID: requestID,
            hashmap: Data(repeating: 0xD4, count: 4 * 8),
            encrypted: true,
            compressed: false,
            split: true,
            isRequest: requestID != nil && !isResponse,
            isResponse: requestID != nil && isResponse,
            hasMetadata: false
        )
    }

    func testRoundTripPlain() throws {
        let adv = makeSample()
        let bytes = adv.pack()
        let decoded = try ResourceAdvertisement.unpack(bytes)
        XCTAssertEqual(decoded, adv)
    }

    func testRoundTripRequest() throws {
        let req = Data(repeating: 0x77, count: 16)
        let adv = makeSample(requestID: req)
        let decoded = try ResourceAdvertisement.unpack(adv.pack())
        XCTAssertEqual(decoded, adv)
        XCTAssertTrue(decoded.isRequest)
        XCTAssertFalse(decoded.isResponse)
        XCTAssertEqual(decoded.requestID, req)
    }

    func testRoundTripResponse() throws {
        let req = Data(repeating: 0x88, count: 16)
        let adv = makeSample(requestID: req, isResponse: true)
        let decoded = try ResourceAdvertisement.unpack(adv.pack())
        XCTAssertEqual(decoded, adv)
        XCTAssertTrue(decoded.isResponse)
    }

    func testFlagsBitLayout() {
        var adv = makeSample()
        adv.encrypted = true; adv.compressed = false; adv.split = false
        adv.isRequest = false; adv.isResponse = false; adv.hasMetadata = true
        XCTAssertEqual(adv.flags, 0x01 | 0x20)
    }

    func testEncodingHasAllExpectedKeys() throws {
        let adv = makeSample()
        let bytes = adv.pack()
        // Decode raw map and verify key set + insertion order matches Python.
        guard case .map(let pairs) = try MsgPack.decode(bytes) else {
            return XCTFail("expected map")
        }
        let keys: [String] = pairs.compactMap {
            if case .string(let s) = $0.0 { return s } else { return nil }
        }
        XCTAssertEqual(keys, ["t", "d", "n", "h", "r", "o", "i", "l", "q", "f", "m"])
    }
}
