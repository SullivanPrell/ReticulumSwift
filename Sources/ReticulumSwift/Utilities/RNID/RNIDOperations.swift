import Foundation

/// Every operation `rnid`'s `main()` dispatches to, each returning an ``RNIDApp/Result``
/// instead of calling `exit()`.
///
/// Python reference: `RNS/Utilities/rnid.py`.
///
/// ### Path expansion is deliberately inconsistent
///
/// Python applies `os.path.expanduser` at ten sites and skips it at two, and the two skips
/// are **not** symmetric between encrypt and decrypt. A uniform "expand everything" helper
/// would silently change where files land, so each call site below matches Python exactly:
///
/// | Site | Python line | Expanded |
/// |------|-------------|----------|
/// | `-g` target | 208, 213 | **no** |
/// | `-i` | 218 | yes |
/// | `-m` / `-M` | 285, 324 | yes |
/// | `-V` per path | 621 | yes |
/// | `-s` per path | 753 | yes |
/// | `-S`'s `-r` input | 804 | yes |
/// | `-E` | 812 | yes |
/// | `--meta-spec` | 813 | **no** |
/// | `-e`'s `-w` output | 862 | **no** |
/// | `-d`'s input | 904 | yes |
/// | `-d`'s `-w` output | 907 | yes |
/// | `-w` (write_identity) | 948 | yes |
///
/// ### Extension matching is deliberately inconsistent too
///
/// `-V` lowercases before testing `.rsm`/`.rsg`; `-d` tests `.rfe` **case-sensitively**;
/// `-S`'s `.rsm` suffix test is **case-sensitive**; `write_identity`'s `.pub` test is
/// case-insensitive but appends a lowercase suffix. Normalising these would produce interop
/// failures on mixed-case filenames.
public final class RNIDOperations {

    private let identity: Identity?
    /// Python: the raw `args.identity` string, which `-H` and `-V` fall back to when no
    /// Identity could be resolved (`identity or args.identity`, rnid.py:167, :169).
    private let identityArgument: String?
    private var options: RNIDApp.Options
    private let output: RNIDOutput
    private let fileSystem: RNIDFileSystem
    private let transport: Transport?
    private let editor: RNIDEditor?

    public init(identity: Identity?,
                identityArgument: String? = nil,
                options: RNIDApp.Options = RNIDApp.Options(),
                output: RNIDOutput,
                fileSystem: RNIDFileSystem,
                transport: Transport? = nil,
                editor: RNIDEditor? = nil) {
        self.identity = identity
        self.identityArgument = identityArgument
        self.options = options
        self.output = output
        self.fileSystem = fileSystem
        self.transport = transport
        self.editor = editor
    }

    // MARK: - Encoding helper

    /// Python: `if args.base64 … elif args.base32 … else RNS.hexrep(..., delimit=False)`.
    /// Note `-U`/`--base256` is **not** honoured by `-p`, `-x` or `-X`; it falls through to hex.
    private func encodeKeyBlob(_ blob: Data) -> String {
        switch options.outputFormat {
        case .base64: return RNIDEncoding.base64URLEncode(blob)
        case .base32: return RNIDEncoding.base32Encode(blob)
        default:      return RNIDEncoding.hexEncode(blob)
        }
    }

    // MARK: - -p / --print-identity

    /// Python: `print_identity_information` (rnid.py:971-982).
    /// The label column is 14 characters wide so the colons align.
    @discardableResult
    public func printIdentityInformation() -> RNIDApp.Result {
        guard let identity else { return .noIdentity }
        output.line("Identity Hash : " + RNSUtilities.prettyhexrep(identity.hash))
        output.line("Public Key    : " + encodeKeyBlob(identity.getPublicKey()))
        // Python gates on `identity.prv`, the X25519 private key object.
        if identity.hasPrivateKey {
            if options.printPrivate, let privateKey = identity.getPrivateKey() {
                output.line("Private Key   : " + encodeKeyBlob(privateKey))
            } else {
                output.line("Private Key   : Hidden")
            }
        }
        return .ok
    }

    // MARK: - -x / --export-pub

    /// Python: `export_pub_identity` (rnid.py:1013-1019). The 22-character label aligns with
    /// the private form.
    @discardableResult
    public func exportPublicIdentity() -> RNIDApp.Result {
        guard let identity else { return .noIdentity }
        // Python's `if not k: … exit(R_NO_PUBKEY)` is unreachable in Swift — Identity's
        // publicKeyBytes is non-optional, so every Identity holds a public key.
        output.line("Public Identity Keys  : " + encodeKeyBlob(identity.getPublicKey()))
        return .ok
    }

