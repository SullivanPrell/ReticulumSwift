import Foundation

/// PKCS#7 padding for AES-CBC. Block size is 16 bytes; pad value equals the
/// number of pad bytes appended.
public enum PKCS7 {
    public static let blockSize: Int = 16

    public static func pad(_ data: Data, blockSize: Int = blockSize) -> Data {
        let padLength = blockSize - (data.count % blockSize)
        return data + Data(repeating: UInt8(padLength), count: padLength)
    }

    public enum UnpadError: Error { case invalidPadding }

    public static func unpad(_ data: Data, blockSize: Int = blockSize) throws -> Data {
        guard !data.isEmpty, data.count % blockSize == 0 else {
            throw UnpadError.invalidPadding
        }
        let padLength = Int(data[data.count - 1])
        guard padLength > 0, padLength <= blockSize, padLength <= data.count else {
            throw UnpadError.invalidPadding
        }
        // Verify all pad bytes equal padLength
        for byte in data.suffix(padLength) where byte != UInt8(padLength) {
            throw UnpadError.invalidPadding
        }
        return data.prefix(data.count - padLength)
    }
}
