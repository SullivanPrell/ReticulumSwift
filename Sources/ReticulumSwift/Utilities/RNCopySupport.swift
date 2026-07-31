import Foundation

// MARK: - rncp support types
//
// Pure, terminal-free, network-free helpers for the `rncp` file-transfer utility.
// Python reference: `RNS/Utilities/rncp.py` (Reticulum File Transfer Utility).
//
// Everything in this file is either a constant, a pure function, or takes the
// ``RNCopyFileSystem`` seam, so the whole surface is drivable from XCTest with no
// terminal and no live network. Terminal control (ANSI erase, Braille spinner,
// `isatty`, SIGINT) lives in `Sources/rncp/main.swift`.
//
// The existing `RNCopyApp` enum (appName / reqFetchNotAllowed) is extended here
// rather than edited in place, so `RNCopyApp.swift` stays untouched.

// MARK: - Constants

public extension RNCopyApp {

    /// Request path served by a listener started with `-F/--allow-fetch`.
    /// Python: `destination.register_request_handler("fetch_file", …)` (rncp.py:216,218).
    static let fetchRequestPath: String = "fetch_file"

    /// Wire key for the fetch handler: `truncated_hash(b"fetch_file")`.
    /// Equals `4ce505754cbdc8c2c8775a3006a712f0`.
    static var fetchRequestPathHash: Data { Hashes.truncatedHash(Data(fetchRequestPath.utf8)) }

    /// Single aspect of the rncp destination — full name `rncp.receive.<identity hash>`.
    /// Python: `RNS.Destination(identity, IN, SINGLE, APP_NAME, "receive")` (rncp.py:112).
    static let receiveAspect: String = "receive"

    /// Basename of the default identity file, `<configdir>/storage/identities/rncp`.
    /// Python: `identity_path = RNS.Reticulum.identitypath+"/"+APP_NAME` (rncp.py:57).
    static let identityFileName: String = appName

    /// Name of the on-disk allow-list. Python: `allowed_file_name` (rncp.py:124).
    static let allowedIdentitiesFileName: String = "allowed_identities"

    /// Number of hex characters in an identity/destination hash argument.
    /// Python: `dest_len = (RNS.Reticulum.TRUNCATED_HASHLENGTH//8)*2` → 32 (rncp.py:122).
    static let destinationHexLength: Int = Constants.truncatedHashLength * 2

    /// Rolling-window sample cap of the transfer-rate meter.
    /// Python: `stats_max = 32` (rncp.py:325).
    static let statsMax: Int = 32

    /// Braille spinner alphabet, advanced modulo 7 every 0.1 s.
    /// Python: `syms = "⢄⢂⢁⡁⡈⡐⡠"` (rncp.py:403).
    static let spinnerFrames: [Character] = Array("⢄⢂⢁⡁⡈⡐⡠")

    /// ANSI "erase entire line, carriage return".
    /// Python: `erase_str = "\33[2K\r"` (rncp.py:73).
    static let eraseString: String = "\u{1B}[2K\r"

    /// Single space appended by `print(end=es)` in the progress loops.
    /// Python: `es = " "` (rncp.py:72). NOTE `send`'s inner `progress_update`
    /// deliberately shadows this with a two-space local (rncp.py:754).
    static let endSpace: String = " "

    /// Ordered candidate locations of the allow-list file; first hit wins.
    /// Python: rncp.py:126-131.
    static func allowedIdentitiesSearchPaths(home: String) -> [String] {
        ["/etc/rncp/\(allowedIdentitiesFileName)",
         "\(home)/.config/rncp/\(allowedIdentitiesFileName)",
         "\(home)/.rncp/\(allowedIdentitiesFileName)"]
    }

    /// Process exit codes used by rncp.
    ///
    /// Python calls `RNS.exit(n)` / `sys.exit(n)` with these values. Note that every
    /// *failed fetch request* outcome deliberately exits 0 (rncp.py:547,553,559,565).
    enum Result: UInt8, Equatable, CaseIterable {
        /// File copied / fetched, identity printed, help printed, SIGINT.
        case ok = 0
        /// Bad destination string, bad `-a` entry, local file missing, path not
        /// found, link timeout, resource start failure, transfer failed.
        case generalError = 1
        /// Identity file present but unreadable/corrupt. Python: rncp.py:63.
        case identityError = 2
        /// `--save` directory not found. Python: rncp.py:106.
        case outputDirNotFound = 3
        /// `--save` directory not writable. Python: rncp.py:103.
        case outputDirNotWritable = 4