    // MARK: - -X / --export-prv

    /// Python: `export_prv_identity` (rnid.py:1021-1027). Prints the private key with no
    /// confirmation prompt, and does **not** require `-P`.
    @discardableResult
    public func exportPrivateIdentity() -> RNIDApp.Result {
        guard let identity else { return .noIdentity }
        guard let privateKey = identity.getPrivateKey() else {
            output.line("Identity doesn't hold a private key, cannot export")
            return .noPrvKey
        }
        output.line("Private Identity Keys : " + encodeKeyBlob(privateKey))
        return .ok
    }

    // MARK: - -H / --hash

    /// Python: `print_hash_information` (rnid.py:984-1011), called with
    /// `identity or args.identity`, so it must work with an unresolved bare hex string.
    @discardableResult
    public func printHashInformation(aspects dottedName: String) -> RNIDApp.Result {
        let identityHash: Data
        var destination: Destination?

        if let identity {
            identityHash = identity.hash
            // Python's Destination.__init__ ends with Transport.register_destination(self);
            // Swift's does not, so register explicitly to match.
            let components = RNIDApp.splitAspects(dottedName)
            let appName = components[0]
            let rest = Array(components.dropFirst())
            do {
                let outbound = try Destination(identity: identity, direction: .out, kind: .single,
                                               appName: appName, aspects: rest)
                transport?.register(destination: outbound)
                destination = outbound
            } catch {
                output.line("An error ocurred while attempting to get hash information: \(error)")
                return .unknownError
            }
        } else if let identityArgument {
            guard identityArgument.count == RNIDIdentityResolver.hashStringLength else {
                output.line("Invalid identity hash length")
                return .invalidIdentity
            }
            guard let decoded = RNIDEncoding.hexDecode(identityArgument) else {
                output.line("Invalid identity: non-hexadecimal number found in fromhex() arg")
                return .invalidIdentity
            }
            identityHash = decoded
        } else {
            // Python: `identity or args.identity` is None when -i was never supplied.
            output.line("Invalid identity")
            return .invalidIdentity
        }

        // Python passes the RAW 16 bytes and the FULL dotted name, so the app/aspect split
        // happens a SECOND time inside hash_from_name_and_identity.
        guard let destinationHash = RNIDDestinationHash.hash(fromFullName: dottedName,
                                                             identityHash: identityHash) else {
            output.line("An error ocurred while attempting to get hash information: "
                        + "Invalid material supplied for destination hash calculation")
            return .unknownError
        }
        output.line("The \(dottedName) destination for this Identity is "
                    + RNSUtilities.prettyhexrep(destinationHash))
        if let destination {
            output.line("The full destination specifier is " + RNIDRender.destination(destination))
        }
        return .ok
    }

    // MARK: - -a / --announce

    /// Python: `announce` (rnid.py:377-390).
    ///
    /// The aspect gate is `len(aspects) > 1`, so a single bare token like `"rns"` is rejected
    /// while `"rns."` — which Python's `str.split` turns into `['rns','']` — is accepted.
    /// See ``RNIDApp/splitAspects(_:)``.
    @discardableResult
    public func announce(aspects dottedName: String) -> RNIDApp.Result {
        let components = RNIDApp.splitAspects(dottedName)
        guard components.count > 1 else {
            output.line("Invalid destination aspects specified")
            return .invalidAspects
        }
        guard let identity else {
            output.line("An error ocurred while attempting to send the announce: no identity")
            return .unknownError
        }
        guard identity.hasPrivateKey else {
            output.line("Cannot announce this destination, since the private key is not held")
            return .noPrvKey
        }

        let appName = components[0]
        let rest = Array(components.dropFirst())
        do {
            let destination = try Destination(identity: identity, direction: .in, kind: .single,
                                              appName: appName, aspects: rest)
            guard let transport else {
                output.line("An error ocurred while attempting to send the announce: no Reticulum instance")
                return .unknownError
            }
            // Python gets this for free from Destination.__init__.
            transport.register(destination: destination)
            output.line("Announcing \(dottedName) destination "
                        + "\(RNSUtilities.prettyhexrep(destination.hash)) for identity "
                        + RNIDRender.identity(identity))
            _ = try transport.announce(destination: destination)
            return .ok
        } catch {
            // Also absorbs Destination.expand_name's ValueError for dots in aspects, which
            // Swift raises as DestinationError.dotsForbidden.
            output.line("An error ocurred while attempting to send the announce: \(error)")
            return .unknownError
        }
    }

