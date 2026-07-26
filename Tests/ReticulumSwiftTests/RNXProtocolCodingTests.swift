import XCTest
@testable import ReticulumSwift

/// Wire coding for the rnx request/response arrays.
/// Python reference: RNS/Utilities/rnx.py:155-160 (request decode), :167-252 (result build),
/// :379-385 (request build), :441-457 (result decode).
final class RNXProtocolCodingTests: XCTestCase {

    // MARK: - RNXRequest

    func testRequestRoundTrip() throws {
        let request = RNXRequest(command: "echo hi",
                                 timeout: 15,
                                 stdoutLimit: 4096,
                                 stderrLimit: 0,
                                 stdin: Data("x".utf8))
        guard case .array(let arr) = request.packedValue() else { return XCTFail("expected array") }
        XCTAssertEqual(arr.count, 5)
        // Python: [command.encode("utf-8"), timeout, stdoutl, stderrl, stdin]
        XCTAssertEqual(arr[0], .bytes(Data("echo hi".utf8)))
        XCTAssertEqual(arr[1], .double(15))
        XCTAssertEqual(arr[2], .int(4096))
        XCTAssertEqual(arr[3], .int(0))
        XCTAssertEqual(arr[4], .bytes(Data("x".utf8)))

        let decoded = try RNXRequest(unpacking: request.packedValue())
        XCTAssertEqual(decoded.command, "echo hi")
        XCTAssertEqual(decoded.timeout, 15)
        XCTAssertEqual(decoded.stdoutLimit, 4096)
        XCTAssertEqual(decoded.stderrLimit, 0)
        XCTAssertEqual(decoded.stdin, Data("x".utf8))
    }

    func testTimeoutPacksAsIntegerMatchesPythonDefaultedW() throws {
        // Python: `-w` defaults to Transport.PATH_REQUEST_TIMEOUT, which is the *int* 15,
        // and argparse does not coerce non-string defaults through type=float. The wire
        // byte is therefore positive fixint 0x0F, not float64.
        var request = RNXRequest(command: "ls", timeout: 15)
        request.timeoutPacksAsInteger = true
        guard case .array(let arr) = request.packedValue() else { return XCTFail() }
        XCTAssertEqual(arr[1], .int(15))
        XCTAssertTrue(MsgPack.encode(arr[1]).elementsEqual([0x0F]))

        request.timeoutPacksAsInteger = false
        guard case .array(let asFloat) = request.packedValue() else { return XCTFail() }
        XCTAssertEqual(asFloat[1], .double(15))
        XCTAssertEqual(MsgPack.encode(asFloat[1]).first, 0xCB)   // float64
    }

    func testRequestDecodeAcceptsEveryTimeoutEncoding() throws {
        let command = MsgPack.Value.bytes(Data("ls".utf8))
        for (encoding, expected) in [(MsgPack.Value.int(15), 15.0),
                                     (MsgPack.Value.uint(15), 15.0),
                                     (MsgPack.Value.double(15.5), 15.5)] {
            let value = MsgPack.Value.array([command, encoding, .nil, .nil, .nil])
            XCTAssertEqual(try RNXRequest(unpacking: value).timeout, expected)
        }
        let nilTimeout = MsgPack.Value.array([command, .nil, .nil, .nil, .nil])
        XCTAssertNil(try RNXRequest(unpacking: nilTimeout).timeout)
    }

    func testRequestDecodeRejectsWrongArity() {
        let command = MsgPack.Value.bytes(Data("ls".utf8))
        for count in [4, 6] {
            let value = MsgPack.Value.array(Array(repeating: command, count: count))
            XCTAssertThrowsError(try RNXRequest(unpacking: value)) { error in
                XCTAssertEqual(error as? RNXError, .malformedRequest)
            }
        }
    }

    func testRequestDecodeRejectsNonBytesCommand() {
        // Python: data[0].decode("utf-8") — a str or int here raises AttributeError inside
        // the response generator, and no response is sent.
        let value = MsgPack.Value.array([.string("ls"), .nil, .nil, .nil, .nil])
        XCTAssertThrowsError(try RNXRequest(unpacking: value)) { error in
            XCTAssertEqual(error as? RNXError, .malformedRequest)
        }
    }

