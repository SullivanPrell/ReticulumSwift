# Security Policy

ReticulumSwift implements cryptographic transport protocols, so security
reports are taken seriously.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Instead, report privately via GitHub's
[private vulnerability reporting](https://github.com/SullivanPrell/ReticulumSwift/security/advisories/new),
or email the maintainer. Include:

- a description of the issue and its impact,
- steps to reproduce (a failing test or packet capture is ideal),
- affected versions / commit.

You can expect an initial acknowledgement within a few days.

## Scope

ReticulumSwift aims for **wire and cryptographic parity** with the Python
Reticulum reference implementation. Reports that demonstrate a divergence from
the reference protocol that weakens security (e.g. an encryption/authentication
mismatch, a key-handling bug, or an interop flaw that downgrades a session) are
in scope.

## Cryptography

All cryptographic primitives are provided by Apple **CryptoKit** (Curve25519,
HMAC-SHA256, HKDF, SHA-256/512) and CommonCrypto (AES-CBC). No third-party
crypto libraries are used. If you believe a primitive is being misused, please
report it.
