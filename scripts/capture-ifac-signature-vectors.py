#!/usr/bin/env python3
"""Print the `ifac_signature` Python RNS stores for a fixed IFAC segment, as hex.

Captured from RNS 1.6.1 for `InterfaceStatsIFACSignatureTests`. The derivation
repeats `Reticulum.py:1292-1306`: hash the network name and passphrase, derive a
64-byte key with HKDF, load it as an identity and sign `full_hash(key)` with it.
Ed25519 is deterministic here, so the bytes depend only on the two strings.

Usage: PYTHONPATH=<reference_implementations>/reticulum \
  <reticulum-interop>/.venv/bin/python scripts/capture-ifac-signature-vectors.py
"""
import RNS

NETNAME = "seg"
NETKEY = "secret"

origin = RNS.Identity.full_hash(NETNAME.encode("utf-8"))
origin += RNS.Identity.full_hash(NETKEY.encode("utf-8"))
key = RNS.Cryptography.hkdf(
    length=64,
    derive_from=RNS.Identity.full_hash(origin),
    salt=RNS.Reticulum.IFAC_SALT,
    context=None,
)
identity = RNS.Identity.from_bytes(key)
signature = identity.sign(RNS.Identity.full_hash(key))

print(f"RNS {RNS.__version__}")
print(f"netname {NETNAME!r} netkey {NETKEY!r}")
print(f"ifac_key {key.hex()}")
print(f"ifac_signature {signature.hex()}")
