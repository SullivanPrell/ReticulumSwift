"""Prints the resource-proof cache vectors that ResourceProofCacheTests pins.

Captured with RNS 1.5.5, the interop venv's version:

    reticulum-interop/.venv/bin/python -I scripts/capture-resource-proof-cache-vectors.py

- `proof_raw` and `proof_hash`: the packet `Resource.prove` sends (`Resource.py:772`)
  and the hash `Transport.cache` names its file by (`Transport.py:3056`).
- `cache_entry`: the bytes `Transport.cache` writes for it (`Transport.py:3058-3064`).
- `cache_request_raw`: the packet `Transport.cache_request` sends for that hash on a cache
  miss (`Transport.py:3123`).
"""
import hashlib
from types import SimpleNamespace

import RNS
import RNS.vendor.umsgpack as umsgpack

link_id = bytes(range(16))
link = SimpleNamespace(hash=link_id, link_id=link_id, type=RNS.Destination.LINK, mtu=RNS.Reticulum.MTU)
resource_hash = hashlib.sha256(b"rs19-resource").digest()
proof = hashlib.sha256(b"rs19-proof").digest()

proof_packet = RNS.Packet(link, resource_hash + proof, packet_type=RNS.Packet.PROOF,
                          context=RNS.Packet.RESOURCE_PRF)
proof_packet.pack()
request = RNS.Packet(link, proof_packet.get_hash(), context=RNS.Packet.CACHE_REQUEST)
request.pack()

print("rns", RNS.__version__)
print("proof_raw", proof_packet.raw.hex())
print("proof_hash", proof_packet.get_hash().hex())
print("cache_entry", umsgpack.packb([proof_packet.raw, None]).hex())
print("cache_request_raw", request.raw.hex())
