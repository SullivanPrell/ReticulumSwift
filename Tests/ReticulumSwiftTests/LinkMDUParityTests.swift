import XCTest
@testable import ReticulumSwift

/// Tests verifying Link MDU matches Python's formula.
/// Python: Link.MDU = floor((MTU - IFAC_MIN_SIZE - HEADER_MINSIZE - TOKEN_OVERHEAD) / AES128_BLOCKSIZE) * AES128_BLOCKSIZE - 1
///       = floor((500 - 1 - 19 - 48) / 16) * 16 - 1 = 431
final class LinkMDUParityTests: XCTestCase {

    func testLinkEncryptedMDU() {
        // Python: Link.MDU = floor((500 - 1 - 19 - 48) / 16) * 16 - 1 = 431
        XCTAssertEqual(Link.encryptedMdu, 431,
            "Link.encryptedMdu must be 431 to match Python's Link.MDU")
    }

    func testLinkMTUConstant() {
        // Python: Link.MDU is derived from MTU=500. The Link.mtu static is MDU=464 (plain).
        // encryptedMdu is what actually limits link packet payload.
        XCTAssertLessThan(Link.encryptedMdu, Link.mtu,
            "encrypted MDU must be less than plain MDU")
    }

    func testLinkMDUFormula() {
        // Manual computation: floor((500 - 1 - 19 - 48) / 16) * 16 - 1
        let mtu = Constants.mtu          // 500
        let ifacMin = Constants.ifacMinSize  // 1
        let headerMin = Constants.headerMinSize  // 19
        let tokenOverhead = Constants.tokenOverhead  // 48
        let blockSize = Constants.aes128BlockSize  // 16

        let expected = (mtu - ifacMin - headerMin - tokenOverhead) / blockSize * blockSize - 1
        XCTAssertEqual(Link.encryptedMdu, expected)
        XCTAssertEqual(Link.encryptedMdu, 431)
    }
}
