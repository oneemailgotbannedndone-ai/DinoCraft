import Foundation

/// Fossil dig sites and the museum (fossil deposits, fossils, display cases), meteorites, paper and maps.
enum DigTextures {
    private static let S = TexturePainter.S
    static let fossils = ["skull", "claw", "rib", "tooth", "fern"]
    private static let bone = RGBA(hex: 0xE8DCC0), boneShade = RGBA(hex: 0xB8A684), boneDark = RGBA(hex: 0x7E6C50)

    static func add(to t: inout [String: Canvas]) {
        t["fossil_deposit"] = deposit()
        t["display_case_top"] = caseTop()
        t["display_case_side"] = caseSide(nil)
        for f in fossils { t["display_case_side_\(f)"] = caseSide(f) }
        t["meteorite_ore"] = meteorite()
    }

    static func item(_ name: String) -> Canvas? {
        if name.hasPrefix("fossil_"), let f = fossils.first(where: { "fossil_\($0)" == name }) {
            let c = Canvas(S)
            drawFossil(f, on: c, ox: 0, oy: 0, scale: 1)
            c.outline()
            return c
        }
        switch name {
        case "meteorite_shard": return shard()
        case "paper": return paper()
        case "map": return map()
        default: return nil
        }
    }

    // MARK: Blocks

    /// Sandy stone with bones peeking out: dig it for a fossil.
    private static func deposit() -> Canvas {
        let c = Canvas(S)
        let rock = Palette([0x8A7A5E, 0x9E8E70, 0xB2A282, 0xC4B494])
        c.fill { x, y in
            let n = TexturePainter.hash01(301, x / 3, y / 3) * 0.6 + TexturePainter.hash01(302, x, y) * 0.4
            return rock.step(n)
        }
        // Strata lines
        for y in [9, 21] { for x in 0..<S where TexturePainter.hash01(303, x, y) > 0.25 { c[x, y] = rock.colors[0] } }
        // A vertebra, a rib and a claw half buried
        c.line(4, 14, 13, 12, width: 2.2) { _ in bone }
        c.disc(4, 14, 1.8, bone); c.disc(13, 12, 1.8, bone)
        c.line(18, 26, 27, 17, width: 1.8) { t in bone.mix(boneShade, t) }
        for k in 0..<3 { c.disc(20 + Double(k) * 3, 5 + Double(k % 2), 1.6, k == 1 ? boneShade : bone) }
        c.plot(8, 13, boneDark); c.plot(22, 22, boneDark)
        return c
    }

    private static func frameWood() -> Palette { Palette([0x4A2E16, 0x6A4424, 0x8A5C32, 0xA8743E]) }

    private static func caseTop() -> Canvas {
        let c = Canvas(S)
        let wood = frameWood()
        c.fill { x, y in
            let edge = min(min(x, y), min(S - 1 - x, S - 1 - y))
            if edge < 3 { return wood.step(0.35 + TexturePainter.hash01(311, x, y / 4) * 0.4) }
            // Glass lid: pale blue with a diagonal sheen
            let sheen = (x + y) % 11 < 2 ? 0.25 : 0.0
            return RGBA(hex: 0x9CC4D8).lighten(sheen)
        }
        c.rect(3, 3, S - 6, 1, RGBA(hex: 0xD8C070))   // brass trim
        return c
    }

