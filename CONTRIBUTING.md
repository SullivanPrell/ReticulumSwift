# Contributing to ReticulumSwift

Thanks for your interest in improving ReticulumSwift. This project values
**wire compatibility with Python Reticulum** before all else—a change that
breaks interop with the reference implementation is a regression, even if the
Swift tests pass.

## Ground rules

- **Test-driven.** Write a failing test first, implement until green, then commit.
  The reference implementation (<https://github.com/markqvist/Reticulum>) is the
  source of truth. Check new wire-level behavior against captured Python bytes
  where possible.
- **Cite the reference.** ReticulumSwift is a translation of the Python
  implementation, not a clean-room one. When a change ports Python behavior,
  its doc comment names the Python file and function it translates.
- **Disclose machine assistance.** If a tool generated part of a change, say so
  in the pull request and add a `Co-Authored-By` trailer. The pull request's
  author answers for all of it.
- **No regressions.** The full `swift test` suite must pass before any commit.
- **No new crypto dependencies.** All cryptography goes through Apple CryptoKit
  (Curve25519, HMAC-SHA256, HKDF, SHA-256/512) and CommonCrypto (AES-CBC).

## Setup

```sh
git clone https://github.com/SullivanPrell/ReticulumSwift.git
cd ReticulumSwift
swift build
swift test
```

If you see `SwiftShims` module-cache errors: `rm -rf .build && swift test`.

## Conventions

- **File names:** PascalCase, matching the primary type (`Identity.swift`).
- **API naming:** the camelCase equivalent of the Python snake_case name
  (`expand_name` → `expandName`), so the two APIs read the same.
- **Errors:** `throw` for protocol errors; return `nil` / `false` for soft
  failures.
- **Bytes:** prefer `Data`; use `[UInt8]` only on performance-critical paths.
- **Tests:** XCTest, not swift-testing. File `Tests/.../<Feature>Tests.swift`,
  class `<Feature>Tests`.
- **Style:** [Google Swift Style Guide](https://google.github.io/swift/).

## Running a single suite

```sh
swift test --filter WireGoldenBytesTests
```

## Verifying interoperability

Unit tests assert against captured Python wire bytes. For end-to-end interop, run
a Python `rnsd` and a Swift `rnsd` on the same network—see
[docs/INTEROP.md](docs/INTEROP.md).

## The CI2PD (i2pd) binary

The I2P interface uses a prebuilt static library of the i2pd daemon
(`CI2PD.xcframework`: macOS-arm64, iOS-arm64, iOS-simulator-arm64). It's **not
committed to git**—it's built from **pinned source** and published as a
GitHub **Release** asset, then consumed via `binaryTarget(url:checksum:)` in
`Package.swift`. Pinned versions: **i2pd 2.60.0**, Boost 1.90.0, OpenSSL 3.3.2.

### Bumping the version (the easy way)

Run the **Build binaries** workflow (Actions ▸ *Build binaries* ▸ *Run workflow*,
or `gh workflow run build-binaries.yml -f i2pd_version=<tag>`). It builds all
three slices from source, publishes a `ci2pd-<version>` release, and opens a PR
that updates the `binaryTarget` URL and checksum. Review and merge it.

### Building locally

```sh
bash build_ci2pd_ios.sh        # clones the pinned i2pd tag; override with I2PD_SRC=/path
```

The script cross-compiles OpenSSL + Boost + i2pd for the iOS SDKs from pinned
source, builds the macOS slice natively (Homebrew `boost` + `openssl@3`), and
assembles + zips the xcframework, printing its SwiftPM checksum. Build artifacts
land in `/tmp/ci2pd_build` (~3 GB, safe to delete). Prerequisites: Xcode with the
iOS SDK, Homebrew `cmake`, `boost`, and `openssl@3`.

See [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) for the licenses of the components
the binary embeds.

## Style checks

```sh
make fmt      # swift format, license headers
make check    # what CI runs: format, license headers, Vale prose lint
```

Vale lints Swift comments as prose, and finds them by scanning for `//`. A `//` inside
a string literal therefore lints code, and acting on that finding would edit it. After
a comment-only change, confirm the code is unchanged:

```sh
git status --porcelain | awk '{print $NF}' | grep '\.swift$' \
    | xargs python3 .vale/tools/verify_code_unchanged.py
```

## Submitting changes

1. Branch from `main`.
2. Keep commits focused; describe the *why*.
3. Ensure `swift test` is green.
4. Open a pull request describing the change and any interop implications.

## License of contributions

By contributing, you agree to license your contributions under the
[Reticulum License](LICENSE), the same license as the project.
