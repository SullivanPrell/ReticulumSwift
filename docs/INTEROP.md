# Interoperability with Python Reticulum

ReticulumSwift targets **wire- and crypto-compatibility** with the Python
reference implementation (RNS 1.5.4), which it translates. A Swift node and a
Python node are peers on the same network: they exchange announces, establish
links, transfer resources, and route for each other with no bridge or translation
layer. The Python implementation is the authority. Where the two disagree, the
Swift port has the bug.

## What "compatible" means here

- **Byte-identical wire format.** Packet headers, flag bytes, announce payloads,
  destination/identity hashing, resource advertisements, and link handshake
  messages follow Python's encoding. Some unit tests assert against wire bytes
  captured from Python.
- **Same cryptography.** X25519 ECDH, Ed25519 signatures, HKDF-SHA256,
  HMAC-SHA256, and the Reticulum Token (AES-CBC + HMAC) match RNS. IFAC uses
  deterministic Ed25519 that reproduces Python's pure25519 signatures bit-for-bit.
- **Same config + ports.** `rnsd` reads the same INI config, defaults to
  `~/.reticulum`, and uses the shared-instance port `37428` and RPC port `37429`,
  so a Swift `rnsd` and a Python `rnsd` cooperate rather than collide.

## Trying it yourself

The shortest interop check:

1. Run a Python node:
   ```sh
   rnsd -v          # the standard Python Reticulum daemon
   ```
2. Run the Swift node on the same LAN (both with an `AutoInterface`), or point a
   Swift `TCPClientInterface` at the Python node's `TCPServerInterface`:
   ```sh
   swift run rnsd -v
   ```
3. Watch announces from one appear on the other. From there, LXMF messages, LXST
   calls, and NomadNet page fetches all cross the boundary.

## How the project verifies interop

Beyond the in-package unit tests, a separate **live Python↔Swift test harness** exercises
interoperability. It stands up a Python `TCPServer` backbone and runs both Python and
Swift nodes as clients against it, then asserts end-to-end behavior across:

- announce / path / link / packet / resource / channel flows,
- IFAC'd networks and request/response,
- LXMF in both directions (opportunistic, direct, and propagated),
- RNSH / RNX wire formats.

That harness lives in its own repository and isn't required to build or use
ReticulumSwift. If you are contributing protocol-level changes and want to run it,
open an issue. The manual check in the preceding section covers a subset of the
same flows.

## Reporting an interop bug

If a Swift node and a Python node disagree on the wire, that's a bug worth
reporting. A packet capture (or a failing test with the expected Python bytes) is
the most useful report—see [SECURITY.md](../SECURITY.md) for anything with a
security dimension, otherwise open a GitHub issue.
