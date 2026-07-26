import Foundation

/// Where the operating identity comes from. Python: the `-g`/`-i`/`-m`/`-M` ladder in
/// `get_operating_identity` (rnid.py:202-370). `validate_args` has already made these
/// mutually exclusive by the time the resolver runs.
public enum RNIDIdentitySource: Equatable {
    /// Python: `-g`/`--generate <path>`. The path is deliberately **not** tilde-expanded.
    case generate(path: String, force: Bool)
    /// Python: `-i`/`--identity <value>` — either a path to an Identity file or a 32-character
    /// hex hash. Which one it is is decided at resolve time, exactly as Python decides it.
    case identityArgument(String)
    /// Python: `-m`/`--import-pub <value>`.
    case importPublic(String)
    /// Python: `-M`/`--import-prv <value>`.
    case importPrivate(String)
    /// No identity flag was given at all.
    case none
}

/// `get_operating_identity` (rnid.py:202-370).
///
/// Every Python `exit(R_*)` becomes a `.failure(RNIDApp.Result)`; every `print` goes through
/// the injected ``RNIDOutput``. The `-R` spin loop is behind ``RNIDPathWaiter`` so tests can
/// supply an instant stub and never reach `Transport.awaitPath`, which busy-waits.
public final class RNIDIdentityResolver {

    private let transport: Transport?
    private let reticulum: Reticulum?
    private let output: RNIDOutput
    private let fileSystem: RNIDFileSystem
    private let pathWaiter: RNIDPathWaiter?

    /// Python: `RNS.Reticulum.TRUNCATED_HASHLENGTH//8*2` = 32 hex characters.
    public static let hashStringLength: Int = Constants.truncatedHashLength * 2

    /// Python: `prvsize = pubsize = RNS.Identity.KEYSIZE//8` = 64.
    public static let keyBlobSize: Int = Constants.keySize

    public init(transport: Transport?,
                reticulum: Reticulum? = nil,
                output: RNIDOutput,
                fileSystem: RNIDFileSystem,
                pathWaiter: RNIDPathWaiter? = nil) {
        self.transport = transport
        self.reticulum = reticulum
        self.output = output
        self.fileSystem = fileSystem
        self.pathWaiter = pathWaiter
    }

    // MARK: - Entry point

    /// Python: `get_operating_identity(args, allow_none, no_cache)`.
    ///
    /// A `.success(nil)` is Python's `return None` — legal only when `allowNone`, which
    /// `main` derives from `op_requires_identity`.
    public func resolve(source: RNIDIdentitySource,
                        allowNone: Bool = false,
                        noCache: Bool = false,
                        request: Bool = false,
                        timeout: TimeInterval = Transport.pathRequestTimeout)
    -> Swift.Result<Identity?, RNIDApp.Result> {

        switch source {
        case .none:
            return .success(nil)
        case .generate(let path, let force):
            return generate(path: path, force: force)
        case .identityArgument(let value):
            return resolveIdentityArgument(value, allowNone: allowNone, noCache: noCache,
                                           request: request, timeout: timeout)
        case .importPublic(let value):
            return importIdentity(value, isPrivate: false)
        case .importPrivate(let value):
            return importIdentity(value, isPrivate: true)
        }
    }

    // MARK: - -g / --generate

    /// Python: rnid.py:206-214.
    ///
    /// Note the identity is constructed **before** the file check, and note that `-g` is the
    /// one input path Python never runs through `os.path.expanduser` — `rnid -g ~/x.rid`
    /// creates a literal file named `~/x.rid` in the working directory. Reproduced.
    private func generate(path: String, force: Bool) -> Swift.Result<Identity?, RNIDApp.Result> {
        let identity = Identity()

        if !force && fileSystem.fileExists(atPath: path) {
            output.line("Identity file \(path) already exists. Not overwriting.")
            return .failure(.fileExists)
        }

        guard let privateKey = identity.privateKeyBytes else {
            // Unreachable: a freshly constructed Identity always holds a private key.
            output.line("An error ocurred while saving the generated Identity: no private key")
            return .failure(.writeError)
        }
        do {
            try fileSystem.writeData(privateKey, atPath: path)
        } catch {
            // Python's misspelling "ocurred" is deliberate — three sites in rnid.py.
            output.line("An error ocurred while saving the generated Identity: \(error)")
            return .failure(.writeError)
        }
        output.line("New identity \(RNIDRender.identity(identity)) written to \(path)")
        return .success(identity)
    }

