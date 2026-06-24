import Foundation
import CryptoKit

public enum Hashes {
    public static func fullHash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    public static func truncatedHash(_ data: Data) -> Data {
        Data(SHA256.hash(data: data).prefix(Constants.truncatedHashLength))
    }

    public static func sha512(_ data: Data) -> Data {
        Data(SHA512.hash(data: data))
    }

    public static func randomHash() -> Data {
        var bytes = Data(count: Constants.truncatedHashLength)
        bytes.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, Constants.truncatedHashLength, $0.baseAddress!) }
        return Data(SHA256.hash(data: bytes).prefix(Constants.truncatedHashLength))
    }
}
