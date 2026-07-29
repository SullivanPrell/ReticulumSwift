import XCTest
@testable import ReticulumSwift

/// `~` must expand to `$HOME` when it is set, as Python's `os.path.expanduser` does.
///
/// Python reaches `~/.reticulum` through `os.path.expanduser("~")`, which returns `$HOME`
/// when set and only consults the password database otherwise. `NSHomeDirectory()` — and
/// `FileManager.homeDirectoryForCurrentUser`, which `rnsd` used — does not: on macOS it
/// always reports the account's real home.
///
/// So a Swift utility launched with `HOME` pointed at a sandbox read and wrote the
/// developer's actual `~/.reticulum` instead. Found while fixing `bugs/013`: `tri-test`
/// isolates every subprocess by setting `HOME`, and its Swift half was quietly ignoring it
/// — a "sandboxed" `rnstatus` picked up the real transport identity, authenticated to the
/// developer's live daemon on 37428, and reported *its* status. The Python half had been
/// correctly isolated the whole time, which is why nothing looked wrong.
///
/// Beyond the test suite this is a real hazard: `$HOME` is the standard way to sandbox a
/// tool, and several utilities keep state there directly (`rncp` uses `$HOME/.rncp` for its
/// identity and allow-list).
final class ConfigDirectoryHomeTests: XCTestCase {

    func testHomeDirectoryHonoursTheEnvironment() {
        let resolved = InstanceConnection.homeDirectory(environment: ["HOME": "/tmp/sandbox-home"])
        XCTAssertEqual(resolved.path, "/tmp/sandbox-home")
    }

    /// Python's `expanduser` falls back to the password database for an unset `$HOME`.
    func testHomeDirectoryFallsBackWhenUnset() {
        XCTAssertEqual(InstanceConnection.homeDirectory(environment: [:]).path, NSHomeDirectory())
    }

    /// An empty `HOME=` is not a home directory; treat it as unset rather than resolving
    /// the config directory to `/.reticulum`.
    func testEmptyHomeIsTreatedAsUnset() {
        XCTAssertEqual(InstanceConnection.homeDirectory(environment: ["HOME": ""]).path,
                       NSHomeDirectory())
    }

    /// The end a caller actually sees: the config directory follows the sandboxed home.
    func testConfigDirectoryFollowsTheSandboxedHome() {
        let home = URL(fileURLWithPath: "/tmp/sandbox-home")
        let resolved = InstanceConnection.resolveConfigDirectory(
            nil,
            home: home,
            // Point the two fixed locations somewhere that cannot exist, so the search
            // reaches the `$HOME/.reticulum` fallback deterministically on any machine.
            systemConfigDir: URL(fileURLWithPath: "/nonexistent/etc/reticulum"),
            fileManager: .default)
        XCTAssertEqual(resolved.path, "/tmp/sandbox-home/.reticulum")
    }
}
