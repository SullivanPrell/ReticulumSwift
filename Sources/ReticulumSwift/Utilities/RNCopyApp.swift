import Foundation

/// Constants mirroring `RNS/Utilities/rncp.py` (Reticulum Copy Utility).
///
/// `rncp.py` implements authenticated file transfer over RNS using the Resource API.
/// These named constants are exposed for use by Swift applications that implement
/// compatible file-transfer endpoints.
public enum RNCopyApp {

    /// Application name used for RNS destinations.
    /// Python: `APP_NAME = "rncp"`.
    public static let appName: String = "rncp"

    /// Response code returned when a fetch request is not authorised.
    /// Python: `REQ_FETCH_NOT_ALLOWED = 0xF0`.
    public static let reqFetchNotAllowed: UInt8 = 0xF0
}
