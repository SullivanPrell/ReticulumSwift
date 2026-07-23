import Foundation

/// The `rnid` command-line surface: the option table, the generated help text, and the
/// argv → ``RNIDCommandLine/Invocation`` mapping.
///
/// Python reference: the `argparse` block in `main()` (rnid.py:106-153).
///
/// This lives in the library rather than in `Sources/rnid/` so the flag spellings, the help
/// text and the argument semantics (notably the `nargs="*"` empty-list quirk) are all
/// assertable from XCTest.
public enum RNIDCommandLine {

    public static let program = "rnid"
    /// Python: `argparse.ArgumentParser(description=…)`.
    public static let description = "Reticulum Identity & Encryption Utility"

    /// Python: `version="rnid {version}".format(version=__version__)`.
    public static var versionText: String { "\(program) \(Reticulum.version)" }

    // MARK: - Option table

    /// Python: every `parser.add_argument(...)` call, in declaration order.
    public static func makeParser() -> ArgumentParser {
        var parser = ArgumentParser(program: program, overview: description)

        // Identity Resolution
        parser.option(["--config"], metavar: "path",
                      help: "path to alternative Reticulum config directory")
        parser.option(["-i", "--identity"], metavar: "rid",
                      help: "hexadecimal Reticulum identity or destination hash, or path to Identity file")
        parser.option(["-g", "--generate"], metavar: "path",
                      help: "generate a new Identity and save to path")
        parser.option(["-m", "--import-pub"], metavar: "rid",
                      help: "import public Reticulum identity in hex, base32 or base64 format, or from file")
        parser.option(["-M", "--import-prv"], metavar: "rid",
                      help: "import Reticulum identity in hex, base32 or base64 format, or from file")
        parser.flag(["-x", "--export-pub"],
                    help: "export public identity to hex, base32 or base64 format")
        parser.flag(["-X", "--export-prv"],
                    help: "export private identity to hex, base32 or base64 format, or to file")

        // Verbosity Control
        parser.counted(["-v", "--verbose"], help: "increase verbosity")
        parser.counted(["-q", "--quiet"], help: "decrease verbosity")

        // Operations
        parser.optionalValue(["-a", "--announce"], metavar: "aspects", const: RNIDApp.defaultAspects,
                             help: "announce a destination based on this Identity")
        parser.option(["-H", "--hash"], metavar: "aspects",
                      help: "show destination hashes for other aspects for this Identity")
        parser.variadic(["-d", "--decrypt"], metavar: "file", help: "decrypt file")
        parser.variadic(["-e", "--encrypt"], metavar: "file", help: "encrypt file")
        parser.variadic(["-V", "--validate"], metavar: "path", help: "validate signature")
        parser.variadic(["-s", "--sign"], metavar: "path", help: "sign file")
        // const=NO_MESSAGE (the int 1) in Python; here a bare -S is recorded by
        // `wasProvided` with no value, which means "open $EDITOR".
        parser.optionalValue(["-S", "--sign-message"], metavar: "text",
                             help: "create embedded signed message")
        // const=NO_META (the int 2) in Python, where expanduser(2) then crashes.
        parser.optionalValue(["-E", "--embed-meta"], metavar: "path",
                             help: "embed metadata structure from file")
        parser.optionalValue(["--meta-spec"], metavar: "path",
                             help: "validate metadata for embedding with spec from file")
        parser.flag(["--raw"], help: "sign raw input data instead of hashing first")

        // I/O Control
        parser.option(["-w", "--write"], metavar: "path", help: "output file path")
        parser.option(["-r", "--read"], metavar: "path",
                      help: "input file path for operations with optional file input")
        parser.flag(["-f", "--force"], help: "write output even if it overwrites existing files")
        // Python: help=argparse.SUPPRESS. `-I` is DEAD — never read anywhere in rnid.py.
        parser.flag(["-I", "--stdin"], help: "read input from STDIN instead of file", hidden: true)
        parser.flag(["-O", "--stdout"], help: "write output to STDOUT instead of file", hidden: true)

        // Information Flow
        parser.flag(["-R", "--request"], help: "request unknown Identities from the network")
        // "never used cached" (sic) — Python's grammar, preserved verbatim.
        parser.flag(["-N", "--no-cache"], help: "never used cached or network-sourced information")
        parser.option(["-t"], metavar: "seconds", help: "identity request timeout before giving up",
                      default: String(Transport.pathRequestTimeout))
        parser.flag(["-p", "--print-identity"], help: "print identity info and exit")
        parser.flag(["-P", "--print-private"], help: "allow displaying private keys")

        // Formatting Control
        parser.flag(["-B", "--base32"], help: "Use base32-encoded input and output")
        parser.flag(["-b", "--base64"], help: "Use base64-encoded input and output")
        parser.flag(["-U", "--base256"], help: "Use base256-encoded input and output")
        parser.flag(["-F", "--hex"], help: "Use hex-encoded input and output")
        parser.flag(["--meta"], help: "Display RSM metadata if available")
        parser.flag(["--version"], help: "show program's version number and exit")

        return parser
    }

