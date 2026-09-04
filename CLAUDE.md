# ReticulumSwift

Swift port of [Reticulum Network Stack](https://reticulum.network) (Python ref: RNS 1.4.2).
Target: wire + API compatibility so a Swift node interoperates with Python nodes.

Ships the library plus the nine `rn*` command-line utilities as executable products
(`rnstatus`, `rnpath`, `rnprobe`, `rncp`, `rnid`, `rnx`, `rnsd`, `rnir`, `rnpkg`).

## Build and test

```bash
swift build
swift test                          # runs the full test suite
swift test --filter <SuiteName>     # e.g. WireGoldenBytesTests

swift build -c release              # also builds the nine rn* executables

# If you see SwiftShims module cache errors:
rm -rf .build && swift test
```

Cross-implementation parity for the utilities lives in `../../tri-test`, which compares
each tool against the installed Python one—CLI surface, instance-control socket, and
file/identity round-trips:

```bash
cd ../../tri-test && RETICULUM_LOCAL_DEPS=1 make build-utilities test-utilities
```

`RETICULUM_LOCAL_DEPS=1` is what points tri-test at this working tree; without it, it
tests the published release pinned in `tri-test/versions.env`.

## Tech stack

- **Swift 5.9**, SPM, Apple platforms (iOS 16+, macOS 13+)
- **Crypto**: Apple CryptoKit—Curve25519, HMAC-SHA256, HKDF, SHA256/512
- **Compression**: CBZip2 (thin wrapper over system libbz2)
- **Serialization**: custom MsgPack (`Sources/ReticulumSwift/Cryptography/MsgPack.swift`)
- **Testing**: XCTest, TDD (failing test → implement → green → commit)

## Source map

```
Sources/ReticulumSwift/
├── Reticulum.swift              ← Entry point, class constants, static utilities
├── Constants.swift              ← Wire-format numeric constants
├── Announce.swift               ← Announce packet encode/decode/validate
├── Discovery.swift              ← Interface discovery
├── InterfaceDiscovery.swift     ← Peer discovery over the discovery interface
├── Resolver.swift               ← Path/announce resolution
├── Utilities.swift              ← prettyHex, prettySize, prettySpeed, prettyTime
├── ReticulumConfig.swift        ← INI config parser
├── Cryptography/                ← AES-128-CBC, HKDF, HMAC, hashes, MsgPack, PKCS#7, Token
├── Identity/Identity.swift      ← Keys, encryption, signing, ratchets, recall/remember
├── Destination/Destination.swift← Hash computation, announce, link accept, requests
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
│   ├── BlackholeManagement.swift← Blackhole identity list + path pruning
│   ├── InterfaceStatsPayload.swift ← ifstats dict served to `rnstatus`
│   ├── PacketCache.swift        ← Packet hashlist (duplicate suppression)
│   ├── PathStore.swift          ← Path table persistence
│   ├── TransportDiscovery.swift ← Transport-node discovery
│   └── TunnelStore.swift        ← Tunnel persistence
├── Channel/Channel.swift        ← Reliable ordered message channel
├── Buffer/Buffer.swift          ← RawChannelReader/Writer stream wrappers
├── Resource/                    ← Resource.swift, ResourceTransfer.swift,
│                                  BZip2Compressor.swift, Compression.swift
├── Interfaces/
│   ├── Interface.swift          ← Interface protocol + base types
│   ├── InterfaceState.swift     ← Shared mutable per-interface state
│   ├── InterfaceCounters.swift  ← Thread-safe tx/rx counters
│   ├── IngressControlState.swift← Ingress burst/rate control
│   ├── InterfaceFreqTracker.swift ← Announce/path-request frequency tracking
│   ├── InterfaceTransportFactories.swift ← Config-driven interface construction
│   ├── HDLC.swift / SocketOptions.swift  ← Framing and socket tuning
│   ├── AutoInterface.swift      ← mDNS/UDP multicast auto-discovery
│   ├── BackboneInterface.swift  ← High-bandwidth TCP backbone (1MB MTU)
│   ├── LocalInterface.swift     ← Shared-instance loopback
│   ├── TCPInterface.swift       ← Shared TCP client/server logic
│   ├── TCPClientInterface.swift / TCPServerInterface.swift / PosixTCPServer.swift
│   ├── UDPInterface.swift       ← UDP broadcast/unicast
│   ├── RNodeInterface.swift / RNodeMultiInterface.swift ← LoRa RNode over BLE/serial
│   ├── SerialInterface.swift / SerialPort.swift  ← Raw serial
│   ├── KISSInterface.swift / AX25KISSInterface.swift ← KISS TNC framing
│   ├── I2PInterface.swift / I2PDaemon.swift / I2PInterfacePeer.swift
│   ├── SAMClient.swift / SAMSocket.swift ← I2P SAM bridge
│   ├── BLEMeshInterface.swift / BLEMeshTransport.swift
│   └── WeaveInterface.swift     ← Weave switching fabric (experimental)
└── Utilities/                   ← The nine rn* tools: arg parsing, RPC client/server,
                                   instance connection, status rendering, rncp, rnid,
                                   rnpath, rnsh, rnx, daemon bootstrap
```

## Key architecture notes

- **RPC**: `Utilities/RPCServer.swift` and `RPCClient.swift` speak Python's
  multiprocessing-connection protocol, so the `rn*` tools drive a remote `rnsd`. In-process
  callers reach Transport directly and skip the socket.
- **Persistence on Transport**: all known destinations, paths, ratchets, hashlists saved via Transport.
- **IFAC**: uses deterministic Ed25519 (RFC 8032, pure Swift)—wire-compatible with Python's
  pure25519 signing. Python config `ifac_size` is in **bits** (so `ifac_size = 64` = 8 bytes).
- **Ratchets**: full ratchet key rotation, persistence, and sweep implemented.
- **Thread safety**: Transport isn't actor-isolated; callers must serialize access. Tests are single-threaded.

## Parity status

Implements the full Reticulum 1.4.2 protocol—all core layers and every standard
interface—wire-compatible with the Python reference. ~78% line coverage across
3,580 tests.

`Reticulum.rnsProtocolVersion` records the upstream release this port matches. It moves
only after a parity audit confirms the match, so it stays at 1.4.2 while work against
1.5.x is in progress. See [CHANGELOG.md](CHANGELOG.md).

## Conventions

- File names: PascalCase (matching class name)
- Public API naming: matches Python camelCase equivalent of snake_case
- Error handling: `throw` for protocol errors, `return nil/false` for soft failures
- Tests: file named `<Feature>Tests.swift`, class named `<Feature>Tests`
- Zero regressions: `swift test` must pass before every commit

## Python reference lookup

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