        public var code: Int32 { Int32(rawValue) }
    }
}

// MARK: - Formatting

public extension RNCopyApp {

    /// rncp's own `size_str`. Python: rncp.py:887-904.
    ///
    /// Identical to the `size_str` in rnstatus.py and rnx.py, and therefore already
    /// implemented byte-for-byte by ``UtilityFormatting/sizeStr(_:suffix:)`` — including
    /// the quirk that the terminal yotta branch omits the space (`"1.00YB"`) while every
    /// other branch keeps it. Deliberately *not* `RNSUtilities.prettysize`.
    static func sizeStr(_ num: Double, suffix: String = "B") -> String {
        UtilityFormatting.sizeStr(num, suffix: suffix)
    }

    /// `Int` convenience overload.
    static func sizeStr(_ num: Int, suffix: String = "B") -> String {
        UtilityFormatting.sizeStr(Double(num), suffix: suffix)
    }

    /// A transfer rate, rendered exactly as rncp composes it: the *byte* rate is
    /// converted to bits by `size_str`'s `'b'` branch and the literal `"ps"` is
    /// appended by the f-string. Python: rncp.py:582,589,757.
    static func speedStr(_ bytesPerSecond: Double) -> String {
        sizeStr(bytesPerSecond, suffix: "b") + "ps"
    }

    /// The `<pct>% - <cur> of <tot>[ in <time>] - <rate>ps[ (<phy>ps at physical layer)]`
    /// line shared by the send and fetch progress displays.
    ///
    /// Python: rncp.py:583 / 590 (fetch) and rncp.py:758 (send). `elapsed` is non-nil
    /// only for the fetch-mode "Transfer complete" line, which inserts the elapsed time
    /// and shows the *average* rate. `phySpeed` is non-nil only under `-P/--phy-rates`
    /// (send additionally suppresses it once the transfer is done — that gate belongs to
    /// the caller, which simply passes `nil`).
    static func transferStat(progress: Double,
                             totalSize: Int,
                             speed: Double,
                             phySpeed: Double? = nil,
                             elapsed: TimeInterval? = nil) -> String {
        // Python: percent = round(prg * 100.0, 1), then f-string interpolation of the
        // float — "0.0" / "33.3" / "100.0". %.1f matches for every practical value.
        let percent = String(format: "%.1f", progress * 100.0)
        let current = sizeStr(Double(Int(progress * Double(totalSize))))
        let total = sizeStr(Double(totalSize))
        let rate = sizeStr(speed, suffix: "b")
        let phy = phySpeed.map { " (\(sizeStr($0, suffix: "b"))ps at physical layer)" } ?? ""
        if let elapsed {
            let dt = RNSUtilities.prettytime(elapsed)
            return "\(percent)% - \(current) of \(total) in \(dt) - \(rate)ps\(phy)"
        }
        return "\(percent)% - \(current) of \(total) - \(rate)ps\(phy)"
    }
}

// MARK: - Path helpers (posixpath semantics)

public extension RNCopyApp {

    /// `os.path.basename` for POSIX: `p[p.rfind('/')+1:]`.
    ///
    /// Splits on `/` only — a backslash is an ordinary character — and yields `""` for
    /// both `"a/b/"` and `""`. Reproducing the exact rule is what collapses a hostile
    /// `"../../etc/passwd"` to `"passwd"`. Python: rncp.py:287,496,640,200.
    static func basename(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }

    /// `os.path.expanduser` against `rncp`'s injected home.
    ///
    /// Delegates to the one implementation every utility uses, rather than keeping a second copy
    /// of the same rules — `bugs/024` is what happens when path resolution exists in more than
    /// one place. See ``InstanceConnection/expandTilde(_:home:)``.
    static func expandUser(_ path: String, home: String) -> String {
        InstanceConnection.expandTilde(path, home: home)
    }

