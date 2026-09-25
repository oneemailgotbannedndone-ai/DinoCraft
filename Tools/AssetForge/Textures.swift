import Foundation
import DinoCraftCore

/// DinoCraft's original texture set, painted procedurally at 32×32.
/// Every block texture tiles seamlessly; sprites carry transparent backgrounds
/// with a dark outline.
enum TexturePainter {
    static let S = 32

    // MARK: Palettes

    static let stone = Palette([0x5C5E66, 0x6D6F78, 0x7B7E88, 0x8A8D97, 0x9A9DA6])
    static let dirt = Palette([0x5A3A24, 0x6A4630, 0x7A5438, 0x8A6242, 0x9A7050])
    static let grass = Palette([0x357A2A, 0x438E30, 0x52A038, 0x64B242, 0x7CC24C])
    static let sand = Palette([0xC3A874, 0xD2B783, 0xDCC58E, 0xE6D19E, 0xEFDDB0])
    static let planks = Palette([0x7E552E, 0x9A6A3C, 0xB27D48, 0xC48D54, 0xD6A066])
    static let bark = Palette([0x3E2A1A, 0x523824, 0x66472E, 0x7A5638, 0x8C6644])
    static let redBark = Palette([0x4E2216, 0x6A2E1E, 0x843A26, 0x9C4830, 0xB0583A])
    static let ginkgo = Palette([0x3F7A22, 0x5A9A2C, 0x78B236, 0x98C640, 0xBAD850])
    static let needles = Palette([0x1C4426, 0x255632, 0x2F6A3C, 0x3C7E48, 0x4E9256])
    static let snow = Palette([0xCBD8E6, 0xDCE6F0, 0xE9F0F7, 0xF4F8FC, 0xFFFFFF])
    static let cobble = Palette([0x55575E, 0x6A6C74, 0x7E8089, 0x92949D, 0xA4A6AE])
    static let bedrock = Palette([0x141418, 0x26262C, 0x3A3A40, 0x4E4E56, 0x62626A])
    static let clay = Palette([0x7F8896, 0x8B94A2, 0x98A1AE, 0xA4ADBA, 0xB0B9C5])
    static let mud = Palette([0x2E2219, 0x3A2C21, 0x46352A, 0x534033, 0x5F4B3C])
    static let bone = Palette([0xB5A888, 0xC9BD9E, 0xD9CEB2, 0xE6DCC2, 0xF2EBD6])
    static let sandstone = Palette([0xBFA36C, 0xCBB07A, 0xD8C08A, 0xE2CC98, 0xEBD8A8])

    static func noise(_ seed: UInt64) -> TileNoise { TileNoise(seed: seed) }

    static func uv(_ x: Int, _ y: Int) -> (Double, Double) {
        ((Double(x) + 0.5) / Double(S), (Double(y) + 0.5) / Double(S))
    }

    static func hash01(_ seed: UInt64, _ x: Int, _ y: Int) -> Double {
        Double(Hashing.hash(seed, Int32(x), Int32(y), 3) >> 11) / Double(1 << 53)
    }

    // MARK: Base materials

