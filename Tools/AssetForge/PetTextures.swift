import Foundation
import DinoCraftCore

/// Items for tamed creatures, boats and fishing.
enum PetTextures {
    static let S = TexturePainter.S

    static func item(_ name: String) -> Canvas? {
        switch name {
        case "boat": return boat()
        case "fishing_rod": return fishingRod()
        case "string": return string()
        case "saddle": return saddle()
        case "spear": return spear()
        case "crossbow": return crossbow()
        case "shield": return shield()
        default: return nil
        }
    }

    private static func saddle() -> Canvas {
        // A leather saddle seen from the side: seat, raised front and back, flap, girth strap and a stirrup.
        let c = Canvas(S)
        let leather = Palette([0x4A2A16, 0x6A3E22, 0x86522E, 0xA0683C, 0xBA804E])
        for y in 9..<20 {
            for x in 4..<28 {
                let dx = (Double(x) - 16) / 12, dy = (Double(y) - 16) / 6
                let seat = dx * dx + dy * dy < 1 && !(y < 13 && abs(Double(x) - 16) < 7)
                if seat { c.plot(x, y, leather.step(0.35 + (y < 14 ? 0.35 : 0) - Double(x - 4) / 60)) }
            }
        }
        c.rect(5, 8, 4, 4, leather.colors[3]); c.rect(23, 7, 4, 5, leather.colors[3])      // pommel and cantle
        c.rect(10, 17, 12, 6, leather.colors[1])                                          // flap
        c.line(15, 22, 15, 27, width: 1.5) { _ in leather.colors[0] }                       // stirrup leather
        c.rect(12, 27, 7, 2, RGBA(hex: 0x9A9AA4)); c.plot(12, 26, RGBA(hex: 0x9A9AA4)); c.plot(18, 26, RGBA(hex: 0x9A9AA4))
        c.plot(8, 10, RGBA(hex: 0xD8B040)); c.plot(24, 9, RGBA(hex: 0xD8B040))              // brass studs
        c.outline()
        return c
    }

    /// A rowing boat from the side: planked hull with a raised bow, gunwale, and an oar resting across it.
    private static func boat() -> Canvas {
        let c = Canvas(S)
        let wood = Palette([0x4E3018, 0x6E4822, 0x8E6230, 0xAA7A40, 0xC49256])
        for y in 14..<25 {
            let t = Double(y - 14) / 10
            let left = 3 + Int(t * t * 5), right = 28 - Int(t * 3)
            for x in left...right {
                let seam = (y - 14) % 4 == 3
                c.plot(x, y, seam ? wood.colors[1] : wood.step(0.75 - t * 0.45 + TexturePainter.hash01(41, x / 3, y) * 0.12))
            }
        }
        // Bow rising at the right, gunwale along the top.
        for (i, x) in (26...29).enumerated() { c.rect(x, 12 - i, 1, 3 + i, wood.colors[2]) }
        c.rect(3, 13, 25, 2, wood.colors[0].lighten(0.1))
        // Oar across the boat, blade down on the left.
        c.line(8, 6, 22, 20, width: 1.4) { _ in RGBA(hex: 0xC8A26A) }
        c.line(4, 2, 9, 8, width: 3.2) { _ in RGBA(hex: 0xB08850) }
        c.outline()
        return c
    }

    /// A bamboo-coloured rod bending to a fine tip, a reel by the handle, and line down to a red and white float.
    private static func fishingRod() -> Canvas {
        let c = Canvas(S)
        // Line from the tip down to the float.
        for y in 4...20 { c.plot(27, y, RGBA(hex: 0xE4E4E4)) }
        c.line(4, 28, 16, 15, width: 2.4) { _ in RGBA(hex: 0x6A4424) }                 // cork handle
        c.line(16, 15, 23, 7, width: 1.8) { t in RGBA(hex: 0x9A6A38).mix(RGBA(hex: 0xB88A50), t) }
        c.line(23, 7, 27, 3, width: 1.1) { _ in RGBA(hex: 0xB88A50) }
        c.disc(10.5, 22.5, 2.2, RGBA(hex: 0x8A8A94))                                     // reel
        c.plot(10, 22, RGBA(hex: 0xC8C8D0))
        c.rect(26, 21, 3, 2, RGBA(hex: 0xE53935))                                      // float
        c.rect(26, 23, 3, 2, RGBA(hex: 0xF4F4F4))
        c.outline()
        return c
    }

