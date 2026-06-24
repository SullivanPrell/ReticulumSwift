# Contributing to ReticulumSwift

Thanks for your interest in improving ReticulumSwift! This project values
**wire compatibility with Python Reticulum** above all else — a change that
breaks interop with the reference implementation is a regression, even if the
Swift tests pass.

## Ground rules

- **Test-driven.** Write a failing test first, implement until green, then commit.
  The reference implementation (<https://github.com/markqvist/Reticulum>) is the
  source of truth; new wire-level behavior should be checked against captured
  Python bytes where possible.
- **Zero regressions.** `swift test` must pass (2145 tests, 0 failures) before any
  commit.
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
- **Tests:** file `Tests/.../<Feature>Tests.swift`, class `<Feature>Tests`.

## Running a single suite

```sh
swift test --filter WireGoldenBytesTests
```

## Verifying interoperability

Unit tests assert against captured Python wire bytes. For end-to-end interop, run
a Python `rnsd` and a Swift `rnsd` on the same network — see
[docs/INTEROP.md](docs/INTEROP.md).

## Rebuilding CI2PD

The I2P interface uses a prebuilt static library of the i2pd daemon, shipped in
`Resources/CI2PD.xcframework` (committed directly). It contains macOS-arm64, iOS-arm64,
and iOS-simulator-arm64 slices.

You only need to rebuild it if you are bumping i2pd, OpenSSL, or Boost. The
i2pd source is **not** bundled — clone it yourself, then run the build script:

```sh
git clone https://github.com/PurpleI2P/i2pd
I2PD_SRC="$(pwd)/i2pd" bash build_ci2pd_ios.sh
```

The script downloads and cross-compiles OpenSSL and Boost for the iOS SDKs,
builds i2pd as a merged static library, and reassembles the xcframework
(preserving the macOS slice). Build artifacts land in `/tmp/ci2pd_build`
(~3 GB, safe to delete). Prerequisites: Xcode with the iOS SDK, Homebrew `cmake`
(Homebrew's still ships `FindBoost.cmake`), and internet access for source
downloads. After it finishes, run `swift build` and `swift test` to confirm no
regressions, and commit the regenerated binary.

See [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) for the licenses of the components
the binary embeds.

## Submitting changes

1. Branch from `main`.
2. Keep commits focused; describe the *why*.
3. Ensure `swift test` is green.
4. Open a pull request describing the change and any interop implications.

## License of contributions

By contributing, you agree your contributions are licensed under the
[Reticulum License](LICENSE), the same license as the project.
