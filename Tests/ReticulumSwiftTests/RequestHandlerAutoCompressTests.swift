import XCTest
@testable import ReticulumSwift

final class RequestHandlerAutoCompressTests: XCTestCase {

    func testDefaultAutoCompressIsTrue() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        dest.registerRequestHandler(path: "/test", allow: .all) { _, _, _, _, _ in Data() }
        let key = Hashes.truncatedHash(Data("/test".utf8))
        XCTAssertTrue(dest.requestHandlers[key]?.autoCompress ?? false,
                      "Default autoCompress should be true")
    }

    func testAutoCompressFalsePreserved() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        dest.registerRequestHandler(path: "/test", allow: .all, autoCompress: false) { _, _, _, _, _ in Data() }
        let key = Hashes.truncatedHash(Data("/test".utf8))
        XCTAssertFalse(dest.requestHandlers[key]?.autoCompress ?? true,
                       "autoCompress = false should be preserved")
    }

    func testAutoCompressTrueExplicit() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        dest.registerRequestHandler(path: "/test", allow: .all, autoCompress: true) { _, _, _, _, _ in Data() }
        let key = Hashes.truncatedHash(Data("/test".utf8))
        XCTAssertTrue(dest.requestHandlers[key]?.autoCompress ?? false)
    }

    func testMultipleHandlersIndependentAutoCompress() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        dest.registerRequestHandler(path: "/yes", allow: .all, autoCompress: true) { _, _, _, _, _ in Data() }
        dest.registerRequestHandler(path: "/no", allow: .all, autoCompress: false) { _, _, _, _, _ in Data() }

        let yesKey = Hashes.truncatedHash(Data("/yes".utf8))
        let noKey = Hashes.truncatedHash(Data("/no".utf8))

        XCTAssertTrue(dest.requestHandlers[yesKey]?.autoCompress ?? false)
        XCTAssertFalse(dest.requestHandlers[noKey]?.autoCompress ?? true)
    }

    func testAutoCompressStoredInEntry() throws {
        let dest = try Destination(identity: Identity(), direction: .in, kind: .single,
                                    appName: "test", aspects: ["compress"])
        dest.registerRequestHandler(path: "/data", allow: .all, autoCompress: false) { _, _, _, _, _ in nil }
        let key = Hashes.truncatedHash(Data("/data".utf8))
        let entry = dest.requestHandlers[key]
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry?.autoCompress, false)
        XCTAssertEqual(entry?.path, "/data")
    }
}
