import Foundation
import DinoCraftCore

/// Textures for the Underworld, Amber Skylands, gateways, creatures' drops and new tools.
enum NewTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let basalt = Palette([0x1E1C22, 0x2A282F, 0x36343C, 0x44424A, 0x524F58])
    static let obsidian = Palette([0x0B0812, 0x15101F, 0x1F1830, 0x2C2244, 0x3D2F5E])
    static let ash = Palette([0x5E5A58, 0x6E6A67, 0x7D7976, 0x8C8884, 0x9A9692])
    static let skyGrass = Palette([0x2E9C8C, 0x3BB5A2, 0x4FCDB6, 0x6FDDC6, 0x9AEBD8])
    static let skySoil = Palette([0x6E6280, 0x7B6F8D, 0x897C9A, 0x978AA8, 0xA598B5])

    static func add(to t: inout [String: Canvas]) {
        t["lava"] = lava()
        ToonTextures.add(to: &t)
        MoreTextures.add(to: &t)
        BiomeTextures.add(to: &t)
        ArmorTextures.add(to: &t)
        CropTextures.add(to: &t)
        t["basalt_side"] = basaltSide()
        t["basalt_top"] = basaltTop()
        t["ash"] = T.paintSand(75, palette: ash)
        t["magma_rock"] = magma()
        t["obsidian"] = obsidianTexture()
        t["ember_crystal"] = emberCrystal()
        t["sky_grass_top"] = skyGrassTop()
        t["sky_soil"] = T.paintSimple(77, palette: skySoil, period: 4, specks: 0.05)
        t["sky_grass_side"] = T.paintGrassSide(top: skyGrass, seed: 78, base: T.paintSimple(77, palette: skySoil, period: 4, specks: 0.05))
        t["cloud"] = cloud()
        t["amber_block"] = amberBlock()
        t["skybloom"] = T.paintFlower(petals: [0xBFF6FF, 0x7FE3F0, 0xE6FBFF], center: 0xFFD23A, seed: 3)
        t["underworld_portal"] = portal(dark: 0x3A0A2A, mid: 0xB0204A, light: 0xFF8A5A, seed: 90)
        t["skylands_portal"] = portal(dark: 0x6A4A0A, mid: 0xF2A33A, light: 0xBFF6FF, seed: 91)
    }

    static func uv(_ x: Int, _ y: Int) -> (Double, Double) { T.uv(x, y) }

    static func lava() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 73), m = TileNoise(seed: 74)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let f = n.fbm(u, v, period: 3, octaves: 4)
            var col = RGBA(hex: 0xB0280A).mix(RGBA(hex: 0xFF7A18), f)
            if abs(m.fbm(u, v, period: 4, octaves: 3) - 0.5) < 0.045 { col = RGBA(hex: 0xFFE27A) }
            if f < 0.32 { col = col.shade(0.7) }
            return col
        }
        return c
    }

    static func basaltSide() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 70)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let column = n.value(Double(x / 8) / 4 + 0.05, 0.5, period: 4)
            var col = basalt.step(0.2 + column * 0.45 + n.value(u, v * 0.25, period: 8) * 0.3)
            if x % 8 == 0 { col = basalt.colors[0] }
            if x % 8 == 1 { col = col.lighten(0.06) }
            return col
        }
        return c
    }

    static func basaltTop() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 71)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, id) = n.voronoi(u, v, cells: 4)
            if d2 - d1 < 0.07 { return basalt.colors[0] }
            return basalt.step(0.3 + Double(id % 100) / 100 * 0.5 - d1 * 0.2)
        }
        return c
    }

    static func magma() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 72)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, _) = n.voronoi(u, v, cells: 5)
            let edge = d2 - d1
            if edge < 0.1 { return RGBA(hex: 0xFFD060).mix(RGBA(hex: 0xFF5A1A), edge / 0.1) }
            if edge < 0.16 { return RGBA(hex: 0x8A2A10) }
            return basalt.step(0.15 + d1 * 0.6).mix(RGBA(hex: 0x3A1410), 0.3)
        }
        return c
    }

    static func obsidianTexture() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 74)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = obsidian.step(n.fbm(u, v, period: 3, octaves: 4))
            if T.hash01(76, x, y) > 0.975 { col = RGBA(hex: 0x7A63B8) }
            if abs(n.value(u + v, v, period: 4) - 0.5) < 0.02 { col = col.lighten(0.12) }
            return col
        }
        return c
    }

    static func emberCrystal() -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: 76)
        for k in 0..<6 {
            let angle = Double.pi / 2 + (Double(k) - 2.5) * 0.28 + (rng.nextDouble() - 0.5) * 0.15
            let len = 14 + rng.nextDouble() * 12
            let x0 = 16 + (rng.nextDouble() - 0.5) * 6
            c.line(x0, 31, x0 + cos(angle) * len, 31 - sin(angle) * len, width: 3.5) { t in
                RGBA(hex: 0xB8280E).mix(RGBA(hex: 0xFFD27A), t)
            }
        }
        c.outline(RGBA(hex: 0x4A0A06, alpha: 0.9))
        return c
    }

    static func skyGrassTop() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 79)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = skyGrass.step(n.fbm(u, v, period: 4, octaves: 4) * 0.9 + 0.05)
            let h = T.hash01(79, x, y)
            if h > 0.94 { col = RGBA(hex: 0xE6FBFF) } else if h < 0.06 { col = skyGrass.colors[0] }
            return col
        }
        return c
    }

    static func cloud() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 80)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let f = n.fbm(u, v, period: 3, octaves: 3)
            return RGBA(hex: 0xDDE8F5).mix(RGBA(hex: 0xFFFFFF), f).withAlpha(0.86)
        }
        return c
    }

    static func amberBlock() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 81)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, id) = n.voronoi(u, v, cells: 3)
            let edge = x == 0 || y == 0 || x == S - 1 || y == S - 1
            if edge { return RGBA(hex: 0xA85A0E) }
            var col = RGBA(hex: 0xE07A12).mix(RGBA(hex: 0xFFD27A), max(0, 0.6 - d1) + Double(id % 10) / 40)
            if d2 - d1 < 0.05 { col = col.shade(0.85) }
            if T.hash01(82, x, y) > 0.985 { col = RGBA(hex: 0xFFF6D0) }
            return col
        }
        return c
    }

    static func portal(dark: UInt32, mid: UInt32, light: UInt32, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: seed)
        let a = RGBA(hex: dark), b = RGBA(hex: mid), l = RGBA(hex: light)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let dx = u - 0.5, dy = v - 0.5
            let r = sqrt(dx * dx + dy * dy)
            let swirl = sin(atan2(dy, dx) * 3 + r * 18 + n.fbm(u, v, period: 3, octaves: 3) * 6)
            var col = a.mix(b, 0.5 + 0.5 * swirl)
            if swirl > 0.85 { col = col.mix(l, 0.6) }
            if T.hash01(seed, x, y) > 0.97 { col = l }
            return col.withAlpha(0.8)
        }
        return c
    }

    // MARK: Items

    static func item(_ name: String) -> Canvas? {
        if let egg = EggTextures.item(name) { return egg }
        if let toon = ToonTextures.item(name) { return toon }
        if let more = MoreTextures.item(name) { return more }
        let c = Canvas(S)
        switch name {
        case "raw_dino_meat", "cooked_dino_steak":
            let raw = name == "raw_dino_meat"
            c.line(6, 27, 13, 20, width: 3.5) { _ in RGBA(hex: 0xE6DCC0) }
            c.disc(5, 27, 2.6, RGBA(hex: 0xF2EBD6)); c.disc(8, 29, 2.4, RGBA(hex: 0xF2EBD6))
            c.disc(19, 14, 10, raw ? RGBA(hex: 0xC8425A) : RGBA(hex: 0x7A3E1E))
            c.disc(16, 11, 4.5, raw ? RGBA(hex: 0xE87A8A) : RGBA(hex: 0x9C5A2E))
            if raw {
                c.line(13, 17, 24, 9, width: 1.2) { _ in RGBA(hex: 0xF2C0C8) }
            } else {
                for k in 0..<3 { c.line(12 + Double(k) * 4, 20, 20 + Double(k) * 4, 8, width: 1.3) { _ in RGBA(hex: 0x4A2210) } }
            }
        case "dino_hide":
            for y in 7..<26 { for x in 5..<27 where (x - 16) * (x - 16) / 3 + (y - 16) * (y - 16) < 90 {
                c.plot(x, y, RGBA(hex: 0xB88A5A).shade(y % 7 == 0 ? 0.9 : 1))
            } }
            for (x, y) in [(10, 12), (19, 10), (22, 19), (13, 20), (16, 15)] { c.disc(Double(x), Double(y), 1.8, RGBA(hex: 0x7A5230)) }
        case "raptor_claw":
            for k in 0..<18 {
                let t = Double(k) / 17
                let a = Double.pi * (0.1 + 0.8 * t)
                c.disc(16 + cos(a) * 10, 22 - sin(a) * 12, 3.6 * (1 - t) + 0.9, RGBA(hex: 0xE6DCC0).mix(RGBA(hex: 0x9C8E70), t))
            }
        case "feather":
            c.line(8, 27, 24, 6, width: 1.3) { _ in RGBA(hex: 0xF2EBD6) }
            for k in 2..<14 {
                let t = Double(k) / 14
                let px = 8 + 16 * t, py = 27 - 21 * t
                let w = 5 * sin(.pi * t)
                c.line(px, py, px - w, py - w * 0.3, width: 1.2) { _ in RGBA(hex: 0x5FC9C0).mix(.init(hex: 0xFFFFFF), t * 0.5) }
                c.line(px, py, px + w * 0.3, py + w, width: 1.2) { _ in RGBA(hex: 0x3FA8A0).mix(.init(hex: 0xFFFFFF), t * 0.5) }
            }
        case "ember_shard":
            for y in 6..<28 { for x in 8..<25 where abs(Double(x) - 16.5) < Double(min(y - 5, 28 - y)) * 0.55 {
                c.plot(x, y, x < 16 ? RGBA(hex: 0xFFB050) : RGBA(hex: 0xE0501A))
            } }
            c.disc(14, 12, 1.5, RGBA(hex: 0xFFF0B0))
        case "ember_lighter":
            c.disc(20, 12, 7, RGBA(hex: 0x9098A4)); c.disc(20, 12, 4, .clear)
            for y in 16..<28 { for x in 6..<16 where abs(Double(x) - 11) < Double(y - 15) * 0.45 { c.plot(x, y, RGBA(hex: 0x33343A)) } }
            c.disc(13, 15, 2, RGBA(hex: 0xFFB050))
        case "claw_dagger":
            c.line(6, 26, 12, 20, width: 3) { _ in RGBA(hex: 0x6A4630) }
            c.line(9, 17, 15, 23, width: 2.5) { _ in RGBA(hex: 0x3A2A1C) }
            for k in 0..<16 {
                let t = Double(k) / 15
                c.disc(13 + 13 * t + sin(t * .pi) * 2, 19 - 13 * t + sin(t * .pi) * 2, 2.6 * (1 - t) + 0.8, RGBA(hex: 0xF2EBD6).mix(RGBA(hex: 0xB8AB8A), t))
            }
        default:
            return nil
        }
        c.outline()
        return c
    }
}
