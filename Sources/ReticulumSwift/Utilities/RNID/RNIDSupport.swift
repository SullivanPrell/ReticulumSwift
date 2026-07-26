import Foundation

// Additions to `RNIDApp` (Sources/ReticulumSwift/Utilities/RNIDApp.swift) needed by the
// `rnid` port. The constants already in that file are deliberately not repeated here.
//
// Python reference: RNS/Utilities/rnid.py

// MARK: - Result as an Error

/// Lets ``RNIDApp/Result`` be the failure type of a `Swift.Result`, so the resolver and the
/// operation layer can propagate Python's `exit(R_*)` codes without a parallel error enum.
/// Declared here rather than in `RNIDApp.swift` to keep that file untouched.
extension RNIDApp.Result: Error {}

// MARK: - Output format

public extension RNIDApp {

    /// The five values `create_rsg`'s `output` parameter accepts.
    /// Python: `if not output in ["bin", "hex", "base32", "base256", "base64"]` (rnid.py:489).
    enum OutputFormat: String, Equatable, CaseIterable {
        case bin
        case hex
        case base32
        case base256
        case base64

        /// Whether this format produces armoured text printed to stdout rather than a file.
        /// Python: `elif output in ["base32", "base64", "base256", "hex"]` (rnid.py:780, :835).
        public var isText: Bool { self != .bin }
    }

    /// The encoding flag ladder shared by `sign`, `sign_message`, `-p`, `-x` and `-X`.
    /// Python: `if args.base32 … elif args.base64 … elif args.base256 … elif args.hex … else "bin"`
    /// (rnid.py:758-762, :792-796).
    static func outputFormat(base32: Bool, base64: Bool, base256: Bool, hex: Bool) -> OutputFormat {
        if base32 { return .base32 }
        if base64 { return .base64 }
        if base256 { return .base256 }
        if hex { return .hex }
        return .bin
    }
}

// MARK: - ASCII armour constants

public extension RNIDApp {
    /// Python: `RSG_ASCII_HEADER = b"#### Start of rsg data "` (rnid.py:518).
    static let rsgAsciiHeader: String = "#### Start of rsg data "
    /// Python: `RSG_ASCII_FOOTER = b" End of rsg data ####"` (rnid.py:519).
    static let rsgAsciiFooter: String = " End of rsg data ####"
    /// Python: `RSG_ASCII_ROW_WIDTH = 64` (rnid.py:520).
    static let rsgAsciiRowWidth: Int = 64
    /// Python: `RSG_PADDING = b"="` (rnid.py:521).
    static let rsgPadding: Character = "="
}

// MARK: - Aspect splitting

public extension RNIDApp {

    /// Split a dotted destination name the way Python's `str.split(".")` does — **preserving
    /// empty components**.
    ///
    /// This is deliberately *not* ``Destination/appAndAspects(fromFullName:)``, which uses
    /// `split(separator:)` with the default `omittingEmptySubsequences: true` and therefore
    /// collapses `"rns."` to `["rns"]` and `"a..b"` to `["a","b"]`. Python yields
    /// `['rns','']` and `['a','','b']`, and both the `-a` `len(aspects) > 1` gate
    /// (rnid.py:380) and the resulting name hash depend on the difference.
    static func splitAspects(_ dotted: String) -> [String] {
        dotted.components(separatedBy: ".")
    }
}

// MARK: - Destination hashing from a raw identity hash

/// Destination-hash helpers that accept a raw 16-byte identity hash.
///
/// Python's `Destination.hash(identity, app_name, *aspects)` explicitly accepts *either* an
/// `RNS.Identity` *or* raw bytes of `TRUNCATED_HASHLENGTH//8` length
/// (RNS/Destination.py:115-129), and `rnid` uses the bytes form twice: for the identity
/// destination hash on the `-R` path-request path (rnid.py:250) and in
/// `print_hash_information` (rnid.py:1007). Swift's `Destination.hash(identity:appName:aspects:)`
/// only takes an `Identity?`, so these live here rather than forcing a shared-file change.
public enum RNIDDestinationHash {

    /// Python: `Destination.hash(identity_bytes, app_name, *aspects)`.
    /// Returns `nil` where Python raises `TypeError("Invalid material supplied for
    /// destination hash calculation")`, i.e. when the hash is not exactly 16 bytes.
    public static func hash(identityHash: Data, appName: String, aspects: [String]) -> Data? {
        guard identityHash.count == Constants.truncatedHashLength else { return nil }
        let nameHash = Destination.computeNameHash(appName: appName, aspects: aspects)
        return Hashes.truncatedHash(nameHash + identityHash)
    }

    /// Python: `Destination.hash_from_name_and_identity(full_name, identity_bytes)`.
    ///
    /// The split uses Python semantics (empty components preserved) — see
    /// ``RNIDApp/splitAspects(_:)``.
    public static func hash(fromFullName fullName: String, identityHash: Data) -> Data? {
        let components = RNIDApp.splitAspects(fullName)
        guard let appName = components.first else { return nil }
        return hash(identityHash: identityHash, appName: appName, aspects: Array(components.dropFirst()))
    }
}

// MARK: - Options

public extension RNIDApp {