    /// `os.path.abspath` — join against `cwd` when relative, then `normpath`.
    ///
    /// This is **lexical**: it does not resolve symlinks, exactly like Python. Both the
    /// fetch jail and the save-path containment check rely on that, so a symlink inside
    /// a jail that points outside it defeats the jail — in Python and here alike. Do not
    /// "harden" this with `resolvingSymlinksInPath`; it would diverge from the Python
    /// listener. Python: rncp.py:93,97,180,185,290,499.
    static func absolutePath(_ path: String, cwd: String) -> String {
        var joined = path
        if !joined.hasPrefix("/") {
            joined = cwd.hasSuffix("/") ? cwd + joined : cwd + "/" + joined
        }
        let isAbsolute = joined.hasPrefix("/")
        var components: [String] = []
        for component in joined.split(separator: "/", omittingEmptySubsequences: true).map(String.init) {
            if component == "." { continue }
            if component == ".." {
                if let last = components.last, last != ".." {
                    components.removeLast()
                } else if !isAbsolute {
                    components.append("..")
                }
                // Absolute paths: ".." at the root is absorbed, as normpath does.
                continue
            }
            components.append(component)
        }
        let body = components.joined(separator: "/")
        if isAbsolute { return "/" + body }
        return body.isEmpty ? "." : body
    }
}

// MARK: - Resource metadata (filename transport)

public extension RNCopyApp {

    /// The metadata map that carries the filename with a resource.
    ///
    /// Python: `metadata = {"name": os.path.basename(file_path).encode("utf-8")}`
    /// (rncp.py:200,640). `RNS.Resource` packs it with umsgpack and prefixes a 3-byte
    /// big-endian length; `Resource.init` / `ResourceTransfer.assemble` already handle
    /// that framing on this side, so only the map itself is built here.
    ///
    /// For `"test.txt"` the bytes are
    /// `81 a4 6e 61 6d 65 c4 08 74 65 73 74 2e 74 78 74`.
    static func encodeMetadata(name: String) -> Data {
        MsgPack.encode(.map([(.string("name"), .bytes(Data(name.utf8)))]))
    }

    /// Recover the filename from a resource's metadata block.
    ///
    /// Python does `resource.metadata["name"].decode("utf-8")` and therefore requires a
    /// msgpack *bin*; a msgpack *str* is accepted here too, so a peer that used a string
    /// still interoperates. Returns nil for anything else (Python would raise, and the
    /// caller reports "An error occurred while saving received resource").
    static func decodeMetadataName(_ packed: Data) -> String? {
        guard let value = try? MsgPack.decode(packed),
              let map = value.asDictionary,
              let name = map["name"] else { return nil }
        if let bytes = name.asData { return String(data: bytes, encoding: .utf8) }
        return name.asString
    }
}

// MARK: - Allowed identities

public extension RNCopyApp {

    /// Parse an `allowed_identities` file body.
    ///
    /// Python: strip every `\r`, split on `\n`, and keep ONLY lines whose length is
    /// exactly `dest_len` (32). Lines are not hex-validated here; comments and blank
    /// lines are silently dropped by the length filter. Python: rncp.py:133-139.
    static func parseAllowedIdentitiesFile(_ contents: String) -> [String] {
        contents
            .replacingOccurrences(of: "\r", with: "")
            .components(separatedBy: "\n")
            .filter { $0.count == destinationHexLength }
    }

    /// Rejection reasons for an `-a` / allow-list entry. The messages are the exact
    /// `ValueError` texts Python raises (rncp.py:159,164) and prints.
    enum AllowedIdentityError: Swift.Error, Equatable, CustomStringConvertible {
        case invalidLength(String)
        case invalidHex(String)

        public var message: String {
            switch self {
            case .invalidLength:
                return "Allowed destination length is invalid, must be \(RNCopyApp.destinationHexLength) hexadecimal characters (\(RNCopyApp.destinationHexLength / 2) bytes)."
            case .invalidHex:
                return "Invalid destination entered. Check your input."
            }
        }

        public var description: String { message }
    }

    /// Validate and decode one allow-list entry into a raw 16-byte identity hash.
    ///
    /// The hashes compared at runtime are IDENTITY hashes (`Identity.hash`), not
    /// destination hashes. Python: rncp.py:155-167.
    static func decodeAllowedIdentity(_ hex: String) throws -> Data {
        guard hex.count == destinationHexLength else {
            throw AllowedIdentityError.invalidLength(hex)
        }
        guard let data = Data(hex: hex), data.count == Constants.truncatedHashLength else {
            throw AllowedIdentityError.invalidHex(hex)
        }
        return data
    }

