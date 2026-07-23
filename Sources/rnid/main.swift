import Foundation
import ReticulumSwift

// rnid — Reticulum Identity & Encryption Utility.
//
// Python reference: RNS/Utilities/rnid.py.
//
// This target does argument parsing, printing, terminal effects and exit codes only.
// Every behaviour lives in ReticulumSwift's RNID* types so it stays testable, and so the
// library keeps building for tvOS and watchOS — `Foundation.Process` (the editor) and
// POSIX signals (SIGINT) are the two things that cannot cross that line.

// MARK: - Terminal output

/// Python: bare `print()` / `print(..., end="")`. No colour, no ANSI, nothing on stderr.
final class TerminalOutput: RNIDOutput {
    func line(_ text: String) {
        print(text)
    }

    func partial(_ text: String) {
        print(text, terminator: "")
        fflush(stdout)
    }
}

// MARK: - Editor

/// Python: `get_editor_content()` (rnid.py:1034-1059).
///
/// Reads `$EDITOR`, falling back to `nano`, `vim`, `vi` in that order, writes an empty
/// template to a temporary file, runs the editor on it and returns the result as UTF-8 bytes.
final class ProcessEditor: RNIDEditor {
    enum EditorError: Error, CustomStringConvertible {
        case noEditor
        case exited(Int32)

        var description: String {
            switch self {
            case .noEditor:          return "Could not launch editor"
            case .exited(let code):  return "Editor exited with error code \(code)"
            }
        }
    }

