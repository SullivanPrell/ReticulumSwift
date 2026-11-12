"""Prints the stamp vectors that StampsTests pins.

Captured with RNS 1.6.0:

    python -I scripts/capture-stamp-vectors.py

- `fp`: `cost_to_fp` for each cost, and the bytes `cost_to_bytes` packs it into (`Stamps.py:823-831`).
- `target`: `target_from_fp` as 33-byte big-endian hex (`Stamps.py:845`).
- `value`: `stamp_value` and `stamp_valid` at three costs for stamps found by a fixed search
  (`Stamps.py:104`, `191`).
- `workblock`: the SHA-256 of `stamp_workblock(material, expand_rounds=3)` (`Stamps.py:87`).
"""
import hashlib

import RNS
from RNS import Stamps

print("rns", RNS.__version__)
for cost in [0, 0.001, 1, 12.5, 15.8, 23.5, 25.0, 99.999, 100, 150, -3]:
    fp = Stamps.cost_to_fp(cost)
    print("fp", cost, fp, Stamps.cost_to_bytes(cost).hex(), Stamps.quantize_cost(cost))
for fp in [0, 1, 255, 256, 3200, 4045, 6016, 25600]:
    print("target", fp, Stamps.target_from_fp(fp).to_bytes(33, "big").hex())

workblock = hashlib.sha256(b"rs-160-stamps").digest()
for n in range(24):
    stamp = hashlib.sha256(b"stamp-%d" % n).digest()[:14]
    # Grind a few to land some values well above zero.
    k = 0
    while Stamps.stamp_value(workblock, stamp) < (n % 12):
        k += 1
        stamp = hashlib.sha256(b"stamp-%d-%d" % (n, k)).digest()[:14]
    v = Stamps.stamp_value(workblock, stamp)
    checks = [(c, Stamps.stamp_valid(stamp, c, workblock)) for c in (v, v + 1 / 256, int(v) or 1)]
    print("value", stamp.hex(), repr(v), " ".join(f"{c!r}:{int(ok)}" for c, ok in checks))

print("workblock", hashlib.sha256(Stamps.stamp_workblock(b"material", expand_rounds=3)).hexdigest())
print("workblock_noexpand", Stamps.stamp_workblock(b"material", expand_rounds=0).hex())

# Stamped announces (`Destination.py:348-357`), at a low DESTINATION_VALUE so capture is quick.
RNS.Transport.STAMP_DESTINATIONS = True
RNS.Transport.DESTINATION_VALUE = 8
RNS.Transport.register_destination = staticmethod(lambda destination: None)  # no running Transport
identity = RNS.Identity.from_bytes(bytes(range(64)))
destination = RNS.Destination(identity, RNS.Destination.IN, RNS.Destination.SINGLE, "rs160", "stamped")
destination.set_link_cost(7.25)
for app_data in [b"hello", None]:
    packet = destination._announce(app_data=app_data, send=False)
    packet.pack()
    print("announce", packet.raw.hex(), repr(destination.stamp_value), destination.stamp.hex())
print("identity_value", identity.get_value())
