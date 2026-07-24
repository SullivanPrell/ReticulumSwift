import XCTest
@testable import ReticulumSwift

final class ZZTempUTF8Probe: XCTestCase {
    func testNonUTF8EmbeddedMessage() throws {
        let identity = Identity()
        let bad = Data([0xFF, 0xFE, 0xFD]) + Data(" invalid utf8 ".utf8) + Data([0x80])

        let signedData = RSG.SignedData(hashType: "sha256",
                                        hash: Hashes.fullHash(bad),
                                        meta: [("signer", .bytes(identity.hash)),
                                               ("pubkey", .bytes(identity.getPublicKey()))],
                                        message: bad)
        let envelope = signedData.envelope()
        let rsm = try identity.sign(envelope) + envelope

        let output = RNIDCapturingOutput()
        let fileSystem = RNIDMemoryFileSystem(files: ["bad.rsm": rsm])
        let operations = RNIDOperations(identity: identity, identityArgument: nil,
                                        options: RNIDApp.Options(), output: output,
                                        fileSystem: fileSystem, transport: nil, editor: nil)

        let result = operations.validate(paths: ["bad.rsm"])
        print("PROBE-RESULT: \(result)")
        for line in output.lines { print("PROBE-LINE: \(Array(line.utf8))") }
        for line in output.lines { print("PROBE-TEXT: \(line)") }
    }
}
