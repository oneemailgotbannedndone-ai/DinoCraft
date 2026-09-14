import Foundation
import DinoCraftCore

/// Textures for wool, palm wood, lanterns, barrels, hay and other building blocks.
enum BuildTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let palmBark = Palette([0x6A5238, 0x7E6444, 0x927652, 0xA68862, 0xB89A72])
    static let palmWood = Palette([0xA88A5A, 0xBC9E6A, 0xCCAE78, 0xDABC88, 0xE6CA98])
    static let palmLeaf = Palette([0x2E7A2A, 0x3E9230, 0x52A838, 0x6ABC42, 0x88CE50])
    static let straw = Palette([0xB08A2A, 0xC49E34, 0xD6B042, 0xE4C254, 0xF0D46A])

    static func add(to t: inout [String: Canvas]) {
        for (name, hex) in DecorTextures.colors {
            t["wool_\(name)"] = wool(hex, seed: 300 + UInt64(hex % 101))
        }
        t["palm_log_side"] = palmLogSide()
        t["palm_log_top"] = T.paintLogTop(301, bark: palmBark, core: [0xE6CA98, 0xCCAE78, 0xB89A72])
        t["palm_planks"] = T.paintPlanks(302, palette: palmWood)
        t["palm_fronds"] = T.paintLeaves(303, palette: palmLeaf, coverage: 0.62)
        t["lantern"] = lantern()
        t["barrel_side"] = barrelSide()
        t["barrel_top"] = barrelTop()
        t["coal_block"] = coalBlock()
        t["packed_ice"] = packedIce()
        t["hay_bale_side"] = haySide()
        t["hay_bale_top"] = hayTop()
        t["berry_bush"] = berryBush()
    }

    static func wool(_ hex: UInt32, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = T.noise(seed)
        let p = DecorTextures.ramp(hex)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let fiber = n.value(u * 3 + v * 3, v * 3 - u * 3, period: 12)
            let tuft = n.fbm(u, v, period: 4, octaves: 3)
            return p.ramp(0.3 + tuft * 0.45 + fiber * 0.2)
        }
        return c
    }

    static func palmLogSide() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(304)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            var col = palmBark.step(0.3 + n.value(u * 4, v, period: 8) * 0.5)
            let ring = y % 6
            if ring == 0 { col = palmBark.colors[0] } else if ring == 1 { col = col.lighten(0.12) }
            if (x + y / 6 * 5) % 11 == 0 && ring > 1 { col = col.shade(0.85) }
            return col
        }
        return c
    }

    static func lantern() -> Canvas {
        let c = Canvas(S)
        let iron = RGBA(hex: 0x3A3A42), ironLight = RGBA(hex: 0x6A6A74)
        c.fill { x, y in
            // Side view (lower half of the texture) and cap (centre) share the sheet.
            let frame = x == 10 || x == 21 || y == 14 || y == 31 || (y > 14 && (x == 11 || x == 20) && y % 4 == 0)
            if x >= 10 && x <= 21 && y >= 14 {
                if frame { return y == 14 ? ironLight : iron }
                let d = hypot(Double(x) - 15.5, Double(y) - 23)
                return RGBA(hex: 0xFFF0A0).mix(RGBA(hex: 0xF08A1A), min(1, d / 8))
            }
            if x >= 10 && x <= 21 && y >= 10 { return iron.mix(ironLight, (x + y) % 3 == 0 ? 0.5 : 0) }
            return iron
        }
        return c
    }

    static func barrelSide() -> Canvas {
        let c = Canvas(S)
        let band = RGBA(hex: 0x3A3A42)
        c.fill { x, y in
            let stave = x / 5
            var col = T.planks.step(0.25 + T.hash01(305, stave, y / 4) * 0.25 + (x % 5 == 0 ? -0.15 : 0))
            if x % 5 == 4 { col = T.planks.colors[0] }
            if (6...8).contains(y) || (23...25).contains(y) { col = y == 6 || y == 23 ? band.lighten(0.2) : band }
            return col
        }
        return c
    }

    static func barrelTop() -> Canvas {
        let c = T.paintPlanks(306)
        for y in 0..<S {
            for x in 0..<S {
                let d = hypot(Double(x) - 15.5, Double(y) - 15.5)
                if d > 14 { c[x, y] = RGBA(hex: 0x3A3A42) } else if d > 12.5 { c[x, y] = T.planks.colors[0] }
                if d < 2.5 { c[x, y] = RGBA(hex: 0x2A1A0E) }
            }
        }
        return c
    }

    static func coalBlock() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(307)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let (d1, d2, _) = n.voronoi(u, v, cells: 5)
            var col = RGBA(hex: 0x1A1A20).mix(RGBA(hex: 0x2E2E36), d2 - d1)
            if d2 - d1 < 0.05 { col = RGBA(hex: 0x0E0E12) }
            if T.hash01(308, x, y) > 0.97 { col = RGBA(hex: 0x8A8A96) }
            return col
        }
        return c
    }

    static func packedIce() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(309)
        let p = Palette([0x6A98CC, 0x7AA8D8, 0x8AB8E2, 0x9CC6EA, 0xB4D6F2])
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let (d1, d2, _) = n.voronoi(u, v, cells: 3)
            var col = p.ramp(0.35 + n.fbm(u, v, period: 3, octaves: 2) * 0.5)
            if d2 - d1 < 0.04 { col = col.lighten(0.35) }
            return col
        }
        return c
    }

    static func haySide() -> Canvas {
        let c = Canvas(S)
        let band = RGBA(hex: 0x8A3A22)
        c.fill { x, y in
            var col = straw.step(0.2 + T.hash01(310, x, y / 3) * 0.6)
            if x % 3 == 0 { col = col.shade(0.88) }
            if (5...7).contains(y) || (24...26).contains(y) { col = y == 5 || y == 24 ? band.lighten(0.2) : band }
            return col
        }
        return c
    }

    static func hayTop() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let d = hypot(Double(x) - 15.5, Double(y) - 15.5)
            let ring = Int(d * 1.2 + T.hash01(311, x, y) * 1.5) % 3
            return straw.step(ring == 0 ? 0.3 : (ring == 1 ? 0.6 : 0.85))
        }
        return c
    }

    static func berryBush() -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: 312)
        for _ in 0..<70 {
            let x = 3 + Double(rng.nextInt(26)), y = 6 + Double(rng.nextInt(26))
            let r = 1.5 + rng.nextDouble() * 2
            let dx = x - 15.5, dy = y - 20
            if dx * dx / 190 + dy * dy / 160 < 1 { c.disc(x, y, r, T.ginkgo.ramp(0.15 + rng.nextDouble() * 0.55)) }
        }
        for _ in 0..<9 {
            let x = 6 + Double(rng.nextInt(20)), y = 10 + Double(rng.nextInt(18))
            c.disc(x, y, 1.6, RGBA(hex: 0xC0203A))
            c.plot(Int(x) - 1, Int(y) - 1, RGBA(hex: 0xFF8A9A))
        }
        c.outline(RGBA(hex: 0x1E3A16, alpha: 0.55))
        return c
    }
}
