import XCTest
@testable import ReticulumSwift

final class MsgPackTests: XCTestCase {

    func roundTrip(_ v: MsgPack.Value, file: StaticString = #file, line: UInt = #line) throws {
        let encoded = MsgPack.encode(v)
        let decoded = try MsgPack.decode(encoded)
        XCTAssertEqual(decoded, v, file: file, line: line)
    }

    func testFixintRoundTrip() throws {
        try roundTrip(.uint(0))
        try roundTrip(.uint(127))
        try roundTrip(.int(-1))
        try roundTrip(.int(-32))
    }

    func testIntWidthsRoundTrip() throws {
        try roundTrip(.uint(255))
        try roundTrip(.uint(256))
        try roundTrip(.uint(0xFFFF))
        try roundTrip(.uint(0x1_0000))
        try roundTrip(.uint(0xFFFF_FFFF))
        try roundTrip(.uint(0xFFFF_FFFF_FFFF_FFFF))
        try roundTrip(.int(-33))
        try roundTrip(.int(-128))
        try roundTrip(.int(-32768))
        try roundTrip(.int(Int64(Int32.min)))
        try roundTrip(.int(Int64.min))
    }

    func testStringWidthsRoundTrip() throws {
        try roundTrip(.string(""))
        try roundTrip(.string("hello"))
        try roundTrip(.string(String(repeating: "x", count: 32)))
        try roundTrip(.string(String(repeating: "y", count: 256)))
        try roundTrip(.string(String(repeating: "z", count: 70_000)))
    }

    func testBinWidthsRoundTrip() throws {
        try roundTrip(.bytes(Data()))
        try roundTrip(.bytes(Data(repeating: 0xAB, count: 10)))
        try roundTrip(.bytes(Data(repeating: 0xCD, count: 256)))
        try roundTrip(.bytes(Data(repeating: 0xEF, count: 70_000)))
    }

    func testNilBoolDouble() throws {
        try roundTrip(.nil)
        try roundTrip(.bool(true))
        try roundTrip(.bool(false))
        try roundTrip(.double(3.14159))
        try roundTrip(.double(-0.0))
    }

    func testArrayAndMap() throws {
        try roundTrip(.array([.uint(1), .string("two"), .nil, .bool(true)]))
        try roundTrip(.map([
            (.string("a"), .uint(1)),
            (.string("b"), .bytes(Data([0x01, 0x02]))),
            (.string("c"), .nil),
        ]))
    }

    func testFloat64TagMatchesPython() {
        // Python: msgpack.packb(1.5) → b'\xcb?\xf8\x00\x00\x00\x00\x00\x00'
        let encoded = MsgPack.encode(.double(1.5))
        XCTAssertEqual(encoded, Data([0xCB, 0x3F, 0xF8, 0, 0, 0, 0, 0, 0]))
    }

    func testFixstrTagMatchesPython() {
        // "hi" → 0xA2 'h' 'i'
        XCTAssertEqual(MsgPack.encode(.string("hi")), Data([0xA2, 0x68, 0x69]))
    }
}