    // MARK: - -V / --validate

    /// Python: `validate` (rnid.py:606-671), list-recursion form.
    @discardableResult
    public func validate(paths: [String]) -> RNIDApp.Result {
        var validated = 0
        for path in paths {
            let code = validateSingle(path: path)
            // Python's per-path failures call exit(), which raises SystemExit and unwinds
            // straight past the caller's `if code != 0` check — so the sequence-error branch
            // below is unreachable in practice. Reproduce the exit, not the sequence error.
            guard code == .ok else { return code }
            validated += 1
        }
        guard paths.count == validated else {
            output.line("Sequence error on recursive signature validation")
            return .sequenceError
        }
        return .ok
    }

    /// Python: the single-path body of `validate`.
    private func validateSingle(path: String) -> RNIDApp.Result {
        let sigExt = ".\(RNIDApp.sigExt)"
        let msgExt = ".\(RNIDApp.msgExt)"
        let validatePath = fileSystem.expandTilde(path)
        // Both of these are CASE-INSENSITIVE in Python.
        let pathIsMsgFile = validatePath.lowercased().hasSuffix(msgExt)
        let pathIsSigFile = validatePath.lowercased().hasSuffix(sigExt)

        let signaturePath: String
        let filePath: String
        if pathIsSigFile {
            signaturePath = validatePath
            filePath = String(validatePath.dropLast(sigExt.count))
        } else {
            signaturePath = validatePath + sigExt
            filePath = validatePath
        }

        // The .rsm delegation happens AFTER both existence probes are computed but BEFORE
        // they are tested, so a .rsm path never hits the two "does not exist" messages.
        if pathIsMsgFile { return validateMessage(path: path) }
        guard fileSystem.fileExists(atPath: filePath) else {
            output.line("The validation target \"\(filePath)\" does not exist")
            return .noFile
        }
        guard fileSystem.fileExists(atPath: signaturePath) else {
            output.line("No signature file exists for \"\(filePath)\"")
            return .noFile
        }

        // Python opens the signature file TWICE — once for format detection and once to read
        // the content — and each open has its own error message. Reproduced so an I/O failure
        // reports the same string Python would.
        let detection: Data
        do {
            detection = try fileSystem.readData(atPath: signaturePath)
        } catch {
            output.line("Could not detect rsg format: \(error)")
            return .unknownError
        }

        if RSG.isLegacyFormat(detection) {
            return validateLegacy(signaturePath: signaturePath, filePath: filePath)
        }

        let rsg: Data
        do {
            rsg = try fileSystem.readData(atPath: signaturePath)
        } catch {
            output.line("Could not read rsg: \(error)")
            return .readError
        }

        let requiredSigner: RSG.RequiredSigner
        switch coerceRequiredSigner() {
        case .success(let signer): requiredSigner = signer
        case .failure(let result): return result
        }

        let reader: RNIDByteReader
        do {
            reader = try fileSystem.makeReader(atPath: filePath)
        } catch {
            output.line("Could not read \(filePath): \(error)")
            return .readError
        }

        do {
            let result = try RSG.validate(rsgData: rsg, message: .file(reader),
                                          requiredSigner: requiredSigner)
            let description = signerDescription(requiredSigner, prefix: "This file was NOT signed by")
            guard result.isValid, let signingIdentity = result.signingIdentity else {
                output.line("Invalid signature \(signaturePath) for file \(filePath)\(description)")
                return .invalidSignature
            }
            output.line("Signature is valid, the file \(filePath) was signed by "
                        + RNIDRender.identity(signingIdentity))
            return .ok
        } catch {
            output.line("Error while validating \(signaturePath): \(error)")
            return .unknownError
        }
    }

    /// Python: the legacy branch of `validate` (rnid.py:660-671).
    ///
    /// A bare hex hash is not sufficient here — a legacy rsg has no embedded pubkey, so an
    /// explicit Identity is required.
    private func validateLegacy(signaturePath: String, filePath: String) -> RNIDApp.Result {
        guard let identity else {
            output.line("Cannot validate legacy rsg signatures without an explicit required identity")
            return .noIdentity
        }
        let signature: Data
        do {
            signature = try fileSystem.readData(atPath: signaturePath)
        } catch {
            output.line("Could not read signature: \(error)")
            return .readError
        }
        let fileData: Data
        do {
            fileData = try fileSystem.readData(atPath: filePath)
        } catch {
            output.line("Could not validate signature: \(error)")
            return .readError
        }
        guard RSG.validateLegacy(signature: signature, fileData: fileData, identity: identity) else {
            output.line("Invalid signature \(signaturePath) for file \(filePath)"
                        + "\nThis file was NOT signed by \(RNIDRender.identity(identity))")
            return .invalidSignature
        }
        output.line("Signature is valid, the file \(filePath) was signed by "
                    + RNIDRender.identity(identity))
        return .ok
    }

