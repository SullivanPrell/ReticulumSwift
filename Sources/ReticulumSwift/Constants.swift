import Foundation

/// Protocol-level constants. Values mirror `RNS.Reticulum` and `RNS.Identity`
/// in the Python reference. Changing these breaks wire compatibility.
public enum Constants {
    public static let mtu: Int = 500
    public static let truncatedHashLengthBits: Int = 128
    public static let truncatedHashLength: Int = truncatedHashLengthBits / 8 // 16
    /// Minimum header size for type1 (single dest hash) packets.
    /// Mirrors Python's `Reticulum.HEADER_MINSIZE = 2 + 1 + TRUNCATED_HASHLENGTH//8 = 19`.
    /// Layout: flags(1) + hops(1) + destHash(16) + context(1) = 19
    public static let headerMinSize: Int = 2 + 1 + truncatedHashLength       // 19
    public static let headerMaxSize: Int = 2 + 1 + truncatedHashLength * 2   // 35
    public static let ifacMinSize: Int = 1
    public static let mdu: Int = mtu - headerMaxSize - ifacMinSize           // 464

    public static let keySizeBits: Int = 256 * 2                              // 512 — concat X25519 + Ed25519 pub
    public static let keySize: Int = keySizeBits / 8                          // 64
    public static let halfKeySize: Int = keySize / 2                          // 32
    public static let signatureLength: Int = keySize                          // 64
    public static let hashLength: Int = 32                                    // SHA256
    /// Alias used by PacketReceipt (full SHA-256 output).
    public static let fullHashLength: Int = 32
    public static let nameHashLengthBits: Int = 80
    public static let nameHashLength: Int = nameHashLengthBits / 8            // 10
    public static let randomHashLength: Int = 10                              // 5 random + 5 timestamp
    public static let ratchetSize: Int = 32

    public static let aes128BlockSize: Int = 16
    public static let tokenOverhead: Int = 48                                 // IV(16) + HMAC(32)
    public static let derivedKeyLength: Int = 64                              // 512 bits — split for Token

    /// Maximum data unit for an encrypted (SINGLE) packet payload.
    /// Mirrors Python `Packet.ENCRYPTED_MDU = 383`.
    /// Formula: floor((MDU - TOKEN_OVERHEAD - ECPUBSIZE) / AES128_BLOCKSIZE) * AES128_BLOCKSIZE - 1
    ///   = floor((464 - 48 - 32) / 16) * 16 - 1 = 383
    public static let encryptedMdu: Int = (mdu - tokenOverhead - halfKeySize) / aes128BlockSize * aes128BlockSize - 1

    /// Maximum data unit for an unencrypted (PLAIN) packet payload.
    /// Mirrors Python `Packet.PLAIN_MDU = MDU = 464`.
    public static let plainMdu: Int = mdu

    /// Maximum data unit for a Link (session-encrypted) packet.
    /// Different from `encryptedMdu` because link packets don't have the ephemeral public key.
    /// Mirrors Python `Link.MDU`:
    ///   floor((MTU - IFAC_MIN_SIZE - HEADER_MINSIZE - TOKEN_OVERHEAD) / AES128_BLOCKSIZE) * AES128_BLOCKSIZE - 1
    ///   = floor((500 - 1 - 19 - 48) / 16) * 16 - 1 = 431
    public static let linkMdu: Int = (mtu - ifacMinSize - headerMinSize - tokenOverhead) / aes128BlockSize * aes128BlockSize - 1

    /// Default per-hop timeout in seconds. Mirrors Python `Reticulum.DEFAULT_PER_HOP_TIMEOUT`.
    public static let defaultPerHopTimeout: TimeInterval = 6.0

    // IFAC — Interface Access Codes
    /// Default IFAC signature-tail size used when not overridden per-interface.
    public static let defaultIfacSize: Int = 16
    /// HKDF salt for deriving the IFAC key from networkname / networkkey.
    /// Matches Python `RNS.Reticulum.IFAC_SALT`.
    public static let ifacSalt = Data(
        [0xad,0xf5,0x4d,0x88,0x2c,0x9a,0x9b,0x80,
         0x77,0x1e,0xb4,0x99,0x5d,0x70,0x2d,0x4a,
         0x3e,0x73,0x33,0x91,0xb2,0xa0,0xf5,0x3f,
         0x41,0x6d,0x9f,0x90,0x7e,0x55,0xcf,0xf8]
    )
}
