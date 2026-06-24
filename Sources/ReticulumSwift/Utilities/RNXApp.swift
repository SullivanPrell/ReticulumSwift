import Foundation

/// Constants mirroring `RNS/Utilities/rnx.py` (Reticulum Remote Execute Utility).
///
/// `rnx.py` allows running commands on a remote host over authenticated RNS links.
/// These named constants expose the application-name used for RNS destinations, enabling
/// Swift applications to interoperate with `rnx` listen endpoints.
public enum RNXApp {

    /// Application name used for RNS destinations.
    /// Python: `APP_NAME = "rnx"`.
    public static let appName: String = "rnx"

    /// Response code returned when a fetch request is not allowed.
    /// Python: FETCH_NOT_ALLOWED = 0xF0
    public static let reqFetchNotAllowed: UInt8 = 0xF0
}