    func testRequestUnpackFromData() throws {
        let request = RNXRequest(command: "cat", stdin: Data("in".utf8))
        let decoded = try RNXRequest(unpackFrom: MsgPack.encode(request.packedValue()))
        XCTAssertEqual(decoded.command, "cat")
        XCTAssertEqual(decoded.stdin, Data("in".utf8))
    }

    // MARK: - RNXResult

    func testResultRoundTripAllFields() throws {
        let result = RNXResult(executed: true,
                               returnCode: 0,
                               stdout: Data("ok\n".utf8),
                               stderr: Data(),
                               totalStdoutLength: 3,
                               totalStderrLength: 0,
                               startedAt: 1000.5,
                               concludedAt: 1002.25)
        guard case .array(let arr) = result.packedValue() else { return XCTFail("expected array") }
        XCTAssertEqual(arr.count, 8)
        XCTAssertEqual(arr[0], .bool(true))
        // Python's vendored umsgpack auto-detects _float_precision = "double" on 64-bit,
        // so timestamps are always 0xCB float64.
        XCTAssertEqual(MsgPack.encode(arr[6]).first, 0xCB)

        let decoded = try RNXResult(unpackFrom: result.pack())
        XCTAssertTrue(decoded.executed)
        XCTAssertEqual(decoded.returnCode, 0)
        XCTAssertEqual(decoded.stdout, Data("ok\n".utf8))
        XCTAssertEqual(decoded.stderr, Data())
        XCTAssertEqual(decoded.totalStdoutLength, 3)
        XCTAssertEqual(decoded.totalStderrLength, 0)
        XCTAssertEqual(decoded.startedAt, 1000.5)
        XCTAssertEqual(decoded.concludedAt, 1002.25)
    }

    func testResultRoundTripNilFields() throws {
        // Python's spawn-failure result: [False, None, None, None, None, None, started, None].
        let result = RNXResult(executed: false, startedAt: 42.0)
        guard case .array(let arr) = result.packedValue() else { return XCTFail() }
        XCTAssertEqual(arr, [.bool(false), .nil, .nil, .nil, .nil, .nil, .double(42.0), .nil])

        let decoded = try RNXResult(unpackFrom: result.pack())
        XCTAssertFalse(decoded.executed)
        XCTAssertNil(decoded.returnCode)
        XCTAssertNil(decoded.stdout)
        XCTAssertNil(decoded.stderr)
        XCTAssertNil(decoded.totalStdoutLength)
        XCTAssertNil(decoded.totalStderrLength)
        XCTAssertNil(decoded.concludedAt)
    }

    func testResultDecodeAcceptsIntegerTimestamps() throws {
        let value = MsgPack.Value.array([
            .bool(true), .int(0), .nil, .nil, .int(0), .int(0), .int(1000), .uint(1001),
        ])
        let decoded = try RNXResult(unpacking: value)
        XCTAssertEqual(decoded.startedAt, 1000)
        XCTAssertEqual(decoded.concludedAt, 1001)
    }

    func testResultDecodeRejectsWrongShape() {
        let short = MsgPack.Value.array(Array(repeating: MsgPack.Value.nil, count: 7))
        XCTAssertThrowsError(try RNXResult(unpacking: short)) { error in
            XCTAssertEqual(error as? RNXError, .malformedResponse)
        }
        let nonBool = MsgPack.Value.array([.int(1)] + Array(repeating: MsgPack.Value.nil, count: 7))
        XCTAssertThrowsError(try RNXResult(unpacking: nonBool)) { error in
            XCTAssertEqual(error as? RNXError, .malformedResponse)
        }
    }

    func testRNXErrorIsEquatableAndKeepsExecutionDenied() {
        // executionDenied is unused but must survive for source compatibility.
        XCTAssertEqual(RNXError.executionDenied, RNXError.executionDenied)
        XCTAssertNotEqual(RNXError.malformedRequest, RNXError.malformedResponse)
    }
}