    // MARK: - -i / --identity

    /// Python: rnid.py:216-276.
    private func resolveIdentityArgument(_ value: String,
                                         allowNone: Bool,
                                         noCache: Bool,
                                         request: Bool,
                                         timeout: TimeInterval)
    -> Swift.Result<Identity?, RNIDApp.Result> {

        let loadPath = fileSystem.expandTilde(value)

        // 1. A loadable Identity file wins outright.
        if fileSystem.fileExists(atPath: loadPath) {
            do {
                let blob = try fileSystem.readData(atPath: loadPath)
                // Python's from_file → load_private_key accepts ANY 64 bytes, so pointing -i
                // at a 64-byte .pub file silently yields a WRONG identity rather than an
                // error. Swift's Identity(privateKeyBytes:) only length-checks too, so the
                // quirk ports for free — do not "fix" it or -i behaviour diverges.
                let identity = try Identity(privateKeyBytes: blob)
                output.line("Loaded Identity \(RNIDRender.identity(identity)) from \(loadPath)")
                return .success(identity)
            } catch {
                output.line("Could not load Identity from specified file: \(error)")
                return .failure(.invalidIdentity)
            }
        }

        // 2. -N disables cache and network lookup entirely — checked BEFORE any recall.
        if noCache {
            if allowNone { return .success(nil) }
            output.line("Could not resolve identity")
            return .failure(.noIdentity)
        }

        // 3. A 32-character hex hash is recalled.
        guard value.count == RNIDIdentityResolver.hashStringLength else {
            // Python silently falls through returning None.
            return .success(nil)
        }
        return recall(hexHash: value, allowNone: allowNone, request: request, timeout: timeout)
    }

    /// Python: rnid.py:235-276 — `RNS.Identity.recall(h) or RNS.Identity.recall(h, from_identity_hash=True)`.
    private func recall(hexHash: String,
                        allowNone: Bool,
                        request: Bool,
                        timeout: TimeInterval)
    -> Swift.Result<Identity?, RNIDApp.Result> {

        guard let requestedHash = RNIDEncoding.hexDecode(hexHash) else {
            output.line("Invalid hexadecimal hash provided: non-hexadecimal number found in fromhex() arg")
            return .failure(.invalidIdentity)
        }

        var identity = recallEitherWay(requestedHash)

        if identity == nil {
            if allowNone && !request { return .success(nil) }
            guard request else {
                output.line("Could not recall Identity for \(RNSUtilities.prettyhexrep(requestedHash)).")
                output.line("You can query the network for unknown Identities with the -R option.")
                return .failure(.noIdentity)
            }

            // Cover both interpretations of the supplied hash, exactly as Python does.
            guard let transport else {
                output.line("Invalid hexadecimal hash provided: no Reticulum instance available")
                return .failure(.invalidIdentity)
            }
            // Python's Transport.request_path does not raise; Swift's throws and silently
            // returns for a hash whose length != 16. Treat a throw as rnid.py:276's catch-all.
            do {
                try transport.requestPath(for: requestedHash)
                if let identityDestination = RNIDDestinationHash.hash(fromFullName: RNIDApp.defaultAspects,
                                                                     identityHash: requestedHash) {
                    try transport.requestPath(for: identityDestination)
                }
            } catch {
                output.line("Invalid hexadecimal hash provided: \(error)")
                return .failure(.invalidIdentity)
            }

            let message = "Requesting unknown Identity for \(RNSUtilities.prettyhexrep(requestedHash))"
            // Python DISCARDS spin()'s return value and re-invokes the predicate itself
            // (rnid.py:259) — so must we, or a waiter that returns true on a spurious wake
            // would report a recall that never happened.
            _ = pathWaiter?.wait(until: { self.recallEitherWay(requestedHash) != nil },
                                 message: message,
                                 timeout: timeout)

            guard let received = recallEitherWay(requestedHash) else {
                output.line("Identity request timed out")
                return allowNone ? .success(nil) : .failure(.noIdentity)
            }
            identity = received
            output.line("Received Identity \(RNIDRender.identity(received)) for destination "
                        + "\(RNSUtilities.prettyhexrep(requestedHash)) from the network")
        } else if let identity {
            let identString = RNIDRender.identity(identity)
            let hashString = RNSUtilities.prettyhexrep(requestedHash)
            if identString == hashString {
                output.line("Recalled Identity \(identString)")
            } else {
                output.line("Recalled Identity \(identString) for destination \(hashString)")
            }
        }

        // Python: `if identity and identity.hash: reticulum._retain_identity(identity.hash)`,
        // shared by BOTH the cached-hit and network-received branches.
        if let identity {
            if let reticulum {
                _ = reticulum.retainIdentity(identity.hash)
            } else {
                _ = transport?.retainIdentity(identity.hash)
            }
        }
        return .success(identity)
    }