    /// Python: `validate_message` (rnid.py:673-737). Re-derives its own paths from
    /// `args.validate` rather than receiving `validate`'s.
    private func validateMessage(path: String) -> RNIDApp.Result {
        let signaturePath = fileSystem.expandTilde(path)
        guard fileSystem.fileExists(atPath: signaturePath) else {
            output.line("The signature file \"\(signaturePath)\" does not exist")
            return .noFile
        }

        let rsg: Data
        do {
            rsg = try fileSystem.readData(atPath: signaturePath)
        } catch {
            output.line("Could not read rsg: \(error)")
            return .readError
        }

        let requiredSigner: RSG.RequiredSigner
        switch coerceRequiredSigner() {
        case .success(let signer): requiredSigner = signer
        case .failure(let result): return result
        }

        do {
            // Python: `"message" in None` raises TypeError for an undecodable envelope, which
            // the outer handler turns into R_UNKNOWN_ERROR (254), NOT R_INVALID_SIGNATURE.
            guard let contents = try RSG.extractSignedData(rsg) else {
                throw RSG.RSGError.malformedEnvelope
            }
            guard let embedded = contents.message else {
                output.line("No embedded message in \(signaturePath)")
                return .invalidSignature
            }
            // An EMPTY embedded message trips validate_rsg's falsy-message guard → 254.
            let result = try RSG.validate(rsgData: rsg, message: .bytes(embedded),
                                          requiredSigner: requiredSigner)
            let description = signerDescription(requiredSigner, prefix: "The message was NOT signed by")
            guard result.isValid,
                  let signedData = result.signedData,
                  let signingIdentity = result.signingIdentity else {
                output.line("Invalid signature in \(signaturePath)\(description)")
                return .invalidSignature
            }
            renderValidMessage(signedData: signedData, signingIdentity: signingIdentity)
            return .ok
        } catch {
            output.line("Error while validating \(signaturePath): \(error)")
            return .unknownError
        }
    }

    /// Python: the success block of `validate_message` (rnid.py:699-733).
    private func renderValidMessage(signedData: RSG.SignedData, signingIdentity: Identity) {
        if options.showMeta {
            output.line("RSM Metadata\n============\n")
            for (key, value) in signedData.meta {
                renderMetaEntry(value, key: key, level: 1)
            }
            output.line("\nValidation\n==========")
        }

        let colon = options.showMeta ? "" : ":"
        let following = options.showMeta ? "" : " following"
        output.line("\nSignature is valid, the\(following) message was signed by "
                    + "\(RNIDRender.identity(signingIdentity))\(colon)\n")
        if options.showMeta { output.line("Message\n=======\n") }
        output.line(String(decoding: signedData.message ?? Data(), as: UTF8.self))
    }

    /// Python: the nested `recurse(entry, key, level)` inside `validate_message`.
    ///
    /// Type tags: `s` str, `b` bytes, `l` list, `d` dict, `i` int, `f` float, `N` None,
    /// `u` anything else — and **bool lands on `u`**, because `type(True) == int` is `False`
    /// in Python.
    private func renderMetaEntry(_ entry: MsgPack.Value, key: String, level: Int) {
        let indent = String(repeating: "  ", count: level)

        if case .map(let pairs) = entry {
            output.line("d\(indent)\(key):")
            for (childKey, childValue) in pairs {
                guard case .string(let name) = childKey else { continue }
                renderMetaEntry(childValue, key: name, level: level + 1)
            }
            return
        }

        let typeTag: String
        switch entry {
        case .string:        typeTag = "s"
        case .bytes:         typeTag = "b"
        case .array:         typeTag = "l"
        case .map:           typeTag = "d"
        case .int, .uint:    typeTag = "i"
        case .double:        typeTag = "f"
        case .nil:           typeTag = "N"
        case .bool:          typeTag = "u"   // Python: bool is not `type(entry) == int`
        }

        // Python: `if key == "note" and entry == None: return` — checked AFTER etype
        // selection. Marked "TODO: Remove this check in 1.3.3" upstream.
        if key == "note", entry.isNil { return }

        let rendered: String
        if case .bytes(let data) = entry {
            rendered = RNSUtilities.hexrep(data, delimit: false)
        } else {
            rendered = RNIDOperations.pythonRepr(entry)
        }

        let leadIn = "\(typeTag)\(indent)\(key)="
        let maxWidth = 64
        var remaining = Substring(rendered)
        let firstChunk = String(remaining.prefix(maxWidth))
        remaining = remaining.dropFirst(firstChunk.count)
        output.line(leadIn + firstChunk)
        while !remaining.isEmpty {
            let chunk = String(remaining.prefix(maxWidth))
            remaining = remaining.dropFirst(chunk.count)
            output.line(String(repeating: " ", count: leadIn.count) + chunk)
        }
    }

