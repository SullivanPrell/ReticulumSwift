import Foundation
import CryptoKit

public enum HMACSHA256 {
    public static func authenticate(_ data: Data, key: Data) -> Data {
        let symmetric = SymmetricKey(data: key)
        let mac = CryptoKit.HMAC<SHA256>.authenticationCode(for: data, using: symmetric)
        return Data(mac)
    }

    public static func verify(_ data: Data, key: Data, expected: Data) -> Bool {
        let computed = authenticate(data, key: key)
        return constantTimeEquals(computed, expected)
    }

    /// Constant-time byte comparison. Avoids timing-channel leaks during
    /// HMAC verification.
    public static func constantTimeEquals(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<a.count { diff |= a[a.startIndex + i] ^ b[b.startIndex + i] }
        return diff == 0
    }
}
