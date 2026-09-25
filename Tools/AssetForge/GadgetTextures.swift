import Foundation

/// Amber circuits (dust, lever, button, pressure plate, lamp, piston) and decorations (paintings, item frames,
/// the armour stand's icon).
enum GadgetTextures {
    private static let S = TexturePainter.S
    static let paintings = ["rex", "sunset", "fern", "volcano", "ptero", "village"]
    private static let stone = Palette([0x5E6068, 0x74767E, 0x8A8C94, 0xA2A4AC])
    private static let wood = Palette([0x6A4424, 0x8A5C32, 0xA8743E, 0xC48D54])

    static func add(to t: inout [String: Canvas]) {
        t["amber_dust_off"] = dust(lit: false)
        t["amber_dust_on"] = dust(lit: true)
        t["lever"] = lever()
        t["amber_button"] = smooth(401)
        t["pressure_plate"] = plate()
        t["amber_lamp_off"] = lamp(lit: false)
        t["amber_lamp_on"] = lamp(lit: true)
        t["piston_front"] = pistonFront(extended: false)
        t["piston_front_extended"] = pistonFront(extended: true)
        t["piston_side"] = pistonSide()
        t["piston_back"] = pistonBack()
        t["piston_head"] = pistonHead()
        t["item_frame"] = frame()
        for p in paintings { t["painting_\(p)"] = painting(p) }
    }

    static func item(_ name: String) -> Canvas? {
        switch name {
        case "amber_dust": return dustItem()
        case "lever_item": return leverItem()
        case "painting": return paintingItem()
        case "item_frame_item": return frameItem()
        case "armor_stand": return standItem()
        default: return nil
        }
    }

    // MARK: Circuits

    /// Amber dust lying on the ground: specks around a cross of trails (transparent elsewhere).
    private static func dust(lit: Bool) -> Canvas {
        let c = Canvas(S)
        let dark = lit ? RGBA(hex: 0xFF9A1A) : RGBA(hex: 0x7A4A12), light = lit ? RGBA(hex: 0xFFE27A) : RGBA(hex: 0xA86A20)
        for y in 0..<S {
            for x in 0..<S {
                let onCross = abs(x - 15) < 3 || abs(y - 15) < 3
                let speck = TexturePainter.hash01(411, x, y)
                guard onCross ? speck > 0.15 : speck > 0.93 else { continue }
                c.plot(x, y, speck > 0.7 ? light : dark)
            }
        }
        c.disc(15.5, 15.5, 3.5, lit ? light : dark)
        return c
    }

