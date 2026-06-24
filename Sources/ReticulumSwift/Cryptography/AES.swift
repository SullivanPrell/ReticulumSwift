import Foundation
import CommonCrypto

/// AES-CBC primitives. CryptoKit doesn't expose CBC mode, so we use
/// CommonCrypto. Reticulum uses AES-128-CBC for 32-byte token keys and
/// AES-256-CBC for 64-byte token keys; the key length determines the
/// algorithm.
public enum AESCBCError: Error {
    case invalidKeyLength
    case invalidIVLength
    case ccCryptError(status: Int32)
}

public enum AESCBC {
    public static func encrypt(plaintext: Data, key: Data, iv: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCEncrypt), input: plaintext, key: key, iv: iv)
    }

    public static func decrypt(ciphertext: Data, key: Data, iv: Data) throws -> Data {
        try crypt(operation: CCOperation(kCCDecrypt), input: ciphertext, key: key, iv: iv)
    }

    private static func crypt(operation: CCOperation, input: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 || key.count == kCCKeySizeAES256 else {
            throw AESCBCError.invalidKeyLength
        }
        guard iv.count == kCCBlockSizeAES128 else { throw AESCBCError.invalidIVLength }

        let outputLength = input.count + kCCBlockSizeAES128
        var output = Data(count: outputLength)
        var bytesWritten = 0

        let status = output.withUnsafeMutableBytes { outputBytes -> CCCryptorStatus in
            input.withUnsafeBytes { inputBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0), // No padding — caller does PKCS7
                            keyBytes.baseAddress, key.count,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress, input.count,
                            outputBytes.baseAddress, outputLength,
                            &bytesWritten
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else { throw AESCBCError.ccCryptError(status: status) }
        return output.prefix(bytesWritten)
    }
}