    /// The subset of parsed command-line state the operation layer needs.
    ///
    /// Everything here maps 1:1 onto an `argparse` destination in `rnid.py`; the executable
    /// target fills it in and the library never reads `CommandLine`.
    struct Options {
        /// Python: derived from `-B`/`-b`/`-U`/`-F` (rnid.py:758-762).
        public var outputFormat: RNIDApp.OutputFormat = .bin
        /// Python: `-f`/`--force`.
        public var force: Bool = false
        /// Python: `--raw`. Only consulted by `-s`.
        public var raw: Bool = false
        /// Python: `-w`/`--write`.
        public var write: String? = nil
        /// Python: `-r`/`--read`. Only consulted by `-S`.
        public var read: String? = nil
        /// Python: `--meta`.
        public var showMeta: Bool = false
        /// Python: `-P`/`--print-private`.
        public var printPrivate: Bool = false
        /// Python: `-E`/`--embed-meta <path>`.
        public var embedMeta: String? = nil
        /// Python: a bare `-E` (const `NO_META`, the int 2). `os.path.expanduser(2)` raises
        /// an *uncaught* `TypeError` in Python; this port reports ``Result/invalidArgs``.
        public var embedMetaWithoutPath: Bool = false
        /// Python: `--meta-spec <path>`. Used raw — Python never expands it (rnid.py:813).
        public var metaSpec: String? = nil
        /// Python: `-t <seconds>`, defaulting to `RNS.Transport.PATH_REQUEST_TIMEOUT`.
        public var timeout: TimeInterval = Transport.pathRequestTimeout

        public init() {}
    }
}

// MARK: - Argument validation

public extension RNIDApp {

    /// The three mutual-exclusion checks `validate_args` performs before any work.
    ///
    /// Python: rnid.py:86-102. All three use a **raw `exit(1)`**, not ``Result/invalidArgs``
    /// (250) — reproduce that in the executable.
    ///
    /// Note the empty-list subtlety: `-e`/`-d`/`-V`/`-s` are `nargs="*"`, so a bare `-e`
    /// yields `[]`, which is falsy in Python and therefore contributes **zero** to the
    /// operation tally (and is skipped entirely by `main`). Pass `[]` for that case, not `nil`.
    enum ArgumentValidation: Equatable {
        case ok
        /// The message Python prints immediately before `exit(1)`.
        case failed(String)
    }

    /// Python: `validate_args(args)` (rnid.py:86-102).
    static func validateArguments(
        encrypt: [String]?,
        decrypt: [String]?,
        validate: [String]?,
        sign: [String]?,
        signMessage: String?,
        signMessageProvided: Bool,
        importPublic: String?,
        importPrivate: String?,
        identity: String?,
        generate: String?,
        base64: Bool,
        base32: Bool,
        base256: Bool,
        hex: Bool
    ) -> ArgumentValidation {

        // Python truthiness: a non-nil but EMPTY list or string is falsy.
        func truthy(_ list: [String]?) -> Bool { !(list ?? []).isEmpty }
        func truthy(_ text: String?) -> Bool { !(text ?? "").isEmpty }
        // `-S` stores either the int NO_MESSAGE (always truthy) or the supplied text.
        let signMessageTruthy = signMessageProvided && (signMessage == nil || !(signMessage!.isEmpty))

        var ops = 0
        for present in [truthy(encrypt), truthy(decrypt), truthy(validate), truthy(sign), signMessageTruthy]
        where present { ops += 1 }
        if ops > 1 {
            // Python: rnid.py:90.
            return .failed("This utility currently only supports one of the encrypt, decrypt, sign or verify operations per invocation")
        }

        var group = 0
        for present in [truthy(importPublic), truthy(importPrivate), truthy(identity), truthy(generate)]
        where present { group += 1 }
        if group > 1 {
            // Python: rnid.py:95.
            return .failed("The -i, -g, -m and -M args are mutually exclusive")
        }

        group = 0
        for present in [base64, base32, base256, hex] where present { group += 1 }
        if group > 1 {
            // Python: rnid.py:100. The message names "--hex" and "--base256" although the
            // short spellings are -F and -U; reproduced verbatim.
            return .failed("The -b, -B, --hex and --base256 args are mutually exclusive")
        }

        return .ok
    }
}

// MARK: - Identity / Destination rendering

/// The `__str__` forms `rnid` interpolates into roughly 25 user-visible strings.
///
/// Neither `Identity` nor `Destination` conforms to `CustomStringConvertible` in
/// ReticulumSwift, and adding conformances would be a shared-file change, so the port
/// centralises the two renderings here instead.
public enum RNIDRender {
    /// Python: `RNS.Identity.__str__` = `RNS.prettyhexrep(self.hash)` (RNS/Identity.py:955-956).
    public static func identity(_ identity: Identity) -> String {
        RNSUtilities.prettyhexrep(identity.hash)
    }

    /// Python: `RNS.Destination.__str__` = `"<"+self.name+":"+self.hexhash+">"`
    /// (RNS/Destination.py:199-203). `name` already ends in `"." + identity.hexhash`.
    public static func destination(_ destination: Destination) -> String {
        "<\(destination.fullName):\(destination.hexHash)>"
    }
}