    /// Python's `f"{entry}"` for the value types a metadata map can hold.
    static func pythonRepr(_ value: MsgPack.Value) -> String {
        switch value {
        case .nil:              return "None"
        case .bool(let flag):   return flag ? "True" : "False"
        case .int(let number):  return String(number)
        case .uint(let number): return String(number)
        case .double(let number):
            // Python's float repr drops the ".0" only for integral values in some contexts;
            // str(1.5) == "1.5" and str(2.0) == "2.0".
            if number == number.rounded(), abs(number) < 1e16 {
                return String(format: "%.1f", number)
            }
            return String(number)
        case .string(let text): return text
        case .bytes(let data):  return RNSUtilities.hexrep(data, delimit: false)
        case .array(let items):
            return "[" + items.map { element -> String in
                if case .string(let text) = element { return "'\(text)'" }
                return pythonRepr(element)
            }.joined(separator: ", ") + "]"
        case .map(let pairs):
            return "{" + pairs.map { key, value in
                "\(pythonRepr(key)): \(pythonRepr(value))"
            }.joined(separator: ", ") + "}"
        }
    }

    /// Python: the `if type(identity) == str:` coercion shared by `validate` (rnid.py:642-645)
    /// and `validate_message` (rnid.py:686-689).
    private func coerceRequiredSigner() -> Swift.Result<RSG.RequiredSigner, RNIDApp.Result> {
        if let identity { return .success(.identity(identity)) }
        guard let identityArgument, !identityArgument.isEmpty else { return .success(.none) }
        guard identityArgument.count == RNIDIdentityResolver.hashStringLength else {
            output.line("Invalid identity hash length")
            return .failure(.invalidIdentity)
        }
        guard let decoded = RNIDEncoding.hexDecode(identityArgument) else {
            output.line("Invalid identity hash: non-hexadecimal number found in fromhex() arg")
            return .failure(.invalidIdentity)
        }
        return .success(.hash(decoded))
    }

    /// Python: `signer_description = f"\n{prefix} {identity_str or signing_identity}" if identity else ""`.
    /// `identity_str` is `RNS.prettyhexrep(identity)` for bytes and `f"{identity}"` for an
    /// Identity, and is always a non-empty string, so the `or signing_identity` fallback never
    /// fires.
    private func signerDescription(_ signer: RSG.RequiredSigner, prefix: String) -> String {
        switch signer {
        case .identity(let identity): return "\n\(prefix) \(RNIDRender.identity(identity))"
        case .hash(let hash) where !hash.isEmpty:
            return "\n\(prefix) \(RNSUtilities.prettyhexrep(hash))"
        default: return ""
        }
    }

    // MARK: - -s / --sign

    /// Python: `sign` (rnid.py:739-786), list-recursion form.
    @discardableResult
    public func sign(paths: [String]) -> RNIDApp.Result {
        var signed = 0
        for path in paths {
            let code = signSingle(path: path)
            // Python's per-path failures call exit(), which raises SystemExit and unwinds
            // straight past the caller's `if code != 0` check — so the sequence-error branch
            // below is unreachable in practice. Reproduce the exit, not the sequence error.
            guard code == .ok else { return code }
            signed += 1
        }
        guard paths.count == signed else {
            output.line("Sequence error on recursive signature creation")
            return .sequenceError
        }
        return .ok
    }