    /// A glass-fronted case on a wooden plinth, empty or with a fossil inside.
    private static func caseSide(_ fossil: String?) -> Canvas {
        let c = Canvas(S)
        let wood = frameWood()
        c.fill { x, y in
            if y >= 24 { return wood.step(0.3 + TexturePainter.hash01(312, x / 3, y) * 0.5) }           // plinth
            if x < 2 || x > S - 3 || y < 2 { return wood.step(0.55 + TexturePainter.hash01(313, x, y) * 0.3) } // frame
            let inside = RGBA(hex: 0x2E3A40).mix(RGBA(hex: 0x4E6A78), Double(y) / 24)                    // dark velvet back
            return inside
        }
        c.rect(2, 22, S - 4, 2, RGBA(hex: 0x7A1E26))   // red velvet shelf
        c.rect(0, 24, S, 1, RGBA(hex: 0xD8C070))       // brass trim
        if let fossil { drawFossil(fossil, on: c, ox: 3, oy: 1, scale: 0.82) }
        // Glass: sheen streaks over everything inside
        for i in 0..<22 {
            let x = 5 + i, y = 20 - i
            guard x < S - 2, y > 1 else { continue }
            c[x, y] = c[x, y].mix(RGBA(hex: 0xE8F6FF), 0.35)
            if x + 1 < S - 2 { c[x + 1, y] = c[x + 1, y].mix(RGBA(hex: 0xE8F6FF), 0.2) }
        }
        return c
    }

    /// Meteorite ore: charred rock with glowing violet metal flecks.
    private static func meteorite() -> Canvas {
        let c = Canvas(S)
        let rock = Palette([0x16121C, 0x221C2A, 0x2E2638, 0x3A3046])
        c.fill { x, y in rock.step(TexturePainter.hash01(321, x / 2, y / 2) * 0.7 + TexturePainter.hash01(322, x, y) * 0.3) }
        let metal = [RGBA(hex: 0x7A4ED8), RGBA(hex: 0xB89AF8), RGBA(hex: 0xFFE8A0)]
        for (x, y) in [(5, 6), (21, 4), (13, 14), (26, 19), (7, 24), (18, 27)] {
            c.disc(Double(x), Double(y), 2.2, metal[0])
            c.plot(x, y, metal[1]); c.plot(x - 1, y - 1, metal[2])
        }
        // Cracks glowing faintly orange from the heat of the fall
        c.line(2, 16, 10, 12, width: 1) { _ in RGBA(hex: 0xC85A1A) }
        c.line(22, 10, 29, 13, width: 1) { _ in RGBA(hex: 0xC85A1A) }
        return c
    }

    // MARK: Items

