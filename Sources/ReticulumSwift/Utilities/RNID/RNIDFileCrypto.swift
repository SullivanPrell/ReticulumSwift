import Foundation

/// Chunked file encryption and decryption — the `.rfe` format.
///
/// Python reference: `encrypt` (rnid.py:847-888) and `decrypt` (rnid.py:890-939).
///
/// The on-disk `.rfe` format is a **bare concatenation of independently-encrypted Identity
/// tokens**: no header, no length prefix, no framing. Each token is
/// `[32-byte ephemeral X25519 public key][16-byte IV][AES-256-CBC ciphertext of PKCS7(chunk)][32-byte HMAC-SHA256]`.
///
/// Decryption re-aligns only because a full `ENC_CHUNK` plaintext encrypts to exactly
/// `DEC_CHUNK` bytes:
///
/// ```
/// 32 (ephemeral pub) + 16 (IV) + (ENC_CHUNK + 16 PKCS7 block) + 32 (HMAC)
///   = ENC_CHUNK + 96 = DEC_CHUNK
/// ```
///
/// PKCS7 appends a **full** 16-byte block when the input is already block-aligned, and
/// `ENC_CHUNK` is, which is what makes the arithmetic work out. If `Identity.encrypt`'s
/// ephemeral-key prefix, the `Token` layout or the padding scheme ever changes, every
/// previously-written `.rfe` becomes silently undecryptable — ``encryptedChunkSize(plaintextChunk:)``
/// exists as the regression guard for that.
public enum RNIDFileCrypto {

    /// Python has no equivalent: `identity.decrypt` swallows every exception and returns
    /// `None`, which `rnid` tests with `if not decrypted`.
    public enum CryptoError: Error, Equatable {
        /// Maps to ``RNIDApp/Result/decryptFailed`` (exit 12).
        case decryptFailed
        case missingPrivateKey
        /// Unreachable in Swift — every `Identity` holds a public key.
        case missingPublicKey
    }

    /// The encrypted size of an `n`-byte plaintext chunk.
    ///
    /// `32 (ephemeral pub) + 16 (IV) + padded(n) + 32 (HMAC)`, where
    /// `padded(n) = n + (16 - n % 16)` — always at least one full pad block.
    public static func encryptedChunkSize(plaintextChunk n: Int) -> Int {
        let padded = n + (PKCS7.blockSize - n % PKCS7.blockSize)
        return Constants.halfKeySize + 16 + padded + 32
    }

    /// Python: the `encrypt` loop (rnid.py:874-883).
    ///
    /// `onProgress` fires on **every** iteration including the terminating one, because
    /// Python's progress `print` sits *outside* the `if chunk` block — so an empty input file
    /// still produces exactly one `"Wrote 0 B"` line and a zero-byte output.
    @discardableResult
    public static func encryptStream(
        identity: Identity,
        reader: RNIDByteReader,
        writer: RNIDByteWriter,
        onProgress: ((Int) -> Void)? = nil
    ) throws -> Int {
        var wrote = 0
        var dataRemaining = true
        while dataRemaining {
            let chunk = try reader.read(upTo: RNIDApp.encChunk)
            if !chunk.isEmpty {
                wrote += try writer.write(try identity.encrypt(chunk))
            } else {
                dataRemaining = false
            }
            onProgress?(wrote)
        }
        return wrote
    }

    /// Python: the `decrypt` loop (rnid.py:925-935).
    ///
    /// `onProgress` fires only **inside** the `if chunk` branch — the exact opposite of
    /// encrypt — so an empty `.rfe` prints nothing at all.
    ///
    /// Every failure from `Identity.decrypt` / `Token` / `PKCS7` becomes
    /// ``CryptoError/decryptFailed``, matching Python's `if not decrypted:` test which cannot
    /// distinguish causes.
    @discardableResult
    public static func decryptStream(
        identity: Identity,
        reader: RNIDByteReader,
        writer: RNIDByteWriter,
        onProgress: ((Int) -> Void)? = nil
    ) throws -> Int {
        guard identity.hasPrivateKey else { throw CryptoError.missingPrivateKey }
        var wrote = 0
        var dataRemaining = true
        while dataRemaining {
            let chunk = try reader.read(upTo: RNIDApp.decChunk)
            if !chunk.isEmpty {
                let decrypted: Data
                do {
                    decrypted = try identity.decrypt(chunk)
                } catch {
                    throw CryptoError.decryptFailed
                }
                wrote += try writer.write(decrypted)
                onProgress?(wrote)
            } else {
                dataRemaining = false
            }
        }
        return wrote
    }
}
