import Foundation

/// Constants, exit codes and argument parsing for `RNS/Utilities/rnpath.py`
/// — the Reticulum Path Management Utility.
///
/// Python reference: `reference_implementations/reticulum/RNS/Utilities/rnpath.py`
/// (RNS 1.4.0). `rnpath` is a single-shot CLI whose nine modes are selected by a strict
/// `if`/`elif` chain in `program_setup` (rnpath.py:129-477); the order of that chain is
/// user-visible, so it is reproduced exactly by ``RNPathRunner``.
///
/// This namespace holds the pieces that are pure data: the destination names it links to,
/// the two carriage-return "clear the line" strings, the Braille spinner glyphs, the
/// reason-truncation length, and the two subtly-different hash parsers.
public enum RNPathApp {

    // MARK: - Application identity

    /// Executable name. Python: `argparse.ArgumentParser(prog=...)` defaults to `rnpath`.
    public static let appName: String = "rnpath"

    /// App name of the remote-management and blackhole destinations.
    /// Python: `RNS.Destination(remote_identity, OUT, SINGLE, "rnstransport", ...)` (rnpath.py:87-88).
    public static let transportAppName: String = "rnstransport"

    /// Python: `"rnstransport", "remote", "management"` (rnpath.py:87).
    public static let managementAspects: [String] = ["remote", "management"]

    /// Python: `"rnstransport", "info", "blackhole"` (rnpath.py:88).
    public static let blackholeAspects: [String] = ["info", "blackhole"]

    /// Python: `RNS.Destination.hash_from_name_and_identity("rnstransport.remote.management", ...)` (rnpath.py:114).
    public static let managementFullName: String = "rnstransport.remote.management"

    /// Python: `RNS.Destination.hash_from_name_and_identity("rnstransport.info.blackhole", ...)` (rnpath.py:149).
    public static let blackholeFullName: String = "rnstransport.info.blackhole"

    // MARK: - Request paths

    /// Python: `remote_link.request("/path", ...)` (rnpath.py:260, 313).
    public static let pathRequestPath: String = "/path"

    /// Python: `remote_link.request("/list")` (rnpath.py:157).
    public static let blackholeListRequestPath: String = "/list"

    /// Python: `data = ["table", destination_hash, max_hops]` (rnpath.py:260).
    public static let commandTable: String = "table"

    /// Python: `data = ["rates", destination_hash]` (rnpath.py:313).
    public static let commandRates: String = "rates"

    // MARK: - Terminal control strings

    /// Python: `output_rst_str = "\r" + 58 spaces + "\r"` (rnpath.py:42 — verified by regex
    /// over the source: exactly 58 spaces, total length 60).
    ///
    /// Emitted with `end=""` before every remote-progress message, so the previous
    /// unterminated progress line is erased first.
    public static let outputResetString: String = "\r" + String(repeating: " ", count: 58) + "\r"

    /// Python: the *different* inline clear string used by the default path-request branch,
    /// `"\r" + 55 spaces + "\r"` (rnpath.py:465 and rnpath.py:476 — verified: 55, not 58).
    public static let lineClearString: String = "\r" + String(repeating: " ", count: 55) + "\r"

    /// Python: `syms = "⢄⢂⢁⡁⡈⡐⡠"` (rnpath.py:453) — 7 Braille glyphs,
    /// U+2884 U+2882 U+2881 U+2841 U+2848 U+2850 U+2860.
    public static let spinnerSymbols: [Character] = ["\u{2884}", "\u{2882}", "\u{2881}",
                                                    "\u{2841}", "\u{2848}", "\u{2850}", "\u{2860}"]

    // MARK: - Numeric constants

    /// Python: `rmlen = 64` — the blackhole reason truncation length (rnpath.py:178).
    public static let reasonMaxLength: Int = 64

    /// Python: `RNS.Transport.PATH_REQUEST_TIMEOUT` == 15, the default for both `-w` and `-W`.
    public static let defaultTimeout: TimeInterval = Transport.pathRequestTimeout