    static func paintStone(_ seed: UInt64 = 1) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed), m = noise(seed + 9)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let t = n.fbm(u, v, period: 4, octaves: 4) * 0.8 + m.value(u, v, period: 16) * 0.25
            return stone.step(t * 0.95)
        }
        // Hairline strata cracks
        var rng = SplitMix64(seed: seed &* 31)
        for _ in 0..<4 {
            var x = Double(rng.nextInt(S)), y = Double(rng.nextInt(S))
            for _ in 0..<(5 + rng.nextInt(6)) {
                let nx = x + Double(rng.nextInt(3) + 1), ny = y + Double(rng.nextInt(3) - 1)
                for i in 0...3 {
                    let t = Double(i) / 3
                    let px = Int(x + (nx - x) * t), py = Int(y + (ny - y) * t)
                    c[px, py] = c[px, py].shade(0.78)
                }
                x = nx; y = ny
            }
        }
        return c
    }

    static func paintDirt(_ seed: UInt64 = 2) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = dirt.step(n.fbm(u, v, period: 4, octaves: 4) * 1.05 - 0.02)
            let h = hash01(seed, x, y)
            if h > 0.94 { col = RGBA(hex: 0x8C857C) }       // pebbles
            else if h < 0.05 { col = col.shade(0.75) }
            return col
        }
        return c
    }

    static func paintGrassTop(_ seed: UInt64 = 3) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed), m = noise(seed + 1)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = grass.step(n.fbm(u, v, period: 4, octaves: 4) * 0.9 + 0.05)
            let h = hash01(seed, x, y)
            if h > 0.93 { col = grass.colors[4].lighten(0.1) }
            else if h < 0.07 { col = grass.colors[0] }
            if m.value(u, v, period: 3) > 0.72 { col = col.mix(RGBA(hex: 0x9BC84C), 0.35) }   // sun-bleached tufts
            return col
        }
        return c
    }

    static func paintGrassSide(top: Palette = grass, seed: UInt64 = 4, snowy: Bool = false, base: Canvas? = nil) -> Canvas {
        let c = base ?? paintDirt(seed)
        let n = noise(seed + 5)
        for x in 0..<S {
            let depth = 5 + Int(n.value((Double(x) + 0.5) / Double(S), 0.3, period: 8) * 6) + (hash01(seed, x, 0) > 0.75 ? 2 : 0)
            for y in 0..<depth {
                let t = Double(y) / Double(depth)
                var col = top.step(0.85 - t * 0.55 + (hash01(seed, x, y) - 0.5) * 0.3)
                if y == depth - 1 { col = col.shade(0.8) }
                c[x, y] = col
            }
        }
        _ = snowy
        return c
    }

    static func paintSand(_ seed: UInt64 = 5, palette: Palette = sand) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = palette.ramp(n.fbm(u, v, period: 4, octaves: 3) * 0.6 + 0.2)
            let h = hash01(seed, x, y)
            if h > 0.9 { col = col.lighten(0.18) } else if h < 0.12 { col = col.shade(0.9) }
            return col
        }
        return c
    }

    static func paintCobble(_ seed: UInt64 = 6, moss: Bool = false) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed), mossN = noise(seed + 77)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, id) = n.voronoi(u, v, cells: 5)
            let edge = d2 - d1
            if edge < 0.09 { return RGBA(hex: 0x3E3F45) }
            let tone = Double(id % 1000) / 1000
            var col = cobble.step(0.2 + tone * 0.6 + (0.4 - d1) * 0.5)
            if edge < 0.16 { col = col.shade(0.82) }
            if d1 < 0.18 { col = col.lighten(0.08) }
            if moss {
                let m = mossN.fbm(u, v, period: 3, octaves: 3)
                if m > 0.52 { col = (m > 0.62 ? RGBA(hex: 0x5E9E3A) : RGBA(hex: 0x467E30)).mix(col, 0.15) }
            }
            return col
        }
        return c
    }

    static func paintGravel(_ seed: UInt64 = 7) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        let tones: [RGBA] = [RGBA(hex: 0x8A8580), RGBA(hex: 0x6F6A66), RGBA(hex: 0x9C958C), RGBA(hex: 0x7A6E62), RGBA(hex: 0xA8A29A)]
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, id) = n.voronoi(u, v, cells: 9)
            if d2 - d1 < 0.12 { return RGBA(hex: 0x4A4644) }
            var col = tones[Int(id % UInt64(tones.count))]
            if d1 < 0.2 { col = col.lighten(0.12) }
            return col
        }
        return c
    }

    static func paintPlanks(_ seed: UInt64 = 8, palette: Palette = planks) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        let boardH = 8
        c.fill { x, y in
            let board = y / boardH
            let offset = board % 2 == 0 ? 0 : 13
            let (u, v) = uv(x, y)
            let grain = n.value((u * 0.25) + Double(board) * 0.37, v * 3, period: 12)
            var col = palette.step(0.35 + grain * 0.55 + Double(board % 2) * 0.05)
            if y % boardH == boardH - 1 { col = palette.colors[0].shade(0.85) }
            else if y % boardH == 0 { col = col.lighten(0.08) }
            if (x + offset) % S == 0 || (x + offset) % S == 31 { col = palette.colors[0] }
            if ((x + offset + 3) % S == 0 || (x + offset + 28) % S == 0) && y % boardH == 3 { col = RGBA(hex: 0x3A2A1C) } // pegs
            return col
        }
        return c
    }

    static func paintLogSide(_ seed: UInt64 = 9, palette: Palette = bark) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed), m = noise(seed + 3)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let fibre = n.value(u, v * 0.125, period: 16)
            var col = palette.step(fibre * 0.9 + m.fbm(u, v, period: 2, octaves: 2) * 0.2)
            let groove = n.value(u + 0.13, v * 0.25 + 0.4, period: 8)
            if groove > 0.7 { col = palette.colors[0] }
            return col
        }
        return c
    }

    static func paintLogTop(_ seed: UInt64 = 10, bark barkPalette: Palette = bark, core: [UInt32] = [0xD2A86A, 0xB88A50, 0xA87B45]) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        let ringA = RGBA(hex: core[0]), ringB = RGBA(hex: core[1]), ringC = RGBA(hex: core[2])
        c.fill { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let edge = max(abs(dx), abs(dy))
            if edge > 13.5 { return barkPalette.step(hash01(seed, x, y) * 0.8) }
            let (u, v) = uv(x, y)
            let r = sqrt(dx * dx + dy * dy) + n.value(u, v, period: 6) * 1.6
            let ring = Int(r) % 4
            return ring == 0 ? ringC : (ring == 1 ? ringB : ringA)
        }
        return c
    }

    static func paintLeaves(_ seed: UInt64, palette: Palette, coverage: Double) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed), m = noise(seed + 2)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let density = n.fbm(u, v, period: 6, octaves: 3)
            let h = hash01(seed, x, y)
            guard density + (h - 0.5) * 0.35 > 1 - coverage else { return .clear }
            var col = palette.step(m.fbm(u, v, period: 5, octaves: 2) * 0.95)
            if h > 0.9 { col = palette.colors[palette.colors.count - 1] }
            if h < 0.1 { col = palette.colors[0] }
            return col
        }
        return c
    }

    static func paintWater(_ seed: UInt64 = 12) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let w = n.fbm(u, v, period: 4, octaves: 3)
            let ripple = sin((v + w * 0.4) * .pi * 8)
            var col = RGBA(hex: 0x2A64B8).mix(RGBA(hex: 0x3A82D4), w)
            if ripple > 0.82 { col = col.lighten(0.25) }
            return col.withAlpha(0.78)
        }
        return c
    }

    static func paintOre(_ seed: UInt64, base: Canvas, colors: [UInt32], blobs: Int, size: Double, glow: Bool = false) -> Canvas {
        let c = base
        var rng = SplitMix64(seed: seed)
        let main = RGBA(hex: colors[0]), dark = RGBA(hex: colors[1]), light = RGBA(hex: colors[2])
        for _ in 0..<blobs {
            let cx = Double(rng.nextInt(S)), cy = Double(rng.nextInt(S))
            let pieces = 3 + rng.nextInt(3)
            for _ in 0..<pieces {
                let px = cx + Double(rng.nextInt(7)) - 3, py = cy + Double(rng.nextInt(7)) - 3
                let r = size * (0.7 + rng.nextDouble() * 0.5)
                for yy in Int(py - r - 1)...Int(py + r + 1) {
                    for xx in Int(px - r - 1)...Int(px + r + 1) {
                        let dx = Double(xx) + 0.5 - px, dy = Double(yy) + 0.5 - py
                        let d = sqrt(dx * dx + dy * dy)
                        if d <= r {
                            var col = main
                            if dx + dy < -r * 0.5 { col = light } else if dx + dy > r * 0.6 { col = dark }
                            c[xx, yy] = col
                        } else if d <= r + 0.9 && glow {
                            c[xx, yy] = c[xx, yy].mix(main, 0.35)
                        }
                    }
                }
            }
        }
        return c
    }

    static func paintBedrock(_ seed: UInt64 = 13) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, id) = n.voronoi(u, v, cells: 6)
            let t = Double(id % 100) / 100 * 0.7 + (d2 - d1) * 0.6
            return bedrock.step(t)
        }
        return c
    }

    static func paintGlass() -> Canvas {
        let c = Canvas(S)
        let frame = RGBA(hex: 0xC9DDE6), frameDark = RGBA(hex: 0x8FAAB6)
        for i in 0..<S {
            c[i, 0] = frame; c[0, i] = frame; c[i, S - 1] = frameDark; c[S - 1, i] = frameDark
        }
        for i in 0..<9 {
            c[6 + i, 5 + i] = RGBA(hex: 0xEAF6FA, alpha: 0.85)
            c[7 + i, 5 + i] = RGBA(hex: 0xEAF6FA, alpha: 0.5)
            if i < 5 { c[19 + i, 18 + i] = RGBA(hex: 0xEAF6FA, alpha: 0.7) }
        }
        return c
    }

    static func paintSandstoneSide(_ seed: UInt64 = 14) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let band = Int((Double(y) + n.value(u, v, period: 4) * 3)) / 5
            var col = sandstone.step(0.15 + Double(band % 4) * 0.22 + (hash01(seed, x, y) - 0.5) * 0.08)
            if y < 3 { col = sandstone.colors[4] }
            if y == 3 || y == S - 1 { col = sandstone.colors[0] }
            return col
        }
        return c
    }

    static func paintStoneBricks(_ seed: UInt64 = 15) -> Canvas {
        let base = paintStone(seed)
        let mortar = RGBA(hex: 0x4A4B52)
        for y in 0..<S {
            for x in 0..<S {
                let row = y / 8
                let off = row % 2 == 0 ? 0 : 8
                if y % 8 == 7 || (x + off) % 16 == 15 { base[x, y] = mortar }
                else if y % 8 == 0 || (x + off) % 16 == 0 { base[x, y] = base[x, y].lighten(0.12) }
                else { base[x, y] = base[x, y].lighten(0.05) }
            }
        }
        return base
    }

    static func paintIce(_ seed: UInt64 = 16) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let (d1, d2, _) = n.voronoi(u, v, cells: 3)
            if d2 - d1 < 0.04 { return RGBA(hex: 0xE8F6FF, alpha: 0.9) }
            return RGBA(hex: 0x8CC4EE).mix(RGBA(hex: 0xB6DCF6), n.fbm(u, v, period: 3, octaves: 2)).withAlpha(0.72)
        }
        return c
    }

    static func paintSnow(_ seed: UInt64 = 17) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = snow.ramp(n.fbm(u, v, period: 4, octaves: 3) * 0.7 + 0.3)
            if hash01(seed, x, y) > 0.95 { col = RGBA(hex: 0xFFFFFF) }
            return col
        }
        return c
    }

    static func paintSnowySide(_ seed: UInt64 = 18) -> Canvas {
        let c = paintDirt(seed)
        let n = noise(seed + 1)
        for x in 0..<S {
            let depth = 6 + Int(n.value((Double(x) + 0.5) / Double(S), 0.5, period: 8) * 7)
            for y in 0..<depth {
                c[x, y] = y == depth - 1 ? snow.colors[0].shade(0.9) : snow.step(0.5 + hash01(seed, x, y) * 0.5)
            }
        }
        return c
    }

    static func paintSimple(_ seed: UInt64, palette: Palette, period: Int = 4, specks: Double = 0.05) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            var col = palette.step(n.fbm(u, v, period: period, octaves: 3) * 0.9 + 0.05)
            let h = hash01(seed, x, y)
            if h > 1 - specks { col = col.lighten(0.15) } else if h < specks { col = col.shade(0.85) }
            return col
        }
        return c
    }

    static func paintMud(_ seed: UInt64 = 19) -> Canvas {
        let c = paintSimple(seed, palette: mud, period: 3, specks: 0.03)
        let n = noise(seed + 4)
        for y in 0..<S { for x in 0..<S {
            let (u, v) = uv(x, y)
            if n.value(u, v, period: 6) > 0.78 { c[x, y] = RGBA(hex: 0x6E5A48) }   // wet sheen
        } }
        return c
    }

    static func paintBoneSide(_ seed: UInt64 = 20) -> Canvas {
        let c = Canvas(S)
        let n = noise(seed)
        c.fill { x, y in
            let (u, v) = uv(x, y)
            let ridge = (x % 8 == 0 || x % 8 == 7) ? 0.1 : 0.55
            return bone.step(ridge + n.value(u, v * 0.25, period: 8) * 0.4)
        }
        return c
    }

    static func paintBoneTop(_ seed: UInt64 = 21) -> Canvas {
        let c = Canvas(S)
        c.fill { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let r = sqrt(dx * dx + dy * dy)
            if r < 5 { return RGBA(hex: 0x9C8E70) }
            if r < 7 { return bone.colors[1] }
            if max(abs(dx), abs(dy)) > 14 { return bone.colors[0] }
            return bone.step(0.55 + hash01(seed, x, y) * 0.4)
        }
        return c
    }

    static func paintFossil(_ seed: UInt64 = 22) -> Canvas {
        let c = paintStone(seed)
        let boneCol = RGBA(hex: 0xE6DCC0), shade = RGBA(hex: 0xB8AB8A)
        // Spine
        for x in 3..<29 {
            let y = 12 + Int(sin(Double(x) / 5) * 2)
            c[x, y] = boneCol; c[x, y + 1] = shade
            if x % 4 == 0 {
                // Ribs curving down
                for k in 1..<8 {
                    let rx = x + k / 3, ry = y + 1 + k
                    c[rx, ry] = k % 2 == 0 ? boneCol : shade
                }
            }
        }
        // Skull
        for yy in 8..<13 { for xx in 26..<31 { c[xx, yy] = (xx + yy) % 3 == 0 ? shade : boneCol } }
        c[28, 10] = RGBA(hex: 0x3A3A40)
        return c
    }

    static func paintAmberLantern(_ seed: UInt64 = 23) -> Canvas {
        let c = Canvas(S)
        let frame = RGBA(hex: 0x4A3322), frameLight = RGBA(hex: 0x6E4C32)
        c.fill { x, y in
            let edge = min(x, y, S - 1 - x, S - 1 - y)
            if edge < 3 { return edge == 0 ? frame.shade(0.7) : (edge == 1 ? frameLight : frame) }
            if x == 15 || x == 16 || y == 15 || y == 16 { return frame }
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let r = sqrt(dx * dx + dy * dy) / 16
            return RGBA(hex: 0xFFE9A8).mix(RGBA(hex: 0xF08C1A), min(1, r * 1.4)).mix(RGBA(hex: 0xFFFFFF), hash01(seed, x, y) > 0.96 ? 0.5 : 0)
        }
        return c
    }

    static func paintCraftingTop() -> Canvas {
        let c = paintPlanks(30)
        let dark = RGBA(hex: 0x5A3C22)
        for i in 2..<30 { c[i, 2] = dark; c[i, 29] = dark; c[2, i] = dark; c[29, i] = dark }
        for i in 3..<29 { c[i, 11] = dark.shade(1.1); c[i, 20] = dark.shade(1.1); c[11, i] = dark.shade(1.1); c[20, i] = dark.shade(1.1) }
        // Tiny bone chisel on the bench surface
        for k in 0..<8 { c[5 + k, 5 + k] = RGBA(hex: 0xE6DCC0) }
        c[4, 4] = RGBA(hex: 0xC9BD9E); c[13, 13] = RGBA(hex: 0x8A8D97)
        return c
    }

    static func paintCraftingSide(front: Bool) -> Canvas {
        let c = paintPlanks(front ? 31 : 32)
        let top = RGBA(hex: 0x5A3C22)
        for y in 0..<6 { for x in 0..<S { c[x, y] = y == 5 ? top : planks.step(0.8 + hash01(9, x, y) * 0.2) } }
        if front {
            // Hanging saw & mallet silhouettes
            let metal = RGBA(hex: 0xA8ADB6), handle = RGBA(hex: 0x4A3322)
            for x in 6..<15 { for y in 10..<14 { c[x, y] = (x + y) % 2 == 0 ? metal : metal.shade(0.85) } }
            for y in 10..<15 { c[5, y] = handle }
            for y in 9..<24 { c[22, y] = handle }
            for x in 19..<26 { for y in 8..<12 { c[x, y] = RGBA(hex: 0x8A8D97) } }
        } else {
            for x in 4..<28 { c[x, 18] = top.shade(1.2) }
        }
        return c
    }

    // MARK: Plants (cutout sprites)

    static func paintTallGrass(_ seed: UInt64 = 40) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: seed)
        for _ in 0..<14 {
            let x0 = Double(3 + rng.nextInt(26))
            let height = 12 + Double(rng.nextInt(16))
            let lean = (rng.nextDouble() - 0.5) * 8
            let shade = rng.nextDouble()
            c.line(x0, 32, x0 + lean, 32 - height, width: 1.6) { t in
                grass.ramp(0.2 + t * 0.7 + shade * 0.15)
            }
        }
        return c
    }

    static func paintFern(_ seed: UInt64 = 41) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: seed)
        let fronds: [(Double, Double)] = [(-14, -20), (14, -20), (-8, -28), (8, -28), (0, -30), (-16, -8), (16, -8)]
        for (fx, fy) in fronds {
            let ex = 16 + fx, ey = 32 + fy
            c.line(16, 31, ex, ey, width: 1.3) { t in ginkgo.ramp(0.1 + t * 0.5) }
            for k in 1..<7 {
                let t = Double(k) / 7
                let px = 16 + fx * t, py = 31 + (fy - 1) * t
                let side = 3.5 * (1 - t)
                c.line(px, py, px - fy / 30 * side * 2, py + fx / 30 * side * 2 - side, width: 1.1) { _ in ginkgo.ramp(0.45 + rng.nextDouble() * 0.4) }
                c.line(px, py, px + fy / 30 * side * 2, py - fx / 30 * side * 2 - side, width: 1.1) { _ in ginkgo.ramp(0.35 + rng.nextDouble() * 0.4) }
            }
        }
        return c
    }

    static func paintFlower(petals: [UInt32], center: UInt32, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        c.line(16, 32, 15, 13, width: 1.8) { t in grass.ramp(0.3 + t * 0.3) }
        c.line(15.5, 24, 10, 19, width: 1.6) { _ in grass.colors[2] }
        c.line(15.5, 27, 21, 22, width: 1.6) { _ in grass.colors[3] }
        let p = petals.map { RGBA(hex: $0) }
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi + Double(seed % 3)
            c.disc(15 + cos(a) * 4.2, 10 + sin(a) * 4.2, 3.0, p[k % p.count])
        }
        c.disc(15, 10, 2.2, RGBA(hex: center))
        c.outline(RGBA(hex: 0x1E3A16, alpha: 0.6))
        return c
    }

    static func paintDeadBush(_ seed: UInt64 = 43) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: seed)
        let twig = RGBA(hex: 0x7A5230)
        func branch(_ x: Double, _ y: Double, _ angle: Double, _ len: Double, _ depth: Int) {
            let ex = x + cos(angle) * len, ey = y - sin(angle) * len
            c.line(x, y, ex, ey, width: depth > 1 ? 1.5 : 1.1) { _ in twig.shade(0.8 + Double(depth) * 0.08) }
            guard depth > 0 else { return }
            branch(ex, ey, angle + 0.5 + rng.nextDouble() * 0.3, len * 0.65, depth - 1)
            branch(ex, ey, angle - 0.5 - rng.nextDouble() * 0.3, len * 0.65, depth - 1)
        }
        branch(16, 32, .pi / 2, 10, 3)
        return c
    }

    static func paintTorch() -> Canvas {
        let c = Canvas(S)
        // Stick column x 14..17, y 16..31 (UV region 7..9 × 6..16 in 1/16 units)
        for y in 16..<32 {
            for x in 14..<18 {
                c[x, y] = RGBA(hex: x < 16 ? 0x8A6242 : 0x6A4630).shade(y % 5 == 0 ? 0.85 : 1)
            }
        }
        // Flame & amber ember cap y 12..15
        let flame: [[UInt32]] = [
            [0xFFF3B0, 0xFFE070, 0xFFE070, 0xFFF3B0],
            [0xFFD050, 0xFFB030, 0xFFB030, 0xFFD050],
            [0xF89020, 0xFF7A18, 0xFF7A18, 0xF89020],
            [0x6A4630, 0xE0701A, 0xE0701A, 0x6A4630],
        ]
        for (dy, row) in flame.enumerated() { for (dx, hex) in row.enumerated() { c[14 + dx, 12 + dy] = RGBA(hex: hex) } }
        return c
    }

    static func paintCrack(stage: Int) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: 999)
        let lines = 2 + stage * 3
        for i in 0..<lines {
            var x = 16.0 + Double(rng.nextInt(9)) - 4, y = 16.0 + Double(rng.nextInt(9)) - 4
            let angle = Double(i) / Double(lines) * 2 * .pi + rng.nextDouble()
            let len = 3 + Double(stage) * 1.6
            for _ in 0..<Int(len) {
                let nx = x + cos(angle) * 1.4 + (rng.nextDouble() - 0.5), ny = y + sin(angle) * 1.4 + (rng.nextDouble() - 0.5)
                c.line(x, y, nx, ny, width: 1.0) { _ in RGBA(0.05, 0.05, 0.05, 0.75) }
                x = nx; y = ny
            }
        }
        return c
    }

    // MARK: Items

    static func paintItem(_ name: String) -> Canvas {
        let c = Canvas(S)
        let wood = RGBA(hex: 0x8A6242), woodDark = RGBA(hex: 0x5C3E26)
        func stick(_ c: Canvas, from: (Double, Double) = (6, 27), to: (Double, Double) = (22, 11)) {
            c.line(from.0, from.1, to.0, to.1, width: 3) { t in wood.mix(woodDark, t * 0.4) }
        }
        let materials: [String: (RGBA, RGBA, RGBA)] = [
            "wooden": (RGBA(hex: 0xC48D54), RGBA(hex: 0x8F6236), RGBA(hex: 0xE0AE72)),
            "stone": (RGBA(hex: 0x8A8D97), RGBA(hex: 0x5C5E66), RGBA(hex: 0xB0B3BC)),
            "iron": (RGBA(hex: 0xD8DCE2), RGBA(hex: 0x9098A4), RGBA(hex: 0xFFFFFF)),
            "diamond": (RGBA(hex: 0x5DF2E6), RGBA(hex: 0x1FA8A0), RGBA(hex: 0xD8FFFB)),
        ]

        switch name {
        case "stick":
            stick(c, from: (7, 26), to: (25, 6))
        case "coal":
            c.disc(15, 17, 8, RGBA(hex: 0x24242A)); c.disc(19, 13, 5, RGBA(hex: 0x2E2E36))
            c.disc(12, 13, 2, RGBA(hex: 0x5A5A66)); c.disc(19, 20, 1.5, RGBA(hex: 0x44444E))
        case "flint":
            for y in 6..<27 { for x in 8..<26 where abs(Double(x) - 16) < Double(y - 5) * 0.45 {
                c.plot(x, y, (x + y) % 5 == 0 ? RGBA(hex: 0x5C5E66) : RGBA(hex: 0x33343A))
            } }
        case "iron_ingot", "gold_ingot":
            let (m, d, l) = name == "iron_ingot"
                ? (RGBA(hex: 0xD8DCE2), RGBA(hex: 0x8A919C), RGBA(hex: 0xFFFFFF))
                : (RGBA(hex: 0xF6C94A), RGBA(hex: 0xB8861C), RGBA(hex: 0xFFF0A0))
            for y in 11..<22 {
                let inset = (21 - y) / 3
                for x in (5 + inset)..<(27 - inset) {
                    c.plot(x, y, y < 13 ? l : (y > 19 ? d : m))
                }
            }
        case "diamond":
            let m = RGBA(hex: 0x5DF2E6), d = RGBA(hex: 0x1FA8A0), l = RGBA(hex: 0xD8FFFB)
            for y in 7..<27 { for x in 4..<28 {
                let top = y < 13
                let w = top ? Double(y - 7) * 1.4 + 6 : Double(27 - y) * 0.85
                if abs(Double(x) - 15.5) < w { c.plot(x, y, top ? (x < 16 ? l : m) : (x < 16 ? m : d)) }
            } }
        case "amber":
            c.disc(16, 18, 8, RGBA(hex: 0xE48418)); c.disc(16, 11, 5, RGBA(hex: 0xF29A22))
            c.disc(13, 14, 2.5, RGBA(hex: 0xFFD27A))
            c.plot(18, 19, RGBA(hex: 0x3A2210)); c.plot(19, 19, RGBA(hex: 0x3A2210)); c.plot(18, 20, RGBA(hex: 0x3A2210))
        case "dino_bone":
            let b = RGBA(hex: 0xE6DCC0), s = RGBA(hex: 0xB8AB8A)
            c.line(9, 23, 23, 9, width: 4) { _ in b }
            for (x, y) in [(7.0, 22.0), (10.0, 25.0), (22.0, 7.0), (25.0, 10.0)] { c.disc(x, y, 3.2, b) }
            c.line(10, 24, 24, 10, width: 1.2) { _ in s }
        case "berries":
            c.line(16, 6, 16, 12, width: 1.5) { _ in RGBA(hex: 0x3F7A22) }
            c.disc(20, 8, 3, RGBA(hex: 0x5A9A2C))
            for (x, y) in [(11.0, 17.0), (20.0, 17.0), (15.5, 23.0)] {
                c.disc(x, y, 5, RGBA(hex: 0xB0203A)); c.disc(x - 1.5, y - 1.5, 1.4, RGBA(hex: 0xFF8A9A))
            }
        case "trail_mix":
            for y in 10..<28 { for x in 7..<25 { c.plot(x, y, RGBA(hex: 0xA8784A).shade(y < 13 ? 0.8 : 1)) } }
            for (x, y) in [(10, 15), (14, 19), (19, 14), (21, 22), (12, 24), (17, 25)] {
                c.disc(Double(x), Double(y), 1.5, [RGBA(hex: 0xB0203A), RGBA(hex: 0xF6C94A), RGBA(hex: 0x5A9A2C)][(x + y) % 3])
            }
            c.line(7, 10, 25, 10, width: 1.5) { _ in RGBA(hex: 0x6A4630) }
        case "bone_club":
            stick(c, from: (7, 27), to: (17, 15))
            c.line(15, 17, 25, 7, width: 6) { _ in RGBA(hex: 0xE6DCC0) }
            c.disc(25, 7, 4, RGBA(hex: 0xD9CEB2)); c.disc(22, 5, 2.5, RGBA(hex: 0xF2EBD6))
        default:
            if let special = NewTextures.item(name) { return special }
            if name.hasSuffix("_pickaxe"), let pick = BetterTextures.pickaxe(String(name.dropLast("_pickaxe".count))) { return pick }
            if name.hasSuffix("_axe"), !name.hasSuffix("_pickaxe"), let axe = BetterTextures.axe(String(name.dropLast("_axe".count))) { return axe }
            if name.hasSuffix("_sword"), let sword = BetterTextures.sword(String(name.dropLast("_sword".count))) { return sword }
            let parts = name.split(separator: "_")
            guard parts.count == 2, let mat = materials[String(parts[0])] else {
                c.disc(16, 16, 10, RGBA(hex: 0xFF00FF))   // missing-texture magenta
                return c
            }
            let (m, d, l) = mat
            switch parts[1] {
            case "pickaxe":
                stick(c, from: (8, 28), to: (22, 10))
                for k in 0..<22 {
                    let t = Double(k) / 21
                    let a = .pi * (0.15 + 0.7 * t)
                    let x = 18 + cos(a + .pi / 4) * 13, y = 14 - sin(a + .pi / 4) * 13 + 8
                    c.disc(x, y - 4, 1.9, t < 0.5 ? l.mix(m, t * 2) : m.mix(d, (t - 0.5) * 2))
                }
            case "axe":
                stick(c, from: (8, 28), to: (21, 8))
                for y in 5..<18 { for x in 17..<28 where Double(x - 17) + abs(Double(y) - 11) * 0.4 < 10 {
                    c.plot(x, y, x > 24 ? l : (y > 13 ? d : m))
                } }
            case "shovel":
                stick(c, from: (7, 27), to: (19, 13))
                c.disc(22, 10, 5.5, m); c.disc(24, 8, 3, l); c.disc(20, 13, 2.5, d)
            case "hoe":
                stick(c, from: (8, 28), to: (22, 8))
                c.line(14, 8, 25, 8, width: 3.5) { t in m.mix(l, t * 0.6) }
                c.line(14, 7, 16, 13, width: 3) { _ in d }
            case "sword":
                c.line(7, 25, 25, 7, width: 3.5) { t in l.mix(m, 0.4 + t * 0.3) }
                c.line(8, 24, 24, 8, width: 1) { _ in l }
                c.line(6, 20, 12, 26, width: 2.5) { _ in d }
                c.line(4, 28, 8, 24, width: 2.5) { _ in wood }
            default:
                c.disc(16, 16, 10, RGBA(hex: 0xFF00FF))
            }
        }
        c.outline()
        return c
    }

    // MARK: Registry

    static func blockTextures() -> [String: Canvas] {
        var t: [String: Canvas] = [:]
        t["stone"] = paintStone()
        t["dirt"] = paintDirt()
        t["grass_top"] = paintGrassTop()
        t["grass_side"] = paintGrassSide()
        t["cobblestone"] = paintCobble()
        t["mossy_cobblestone"] = paintCobble(6, moss: true)
        t["planks"] = paintPlanks()
        t["sand"] = paintSand()
        t["gravel"] = paintGravel()
        t["log_side"] = paintLogSide()
        t["log_top"] = paintLogTop()
        t["redwood_log_side"] = paintLogSide(33, palette: redBark)
        t["redwood_log_top"] = paintLogTop(34, bark: redBark, core: [0xC8764A, 0xA85A36, 0x94482A])
        t["leaves"] = paintLeaves(11, palette: ginkgo, coverage: 0.72)
        t["redwood_needles"] = paintLeaves(35, palette: needles, coverage: 0.82)
        t["water"] = paintWater()
        t["coal_ore"] = paintOre(50, base: paintStone(51), colors: [0x26262C, 0x121216, 0x4A4A55], blobs: 4, size: 1.6)
        t["iron_ore"] = paintOre(52, base: paintStone(53), colors: [0xD6A488, 0xA87254, 0xF0CDB4], blobs: 4, size: 1.5)
        t["gold_ore"] = paintOre(54, base: paintStone(55), colors: [0xF6C94A, 0xC8961F, 0xFFF0A0], blobs: 4, size: 1.4)
        t["diamond_ore"] = paintOre(56, base: paintStone(57), colors: [0x5DF2E6, 0x1FA8A0, 0xD8FFFB], blobs: 3, size: 1.5)
        t["amber_ore"] = paintOre(58, base: paintStone(59), colors: [0xF29A22, 0xB45E0E, 0xFFD27A], blobs: 3, size: 1.8, glow: true)
        t["fossil_stone"] = paintFossil()
        t["bedrock"] = paintBedrock()
        t["glass"] = paintGlass()
        t["sandstone_side"] = paintSandstoneSide()
        t["sandstone_top"] = paintSand(60, palette: sandstone)
        t["crafting_bench_top"] = paintCraftingTop()
        t["crafting_bench_side"] = paintCraftingSide(front: false)
        t["crafting_bench_front"] = paintCraftingSide(front: true)
        t["tall_grass"] = paintTallGrass()
        t["fern"] = paintFern()
        t["emberbloom"] = paintFlower(petals: [0xE8432A, 0xFF6A3A, 0xC8301E], center: 0xFFD050, seed: 1)
        t["sunpetal"] = paintFlower(petals: [0xFFD23A, 0xFFE878, 0xF0B820], center: 0x8A4A1A, seed: 2)
        t["dead_bush"] = paintDeadBush()
        t["snow"] = paintSnow()
        t["snowy_grass_side"] = paintSnowySide()
        t["clay"] = paintSimple(61, palette: clay, period: 3, specks: 0.02)
        t["ice"] = paintIce()
        t["amber_lantern"] = paintAmberLantern()
        t["torch"] = paintTorch()
        t["stone_bricks"] = paintStoneBricks()
        t["mud"] = paintMud()
        t["bone_block_side"] = paintBoneSide()
        t["bone_block_top"] = paintBoneTop()
        NewTextures.add(to: &t)
        BetterTextures.add(to: &t)
        return t
    }
}
