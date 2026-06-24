# Third-Party Notices

ReticulumSwift is a Swift port of, and a derivative work of, the original
Reticulum Network Stack:

> **Reticulum** — Copyright (c) 2016-2026 Mark Qvist — Reticulum License
> https://github.com/markqvist/Reticulum

ReticulumSwift adopts the same **Reticulum License** (see [`LICENSE`](../LICENSE)).

This repository also ships a **prebuilt binary** of the i2pd daemon, used to
implement the I2P interface. Its license and the licenses of the libraries it
statically links are reproduced below.

---

## i2pd (`Resources/CI2PD.xcframework`)

**i2pd** — Copyright (c) 2013-2026, The PurpleI2P Project — BSD 3-Clause License
https://github.com/PurpleI2P/i2pd

```
Copyright (c) 2013-2026, The PurpleI2P Project

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are
permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of
conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of
conditions and the following disclaimer in the documentation and/or other materials
provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors may be used
to endorse or promote products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR
TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

### Libraries statically linked into the i2pd binary

The `CI2PD.xcframework` static library also embeds:

| Component | License | Project |
|-----------|---------|---------|
| Boost     | Boost Software License 1.0 | https://www.boost.org |
| OpenSSL   | Apache License 2.0 (OpenSSL 3.x) | https://www.openssl.org |
| zlib      | zlib License (linked from the platform SDK) | https://zlib.net |

To rebuild the xcframework from source — and produce your own attribution for
the exact versions you link — see [`CONTRIBUTING.md`](../CONTRIBUTING.md#rebuilding-ci2pd).

---

## CryptoKit / libbz2 / libz

ReticulumSwift links the system **CryptoKit** framework and the system
**libbz2** / **libz** libraries that ship with every Apple SDK. These are not
redistributed by this project.