    /// The `--help` output, laid out the way `argparse` lays it out.
    public static var helpText: String {
        RNIDArgparseHelp.render(program: program, description: description,
                            options: makeParser().optionSpecs)
    }

    // MARK: - Invocation

    /// Everything `main()` reads off `args`.
    public struct Invocation {
        // Identity resolution
        public var config: String?
        public var identity: String?
        public var generate: String?
        public var importPublic: String?
        public var importPrivate: String?
        public var exportPublic = false
        public var exportPrivate = false

        // Verbosity
        public var verbose = 0
        public var quiet = 0
        public var stdout = false

        // Operations
        public var announce: String?
        public var hash: String?
        public var decrypt: [String]?
        public var encrypt: [String]?
        public var validate: [String]?
        public var sign: [String]?
        /// `nil` with ``signMessageProvided`` true means a bare `-S` (open `$EDITOR`).
        public var signMessage: String?
        public var signMessageProvided = false
        public var embedMeta: String?
        public var embedMetaWithoutPath = false
        public var metaSpec: String?
        public var raw = false

        // I/O
        public var write: String?
        public var read: String?
        public var force = false

        // Information flow
        public var request = false
        public var noCache = false
        public var timeout: TimeInterval = Transport.pathRequestTimeout
        public var printIdentity = false
        public var printPrivate = false

        // Formatting
        public var base32 = false
        public var base64 = false
        public var base256 = false
        public var hex = false
        public var showMeta = false

        public var wantsHelp = false
        public var wantsVersion = false

        public init() {}

        /// Python: `op_requires_identity = (args.sign or args.sign_message or args.encrypt or
        /// args.decrypt or args.announce or args.write or args.print_identity or
        /// args.print_identity or args.export_pub or args.export_prv)` — note
        /// `print_identity` appears twice, a harmless typo.
        ///
        /// `args.hash` and `args.validate` are deliberately absent, which is exactly why they
        /// are dispatched with `identity or args.identity` and must work with an unresolved
        /// bare hex string.
        public var operationRequiresIdentity: Bool {
            truthy(sign) || signMessageTruthy || truthy(encrypt) || truthy(decrypt)
                || truthy(announce) || truthy(write) || printIdentity
                || exportPublic || exportPrivate
        }

        /// Python truthiness for a `nargs="*"` list: `[]` is falsy.
        public func truthy(_ list: [String]?) -> Bool { !(list ?? []).isEmpty }
        /// Python truthiness for a string: `""` is falsy.
        public func truthy(_ text: String?) -> Bool { !(text ?? "").isEmpty }

        /// `-S` stores either the int `NO_MESSAGE` (always truthy) or the supplied text.
        public var signMessageTruthy: Bool {
            signMessageProvided && (signMessage == nil || !(signMessage!.isEmpty))
        }

