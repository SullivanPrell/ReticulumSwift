# Architecture

ReticulumSwift mirrors the structure of the Python Reticulum reference
implementation (`RNS`) closely enough that the two are wire-compatible. Where
Python uses snake_case, Swift uses the camelCase equivalent (`expand_name` →
`expandName`); otherwise types and responsibilities line up one-to-one.

## Layer overview

```
            ┌──────────────────────────────────────────────┐
   apps     │  LXMFSwift · LXSTSwift · NomadNetSwift · …     │
            └──────────────────────────────────────────────┘
                               │
            ┌──────────────────────────────────────────────┐
   high     │  Resource   Channel   Buffer   Link            │
            ├──────────────────────────────────────────────┤
   routing  │  Transport (paths, announces, relay, tunnels)  │
            ├──────────────────────────────────────────────┤
   identity │  Identity   Destination   Packet   Announce     │
            ├──────────────────────────────────────────────┤
   crypto   │  Token · AES-CBC · HKDF · HMAC · Hashes · MsgPack│
            ├──────────────────────────────────────────────┤
   links    │  Interface protocol + TCP/UDP/Auto/RNode/I2P/…  │
            └──────────────────────────────────────────────┘
```

## Source map

```
Sources/ReticulumSwift/
├── Reticulum.swift          Entry point, stack lifecycle (start/stop), config, identity load
├── Constants.swift          Wire-format numeric constants
├── Announce.swift           Announce packet encode / decode / validate
├── Discovery.swift          Interface discovery
├── Resolver.swift           Path / announce resolution, label→hash address book
├── ReticulumConfig.swift    INI config parser (Python-compatible)
├── Utilities.swift          prettyHex / prettySize / prettySpeed / prettyTime
├── Cryptography/
│   ├── AES.swift            AES-128/256-CBC
│   ├── HKDF.swift           HKDF-SHA256
│   ├── HMAC.swift           HMAC-SHA256
│   ├── Hashes.swift         fullHash / truncatedHash / randomHash
│   ├── MsgPack.swift        Minimal MsgPack encode / decode
│   ├── PKCS7.swift          PKCS#7 padding
│   └── Token.swift          IV + AES + HMAC token (Reticulum "Token")
├── Identity/Identity.swift  Keys, encrypt/decrypt, sign/verify, ratchets, recall/remember
├── Destination/Destination.swift   Hash computation, announce, link accept, requests
├── Packet/
│   ├── Packet.swift         Header pack/unpack, all packet types
│   └── PacketReceipt.swift  Delivery / proof tracking
├── Link/
│   ├── Link.swift           Establishment, keepalive, MTU, ratchets
│   └── LinkRequest.swift    Outbound link-request state
├── Transport/
│   ├── Transport.swift          Core routing: inbound, announce, path, tunnel
│   ├── AnnounceHandler.swift    AnnounceHandler protocol + dispatch
│   ├── AnnounceQueue.swift      Rate-limited announce queuing (announce cap)
│   ├── BlackholeManagement.swift Blackhole list + path pruning
│   ├── PacketCache.swift        Packet hashlist (duplicate suppression)
│   └── PathStore.swift          Path table persistence
├── Channel/Channel.swift    Reliable, ordered message channel
├── Buffer/Buffer.swift      RawChannelReader / Writer stream wrappers
├── Resource/
│   ├── Resource.swift           Multi-segment file/data transfer
│   ├── ResourceTransfer.swift   Transfer state machine
│   ├── BZip2Compressor.swift    Compression wrapper (CBZip2)
│   └── Compression.swift        Compression type enum
└── Interfaces/
    ├── Interface.swift          Interface protocol + base types
    ├── IfacStore.swift          Per-interface state
    ├── IngressControlState.swift Ingress burst / rate control
    ├── InterfaceFreqTracker.swift Announce / path-request frequency tracking
    ├── HDLC.swift / KISS framing
    ├── AutoInterface.swift      mDNS / UDP-multicast auto-discovery
    ├── BackboneInterface.swift  High-bandwidth TCP backbone
    ├── LocalInterface.swift     Shared-instance loopback
    ├── RNodeInterface.swift     LoRa RNode over BLE / serial
    ├── RNodeMultiInterface.swift Multi-subinterface RNode
    ├── TCPClientInterface.swift / TCPServerInterface.swift / TCPInterface.swift
    ├── UDPInterface.swift
    └── (I2P, Serial, KISS, AX25KISS, Weave)
Sources/rnsd/main.swift       Daemon executable (config, shared instance, RPC)
Sources/CI2PDCShims/          Clang module wrapping the i2pd C API (see Package.swift notes)
```

## Key design choices

- **No RPC process boundary.** Python Reticulum uses a multiprocessing RPC layer
  between the daemon and client tools. ReticulumSwift is in-process: callers use
  the `Reticulum` / `Transport` API directly. (`rnsd` still exposes the Python
  RPC port `37429` for compatibility with Python client tools.)
- **Persistence lives on `Transport`.** Known destinations, path table, ratchets,
  and packet hashlists are snapshotted to `storagePath` on `stop()` /
  `checkpoint()` and rehydrated on `start()`. Identities and ratchet privates are
  persisted alongside.
- **IFAC uses deterministic Ed25519** (RFC 8032, pure Swift) so it is
  bit-for-bit compatible with Python's pure25519 signing. `ifac_size` in the
  config is in **bits** (so `ifac_size = 64` means an 8-byte field).
- **Crypto is CryptoKit-only.** Curve25519, HMAC-SHA256, HKDF, SHA-256/512 come
  from CryptoKit; AES-CBC from CommonCrypto. No third-party crypto libraries.
- **Thread safety.** `Transport` is not actor-isolated; callers must serialize
  access (e.g. drive it from a single queue). The test suite is single-threaded.

## How it maps to Python

| ReticulumSwift | Python `RNS` |
|----------------|--------------|
| `Identity` | `RNS.Identity` |
| `Destination` | `RNS.Destination` |
| `Packet` / `PacketReceipt` | `RNS.Packet` / `RNS.PacketReceipt` |
| `Transport` | `RNS.Transport` |
| `Link` / `LinkRequest` | `RNS.Link` |
| `Resource` | `RNS.Resource` |
| `Channel` / `Buffer` | `RNS.Channel` / `RNS.Buffer` |
| `Cryptography.Token` | `RNS.Cryptography.Token` |
| `Interfaces.*` | `RNS.Interfaces.*` |

To trace a behavior against the reference, the corresponding Python file is the
authoritative source — see <https://github.com/markqvist/Reticulum>.