    /// The outcome of locating, parsing and merging the `allowed_identities` file with the
    /// `-a` entries. Python: rncp.py:122-150.
    struct AllowedIdentitiesLoad: Equatable {
        /// The `-a` entries merged with the file entries, in Python's order.
        public let merged: [String]
        /// How many entries the FILE contributed — this, not the merged count, is what the
        /// log line reports.
        public let fileEntryCount: Int
        /// The file that was read, or nil when none of the three candidates existed.
        public let sourcePath: String?
        /// The text of any exception caught while locating/reading the file. Python catches
        /// everything, logs it at ERROR, and continues without exiting.
        public let failure: String?

        /// `Loaded <N> allowed identit{y|ies} from <path>`, or nil when no file was found.
        ///
        /// Note the plural is computed from the FILE entries only, and Python emits the line
        /// even when the count is zero (in which case the suffix is "ies").
        public var logMessage: String? {
            guard let sourcePath else { return nil }
            return "Loaded \(fileEntryCount) allowed identit\(fileEntryCount == 1 ? "y" : "ies") from \(sourcePath)"
        }
    }

    /// Locate, parse and merge the allow-list. Python: rncp.py:122-153.
    ///
    /// The file entries REPLACE the `-a` list when it is empty, and are appended otherwise
    /// (`allowed.extend(ali)`). Only the first existing candidate is read.
    ///
    /// This is skipped entirely by `-n/--no-auth`, which is why no file is read in that mode.
    static func loadAllowedIdentities(commandLineEntries: [String],
                                      fileSystem: RNCopyFileSystem) -> AllowedIdentitiesLoad {
        let candidates = allowedIdentitiesSearchPaths(home: fileSystem.homeDirectoryPath)
        guard let path = candidates.first(where: { fileSystem.fileExists(atPath: $0) }) else {
            return AllowedIdentitiesLoad(merged: commandLineEntries, fileEntryCount: 0,
                                         sourcePath: nil, failure: nil)
        }

        do {
            let bytes = try fileSystem.readFile(atPath: path)
            let contents = String(data: bytes, encoding: .utf8) ?? ""
            let fromFile = parseAllowedIdentitiesFile(contents)

            var merged = commandLineEntries
            if !fromFile.isEmpty {
                if merged.isEmpty { merged = fromFile } else { merged.append(contentsOf: fromFile) }
            }
            return AllowedIdentitiesLoad(merged: merged, fileEntryCount: fromFile.count,
                                         sourcePath: path, failure: nil)
        } catch {
            // Python logs "Error while parsing allowed_identities file. The contained
            // exception was: <e>" at ERROR and carries on with just the -a entries.
            return AllowedIdentitiesLoad(merged: commandLineEntries, fileEntryCount: 0,
                                         sourcePath: nil, failure: "\(error)")
        }
    }

    /// Validate the `destination` positional shared by fetch and send.
    ///
    /// Identical rules to ``decodeAllowedIdentity(_:)`` — Python literally repeats the
    /// block (rncp.py:377-387, 622-632) — and the raised message is printed with a plain
    /// `print()` before `exit(1)`.
    static func decodeDestinationArgument(_ hex: String) throws -> Data {
        try decodeAllowedIdentity(hex)
    }
}

// MARK: - Fetch response classification

/// How a fetch client classifies the scalar response to its `fetch_file` request.
/// Python: `request_status` (rncp.py:456-477).
public enum RNCopyFetchStatus: String, Equatable, CaseIterable {
    case found
    case notFound = "not_found"
    case remoteError = "remote_error"
    case fetchNotAllowed = "fetch_not_allowed"
    case unknown
}

public extension RNCopyApp {

    /// Classify a `fetch_file` response payload.
    ///
    /// Python compares the unpacked response in this order (rncp.py:461-472):
    /// `== False` → not_found; `== None` → remote_error; `== REQ_FETCH_NOT_ALLOWED`
    /// → fetch_not_allowed; else → found. Because Python treats `0 == False`, an integer
    /// zero also lands in not_found; `True == 1` never equals 240 so it lands in found.
    ///
    /// `Link.handleIncomingResponse` re-encodes a non-bytes response element with
    /// `MsgPack.encode`, so the payload handed to the callback is the msgpack encoding of
    /// the scalar. An undecodable payload falls through to `.found`, matching Python's
    /// else-branch.
    static func classifyFetchResponse(_ payload: Data) -> RNCopyFetchStatus {
        guard let value = try? MsgPack.decode(payload) else { return .found }
        if case .bool(let flag) = value { return flag ? .found : .notFound }
        if let number = value.asInt {
            if number == 0 { return .notFound }                                  // Python: 0 == False
            if number == Int(reqFetchNotAllowed) { return .fetchNotAllowed }      // 0xF0
            return .found
        }
        if value.isNil { return .remoteError }
        return .found
    }
}