        /// Python: the identity source `get_operating_identity` selects.
        public var identitySource: RNIDIdentitySource {
            if truthy(generate) { return .generate(path: generate!, force: force) }
            if truthy(identity) { return .identityArgument(identity!) }
            if truthy(importPublic) { return .importPublic(importPublic!) }
            if truthy(importPrivate) { return .importPrivate(importPrivate!) }
            return .none
        }

        /// Python: the `-B`/`-b`/`-U`/`-F` ladder.
        public var outputFormat: RNIDApp.OutputFormat {
            RNIDApp.outputFormat(base32: base32, base64: base64, base256: base256, hex: hex)
        }

        /// The subset ``RNIDOperations`` needs.
        public var operationOptions: RNIDApp.Options {
            var options = RNIDApp.Options()
            options.outputFormat = outputFormat
            options.force = force
            options.raw = raw
            options.write = write
            options.read = read
            options.showMeta = showMeta
            options.printPrivate = printPrivate
            options.embedMeta = embedMeta
            options.embedMetaWithoutPath = embedMetaWithoutPath
            options.metaSpec = metaSpec
            options.timeout = timeout
            return options
        }

        /// Python: `validate_args(args)`.
        public var argumentValidation: RNIDApp.ArgumentValidation {
            RNIDApp.validateArguments(
                encrypt: encrypt, decrypt: decrypt, validate: validate, sign: sign,
                signMessage: signMessage, signMessageProvided: signMessageProvided,
                importPublic: importPublic, importPrivate: importPrivate,
                identity: identity, generate: generate,
                base64: base64, base32: base32, base256: base256, hex: hex)
        }
    }

    /// Parse argv (without the executable name) into an ``Invocation``.
    public static func parse(_ arguments: [String]) throws -> Invocation {
        let parsed = try makeParser().parse(arguments)
        var invocation = Invocation()

        invocation.config = parsed.value("--config")
        invocation.identity = parsed.value("--identity")
        invocation.generate = parsed.value("--generate")
        invocation.importPublic = parsed.value("--import-pub")
        invocation.importPrivate = parsed.value("--import-prv")
        invocation.exportPublic = parsed.flag("--export-pub")
        invocation.exportPrivate = parsed.flag("--export-prv")

        invocation.verbose = parsed.count("--verbose")
        invocation.quiet = parsed.count("--quiet")
        invocation.stdout = parsed.flag("--stdout")

        invocation.announce = parsed.value("--announce")
        invocation.hash = parsed.value("--hash")
        invocation.decrypt = parsed.values("--decrypt")
        invocation.encrypt = parsed.values("--encrypt")
        invocation.validate = parsed.values("--validate")
        invocation.sign = parsed.values("--sign")
        invocation.signMessage = parsed.value("--sign-message")
        invocation.signMessageProvided = parsed.wasProvided("--sign-message")
        invocation.embedMeta = parsed.value("--embed-meta")
        // Python: a bare -E yields the int NO_META and then crashes in expanduser.
        invocation.embedMetaWithoutPath = parsed.wasProvided("--embed-meta")
            && parsed.value("--embed-meta") == nil
        invocation.metaSpec = parsed.value("--meta-spec")
        invocation.raw = parsed.flag("--raw")

        invocation.write = parsed.value("--write")
        invocation.read = parsed.value("--read")
        invocation.force = parsed.flag("--force")

        invocation.request = parsed.flag("--request")
        invocation.noCache = parsed.flag("--no-cache")
        invocation.timeout = parsed.double("-t") ?? Transport.pathRequestTimeout
        invocation.printIdentity = parsed.flag("--print-identity")
        invocation.printPrivate = parsed.flag("--print-private")

        invocation.base32 = parsed.flag("--base32")
        invocation.base64 = parsed.flag("--base64")
        invocation.base256 = parsed.flag("--base256")
        invocation.hex = parsed.flag("--hex")
        invocation.showMeta = parsed.flag("--meta")

        invocation.wantsHelp = parsed.wantsHelp
        invocation.wantsVersion = parsed.flag("--version")

        return invocation
    }
}
