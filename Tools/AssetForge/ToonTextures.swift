import Foundation
import DinoCraftCore

/// Toonland: black-and-white cartoon art with bold ink outlines, like an old animated short.
enum ToonTextures {
    static let S = TexturePainter.S
    static let ink = RGBA(hex: 0x141414)
    static let paper = RGBA(hex: 0xF4F4F0)
    static let light = RGBA(hex: 0xDADADA)
    static let mid = RGBA(hex: 0x9A9A9A)
    static let dark = RGBA(hex: 0x5A5A5A)

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

    static func grassTop() -> Canvas {
        let c = Canvas(S, fill: paper)
        var rng = SplitMix64(seed: 901)
        for _ in 0..<9 {
            let x = Double(rng.nextInt(S)), y = Double(rng.nextInt(S))
            // A little "v" tuft
            c.line(x - 1.5, y - 2, x, y, width: 1) { _ in ink }
            c.line(x + 1.5, y - 2, x, y, width: 1) { _ in ink }
        }
        for _ in 0..<14 { c[rng.nextInt(S), rng.nextInt(S)] = light }
        return c
    }

    static func soil() -> Canvas {
        let c = Canvas(S, fill: mid)
        var rng = SplitMix64(seed: 902)
        for _ in 0..<10 {
            let x = Double(rng.nextInt(S)), y = Double(rng.nextInt(S))
            c.disc(x, y, 1.6, dark)
            c.disc(x - 0.5, y - 0.5, 0.7, light)
        }
        for _ in 0..<12 { c[rng.nextInt(S), rng.nextInt(S)] = ink }
        return c
    }

    static func grassSide() -> Canvas {
        let c = soil()
        for x in 0..<S {
            // Scalloped white grass band with an ink edge
            let edge = 7 + Int((sin(Double(x) / Double(S) * 2 * .pi * 4) * 1.6).rounded())
            for y in 0..<edge { c[x, y] = paper }
            c[x, edge] = ink
            c[x, edge + 1] = ink.withAlpha(1).mix(mid, 0.5)
        }
        return c
    }

    static func stone() -> Canvas {
        let c = Canvas(S, fill: light)
        var rng = SplitMix64(seed: 903)
        // Round cartoon pebbles, outlined in ink
        for _ in 0..<7 {
            let x = Double(rng.nextInt(S)), y = Double(rng.nextInt(S)), r = 3.0 + Double(rng.nextInt(3))
            for dy in -1...1 {
                for dx in -1...1 {
                    let ox = Double(dx * S), oy = Double(dy * S)
                    c.disc(x + ox, y + oy, r + 1, ink)
                    c.disc(x + ox, y + oy, r, RGBA(hex: 0xC4C4C4))
                    c.disc(x + ox - r * 0.35, y + oy - r * 0.35, r * 0.35, paper)
                }
            }
        }
        return c
    }

    static func smileFlower() -> Canvas {
        let c = Canvas(S)
        c.line(16, 32, 16, 16, width: 1.8) { _ in ink }
        c.disc(12, 25, 2.2, dark); c.disc(20, 23, 2.2, dark)
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi
            c.disc(16 + cos(a) * 6.5, 11 + sin(a) * 6.5, 3.0, paper)
        }
        c.disc(16, 11, 5, RGBA(hex: 0xE8E8E8))
        // Face: two eyes and a big smile
        c.rect(14, 8, 1, 2, ink); c.rect(18, 8, 1, 2, ink)
        for x in 13...19 {
            let dx = Double(x) - 16
            c.plot(x, 12 + Int((1.6 - dx * dx / 6).rounded()), ink)
        }
        c.outline(ink)
        return c
    }

    static func logSide() -> Canvas {
        let c = Canvas(S, fill: paper)
        for x in stride(from: 2, to: S, by: 8) {
            for y in 0..<S {
                let wobble = Int((sin(Double(y) / 5 + Double(x)) * 1.2).rounded())
                c[x + wobble, y] = ink
            }
        }
        c.disc(22, 12, 2, ink); c.disc(22, 12, 1, light)
        return c
    }

    static func logTop() -> Canvas {
        let c = Canvas(S, fill: paper)
        for y in 0..<S {
            for x in 0..<S {
                let d = sqrt(pow(Double(x) - 15.5, 2) + pow(Double(y) - 15.5, 2))
                if d > 14.5 { c[x, y] = ink }
                else if Int(d) % 4 == 0 { c[x, y] = mid }
            }
        }
        return c
    }

    static func leaves() -> Canvas {
        let c = Canvas(S)
        // Overlapping puffs; the ink outline comes from drawing a bigger dark disc first
        let puffs: [(Double, Double, Double)] = [(8, 8, 7), (24, 7, 7), (16, 17, 8), (6, 25, 7), (26, 25, 7), (0, 16, 5), (32, 16, 5)]
        for (x, y, r) in puffs {
            c.disc(x, y, r + 1, ink)
        }
        for (x, y, r) in puffs {
            c.disc(x, y, r, paper)
            c.disc(x - r * 0.3, y - r * 0.3, r * 0.3, RGBA(hex: 0xFFFFFF))
            c.disc(x + r * 0.35, y + r * 0.4, r * 0.25, light)
        }
        return c
    }

    static func checker() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let on = ((x / 8) + (y / 8)) % 2 == 0
            let edge = x % 8 == 0 || y % 8 == 0
            return on ? (edge ? RGBA(hex: 0x2A2A2A) : ink) : (edge ? light : paper)
        }
        return c
    }

    static func portal() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let r = sqrt(dx * dx + dy * dy), a = atan2(dy, dx)
            let swirl = sin(a * 2 + r * 0.55)
            let v = 0.55 + swirl * 0.4
            return RGBA(v, v, v, 0.8)
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
