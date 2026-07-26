import Foundation

/// Constants and exit codes belonging to `rnx` — the Reticulum Remote Execution Utility.
///
/// Python reference: `RNS/Utilities/rnx.py`.
///
/// These live in their own file (rather than in ``RNXApp``'s declaration) so the port
/// adds to the shared utility surface without rewriting it.
public extension RNXApp {

    /// Destination aspect for the listener endpoint.
    /// Python: `RNS.Destination(identity, IN, SINGLE, APP_NAME, "execute")` — rnx.py:70.
    static let aspect: String = "execute"

    /// Request path the listener registers a handler on.
    /// Python: `register_request_handler(path = "command", ...)` — rnx.py:120.
    static let requestPath: String = "command"

    /// File name of the utility's own identity inside `<configdir>/storage/identities`.
    /// Python: `identity_path = RNS.Reticulum.identitypath+"/"+APP_NAME` — rnx.py:53.
    static let identityFileName: String = "rnx"

    /// File name searched for the listener's allow-list.
    /// Python: `allowed_file_name = "allowed_identities"` — rnx.py:95.
    static let allowedIdentitiesFileName: String = "allowed_identities"

    /// Directories searched, in order, for ``allowedIdentitiesFileName``.
    /// Python: rnx.py:97-102 — each goes through `os.path.expanduser`, first hit wins.
    static let allowedIdentitiesSearchPaths: [String] = ["/etc/rnx", "~/.config/rnx", "~/.rnx"]

    /// Extra seconds added to the request timeout to cover remote scheduling overhead.
    /// Python: `remote_exec_grace = 2.0` — rnx.py:325.
    static let remoteExecGrace: TimeInterval = 2.0

    /// RTT multiplier used when deriving the request timeout.
    /// Python: `rexec_timeout = timeout+link.rtt*4+remote_exec_grace` — rnx.py:388.
    /// Note this is **4**, not `Link.trafficTimeoutFactor` (6).
    static let rexecRttFactor: Double = 4.0

    /// Number of hex characters in a destination / identity hash argument.
    /// Python: `(RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2` — rnx.py:83, 330.
    static let destinationHexLength: Int = 32

    /// Lowest log level a `-q` run can reach.
    /// Python clamps the requested level to `LOG_CRITICAL` — Reticulum.py:302.
    /// `-qqqq` therefore yields 0, and can never reach `LOG_NONE` (-1).
    static let minLogLevel: Int = 0

    /// Highest log level a `-v` run can reach.
    /// Python clamps the requested level to `LOG_EXTREME` — Reticulum.py:301.
    static let maxLogLevel: Int = 8

    /// Braille spinner frames, advanced every 100 ms.
    /// Python: `syms = "⢄⢂⢁⡁⡈⡐⡠"` — rnx.py:256, 280.
    static let spinnerSymbols: [Character] = ["\u{2884}", "\u{2882}", "\u{2881}",
                                              "\u{2841}", "\u{2848}", "\u{2850}", "\u{2860}"]

    /// Width of the blank field `spin_stat` writes before each status line.
    /// Python: the literal run of spaces at rnx.py:289 and rnx.py:294 — exactly 82.
    static let statClearWidth: Int = 82

    /// Process exit codes. Python calls `exit(<int>)` directly at each site.
    ///
    /// Note the collision Python itself has: 244 is used both for "link was closed"
    /// (rnx.py:407) and for "request receipt FAILED" (rnx.py:414). Reproduced as-is.
    enum Result: UInt8, Equatable, CaseIterable {
        /// Success — also `--version`, `--help`, `-p`, interactive `exit`/`quit`, EOF, SIGINT.
        case ok = 0
        /// Listener argument error: bad `-a` value or unreadable allow-list file. rnx.py:93,111.
        case argumentError = 1
        /// argparse usage error (unknown option, missing value, bad numeric conversion).
        case usageError = 2
        /// `-m` requested but the remote return code was nil. rnx.py:543.
        case mirrorNoReturnCode = 240
        /// The destination argument was not 32 hex characters. rnx.py:339.
        case invalidDestination = 241
        /// No path to the listener within `-w` seconds. rnx.py:352.
        case pathNotFound = 242
        /// The link could not be established within `-w` seconds. rnx.py:370.
        case linkFailed = 243
        /// The link closed, or the request failed, while sending. rnx.py:407, 414.
        case requestFailed = 244
        /// No result was received. rnx.py:427.
        case noResult = 245
        /// Receiving the result failed. rnx.py:439.
        case receiveFailed = 246
        /// The 8-element response could not be destructured. rnx.py:457.
        case invalidResult = 247
        /// The remote reported `executed == False`. rnx.py:524.
        case remoteExecFailed = 248
        /// `receipt.response` was nil. rnx.py:530.
        case noResponse = 249
    }
}

// MARK: - Hex helpers

/// Hex decoding used by the rnx allow-list and destination parsing.
///
/// Kept rnx-local (rather than a `Data(hexString:)` extension) so the port adds no
/// shared surface that could collide with a sibling utility.
enum RNXHex {
    /// Python: `bytes.fromhex(s)` — accepts upper and lower case, rejects anything else.
    /// Unlike CPython, an odd-length string is rejected rather than raising a
    /// differently-worded error.
    static func decode(_ hex: String) -> Data? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        var index = 0
        while index < chars.count {
            guard let high = nibble(chars[index]), let low = nibble(chars[index + 1]) else { return nil }
            out.append(high << 4 | low)
            index += 2
        }
        return out
    }

    private static func nibble(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30           // 0-9
        case 0x61...0x66: return byte - 0x61 + 10      // a-f
        case 0x41...0x46: return byte - 0x41 + 10      // A-F
        default:          return nil
        }
    }
}
