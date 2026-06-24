// DeterministicEd25519.swift
// RFC 8032 deterministic Ed25519 signing.
//
// Apple CryptoKit uses a hedged (non-deterministic) Ed25519 variant: signing
// the same message twice produces different bytes.  Python RNS verifies IFAC
// codes by re-signing and comparing, which requires deterministic output.
// This implementation is wire-compatible with Python's pure25519 library.

import CryptoKit
import Foundation

// MARK: - BigUInt (little-endian, [UInt32] limbs)

/// Arbitrary-precision unsigned integer used only for the Ed25519 field/scalar
/// arithmetic inside this file.  Not part of the public API.
private struct BigUInt: Comparable, Equatable {
    var limbs: [UInt32]   // little-endian, no trailing zeros

    // MARK: Initialise

    init() { limbs = [] }
    init(_ v: UInt64) {
        if v == 0 { limbs = [] }
        else if v <= 0xFFFF_FFFF { limbs = [UInt32(v)] }
        else { limbs = [UInt32(v & 0xFFFF_FFFF), UInt32(v >> 32)] }
    }
    /// From little-endian byte array.
    init(le bytes: [UInt8]) {
        var ls: [UInt32] = []
        var i = 0
        while i < bytes.count {
            var w: UInt32 = 0
            for j in 0..<4 where i + j < bytes.count {
                w |= UInt32(bytes[i + j]) << (j * 8)
            }
            ls.append(w)
            i += 4
        }
        limbs = ls
        trim()
    }
    /// From big-endian hex string (e.g. "7fff…ed").
    init(hex h: String) {
        let s = h.count % 2 == 0 ? h : "0" + h
        var bytes: [UInt8] = []
        var idx = s.startIndex
        while idx < s.endIndex {
            let next = s.index(idx, offsetBy: 2)
            bytes.append(UInt8(s[idx..<next], radix: 16)!)
            idx = next
        }
        self.init(le: bytes.reversed())   // hex is big-endian; we store LE
    }
    init(limbs ls: [UInt32]) { self.limbs = ls; trim() }

    mutating func trim() { while limbs.last == 0 { limbs.removeLast() } }

    // MARK: Properties

    var isZero: Bool { limbs.isEmpty }
    var bitLength: Int {
        guard let top = limbs.last else { return 0 }
        return (limbs.count - 1) * 32 + (32 - top.leadingZeroBitCount)
    }
    func bit(_ i: Int) -> Bool {
        let (w, b) = (i / 32, i % 32)
        return w < limbs.count && (limbs[w] >> b) & 1 == 1
    }

    // MARK: Compare

    static func == (a: Self, b: Self) -> Bool { a.limbs == b.limbs }
    static func < (a: Self, b: Self) -> Bool {
        let n = max(a.limbs.count, b.limbs.count)
        for i in stride(from: n - 1, through: 0, by: -1) {
            let al = i < a.limbs.count ? a.limbs[i] : 0
            let bl = i < b.limbs.count ? b.limbs[i] : 0
            if al < bl { return true }
            if al > bl { return false }
        }
        return false
    }

    // MARK: Arithmetic

    static func + (a: Self, b: Self) -> Self {
        let n = max(a.limbs.count, b.limbs.count)
        var r = [UInt32](repeating: 0, count: n + 1)
        var carry: UInt64 = 0
        for i in 0...n {
            let al: UInt64 = i < a.limbs.count ? UInt64(a.limbs[i]) : 0
            let bl: UInt64 = i < b.limbs.count ? UInt64(b.limbs[i]) : 0
            let s = al + bl + carry
            r[i] = UInt32(s & 0xFFFF_FFFF); carry = s >> 32
        }
        return BigUInt(limbs: r)
    }

