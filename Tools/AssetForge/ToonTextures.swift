import Foundation
import DinoCraftCore

/// Toonland's blocks, painted in DinoCraft's own natural style: sunny meadow grass on rich loam,
/// pale limestone, birch woods with glowing sunblooms, polished checker tiles and a golden gateway.
enum ToonTextures {
    static let S = TexturePainter.S
    static let ink = RGBA(hex: 0x141414)

    static func add(to t: inout [String: Canvas]) {
        t["toon_grass_top"] = grassTop()
        t["toon_grass_side"] = grassSide()
        t["toon_soil"] = soil()
        t["toon_stone"] = stone()
        t["smile_flower"] = smileFlower()
        t["toon_log_side"] = logSide()
        t["toon_log_top"] = logTop()
        t["toon_leaves"] = leaves()
        t["checker_block"] = checker()
        t["toonland_portal"] = portal()
    }

    static func item(_ name: String) -> Canvas? {
        switch name {
        case "smile_trophy": return trophy()
        default: return nil
        }
    }

    /// Picks a colour from a dark-to-light list.
    private static func ramp(_ tones: [UInt32], _ t: Double) -> RGBA {
        RGBA(hex: tones[max(0, min(tones.count - 1, Int(t * Double(tones.count))))])
    }

    static let meadow: [UInt32] = [0x4E7A22, 0x62902A, 0x78A634, 0x8EBA40, 0xA8CC52]
    static let loam: [UInt32] = [0x3E2A1A, 0x523824, 0x664830, 0x7A5A3E]

