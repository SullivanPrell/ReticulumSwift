import Foundation

/// Constants and types mirroring `RNS/Utilities/rnid.py` (Reticulum Identity & Encryption Utility).
///
/// `rnid.py` provides identity generation, import/export, signing, and encryption as a CLI
/// tool. These constants and the `Result` error-code enum expose the same named values to
/// Swift callers without requiring the CLI infrastructure.
public enum RNIDApp {

    // MARK: - Application identity

    /// Application name used for RNS destinations.
    /// Python: `APP_NAME = "rns"`.
    public static let appName: String = "rns"

    /// Default destination aspects in dotted notation.
    /// Python: `DEFAULT_ASPECTS = f"{APP_NAME}.id"`.
    public static let defaultAspects: String = "\(appName).id"

    // MARK: - In-band flag bytes

    /// Sentinel used when no message body is provided to a signed-message operation.
    /// Python: `NO_MESSAGE = 0x01`.
    public static let noMessage: UInt8 = 0x01

    /// Sentinel used when no metadata is provided.
    /// Python: `NO_META = 0x02`.
    public static let noMeta: UInt8 = 0x02

    // MARK: - File extensions

    /// Extension for private-key identity files.
    /// Python: `PRV_EXT = "rid"`.
    public static let prvExt: String = "rid"

    /// Extension for public-key identity files.
    /// Python: `PUB_EXT = "pub"`.
    public static let pubExt: String = "pub"

    /// Extension for RSG (Reticulum Signed?) signature files.
    /// Python: `SIG_EXT = "rsg"`.
    public static let sigExt: String = "rsg"

    /// Extension for RSM (Reticulum Signed Message?) files.
    /// Python: `MSG_EXT = "rsm"`.
    public static let msgExt: String = "rsm"

    /// Extension for encrypted files.
    /// Python: `ENCRYPT_EXT = "rfe"`.
    public static let encryptExt: String = "rfe"

    // MARK: - Chunk sizes for streaming encrypt/decrypt

    /// Number of raw bytes per encryption block (1 MiB).
    /// Python: `CHUNK_BLOCKS = 1024*1024`.
    public static let chunkBlocks: Int = 1_048_576

    /// Bytes per encrypted chunk: `chunkBlocks × Identity.aes256BlockSize`.
    /// Python: `ENC_CHUNK = CHUNK_BLOCKS * RNS.Identity.AES256_BLOCKSIZE`.
    public static let encChunk: Int = chunkBlocks * Identity.aes256BlockSize

    /// Bytes per decrypted chunk: `encChunk + Token.tokenOverhead × 2`.
    /// Python: `DEC_CHUNK = ENC_CHUNK + RNS.Cryptography.Token.TOKEN_OVERHEAD*2`.
    public static let decChunk: Int = encChunk + Identity.tokenOverhead * 2

    // MARK: - Hash algorithm names accepted by RSG files

    /// Supported hash algorithm names for RSG creation/verification.
    /// Python: `RSG_HASHTYPES = ["sha256"]`.
    public static let rsgHashTypes: [String] = ["sha256"]

    // MARK: - Result / exit-code enumeration

    /// Exit codes returned by the `rnid` command-line tool.
    /// Mirrors the `R_*` module-level constants in `rnid.py`.
    public enum Result: UInt8, Equatable, CaseIterable {
        /// Success.   Python: `R_OK = 0`.
        case ok                = 0
        /// No signature file found.   Python: `R_NO_SIG_FILE = 1`.
        case noSigFile         = 1
        /// No identity available.     Python: `R_NO_IDENTITY = 2`.
        case noIdentity        = 2
        /// No public key.             Python: `R_NO_PUBKEY = 3`.
        case noPubKey          = 3
        /// No private key.            Python: `R_NO_PRVKEY = 4`.
        case noPrvKey          = 4
        /// No key material at all.    Python: `R_NO_KEYS = 5`.
        case noKeys            = 5
        /// Target file not found.     Python: `R_NO_FILE = 6`.
        case noFile            = 6
        /// File format invalid.       Python: `R_INVALID_FILE = 7`.
        case invalidFile       = 7
        /// Identity data invalid.     Python: `R_INVALID_IDENTITY = 8`.
        case invalidIdentity   = 8
        /// Destination aspects invalid. Python: `R_INVALID_ASPECTS = 9`.
        case invalidAspects    = 9
        /// Signature verification failed. Python: `R_INVALID_SIGNATURE = 10`.
        case invalidSignature  = 10
        /// Output file already exists.  Python: `R_FILE_EXISTS = 11`.
        case fileExists        = 11
        /// Decryption failed.          Python: `R_DECRYPT_FAILED = 12`.
        case decryptFailed     = 12
        /// Invalid argument combination. Python: `R_INVALID_ARGS = 250`.
        case invalidArgs       = 250
        /// Unexpected operation sequence. Python: `R_SEQUENCE_ERROR = 251`.
        case sequenceError     = 251
        /// Failed to read input.       Python: `R_READ_ERROR = 252`.
        case readError         = 252
        /// Failed to write output.     Python: `R_WRITE_ERROR = 253`.
        case writeError        = 253
        /// Unknown error.              Python: `R_UNKNOWN_ERROR = 254`.
        case unknownError      = 254
        /// Operation was interrupted.  Python: `R_INTERRUPTED = 255`.
        case interrupted       = 255
    }
}
