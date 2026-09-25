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
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)
        handle(c, length: 20)
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

    /// An axe: a broad bevelled blade with a bright cutting edge, fitted over the top of the handle,
    /// with a short poll on the back. Drawn pixel by pixel so the shape stays crisp.
    static func axe(_ material: String) -> Canvas? {
        guard let (edgeHex, bodyHex, lightHex, sparkHex) = heads[material] else { return nil }
        let c = Canvas(S)
        handle(c, length: 22)
        // K dark rim, D shadow near the handle, B body, L lit bevel, W cutting edge, S sparkle.
        let head = [
            "..KKK..............",
            ".KWLLKK............",
            ".KWLBBBKK..........",
            "KWLBBBBBBKK........",
            "KWLBBBBBBBDKK..KK..",
            "KWLBBBBBBBBDDKKDDK.",
            "KWLBBBBBBBBDDDBBDK.",
            "KWLBBBBBBBBDDKKDDK.",
            "KWLBBBBBBBDKK..KK..",
            "KWLBBBBBBKK........",
            ".KWLBBBKK..........",
            ".KWLLKK............",
            "..KKK..............",
        ]
        let colors: [Character: RGBA] = [
            "K": RGBA(hex: edgeHex).shade(0.7), "D": RGBA(hex: edgeHex), "B": RGBA(hex: bodyHex),
            "L": RGBA(hex: lightHex), "W": RGBA(hex: sparkHex).mix(RGBA(hex: lightHex), 0.35), "S": RGBA(hex: sparkHex),
        ]
        for (row, line) in head.enumerated() {
            for (col, ch) in line.enumerated() {
                if let color = colors[ch] { c.plot(8 + col, 2 + row, color) }
            }
        }
        c.plot(10, 6, RGBA(hex: sparkHex)); c.plot(10, 7, RGBA(hex: sparkHex))
        if material == "diamond" { c.plot(14, 8, RGBA(hex: sparkHex)); c.plot(11, 12, RGBA(hex: sparkHex).withAlpha(0.7)) }
        c.outline()
        return c
    }

    /// A sword: a tapered blade with a fuller down the middle and one lit side, a crossguard,
    /// a wrapped grip and a round pommel.
    static func sword(_ material: String) -> Canvas? {
        guard let (edgeHex, bodyHex, lightHex, sparkHex) = heads[material] else { return nil }
        let c = Canvas(S)
        let edge = RGBA(hex: edgeHex), body = RGBA(hex: bodyHex), light = RGBA(hex: lightHex), spark = RGBA(hex: sparkHex)
        let guardColors: [String: (UInt32, UInt32)] = [
            "wooden": (0x4A3018, 0x7A5230), "stone": (0x3A3C44, 0x62656F), "iron": (0x4A525E, 0x8A94A2), "diamond": (0xA8741C, 0xF0C24A),
        ]
        let (gDark, gLight) = guardColors[material] ?? (0x4A525E, 0x8A94A2)
        let grip = RGBA(hex: 0x4A2E1E), gripLight = RGBA(hex: 0x7A5034)
        // Local frame at the guard: s runs towards the tip (top-right), t across the blade.
        let guardAt = (x: 10.0, y: 22.0), r = 1 / 2.0.squareRoot()
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - guardAt.x, dy = Double(y) + 0.5 - guardAt.y
                let s = (dx - dy) * r, t = (dx + dy) * r
                if s > 0.6 && s < 23.5 {
                    let half = s < 18 ? 2.3 : 2.3 * (23.5 - s) / 5.5
                    guard abs(t) < half else { continue }
                    let shade: RGBA
                    if t < -half + 0.9 { shade = light } else if t > half - 0.9 { shade = edge } else if abs(t) < 0.5 && s > 2 && s < 16 { shade = edge.mix(body, 0.45) } else { shade = body }
                    c.plot(x, y, shade)
                } else if s > -1.2 && s <= 0.6 && abs(t) < 5.2 {
                    c.plot(x, y, s > -0.3 ? RGBA(hex: gLight) : RGBA(hex: gDark))   // crossguard
                } else if s > -6.8 && s <= -1.2 && abs(t) < 1.2 {
                    c.plot(x, y, Int((-s) * 1.2) % 2 == 0 ? grip : gripLight)    // wrapped grip
                } else if (s + 8.2) * (s + 8.2) + t * t < 3.4 {
                    c.plot(x, y, (s + 8.2) + t < 0 ? RGBA(hex: gDark) : RGBA(hex: gLight))   // pommel
                }
            }
        }
        c.plot(24, 7, spark); c.plot(22, 9, spark.withAlpha(0.7)); c.plot(18, 13, spark.withAlpha(0.5))
        c.outline()
        return c
    }

    /// The shared diagonal wooden handle with grain and a leather wrap near the bottom.
    private static func handle(_ c: Canvas, length: Int) {
        let wood = RGBA(hex: 0x8A5A30), woodDark = RGBA(hex: 0x5A3A1C), woodLight = RGBA(hex: 0xB07A44)
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)
        for i in 0..<length {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, wood)
            c.plot(x + 1, y, i % 4 == 1 ? woodDark : woodLight)
            c.plot(x, y + 1, woodDark)
        }
        for i in 1..<5 {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, i % 2 == 0 ? wrap : wrapLight)
            c.plot(x + 1, y, wrap)
            c.plot(x, y + 1, wrap)
        }
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
