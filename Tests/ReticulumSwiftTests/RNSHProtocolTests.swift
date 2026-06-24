import XCTest
@testable import ReticulumSwift

/// Tests for rnsh protocol constants and channel message types.
/// Python reference: RNS/Utilities/rnsh/protocol.py

final class RNSHProtocolTests: XCTestCase {

    // MARK: - Module constants

    func testAppName() {
        XCTAssertEqual(RNSHProtocol.appName, "rnsh")
    }

    func testMsgMagic() {
        XCTAssertEqual(RNSHProtocol.msgMagic, 0xac)
    }

    func testProtocolVersion() {
        // Python: PROTOCOL_VERSION = 1
        XCTAssertEqual(RNSHProtocol.protocolVersion, 1)
    }

    func testStreamIDStdin() {
        // Python: STREAM_ID_STDIN = 0
        XCTAssertEqual(RNSHProtocol.streamIDStdin, 0)
    }

    func testStreamIDStdout() {
        // Python: STREAM_ID_STDOUT = 1
        XCTAssertEqual(RNSHProtocol.streamIDStdout, 1)
    }

    func testStreamIDStderr() {
        // Python: STREAM_ID_STDERR = 2
        XCTAssertEqual(RNSHProtocol.streamIDStderr, 2)
    }

    // MARK: - makeMessageType helper

    func testMakeMessageType0() {
        // ((0xac << 8) & 0xff00) | (0 & 0x00ff) = 0xac00
        XCTAssertEqual(RNSHProtocol.makeMessageType(0), 0xac00)
    }

    func testMakeMessageType7() {
        XCTAssertEqual(RNSHProtocol.makeMessageType(7), 0xac07)
    }

    func testMakeMessageTypeMaskBound() {
        // High nibble always comes from msgMagic
        let t = RNSHProtocol.makeMessageType(0xff)
        XCTAssertEqual(t >> 8, UInt16(RNSHProtocol.msgMagic))
    }

    // MARK: - Message type IDs

    func testNoopMessageTypeID() {
        XCTAssertEqual(RNSHNoopMessage.typeID, 0xac00)
    }

    func testWindowSizeMessageTypeID() {
        XCTAssertEqual(RNSHWindowSizeMessage.typeID, 0xac02)
    }

    func testExecuteCommandMessageTypeID() {
        XCTAssertEqual(RNSHExecuteCommandMessage.typeID, 0xac03)
    }

    func testStreamDataMessageTypeID() {
        XCTAssertEqual(RNSHStreamDataMessage.typeID, 0xac04)
    }

    func testVersionInfoMessageTypeID() {
        XCTAssertEqual(RNSHVersionInfoMessage.typeID, 0xac05)
    }

    func testErrorMessageTypeID() {
        XCTAssertEqual(RNSHErrorMessage.typeID, 0xac06)
    }

    func testCommandExitedMessageTypeID() {
        XCTAssertEqual(RNSHCommandExitedMessage.typeID, 0xac07)
    }

    // MARK: - All type IDs are distinct

    func testAllTypeIDsDistinct() {
        let ids: [UInt16] = [
            RNSHNoopMessage.typeID,
            RNSHWindowSizeMessage.typeID,
            RNSHExecuteCommandMessage.typeID,
            RNSHStreamDataMessage.typeID,
            RNSHVersionInfoMessage.typeID,
            RNSHErrorMessage.typeID,
            RNSHCommandExitedMessage.typeID,
        ]
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    // MARK: - NoopMessage

    func testNoopPackIsEmpty() throws {
        XCTAssertTrue(try RNSHNoopMessage().pack().isEmpty)
    }

    func testNoopUnpackDoesNotThrow() {
        XCTAssertNoThrow(try RNSHNoopMessage().unpack(Data()))
    }

    // MARK: - WindowSizeMessage

    func testWindowSizeRoundtrip() throws {
        let m = RNSHWindowSizeMessage()
        m.rows = 24; m.cols = 80; m.hpix = 640; m.vpix = 480
        let m2 = RNSHWindowSizeMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.rows, 24)
        XCTAssertEqual(m2.cols, 80)
        XCTAssertEqual(m2.hpix, 640)
        XCTAssertEqual(m2.vpix, 480)
    }

    func testWindowSizeNilFieldsRoundtrip() throws {
        let m = RNSHWindowSizeMessage() // all nil
        let m2 = RNSHWindowSizeMessage()
        try m2.unpack(m.pack())
        XCTAssertNil(m2.rows)
        XCTAssertNil(m2.cols)
        XCTAssertNil(m2.hpix)
        XCTAssertNil(m2.vpix)
    }

    func testWindowSizePackIsArray() throws {
        let m = RNSHWindowSizeMessage()
        guard case .array(let arr) = try MsgPack.decode(m.pack()) else {
            return XCTFail("expected msgpack array")
        }
        XCTAssertEqual(arr.count, 4)
    }

    // MARK: - VersionInfoMessage

