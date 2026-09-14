import Foundation
import DinoCraftCore

/// Textures for doors, furnaces, chests, storage blocks and building blocks.
enum MoreTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let chestWood = Palette([0x4E3018, 0x643E20, 0x7A4E2A, 0x8E5E34, 0xA06C3E])
    static let brick = Palette([0x7A2E22, 0x8E3A2A, 0xA04632, 0xB0543C, 0xBE6448])
    static let terracotta = Palette([0x8A4A30, 0x985438, 0xA45E40, 0xB06A48, 0xBA7652])

    static func add(to t: inout [String: Canvas]) {
        t["door_lower"] = door(upper: false)
        t["door_upper"] = door(upper: true)
        t["furnace_top"] = furnaceTop()
        t["furnace_side"] = furnaceSide()
        t["furnace_front"] = furnaceFront(lit: false)
        t["furnace_front_lit"] = furnaceFront(lit: true)
        t["chest_top"] = chest(face: 0)
        t["chest_side"] = chest(face: 1)
        t["chest_front"] = chest(face: 2)
        t["emerald_ore"] = T.paintOre(80, base: T.paintStone(81), colors: [0x2EDB6A, 0x138A3E, 0xA8FFC8], blobs: 3, size: 1.4)
        t["emerald_block"] = gemBlock(Palette([0x0E6A30, 0x14873E, 0x22A850, 0x3CCB6A, 0x8AF2B0]), seed: 82)
        t["diamond_block"] = gemBlock(Palette([0x137A74, 0x1FA8A0, 0x3CCBC2, 0x5DF2E6, 0xC8FFFA]), seed: 83)
        t["iron_block"] = metalBlock(Palette([0x8A919C, 0xA8AFB8, 0xC4CAD2, 0xD8DCE2, 0xF0F2F5]), seed: 84)
        t["gold_block"] = metalBlock(Palette([0xA8741A, 0xC8961F, 0xE0B232, 0xF6C94A, 0xFFE89A]), seed: 85)
        t["bricks"] = bricks()
        t["bookshelf"] = bookshelf()
        t["mossy_stone_bricks"] = mossy(T.paintStoneBricks(86))
        t["terracotta"] = T.paintSimple(87, palette: terracotta, period: 3, specks: 0.03)
        t["polished_stone"] = polishedStone()
        DecorTextures.add(to: &t)
        BuildTextures.add(to: &t)
    }

    static func item(_ name: String) -> Canvas? {
        if let decor = DecorTextures.item(name) { return decor }
        if let food = FarmTextures.item(name) { return food }
        if let armor = ArmorTextures.item(name) { return armor }
        if let crop = CropTextures.item(name) { return crop }
        let c = Canvas(S)
        switch name {
        case "emerald":
            let m = RGBA(hex: 0x2EDB6A), d = RGBA(hex: 0x138A3E), l = RGBA(hex: 0xB8FFD2)
            for y in 5..<28 {
                let half = y < 16 ? Double(y - 5) * 0.8 + 3 : Double(27 - y) * 0.8 + 3
                for x in 4..<28 where abs(Double(x) - 15.5) < half {
                    c.plot(x, y, x < 13 ? l : (x > 19 || y > 22 ? d : m))
                }
            }
        case "brick":
            for y in 12..<22 {
                for x in 5..<27 {
                    let top = y < 14
                    c.plot(x, y, top ? brick.colors[4] : (y > 19 ? brick.colors[0] : brick.step(0.4 + T.hash01(9, x, y) * 0.4)))
                }
            }
        case "charcoal":
            c.disc(15, 17, 8, RGBA(hex: 0x2E2218)); c.disc(19, 13, 5, RGBA(hex: 0x3A2C20))
            c.disc(12, 13, 2, RGBA(hex: 0x6A5040)); c.line(9, 22, 21, 10, width: 1) { _ in RGBA(hex: 0x4A3828) }
        case "wooden_door":
            for y in 3..<30 {
                for x in 9..<23 {
                    let edge = x == 9 || x == 22 || y == 3 || y == 29 || y == 16
                    var col = T.planks.step(0.35 + T.hash01(4, x / 3, y) * 0.5)
                    if edge { col = T.planks.colors[0] }
                    if y > 5 && y < 14 && x > 11 && x < 20 && (x != 15 && x != 16) { col = RGBA(hex: 0xBFE8F2, alpha: 1) }
                    c.plot(x, y, col)
                }
            }
            c.plot(20, 18, RGBA(hex: 0x3A3A40)); c.plot(20, 19, RGBA(hex: 0x3A3A40))
        default:
            return nil
        }
        c.outline()
        return c
    }

    // MARK: Painters

    static func door(upper: Bool) -> Canvas {
        let c = Canvas(S)
        let frame = T.planks.colors[0].shade(0.9)
        c.fill { x, y in
            // Vertical boards with a darker frame
            var col = T.planks.step(0.3 + T.hash01(upper ? 12 : 11, x / 8, y / 3) * 0.2 + T.noise(13).value(Double(x) / 32 * 0.25 + Double(x / 8) * 0.3, Double(y) / 32 * 3, period: 12) * 0.4)
            if x % 8 == 0 { col = col.shade(0.82) }
            if x < 3 || x > 28 { col = frame }
            if upper ? y < 3 : y > 28 { col = frame }
            return col
        }
        if upper {
            // Two window panes (transparent) with mullion
            for y in 6..<24 {
                for x in 6..<26 {
                    if x == 15 || x == 16 || y == 14 || y == 15 { c[x, y] = frame }
                    else { c[x, y] = RGBA.clear }
                }
            }
            for i in 5..<27 { c[i, 5] = frame; c[i, 24] = frame }
            for i in 5..<25 { c[5, i] = frame; c[26, i] = frame }
        } else {
            // Z brace and a handle
            for i in 0..<22 {
                let x = 5 + i, y = 25 - i
                c[x, y] = frame; c[x, y + 1] = frame
            }
            for x in 3..<29 { c[x, 4] = frame; c[x, 26] = frame }
            for (x, y) in [(24, 1), (25, 1), (24, 2), (25, 2)] { c[x, y] = RGBA(hex: 0x2E2E34) }
        }
        return c
    }

    static func furnaceTop() -> Canvas {
        let c = T.paintStone(88)
        for i in 0..<S {
            c[i, 0] = c[i, 0].shade(0.75); c[i, S - 1] = c[i, S - 1].shade(0.75)
            c[0, i] = c[0, i].shade(0.75); c[S - 1, i] = c[S - 1, i].shade(0.75)
        }
        for y in 10..<22 { for x in 10..<22 { c[x, y] = c[x, y].shade(0.7) } }
        return c
    }

    static func furnaceSide() -> Canvas {
        let c = T.paintCobble(89)
        for x in 0..<S {
            for y in 0..<3 { c[x, y] = T.stone.colors[3].shade(y == 2 ? 0.8 : 1) }
            for y in (S - 3)..<S { c[x, y] = T.stone.colors[1].shade(y == S - 3 ? 1.1 : 0.9) }
        }
        return c
    }

    static func furnaceFront(lit: Bool) -> Canvas {
        let c = furnaceSide()
        // Opening
        for y in 15..<27 {
            for x in 8..<24 {
                let depth = Double(y - 15) / 12
                if lit {
                    let flicker = T.hash01(90, x, y)
                    let base = RGBA(hex: 0xFF8A1A).mix(RGBA(hex: 0xFFE070), max(0, depth - 0.2 + flicker * 0.3))
                    c[x, y] = y < 18 ? RGBA(hex: 0x3A1A0A).mix(base, Double(y - 15) / 3) : base
                } else {
                    c[x, y] = RGBA(hex: 0x141418).mix(RGBA(hex: 0x24242A), depth)
                }
            }
        }
        // Grate bars and lintel
        for x in 7..<25 { c[x, 14] = T.stone.colors[4]; c[x, 27] = T.stone.colors[0] }
        for y in 15..<27 { c[7, y] = T.stone.colors[4]; c[24, y] = T.stone.colors[0] }
        for x in stride(from: 10, to: 24, by: 4) { for y in 22..<27 { c[x, y] = RGBA(hex: 0x3A3A42) } }
        // Chimney vent
        for x in 12..<20 { for y in 6..<10 { c[x, y] = RGBA(hex: 0x1E1E24) } }
        return c
    }

    /// face: 0 top, 1 side, 2 front
    static func chest(face: Int) -> Canvas {
        let c = T.paintPlanks(face == 0 ? 91 : 92, palette: chestWood)
        let band = RGBA(hex: 0x3A3A42), bandLight = RGBA(hex: 0x6A6A74)
        for i in 0..<S {
            c[i, 1] = band; c[i, S - 2] = band; c[1, i] = band; c[S - 2, i] = band
            c[i, 0] = bandLight.shade(0.7); c[0, i] = bandLight.shade(0.7)
        }
        if face != 0 {
            // Lid seam
            for x in 0..<S { c[x, 10] = band; c[x, 11] = RGBA(hex: 0x2A1A0E) }
        }
        if face == 2 {
            // Latch
            for y in 8..<16 { for x in 13..<19 { c[x, y] = (x == 13 || x == 18 || y == 8 || y == 15) ? band : bandLight } }
            c[15, 12] = RGBA(hex: 0x141418); c[16, 12] = RGBA(hex: 0x141418)
        }
        return c
    }

    static func metalBlock(_ p: Palette, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = T.noise(seed)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            var col = p.ramp(0.45 + n.fbm(u, v, period: 4, octaves: 3) * 0.3)
            if x == 0 || y == 0 { col = p.colors[4] }
            if x == S - 1 || y == S - 1 { col = p.colors[0] }
            if x == 1 || y == 1 { col = col.lighten(0.2) }
            if x == S - 2 || y == S - 2 { col = col.shade(0.8) }
            if (x == 15 || x == 16) && y > 2 && y < S - 3 { col = col.shade(0.85) }
            return col
        }
        for (x, y) in [(4, 4), (S - 5, 4), (4, S - 5), (S - 5, S - 5)] {
            c[x, y] = p.colors[4]; c[x + 1, y + 1] = p.colors[0]
        }
        return c
    }

    static func gemBlock(_ p: Palette, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let n = T.noise(seed)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            let (d1, d2, _) = n.voronoi(u, v, cells: 4)
            var col = p.ramp(0.35 + (d2 - d1) * 0.9)
            if d2 - d1 < 0.06 { col = p.colors[0] }
            if x == 0 || y == 0 { col = p.colors[4] }
            if x == S - 1 || y == S - 1 { col = p.colors[0] }
            return col
        }
        return c
    }

    static func bricks() -> Canvas {
        let c = Canvas(S)
        let mortar = RGBA(hex: 0xB8AFA4)
        c.fill { x, y in
            let row = y / 8
            let off = row % 2 == 0 ? 0 : 8
            if y % 8 == 7 || (x + off) % 16 == 15 { return mortar.shade(0.9 + T.hash01(93, x, y) * 0.1) }
            let brickID = (x + off) / 16 + row * 7
            var col = brick.step(0.2 + T.hash01(94, brickID, row) * 0.5 + T.hash01(95, x, y) * 0.2)
            if y % 8 == 0 { col = col.lighten(0.08) }
            return col
        }
        return c
    }

    static func bookshelf() -> Canvas {
        let c = T.paintPlanks(96)
        let spines: [UInt32] = [0x8E2A2A, 0x2A5A8E, 0x3E7A34, 0xC89A2A, 0x6A3A7A, 0x7A4A2A, 0x2A7A74]
        var rng = SplitMix64(seed: 97)
        for shelf in 0..<2 {
            let top = 3 + shelf * 15, bottom = top + 11
            var x = 1
            while x < S - 2 {
                let w = 2 + rng.nextInt(2)
                let h = 8 + rng.nextInt(4)
                let col = RGBA(hex: spines[rng.nextInt(spines.count)])
                for bx in x..<min(S - 1, x + w) {
                    for by in (bottom - h)..<bottom { c[bx, by] = col.shade(bx == x ? 1.15 : 0.9) }
                    c[bx, bottom - h + 2] = col.lighten(0.4)
                }
                x += w + (rng.nextInt(5) == 0 ? 1 : 0)
            }
            for bx in 0..<S { c[bx, bottom] = T.planks.colors[0]; c[bx, top - 1] = T.planks.colors[0].shade(0.8) }
        }
        return c
    }

    static func mossy(_ base: Canvas) -> Canvas {
        let n = T.noise(98)
        for y in 0..<S {
            for x in 0..<S {
                let (u, v) = T.uv(x, y)
                let m = n.fbm(u, v, period: 3, octaves: 3)
                if m > 0.55 { base[x, y] = base[x, y].mix(T.grass.step(m), min(0.85, (m - 0.55) * 4)) }
            }
        }
        return base
    }

    static func polishedStone() -> Canvas {
        let c = Canvas(S)
        let n = T.noise(99)
        c.fill { x, y in
            let (u, v) = T.uv(x, y)
            var col = T.stone.ramp(0.55 + n.fbm(u, v, period: 2, octaves: 2) * 0.15)
            if x == 0 || y == 0 { col = T.stone.colors[4] }
            if x == S - 1 || y == S - 1 { col = T.stone.colors[1] }
            return col
        }
        return c
    }
}