    /// Python: `RNS.Identity.recall(h) or RNS.Identity.recall(h, from_identity_hash=True)`
    /// (RNS/Identity.py:115-158).
    ///
    /// The destination-hash form has two lookups, not one: `known_destinations`, then a scan
    /// of `Transport.destinations` for a locally-registered destination whose hash matches.
    /// Both branches also call `_used_destination_data`, which is why
    /// `Transport.markDestinationUsed` is invoked here.
    private func recallEitherWay(_ hash: Data) -> Identity? {
        guard let transport else { return nil }

        // (a) Known destination.
        if let identity = transport.recall(identity: hash) {
            transport.markDestinationUsed(hash)
            return identity
        }
        // (b) Locally-registered destination with that hash.
        if let destination = transport.registeredDestinations[hash], let identity = destination.identity {
            transport.markDestinationUsed(hash)
            return identity
        }
        // (c) from_identity_hash=True — scan for an identity whose own hash matches.
        for (destinationHash, identity) in transport.knownIdentities where identity.hash == hash {
            transport.markDestinationUsed(destinationHash)
            return identity
        }
        for (_, destination) in transport.registeredDestinations {
            if let identity = destination.identity, identity.hash == hash { return identity }
        }
        return nil
    }

    // MARK: - -m / -M import

    /// Python: rnid.py:282-368.
    ///
    /// The four-step decode ladder is identical for `-m` and `-M`: file → hex → base32 →
    /// base64, each guarded so a failure falls through. Encoded lengths do not collide:
    /// hex(64) = 128, base32(64) = 104, base64(64) = 88.
    private func importIdentity(_ value: String, isPrivate: Bool) -> Swift.Result<Identity?, RNIDApp.Result> {
        let size = RNIDIdentityResolver.keyBlobSize
        var identityBytes: Data?

        // (1) File.
        let importPath = fileSystem.expandTilde(value)
        if fileSystem.fileExists(atPath: importPath),
           let fileInput = try? fileSystem.readData(atPath: importPath),
           fileInput.count == size {
            identityBytes = fileInput
            output.line("Reticulum Identity imported from \(importPath)")
        }

        // (2) Hex.
        if identityBytes == nil, value.count == size * 2, let decoded = RNIDEncoding.hexDecode(value) {
            identityBytes = decoded
            output.line("Reticulum Identity imported from hex input")
        }

        // (3) Base32.
        if identityBytes == nil, let decoded = RNIDEncoding.base32Decode(value), decoded.count == size {
            identityBytes = decoded
            output.line("Reticulum Identity imported from base32 input")
        }

        // (4) Base64 (url-safe).
        if identityBytes == nil, let decoded = RNIDEncoding.base64URLDecode(value), decoded.count == size {
            identityBytes = decoded
            output.line("Reticulum Identity imported from base64 input")
        }

        guard let identityBytes else {
            output.line(isPrivate
                        ? "Could not decode specified data to a valid private Reticulum Identity"
                        : "Could not decode specified data to a valid public Reticulum Identity")
            return .failure(.invalidIdentity)
        }

        do {
            // Python: from_bytes for -M; Identity(create_keys=False) + load_public_key for -m.
            // Swift's INSTANCE methods loadPublicKey/loadPrivateKey return a NEW Identity and
            // do not mutate self, so the inits are the only correct choice here.
            let identity = isPrivate
                ? try Identity(privateKeyBytes: identityBytes)
                : try Identity(publicKeyBytes: identityBytes)
            return .success(identity)
        } catch {
            output.line("Could not create Reticulum identity from specified data: \(error)")
            return .failure(.invalidIdentity)
        }
    }
}
