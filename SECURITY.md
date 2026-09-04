# Security policy

ReticulumSwift implements cryptographic transport protocols, so this project
takes security reports seriously.

## Reporting a vulnerability

**Please don't open a public issue for security vulnerabilities.**

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
the reference protocol that weakens security (for example, an encryption/authentication
mismatch, a key-handling bug, or an interop flaw that downgrades a session) are
in scope.

## Cryptography

Apple **CryptoKit** provides all cryptographic primitives (Curve25519,
HMAC-SHA256, HKDF, SHA-256/512) except AES-CBC, which comes from CommonCrypto.
This project uses no third-party crypto libraries. If you believe a primitive is
wrong for its purpose, please report it.