// MARK: - File-system seam

/// The disk operations rncp performs, injected so the listener, sender and fetcher can be
/// unit-tested without touching a real file system.
public protocol RNCopyFileSystem: AnyObject {
    /// `os.path.expanduser("~")`.
    var homeDirectoryPath: String { get }
    /// `os.getcwd()` — the base for `os.path.abspath` on a relative path.
    var currentDirectoryPath: String { get }
    /// `os.path.isfile` — true only for an existing *regular* file.
    func fileExists(atPath path: String) -> Bool
    /// `os.path.isdir`.
    func isDirectory(atPath path: String) -> Bool
    /// `os.access(path, os.W_OK)` on a directory.
    func isWritableDirectory(atPath path: String) -> Bool
    func readFile(atPath path: String) throws -> Data
    func writeFile(_ data: Data, toPath path: String) throws
    /// `os.unlink`.
    func removeFile(atPath path: String) throws
}

/// `RNCopyFileSystem` backed by `FileManager`.
public final class RNCopyDiskFileSystem: RNCopyFileSystem {

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    /// `rncp`'s identity store and its `~/.rncp` allow-list hang off this.
    ///
    /// Resolved through the shared `$HOME`-aware resolver, not `NSHomeDirectory()`, which reports
    /// the account's real home regardless of `$HOME`. Applying the wrong allow-list silently
    /// accepts identities the operator never authorised for that environment — or refuses the
    /// ones they did — behind a normal-looking banner (`bugs/024`).
    public var homeDirectoryPath: String {
        InstanceConnection.homeDirectory(environment: environment).path
    }

    public var currentDirectoryPath: String {
        FileManager.default.currentDirectoryPath
    }

    public func fileExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && !isDirectory.boolValue
    }

    public func isDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    public func isWritableDirectory(atPath path: String) -> Bool {
        FileManager.default.isWritableFile(atPath: path)
    }

    public func readFile(atPath path: String) throws -> Data {
        // Memory-mapped where safe: `ResourceTransfer.send` needs the whole payload in
        // memory, so this at least avoids one full copy for large files.
        try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
    }

    public func writeFile(_ data: Data, toPath path: String) throws {
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    public func removeFile(atPath path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }
}

// MARK: - Fetch-jail resolution

/// The outcome of resolving a client-requested fetch path against the listener's jail.
///
/// The associated paths are carried so callers can reproduce Python's log lines verbatim
/// (`"Disallowing fetch request for <path> outside of fetch jail <jail>"` and
/// `"Client-requested file not found: <path>"`).
public enum RNCopyFetchResolution: Equatable {
    /// Resolved outside the jail. Python returns `REQ_FETCH_NOT_ALLOWED` (0xF0).
    case notAllowed(path: String)
    /// Inside the jail (or unjailed) but not an existing regular file. Python returns `False`.
    case notFound(path: String)
    /// Serve this absolute path. Python constructs an ordinary Resource and returns `True`.
    case serve(path: String)
}

public extension RNCopyApp {

    /// Resolve a `fetch_file` request path. Python: `fetch_request` (rncp.py:172-209).
    ///
    /// With a jail: if the request already starts with `<jail>/`, Python strips it with
    /// `data.replace(fetch_jail+"/", "")` — a replace-**ALL**, not a prefix drop, so every
    /// occurrence anywhere in the string disappears. The remainder is re-joined under the
    /// jail and lexically absolutised; a result that does not start with `<jail>/` is
    /// rejected. Without a jail the client may request any absolute path the listener
    /// process can read.
    static func resolveFetchPath(requested: String,
                                 jail: String?,
                                 fileSystem: RNCopyFileSystem) -> RNCopyFetchResolution {
        let home = fileSystem.homeDirectoryPath
        let cwd = fileSystem.currentDirectoryPath
        let filePath: String

        if let jail {
            var data = requested
            if data.hasPrefix(jail + "/") {
                // Python: data = data.replace(fetch_jail+"/", "")  ← replace-ALL
                data = data.replacingOccurrences(of: jail + "/", with: "")
            }
            filePath = absolutePath(expandUser("\(jail)/\(data)", home: home), cwd: cwd)
            guard filePath.hasPrefix(jail + "/") else { return .notAllowed(path: filePath) }
        } else {
            filePath = absolutePath(expandUser(requested, home: home), cwd: cwd)
        }

        guard fileSystem.fileExists(atPath: filePath) else { return .notFound(path: filePath) }
        return .serve(path: filePath)
    }
}