    /// A loose coil of string.
    private static func string() -> Canvas {
        let c = Canvas(S)
        let white = RGBA(hex: 0xF2EEE4), shadow = RGBA(hex: 0xB8B2A6)
        for k in 0..<3 {
            let r = 8.0 - Double(k) * 1.6, cx = 15.0 + Double(k) * 1.2, cy = 15.0 - Double(k) * 0.8
            var a = 0.0
            while a < 2 * .pi {
                c.disc(cx + cos(a) * r, cy + sin(a) * r * 0.8, 0.8, sin(a) > 0.2 ? shadow : white)
                a += 0.05
            }
        }
        c.line(21, 20, 27, 27, width: 1) { _ in white }
        c.outline()
        return c
    }

    /// A long ash shaft bound with leather under a knapped flint point.
    private static func spear() -> Canvas {
        let c = Canvas(S)
        c.line(4, 28, 21, 11, width: 1.8) { t in RGBA(hex: 0x8A5E32).mix(RGBA(hex: 0xB0824A), t) }
        c.line(12, 20, 15, 17, width: 2.4) { _ in RGBA(hex: 0x5A3A1E) }                 // leather grip
        c.line(19, 13, 21, 11, width: 2.6) { _ in RGBA(hex: 0x6A4424) }                 // binding
        for (x, y, col) in [(22, 10, 0x4A4A55), (23, 9, 0x5E5E6A), (24, 8, 0x6E6E7C), (25, 7, 0x7E7E8C), (26, 6, 0x9A9AA8),
                            (27, 5, 0xB8B8C4), (23, 11, 0x3C3C46), (24, 10, 0x55555F), (21, 8, 0x55555F), (22, 7, 0x6E6E7C)] {
            c.plot(x, y, RGBA(hex: UInt32(col)))
        }
        c.plot(22, 9, RGBA(hex: 0x6E6E7C)); c.plot(24, 9, RGBA(hex: 0x8A8A98)); c.plot(25, 8, RGBA(hex: 0x9A9AA8)); c.plot(26, 7, RGBA(hex: 0xC8C8D4))
        c.outline()
        return c
    }

    /// A wooden stock with an iron-tipped bow across it and a bolt ready.
    private static func crossbow() -> Canvas {
        let c = Canvas(S)
        c.line(7, 25, 22, 10, width: 3) { t in RGBA(hex: 0x7A5028).mix(RGBA(hex: 0x9A6A38), t) }     // stock
        // Bow limbs, curved across the front of the stock
        c.line(12, 6, 18, 9, width: 1.6) { _ in RGBA(hex: 0x8A8A96) }
        c.line(18, 9, 22, 13, width: 1.8) { _ in RGBA(hex: 0x8A8A96) }
        c.line(22, 13, 25, 19, width: 1.6) { _ in RGBA(hex: 0x8A8A96) }
        c.line(12, 6, 25, 19, width: 0.9) { _ in RGBA(hex: 0xE8E4D8) }                   // string
        c.line(15, 17, 24, 8, width: 1) { _ in RGBA(hex: 0xC8A060) }                     // bolt
        c.plot(25, 7, RGBA(hex: 0xB8B8C4)); c.plot(24, 7, RGBA(hex: 0x9A9AA8))
        c.rect(8, 22, 3, 3, RGBA(hex: 0x5A3A1E))                                          // butt
        c.outline()
        return c
    }

    /// A round wooden shield with an iron rim and boss, painted with a dinosaur footprint.
    private static func shield() -> Canvas {
        let c = Canvas(S)
        let wood = Palette([0x5E3C1C, 0x7A5028, 0x96683A, 0xB08050])
        for y in 3..<29 {
            for x in 5..<27 {
                let dx = (Double(x) - 15.5) / 11, dy = (Double(y) - 15.5) / 13
                let d = dx * dx + dy * dy
                guard d < 1 else { continue }
                if d > 0.8 { c.plot(x, y, RGBA(hex: 0x8A8A96).shade(d > 0.9 ? 0.8 : 1)) }
                else { c.plot(x, y, wood.step(0.4 + Double((x / 3) % 2) * 0.15 + (1 - d) * 0.3)) }
            }
        }
        // Three-toed footprint in red paint
        let red = RGBA(hex: 0xA83228)
        c.line(15.5, 20, 15.5, 11, width: 1.8) { _ in red }
        c.line(15.5, 20, 11, 13, width: 1.6) { _ in red }
        c.line(15.5, 20, 20, 13, width: 1.6) { _ in red }
        c.disc(15.5, 20.5, 2.2, red)
        c.disc(15.5, 16, 1.4, RGBA(hex: 0xB8B8C4))                                        // boss
        c.outline()
        return c
    }
}