    func composeMessage() throws -> Data {
        var editor = ProcessInfo.processInfo.environment["EDITOR"] ?? ""
        if editor.isEmpty {
            for fallback in ["nano", "vim", "vi"] where which(fallback) {
                editor = fallback
                break
            }
        }
        guard !editor.isEmpty else { throw EditorError.noEditor }

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("rnid-\(UUID().uuidString).tmp")
        try Data().write(to: temporary)
        defer { try? FileManager.default.removeItem(at: temporary) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [editor, temporary.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw EditorError.exited(process.terminationStatus)
        }
        return try Data(contentsOf: temporary)
    }

    private func which(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

// MARK: - Spinner

/// Python: `spin(until, msg, timeout)` (rnid.py:1061-1076).
///
/// Prints `msg + "  "` with `end=" "` — three trailing spaces in total — then animates the
/// seven braille glyphs every 100 ms, and finally erases the line.
final class BrailleSpinner: RNIDPathWaiter {
    private static let symbols = Array("⢄⢂⢁⡁⡈⡐⡠")

    @discardableResult
    func wait(until condition: () -> Bool, message: String, timeout: TimeInterval) -> Bool {
        var index = 0
        let deadline = Date().addingTimeInterval(timeout)

        print(message + "  ", terminator: " ")
        fflush(stdout)
        while Date() < deadline && !condition() {
            Thread.sleep(forTimeInterval: 0.1)
            print("\u{8}\u{8}" + String(BrailleSpinner.symbols[index]) + " ", terminator: "")
            fflush(stdout)
            index = (index + 1) % BrailleSpinner.symbols.count
        }
        print("\r" + String(repeating: " ", count: message.count) + "  \r", terminator: "")
        fflush(stdout)
        return Date() <= deadline
    }
}

// MARK: - Reticulum bring-up

/// Python: `ensure_reticulum(args)` (rnid.py:188-195). Lazily creates the stack exactly once.
final class ReticulumBringUp {
    private var connection: InstanceConnection?
    private let invocation: RNIDCommandLine.Invocation

    init(invocation: RNIDCommandLine.Invocation) {
        self.invocation = invocation
    }

    var transport: Transport? { connection?.reticulum.transport }
    var reticulum: Reticulum? { connection?.reticulum }

    @discardableResult
    func ensure() -> InstanceConnection? {
        if let connection { return connection }

        // Python: targetloglevel = 4; adjusted by -v / -q.
        var target = Reticulum.LogLevel.info.rawValue
        if invocation.verbose != 0 || invocation.quiet != 0 {
            target = target + invocation.verbose - invocation.quiet
        }
        var level = Reticulum.LogLevel(rawValue: max(-1, min(8, target))) ?? .info
        // Python: `if args.stdout: RNS.loglevel = -1`.
        if invocation.stdout { level = Reticulum.LogLevel.none }

        // Reticulum.Configuration.logLevel is stored but never applied by start(); only a
        // parsed config file's [logging] loglevel reaches globalLogLevel. rnsd works around
        // this the same way.
        Reticulum.globalLogLevel = level
        Reticulum.compactLogFmt = true

        // Python takes a config DIRECTORY; Swift's Configuration takes a storage directory
        // plus a config FILE, so map --config the way InstanceConnection already derives them.
        let configDirectory = invocation.config.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
        connection = try? InstanceConnection.attach(configDirectory: configDirectory, logLevel: level)
        return connection
    }

    func stop() {
        connection?.stop()
        connection = nil
    }
}

// MARK: - Entry point

func runRNID() -> Int32 {
    let arguments = Array(CommandLine.arguments.dropFirst())

    let invocation: RNIDCommandLine.Invocation
    do {
        invocation = try RNIDCommandLine.parse(arguments)
    } catch {
        // Python: argparse prints usage + the error and exits 2.
        FileHandle.standardError.write(Data((RNIDCommandLine.helpText + "\n").utf8))
        FileHandle.standardError.write(Data("\(RNIDCommandLine.program): error: \(error)\n".utf8))
        return 2
    }

    if invocation.wantsHelp {
        print(RNIDCommandLine.helpText)
        return 0
    }
    if invocation.wantsVersion {
        print(RNIDCommandLine.versionText)
        return 0
    }

    // Python: validate_args uses a raw exit(1), NOT R_INVALID_ARGS (250).
    if case .failed(let message) = invocation.argumentValidation {
        print(message)
        return 1
    }

    let output = TerminalOutput()
    let fileSystem = RNIDRealFileSystem()
    let bringUp = ReticulumBringUp(invocation: invocation)
    defer { bringUp.stop() }

    // Python's ensure_reticulum only runs from the hex-recall branch and from announce().
    let needsStack = invocation.truthy(invocation.announce)
        || (invocation.truthy(invocation.identity)
            && invocation.identity!.count == RNIDIdentityResolver.hashStringLength
            && !FileManager.default.fileExists(atPath: (invocation.identity! as NSString).expandingTildeInPath))
    if needsStack { bringUp.ensure() }

    let resolver = RNIDIdentityResolver(transport: bringUp.transport,
                                        reticulum: bringUp.reticulum,
                                        output: output,
                                        fileSystem: fileSystem,
                                        pathWaiter: BrailleSpinner())

    let requiresIdentity = invocation.operationRequiresIdentity
    let identity: Identity?
    switch resolver.resolve(source: invocation.identitySource,
                            allowNone: !requiresIdentity,
                            noCache: invocation.noCache,
                            request: invocation.request,
                            timeout: invocation.timeout) {
    case .success(let resolved): identity = resolved
    case .failure(let result):   return Int32(result.rawValue)
    }

    if identity == nil && requiresIdentity {
        print("Could not get working identity")
        return Int32(RNIDApp.Result.noIdentity.rawValue)
    }

    let operations = RNIDOperations(identity: identity,
                                    identityArgument: invocation.identity,
                                    options: invocation.operationOptions,
                                    output: output,
                                    fileSystem: fileSystem,
                                    transport: bringUp.transport,
                                    editor: ProcessEditor())

    // Python's fixed dispatch order (rnid.py:164-175). print_identity / export_pub /
    // export_prv / hash / announce do NOT exit and therefore compose; the rest terminate.
    var didOperation = false

    if invocation.printIdentity {
        let code = operations.printIdentityInformation()
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
    }
    if invocation.exportPublic {
        let code = operations.exportPublicIdentity()
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
    }
    if invocation.exportPrivate {
        let code = operations.exportPrivateIdentity()
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
    }
    if invocation.truthy(invocation.hash) {
        let code = operations.printHashInformation(aspects: invocation.hash!)
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
    }
    if invocation.truthy(invocation.announce) {
        // Python calls ensure_reticulum() inside announce(); `needsStack` above already
        // brought it up, and ensure() is idempotent.
        bringUp.ensure()
        let code = operations.announce(aspects: invocation.announce!)
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
        // Python: `destination.announce(); time.sleep(0.25)`.
        Thread.sleep(forTimeInterval: 0.25)
    }
    if invocation.truthy(invocation.validate) {
        return Int32(operations.validate(paths: invocation.validate!).rawValue)
    }
    if invocation.truthy(invocation.sign) {
        return Int32(operations.sign(paths: invocation.sign!).rawValue)
    }
    if invocation.signMessageTruthy {
        return Int32(operations.signMessage(invocation.signMessage).rawValue)
    }
    if invocation.truthy(invocation.encrypt) {
        return Int32(operations.encrypt(paths: invocation.encrypt!).rawValue)
    }
    if invocation.truthy(invocation.decrypt) {
        return Int32(operations.decrypt(paths: invocation.decrypt!).rawValue)
    }
    if invocation.truthy(invocation.write) {
        let code = operations.writeIdentity(path: invocation.write!,
                                            exportPrivate: invocation.exportPrivate)
        didOperation = true
        if code != .ok { return Int32(code.rawValue) }
    }
    if invocation.truthy(invocation.generate) { didOperation = true }

    if !didOperation { print(RNIDCommandLine.helpText) }
    return Int32(RNIDApp.Result.ok.rawValue)
}

// Python: the whole of main() is wrapped in `except KeyboardInterrupt: print(""); exit(255)`.
signal(SIGINT) { _ in
    print("")
    exit(Int32(RNIDApp.Result.interrupted.rawValue))
}

exit(runRNID())