    private func signSingle(path: String) -> RNIDApp.Result {
        let sigExt = ".\(RNIDApp.sigExt)"
        let signPath = fileSystem.expandTilde(path)
        // The .rsg suffix is appended ALWAYS, even for text output formats.
        let rsgPath = signPath + sigExt
        let format = options.outputFormat

        guard let identity else { return .unknownError }
        guard identity.hasPrivateKey else {
            output.line("Cannot sign \"\(signPath)\", the identity does not hold a private key")
            return .noPrvKey
        }
        guard fileSystem.fileExists(atPath: signPath) else {
            output.line("The file \"\(signPath)\" does not exist")
            return .noFile
        }
        // QUIRK: the overwrite guard is gated on `output == "bin"`, so `-s file --raw -b`
        // still overwrites the .rsg without asking, because --raw always writes binary
        // regardless of the encoding flag. Preserved deliberately.
        if format == .bin, fileSystem.fileExists(atPath: rsgPath), !options.force {
            output.line("The signature file \"\(rsgPath)\" already exists, not overwriting")
            return .fileExists
        }

        do {
            if options.raw {
                // The only producer of legacy-format RSG files: a bare 64-byte Ed25519
                // signature over the raw file bytes. `output` is computed but ignored here.
                let data = try fileSystem.readData(atPath: signPath)
                try fileSystem.writeData(try identity.sign(data), atPath: rsgPath)
            } else {
                let reader = try fileSystem.makeReader(atPath: signPath)
                let rsg = try RSG.create(signer: identity, message: .file(reader),
                                         embed: false, meta: nil, output: format)
                switch rsg {
                case .binary(let data): try fileSystem.writeData(data, atPath: rsgPath)
                case .text(let text):   output.line("\n\(RSGArmour.wrap(text))\n")
                }
            }
            output.line("Signed file \(signPath) with \(RNIDRender.identity(identity))")
            return .ok
        } catch {
            output.line("Could not sign \(signPath): \(error)")
            return .unknownError
        }
    }

    // MARK: - -S / --sign-message

    /// Python: `sign_message` (rnid.py:788-840).
    ///
    /// - Parameter message: the inline text, or `nil` for a bare `-S` (Python's `NO_MESSAGE`
    ///   sentinel), which means "open `$EDITOR`".
    @discardableResult
    public func signMessage(_ message: String?) -> RNIDApp.Result {
        let format = options.outputFormat

        if format == .bin, options.write == nil {
            output.line("No write path specified")
            return .invalidArgs
        }
        guard let identity else {
            output.line("Cannot sign, no working identity available")
            return .noIdentity
        }
        guard identity.hasPrivateKey else {
            output.line("Cannot sign, the identity does not hold a private key")
            return .noPrvKey
        }

        var body: RSG.Message?
        if let readPath = options.read {
            if message != nil {
                output.line("Both an input file and command-line provided message was specified, aborting")
                return .invalidArgs
            }
            let signPath = fileSystem.expandTilde(readPath)
            guard fileSystem.fileExists(atPath: signPath) else {
                output.line("The file \(signPath) does not exist")
                return .noFile
            }
            do {
                body = .text(try fileSystem.readText(atPath: signPath))
            } catch {
                // DIVERGENCE: Python's open/read here sits outside any try, so a
                // UnicodeDecodeError is an uncaught traceback (shell exit 1). We report
                // R_READ_ERROR (252) instead.
                output.line("Could not sign message: \(error)")
                return .readError
            }
        } else if let message {
            body = .text(message)
        }

        if body == nil {
            guard let editor else {
                output.line("Could not launch editor")
                return .readError
            }
            do {
                body = .bytes(try editor.composeMessage())
            } catch {
                output.line("Could not get content from editor: \(error)")
                return .readError
            }
        }

        guard let body, body.isTruthy else {
            output.line("No message specified")
            return .invalidArgs
        }

        var meta: [(String, MsgPack.Value)]?
        // Python: a bare -E is the int NO_META, and os.path.expanduser(2) raises an uncaught
        // TypeError → shell exit 1. This port reports R_INVALID_ARGS (250).
        if options.embedMetaWithoutPath { return .invalidArgs }
        if let embedMeta = options.embedMeta, !embedMeta.isEmpty {
            let metaPath = fileSystem.expandTilde(embedMeta)
            // Note: an explicit --meta-spec is used RAW, without expansion.
            var metaSpecPath: String? = options.metaSpec ?? (metaPath + ".spec")
            guard fileSystem.fileExists(atPath: metaPath) else {
                output.line("Metadata file \(metaPath) does not exist")
                return .noFile
            }
            // A missing spec is silently nulled — including an explicitly supplied one.
            if let candidate = metaSpecPath, !fileSystem.fileExists(atPath: candidate) {
                metaSpecPath = nil
            }
            let specInfo = metaSpecPath.map { " using spec from \($0)" } ?? ""
            output.line("Embedding metadata from \(metaPath)\(specInfo)")
            do {
                let text = try fileSystem.readText(atPath: metaPath)
                let spec = try metaSpecPath.map { try fileSystem.readText(atPath: $0) }
                meta = try RNIDMeta.parse(text, spec: spec)
            } catch {
                output.line("Could not load metadata from \(metaPath): \(error)")
                return .unknownError
            }
        }

        do {
            let rsg = try RSG.create(signer: identity, message: body, embed: true,
                                     meta: meta, output: format)
            switch rsg {
            case .binary(let data):
                let msgExt = ".\(RNIDApp.msgExt)"
                var rsgPath = fileSystem.expandTilde(options.write ?? "")
                // CASE-SENSITIVE, unlike validate's checks.
                if !rsgPath.hasSuffix(msgExt) { rsgPath += msgExt }
                if fileSystem.fileExists(atPath: rsgPath), !options.force {
                    output.line("The signature file \"\(rsgPath)\" already exists, not overwriting")
                    return .fileExists
                }
                try fileSystem.writeData(data, atPath: rsgPath)
                output.line("Message signed with \(RNIDRender.identity(identity)) saved to \(rsgPath)")
                return .ok
            case .text(let text):
                output.line("\n\(RSGArmour.wrap(text))\n")
                // Python FALLS THROUGH to the shorter line here — no "saved to".
                output.line("Message signed with \(RNIDRender.identity(identity))")
                return .ok
            }
        } catch {
            output.line("Could not sign message: \(error)")
            return .unknownError
        }
    }

