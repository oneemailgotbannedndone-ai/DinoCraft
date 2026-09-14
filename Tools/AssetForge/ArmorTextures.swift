import Foundation
import DinoCraftCore

/// Armor icons (hide, iron, diamond) and the bed block.
enum ArmorTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let materials: [String: (base: UInt32, dark: UInt32, light: UInt32)] = [
        "hide": (0x8A5A3A, 0x5E3A22, 0xB8845A),
        "iron": (0xD0D5DC, 0x8A919C, 0xFFFFFF),
        "diamond": (0x5DF2E6, 0x1FA0A0, 0xD8FFFB),
    ]

    static func add(to t: inout [String: Canvas]) {
        t["bed_top"] = bedTop()
        t["bed_side"] = bedSide()
    }

    static func item(_ name: String) -> Canvas? {
        if name == "bow" || name == "arrow" { return archery(name) }
        let parts = name.split(separator: "_")
        guard parts.count == 2, let m = materials[String(parts[0])] else { return nil }
        let base = RGBA(hex: m.base), dark = RGBA(hex: m.dark), light = RGBA(hex: m.light)
        let c = Canvas(S)
        func fill(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) {
            for y in y0...y1 {
                for x in x0...x1 {
                    let shade = x <= x0 + 1 || y <= y0 + 1 ? light : (x >= x1 - 1 ? dark : base)
                    c.plot(x, y, shade)
                }
            }
        }
        switch parts[1] {
        case "helmet":
            fill(8, 8, 23, 14)
            fill(6, 14, 11, 22)
            fill(20, 14, 25, 22)
            for x in 12..<20 { c.plot(x, 15, dark) }
        case "chestplate":
            fill(5, 6, 11, 12)
            fill(20, 6, 26, 12)
            fill(9, 8, 22, 26)
            for y in 8..<14 { for x in 14..<18 { c.plot(x, y, .clear) } }
            for x in 11..<21 { c.plot(x, 19, dark) }
        case "leggings":
            fill(8, 6, 23, 11)
            fill(8, 11, 14, 27)
            fill(17, 11, 23, 27)
            for x in 8..<24 { c.plot(x, 8, dark) }
        case "boots":
            fill(6, 14, 12, 24)
            fill(3, 22, 12, 27)
            fill(19, 14, 25, 24)
            fill(19, 22, 28, 27)
        default:
            return nil
        }
        if parts[0] == "diamond" {
            for (x, y) in [(10, 10), (12, 20), (21, 12), (18, 24)] { c.plot(x, y, RGBA(hex: 0xFFFFFF)) }
        }
        c.outline()
        return c
    }

    static func archery(_ name: String) -> Canvas {
        let c = Canvas(S)
        let wood = RGBA(hex: 0x8A5A30), woodLight = RGBA(hex: 0xB47E48)
        if name == "bow" {
            // D-shaped limb bulging left with a leather grip, string straight down the right.
            c.line(22, 5, 22, 27, width: 0.9) { _ in RGBA(hex: 0xEDE6D6) }
            for i in 0...48 {
                let t = Double(i) / 48
                let a = -Double.pi / 2 + t * .pi
                let x = 22 - cos(a) * 13, y = 16 + sin(a) * 11
                let grip = abs(t - 0.5) < 0.1
                c.disc(x, y, grip ? 2.0 : 1.4, grip ? RGBA(hex: 0x5E3A22) : wood.mix(woodLight, abs(t - 0.5)))
            }
        } else {
            c.line(7, 25, 24, 8, width: 1.8) { _ in wood }
            for (dx, dy) in [(0.0, 0.0), (1.5, -1.5)] {
                c.line(8 + dx, 28 + dy, 5 + dx, 25 + dy, width: 1.6) { _ in RGBA(hex: 0xEFEDE6) }
                c.line(4 + dx, 24 + dy, 8 + dx, 28 + dy, width: 1.2) { _ in RGBA(hex: 0xD8D2C4) }
            }
            c.disc(25, 7, 2.6, RGBA(hex: 0x6E7078))
            c.plot(26, 6, RGBA(hex: 0xB8BCC6))
        }
        c.outline()
        return c
    }

    static func bedTop() -> Canvas {
        let c = Canvas(S)
        let blanket = Palette([0x8E1E22, 0xA82A2A, 0xC03A34, 0xD44A40])
        c.fill { x, y in
            if x < 2 || x > 29 { return RGBA(hex: 0x6A4630) }
            if y < 11 {
                return RGBA(hex: 0xF2EEE6).mix(RGBA(hex: 0xD8D2C8), T.hash01(501, x, y) * 0.5)
            }
            var col = blanket.step(0.3 + T.hash01(502, x / 2, y / 2) * 0.5)
            if y == 11 { col = col.lighten(0.25) }
            if (x + y) % 9 == 0 { col = col.lighten(0.12) }
            return col
        }
        return c
    }

    /// The bed is 9/16 tall, so only the lower part of this texture shows on its sides.
    static func bedSide() -> Canvas {
        let c = T.paintPlanks(503)
        let blanket = Palette([0x8E1E22, 0xA82A2A, 0xC03A34, 0xD44A40])
        for y in 0..<S {
            for x in 0..<S {
                if y < 14 { c[x, y] = blanket.step(0.5 + T.hash01(505, x / 2, y / 2) * 0.5) }
                else if y < 21 { c[x, y] = blanket.step(0.35 + T.hash01(504, x, y) * 0.5).shade(y == 20 ? 0.8 : 1) }
                else if y > 29 { c[x, y] = RGBA(hex: 0x4A3020) }
            }
        }
        return c
    }
}