// MARK: - Save-target resolution

/// Where a received resource should be written.
public enum RNCopySaveResolution: Equatable {
    /// The name escaped `--save`; Python logs "Invalid save path <path>, ignoring" and drops it.
    case rejected(path: String)
    /// Write here. `unlinkFirst` names the file that `-O/--overwrite` actually removed.
    case write(path: String, unlinkFirst: String?)
}

public extension RNCopyApp {

    /// Resolve the on-disk target for a received file. Python: rncp.py:287-306 (listen)
    /// and rncp.py:496-515 (fetch) — the two blocks are identical apart from log vs print.
    ///
    /// - With `--save`, the target is `abspath(expanduser(save + "/" + filename))` and must
    ///   start with `save + "/"`. Without it the target is the bare filename, i.e. a
    ///   **relative** path — the file lands in the process working directory.
    /// - With `-O` the existing file is unlinked first; if the unlink throws, Python logs
    ///   "…renaming instead" and falls through.
    /// - Unconditionally afterwards, collisions become `name.1`, `name.2`, …
    ///
    /// - Parameter onOverwriteFailure: invoked with the path when `-O` was requested but
    ///   the unlink failed, so the caller can emit Python's message.
    static func resolveSaveTarget(filename: String,
                                  savePath: String?,
                                  allowOverwrite: Bool,
                                  fileSystem: RNCopyFileSystem,
                                  onOverwriteFailure: ((String) -> Void)? = nil) -> RNCopySaveResolution {
        let savedFilename: String
        if let savePath {
            savedFilename = absolutePath(expandUser(savePath + "/" + filename,
                                                    home: fileSystem.homeDirectoryPath),
                                         cwd: fileSystem.currentDirectoryPath)
            guard savedFilename.hasPrefix(savePath + "/") else {
                return .rejected(path: savedFilename)
            }
        } else {
            savedFilename = filename
        }

        var unlinkFirst: String?
        var fullSavePath = savedFilename

        if allowOverwrite, fileSystem.fileExists(atPath: fullSavePath) {
            do {
                try fileSystem.removeFile(atPath: fullSavePath)
                unlinkFirst = fullSavePath
            } catch {
                onOverwriteFailure?(fullSavePath)
            }
        }

        var counter = 0
        while fileSystem.fileExists(atPath: fullSavePath) {
            counter += 1
            fullSavePath = savedFilename + "." + String(counter)
        }

        return .write(path: fullSavePath, unlinkFirst: unlinkFirst)
    }
}

// MARK: - Save-directory resolution (`--save`)

/// Result of validating the `--save` argument. Python: rncp.py:96-108 / 365-375.
public enum RNCopySaveDirectory: Equatable {
    case ok(path: String)
    /// "Output directory not found" → exit 3.
    case notFound
    /// "Output directory not writable" → exit 4.
    case notWritable
}

public extension RNCopyApp {

    /// Validate `--save`. Runs *before* `prepare_identity`, so `-p -s /bad` exits 3 or 4
    /// rather than printing the identity. Python: rncp.py:96-108.
    static func resolveSaveDirectory(_ save: String,
                                     fileSystem: RNCopyFileSystem) -> RNCopySaveDirectory {
        let path = absolutePath(expandUser(save, home: fileSystem.homeDirectoryPath),
                                cwd: fileSystem.currentDirectoryPath)
        guard fileSystem.isDirectory(atPath: path) else { return .notFound }
        guard fileSystem.isWritableDirectory(atPath: path) else { return .notWritable }
        return .ok(path: path)
    }
}

// MARK: - Transfer-rate meter

/// The rolling-window rate meter behind rncp's progress line.
/// Python: `sender_progress` (rncp.py:318-356).
public struct RNCopyProgressMeter {

    /// Application-layer bytes per second over the window.
    public private(set) var speed: Double = 0
    /// Physical-layer bytes per second over the window (`-P/--phy-rates`).
    public private(set) var phySpeed: Double = 0

    private var samples: [(time: TimeInterval, got: Double, phyGot: Double)] = []

    public init() {}