    // MARK: - -e / --encrypt

    /// Python: `encrypt` (rnid.py:847-888), list-recursion form.
    @discardableResult
    public func encrypt(paths: [String]) -> RNIDApp.Result {
        var encrypted = 0
        for path in paths {
            let code = encryptSingle(path: path)
            // Python's per-path failures call exit(), which raises SystemExit and unwinds
            // straight past the caller's `if code != 0` check — so the sequence-error branch
            // below is unreachable in practice. Reproduce the exit, not the sequence error.
            guard code == .ok else { return code }
            encrypted += 1
        }
        guard paths.count == encrypted else {
            output.line("Sequence error on recursive file encryption")
            return .sequenceError
        }
        return .ok
    }

    private func encryptSingle(path: String) -> RNIDApp.Result {
        let encExt = ".\(RNIDApp.encryptExt)"
        let encryptPath = fileSystem.expandTilde(path)
        // `args.write` is used RAW here — unlike decrypt, which expands it (rnid.py:862 vs :907).
        let rfePath = options.write ?? (encryptPath + encExt)

        guard let identity else {
            output.line("Cannot encrypt \"\(encryptPath)\", no identity specified")
            return .noIdentity
        }
        // Python's R_NO_PUBKEY branch is unreachable in Swift — Identity always holds a
        // public key.
        guard fileSystem.fileExists(atPath: encryptPath) else {
            output.line("The file \"\(encryptPath)\" does not exist")
            return .noFile
        }
        if fileSystem.fileExists(atPath: rfePath), !options.force {
            output.line("The encryption output file \"\(rfePath)\" already exists, not overwriting")
            return .fileExists
        }

        let reader: RNIDByteReader
        do {
            reader = try fileSystem.makeReader(atPath: encryptPath)
        } catch {
            // Python's OUTER try only wraps opening the input, so this is the one failure
            // reported as a read error — and it still exits R_WRITE_ERROR.
            output.line("\nError reading \(encryptPath) for encryption: \(error)")
            return .writeError
        }

        do {
            let writer = try fileSystem.makeWriter(atPath: rfePath)
            try RNIDFileCrypto.encryptStream(identity: identity, reader: reader, writer: writer) { wrote in
                self.output.partial("\rWrote \(RNSUtilities.prettysize(wrote)) to \(rfePath)   ")
            }
        } catch {
            output.line("\nError writing encrypted output to \(rfePath): \(error)")
            return .writeError
        }

        output.line("\nFile \(encryptPath) encrypted for \(RNIDRender.identity(identity)) to \(rfePath)")
        return .ok
    }

    // MARK: - -d / --decrypt