    private static func smooth(_ seed: UInt64) -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let edge = x == 0 || y == 0 || x == S - 1 || y == S - 1
            return edge ? stone.colors[0] : stone.step(0.45 + TexturePainter.hash01(seed, x / 4, y / 4) * 0.35)
        }
        return c
    }

    private static func lever() -> Canvas {
        let c = smooth(402)
        // The cobble base with a wooden handle stripe in the middle (the handle box uses the centre).
        for y in 0..<S { for x in 12..<20 { c[x, y] = wood.step(0.4 + Double((y / 3) % 2) * 0.3) } }
        return c
    }

    private static func plate() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 2 { return wood.colors[0] }
            return wood.step(0.4 + TexturePainter.hash01(403, x / 8, y) * 0.4)
        }
        return c
    }

    private static func lamp(lit: Bool) -> Canvas {
        let c = Canvas(S)
        let frame = Palette([0x3A2A1A, 0x5A4228, 0x7A5A36])
        let glass = lit ? Palette([0xE8901A, 0xFFB43A, 0xFFD77A, 0xFFF2C0]) : Palette([0x4A3218, 0x5E4020, 0x6E4E2A, 0x7E5E36])
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 3 { return frame.step(0.3 + TexturePainter.hash01(404, x, y) * 0.5) }
            // Leaded panes: a cross of frame through the middle.
            if abs(x - 15) < 1 || abs(y - 15) < 1 { return frame.colors[1] }
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let glow = 1 - (dx * dx + dy * dy).squareRoot() / 18
            return glass.ramp(glow * 0.9 + TexturePainter.hash01(405, x / 2, y / 2) * 0.15)
        }
        return c
    }

    private static func pistonFront(extended: Bool) -> Canvas {
        let c = Canvas(S)
        if extended {
            // The body with the head gone: dark stone and the end of the rod.
            c.fill { x, y in
                let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
                return edge < 3 ? stone.colors[1] : stone.colors[0].shade(0.7)
            }
            c.rect(12, 12, 8, 8, wood.colors[2])
        } else {
            c.fill { x, y in
                let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
                if edge < 3 { return RGBA(hex: 0xB0B4BC) }   // iron rim
                return wood.step(0.45 + TexturePainter.hash01(406, x / 8, y) * 0.35)
            }
            c.rect(3, 3, S - 6, 1, RGBA(hex: 0xE8ECF0))
        }
        return c
    }

    private static func pistonSide() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            if y < 8 { return wood.step(0.45 + TexturePainter.hash01(407, x / 8, y) * 0.35) }   // the pusher plank on top
            if y == 8 { return RGBA(hex: 0xB0B4BC) }
            return stone.step(0.3 + TexturePainter.hash01(408, x / 3, y / 3) * 0.45)
        }
        // An amber-lit slot showing the piston is wired in.
        c.rect(14, 18, 4, 8, RGBA(hex: 0x7A4A12))
        c.rect(15, 20, 2, 4, RGBA(hex: 0xE8901A))
        return c
    }

    private static func pistonBack() -> Canvas {
        let c = smooth(409)
        c.rect(12, 12, 8, 8, stone.colors[0])
        return c
    }

    private static func pistonHead() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in wood.step(0.45 + TexturePainter.hash01(410, x / 8, y) * 0.35) }
        return c
    }

    // MARK: Decorations

    private static func frame() -> Canvas {
        let c = Canvas(S)
        let leather = RGBA(hex: 0x8A6A44)
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 3 { return wood.step(0.5 + TexturePainter.hash01(412, x, y) * 0.3) }
            return leather.shade(0.85 + TexturePainter.hash01(413, x / 3, y / 3) * 0.2)
        }
        return c
    }

    /// Little landscape paintings in a gilt frame.
    private static func painting(_ motif: String) -> Canvas {
        let c = Canvas(S)
        let gilt = Palette([0x8A6420, 0xB88A30, 0xE0B850])
        var sky = RGBA(hex: 0x8AC4F0), ground = RGBA(hex: 0x5A9A3A)
        switch motif {
        case "sunset": sky = RGBA(hex: 0xF0905A); ground = RGBA(hex: 0x4A3A5A)
        case "volcano": sky = RGBA(hex: 0x6A4A5A); ground = RGBA(hex: 0x2E2A2E)
        case "village": sky = RGBA(hex: 0xA8D8F8); ground = RGBA(hex: 0x6AAA46)
        case "ptero": sky = RGBA(hex: 0xC8E0F0); ground = RGBA(hex: 0x4A8ABA)
        default: break
        }
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 3 { return gilt.step(0.3 + Double((x + y) % 5) * 0.12) }
            return y < 20 ? sky.mix(RGBA(hex: 0xFFFFFF), Double(20 - y) / 60) : ground.shade(0.9 + TexturePainter.hash01(414, x / 3, y) * 0.15)
        }
        switch motif {
        case "rex":
            // A T-Rex silhouette.
            c.rect(10, 12, 10, 6, RGBA(hex: 0x3A4A2A)); c.rect(18, 9, 7, 5, RGBA(hex: 0x3A4A2A))
            c.rect(11, 18, 2, 4, RGBA(hex: 0x3A4A2A)); c.rect(16, 18, 2, 4, RGBA(hex: 0x3A4A2A))
            c.line(10, 14, 4, 18, width: 2.2) { _ in RGBA(hex: 0x3A4A2A) }
            c.plot(22, 10, RGBA(hex: 0xF0E060))
        case "sunset":
            c.disc(16, 19, 5, RGBA(hex: 0xFFD060))
            for x in 3..<29 { c.plot(x, 20, RGBA(hex: 0x3A2A4A)) }
        case "fern":
            c.line(16, 27, 16, 8, width: 1.4) { _ in RGBA(hex: 0x2E6A2A) }
            for i in 0..<6 {
                let y = 10 + Double(i) * 3
                c.line(16, y, 10 + Double(i) * 0.5, y - 2, width: 1.3) { _ in RGBA(hex: 0x3E8A34) }
                c.line(16, y, 22 - Double(i) * 0.5, y - 2, width: 1.3) { _ in RGBA(hex: 0x3E8A34) }
            }
        case "volcano":
            for y in 10..<21 { let w = (y - 10); c.rect(16 - w, y, 2 * w + 1, 1, RGBA(hex: 0x4A3A36)) }
            c.rect(14, 10, 5, 1, RGBA(hex: 0xFF7A20))
            c.disc(15, 6, 2.5, RGBA(hex: 0x6A6A6A)); c.disc(18, 4.5, 2, RGBA(hex: 0x7A7A7A))
        case "ptero":
            c.line(9, 12, 16, 14, width: 1.6) { _ in RGBA(hex: 0x4A3A30) }
            c.line(16, 14, 23, 11, width: 1.6) { _ in RGBA(hex: 0x4A3A30) }
            c.plot(16, 13, RGBA(hex: 0x4A3A30)); c.plot(17, 13, RGBA(hex: 0xD8A040))
        default: // village
            c.rect(8, 14, 7, 6, RGBA(hex: 0xC8A070)); c.rect(7, 12, 9, 2, RGBA(hex: 0x8A3A2A))
            c.rect(18, 15, 6, 5, RGBA(hex: 0xD8B880)); c.rect(17, 13, 8, 2, RGBA(hex: 0x6A4A2A))
            c.plot(11, 17, RGBA(hex: 0x3A2A1A)); c.plot(21, 17, RGBA(hex: 0x3A2A1A))
        }
        return c
    }

    // MARK: Item icons

    private static func dustItem() -> Canvas {
        let c = Canvas(S)
        for (x, y, r) in [(14.0, 18.0, 5.5), (19.0, 14.0, 4.0), (10.0, 13.0, 3.0), (20.0, 21.0, 3.0)] {
            c.disc(x, y, r, RGBA(hex: 0xE8901A))
            c.disc(x - 1, y - 1, r * 0.45, RGBA(hex: 0xFFD27A))
        }
        c.outline()
        return c
    }

    private static func leverItem() -> Canvas {
        let c = Canvas(S)
        c.rect(8, 22, 16, 6, stone.colors[2]); c.rect(8, 26, 16, 2, stone.colors[0])
        c.line(16, 23, 22, 7, width: 2.4) { t in wood.colors[2].mix(wood.colors[0], t * 0.5) }
        c.disc(22, 7, 2.2, RGBA(hex: 0xE8901A))
        c.outline()
        return c
    }

    private static func paintingItem() -> Canvas {
        let c = painting("rex")
        return c
    }

    private static func frameItem() -> Canvas {
        let c = frame()
        return c
    }

    private static func standItem() -> Canvas {
        let c = Canvas(S)
        let w = wood.colors[2], d = wood.colors[0]
        c.rect(8, 27, 16, 3, d)                      // base
        c.rect(15, 6, 2, 21, w)                      // pole
        c.rect(9, 10, 14, 2, w)                      // shoulders
        c.rect(12, 18, 8, 2, w)                      // hips
        c.disc(16, 5, 2.6, w)                        // head
        c.outline()
        return c
    }
}
