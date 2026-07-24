import XCTest
@testable import ReticulumSwift

/// Validating an `.rsm` whose embedded message is not valid UTF-8.
///
/// Python prints the message with a **strict** decode:
///
///     print(signed_data["message"].decode("utf-8"))       # rnid.py:733
///
/// so a signed message containing arbitrary bytes raises `UnicodeDecodeError` *after*
/// "Signature is valid …" has already been printed — an unhandled traceback, not a
/// diagnostic. Nothing upstream catches it.
///
/// This port decodes lossily instead: the signature verdict is still correct (that is
/// computed over the raw bytes, which are unaffected), and undecodable bytes render as
/// U+FFFD rather than taking the process down. Reproducing the traceback would mean
/// crashing on a validly-signed file, which is worse than showing replacement characters.
///
/// Started life as a print-only probe with no assertions; kept because nothing else covers
/// a non-UTF-8 embedded message, and because the divergence from Python is deliberate and
/// worth pinning.
final class RNIDNonUTF8MessageTests: XCTestCase {

    /// Bytes that cannot be decoded as UTF-8, wrapped around text that can.
    private let badMessage = Data([0xFF, 0xFE, 0xFD]) + Data(" invalid utf8 ".utf8) + Data([0x80])

    private func makeSignedMessage(_ identity: Identity, message: Data) throws -> Data {
        let signedData = RSG.SignedData(hashType: "sha256",
                                        hash: Hashes.fullHash(message),
                                        meta: [("signer", .bytes(identity.hash)),
                                               ("pubkey", .bytes(identity.getPublicKey()))],
                                        message: message)
        let envelope = signedData.envelope()
        return try identity.sign(envelope) + envelope
    }

    private func validate(_ rsm: Data, with identity: Identity)
    -> (result: RNIDApp.Result, lines: [String]) {
        let output = RNIDCapturingOutput()
        let fileSystem = RNIDMemoryFileSystem(files: ["message.rsm": rsm])
        let operations = RNIDOperations(identity: identity, identityArgument: nil,
                                        options: RNIDApp.Options(), output: output,
                                        fileSystem: fileSystem, transport: nil, editor: nil)
        return (operations.validate(paths: ["message.rsm"]), output.lines)
    }

    func testNonUTF8MessageStillValidatesSuccessfully() throws {
        // The signature covers the raw bytes, so decodability has no bearing on validity.
        let identity = Identity()
        let rsm = try makeSignedMessage(identity, message: badMessage)

        let (result, _) = validate(rsm, with: identity)
        XCTAssertEqual(result, .ok, "a validly-signed message must verify regardless of encoding")
    }

    func testNonUTF8MessageIsRenderedLossilyRatherThanCrashing() throws {
        let identity = Identity()
        let rsm = try makeSignedMessage(identity, message: badMessage)

        let (_, lines) = validate(rsm, with: identity)
        let rendered = try XCTUnwrap(lines.last)

        // The decodable middle survives intact...
        XCTAssertTrue(rendered.contains("invalid utf8"), rendered)
        // ...and each undecodable byte becomes the replacement character, rather than
        // taking the process down the way Python's strict decode does.
        XCTAssertTrue(rendered.contains("\u{FFFD}"), rendered)
    }

    func testValidUTF8MessageIsUnaffected() throws {
        // Guards against "fix" by simply dropping the message: normal text must round-trip.
        let identity = Identity()
        let text = "a perfectly ordinary message"
        let rsm = try makeSignedMessage(identity, message: Data(text.utf8))

        let (result, lines) = validate(rsm, with: identity)
        XCTAssertEqual(result, .ok)
        XCTAssertEqual(lines.last, text)
    }
}
