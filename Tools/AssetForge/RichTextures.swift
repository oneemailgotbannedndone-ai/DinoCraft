import Foundation
import DinoCraftCore

/// Richer everyday blocks: wood, dirt, grass, sand and bricks. Each is painted
/// from a height field lit from the top left, so surfaces have bumps, grooves and edges you can see, in the
/// same colours as before (worlds keep their look, just with more detail). Everything tiles seamlessly.
enum RichTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static let stonePal = Palette([0x4C4E55, 0x5A5C64, 0x686A73, 0x767982, 0x858891, 0x9497A0, 0xA5A8B0])
    static let mossPal = Palette([0x243E16, 0x2E5020, 0x3A6226, 0x48742E, 0x588636])
    static let dirtPal = Palette([0x4A2E1C, 0x5A3A24, 0x6A4630, 0x7A5438, 0x8A6242, 0x9A7050])
    static let grassPal = Palette([0x2C6A22, 0x357A2A, 0x438E30, 0x52A038, 0x64B242, 0x7CC24C, 0x96D45C])
    static let snowPal = Palette([0xBCCADA, 0xCBD8E6, 0xDCE6F0, 0xE9F0F7, 0xF4F8FC, 0xFFFFFF])
    static let sandPal = Palette([0xB49868, 0xC3A874, 0xD2B783, 0xDCC58E, 0xE6D19E, 0xEFDDB0])
    static let oakPlanks = Palette([0x5E3C20, 0x7E552E, 0x9A6A3C, 0xB27D48, 0xC48D54, 0xD6A066])
    static let palmPlanks = Palette([0x8A6E44, 0xA88A5A, 0xBC9E6A, 0xCCAE78, 0xDABC88, 0xE6CA98])
    static let oakBark = Palette([0x2A1C10, 0x3E2A1A, 0x523824, 0x66472E, 0x7A5638, 0x8C6644])
    static let redBark = Palette([0x361610, 0x4E2216, 0x6A2E1E, 0x843A26, 0x9C4830, 0xB0583A])
    static let palmBark = Palette([0x524028, 0x6A5238, 0x7E6444, 0x927652, 0xA68862, 0xB89A72])
    static let brickPal = Palette([0x5E2218, 0x7A2E22, 0x8E3A2A, 0xA04632, 0xB0543C, 0xBE6448, 0xCC7454])

    static func add(to t: inout [String: Canvas]) {
        let dirtCanvas = dirt()
        t["dirt"] = dirtCanvas
        t["grass_top"] = grassTop()
        t["grass_side"] = overhang(dirt: dirtCanvas, top: grassPal, seed: 931)
        t["snowy_grass_side"] = overhang(dirt: dirtCanvas, top: snowPal, seed: 932)
        t["sand"] = sand()
        t["planks"] = planks(seed: 940, palette: oakPlanks)
        t["palm_planks"] = planks(seed: 941, palette: palmPlanks)
        t["log_side"] = bark(seed: 950, palette: oakBark)
        t["redwood_log_side"] = bark(seed: 951, palette: redBark)
        t["log_top"] = logTop(seed: 960, bark: oakBark, core: Palette([0x8E6236, 0xA87B45, 0xB88A50, 0xC89A5C, 0xD2A86A, 0xE0BC80]))
        t["redwood_log_top"] = logTop(seed: 961, bark: redBark, core: Palette([0x7A3620, 0x94482A, 0xA85A36, 0xB86A42, 0xC8764A, 0xD8905E]))
        t["palm_log_top"] = logTop(seed: 962, bark: palmBark, core: Palette([0xA08660, 0xB89A72, 0xCCAE78, 0xDABC88, 0xE6CA98, 0xF0DAAE]))
        t["stone_bricks"] = stoneBricks(seed: 970)
        t["mossy_stone_bricks"] = stoneBricks(seed: 971, moss: true)
        t["cracked_stone_bricks"] = stoneBricks(seed: 972, cracked: true)
        t["bricks"] = bricks(seed: 980)
    }

    // MARK: Helpers

    @inline(__always) static func uv(_ v: Int) -> Double { (Double(v) + 0.5) / Double(S) }
    @inline(__always) static func wrap(_ v: Int) -> Int { ((v % S) + S) % S }

    /// A height value for every pixel.
    static func field(_ f: (Int, Int) -> Double) -> [Double] {
        var a = [Double](repeating: 0, count: S * S)
        for y in 0..<S { for x in 0..<S { a[y * S + x] = f(x, y) } }
        return a
    }

    /// Light from the top left on a height field: positive where a slope faces the light.
    static func relief(_ h: [Double], _ x: Int, _ y: Int) -> Double {
        h[wrap(y - 1) * S + wrap(x - 1)] - h[wrap(y + 1) * S + wrap(x + 1)]
    }

    // MARK: Earth

    /// Dirt: crumbly clods with a few pebbles and root threads.
    static func dirt(seed: UInt64 = 920) -> Canvas {
        let n = TileNoise(seed: seed), clods = TileNoise(seed: seed + 1)
        let h = field { x, y in
            let (d1, d2, _) = clods.voronoi(uv(x), uv(y), cells: 8)
            return n.fbm(uv(x), uv(y), period: 8, octaves: 3) * 0.75 + min(1, (d2 - d1) * 4) * 0.25
        }
        let c = Canvas(S)
        c.fill { x, y in
            var t = 0.22 + h[y * S + x] * 0.55 + relief(h, x, y) * 1.6
            let speck = T.hash01(seed + 2, x, y)
            if speck < 0.05 { t -= 0.18 } else if speck > 0.96 { t += 0.14 }
            return dirtPal.step(t)
        }
        // Pebbles
        for i in 0..<5 {
            let px = 2 + Int(T.hash01(seed + 3, i, 0) * 27), py = 2 + Int(T.hash01(seed + 3, i, 1) * 27)
            let grey = RGBA(hex: [0x6E6A66, 0x7E7A74, 0x8A847C][i % 3])
            c.plot(px, py, grey); c.plot(px + 1, py, grey.lighten(0.15)); c.plot(px, py + 1, grey.shade(0.75)); c.plot(px + 1, py + 1, grey.shade(0.85))
        }
        // Root threads
        for i in 0..<2 {
            var x = Double(T.hash01(seed + 4, i, 0) * 32), y = Double(T.hash01(seed + 4, i, 1) * 32)
            for step in 0..<7 {
                c[Int(x), Int(y)] = RGBA(hex: 0x3A2414)
                x += 1; y += T.hash01(seed + 5, i, step) < 0.5 ? 0 : 1
            }
        }
        return c
    }

    /// Grass seen from above: a mottled lawn with little blades catching the light.
    static func grassTop(seed: UInt64 = 930) -> Canvas {
        let n = TileNoise(seed: seed)
        let h = field { x, y in n.fbm(uv(x), uv(y), period: 4, octaves: 3) }
        let c = Canvas(S)
        c.fill { x, y in grassPal.step(0.18 + h[y * S + x] * 0.5 + relief(h, x, y) * 1.5 + (T.hash01(seed + 1, x, y) - 0.5) * 0.12) }
        for i in 0..<150 {
            let x = Int(T.hash01(seed + 2, i, 0) * 32), y = Int(T.hash01(seed + 2, i, 1) * 32)
            let length = 2 + Int(T.hash01(seed + 2, i, 2) * 2)
            let lean = T.hash01(seed + 2, i, 3) < 0.5 ? 0 : 1
            for k in 0..<length {
                let tone = 0.35 + Double(k) / Double(length) * 0.6 + h[wrap(y) * S + wrap(x)] * 0.1
                c[x + (k == length - 1 ? lean : 0), y - k] = grassPal.step(tone)
            }
            c[x, y + 1] = grassPal.step(0.05)   // a shadow at the blade's foot
        }
        return c
    }

    /// The side of a grass (or snowy) block: dirt with a ragged, dripping top layer and a shadow under it.
    static func overhang(dirt: Canvas, top p: Palette, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        c.px = dirt.px
        let n = TileNoise(seed: seed)
        for x in 0..<S {
            var depth = 3 + Int(T.hash01(seed, x, 0) * 2.5)
            if T.hash01(seed, x / 2, 1) < 0.28 { depth += 1 + Int(T.hash01(seed, x, 2) * 4) }   // drips
            for y in 0..<depth {
                let t = 0.85 - Double(y) / Double(depth) * 0.55 + (n.fbm(uv(x), uv(y), period: 8, octaves: 2) - 0.5) * 0.35
                c[x, y] = p.step(t)
            }
            c[x, depth] = c[x, depth].shade(0.62)
            c[x, depth + 1] = c[x, depth + 1].shade(0.82)
        }
        return c
    }

    /// Sand: fine grains in soft wind ripples, with the odd shell fleck.
    static func sand(seed: UInt64 = 925) -> Canvas {
        let n = TileNoise(seed: seed), w = TileNoise(seed: seed + 1)
        let c = Canvas(S)
        c.fill { x, y in
            let ripple = sin((Double(y) + w.fbm(uv(x), uv(y), period: 2, octaves: 2) * 7) * 2 * .pi / 8) * 0.1
            var t = 0.3 + n.fbm(uv(x), uv(y), period: 8, octaves: 3) * 0.45 + ripple
            let speck = T.hash01(seed + 2, x, y)
            if speck < 0.05 { t -= 0.22 } else if speck > 0.965 { t += 0.25 }
            return sandPal.step(t)
        }
        return c
    }

    // MARK: Wood

    /// Planks: four boards with wavy grain, a knot or two, lit top edges, dark seams and nail heads.
    static func planks(seed: UInt64, palette p: Palette) -> Canvas {
        let n = TileNoise(seed: seed)
        let c = Canvas(S)
        let boardH = 8
        for y in 0..<S {
            for x in 0..<S {
                let board = y / boardH, yy = y % boardH
                let joint = Int(T.hash01(seed, board, 0) * 32)
                let local = wrap(x - joint)
                let tone = (T.hash01(seed, board, 1) - 0.5) * 0.18
                let grain = sin((Double(yy) + n.fbm(uv(x), uv(y), period: 2, octaves: 3) * 4) * 2.2 + Double(board) * 1.7) * 0.12
                var t = 0.52 + tone + grain + (T.hash01(seed + 3, x / 3, y) - 0.5) * 0.08
                if yy == 0 { t += 0.2 }
                if yy == boardH - 2 { t -= 0.12 }
                if yy == boardH - 1 { t = 0.02 }
                if local == 0 && yy < boardH - 1 { t = 0.08 }
                if local == 1 && yy < boardH - 1 { t += 0.14 }
                c.plot(x, y, p.step(t))
            }
        }
        // Knots
        for i in 0..<2 {
            let kx = 4 + Int(T.hash01(seed + 4, i, 0) * 24), board = Int(T.hash01(seed + 4, i, 1) * 4)
            let ky = board * boardH + 3
            c[kx, ky] = p.colors[0]; c[kx + 1, ky] = p.colors[1]; c[kx - 1, ky] = p.colors[2]
            c[kx, ky - 1] = p.colors[2]; c[kx, ky + 1] = p.colors[2]
        }
        // Nail heads beside each joint
        for board in 0..<4 {
            let joint = Int(T.hash01(seed, board, 0) * 32)
            for dx in [-2, 2] {
                let x = joint + dx, y = board * boardH + 3
                c[x, y] = RGBA(hex: 0x2E2A26); c[x, y + 1] = RGBA(hex: 0x4A4640); c[x + 1, y] = RGBA(hex: 0x8A847C)
            }
        }
        return c
    }

    /// Bark: deep vertical furrows between raised ridges, broken by little cross-cracks.
    static func bark(seed: UInt64, palette p: Palette) -> Canvas {
        let n = TileNoise(seed: seed), m = TileNoise(seed: seed + 1)
        let h = field { x, y in
            let warp = n.fbm(uv(x), uv(y), period: 2, octaves: 3)
            let ridge = abs(sin((Double(x) + warp * 7) * .pi / 5.333))   // 6 ridges across the tile
            return pow(ridge, 0.6) * 0.8 + m.fbm(uv(x), uv(y), period: 8, octaves: 2) * 0.2
        }
        let c = Canvas(S)
        c.fill { x, y in
            var t = 0.06 + h[y * S + x] * 0.72 + relief(h, x, y) * 2.2
            if T.hash01(seed + 2, x / 3, y) < 0.05 { t -= 0.25 }   // cross-cracks in the ridges
            return p.step(t)
        }
        return c
    }

    /// The cut end of a log: growth rings (a little wobbly), darker heartwood, a radial crack and bark round the edge.
    static func logTop(seed: UInt64, bark b: Palette, core p: Palette) -> Canvas {
        let n = TileNoise(seed: seed)
        let crackAngle = T.hash01(seed, 0, 0) * 2 * .pi
        let c = Canvas(S)
        c.fill { x, y in
            let dx = Double(x) - 15.5, dy = Double(y) - 15.5
            let edge = max(abs(dx), abs(dy))
            if edge > 13.5 {
                // Bark rim, darker on the very outside
                return b.step(0.2 + (edge > 14.5 ? 0 : 0.3) + n.fbm(uv(x), uv(y), period: 8, octaves: 2) * 0.4)
            }
            let r = sqrt(dx * dx + dy * dy) + (n.fbm(uv(x), uv(y), period: 4, octaves: 2) - 0.5) * 1.6
            let ring = (r / 2.2).truncatingRemainder(dividingBy: 1)
            var t = 0.4 + min(0.3, r / 45) + (ring < 0.35 ? -0.32 : 0) + (T.hash01(seed + 1, x, y) - 0.5) * 0.06
            if edge > 12.5 { t += 0.12 }                                  // light sapwood under the bark
            if r < 2.5 { t -= 0.15 }                                      // pith
            return p.step(t)
        }
        // A drying crack running out from the centre
        let dark = p.colors[0]
        for k in 3..<11 {
            let x = Int((15.5 + cos(crackAngle) * Double(k)).rounded(.down)), y = Int((15.5 + sin(crackAngle) * Double(k)).rounded(.down))
            c.plot(x, y, dark)
        }
        return c
    }

    // MARK: Masonry

    /// Stone bricks: two courses of bevelled blocks with recessed mortar; optionally mossy or cracked.
    static func stoneBricks(seed: UInt64, moss: Bool = false, cracked: Bool = false) -> Canvas {
        let n = TileNoise(seed: seed), g = TileNoise(seed: seed + 1)
        let c = Canvas(S)
        for y in 0..<S {
            for x in 0..<S {
                let row = y / 16, by = y % 16
                let bx = wrap(x + (row % 2) * 8) % 16
                let brick = (wrap(x + (row % 2) * 8) / 16) + row * 2
                if by == 15 || bx == 15 { c.plot(x, y, stonePal.colors[0]); continue }
                let tone = (T.hash01(seed, brick, 0) - 0.5) * 0.15
                var t = 0.35 + tone + n.fbm(uv(x), uv(y), period: 4, octaves: 3) * 0.35
                if by == 0 || bx == 0 { t += 0.22 }
                if by == 14 || bx == 14 { t -= 0.2 }
                if T.hash01(seed + 2, x, y) < 0.04 { t -= 0.15 }
                c.plot(x, y, stonePal.step(t))
            }
        }
        if moss {
            for y in 0..<S {
                for x in 0..<S {
                    let growth = g.fbm(uv(x), uv(y), period: 4, octaves: 3)
                    let mortar = y % 16 == 15 || wrap(x + (y / 16 % 2) * 8) % 16 == 15
                    if growth > (mortar ? 0.48 : 0.66) || (y % 16 >= 13 && growth > 0.58) {
                        c[x, y] = mossPal.step(0.2 + (growth - 0.4) * 1.8 + T.hash01(seed + 3, x, y) * 0.2)
                    }
                }
            }
        }
        if cracked {
            for i in 0..<3 {
                var x = Double(T.hash01(seed + 4, i, 0) * 32), y = Double(T.hash01(seed + 4, i, 1) * 32)
                for step in 0..<9 {
                    c[Int(x), Int(y)] = stonePal.colors[0]
                    c[Int(x) + 1, Int(y)] = c[Int(x) + 1, Int(y)].shade(0.82)
                    x += T.hash01(seed + 5, i, step) < 0.5 ? 1 : -1
                    y += 1
                }
            }
        }
        return c
    }

    /// Clay bricks: four courses of bricks in slightly different reds, pale mortar and a speckled surface.
    static func bricks(seed: UInt64) -> Canvas {
        let n = TileNoise(seed: seed)
        let mortar = Palette([0x8E867C, 0xA49C92, 0xB8AFA4, 0xC8C0B6])
        let c = Canvas(S)
        for y in 0..<S {
            for x in 0..<S {
                let row = y / 8, by = y % 8
                let shifted = wrap(x + (row % 2) * 8)
                let bx = shifted % 16, brick = shifted / 16 + row * 2
                if by == 7 || bx == 15 {
                    c.plot(x, y, mortar.step(0.35 + T.hash01(seed + 1, x, y) * 0.5))
                    continue
                }
                let tone = (T.hash01(seed, brick, 0) - 0.5) * 0.3
                var t = 0.4 + tone + n.fbm(uv(x), uv(y), period: 8, octaves: 2) * 0.25
                if by == 0 || bx == 0 { t += 0.16 }
                if by == 6 || bx == 14 { t -= 0.18 }
                let speck = T.hash01(seed + 2, x, y)
                if speck < 0.06 { t -= 0.2 } else if speck > 0.95 { t += 0.14 }
                c.plot(x, y, brickPal.step(t))
            }
        }
        return c
    }
}