    /// Python: `decrypt` (rnid.py:890-939), list-recursion form.
    @discardableResult
    public func decrypt(paths: [String]) -> RNIDApp.Result {
        var decrypted = 0
        for path in paths {
            let code = decryptSingle(path: path)
            // Python's per-path failures call exit(), which raises SystemExit and unwinds
            // straight past the caller's `if code != 0` check — so the sequence-error branch
            // below is unreachable in practice. Reproduce the exit, not the sequence error.
            guard code == .ok else { return code }
            decrypted += 1
        }
        guard paths.count == decrypted else {
            output.line("Sequence error on recursive file decryption")
            return .sequenceError
        }
        return .ok
    }

    private func decryptSingle(path: String) -> RNIDApp.Result {
        let encExt = ".\(RNIDApp.encryptExt)"
        let rfePath = fileSystem.expandTilde(path)
        // CASE-SENSITIVE, unlike validate's checks.
        guard rfePath.hasSuffix(encExt) else {
            output.line("The file \(rfePath) does not appear to be a Reticulum encrypted file")
            return .invalidFile
        }
        // Expanded here, unlike encrypt's -w.
        let decryptPath = options.write.map { fileSystem.expandTilde($0) }
            ?? String(rfePath.dropLast(encExt.count))
        guard !decryptPath.isEmpty else {
            output.line("Invalid output filename")
            return .invalidFile
        }

        guard let identity else {
            output.line("Cannot decrypt \"\(rfePath)\", no identity specified")
            return .noIdentity
        }
        guard identity.hasPrivateKey else {
            output.line("Cannot decrypt \"\(rfePath)\", the identity does not hold a private key")
            return .noPrvKey
        }
        guard fileSystem.fileExists(atPath: rfePath) else {
            output.line("The file \"\(rfePath)\" does not exist")
            return .noFile
        }
        if fileSystem.fileExists(atPath: decryptPath), !options.force {
            output.line("The decryption output file \"\(decryptPath)\" already exists, not overwriting")
            return .fileExists
        }

        let reader: RNIDByteReader
        do {
            reader = try fileSystem.makeReader(atPath: rfePath)
        } catch {
            output.line("\nError reading \(rfePath) for decryption: \(error)")
            return .writeError
        }

        do {
            let writer = try fileSystem.makeWriter(atPath: decryptPath)
            try RNIDFileCrypto.decryptStream(identity: identity, reader: reader, writer: writer) { wrote in
                self.output.partial("\rWrote \(RNSUtilities.prettysize(wrote)) to \(decryptPath)   ")
            }
        } catch is RNIDFileCrypto.CryptoError {
            // Python's `if not decrypted:` cannot distinguish causes, so every crypto failure
            // lands on R_DECRYPT_FAILED (12).
            output.line("The provided identity could not decrypt the file")
            return .decryptFailed
        } catch {
            output.line("\nError writing decrypted output to \(decryptPath): \(error)")
            return .writeError
        }

        output.line("\nFile \(rfePath) decrypted to \(decryptPath)")
        return .ok
    }

    // MARK: - -w / --write

    /// Python: `write_identity` (rnid.py:946-964).
    ///
    /// `-w` **without** `-X` always writes the public key with a forced `.pub` extension.
    @discardableResult
    public func writeIdentity(path: String, exportPrivate: Bool) -> RNIDApp.Result {
        guard let identity else { return .noIdentity }
        var writePath = fileSystem.expandTilde(path)

        do {
            if identity.hasPrivateKey, exportPrivate {
                if !fileSystem.fileExists(atPath: writePath) || options.force {
                    guard let privateKey = identity.getPrivateKey() else { return .noKeys }
                    try fileSystem.writeData(privateKey, atPath: writePath)
                    output.line("Wrote private identity to " + writePath)
                } else {
                    output.line("File " + writePath + " already exists, not overwriting")
                    return .fileExists
                }
            } else {
                // Case-INSENSITIVE test, lowercase suffix appended.
                if !writePath.lowercased().hasSuffix(".\(RNIDApp.pubExt)") {
                    writePath += ".\(RNIDApp.pubExt)"
                }
                if !fileSystem.fileExists(atPath: writePath) || options.force {
                    try fileSystem.writeData(identity.getPublicKey(), atPath: writePath)
                    output.line("Wrote public identity to " + writePath)
                } else {
                    output.line("File " + writePath + " already exists, not overwriting")
                    return .fileExists
                }
            }
            // Python's final `else: print("Identity holds neither a public nor private key");
            // exit(R_NO_KEYS)` is unreachable in Swift.
            return .ok
        } catch {
            output.line("Error while writing imported identity to file: \(error)")
            return .writeError
        }
    }
}
