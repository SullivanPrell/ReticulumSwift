# Changelog

All notable changes to ReticulumSwift are documented here. This project follows
[Semantic Versioning](https://semver.org).

## [1.4.1] — Correct the reported library version

### Fixed

- **`Reticulum.version` was stuck at `"0.1.0"`.** The constant was never bumped
  past the initial value, so `rnsd --version` and RetiOS's Settings ▸ About both
  reported "ReticulumSwift 0.1.0" despite the package being released through
  1.4.0. It now reports the real release version. (`version` is informational
  only — it never travels on the wire.)

### Added

- **`Reticulum.rnsProtocolVersion`** — the Python RNS release whose wire protocol
  this port matches (currently `"1.4.0"`), kept distinct from the library's own
  release `version`. Mirrors Python's single `RNS.__version__` as a parity
  reference.

## [1.4.0] — Large link packets, response Resources & RNS 1.4.0 parity

### Fixed

- **Inbound link packets larger than the base MTU were silently dropped.**
  `Packet.pack()` enforces a 500-byte (`Constants.mtu`) transmit cap, and
  `Packet.hashablePart()` computed the packet hash through `pack()` — so hashing
  threw for any packet over 500 B, and `Transport.filterAndRecord()` treated the
  failed hash as a duplicate and dropped the packet before it reached
  `Link.receive`. Because links negotiate their MTU upward (a TCP link commonly
  reaches 8192), a peer legitimately sends single link packets far larger than
  500 B — e.g. a NomadNet node serving any real page. **Every such packet was
  discarded**, so browsing NomadNet pages timed out. Packet identity and byte
  accounting are now MTU-independent (new `Packet.packedBytes()`), matching Python
  (`get_hashable_part` slices the already-packed bytes; only `pack()` checks the
  MTU). (bugs/010)
- **Over-MDU request responses sent as Resources used the wrong payload envelope.**
  The responder resourced the bare response value and the initiator delivered it
  un-decoded, so a large response either arrived msgpack-wrapped (Swift↔Swift) or
  timed out (a Python fetcher's `unpackb([id, response])` threw). Both sides now
  use the `[request_id, response]` envelope — identical to the single-packet path —
  matching Python `Link.handle_request` / `response_resource_concluded`. (bugs/011)

### Changed — RNS 1.4.0 parity

- **Link keepalive** is now sent when *either* the inbound *or* the outbound
  direction has been idle for `keepalive` (previously inbound only), so a
  receive-only initiator no longer has its link torn down as stale by the peer.
  The responder rate-limits its `0xFE` keepalive echo (skips it when it has sent
  something within `keepalive`). (RNS commit e64d8150)
- **Default interface-discovery stamp value raised 14 → 16**
  (`DEFAULT_STAMP_VALUE`, RNS commit be36abd8).

### Tests

- Unit: `PacketOversizeMTUTests`, `LinkRequestTests.testLargeResponseViaResource*`,
  updated `KeepaliveTests`. Interop: tri-test `test_nomadnet_get_large` (py/swift
  matrix over a ~2 KB page) closes the blind spot where the suites only ever served
  a 20-byte page.

## [1.0.0] — Initial public release

First public release of ReticulumSwift — a from-scratch Swift port of the
[Reticulum Network Stack](https://reticulum.network), wire-compatible with the
Python reference implementation (RNS 1.3.0).

### Highlights

- **Cryptography** — Curve25519 (X25519 + Ed25519), HMAC-SHA256, HKDF, SHA-256/512
  via CryptoKit; AES-CBC + PKCS#7 via CommonCrypto; Reticulum Token.
- **Identity / Destination / Packet / Announce** — byte-identical wire format.
- **Transport** — routing, path table, announce relaying and dedup, ratchet
  rotation/learning, blackholing, announce rate-limiting, multi-hop links.
- **Link** — full handshake, keepalive, MTU signalling, request/response.
- **Resource** — segmented transfers with hashmap-windowed retransmit.
- **Channel / Buffer** — reliable ordered messaging and stream wrappers.
- **Interfaces** — TCP client/server, UDP, AutoInterface (mDNS), Backbone,
  Local, RNode (+ RNodeMulti), I2P (embedded i2pd), Serial, KISS, AX.25 KISS,
  Weave. (PipeInterface is intentionally out of scope on Apple platforms.)
- **`rnsd`** — a Reticulum daemon executable, config-compatible with Python's.
- **IFAC** — deterministic Ed25519, wire-compatible with Python's pure25519.

Covered by 2,145 unit tests (~78% line coverage) plus a live Python↔Swift
interoperability suite.
