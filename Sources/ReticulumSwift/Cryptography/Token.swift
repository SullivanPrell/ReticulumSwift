import Foundation

/// A trimmed Fernet-spec token: AES-CBC + PKCS7 + HMAC-SHA256, with the
/// Fernet version byte and 8-byte timestamp stripped (Reticulum doesn't
/// need them, and stripping them avoids leaking initiator metadata).
///
/// Wire format:
///   [16-byte IV] [ciphertext] [32-byte HMAC-SHA256(signing_key, IV||ciphertext)]
///
/// Key length determines the AES variant:
///   * 32 bytes -> 16-byte signing key + 16-byte AES-128 encryption key
///   * 64 bytes -> 32-byte signing key + 32-byte AES-256 encryption key
public struct Token {
    public enum Mode: Equatable { case aes128cbc, aes256cbc }
    public enum TokenError: Error {
        case invalidKeyLength
        case invalidTokenLength
        case hmacInvalid
        case decryptionFailed(underlying: Error)
    }

    public let mode: Mode
    public let signingKey: Data
    public let encryptionKey: Data

    public init(key: Data) throws {
        switch key.count {
        case 32:
            self.mode = .aes128cbc
            self.signingKey = key.prefix(16)
            self.encryptionKey = key.suffix(16)
        case 64:
            self.mode = .aes256cbc
            self.signingKey = key.prefix(32)
            self.encryptionKey = key.suffix(32)
        default:
            throw TokenError.invalidKeyLength
        }
    }

    public func encrypt(_ plaintext: Data, iv overrideIV: Data? = nil) throws -> Data {
        let iv = overrideIV ?? Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        let padded = PKCS7.pad(plaintext)
        let ciphertext = try AESCBC.encrypt(plaintext: padded, key: encryptionKey, iv: iv)
        var signedParts = Data()
        signedParts.append(iv)
        signedParts.append(ciphertext)
        let mac = HMACSHA256.authenticate(signedParts, key: signingKey)
        var token = signedParts
        token.append(mac)
        return token
    }

    /// Generate a fresh random 64-byte symmetric key suitable for use with `Token`.
    /// Mirrors Python's `Token.generate_key()`.
    public static func generateKey() -> Data {
        var key = Data(count: 64)
        _ = key.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 64, $0.baseAddress!)
        }
        return key
    }

    public func decrypt(_ token: Data) throws -> Data {
        guard token.count > 48 else { throw TokenError.invalidTokenLength }
        let mac = token.suffix(32)
        let signed = token.prefix(token.count - 32)
        guard HMACSHA256.verify(signed, key: signingKey, expected: mac) else {
            throw TokenError.hmacInvalid
        }
        let iv = signed.prefix(16)
        let ciphertext = signed.suffix(signed.count - 16)
        do {
            let padded = try AESCBC.decrypt(ciphertext: ciphertext, key: encryptionKey, iv: iv)
            return try PKCS7.unpad(padded)
        } catch {
            throw TokenError.decryptionFailed(underlying: error)
        }
    }
}
