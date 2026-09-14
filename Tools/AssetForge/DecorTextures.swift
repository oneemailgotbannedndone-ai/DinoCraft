import Foundation
import DinoCraftCore

/// Textures for plants, decorative stone, dyed blocks and dyes.
enum DecorTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let colors: [(String, UInt32)] = [
        ("white", 0xE8E8E0), ("black", 0x2A2A30), ("red", 0xB83A2E), ("orange", 0xE0782A), ("yellow", 0xE8C83A),
        ("green", 0x5A9A3A), ("cyan", 0x3AA8A8), ("blue", 0x3A5AB8), ("purple", 0x7A4AAA), ("pink", 0xE88AB0),
    ]

    static func shade(_ hex: UInt32, _ k: Double) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 {
            let v = Double((hex >> shift) & 0xFF)
            let out = k >= 1 ? v + (255 - v) * (k - 1) : v * k
            return UInt32(max(0, min(255, out.rounded())))
        }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

    static func ramp(_ hex: UInt32) -> Palette {
        Palette([shade(hex, 0.68), shade(hex, 0.8), shade(hex, 0.9), hex, shade(hex, 1.12)])
    }

    static func add(to t: inout [String: Canvas]) {
        t["blue_bloom"] = T.paintFlower(petals: [0x3A6AE0, 0x5A8AF0, 0x2A4AC0], center: 0xF0E060, seed: 5)
        t["white_daisy"] = T.paintFlower(petals: [0xFFFFFF, 0xF0F0F0, 0xE0E0E8], center: 0xF0C020, seed: 6)
        t["pink_petal"] = T.paintFlower(petals: [0xF08AC0, 0xF8A8D0, 0xE070A8], center: 0xFFF0A0, seed: 7)
        t["red_mushroom"] = mushroom(cap: 0xC8302A, spots: 0xF2EBD6, glow: false)
        t["brown_mushroom"] = mushroom(cap: 0x8A5A3A, spots: nil, glow: false)
        t["glow_mushroom"] = mushroom(cap: 0x3AE0C8, spots: 0xC8FFF4, glow: true)
        t["cattail"] = reeds(seed: 21, stalk: T.grass, head: 0x6A4026)
        t["horsetail"] = horsetail()
        t["dry_grass"] = dryGrass()
        t["stalagmite"] = stalagmite()
        t["cactus_side"] = cactus(top: false)
        t["cactus_top"] = cactus(top: true)
        t["lily_pad"] = lilyPad()
        t["pebbles"] = pebbles()
        t["moss_block"] = T.paintSimple(120, palette: Palette([0x2F5A22, 0x3A6A28, 0x4A7E30, 0x5A9038, 0x6AA242]), period: 5, specks: 0.08)

        let stone = T.paintStone(121)
        t["cracked_stone_bricks"] = cracks(T.paintStoneBricks(122), seed: 123)
        t["chiseled_stone_bricks"] = chiseled(stone)
        t["sandstone_bricks"] = bricks(T.paintSand(124, palette: T.sandstone), mortar: 0xA88A58)
        t["smooth_sandstone"] = T.paintSimple(125, palette: T.sandstone, period: 2, specks: 0.01)
        t["basalt_bricks"] = bricks(T.paintSimple(126, palette: NewTextures.basalt, period: 4, specks: 0.04), mortar: 0x141218)
        t["obsidian_bricks"] = bricks(T.paintSimple(127, palette: NewTextures.obsidian, period: 4, specks: 0.05), mortar: 0x06040A)
        t["marble"] = marble(128)
        t["marble_bricks"] = bricks(marble(129), mortar: 0xB8B4AE)
        t["slate"] = layered(130, palette: Palette([0x2E3440, 0x3A424E, 0x46505C, 0x525C68, 0x5E6874]))
        t["slate_tiles"] = tiles(layered(131, palette: Palette([0x2E3440, 0x3A424E, 0x46505C, 0x525C68, 0x5E6874])), grout: 0x1E222A)
        let redRock = Palette([0x8A3A22, 0x9E482A, 0xB05834, 0xC0683E, 0xCE7A4A])
        t["red_rock"] = layered(132, palette: redRock)
        t["red_rock_bricks"] = bricks(layered(133, palette: redRock), mortar: 0x5A2A18)
        t["mud_bricks"] = bricks(T.paintSimple(134, palette: Palette([0x6A5038, 0x7A5E42, 0x8A6C4C, 0x9A7A56, 0xA88860]), period: 3, specks: 0.05), mortar: 0x4A3624)
        t["snow_bricks"] = bricks(T.paintSnow(135), mortar: 0xB8C4D0)
        t["ice_bricks"] = bricks(T.paintSimple(136, palette: Palette([0x7AA8D8, 0x8AB8E4, 0x9AC6EE, 0xAAD2F4, 0xC0E0F8]), period: 4, specks: 0.02), mortar: 0x5A88B8)
        t["fossil_bricks"] = bricks(T.paintFossil(137), mortar: 0x6A6258)
        t["amber_tiles"] = tiles(T.paintSimple(138, palette: Palette([0xB45E0E, 0xD07818, 0xE48A22, 0xF29A2E, 0xFFC060]), period: 3, specks: 0.03), grout: 0x6A3A08)
        t["ember_lamp"] = emberLamp()
        t["bone_bricks"] = bricks(T.paintSimple(139, palette: T.bone, period: 3, specks: 0.03), mortar: 0x9A8E70)
        t["mossy_bricks"] = MoreTextures.mossy(MoreTextures.bricks())

        for (name, hex) in colors {
            t["dyed_clay_\(name)"] = T.paintSimple(140 + UInt64(hex % 97), palette: ramp(hex), period: 3, specks: 0.02)
            t["stained_glass_\(name)"] = stainedGlass(hex)
            t["painted_planks_\(name)"] = T.paintPlanks(160 + UInt64(hex % 89), palette: ramp(hex))
        }
    }

    static func item(_ name: String) -> Canvas? {
        guard name.hasPrefix("dye_"), let hex = colors.first(where: { "dye_\($0.0)" == name })?.1 else { return nil }
        let c = Canvas(S)
        let p = ramp(hex)
        // A little clay pot of pigment
        for y in 14..<28 {
            let half = y < 16 ? 7 : (y > 25 ? 6 : 8)
            for x in (16 - half)..<(16 + half) {
                c.plot(x, y, y < 16 ? RGBA(hex: 0x6A4630) : RGBA(hex: 0xA8704A).shade(x < 13 ? 1.1 : 0.9))
            }
        }
        for y in 8..<16 {
            for x in 9..<23 where Double((x - 16) * (x - 16)) / 49 + Double((y - 15) * (y - 15)) / 49 < 1 {
                c.plot(x, y, p.step(0.3 + T.hash01(9, x, y) * 0.7))
            }
        }
        c.outline()
        return c
    }

    // MARK: Plants

    static func mushroom(cap: UInt32, spots: UInt32?, glow: Bool) -> Canvas {
        let c = Canvas(S)
        let stem = RGBA(hex: glow ? 0xB8F0E8 : 0xE6DCC0)
        for y in 18..<31 { for x in 14..<18 { c[x, y] = stem.shade(x == 14 ? 1.05 : 0.92) } }
        let p = ramp(cap)
        for y in 8..<20 {
            for x in 5..<27 {
                let dx = Double(x) - 15.5, dy = Double(y) - 19
                if dx * dx / 110 + dy * dy / 121 < 1 && y < 19 {
                    c[x, y] = p.step(0.25 + Double(19 - y) / 14 + T.hash01(3, x, y) * 0.15)
                }
            }
        }
        if let spots {
            for (x, y) in [(10, 13), (18, 11), (22, 15), (14, 16), (16, 9)] { c[x, y] = RGBA(hex: spots); c[x + 1, y] = RGBA(hex: spots) }
        }
        for x in 6..<26 where c[x, 18].a > 0 { c[x, 18] = p.colors[0].shade(0.7) }
        c.outline(RGBA(hex: 0x1A1410, alpha: 0.6))
        return c
    }

    static func reeds(seed: UInt64, stalk: Palette, head: UInt32) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: seed)
        for i in 0..<5 {
            let x = 6 + Double(i) * 5 + (rng.nextDouble() - 0.5) * 2
            let h = 20 + Double(rng.nextInt(10))
            c.line(x, 32, x + (rng.nextDouble() - 0.5) * 2, 32 - h, width: 1.4) { t in stalk.ramp(0.3 + t * 0.4) }
            if i % 2 == 0 {
                let top = 32 - h
                for y in Int(top)..<Int(top) + 7 { c[Int(x), y] = RGBA(hex: head).shade(y % 2 == 0 ? 1 : 0.85); c[Int(x) + 1, y] = RGBA(hex: head).shade(0.8) }
            }
        }
        return c
    }

    static func horsetail() -> Canvas {
        let c = Canvas(S)
        for (i, x) in [8, 15, 22].enumerated() {
            let h = 22 + i * 3
            for y in (32 - h)..<32 {
                c[x, y] = y % 5 == 0 ? RGBA(hex: 0x2A3A1A) : T.grass.step(0.3 + Double(i) * 0.2)
                if y % 5 == 1 && y < 26 { c[x - 1, y] = T.grass.colors[1]; c[x + 1, y] = T.grass.colors[1]; c[x - 2, y + 1] = T.grass.colors[0]; c[x + 2, y + 1] = T.grass.colors[0] }
            }
        }
        return c
    }

    static func dryGrass() -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: 44)
        let p = Palette([0x8A6A3A, 0xA8844A, 0xC09A5A, 0xD4B070, 0xE2C488])
        for _ in 0..<12 {
            let x0 = Double(3 + rng.nextInt(26)), h = 8 + Double(rng.nextInt(14)), lean = (rng.nextDouble() - 0.5) * 10
            let tone = rng.nextDouble()
            c.line(x0, 32, x0 + lean, 32 - h, width: 1.3) { t in p.ramp(0.2 + t * 0.6 + tone * 0.2) }
        }
        return c
    }

    static func stalagmite() -> Canvas {
        let c = Canvas(S)
        for y in 2..<32 {
            let half = Double(y - 2) / 30 * 7 + 1
            for x in 0..<S where abs(Double(x) - 15.5) < half {
                c[x, y] = T.stone.step(0.3 + T.hash01(5, x, y / 2) * 0.5).shade(Double(x) < 15.5 ? 1.08 : 0.85)
            }
        }
        c.outline(RGBA(hex: 0x1A1A1E, alpha: 0.5))
        return c
    }

    static func cactus(top: Bool) -> Canvas {
        let c = Canvas(S)
        let p = Palette([0x2A6A2A, 0x357A30, 0x428A38, 0x509A40, 0x62AA4C])
        c.fill { x, y in
            if top {
                let d = hypot(Double(x) - 15.5, Double(y) - 15.5)
                return p.step(d < 6 ? 0.85 : (d < 11 ? 0.55 : 0.35))
            }
            let rib = (x % 6) < 2
            return p.step((rib ? 0.75 : 0.35) + T.hash01(8, x, y) * 0.2)
        }
        if !top {
            for y in stride(from: 3, to: S, by: 7) { for x in stride(from: 1, to: S, by: 6) { c[x, y] = RGBA(hex: 0xF2EBD6); c[x + 1, y - 1] = RGBA(hex: 0xD8D0B8) } }
        }
        return c
    }

    static func lilyPad() -> Canvas {
        let c = Canvas(S)
        let p = Palette([0x2E6A2A, 0x3A7E32, 0x4A923C, 0x5AA646])
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) - 15.5, dy = Double(y) - 15.5
                let d = hypot(dx, dy)
                let notch = dx > 0 && abs(dy) < dx * 0.35
                if d < 14 && !notch { c[x, y] = p.step(0.2 + d / 18 + T.hash01(4, x, y) * 0.1) }
            }
        }
        for k in 0..<8 {
            let a = Double(k) / 8 * 2 * .pi + 0.4
            c.line(15.5, 15.5, 15.5 + cos(a) * 12, 15.5 + sin(a) * 12, width: 0.6) { _ in p.colors[3].lighten(0.15) }
        }
        return c
    }

    static func pebbles() -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: 77)
        for _ in 0..<9 {
            let x = 4 + Double(rng.nextInt(24)), y = 4 + Double(rng.nextInt(24)), r = 1.5 + rng.nextDouble() * 2
            let tone = rng.nextDouble()
            c.disc(x, y, r, T.stone.ramp(0.3 + tone * 0.6))
            c.disc(x - r * 0.3, y - r * 0.3, r * 0.4, T.stone.colors[4])
        }
        return c
    }

    // MARK: Stone

    static func bricks(_ base: Canvas, mortar: UInt32) -> Canvas {
        let m = RGBA(hex: mortar)
        for y in 0..<S {
            for x in 0..<S {
                let row = y / 8
                let off = row % 2 == 0 ? 0 : 8
                if y % 8 == 7 || (x + off) % 16 == 15 { base[x, y] = m }
                else if y % 8 == 0 || (x + off) % 16 == 0 { base[x, y] = base[x, y].lighten(0.1) }
            }
        }
        return base
    }

    static func tiles(_ base: Canvas, grout: UInt32) -> Canvas {
        let g = RGBA(hex: grout)
        for y in 0..<S {
            for x in 0..<S {
                if x % 16 == 15 || y % 16 == 15 { base[x, y] = g }
                else if x % 16 == 0 || y % 16 == 0 { base[x, y] = base[x, y].lighten(0.12) }
            }
        }
        return base
    }

    static func cracks(_ base: Canvas, seed: UInt64) -> Canvas {
        var rng = SplitMix64(seed: seed)
        for _ in 0..<5 {
            var x = Double(rng.nextInt(S)), y = Double(rng.nextInt(S))
            for _ in 0..<(4 + rng.nextInt(6)) {
                let nx = x + (rng.nextDouble() - 0.5) * 5, ny = y + rng.nextDouble() * 3
                base.line(x, y, nx, ny, width: 0.8) { _ in RGBA(hex: 0x2A2A30, alpha: 0.9) }
                x = nx; y = ny
            }
        }
        return base
    }

    static func chiseled(_ base: Canvas) -> Canvas {
        let dark = RGBA(hex: 0x4A4B52), light = RGBA(hex: 0xB0B3BC)
        for i in 0..<S { base[i, 0] = light; base[0, i] = light; base[i, S - 1] = dark; base[S - 1, i] = dark }
        for r in [11.0, 6.0] {
            for k in 0..<64 {
                let a = Double(k) / 64 * 2 * .pi
                let x = Int((15.5 + cos(a) * r).rounded()), y = Int((15.5 + sin(a) * r).rounded())
                base[x, y] = dark
                base[x + (cos(a) > 0 ? -1 : 1), y] = light.shade(0.9)
            }
        }
        for i in 13..<19 { base[i, 15] = dark; base[15, i] = dark }
        return base
    }

    static func marble(_ seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = T.noise(seed)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let vein = abs(sin((u * 2 + v) * .pi * 2 + n.fbm(u, v, period: 3, octaves: 3) * 6))
            var col = RGBA(hex: 0xECEAE4).mix(RGBA(hex: 0xD8D4CC), n.value(u, v, period: 4))
            if vein < 0.08 { col = RGBA(hex: 0x9A96A0) } else if vein < 0.16 { col = col.mix(RGBA(hex: 0xB8B4BE), 0.6) }
            return col
        }
        return c
    }

    static func layered(_ seed: UInt64, palette: Palette) -> Canvas {
        let c = Canvas(S)
        let n = T.noise(seed)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let band = n.value(u * 0.5, v * 4 + n.value(u, v, period: 4) * 0.3, period: 8)
            return palette.step(band * 0.8 + T.hash01(seed, x, y) * 0.2)
        }
        return c
    }

    static func emberLamp() -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let frame = x % 16 < 2 || y % 16 < 2 || x % 16 == 15 || y % 16 == 15
            if frame { return RGBA(hex: 0x4A2A1A) }
            let d = hypot(Double(x % 16) - 7.5, Double(y % 16) - 7.5)
            return RGBA(hex: 0xFFE070).mix(RGBA(hex: 0xE0601A), min(1, d / 8))
        }
        return c
    }

    static func stainedGlass(_ hex: UInt32) -> Canvas {
        let base = T.paintGlass()
        let tint = RGBA(hex: hex)
        for i in 0..<(S * S) {
            let p = base.px[i]
            if p.a > 0.5 {
                base.px[i] = p.mix(tint, 0.55).withAlpha(0.95)
            } else {
                base.px[i] = tint.withAlpha(0.42)
            }
        }
        return base
    }
}