    /// Python: `dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2` == 32.
    ///
    /// - Important: this must be derived from ``Constants/truncatedHashLength`` (16 **bytes**).
    ///   `Reticulum.truncatedHashLength` and `Identity.truncatedHashLength` are both 128
    ///   (**bits**) and would yield 256 — a trap that silently rejects every valid hash.
    public static let hexHashLength: Int = Constants.truncatedHashLength * 2

    /// Python: `RNS.Transport.PATHFINDER_M` — the hop count `Transport.hops_to()` returns
    /// for an unknown destination (Transport.py:2676-2683). Swift's ``Transport/hopsTo(_:)``
    /// returns `nil` there instead, so callers map `nil` → 128.
    public static let unknownHops: UInt8 = 128

    // MARK: - Exit codes

    /// Every exit code `rnpath` can produce.
    ///
    /// Note that Python collapses several distinct causes onto the same code — a remote
    /// request that timed out, one that was rejected by the ACL, and one that legitimately
    /// returned an empty table all exit 10 with the same message. That is reproduced.
    public enum Result: Int32, Equatable, CaseIterable {
        /// Success; also `--help`, `--version`, the no-mode help gate and Ctrl-C.
        case ok = 0
        /// Every `sys.exit(1)`: malformed destination, "No path known", "Path not found",
        /// a drop that removed nothing, "Error: Invalid path data returned".
        case generalFailure = 1
        /// `argparse` parse errors — unrecognised option, missing value, bad int/float.
        case usageError = 2
        /// Remote link failure, or "The remote request failed…".
        case remoteFailure = 10
        /// "Path request timed out" while waiting for a path to the remote instance (`-W`).
        case remotePathTimeout = 12
        /// Remote setup failure, or any blackhole fetch/apply error.
        case setupFailure = 20
        /// "… on remote instances not yet implemented".
        case notImplemented = 255
    }

    // MARK: - Hash parsing

    /// The two distinct wordings `rnpath` uses for the same validation.
    ///
    /// `parse_hash` (rnpath.py:93-99) says "Hash …" and its callers exit **20**; the
    /// inline copies in the `-t`/`-r`/`-d`/`-x`/default branches say "Destination …" and
    /// exit **1**. Both differences are load-bearing for parity.
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case invalidHashLength
        case invalidHash
        case invalidDestinationLength
        case invalidDestination

        public var message: String {
            switch self {
            case .invalidHashLength:
                // Python: rnpath.py:95
                return "Hash length is invalid, must be \(RNPathApp.hexHashLength) hexadecimal characters (\(Constants.truncatedHashLength) bytes)."
            case .invalidHash:
                // Python: rnpath.py:99
                return "Invalid hash entered. Check your input."
            case .invalidDestinationLength:
                // Python: rnpath.py:247 (and 300, 398, 419, 440 — all identical)
                return "Destination length is invalid, must be \(RNPathApp.hexHashLength) hexadecimal characters (\(Constants.truncatedHashLength) bytes)."
            case .invalidDestination:
                // Python: rnpath.py:249
                return "Invalid destination entered. Check your input."
            }
        }

