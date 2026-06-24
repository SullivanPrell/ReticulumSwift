# ReticulumSwift

A from-scratch Swift implementation of the [Reticulum Network Stack](https://reticulum.network) —
wire-compatible with the Python reference implementation, with first-class support
for Apple platforms.

[![Platforms](https://img.shields.io/badge/platforms-iOS%2016%2B%20%7C%20macOS%2013%2B%20%7C%20tvOS%2016%2B%20%7C%20watchOS%209%2B-blue)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![Tests](https://img.shields.io/badge/tests-2145%20passing-brightgreen)](#testing)
[![License](https://img.shields.io/badge/license-Reticulum-lightgrey)](LICENSE)

Reticulum is a cryptography-based networking stack for building local and wide-area
networks with readily available hardware — operable over anything from packet radio
and LoRa to TCP/IP and I2P. Every destination is identified by a self-certifying
cryptographic address; all traffic is end-to-end encrypted by default.

**ReticulumSwift** ports that stack to idiomatic Swift. It is byte-for-byte
wire-compatible with Python Reticulum (RNS 1.3.0): a Swift node and a Python node
interoperate on the same network, exchange announces, establish links, and transfer
resources transparently.

---

## The ReticulumSwift stack

This repository is the foundation. Four packages build on top of it, mirroring the
Python ecosystem:

| Package | What it is | Repo |
|---------|-----------|------|
| **ReticulumSwift** | Core stack: identity, transport, links, resources, interfaces, `rnsd` | *(this repo)* |
| **LXMFSwift** | Lightweight Extensible Message Format — store-and-forward messaging | [LXMFSwift](https://github.com/SullivanPrell/LXMFSwift) |
| **LXSTSwift** | Reticulum audio/video streaming (codec2 / opus, Telephone) | [LXSTSwift](https://github.com/SullivanPrell/LXSTSwift) |
| **NomadNetSwift** | NomadNet: Micron pages, Browser, node, RRC chat rooms | [NomadNetSwift](https://github.com/SullivanPrell/NomadNetSwift) |
| **RetiOS** | Reference iOS/macOS app consuming all four packages | [RetiOS](https://github.com/SullivanPrell/RetiOS) |

The goal of the stack is a complete iOS/macOS Reticulum experience — think
"Meshtastic for Reticulum" — that interoperates with every standard Reticulum node.

---

## Status

**At parity with Python Reticulum 1.3.0.** All core protocol layers and every
standard interface are implemented and covered by tests.

| Layer | State |
|-------|-------|
| Cryptography (Curve25519, Token, HKDF, HMAC, ratchets) | ✅ |
| Identity / Destination / Packet / Announce | ✅ wire-compatible |
| Transport (routing, paths, relay, dedup, blackholing, rate-limit) | ✅ |
| Link (handshake, keepalive, MTU, request/response) | ✅ |
| Resource (segmented transfer + windowed retransmit) | ✅ |
| Channel / Buffer | ✅ |
| IFAC (deterministic Ed25519) | ✅ wire-compatible |
| `rnsd` daemon + RPC + shared instance | ✅ config-compatible |

**2145 unit tests, 0 failures.** Interoperability with Python is exercised by a
separate live Python↔Swift test suite; see [docs/INTEROP.md](docs/INTEROP.md).

### Interfaces

TCP client/server · UDP · AutoInterface (mDNS) · Backbone · Local · RNode (LoRa) ·
RNodeMulti · I2P (embedded i2pd) · Serial · KISS · AX.25 KISS · Weave.
`PipeInterface` is intentionally out of scope on Apple platforms.

See [docs/INTERFACES.md](docs/INTERFACES.md) for configuration of each.

---

## Requirements

- Swift 5.9+ (Xcode 15+ on Apple platforms)
- iOS 16+ / macOS 13+ / tvOS 16+ / watchOS 9+
- The embedded i2pd binary is fetched automatically by SwiftPM from a GitHub
  Release (a checksummed `binaryTarget`), built from pinned source by the
  *Build binaries* workflow — a normal `git clone` + `swift build` is all you need.

## Installation

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/SullivanPrell/ReticulumSwift.git", from: "1.0.0")
],
targets: [
    .target(name: "MyApp", dependencies: ["ReticulumSwift"])
]
```

Or in Xcode: **File ▸ Add Package Dependencies…** and paste the repository URL.

## Quick start

```swift
import ReticulumSwift

// Bring up the stack with on-disk storage for identity, paths, and ratchets.
let stack = Reticulum(configuration: .init(
    storagePath: URL.documentsDirectory.appendingPathComponent("reticulum")
))
try stack.start()

// A self-certifying identity, persisted across launches.
let identity = try stack.loadOrCreateIdentity()

// An inbound destination others can address.
let destination = try Destination(
    identity: identity,
    direction: .in,
    kind: .single,
    appName: "example",
    aspects: ["demo"]
)
stack.transport.register(destination: destination)

// Reach the wider network over a TCP interface (e.g. a public hub or a Python node).
let tcp = TCPClientInterface(name: "hub", host: "192.0.2.10", port: 4242)
stack.transport.register(interface: tcp)
try tcp.start()

// Learn about peers as their announces arrive.
stack.transport.onAnnounceReceived = { decoded, iface in
    print("announce from \(decoded.identity.hexHash) via \(iface.name)")
}

// Tell the network this destination exists.
_ = try stack.transport.announce(destination: destination, appData: Data("hello".utf8))
```

## Running a node (`rnsd`)

ReticulumSwift ships `rnsd`, a daemon that reads the same INI config as Python's
`rnsd` and defaults to the same `~/.reticulum` directory:

```sh
swift run rnsd            # uses ~/.reticulum/config (writes a default if missing)
swift run rnsd -v         # info logging
swift run rnsd --help
```

For a full local-network walkthrough — toolchain setup, configuration, connecting
to the public testnet, and pairing with a Python node — see
**[docs/RUNNING-LOCALLY.md](docs/RUNNING-LOCALLY.md)**.

---

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/RUNNING-LOCALLY.md](docs/RUNNING-LOCALLY.md) | Build, test, run `rnsd`, connect to a network |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Module map and how it mirrors Python RNS |
| [docs/INTERFACES.md](docs/INTERFACES.md) | Every interface and how to configure it |
| [docs/INTEROP.md](docs/INTEROP.md) | Wire compatibility and testing against Python |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Dev workflow, conventions, rebuilding CI2PD |

## Testing

```sh
swift test                              # 2145 tests
swift test --filter <TestSuiteName>     # a single suite
```

If you hit `SwiftShims` module-cache errors: `rm -rf .build && swift test`.

---

## License

ReticulumSwift is released under the **Reticulum License** — a permissive MIT-style
license with two binding conditions inherited from upstream Reticulum: the software
**may not be used in systems that can purposefully harm human beings**, and it **may
not be used to create AI/ML/LLM training datasets**. See [LICENSE](LICENSE).

ReticulumSwift is a derivative work of [Reticulum](https://github.com/markqvist/Reticulum)
by Mark Qvist. See [NOTICE](NOTICE) and [docs/THIRD-PARTY.md](docs/THIRD-PARTY.md) for
attribution and bundled-binary licenses (i2pd, Boost, OpenSSL).
