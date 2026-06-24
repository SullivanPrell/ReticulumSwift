# ReticulumSwift

Swift port of [Reticulum Network Stack](https://reticulum.network) (Python ref: RNS 1.3.0).
Target: 100% wire + API parity so a Swift node interoperates with Python nodes.

## Build & Test

```bash
swift build
swift test                          # 2119 tests, 0 failures
swift test --filter <SuiteName>     # e.g. WireGoldenBytesTests

# If you see SwiftShims module cache errors:
rm -rf .build && swift test
```

## Tech Stack

- **Swift 5.9**, SPM, Apple platforms (iOS 16+, macOS 13+)
- **Crypto**: Apple CryptoKit — Curve25519, HMAC-SHA256, HKDF, SHA256/512
- **Compression**: CBZip2 (thin wrapper over system libbz2)
- **Serialization**: Custom MsgPack (`Sources/ReticulumSwift/Cryptography/MsgPack.swift`)
- **Testing**: XCTest, TDD (failing test → implement → green → commit)

## Source Map

```
Sources/ReticulumSwift/
├── Reticulum.swift              ← Entry point, class constants, static utilities
├── Constants.swift              ← Wire-format numeric constants
├── Announce.swift               ← Announce packet encode/decode/validate
├── Discovery.swift              ← Interface discovery
├── Resolver.swift               ← Path/announce resolution
├── Utilities.swift              ← prettyHex, prettySize, prettySpeed, prettyTime
├── ReticulumConfig.swift        ← INI config parser
├── Cryptography/
│   ├── AES.swift                ← AES-128-CBC
│   ├── HKDF.swift               ← HKDF-SHA256
│   ├── HMAC.swift               ← HMAC-SHA256
│   ├── Hashes.swift             ← fullHash, truncatedHash, randomHash
│   ├── MsgPack.swift            ← Minimal msgpack encode/decode
│   ├── PKCS7.swift              ← PKCS#7 padding
│   └── Token.swift              ← IV+AES+HMAC token (Python Reticulum "token")
├── Identity/
│   └── Identity.swift           ← Keys, encryption, signing, ratchets, recall/remember
├── Destination/
│   └── Destination.swift        ← Hash computation, announce, link accept, requests
├── Packet/
│   ├── Packet.swift             ← Header pack/unpack, all packet types
│   └── PacketReceipt.swift      ← Delivery/proof tracking
├── Link/
│   ├── Link.swift               ← Link establishment, keepalive, MDU, ratchets
│   └── LinkRequest.swift        ← Outbound link-request state
├── Transport/
│   ├── Transport.swift          ← Core routing: inbound, announce, path, tunnel
│   ├── AnnounceHandler.swift    ← AnnounceHandler protocol + dispatch
│   ├── AnnounceQueue.swift      ← Rate-limited announce queuing (2% cap)
│   ├── BlackholeManagement.swift ← Blackhole identity list + path pruning
│   ├── PacketCache.swift        ← Packet hashlist (duplicate suppression)
│   └── PathStore.swift          ← Path table persistence
├── Channel/
│   └── Channel.swift            ← Reliable ordered message channel
├── Buffer/
│   └── Buffer.swift             ← RawChannelReader/Writer stream wrappers
├── Resource/
│   ├── Resource.swift           ← Multi-segment file/data transfer
│   ├── ResourceTransfer.swift   ← Transfer state
│   ├── BZip2Compressor.swift    ← Compression wrapper
│   └── Compression.swift        ← Compression type enum
└── Interfaces/
    ├── Interface.swift          ← Interface protocol + base types
    ├── IfacStore.swift          ← Per-interface state store
    ├── IngressControlState.swift← Ingress burst/rate control
    ├── InterfaceFreqTracker.swift← Announce/path-request frequency tracking
    ├── HDLC.swift               ← HDLC framing (TCP/Backbone)
    ├── AutoInterface.swift      ← mDNS/UDP multicast auto-discovery
    ├── BackboneInterface.swift  ← High-bandwidth TCP backbone (1MB MTU)
    ├── LocalInterface.swift     ← Shared-instance loopback
    ├── RNodeInterface.swift     ← LoRa RNode over BLE/serial
    ├── TCPInterface.swift       ← Shared TCP client/server logic
    ├── TCPClientInterface.swift ← TCP client
    ├── TCPServerInterface.swift ← TCP server (accepts clients)
    └── UDPInterface.swift       ← UDP broadcast/unicast
```

## Key Architecture Notes

- **No RPC layer**: Python uses multiprocessing RPC. Swift uses in-process direct calls.
- **Persistence on Transport**: all known destinations, paths, ratchets, hashlists saved via Transport.
- **IFAC**: Uses deterministic Ed25519 (RFC 8032, pure Swift) — wire-compatible with Python's
  pure25519 signing. Python config `ifac_size` is in **bits** (so `ifac_size = 64` = 8 bytes).
- **Ratchets**: full ratchet key rotation, persistence, and sweep implemented.
- **Thread safety**: Transport is not actor-isolated; callers must serialize access. Tests are single-threaded.

## Parity Status

**At parity with Python Reticulum 1.3.0.** All core layers and every standard
interface are implemented. 2145 tests, 0 failures. See [CHANGELOG.md](CHANGELOG.md).

## Conventions

- File names: PascalCase (matching class name)
- Public API naming: matches Python camelCase equivalent of snake_case
- Error handling: `throw` for protocol errors, `return nil/false` for soft failures
- Tests: file named `<Feature>Tests.swift`, class named `<Feature>Tests`
- Zero regressions: `swift test` must pass before every commit

## Python Reference Lookup

The Python reference implementation is the source of truth for wire format and
behavior. Files live under `RNS/` in <https://github.com/markqvist/Reticulum>:

```
RNS/Transport.py     ← Transport routing
RNS/Identity.py      ← Crypto identity
RNS/Destination.py   ← Destination hashing
RNS/Link.py          ← Link lifecycle
RNS/Packet.py        ← Wire format
RNS/Resource.py      ← Resource transfers
RNS/Channel.py       ← Channel protocol
RNS/Buffer.py        ← Buffer streams
```