        public var description: String { message }
    }

    /// Python: `parse_hash(input_str)` (rnpath.py:93-99). Used by `-p`, `-B` and `-U`.
    public static func parseHash(_ input: String) throws -> Data {
        try decodeHash(input, lengthError: .invalidHashLength, contentError: .invalidHash)
    }

    /// The inline variant duplicated in the `-t`, `-r`, `-d`, `-x` and default branches.
    /// Same logic, different wording, different exit code.
    public static func parseDestination(_ input: String) throws -> Data {
        try decodeHash(input, lengthError: .invalidDestinationLength, contentError: .invalidDestination)
    }

    private static func decodeHash(_ input: String,
                                   lengthError: ParseError,
                                   contentError: ParseError) throws -> Data {
        // Python's len() counts code points, not grapheme clusters — use unicodeScalars so a
        // combining mark in argv cannot make a 32-character string look like 31 to Swift.
        guard input.unicodeScalars.count == hexHashLength else { throw lengthError }
        guard isStrictHex(input) else { throw contentError }
        let scalars = Array(input.unicodeScalars)
        var bytes = Data(capacity: scalars.count / 2)
        var index = 0
        while index + 1 < scalars.count {
            guard let high = nibble(scalars[index]), let low = nibble(scalars[index + 1]) else {
                throw contentError
            }
            bytes.append(high << 4 | low)
            index += 2
        }
        return bytes
    }

    /// Whether every character is `[0-9a-fA-F]`.
    ///
    /// The package's internal `Data(hex:)` delegates to `UInt8(_:radix: 16)`, which accepts a
    /// leading `"+"` (`UInt8("+a", radix: 16) == 10`) where Python's `bytes.fromhex` rejects
    /// it. Pre-validating here keeps a malformed argument on the "Invalid …" path instead of
    /// silently producing a different hash.
    public static func isStrictHex(_ input: String) -> Bool {
        guard !input.isEmpty else { return false }
        return input.unicodeScalars.allSatisfy { nibble($0) != nil }
    }

    private static func nibble(_ scalar: Unicode.Scalar) -> UInt8? {
        switch scalar {
        case "0"..."9": return UInt8(scalar.value - 0x30)
        case "a"..."f": return UInt8(scalar.value - 0x61 + 10)
        case "A"..."F": return UInt8(scalar.value - 0x41 + 10)
        default:        return nil
        }
    }

    // MARK: - Help text

    /// The `argparse` help block, verbatim.
    ///
    /// `argparse` wraps to the terminal width (defaulting to 80 when `COLUMNS` is unset) and
    /// its section header changed across Python releases, so this literal is pinned to the
    /// **80-column, Python 3.10–3.12** rendering — captured from the installed `rnpath` under
    /// Python 3.11.3. (Python ≤ 3.9 prints `optional arguments:`; Python ≥ 3.13 renders
    /// value-taking options as `-m, --max hops`.)
    ///
    /// It is a literal rather than generated because ``ArgumentParser/usage`` is not
    /// argparse-shaped — it emits `usage: rnpath [options] …` and pads to a fixed 24 columns.
    /// Parsing still goes through ``ArgumentParser``; only the rendering is hand-pinned.
    public static let helpText: String = """
    usage: rnpath [-h] [--config CONFIG] [--version] [-t] [-m hops] [-r] [-d] [-D]
                  [-x] [-w seconds] [-R hash] [-i path] [-W seconds] [-b] [-B]
                  [-U] [--duration DURATION] [--reason REASON] [-p] [-j] [-v]
                  [destination] [list_filter]

    Reticulum Path Management Utility

    positional arguments:
      destination           hexadecimal hash of the destination
      list_filter           filter for remote blackhole list view

    options:
      -h, --help            show this help message and exit
      --config CONFIG       path to alternative Reticulum config directory
      --version             show program's version number and exit
      -t, --table           show all known paths
      -m hops, --max hops   maximum hops to filter path table by
      -r, --rates           show announce rate info
      -d, --drop            remove the path to a destination
      -D, --drop-announces  drop all queued announces
      -x, --drop-via        drop all paths via specified transport instance
      -w seconds            timeout before giving up
      -R hash               transport identity hash of remote instance to manage
      -i path               path to identity used for remote management
      -W seconds            timeout before giving up on remote queries
      -b, --blackholed      list blackholed identities
      -B, --blackhole       blackhole identity
      -U, --unblackhole     unblackhole identity
      --duration DURATION   duration of blackhole enforcement in hours
      --reason REASON       reason for blackholing identity
      -p, --blackholed-list
                            view published blackhole list for remote transport
                            instance
      -j, --json            output in JSON format
      -v, --verbose
    """

    /// `rnpath {version}`, printed by `--version`.
    ///
    /// Python uses `RNS._version.__version__`, so this tracks
    /// ``Reticulum/rnsProtocolVersion`` (the RNS protocol release, "1.4.0") and **not**
    /// `Reticulum.version` (the Swift package version). `Sources/rnsd/main.swift` uses the
    /// latter for its own `--version`; that is not the behaviour to copy here.
    public static var versionString: String { "\(appName) \(Reticulum.rnsProtocolVersion)" }
}