    /// Precondition: a >= b
    static func - (a: Self, b: Self) -> Self {
        var r = [UInt32](repeating: 0, count: a.limbs.count)
        var borrow: Int64 = 0
        for i in 0..<a.limbs.count {
            let al = Int64(a.limbs[i])
            let bl = i < b.limbs.count ? Int64(b.limbs[i]) : 0
            var d = al - bl - borrow
            if d < 0 { d += 1 << 32; borrow = 1 } else { borrow = 0 }
            r[i] = UInt32(d)
        }
        return BigUInt(limbs: r)
    }

    static func * (a: Self, b: Self) -> Self {
        guard !a.isZero, !b.isZero else { return BigUInt() }
        var r = [UInt32](repeating: 0, count: a.limbs.count + b.limbs.count)
        for i in 0..<a.limbs.count {
            var carry: UInt64 = 0
            for j in 0..<b.limbs.count {
                let p = UInt64(a.limbs[i]) * UInt64(b.limbs[j])
                      + UInt64(r[i + j]) + carry
                r[i + j] = UInt32(p & 0xFFFF_FFFF); carry = p >> 32
            }
            r[i + b.limbs.count] += UInt32(carry)
        }
        return BigUInt(limbs: r)
    }

    static func << (a: Self, n: Int) -> Self {
        guard !a.isZero, n > 0 else { return a }
        let (wsh, bsh) = (n / 32, n % 32)
        var r = [UInt32](repeating: 0, count: a.limbs.count + wsh + 1)
        var carry: UInt64 = 0
        for i in 0..<a.limbs.count {
            let v = (UInt64(a.limbs[i]) << bsh) | carry
            r[i + wsh] = UInt32(v & 0xFFFF_FFFF); carry = v >> 32
        }
        if carry > 0 { r[a.limbs.count + wsh] = UInt32(carry) }
        return BigUInt(limbs: r)
    }

    static func >> (a: Self, n: Int) -> Self {
        guard !a.isZero, n > 0 else { return a }
        let (wsh, bsh) = (n / 32, n % 32)
        guard wsh < a.limbs.count else { return BigUInt() }
        let nc = a.limbs.count - wsh
        var r = [UInt32](repeating: 0, count: nc)
        for i in 0..<nc {
            let lo = UInt64(a.limbs[i + wsh]) >> bsh
            let hi: UInt64 = bsh > 0 && i + wsh + 1 < a.limbs.count
                           ? UInt64(a.limbs[i + wsh + 1]) << (32 - bsh) : 0
            r[i] = UInt32((lo | hi) & 0xFFFF_FFFF)
        }
        return BigUInt(limbs: r)
    }

    static func & (a: Self, b: Self) -> Self {
        let n = min(a.limbs.count, b.limbs.count)
        return BigUInt(limbs: (0..<n).map { a.limbs[$0] & b.limbs[$0] })
    }

    /// General modular reduction (binary shift-subtract). O(bitLen) iterations.
    static func % (a: Self, m: Self) -> Self {
        if a < m { return a }
        if a == m { return BigUInt() }
        let shift = a.bitLength - m.bitLength
        var rem = a
        var div = m << shift
        for _ in 0...shift {
            if rem >= div { rem = rem - div }
            div = div >> 1
        }
        return rem
    }

    /// Left-to-right binary modular exponentiation.
    func powmod(_ exp: BigUInt, _ mod: BigUInt) -> BigUInt {
        guard !exp.isZero else { return BigUInt(1) % mod }
        var base = self % mod
        var result = BigUInt(1)
        var e = exp
        while !e.isZero {
            if e.bit(0) { result = (result * base) % mod }
            base = (base * base) % mod
            e = e >> 1
        }
        return result
    }

    // MARK: Encode

    /// Little-endian, zero-padded to `n` bytes.
    func toBytes(count n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n)
        for (wi, limb) in limbs.enumerated() {
            let base = wi * 4
            for bi in 0..<4 where base + bi < n {
                out[base + bi] = UInt8((limb >> (bi * 8)) & 0xFF)
            }
        }
        return out
    }
}

