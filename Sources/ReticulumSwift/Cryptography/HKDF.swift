import Foundation
import CryptoKit

/// HKDF-SHA256 in the exact byte-for-byte form used by `RNS.Cryptography.hkdf`:
///
///   PRK   = HMAC-SHA256(salt, IKM)
///   T(0)  = empty
///   T(i)  = HMAC-SHA256(PRK, T(i-1) || info || byte((i+1) mod 256))
///   OKM   = T(1) || T(2) || ... truncated to `length`
///
/// This matches RFC 5869 for any output length up to 8192 bytes (256 blocks);
/// Reticulum never asks for more.
public enum HKDF {
    public static func derive(
        length: Int,
        derivedFrom ikm: Data,
        salt: Data? = nil,
        context: Data? = nil
    ) -> Data {
        precondition(length > 0, "HKDF length must be positive")

        let usedSalt: Data = (salt?.isEmpty == false) ? salt! : Data(repeating: 0, count: 32)
        let info: Data = context ?? Data()

        let prk = HMACSHA256.authenticate(ikm, key: usedSalt)

        var derived = Data()
        var block = Data()
        let blocksNeeded = Int((Double(length) / 32.0).rounded(.up))
        for i in 0..<blocksNeeded {
            var input = Data()
            input.append(block)
            input.append(info)
            input.append(UInt8((i + 1) % 256))
            block = HMACSHA256.authenticate(input, key: prk)
            derived.append(block)
        }
        return derived.prefix(length)
    }
}
