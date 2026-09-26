import Foundation

/// Treasure maps and crabs.
enum SeaTextures {
    private static let S = TexturePainter.S

    static func item(_ name: String) -> Canvas? {
        switch name {
        case "treasure_map": return treasureMap()
        case "crab_claw": return claw(cooked: false)
        case "cooked_crab_claw": return claw(cooked: true)
        default: return nil
        }
    }

    /// An old, torn parchment with a dotted trail, an island and a big red X.
    private static func treasureMap() -> Canvas {
        let c = Canvas(S)
        let parch = RGBA(hex: 0xD8C08A), dark = RGBA(hex: 0x9A7A48)
        for y in 4..<28 {
            for x in 4..<28 {
                let torn = (x < 6 || x > 25 || y < 6 || y > 25) && TexturePainter.hash01(501, x, y) > 0.55
                if torn { continue }
                let n = TexturePainter.hash01(502, x / 3, y / 3)
                c.plot(x, y, parch.shade(0.85 + n * 0.2).mix(dark, (x + y) % 9 == 0 ? 0.3 : 0))
            }
        }
        c.disc(12, 18, 5, RGBA(hex: 0x8AA860).mix(parch, 0.35))          // an island
        c.disc(10, 20, 3, RGBA(hex: 0x8AA860).mix(parch, 0.25))
        for (x, y) in [(8, 25), (10, 23), (12, 21), (14, 18), (16, 16), (18, 14)] { c.plot(x, y, RGBA(hex: 0x5A3A1E)) }
        c.line(19, 8, 24, 13, width: 1.8) { _ in RGBA(hex: 0xC02020) }
        c.line(24, 8, 19, 13, width: 1.8) { _ in RGBA(hex: 0xC02020) }
        c.line(6, 6, 9, 6, width: 1) { _ in dark }                         // a compass flourish
        c.outline()
        return c
    }

    /// A crab's pincer: raw is deep red, cooked is bright orange.
    private static func claw(cooked: Bool) -> Canvas {
        let c = Canvas(S)
        let shell = cooked ? RGBA(hex: 0xF07A2A) : RGBA(hex: 0xB8302A), light = cooked ? RGBA(hex: 0xFFB06A) : RGBA(hex: 0xE05A4A)
        c.line(6, 26, 14, 18, width: 4) { _ in shell }                     // arm
        c.disc(17, 15, 6, shell)                                           // palm
        c.line(19, 12, 27, 5, width: 3.2) { _ in shell }                   // upper finger
        c.line(21, 17, 28, 13, width: 2.6) { _ in shell }                  // lower finger
        c.disc(16, 13, 2, light)
        c.plot(26, 6, RGBA(hex: 0x2A1A14)); c.plot(27, 13, RGBA(hex: 0x2A1A14))
        c.outline()
        return c
    }
}