// MARK: - Ed25519 constants (all precomputed, verified against RFC 8032)

// Q = 2^255 - 19  (field prime)
private let Q = BigUInt(hex: "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed")

// L = 2^252 + 27742317777372353535851937790883648493  (group order)
private let L = BigUInt(hex: "1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed")

// d = -121665/121666 mod Q
private let dConst = BigUInt(hex: "52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3")

// 2*d mod Q
private let d2 = BigUInt(hex: "2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159")

// Base point B affine coordinates
private let Bx = BigUInt(hex: "216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a")
private let By = BigUInt(hex: "6666666666666666666666666666666666666666666666666666666666666658")

// mask255 = 2^255 - 1
private let mask255 = BigUInt(hex: "7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")

// MARK: - Field arithmetic mod Q

/// a + b mod Q  (a, b < Q)
private func qadd(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
    var r = a + b
    if r >= Q { r = r - Q }
    return r
}

/// a - b mod Q  (a, b < Q)
private func qsub(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
    if a >= b { return a - b }
    return (Q - b) + a   // = Q + a - b; since a < b, result ∈ [1, Q-1]
}

/// a * b mod Q
private func qmul(_ a: BigUInt, _ b: BigUInt) -> BigUInt {
    fastReduceQ(a * b)
}

/// -a mod Q
private func qneg(_ a: BigUInt) -> BigUInt {
    a.isZero ? BigUInt() : Q - a
}

/// a^(Q-2) mod Q  (multiplicative inverse)
private func qinv(_ a: BigUInt) -> BigUInt {
    a.powmod(Q - BigUInt(2), Q)
}

/// Reduce x mod Q using the special form Q = 2^255 - 19.
/// Handles x < Q^2 (≈ 2^510) in two rounds without general division.
private func fastReduceQ(_ x: BigUInt) -> BigUInt {
    // Round 1: x = (x mod 2^255) + 19*(x >> 255)
    let lo1 = x & mask255
    let hi1 = x >> 255
    if hi1.isZero { return lo1 >= Q ? lo1 - Q : lo1 }
    var r = lo1 + BigUInt(19) * hi1      // < 2^260 for x < Q^2
    // Round 2
    let lo2 = r & mask255
    let hi2 = r >> 255
    if !hi2.isZero { r = lo2 + BigUInt(19) * hi2 }   // r < Q + 627 < 2Q
    if r >= Q { r = r - Q }
    return r
}

// MARK: - Extended Edwards point (X:Y:Z:T), x=X/Z, y=Y/Z, T=XY/Z

private struct Pt {
    var X, Y, Z, T: BigUInt

    static let identity = Pt(X: .init(), Y: .init(1), Z: .init(1), T: .init())

    // Unified point addition (add-2008-hwcd-3)
    func add(_ o: Pt) -> Pt {
        let A = qmul(qsub(Y, X), qsub(o.Y, o.X))
        let B = qmul(qadd(Y, X), qadd(o.Y, o.X))
        let C = qmul(T, qmul(d2, o.T))
        let D = qmul(qadd(Z, Z), o.Z)          // 2*Z1*Z2
        let E = qsub(B, A)
        let F = qsub(D, C)
        let G = qadd(D, C)
        let H = qadd(B, A)
        return Pt(X: qmul(E, F), Y: qmul(G, H), Z: qmul(F, G), T: qmul(E, H))
    }

    // Point doubling (dbl-2008-hwcd)
    func doubled() -> Pt {
        let A  = qmul(X, X)
        let B  = qmul(Y, Y)
        let C  = qadd(qmul(Z, Z), qmul(Z, Z))  // 2*Z^2
        let D  = qneg(A)
        let E  = qsub(qsub(qmul(qadd(X, Y), qadd(X, Y)), A), B)   // (X+Y)^2-A-B
        let G  = qadd(D, B)
        let F  = qsub(G, C)
        let H  = qsub(D, B)
        return Pt(X: qmul(E, F), Y: qmul(G, H), Z: qmul(F, G), T: qmul(E, H))
    }