    /// Record one sample and recompute the rates.
    ///
    /// - `got` is `get_progress() * get_data_size()`.
    /// - `phyGot` is `get_segment_progress() * get_transfer_size()`.
    ///
    /// A zero span zeroes BOTH rates. Otherwise `speed` is the window delta, while
    /// `phySpeed` is only updated when the physical delta is strictly positive — Python's
    /// `if phy_diff > 0:` leaves the previous value in place rather than zeroing it.
    public mutating func update(now: TimeInterval, got: Double, phyGot: Double) {
        samples.append((now, got, phyGot))
        while samples.count > RNCopyApp.statsMax { samples.removeFirst() }

        let span = now - samples[0].time
        if span == 0 {
            speed = 0
            phySpeed = 0
            return
        }
        speed = (got - samples[0].got) / span
        let phyDiff = phyGot - samples[0].phyGot
        if phyDiff > 0 { phySpeed = phyDiff / span }
    }

    /// Number of retained samples — exposed for tests asserting the 32-entry cap.
    public var sampleCount: Int { samples.count }
}

// MARK: - Identity bootstrap

public extension RNCopyApp {

    /// Failures of ``prepareIdentity(at:)``.
    enum IdentityError: Swift.Error, Equatable, CustomStringConvertible {
        /// The file exists but `Identity.fromFile` returned nil. Python: rncp.py:59-63 → exit 2.
        case corruptIdentityFile(String)

        public var message: String {
            switch self {
            case .corruptIdentityFile(let path):
                return "Could not load identity for rncp. The identity file at \"\(path)\" may be corrupt or unreadable."
            }
        }

        public var description: String { message }
    }

    /// `<storagePath>/identities/rncp` — Python's `RNS.Reticulum.identitypath + "/" + APP_NAME`.
    ///
    /// `Reticulum.start()` creates `storage/` but NOT the `identities/` subdirectory, so
    /// ``prepareIdentity(at:)`` creates it with intermediates before writing.
    static func defaultIdentityPath(storagePath: URL) -> URL {
        StorageInventory.url(.identities, storage: storagePath)
            .appendingPathComponent(identityFileName)
    }

    /// Load, or create and persist, the rncp identity. Python: `prepare_identity` (rncp.py:54-68).
    ///
    /// - Throws: ``IdentityError/corruptIdentityFile(_:)`` when the file is present but
    ///   unreadable — the CLI maps that to exit code 2.
    static func prepareIdentity(at url: URL) throws -> Identity {
        if FileManager.default.fileExists(atPath: url.path) {
            guard let loaded = Identity.fromFile(url) else {
                throw IdentityError.corruptIdentityFile(url.path)
            }
            return loaded
        }
        // Python: RNS.log("No valid saved identity found, creating new...", LOG_INFO)
        Reticulum.log("No valid saved identity found, creating new...", level: .info)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let identity = Identity()
        // Python does not check the to_file result either.
        _ = try? identity.toFile(url)
        return identity
    }

    /// Convenience for the default location under a Reticulum storage directory.
    static func prepareIdentity(storagePath: URL) throws -> Identity {
        try prepareIdentity(at: defaultIdentityPath(storagePath: storagePath))
    }
}

// MARK: - Command-line surface

public extension RNCopyApp {

    /// argparse's `description=`. Python: rncp.py:796.
    static let overview: String = "Reticulum File Transfer Utility"

    /// The `--help` output, byte-identical to Python argparse's.
    ///
    /// ``ArgumentParser/usage`` produces a single-line `usage:` header and a fixed 24-column
    /// help gutter, which does not reproduce argparse's wrapped usage block, its
    /// `-j path, --jail path` metavar repetition, or its 79-column help-text wrapping. The
    /// text is therefore held literally here and asserted against captured Python output in
    /// `RNCopyHelpTextTests`, rather than being generated and drifting.
    static let helpText: String = """
    usage: rncp [-h] [--config path] [-v] [-q] [-S] [-l] [-C] [-F] [-f] [-j path]
                [-s path] [-O] [-b seconds] [-a allowed_hash] [-n] [-p]
                [-i identity] [-w seconds] [-P] [--version]
                [file] [destination]

    Reticulum File Transfer Utility

    positional arguments:
      file                  file to be transferred
      destination           hexadecimal hash of the receiver

    options:
      -h, --help            show this help message and exit
      --config path         path to alternative Reticulum config directory
      -v, --verbose         increase verbosity
      -q, --quiet           decrease verbosity
      -S, --silent          disable transfer progress output
      -l, --listen          listen for incoming transfer requests
      -C, --no-compress     disable automatic compression
      -F, --allow-fetch     allow authenticated clients to fetch files
      -f, --fetch           fetch file from remote listener instead of sending
      -j path, --jail path  restrict fetch requests to specified path
      -s path, --save path  save received files in specified path
      -O, --overwrite       Allow overwriting received files, instead of adding
                            postfix
      -b seconds            announce interval, 0 to only announce at startup
      -a allowed_hash       allow this identity (or add in
                            ~/.rncp/allowed_identities)
      -n, --no-auth         accept requests from anyone
      -p, --print-identity  print identity and destination info and exit
      -i identity           path to identity to use
      -w seconds            sender timeout before giving up
      -P, --phy-rates       display physical layer transfer rates
      --version             show program's version number and exit
    """