    /// Sunny meadow grass: warm greens, lighter blades and the odd buttercup.
    static func grassTop() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1901)
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            return ramp(meadow, n.fbm(u, v, period: 4, octaves: 3) * 0.8 + Double(Hashing.unit(19, Int32(x), Int32(y), 0)) * 0.35)
        }
        var rng = SplitMix64(seed: 1902)
        for _ in 0..<26 { c[rng.nextInt(S), rng.nextInt(S)] = RGBA(hex: 0xB8DA62) }
        for _ in 0..<3 {
            let x = rng.nextInt(S), y = rng.nextInt(S)
            c[x, y] = RGBA(hex: 0xF4D23A); c[(x + 1) % S, y] = RGBA(hex: 0xE0B82A)
        }
        return c
    }

    /// Rich brown loam with small pebbles.
    static func soil() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1903)
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            return ramp(loam, n.fbm(u, v, period: 5, octaves: 3) * 0.85 + Double(Hashing.unit(23, Int32(x), Int32(y), 0)) * 0.3)
        }
        var rng = SplitMix64(seed: 1904)
        for _ in 0..<7 {
            let x = rng.nextInt(S), y = rng.nextInt(S)
            c[x, y] = RGBA(hex: 0x8C7A66); c[(x + 1) % S, y] = RGBA(hex: 0x6E5E4E)
        }
        return c
    }

    /// Loam with a ragged fringe of meadow grass along the top.
    static func grassSide() -> Canvas {
        let c = soil()
        let top = grassTop()
        for x in 0..<S {
            let edge = 6 + Int((Double(Hashing.unit(29, Int32(x), 0, 0)) * 5).rounded()) - (x % 5 == 2 ? 2 : 0)
            for y in 0..<edge { c[x, y] = top[x, y] }
            c[x, edge] = RGBA(hex: 0x4A6E20)
        }
        return c
    }

    /// Pale, warm limestone with soft cracks and tiny shell fossils.
    static func stone() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1905)
        let tones: [UInt32] = [0x8C8474, 0xA29A88, 0xB6AE9C, 0xC8C0AE, 0xD8D1C0]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let (d1, d2, _) = n.voronoi(u, v, cells: 4)
            if d2 - d1 < 0.025 { return RGBA(hex: 0x7C7464) }
            return ramp(tones, n.fbm(u, v, period: 4, octaves: 3) * 0.9 + 0.1)
        }
        var rng = SplitMix64(seed: 1906)
        for _ in 0..<3 {
            let x = Double(rng.nextInt(S - 6) + 3), y = Double(rng.nextInt(S - 6) + 3)
            for k in 0..<9 {
                let a = Double(k) * 0.7, r = 0.6 + Double(k) * 0.25
                c.plot(Int(x + cos(a) * r), Int(y + sin(a) * r), RGBA(hex: 0x8A826F))
            }
        }
        return c
    }

    /// Sunbloom: a glowing golden flower with a brown heart, on a leafy stem.
    static func smileFlower() -> Canvas {
        let c = Canvas(S)
        let stem = RGBA(hex: 0x3E6E22), leaf = RGBA(hex: 0x5A9030)
        c.line(16, 32, 16, 15, width: 1.8) { _ in stem }
        c.disc(12, 24, 2.4, leaf); c.disc(20, 21, 2.4, leaf)
        c.line(16, 26, 12, 24, width: 1) { _ in stem }; c.line(16, 23, 20, 21, width: 1) { _ in stem }
        for k in 0..<10 {
            let a = Double(k) / 10 * 2 * .pi
            c.disc(16 + cos(a) * 6, 11 + sin(a) * 6, 2.6, k % 2 == 0 ? RGBA(hex: 0xF6C832) : RGBA(hex: 0xE8A624))
        }
        c.disc(16, 11, 3.8, RGBA(hex: 0x6A4222))
        c.disc(15, 10, 1.6, RGBA(hex: 0x8A5C30))
        for (x, y) in [(15, 12), (17, 10), (16, 13), (18, 12)] { c.plot(x, y, RGBA(hex: 0x4A2C16)) }
        c.outline()
        return c
    }

    /// Birch bark: creamy white with dark lenticel streaks and grey shading.
    static func logSide() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1907)
        let tones: [UInt32] = [0xB8B2A4, 0xD2CCBE, 0xE4DFD2, 0xF0ECE2]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            var col = ramp(tones, n.fbm(u * 0.5, v * 2, period: 4, octaves: 2) * 0.8 + 0.2)
            if x % 16 == 0 || x % 16 == 15 { col = col.shade(0.88) }
            return col
        }
        var rng = SplitMix64(seed: 1908)
        for _ in 0..<14 {
            let x = rng.nextInt(S), y = rng.nextInt(S), len = 2 + rng.nextInt(4)
            for k in 0..<len { c[(x + k) % S, y] = RGBA(hex: k == 0 || k == len - 1 ? 0x5A544A : 0x2E2A24) }
        }
        return c
    }

    /// Birch rings: pale wood inside a thin bark edge.
    static func logTop() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let d = sqrt(pow(Double(x) - 15.5, 2) + pow(Double(y) - 15.5, 2))
            if d > 14.2 { return RGBA(hex: 0xE4DFD2) }
            if d > 13 { return RGBA(hex: 0x5A544A) }
            return Int(d) % 3 == 0 ? RGBA(hex: 0xC8A67A) : RGBA(hex: 0xDEC094)
        }
        return c
    }

    /// Birch leaves: bright, airy foliage with gaps.
    static func leaves() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1909)
        let tones: [UInt32] = [0x4E7E26, 0x66982E, 0x80B03A, 0x9CC84A]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let f = n.fbm(u, v, period: 6, octaves: 3)
            if Double(Hashing.unit(31, Int32(x), Int32(y), 0)) < 0.16 + (0.5 - f) * 0.3 { return RGBA(0, 0, 0, 0) }
            return ramp(tones, f * 0.9 + Double(Hashing.unit(37, Int32(x), Int32(y), 0)) * 0.25)
        }
        return c
    }

    /// Polished checker tiles of cream marble and dark slate, with fine veins and grout.
    static func checker() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1910)
        c.fill { x, y in
            let on = ((x / 8) + (y / 8)) % 2 == 0
            if x % 8 == 0 || y % 8 == 0 { return RGBA(hex: 0x6E665A) }        // grout
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let vein = abs(n.fbm(u * 1.5, v * 1.5, period: 4, octaves: 3) - 0.5) < 0.02
            if on { return vein ? RGBA(hex: 0x4A4E58) : RGBA(hex: 0x2C2F36).lighten(Double(Hashing.unit(41, Int32(x), Int32(y), 0)) * 0.06) }
            return vein ? RGBA(hex: 0xB4AA96) : RGBA(hex: 0xECE4D2).shade(1 - Double(Hashing.unit(43, Int32(x), Int32(y), 0)) * 0.05)
        }
        return c
    }

    /// The gateway: warm golden light swirling inward.
    static func portal() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let r = sqrt(dx * dx + dy * dy), a = atan2(dy, dx)
            let swirl = sin(a * 2 + r * 0.55) * 0.5 + 0.5
            return RGBA(1, 0.72 + swirl * 0.2, 0.25 + swirl * 0.3, 0.78)
        }
        return c
    }

    static func trophy() -> Canvas {
        let c = Canvas(S)
        let gold = RGBA(hex: 0xF2C23A), shade = RGBA(hex: 0xC8901E), shine = RGBA(hex: 0xFFF0A0)
        c.rect(10, 26, 12, 3, shade)
        c.rect(13, 22, 6, 4, gold)
        c.disc(16, 12, 9, gold)
        c.rect(7, 3, 18, 8, gold)
        c.disc(6, 10, 3.2, .clear); c.line(5, 7, 6, 13, width: 1.6) { _ in shade }
        c.line(27, 7, 26, 13, width: 1.6) { _ in shade }
        c.disc(12, 7, 1.5, shine)
        // Smiley face on the cup
        c.rect(13, 9, 2, 2, ink); c.rect(18, 9, 2, 2, ink)
        for x in 12...20 {
            let dx = Double(x) - 16
            c.plot(x, 14 + Int((1.5 - dx * dx / 10).rounded()), ink)
        }
        c.outline()
        return c
    }
}
