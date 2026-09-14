import Foundation
import DinoCraftCore

/// Textures for the blocks that come with the newer biomes.
enum BiomeTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static func add(to t: inout [String: Canvas]) {
        t["pink_leaves"] = T.paintLeaves(301, palette: Palette([0xB8487A, 0xD86A9A, 0xEE8AB8, 0xF6AACC, 0xFFD0E4]), coverage: 0.78)
        t["silver_leaves"] = T.paintLeaves(302, palette: Palette([0x7A9A3A, 0x94B24A, 0xAECA5E, 0xC6DC78, 0xDCEC9A]), coverage: 0.74)
        t["silver_log_side"] = silverBark()
        t["silver_log_top"] = T.paintLogTop(303, bark: Palette([0xB8B4AA, 0xC8C4BA, 0xD8D4CA, 0xE6E2D8, 0xF2EEE4]), core: [0xE0C89A, 0xC8A878, 0xB8986A])
        t["mushroom_cap"] = mushroomCap()
        t["mushroom_stem"] = mushroomStem()
    }

    static func silverBark() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(304)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            return RGBA(hex: 0xE8E4DA).mix(RGBA(hex: 0xD2CEC4), n.value(u * 0.5, v * 2, period: 6))
        }
        var rng = SplitMix64(seed: 305)
        for _ in 0..<14 {
            let x0 = rng.nextInt(S), y0 = rng.nextInt(S), len = 2 + rng.nextInt(6)
            for dx in 0..<len { c[x0 + dx, y0] = RGBA(hex: 0x3A3630).shade(0.9 + rng.nextDouble() * 0.2) }
            if rng.nextInt(2) == 0 { for dx in 1..<max(2, len - 1) { c[x0 + dx, y0 + 1] = RGBA(hex: 0x6A6660) } }
        }
        return c
    }

    static func mushroomCap() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(306)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            return RGBA(hex: 0xC8302A).mix(RGBA(hex: 0xA82620), n.fbm(u, v, period: 3, octaves: 2))
        }
        var rng = SplitMix64(seed: 307)
        for _ in 0..<7 {
            let x = Double(3 + rng.nextInt(26)), y = Double(3 + rng.nextInt(26)), r = 1.8 + rng.nextDouble() * 1.8
            for dy in -3...3 {
                for dx in -3...3 where Double(dx * dx + dy * dy) <= r * r {
                    c[Int(x) + dx, Int(y) + dy] = RGBA(hex: 0xF2EBD6).shade(0.94 + rng.nextDouble() * 0.06)
                }
            }
        }
        return c
    }

    static func mushroomStem() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let fibre = T.hash01(308, x, y / 4)
            return RGBA(hex: 0xE6DCC0).mix(RGBA(hex: 0xC8BC9E), fibre * 0.6)
        }
        return c
    }
}
