import XCTest
@testable import ReticulumSwift

/// Tests for the rnx remote-execution protocol wire types.
/// Python reference: RNS/Utilities/rnx.py

final class RNXProtocolTests: XCTestCase {

    // MARK: - RNXApp constants

    func testAppName() {
        XCTAssertEqual(RNXApp.appName, "rnx")
    }

    func testReqFetchNotAllowed() {
        XCTAssertEqual(RNXApp.reqFetchNotAllowed, 0xF0)
    }

    // MARK: - RNXRequest encoding

    func testRequestPackProducesArray() throws {
        let req = RNXRequest(command: "ls")
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else {
            return XCTFail("expected msgpack array")
        }
        XCTAssertEqual(arr.count, 5)
    }

    func testRequestPackCommandAsBin() throws {
        // Python: request_data[0] = command.encode("utf-8")
        let req = RNXRequest(command: "echo hi")
        guard case .array(let arr) = try MsgPack.decode(req.pack()),
              case .bytes(let cmdBytes) = arr[0] else {
            return XCTFail("expected bytes at index 0")
        }
        XCTAssertEqual(String(data: cmdBytes, encoding: .utf8), "echo hi")
    }

    func testRequestPackTimeoutNilByDefault() throws {
        let req = RNXRequest(command: "ls")
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else { return XCTFail() }
        XCTAssertEqual(arr[1], .nil)
    }

    func testRequestPackTimeoutValue() throws {
        var req = RNXRequest(command: "sleep 1")
        req.timeout = 30
        guard case .array(let arr) = try MsgPack.decode(req.pack()),
              case .double(let t) = arr[1] else {
            return XCTFail("expected double at index 1")
        }
        XCTAssertEqual(t, 30.0, accuracy: 0.001)
    }

    func testRequestPackStdoutLimitNilByDefault() throws {
        let req = RNXRequest(command: "ls")
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else { return XCTFail() }
        XCTAssertEqual(arr[2], .nil)
    }

    func testRequestPackStdoutLimit() throws {
        var req = RNXRequest(command: "ls")
        req.stdoutLimit = 4096
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else { return XCTFail() }
        XCTAssertEqual(arr[2], .int(4096))
    }

    func testRequestPackStderrLimitNilByDefault() throws {
        let req = RNXRequest(command: "ls")
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else { return XCTFail() }
        XCTAssertEqual(arr[3], .nil)
    }

    func testRequestPackStdinNilByDefault() throws {
        let req = RNXRequest(command: "ls")
        guard case .array(let arr) = try MsgPack.decode(req.pack()) else { return XCTFail() }
        XCTAssertEqual(arr[4], .nil)
    }

    func testRequestPackStdinData() throws {
        var req = RNXRequest(command: "cat")
        req.stdin = Data("hello input\n".utf8)
        guard case .array(let arr) = try MsgPack.decode(req.pack()),
              case .bytes(let stdinBytes) = arr[4] else {
            return XCTFail("expected bytes at index 4")
        }
        XCTAssertEqual(stdinBytes, Data("hello input\n".utf8))
    }

    // MARK: - RNXResult decoding

    func testResultDecodeExecutedSuccess() throws {
        let packed = makeResult(executed: true, returnCode: 0,
                                stdout: Data("ok\n".utf8), stderr: nil,
                                outLen: 3, errLen: 0,
                                started: 1000.0, concluded: 1001.5)
        let r = try RNXResult(unpackFrom: packed)
        XCTAssertTrue(r.executed)
        XCTAssertEqual(r.returnCode, 0)
        XCTAssertEqual(r.stdout, Data("ok\n".utf8))
        XCTAssertNil(r.stderr)
        XCTAssertEqual(r.totalStdoutLength, 3)
        XCTAssertEqual(r.totalStderrLength, 0)
        XCTAssertEqual(r.startedAt ?? 0, 1000.0, accuracy: 0.001)
        XCTAssertEqual(r.concludedAt ?? 0, 1001.5, accuracy: 0.001)
    }

    func testResultDecodeNotExecuted() throws {
        let packed = makeResult(executed: false, returnCode: nil,
                                stdout: nil, stderr: nil,
                                outLen: nil, errLen: nil,
                                started: 2000.0, concluded: nil)
        let r = try RNXResult(unpackFrom: packed)
        XCTAssertFalse(r.executed)
        XCTAssertNil(r.returnCode)
        XCTAssertNil(r.stdout)
        XCTAssertNil(r.concludedAt)
    }

    func testResultDecodeNonZeroReturn() throws {
        let packed = makeResult(executed: true, returnCode: 127,
                                stdout: nil, stderr: Data("cmd not found\n".utf8),
                                outLen: 0, errLen: 14,
                                started: 5.0, concluded: 5.1)
        let r = try RNXResult(unpackFrom: packed)
        XCTAssertEqual(r.returnCode, 127)
        XCTAssertEqual(r.stderr, Data("cmd not found\n".utf8))
        XCTAssertEqual(r.totalStderrLength, 14)
    }

    // MARK: - Helpers

    private func makeResult(
        executed: Bool, returnCode: Int?,
        stdout: Data?, stderr: Data?,
        outLen: Int?, errLen: Int?,
        started: Double, concluded: Double?
    ) -> Data {
        MsgPack.encode(.array([
            .bool(executed),
            returnCode.map { .int(Int64($0)) } ?? .nil,
            stdout.map    { .bytes($0) }        ?? .nil,
            stderr.map    { .bytes($0) }        ?? .nil,
            outLen.map    { .int(Int64($0)) }   ?? .nil,
            errLen.map    { .int(Int64($0)) }   ?? .nil,
            .double(started),
            concluded.map { .double($0) }       ?? .nil,
        ]))
    }
}