    /// A fossil drawn in bone colours, in the item's 32×32 frame (scaled and offset for the display case).
    private static func drawFossil(_ kind: String, on c: Canvas, ox: Double, oy: Double, scale k: Double) {
        func P(_ x: Double, _ y: Double) -> (Double, Double) { (ox + x * k, oy + y * k) }
        func disc(_ x: Double, _ y: Double, _ r: Double, _ col: RGBA) { let p = P(x, y); c.disc(p.0, p.1, r * k, col) }
        func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ w: Double, _ col: RGBA) {
            let a = P(x0, y0), b = P(x1, y1)
            c.line(a.0, a.1, b.0, b.1, width: w * k) { _ in col }
        }
        switch kind {
        case "skull":
            // A raptor skull in profile: long snout, big eye socket, a row of teeth.
            disc(12, 14, 7, bone); disc(19, 16, 5, bone); line(18, 17, 28, 19, 6, bone)
            line(14, 22, 27, 23, 2.5, boneShade)
            disc(11, 12, 2.6, boneDark); disc(20, 14, 1.4, boneDark)
            for i in 0..<5 { line(16 + Double(i) * 2.5, 21, 16.6 + Double(i) * 2.5, 24, 1, RGBA(hex: 0xF6F0E0)) }
        case "claw":
            // A big curved killing claw.
            for i in 0..<14 {
                let t = Double(i) / 13
                let a = t * 2.3
                disc(10 + sin(a) * 12, 26 - (1 - cos(a)) * 9 - t * 8, 4.2 - t * 3.2, i % 3 == 0 ? boneShade : bone)
            }
            disc(9, 26, 3.6, boneShade)
        case "rib":
            // Three curved ribs joined to a piece of spine.
            line(6, 6, 6, 27, 3.5, boneShade)
            for r in 0..<3 {
                let y = 8 + Double(r) * 7
                for i in 0..<10 {
                    let t = Double(i) / 9
                    disc(7 + t * 18, y + sin(t * 2.4) * 5, 1.6, bone)
                }
            }
        case "tooth":
            // A big serrated T-Rex tooth.
            for y in 4..<28 {
                let t = Double(y - 4) / 24
                let half = 1 + t * 6
                line(16 - half, Double(y), 16 + half * 0.8, Double(y), 1.6, y > 22 ? boneShade : bone)
            }
            for y in stride(from: 8, to: 24, by: 3) { let p = P(16 + (1 + Double(y - 4) / 24 * 6) * 0.8, Double(y)); c.plot(Int(p.0) + 1, Int(p.1), boneDark) }
            line(12, 27, 21, 27, 2, RGBA(hex: 0xA08858))
        default:
            // A fern pressed into a slab of stone.
            let slab = RGBA(hex: 0x9A8E7A)
            for y in 5..<28 { line(6, Double(y), 26, Double(y), 1.6, slab.shade(0.9 + TexturePainter.hash01(331, 0, y) * 0.15)) }
            let leaf = RGBA(hex: 0x4E4232)
            line(16, 26, 16, 7, 1.6, leaf)
            for i in 0..<7 {
                let y = 9 + Double(i) * 2.6, len = 7 - Double(i) * 0.7
                line(16, y, 16 - len, y - 2, 1.4, leaf); line(16, y, 16 + len, y - 2, 1.4, leaf)
            }
        }
    }

    private static func shard() -> Canvas {
        let c = Canvas(S)
        let dark = RGBA(hex: 0x3A2458), body = RGBA(hex: 0x7A4ED8), light = RGBA(hex: 0xB89AF8), spark = RGBA(hex: 0xFFE8A0)
        for y in 4..<29 {
            for x in 6..<27 {
                let dx = Double(x) - 16, dy = Double(y) - 16
                guard abs(dx) * 1.3 + abs(dy) * 0.9 < 12 - (dx * dy > 0 ? 2 : 0) else { continue }
                c.plot(x, y, dx < -2 ? light : (dy > 4 ? dark : body))
            }
        }
        c.plot(12, 10, spark); c.plot(13, 9, spark); c.plot(19, 20, spark.withAlpha(0.8))
        c.outline()
        return c
    }

    private static func paper() -> Canvas {
        let c = Canvas(S)
        for y in 5..<28 { for x in 7..<25 { c.plot(x + (y > 20 ? 1 : 0), y, RGBA(hex: 0xF2ECDA).shade(0.94 + TexturePainter.hash01(341, x, y) * 0.06)) } }
        for y in stride(from: 9, to: 25, by: 3) { c.rect(10, y, 12, 1, RGBA(hex: 0xC8C0AA)) }
        c.outline()
        return c
    }

    private static func map() -> Canvas {
        let c = Canvas(S)
        let land = RGBA(hex: 0x8AB060), sea = RGBA(hex: 0x6A9ACA), parch = RGBA(hex: 0xE6D8B0)
        for y in 4..<28 {
            for x in 4..<28 {
                let edge = x < 6 || x > 25 || y < 6 || y > 25
                if edge { c.plot(x, y, parch.shade(0.85)); continue }
                let n = TexturePainter.hash01(351, x / 4, y / 4) * 0.6 + TexturePainter.hash01(352, x / 2, y / 2) * 0.4
                c.plot(x, y, n > 0.5 ? land.mix(parch, 0.3) : sea.mix(parch, 0.35))
            }
        }
        // A dotted trail to a red X
        for (x, y) in [(8, 22), (10, 20), (12, 19), (14, 17), (16, 15), (18, 13)] { c.plot(x, y, RGBA(hex: 0x5A3A1E)) }
        c.line(19, 9, 23, 13, width: 1.4) { _ in RGBA(hex: 0xD02828) }
        c.line(23, 9, 19, 13, width: 1.4) { _ in RGBA(hex: 0xD02828) }
        c.outline()
        return c
    }
}