    /// The declared argument surface, mirroring `main()`'s parser (rncp.py:796-818).
    ///
    /// `--limit` is deliberately absent: it is commented out upstream in both the parser and
    /// the `listen()` call (rncp.py:817). `-a` is `action="append"` in argparse; the shared
    /// ``ArgumentParser`` has no append action, so it is declared here as an ordinary option
    /// (which makes it consume its value correctly and keeps the positionals right) and the
    /// executable collects every occurrence itself.
    static func makeArgumentParser() -> ArgumentParser {
        var parser = ArgumentParser(program: appName, overview: overview)
        parser.positional("file", help: "file to be transferred", required: false)
        parser.positional("destination", help: "hexadecimal hash of the receiver", required: false)
        parser.option(["--config"], metavar: "path",
                      help: "path to alternative Reticulum config directory")
        parser.counted(["-v", "--verbose"], help: "increase verbosity")
        parser.counted(["-q", "--quiet"], help: "decrease verbosity")
        parser.flag(["-S", "--silent"], help: "disable transfer progress output")
        parser.flag(["-l", "--listen"], help: "listen for incoming transfer requests")
        parser.flag(["-C", "--no-compress"], help: "disable automatic compression")
        parser.flag(["-F", "--allow-fetch"], help: "allow authenticated clients to fetch files")
        parser.flag(["-f", "--fetch"], help: "fetch file from remote listener instead of sending")
        parser.option(["-j", "--jail"], metavar: "path",
                      help: "restrict fetch requests to specified path")
        parser.option(["-s", "--save"], metavar: "path",
                      help: "save received files in specified path")
        parser.flag(["-O", "--overwrite"],
                    help: "Allow overwriting received files, instead of adding postfix")
        parser.option(["-b"], metavar: "seconds",
                      help: "announce interval, 0 to only announce at startup", default: "-1")
        parser.option(["-a"], metavar: "allowed_hash",
                      help: "allow this identity (or add in ~/.rncp/allowed_identities)")
        parser.flag(["-n", "--no-auth"], help: "accept requests from anyone")
        parser.flag(["-p", "--print-identity"], help: "print identity and destination info and exit")
        parser.option(["-i"], metavar: "identity", help: "path to identity to use")
        parser.option(["-w"], metavar: "seconds", help: "sender timeout before giving up",
                      default: String(Int(Transport.pathRequestTimeout)))
        parser.flag(["-P", "--phy-rates"], help: "display physical layer transfer rates")
        parser.flag(["--version"], help: "show program's version number and exit")
        return parser
    }

    /// Collect every occurrence of a repeatable option, reproducing argparse's
    /// `action="append"` for `-a`. Honours `--` the same way ``ArgumentParser`` does.
    static func collectRepeatedOption(_ name: String, in arguments: [String]) -> [String] {
        var values: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--" { break }
            if arguments[index] == name, index + 1 < arguments.count {
                values.append(arguments[index + 1])
                index += 2
                continue
            }
            index += 1
        }
        return values
    }
}

// MARK: - Log level

public extension RNCopyApp {

    /// `targetloglevel = 3 + verbosity - quietness`, clamped into the `LogLevel` range.
    ///
    /// 3 is `RNS.LOG_NOTICE`. `Reticulum.Configuration.logLevel` is stored but never
    /// applied by `start()`, so callers must also assign `Reticulum.globalLogLevel`
    /// (exactly as `Sources/rnsd/main.swift` does). Python: rncp.py:89,361,619.
    static func logLevel(verbosity: Int, quietness: Int) -> Reticulum.LogLevel {
        let raw = max(-1, min(8, 3 + verbosity - quietness))
        return Reticulum.LogLevel(rawValue: raw) ?? .notice
    }
}
