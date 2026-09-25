import Foundation

/// The enchanting table (obsidian base, red cloth, an open spellbook and amber studs) and the Quest Book.
enum MagicTextures {
    private static let S = TexturePainter.S
    private static let obsidian = Palette([0x0E0A16, 0x17112A, 0x221A3C, 0x2E2450, 0x3C3066])
    private static let cloth = Palette([0x5A0E14, 0x7A161C, 0x9A2026, 0xB82C30])
    private static let gold = RGBA(hex: 0xE8B040), goldDark = RGBA(hex: 0xA0701E)
    private static let amber = RGBA(hex: 0xF4A020), amberGlow = RGBA(hex: 0xFFD27A)

    static func add(to t: inout [String: Canvas]) {
        t["enchanting_table_top"] = top()
        t["enchanting_table_side"] = side()
        t["enchanting_table_bottom"] = obsidianFace(seed: 91)
    }

    static func item(_ name: String) -> Canvas? {
        name == "quest_book" ? questBook() : nil
    }

    private static func obsidianFace(seed: UInt64) -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let n = TexturePainter.hash01(seed, x / 2, y / 2) * 0.7 + TexturePainter.hash01(seed + 1, x, y) * 0.3
            var col = obsidian.step(n * 0.8)
            if TexturePainter.hash01(seed + 2, x, y) > 0.985 { col = RGBA(hex: 0x8A6ADA) }   // purple glints
            return col
        }
        return c
    }

    private static func top() -> Canvas {
        let c = Canvas(S)
        // Red cloth over the top with a gold hem, obsidian showing at the corners.
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 2 { return obsidian.step(0.4 + TexturePainter.hash01(93, x, y) * 0.4) }
            if edge == 2 { return gold }
            let weave = (x + y) % 4 == 0 ? 0.0 : 0.25
            return cloth.step(0.45 + weave + TexturePainter.hash01(94, x / 2, y / 2) * 0.2)
        }
        // Amber studs in the corners.
        for (x, y) in [(3, 3), (28, 3), (3, 28), (28, 28)] {
            c.rect(x - 1, y - 1, 2, 2, amber)
            c.plot(x - 1, y - 1, amberGlow)
        }
        // An open book in the middle: leather cover, two cream pages with lines of writing.
        c.rect(7, 9, 18, 14, RGBA(hex: 0x5A3418))
        c.rect(8, 10, 7, 12, RGBA(hex: 0xF2E6C4)); c.rect(17, 10, 7, 12, RGBA(hex: 0xECDDB4))
        c.rect(15, 9, 2, 14, RGBA(hex: 0x3E2210))
        for row in stride(from: 12, through: 20, by: 2) {
            let a = 9 + Int(TexturePainter.hash01(95, row, 0) * 2), b = 13 - Int(TexturePainter.hash01(96, row, 0) * 2)
            c.rect(a, row, b - a + 1, 1, RGBA(hex: 0x6A4A8A))
            let d = 18 + Int(TexturePainter.hash01(97, row, 1) * 2), e = 22 - Int(TexturePainter.hash01(98, row, 1) * 2)
            c.rect(d, row, e - d + 1, 1, RGBA(hex: 0x6A4A8A))
        }
        c.plot(11, 11, RGBA(hex: 0xB070F0)); c.plot(20, 19, RGBA(hex: 0xB070F0))   // a little glowing ink
        return c
    }

    private static func side() -> Canvas {
        let c = obsidianFace(seed: 92)
        // Cloth draped over the top quarter, with a gold hem and tassels.
        for y in 0..<9 {
            for x in 0..<S {
                c[x, y] = y == 8 ? goldDark : (y == 7 ? gold : cloth.step(0.5 + ((x / 2) % 2 == 0 ? 0.2 : 0) - Double(y) * 0.03))
            }
        }
        for x in stride(from: 3, to: S, by: 7) {
            c.rect(x, 9, 1, 3, gold)
            c.plot(x, 12, amber)
        }
        // A carved rune band across the middle of the obsidian.
        for x in 4..<(S - 4) where (x / 3) % 2 == 0 {
            c.plot(x, 20, RGBA(hex: 0x5A3E9A))
            if x % 6 == 0 { c.plot(x, 19, RGBA(hex: 0x8A6ADA)); c.plot(x, 21, RGBA(hex: 0x8A6ADA)) }
        }
        return c
    }

    private static func questBook() -> Canvas {
        let c = Canvas(S)
        let leather = Palette([0x3A2A12, 0x5A4220, 0x76582C, 0x8E6E38])
        // Closed book, tilted slightly: pages along the right edge, a clasp and an emerald on the cover.
        for y in 5..<28 {
            for x in 6..<25 {
                c.plot(x, y, leather.step(0.55 + TexturePainter.hash01(99, x / 2, y / 2) * 0.3 - Double(y - 5) / 80))
            }
        }
        c.rect(25, 6, 2, 21, RGBA(hex: 0xEDE2C2))                      // page edges
        for y in stride(from: 7, to: 27, by: 2) { c.plot(26, y, RGBA(hex: 0xC8B890)) }
        c.rect(6, 5, 2, 23, leather.colors[0])                          // spine
        c.rect(9, 7, 14, 1, gold); c.rect(9, 25, 14, 1, gold)           // gold rules
        // An emerald set in a gold mount.
        c.disc(16, 14, 3.6, gold)
        c.disc(16, 14, 2.4, RGBA(hex: 0x2EC46A))
        c.plot(15, 13, RGBA(hex: 0xB8F8D0))
        // A green ribbon bookmark hanging out of the bottom.
        c.rect(20, 27, 2, 3, RGBA(hex: 0x2E9A4E)); c.plot(20, 30, RGBA(hex: 0x2E9A4E))
        // "!" under the gem: a quest to do.
        c.rect(15, 19, 2, 3, gold); c.rect(15, 23, 2, 1, gold)
        c.outline()
        return c
    }
}
