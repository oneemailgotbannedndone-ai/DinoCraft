import Foundation
import DinoCraftCore

/// The sea floor: kelp, seagrass, five colours of coral (blocks and branching coral), sea lanterns,
/// and fish to eat.
enum OceanTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    /// Coral colours: (name, dark, mid, light, glint).
    static let corals: [(String, UInt32, UInt32, UInt32, UInt32)] = [
        ("red", 0x8E1C24, 0xC8323A, 0xE8604E, 0xFFB08A),
        ("pink", 0x9A3A6E, 0xD85E9A, 0xF08AB8, 0xFFD0E4),
        ("yellow", 0x9A7A10, 0xD8B424, 0xF2D84A, 0xFFF4A8),
        ("blue", 0x1E4A9E, 0x3474D8, 0x5AA0F2, 0xB8E0FF),
        ("purple", 0x5A2A8A, 0x8248C0, 0xA878E0, 0xE0C8FF),
    ]

    static func add(to t: inout [String: Canvas]) {
        t["kelp"] = kelp()
        t["seagrass"] = seagrass()
        t["sea_lantern"] = seaLantern()
        for (i, coral) in corals.enumerated() {
            t["coral_\(coral.0)"] = coralBlock(coral, seed: 300 + UInt64(i))
            t["coral_fan_\(coral.0)"] = coralFan(coral, shape: i, seed: 310 + UInt64(i))
        }
    }

    // MARK: Plants

    /// A tall wavy frond with leaf blades and little gas bladders; tiles top to bottom.
    static func kelp() -> Canvas {
        let c = Canvas(S)
        let stem = Palette([0x2E4A14, 0x3E6018, 0x557A20, 0x6C922A])
        let blade = Palette([0x3A5A16, 0x4E7A1E, 0x68962A, 0x86B23A])
        for y in 0..<S {
            let a = Double(y) / Double(S) * 2 * .pi
            let cx = 15.5 + sin(a) * 2.2
            for x in 0..<S {
                let d = Double(x) + 0.5 - cx
                if abs(d) < 2.2 { c.plot(x, y, stem.step(0.3 + (d < 0 ? 0.4 : 0) + T.hash01(401, x, y) * 0.2)) }
            }
            // Blades sprout left and right, alternating down the stem.
            let phase = y % 16
            if phase < 9 {
                let side = (y / 16) % 2 == 0 ? -1.0 : 1.0
                let length = 11.0 - abs(Double(phase) - 4) * 1.4
                for k in 0..<Int(length) {
                    let x = Int(cx + side * (2 + Double(k)))
                    let droop = k / 3
                    c.plot(x, y + droop, blade.step(0.25 + Double(k) / length * 0.6 + T.hash01(402, x, y) * 0.15))
                    c.plot(x, y + droop + 1, blade.step(0.1 + Double(k) / length * 0.4))
                }
            }
        }
        // Gas bladders
        for (x, y) in [(12, 6), (19, 14), (12, 22), (19, 30)] {
            c.disc(Double(x), Double(y), 1.8, RGBA(hex: 0x9AAE3A))
            c.plot(x - 1, y - 1, RGBA(hex: 0xD8E07A))
        }
        return c
    }

    /// A tuft of thin, swaying blades.
    static func seagrass() -> Canvas {
        let c = Canvas(S)
        let green = Palette([0x2A6A2A, 0x358A34, 0x46A63E, 0x62C050, 0x8AD86A])
        for blade in 0..<9 {
            let base = 5.0 + Double(blade) * 2.7 + T.hash01(410, blade, 0) * 2
            let height = 14.0 + T.hash01(411, blade, 0) * 16
            let lean = (T.hash01(412, blade, 0) - 0.5) * 8
            for step in 0..<Int(height) {
                let t = Double(step) / height
                let x = base + lean * t * t
                let y = 31 - step
                c.plot(Int(x), y, green.step(0.15 + t * 0.7 + T.hash01(413, blade, step) * 0.15))
                if t < 0.4 { c.plot(Int(x) + 1, y, green.step(0.1 + t * 0.5)) }
            }
        }
        return c
    }

    /// Coral rock: bumpy cells with dark pores and lit rims.
    static func coralBlock(_ k: (String, UInt32, UInt32, UInt32, UInt32), seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: seed)
        let p = Palette([k.1, k.2, k.3, k.4])
        c.fill { x, y in
            let u = (Double(x) + 0.5) / Double(S), v = (Double(y) + 0.5) / Double(S)
            let (d1, d2, id) = n.voronoi(u, v, cells: 6)
            let edge = d2 - d1
            let bump = 1 - min(1, d1 * 1.6)
            if edge < 0.08 { return p.colors[0].shade(0.85) }
            // Little round pores dotted over the polyps.
            if d1 < 0.12 && id % 3 == 0 { return p.colors[0] }
            let light = bump * 0.65 + n.fbm(u, v, period: 4) * 0.35 - (Double(y) / Double(S)) * 0.1
            return p.step(0.1 + light * 0.95)
        }
        return c
    }

    /// Branching coral in five shapes: fire branches, a brain-like bush, a horn fan, tubes and bubbles.
    static func coralFan(_ k: (String, UInt32, UInt32, UInt32, UInt32), shape: Int, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let dark = RGBA(hex: k.1), mid = RGBA(hex: k.2), light = RGBA(hex: k.3), glint = RGBA(hex: k.4)
        switch shape {
        case 0:
            // Fire coral: forking branches with bright tips.
            func branch(_ x: Double, _ y: Double, _ angle: Double, _ length: Double, _ depth: Int) {
                let ex = x + sin(angle) * length, ey = y - cos(angle) * length
                c.line(x, y, ex, ey, width: max(1.2, Double(3 - depth) * 1.1)) { t in mid.mix(light, t * 0.6) }
                if depth < 3 {
                    branch(ex, ey, angle - 0.45, length * 0.72, depth + 1)
                    branch(ex, ey, angle + 0.4, length * 0.7, depth + 1)
                } else {
                    c.disc(ex, ey, 1.1, glint)
                }
            }
            branch(16, 31, 0, 9, 0)
        case 1:
            // Brain coral bush: a round cluster of wiggly ridges.
            for y in 8..<31 {
                for x in 4..<28 {
                    let dx = Double(x) - 15.5, dy = Double(y) - 20
                    guard dx * dx / 140 + dy * dy / 120 < 1 else { continue }
                    let ridge = sin(Double(x) * 0.9 + sin(Double(y) * 0.7) * 2.2) > 0.2
                    c.plot(x, y, ridge ? light : (dy < 0 ? mid : dark))
                }
            }
            c.plot(11, 12, glint); c.plot(12, 11, glint); c.plot(18, 10, glint)
        case 2:
            // Horn coral: a fan of flat lobes.
            for lobe in 0..<5 {
                let a = (Double(lobe) - 2) * 0.42
                let length = 12 + Double(lobe % 2) * 3
                c.line(16, 30, 16 + sin(a) * length, 30 - cos(a) * length, width: 4.2) { t in dark.mix(light, t) }
                c.disc(16 + sin(a) * length, 30 - cos(a) * length, 2.6, light)
                c.plot(Int(16 + sin(a) * length), Int(29 - cos(a) * length), glint)
            }
        case 3:
            // Tube coral: open tubes of different heights.
            for (i, x) in [7.0, 12, 16.5, 21, 25].enumerated() {
                let top = 10.0 + Double([6, 0, 3, 8, 4][i])
                c.line(x, 31, x, top, width: 3.6) { t in dark.mix(mid, t) }
                c.disc(x, top, 2.2, light)
                c.disc(x, top, 1.0, dark)
            }
        default:
            // Bubble coral: clusters of glossy spheres on short stalks.
            c.line(16, 31, 16, 22, width: 2.5) { _ in dark }
            c.line(16, 26, 10, 18, width: 2) { _ in dark }
            c.line(16, 26, 22, 17, width: 2) { _ in dark }
            for (x, y, r) in [(10.0, 15.0, 4.2), (22, 14, 4.5), (16, 19, 3.8), (13, 9, 3.2), (20, 7, 2.8), (8, 22, 2.6), (24, 22, 2.8)] {
                c.disc(x, y, r, mid)
                c.disc(x - r * 0.25, y - r * 0.25, r * 0.6, light)
                c.plot(Int(x - r * 0.4), Int(y - r * 0.45), glint)
            }
        }
        return c
    }

    /// A glowing sea-glass lantern: pale cyan panes in a frame, brightest in the middle.
    static func seaLantern() -> Canvas {
        let c = Canvas(S)
        let glass = Palette([0x6ABCC0, 0x8AD8D8, 0xAEEAE6, 0xD6FAF4, 0xFFFFFF])
        c.fill { x, y in
            let fx = Double(x) + 0.5 - 16, fy = Double(y) + 0.5 - 16
            if x < 2 || y < 2 || x > 29 || y > 29 { return RGBA(hex: 0x4E8E96) }
            if x == 2 || y == 2 { return RGBA(hex: 0x9AD8D8) }
            let pane = (x / 8 + y / 8) % 2 == 0
            let glow = 1 - min(1, sqrt(fx * fx + fy * fy) / 20)
            if x % 8 == 1 || y % 8 == 1 { return glass.step(0.2 + glow * 0.3) }
            return glass.step(0.25 + glow * 0.7 + (pane ? 0.05 : -0.05) + T.hash01(420, x, y) * 0.08)
        }
        return c
    }

    // MARK: Items

    static func item(_ name: String) -> Canvas? {
        switch name {
        case "raw_fish": return fish(body: Palette([0x6A7A86, 0x8A9AA6, 0xAAB8C2, 0xD2DCE2]), fin: 0x5A6A78, stripe: nil)
        case "cooked_fish": return fish(body: Palette([0x8A5424, 0xA86C32, 0xC48A44, 0xDCA85E]), fin: 0x6A3E18, stripe: nil)
        case "tropical_fish": return fish(body: Palette([0xC85A10, 0xE87A1A, 0xF89A2A, 0xFFC060]), fin: 0x2A2A2A, stripe: 0xFFFFFF)
        case "dried_kelp":
            let c = Canvas(S)
            let p = Palette([0x1E2A10, 0x2E3E18, 0x3E5220, 0x52682A])
            for y in 6..<27 {
                let wave = sin(Double(y) * 0.6) * 1.5
                for x in 0..<S {
                    let d = Double(x) - 16 - wave
                    if abs(d) < 5 { c.plot(x, y, p.step(0.2 + (d < -2 ? 0.5 : 0) + T.hash01(430, x, y) * 0.3)) }
                }
            }
            c.outline()
            return c
        default:
            return nil
        }
    }

    /// A side-on fish: body, tail, fins and an eye.
    static func fish(body p: Palette, fin: UInt32, stripe: UInt32?) -> Canvas {
        let c = Canvas(S)
        for y in 8..<25 {
            for x in 3..<24 {
                let dx = (Double(x) - 13) / 10.5, dy = (Double(y) - 16) / 7
                guard dx * dx + dy * dy < 1 else { continue }
                var col = p.step(0.2 + (dy < 0 ? 0.45 : 0.1) - dx * 0.15 + T.hash01(440, x / 2, y / 2) * 0.15)
                if let stripe, abs(Double(x) - 10) < 1.6 || abs(Double(x) - 17) < 1.4 { col = RGBA(hex: stripe) }
                c.plot(x, y, col)
            }
        }
        // Tail
        for y in 9..<24 {
            let spread = abs(Double(y) - 16)
            for x in 23..<30 where Double(x - 23) > spread * 0.55 - 1 { c.plot(x, y, RGBA(hex: fin)) }
        }
        // Fins
        for row in 0..<4 {
            for x in (10 + row)..<(18 - row / 2) { c.plot(x, 8 - row, RGBA(hex: fin)) }
        }
        c.line(12, 23, 15, 26, width: 1.6) { _ in RGBA(hex: fin) }
        // Eye and gill
        c.disc(7, 14.5, 1.6, RGBA(hex: 0xFFFFFF)); c.plot(6, 14, RGBA(hex: 0x111111))
        c.line(10, 12, 10.5, 19, width: 1) { _ in p.colors[0] }
        c.outline()
        return c
    }
}
