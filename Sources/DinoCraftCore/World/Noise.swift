import Foundation

/// Small, fast, deterministic PRNG (SplitMix64). Used for seeding and for all
/// world-generation randomness so identical seeds produce identical worlds.
public struct SplitMix64: Sendable {
    public var state: UInt64
    @inlinable public init(seed: UInt64) { state = seed }

    @inlinable public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    @inlinable public mutating func nextDouble() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    @inlinable public mutating func nextFloat() -> Float { Float(next() >> 40) * (1.0 / 16_777_216.0) }
    @inlinable public mutating func nextInt(_ upperBound: Int) -> Int { Int(next() % UInt64(max(1, upperBound))) }
}

public enum Hashing {
    /// Stateless positional hash → uniformly distributed 64-bit value.
    @inlinable public static func hash(_ seed: UInt64, _ x: Int32, _ y: Int32, _ z: Int32, salt: UInt64 = 0) -> UInt64 {
        var h = seed ^ (salt &* 0xD6E8_FEB8_6659_FD93)
        h ^= UInt64(bitPattern: Int64(x)) &* 0x9E37_79B9_7F4A_7C15
        h = (h ^ (h >> 32)) &* 0xD6E8_FEB8_6659_FD93
        h ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2_AE3D_27D4_EB4F
        h = (h ^ (h >> 32)) &* 0xD6E8_FEB8_6659_FD93
        h ^= UInt64(bitPattern: Int64(z)) &* 0x1656_67B1_9E37_79F9
        h = (h ^ (h >> 32)) &* 0xD6E8_FEB8_6659_FD93
        return h ^ (h >> 29)
    }

    /// Uniform value in [0, 1) for a position.
    @inlinable public static func unit(_ seed: UInt64, _ x: Int32, _ y: Int32, _ z: Int32, salt: UInt64 = 0) -> Float {
        Float(hash(seed, x, y, z, salt: salt) >> 40) * (1.0 / 16_777_216.0)
    }

    /// Stable 64-bit seed from arbitrary text (FNV-1a), so "Dino World" as a seed
    /// string always maps to the same numeric seed.
    public static func seed(from text: String) -> UInt64 {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Int64(trimmed) { return UInt64(bitPattern: n) }
        var h: UInt64 = 0xCBF2_9CE4_8422_2325
        for b in trimmed.utf8 { h = (h ^ UInt64(b)) &* 0x0000_0100_0000_01B3 }
        return h
    }
}

/// Seeded simplex noise in 2D and 3D (after Stefan Gustavson's reference
/// description). Output range is approximately [-1, 1].
public final class SimplexNoise: @unchecked Sendable {
    private let perm: UnsafeMutablePointer<Int32>
    private let permMod12: UnsafeMutablePointer<Int32>

    private static let grad3: [(Double, Double, Double)] = [
        (1, 1, 0), (-1, 1, 0), (1, -1, 0), (-1, -1, 0),
        (1, 0, 1), (-1, 0, 1), (1, 0, -1), (-1, 0, -1),
        (0, 1, 1), (0, -1, 1), (0, 1, -1), (0, -1, -1),
    ]
    private let gx: UnsafeMutablePointer<Double>
    private let gy: UnsafeMutablePointer<Double>
    private let gz: UnsafeMutablePointer<Double>

    private static let F2 = 0.5 * (sqrt(3.0) - 1.0)
    private static let G2 = (3.0 - sqrt(3.0)) / 6.0
    private static let F3 = 1.0 / 3.0
    private static let G3 = 1.0 / 6.0

    public init(seed: UInt64) {
        perm = .allocate(capacity: 512)
        permMod12 = .allocate(capacity: 512)
        gx = .allocate(capacity: 12); gy = .allocate(capacity: 12); gz = .allocate(capacity: 12)
        for (i, g) in SimplexNoise.grad3.enumerated() { gx[i] = g.0; gy[i] = g.1; gz[i] = g.2 }

        var table = Array(0..<256).map { Int32($0) }
        var rng = SplitMix64(seed: seed)
        for i in stride(from: 255, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            table.swapAt(i, j)
        }
        for i in 0..<512 {
            perm[i] = table[i & 255]
            permMod12[i] = perm[i] % 12
        }
    }

    deinit {
        perm.deallocate(); permMod12.deallocate()
        gx.deallocate(); gy.deallocate(); gz.deallocate()
    }

    @inline(__always) private func fastFloor(_ v: Double) -> Int {
        let i = Int(v)
        return v < Double(i) ? i - 1 : i
    }