    func testVersionInfoRoundtrip() throws {
        let m = RNSHVersionInfoMessage()
        m.swVersion = "0.7.0"
        m.protocolVersion = 1
        let m2 = RNSHVersionInfoMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.swVersion, "0.7.0")
        XCTAssertEqual(m2.protocolVersion, 1)
    }

    func testVersionInfoDefaultProtocolVersion() {
        XCTAssertEqual(RNSHVersionInfoMessage().protocolVersion, RNSHProtocol.protocolVersion)
    }

    func testVersionInfoPackIsArray() throws {
        let m = RNSHVersionInfoMessage()
        guard case .array(let arr) = try MsgPack.decode(m.pack()) else {
            return XCTFail("expected msgpack array")
        }
        XCTAssertEqual(arr.count, 2)
    }

    // MARK: - ErrorMessage

    func testErrorMessageRoundtrip() throws {
        let m = RNSHErrorMessage()
        m.msg = "connection denied"
        m.fatal = true
        let m2 = RNSHErrorMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.msg, "connection denied")
        XCTAssertTrue(m2.fatal)
    }

    func testErrorMessageNilMsgRoundtrip() throws {
        let m = RNSHErrorMessage() // msg = nil, fatal = false
        let m2 = RNSHErrorMessage()
        try m2.unpack(m.pack())
        XCTAssertNil(m2.msg)
        XCTAssertFalse(m2.fatal)
    }

    func testErrorMessagePackIsArray() throws {
        let m = RNSHErrorMessage()
        guard case .array(let arr) = try MsgPack.decode(m.pack()) else {
            return XCTFail("expected msgpack array")
        }
        XCTAssertEqual(arr.count, 3)
    }

    // MARK: - CommandExitedMessage

    func testCommandExitedZeroReturn() throws {
        let m = RNSHCommandExitedMessage(); m.returnCode = 0
        let m2 = RNSHCommandExitedMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.returnCode, 0)
    }

    func testCommandExited127Return() throws {
        let m = RNSHCommandExitedMessage(); m.returnCode = 127
        let m2 = RNSHCommandExitedMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.returnCode, 127)
    }

    func testCommandExitedNilReturn() throws {
        let m = RNSHCommandExitedMessage() // returnCode = nil
        let m2 = RNSHCommandExitedMessage()
        try m2.unpack(m.pack())
        XCTAssertNil(m2.returnCode)
    }

    // MARK: - RNSHStreamDataMessage

    func testStreamDataStdoutRoundtrip() throws {
        let m = RNSHStreamDataMessage()
        m.streamID = RNSHProtocol.streamIDStdout
        m.data = Data("hello stdout\n".utf8)
        let m2 = RNSHStreamDataMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.streamID, RNSHProtocol.streamIDStdout)
        XCTAssertEqual(m2.data, Data("hello stdout\n".utf8))
        XCTAssertFalse(m2.eof)
    }

    func testStreamDataEOF() throws {
        let m = RNSHStreamDataMessage()
        m.streamID = RNSHProtocol.streamIDStdin
        m.eof = true
        m.data = Data()
        let m2 = RNSHStreamDataMessage()
        try m2.unpack(m.pack())
        XCTAssertTrue(m2.eof)
        XCTAssertEqual(m2.streamID, RNSHProtocol.streamIDStdin)
    }

    func testStreamDataStderrRoundtrip() throws {
        let m = RNSHStreamDataMessage()
        m.streamID = RNSHProtocol.streamIDStderr
        m.data = Data("error: not found\n".utf8)
        let m2 = RNSHStreamDataMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.streamID, RNSHProtocol.streamIDStderr)
        XCTAssertEqual(m2.data, Data("error: not found\n".utf8))
    }

    // MARK: - ExecuteCommandMessage

    func testExecuteCommandRoundtrip() throws {
        let m = RNSHExecuteCommandMessage()
        m.cmdline    = ["/bin/bash", "-c", "echo hi"]
        m.pipeStdin  = true
        m.pipeStdout = true
        m.pipeStderr = false
        m.term       = "xterm-256color"
        m.rows       = 24
        m.cols       = 80
        m.hpix       = 640
        m.vpix       = 480
        let m2 = RNSHExecuteCommandMessage()
        try m2.unpack(m.pack())
        XCTAssertEqual(m2.cmdline, ["/bin/bash", "-c", "echo hi"])
        XCTAssertTrue(m2.pipeStdin)
        XCTAssertTrue(m2.pipeStdout)
        XCTAssertFalse(m2.pipeStderr)
        XCTAssertEqual(m2.term, "xterm-256color")
        XCTAssertEqual(m2.rows, 24)
        XCTAssertEqual(m2.cols, 80)
        XCTAssertEqual(m2.hpix, 640)
        XCTAssertEqual(m2.vpix, 480)
    }

    func testExecuteCommandNilCmdlineRoundtrip() throws {
        let m = RNSHExecuteCommandMessage() // cmdline = nil
        let m2 = RNSHExecuteCommandMessage()
        try m2.unpack(m.pack())
        XCTAssertNil(m2.cmdline)
    }

    func testExecuteCommandPackIsArray() throws {
        let m = RNSHExecuteCommandMessage()
        guard case .array(let arr) = try MsgPack.decode(m.pack()) else {
            return XCTFail("expected msgpack array")
        }
        XCTAssertEqual(arr.count, 10)
    }

    // MARK: - RNSHSessionState

    func testSessionStateWaitIdent()   { XCTAssertEqual(RNSHSessionState.waitIdent.rawValue,   1) }
    func testSessionStateWaitVersion() { XCTAssertEqual(RNSHSessionState.waitVersion.rawValue, 2) }
    func testSessionStateWaitCommand() { XCTAssertEqual(RNSHSessionState.waitCommand.rawValue, 3) }
    func testSessionStateRunning()     { XCTAssertEqual(RNSHSessionState.running.rawValue,     4) }
    func testSessionStateError()       { XCTAssertEqual(RNSHSessionState.error.rawValue,       5) }
    func testSessionStateTeardown()    { XCTAssertEqual(RNSHSessionState.teardown.rawValue,    6) }
}