    /// Compressed 32-byte encoding (RFC 8032 §5.1.2).
    var encodedBytes: [UInt8] {
        let zi = qinv(Z)
        let x  = qmul(X, zi)
        let y  = qmul(Y, zi)
        var out = y.toBytes(count: 32)    // little-endian y
        if x.bit(0) { out[31] |= 0x80 }  // sign bit = low bit of x
        return out
    }
}

/// Scalar multiplication of the Ed25519 base point B.
/// `s` must be in [0, L) for correct results.
private func scalarMultBase(_ s: BigUInt) -> Pt {
    guard !s.isZero else { return .identity }
    let base = Pt(X: Bx, Y: By, Z: .init(1), T: qmul(Bx, By))
    var result = Pt.identity
    var P = base
    for i in 0..<s.bitLength {
        if s.bit(i) { result = result.add(P) }
        P = P.doubled()
    }
    return result
}

// MARK: - Public API

/// RFC 8032 deterministic Ed25519 signing, wire-compatible with Python RNS's
/// `Identity.sign()` (backed by pure25519 / eddsa.py).
///
/// Usage: IFAC code generation only.  General signing should use
/// Apple CryptoKit's `Curve25519.Signing.PrivateKey` for its security properties.
public enum DeterministicEd25519 {

    /// Signs `message` with the given 32-byte Ed25519 `seed`.
    /// Returns a 64-byte signature: R (32 bytes) || S (32 bytes).
    public static func sign(_ message: Data, seed: Data) -> Data {
        precondition(seed.count == 32, "Ed25519 seed must be exactly 32 bytes")
        let msgBytes = [UInt8](message)

        // 1. Expand seed with SHA-512
        let h      = [UInt8](SHA512.hash(data: seed))
        var aBytes = Array(h[0..<32])
        let bBytes = Array(h[32..<64])

        // 2. Clamp the private scalar (RFC 8032 §5.1.5)
        aBytes[0]  &= 0xF8   // clear low 3 bits
        aBytes[31] &= 0x7F   // clear bit 255
        aBytes[31] |= 0x40   // set bit 254

        let a = BigUInt(le: aBytes)                   // private scalar a ∈ [2^254, 2^255)

        // 3. Public key A = (a mod L) * B
        let A_bytes = scalarMultBase(a % L).encodedBytes

        // 4. Nonce r = SHA-512(b || M) as a little-endian integer
        let rHash = [UInt8](SHA512.hash(data: Data(bBytes + msgBytes)))
        let r     = BigUInt(le: rHash)                // 512-bit nonce, not yet reduced

        // 5. R = (r mod L) * B
        let R_bytes = scalarMultBase(r % L).encodedBytes

        // 6. k = SHA-512(R || A || M) as a little-endian integer
        let kHash = [UInt8](SHA512.hash(data: Data(R_bytes + A_bytes + msgBytes)))
        let k     = BigUInt(le: kHash)                // 512-bit

        // 7. S = (r + k * a) mod L
        //    Using full (un-reduced) r and a gives the same result mod L.
        let S       = (r + k * a) % L
        let S_bytes = S.toBytes(count: 32)

        return Data(R_bytes + S_bytes)
    }

    /// Returns the 32-byte Ed25519 public key for the given 32-byte seed.
    public static func publicKey(forSeed seed: Data) -> Data {
        precondition(seed.count == 32, "Ed25519 seed must be exactly 32 bytes")
        let h      = [UInt8](SHA512.hash(data: seed))
        var aBytes = Array(h[0..<32])
        aBytes[0]  &= 0xF8
        aBytes[31] &= 0x7F
        aBytes[31] |= 0x40
        return Data(scalarMultBase(BigUInt(le: aBytes) % L).encodedBytes)
    }
}