    public func noise2(_ xin: Double, _ yin: Double) -> Double {
        let s = (xin + yin) * SimplexNoise.F2
        let i = fastFloor(xin + s), j = fastFloor(yin + s)
        let t = Double(i + j) * SimplexNoise.G2
        let x0 = xin - (Double(i) - t), y0 = yin - (Double(j) - t)
        let i1: Int, j1: Int
        if x0 > y0 { i1 = 1; j1 = 0 } else { i1 = 0; j1 = 1 }
        let x1 = x0 - Double(i1) + SimplexNoise.G2, y1 = y0 - Double(j1) + SimplexNoise.G2
        let x2 = x0 - 1 + 2 * SimplexNoise.G2, y2 = y0 - 1 + 2 * SimplexNoise.G2
        let ii = i & 255, jj = j & 255

        var n0 = 0.0, n1 = 0.0, n2 = 0.0
        var t0 = 0.5 - x0 * x0 - y0 * y0
        if t0 > 0 {
            let g = Int(permMod12[ii + Int(perm[jj])])
            t0 *= t0; n0 = t0 * t0 * (gx[g] * x0 + gy[g] * y0)
        }
        var t1 = 0.5 - x1 * x1 - y1 * y1
        if t1 > 0 {
            let g = Int(permMod12[ii + i1 + Int(perm[jj + j1])])
            t1 *= t1; n1 = t1 * t1 * (gx[g] * x1 + gy[g] * y1)
        }
        var t2 = 0.5 - x2 * x2 - y2 * y2
        if t2 > 0 {
            let g = Int(permMod12[ii + 1 + Int(perm[jj + 1])])
            t2 *= t2; n2 = t2 * t2 * (gx[g] * x2 + gy[g] * y2)
        }
        return 70.0 * (n0 + n1 + n2)
    }

    public func noise3(_ xin: Double, _ yin: Double, _ zin: Double) -> Double {
        let s = (xin + yin + zin) * SimplexNoise.F3
        let i = fastFloor(xin + s), j = fastFloor(yin + s), k = fastFloor(zin + s)
        let t = Double(i + j + k) * SimplexNoise.G3
        let x0 = xin - (Double(i) - t), y0 = yin - (Double(j) - t), z0 = zin - (Double(k) - t)

        let i1, j1, k1, i2, j2, k2: Int
        if x0 >= y0 {
            if y0 >= z0 { (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 1, 0) }
            else if x0 >= z0 { (i1, j1, k1, i2, j2, k2) = (1, 0, 0, 1, 0, 1) }
            else { (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 1, 0, 1) }
        } else {
            if y0 < z0 { (i1, j1, k1, i2, j2, k2) = (0, 0, 1, 0, 1, 1) }
            else if x0 < z0 { (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 0, 1, 1) }
            else { (i1, j1, k1, i2, j2, k2) = (0, 1, 0, 1, 1, 0) }
        }
        let G3 = SimplexNoise.G3
        let x1 = x0 - Double(i1) + G3, y1 = y0 - Double(j1) + G3, z1 = z0 - Double(k1) + G3
        let x2 = x0 - Double(i2) + 2 * G3, y2 = y0 - Double(j2) + 2 * G3, z2 = z0 - Double(k2) + 2 * G3
        let x3 = x0 - 1 + 3 * G3, y3 = y0 - 1 + 3 * G3, z3 = z0 - 1 + 3 * G3
        let ii = i & 255, jj = j & 255, kk = k & 255

        var n = 0.0
        var t0 = 0.6 - x0 * x0 - y0 * y0 - z0 * z0
        if t0 > 0 {
            let g = Int(permMod12[ii + Int(perm[jj + Int(perm[kk])])])
            t0 *= t0; n += t0 * t0 * (gx[g] * x0 + gy[g] * y0 + gz[g] * z0)
        }
        var t1 = 0.6 - x1 * x1 - y1 * y1 - z1 * z1
        if t1 > 0 {
            let g = Int(permMod12[ii + i1 + Int(perm[jj + j1 + Int(perm[kk + k1])])])
            t1 *= t1; n += t1 * t1 * (gx[g] * x1 + gy[g] * y1 + gz[g] * z1)
        }
        var t2 = 0.6 - x2 * x2 - y2 * y2 - z2 * z2
        if t2 > 0 {
            let g = Int(permMod12[ii + i2 + Int(perm[jj + j2 + Int(perm[kk + k2])])])
            t2 *= t2; n += t2 * t2 * (gx[g] * x2 + gy[g] * y2 + gz[g] * z2)
        }
        var t3 = 0.6 - x3 * x3 - y3 * y3 - z3 * z3
        if t3 > 0 {
            let g = Int(permMod12[ii + 1 + Int(perm[jj + 1 + Int(perm[kk + 1])])])
            t3 *= t3; n += t3 * t3 * (gx[g] * x3 + gy[g] * y3 + gz[g] * z3)
        }
        return 32.0 * n
    }

    /// Fractal Brownian motion, normalized to roughly [-1, 1].
    public func fbm2(_ x: Double, _ y: Double, octaves: Int, lacunarity: Double = 2.0, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += noise2(x * freq, y * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }

    public func fbm3(_ x: Double, _ y: Double, _ z: Double, octaves: Int, lacunarity: Double = 2.0, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 1.0, freq = 1.0, norm = 0.0
        for _ in 0..<octaves {
            sum += noise3(x * freq, y * freq, z * freq) * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }

    /// Ridged multifractal in [0, 1]; sharp crests for mountain ranges.
    public func ridged2(_ x: Double, _ y: Double, octaves: Int, lacunarity: Double = 2.0, gain: Double = 0.5) -> Double {
        var sum = 0.0, amp = 0.5, freq = 1.0, norm = 0.0, weight = 1.0
        for _ in 0..<octaves {
            var n = 1.0 - abs(noise2(x * freq, y * freq))
            n *= n
            n *= weight
            weight = min(1.0, max(0.0, n * 2.0))
            sum += n * amp
            norm += amp
            amp *= gain
            freq *= lacunarity
        }
        return sum / norm
    }
}
