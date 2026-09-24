import Foundation
import DinoCraftCore

/// Hand-shaded pickaxes, a craggier bedrock and the Deep Slate of the deep layers.
enum BetterTextures {
    static let S = TexturePainter.S

    static func add(to t: inout [String: Canvas]) {
        t["bedrock"] = bedrock()
        t["deep_slate"] = deepSlate()
    }

    /// Head colours per material: (dark edge, body, highlight, sparkle).
    static let heads: [String: (UInt32, UInt32, UInt32, UInt32)] = [
        "wooden": (0x6B4424, 0xA8743F, 0xD6A266, 0xEBC48C),
        "stone": (0x4A4C54, 0x7E818C, 0xA9ACB6, 0xCDD0D8),
        "iron": (0x7C8591, 0xC4CAD3, 0xE8ECF1, 0xFFFFFF),
        "diamond": (0x138A84, 0x3FD9CE, 0x9BF6EE, 0xE8FFFD),
    ]

    /// A pickaxe drawn pixel by pixel: a curved two-pointed head with a bevel and
    /// highlights, bound to a grained handle with a leather wrap.
    static func pickaxe(_ material: String) -> Canvas? {
        guard let (edgeHex, bodyHex, lightHex, sparkHex) = heads[material] else { return nil }
        let c = Canvas(S)
        let edge = RGBA(hex: edgeHex), body = RGBA(hex: bodyHex), light = RGBA(hex: lightHex), spark = RGBA(hex: sparkHex)
        let wood = RGBA(hex: 0x8A5A30), woodDark = RGBA(hex: 0x5A3A1C), woodLight = RGBA(hex: 0xB07A44)
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)

        // Handle: diagonal from bottom-left to the head, with grain
        for i in 0..<20 {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, wood)
            c.plot(x + 1, y, i % 4 == 1 ? woodDark : woodLight)
            c.plot(x, y + 1, woodDark)
        }
        // Leather wrap near the bottom
        for i in 1..<5 {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, i % 2 == 0 ? wrap : wrapLight)
            c.plot(x + 1, y, wrap)
            c.plot(x, y + 1, wrap)
        }
        // Head: an arc of thick pixels centred on the top of the handle
        let cx = 21.0, cy = 11.0
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                // u runs across the handle (top-left to bottom-right); v points back down the handle.
                let u = (dx + dy) / 2.0.squareRoot(), v = (dy - dx) / 2.0.squareRoot()
                let arc = v - u * u / 16                        // an arch over the handle, points curving down
                let thickness = 3.1 - abs(u) * 0.16             // tapers to points
                guard abs(u) < 11.5, abs(arc) < thickness else { continue }
                let shade: RGBA
                if arc < -thickness * 0.35 { shade = light } else if arc > thickness * 0.35 { shade = edge } else { shade = body }
                c.plot(x, y, abs(u) > 10 ? edge : shade)
            }
        }
        // Binding where head meets handle, and a glint on the blade
        c.plot(20, 11, wrap); c.plot(21, 12, wrap); c.plot(21, 11, wrapLight); c.plot(22, 12, wrap)
        c.plot(17, 6, spark); c.plot(18, 6, spark.withAlpha(0.7)); c.plot(17, 7, spark.withAlpha(0.7))
        if material == "diamond" { c.plot(26, 16, spark); c.plot(25, 15, spark.withAlpha(0.6)) }
        c.outline()
        return c
    }

    /// Bedrock: dark, jagged chunks of rock with deep cracks and a few pale flecks.
    static func bedrock() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1313)
        let tones: [UInt32] = [0x121214, 0x1E1E22, 0x2C2C32, 0x3C3C44, 0x50505A, 0x6A6A74]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let (d1, d2, id) = n.voronoi(u, v, cells: 5)
            let rim = d2 - d1
            if rim < 0.035 { return RGBA(hex: 0x0A0A0C) }                        // cracks between chunks
            var level = Int(id % 4) + 1
            if rim > 0.1 && Hashing.unit(3, Int32(x), Int32(y), 0) < 0.25 { level += 1 }   // raised faces catch light
            return RGBA(hex: tones[max(0, min(tones.count - 1, level))])
        }
        var rng = SplitMix64(seed: 77)
        for _ in 0..<6 { c[rng.nextInt(S), rng.nextInt(S)] = RGBA(hex: 0x8A8A96) }
        return c
    }

    /// Deep Slate: dark blue-grey rock in thin tilted layers.
    static func deepSlate() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 2525)
        let tones: [UInt32] = [0x1C1F28, 0x262A35, 0x303543, 0x3B4151, 0x4A5163]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let layer = (y + x / 6) % 5
            let grain = n.fbm(u, v, period: 4, octaves: 3)
            var level = 2 + (layer == 0 ? -1 : 0) + (layer == 2 ? 1 : 0) + Int((grain - 0.5) * 3)
            if layer == 4 && x % 9 == 3 { level = 0 }
            return RGBA(hex: tones[max(0, min(tones.count - 1, level))])
        }
        return c
    }
}
