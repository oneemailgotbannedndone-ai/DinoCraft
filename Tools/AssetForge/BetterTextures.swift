import Foundation
import DinoCraftCore

/// Hand-shaded tools, a craggier bedrock and the Deep Slate of the deep layers.
enum BetterTextures {
    static let S = TexturePainter.S

    static func add(to t: inout [String: Canvas]) {
        t["bedrock"] = bedrock()
        t["deep_slate"] = deepSlate()
    }

    /// Head colours per material: (dark edge, body, highlight, sparkle).
    static let heads: [String: (UInt32, UInt32, UInt32, UInt32)] = [
        "wooden": (0x6B4424, 0xA8743F, 0xD6A266, 0xEBC48C),
        "stone": (0x4A4C54, 0x7E818C, 0xA9ACB6, 0xCDD0D8),
        "iron": (0x7C8591, 0xC4CAD3, 0xE8ECF1, 0xFFFFFF),
        "diamond": (0x138A84, 0x3FD9CE, 0x9BF6EE, 0xE8FFFD),
        "starmetal": (0x3A2458, 0x7A4ED8, 0xB89AF8, 0xFFE8A0),
    ]

    /// A pickaxe drawn pixel by pixel: a curved two-pointed head with a bevel and
    /// highlights, bound to a grained handle with a leather wrap.
    static func pickaxe(_ material: String) -> Canvas? {
        guard let (edgeHex, bodyHex, lightHex, sparkHex) = heads[material] else { return nil }
        let c = Canvas(S)
        let edge = RGBA(hex: edgeHex), body = RGBA(hex: bodyHex), light = RGBA(hex: lightHex), spark = RGBA(hex: sparkHex)
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)
        handle(c, length: 20)
        // Head: an arc of thick pixels centred on the top of the handle
        let cx = 21.0, cy = 11.0
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                // u runs across the handle (top-left to bottom-right); v points back down the handle.
                let u = (dx + dy) / 2.0.squareRoot(), v = (dy - dx) / 2.0.squareRoot()
                let arc = v - u * u / 16                        // an arch over the handle, points curving down
                let thickness = 3.1 - abs(u) * 0.16             // tapers to points
                guard abs(u) < 11.5, abs(arc) < thickness else { continue }
                let shade: RGBA
                if arc < -thickness * 0.35 { shade = light } else if arc > thickness * 0.35 { shade = edge } else { shade = body }
                c.plot(x, y, abs(u) > 10 ? edge : shade)
            }
        }
        // Binding where head meets handle, and a glint on the blade
        c.plot(20, 11, wrap); c.plot(21, 12, wrap); c.plot(21, 11, wrapLight); c.plot(22, 12, wrap)
        c.plot(17, 6, spark); c.plot(18, 6, spark.withAlpha(0.7)); c.plot(17, 7, spark.withAlpha(0.7))
        if material == "diamond" { c.plot(26, 16, spark); c.plot(25, 15, spark.withAlpha(0.6)) }
        c.outline()
        return c
    }

    /// Every tool uses the pickaxe's look: the same grained handle with a leather wrap, and a metal
    /// head shaded in three bands (lit top edge, body, dark lower edge) with a dark outline and a glint.
    private struct Head {
        let edge: RGBA, body: RGBA, light: RGBA, spark: RGBA
        init?(_ material: String) {
            guard let (e, b, l, s) = BetterTextures.heads[material] else { return nil }
            edge = RGBA(hex: e); body = RGBA(hex: b); light = RGBA(hex: l); spark = RGBA(hex: s)
        }
        /// `across` runs from -1 (lit side) to 1 (shadow side) of the part being shaded.
        func shade(_ across: Double) -> RGBA { across < -0.35 ? light : (across > 0.35 ? edge : body) }
    }

    /// Pixel centres in the pickaxe's frame around (cx, cy): u runs across the handle (top-left to
    /// bottom-right), v back down the handle (towards the bottom-left).
    private static func eachPixel(cx: Double, cy: Double, _ body: (Int, Int, Double, Double) -> Void) {
        let r = 1 / 2.0.squareRoot()
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                body(x, y, (dx + dy) * r, (dy - dx) * r)
            }
        }
    }

    /// An axe: a flared, gently curved blade on one side of the handle and a short poll on the other.
    static func axe(_ material: String) -> Canvas? {
        guard let head = Head(material) else { return nil }
        let c = Canvas(S)
        handle(c, length: 20)
        eachPixel(cx: 21, cy: 11) { x, y, u, v in
            if u < -0.5 {
                // The blade widens (along the handle) the further it reaches, and its cutting edge bulges out.
                let reach = -u
                let half = 1.8 + (reach - 0.5) * 0.46
                let centre = 0.2 - reach * 0.06
                let limit = 10.6 - (v - centre) * (v - centre) / 12
                guard reach < limit, abs(v - centre) < half else { return }
                c.plot(x, y, reach > limit - 1.3 ? head.light : head.shade((v - centre) / half))
            } else if u < 3.2 && abs(v) < 1.7 {
                c.plot(x, y, u > 2.2 ? head.edge : head.shade(v / 1.7))          // the poll
            }
        }
        let wrap = RGBA(hex: 0x3A2A22)
        c.plot(20, 11, wrap); c.plot(21, 12, wrap); c.plot(22, 12, wrap)
        c.plot(14, 7, head.spark); c.plot(15, 6, head.spark.withAlpha(0.7))
        if material == "diamond" { c.plot(17, 11, head.spark); c.plot(12, 9, head.spark.withAlpha(0.6)) }
        c.outline()
        return c
    }

    /// A sword: a tapered blade with a fuller, a crossguard of the same metal, and the pickaxe's wooden
    /// handle wood and leather wrap on the grip.
    static func sword(_ material: String) -> Canvas? {
        guard let head = Head(material) else { return nil }
        let c = Canvas(S)
        let wood = RGBA(hex: 0x8A5A30), woodDark = RGBA(hex: 0x5A3A1C)
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)
        // Local frame at the guard: s runs towards the tip (top-right), t across the blade.
        let gx = 10.0, gy = 22.0, r = 1 / 2.0.squareRoot()
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - gx, dy = Double(y) + 0.5 - gy
                let s = (dx - dy) * r, t = (dx + dy) * r
                if s > 0.6 && s < 23.5 {
                    let half = s < 18 ? 2.2 : 2.2 * (23.5 - s) / 5.5
                    guard abs(t) < half else { continue }
                    var shade = head.shade(t / half)
                    if abs(t) < 0.45 && s > 2 && s < 16 { shade = head.edge.mix(head.body, 0.5) }   // fuller
                    c.plot(x, y, shade)
                } else if s > -1.1 && s <= 0.6 && abs(t) < 4.8 {
                    c.plot(x, y, s > -0.25 ? head.light : head.edge)                               // crossguard
                } else if s > -6.6 && s <= -1.1 && abs(t) < 1.15 {
                    let band = Int((-s) * 1.2) % 3
                    c.plot(x, y, band == 0 ? wrap : (band == 1 ? wrapLight : (t < 0 ? wood : woodDark)))   // grip
                } else if (s + 7.8) * (s + 7.8) + t * t < 3 {
                    c.plot(x, y, head.shade(t + (s + 7.8)))                                       // pommel
                }
            }
        }
        c.plot(24, 7, head.spark); c.plot(22, 9, head.spark.withAlpha(0.7)); c.plot(18, 13, head.spark.withAlpha(0.5))
        c.outline()
        return c
    }

    /// A shovel: a rounded spade on a metal collar at the end of the handle.
    static func shovel(_ material: String) -> Canvas? {
        guard let head = Head(material) else { return nil }
        let c = Canvas(S)
        handle(c, length: 17)
        // Frame at the collar: s runs out along the handle (top-right), t across it.
        let ox = 22.0, oy = 10.0, r = 1 / 2.0.squareRoot()
        for y in 0..<S {
            for x in 0..<S {
                let dx = Double(x) + 0.5 - ox, dy = Double(y) + 0.5 - oy
                let s = (dx - dy) * r, t = (dx + dy) * r
                if s > -0.8 && s < 1.6 && abs(t) < 1.5 {
                    c.plot(x, y, s < 0.4 ? head.edge : head.body)                                 // collar
                } else if s >= 1.6 && s < 11 {
                    let tip = max(0, s - 7.5)
                    let half = 3.3 - tip * tip * 0.27
                    guard abs(t) < half else { continue }
                    c.plot(x, y, s > 10 - tip * 0.2 ? head.light : head.shade(t / half))
                }
            }
        }
        c.plot(25, 4, head.spark); c.plot(26, 5, head.spark.withAlpha(0.7))
        c.outline()
        return c
    }

    /// A hoe: a flat blade turned down at the end, fixed across the top of the handle.
    static func hoe(_ material: String) -> Canvas? {
        guard let head = Head(material) else { return nil }
        let c = Canvas(S)
        handle(c, length: 21)
        eachPixel(cx: 22, cy: 10) { x, y, u, v in
            if u < 1.4 && u > -9.5 && v > -1.9 && v < 1.5 {
                c.plot(x, y, head.shade((v + 0.2) / 1.7))                                          // blade
            } else if u <= -6.2 && u > -9.5 && v >= 1.5 && v < 5 {
                c.plot(x, y, u < -8.4 ? head.light : head.shade((u + 7.85) / 1.6))                 // turned-down edge
            }
        }
        let wrap = RGBA(hex: 0x3A2A22)
        c.plot(22, 10, wrap); c.plot(23, 11, wrap)
        c.plot(16, 6, head.spark); c.plot(17, 5, head.spark.withAlpha(0.7))
        c.outline()
        return c
    }

    /// The shared diagonal wooden handle with grain and a leather wrap near the bottom.
    private static func handle(_ c: Canvas, length: Int) {
        let wood = RGBA(hex: 0x8A5A30), woodDark = RGBA(hex: 0x5A3A1C), woodLight = RGBA(hex: 0xB07A44)
        let wrap = RGBA(hex: 0x3A2A22), wrapLight = RGBA(hex: 0x5E4636)
        for i in 0..<length {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, wood)
            c.plot(x + 1, y, i % 4 == 1 ? woodDark : woodLight)
            c.plot(x, y + 1, woodDark)
        }
        for i in 1..<5 {
            let x = 5 + i, y = 27 - i
            c.plot(x, y, i % 2 == 0 ? wrap : wrapLight)
            c.plot(x + 1, y, wrap)
            c.plot(x, y + 1, wrap)
        }
    }

    /// One half of a double chest, made from the single chest's texture: the metal border is taken off
    /// the right-hand edge (where the two halves meet), and on the front the latch moves to that edge
    /// so the pair shares one latch in the middle.
    static func chestHalf(_ full: Canvas, front: Bool) -> Canvas {
        let c = Canvas(S)
        c.px = full.px
        for y in 0..<S {
            c[S - 2, y] = full[S - 4, y]
            c[S - 1, y] = full[S - 3, y]
        }
        guard front else { return c }
        // Cover the old latch with the wood beside it, then draw half a latch on the seam.
        for y in 8..<16 { for x in 13..<19 { c[x, y] = full[x - 6, y] } }
        let band = RGBA(hex: 0x3A3A42), bandLight = RGBA(hex: 0x6A6A74)
        for y in 8..<16 { for x in (S - 3)..<S { c[x, y] = (x == S - 3 || y == 8 || y == 15) ? band : bandLight } }
        c[S - 1, 12] = RGBA(hex: 0x141418)
        return c
    }

    // MARK: Ores

    /// How each ore's deposits look: colours (outline, dark, body, light, sparkle), shape and how many.
    private struct OreStyle {
        enum Shape { case lump, nugget, gem, crystal, drop }
        let colors: (UInt32, UInt32, UInt32, UInt32, UInt32)
        let shape: Shape
        let clusters: Int
        let size: Double
        let glow: Bool
    }

    private static let ores: [String: OreStyle] = [
        "coal": OreStyle(colors: (0x0A0A0D, 0x17171C, 0x2A2A32, 0x4A4A56, 0x8C8C9A), shape: .lump, clusters: 5, size: 2.3, glow: false),
        "iron": OreStyle(colors: (0x6A4A36, 0xB48262, 0xDEB294, 0xF4D4BC, 0xFFFFFF), shape: .nugget, clusters: 5, size: 2.2, glow: false),
        "gold": OreStyle(colors: (0x8A6410, 0xD8A020, 0xFAD23C, 0xFFF08A, 0xFFFFF0), shape: .nugget, clusters: 5, size: 2.1, glow: false),
        "diamond": OreStyle(colors: (0x0A4A4A, 0x159A94, 0x3FD9CE, 0x9BF6EE, 0xFFFFFF), shape: .gem, clusters: 4, size: 3.0, glow: false),
        "emerald": OreStyle(colors: (0x063A1A, 0x0E7A3A, 0x22C25E, 0x8AF2B0, 0xE8FFF0), shape: .crystal, clusters: 3, size: 3.2, glow: false),
        "amber": OreStyle(colors: (0x5A2A04, 0xB4600E, 0xF29A22, 0xFFD27A, 0xFFF4D0), shape: .drop, clusters: 4, size: 2.6, glow: true),
    ]

    /// An ore block: the stone with each deposit set into a shadowed socket, shaded to look solid,
    /// with a glint of light. Deposits wrap across the edges so ores tile seamlessly.
    static func ore(_ kind: String, base: Canvas, seed: UInt64) -> Canvas? {
        guard let style = ores[kind] else { return nil }
        let c = Canvas(S)
        c.px = base.px
        let (outlineHex, darkHex, bodyHex, lightHex, sparkHex) = style.colors
        let outline = RGBA(hex: outlineHex), dark = RGBA(hex: darkHex), body = RGBA(hex: bodyHex), light = RGBA(hex: lightHex), spark = RGBA(hex: sparkHex)
        var rng = SplitMix64(seed: seed)
        // Spread the clusters out: keep the candidate furthest from the others each time.
        var centres: [(Double, Double)] = []
        for _ in 0..<style.clusters {
            var best = (0.0, 0.0), bestGap = -1.0
            for _ in 0..<12 {
                let p = (Double(rng.nextInt(S)), Double(rng.nextInt(S)))
                let gap = centres.map { q -> Double in
                    let dx = min(abs(p.0 - q.0), Double(S) - abs(p.0 - q.0)), dy = min(abs(p.1 - q.1), Double(S) - abs(p.1 - q.1))
                    return dx * dx + dy * dy
                }.min() ?? 1000
                if gap > bestGap { bestGap = gap; best = p }
            }
            centres.append(best)
        }
        func wrap(_ v: Int) -> Int { ((v % S) + S) % S }
        for (cx, cy) in centres {
            // Each cluster is a few pieces of different sizes.
            let pieces = style.shape == .gem || style.shape == .crystal ? 1 + rng.nextInt(2) : 2 + rng.nextInt(3)
            for k in 0..<pieces {
                let px = cx + (k == 0 ? 0 : Double(rng.nextInt(7)) - 3), py = cy + (k == 0 ? 0 : Double(rng.nextInt(7)) - 3)
                let r = style.size * (k == 0 ? 1 : 0.55 + rng.nextDouble() * 0.35)
                let wobble = rng.nextDouble() * 6.28
                let reach = Int(r * 2 + 3)
                for yy in -reach...reach {
                    for xx in -reach...reach {
                        let dx = Double(xx) + 0.5 - (px - floor(px)), dy = Double(yy) + 0.5 - (py - floor(py))
                        let X = wrap(Int(floor(px)) + xx), Y = wrap(Int(floor(py)) + yy)
                        // Signed "inside" value (>0 inside) and a facet/light value from -1 (lit) to 1 (shadow).
                        var inside: Double, facet: Double
                        switch style.shape {
                        case .lump, .nugget, .drop:
                            let a = atan2(dy, dx)
                            let rr = r * (1 + (style.shape == .lump ? 0.22 : 0.12) * sin(a * 3 + wobble))
                            let d = (dx * dx + dy * dy * (style.shape == .drop ? 0.8 : 1)).squareRoot()
                            inside = rr - d
                            facet = (dx + dy) / max(0.5, rr) * 0.9
                        case .gem:
                            let d = abs(dx) + abs(dy)
                            inside = r * 1.25 - d
                            facet = dx < 0 && dy < 0 ? -1 : (dx >= 0 && dy >= 0 ? 1 : (dy < 0 ? -0.2 : 0.3))
                        case .crystal:
                            let w = r * 0.62, h = r * 1.45
                            inside = min(w - abs(dx), h - abs(dy) - max(0, abs(dx) - w * 0.2) * 1.1)
                            facet = dx < -w * 0.3 ? -1 : (dx > w * 0.3 ? 1 : -0.1)
                        }
                        if inside > 0 {
                            var col: RGBA
                            if inside < (style.shape == .nugget ? 0.55 : 0.85) { col = outline.mix(dark, 0.35) }
                            else if facet < -0.45 { col = light }
                            else if facet > 0.45 { col = dark }
                            else { col = body }
                            if style.shape == .drop && abs(dx + 0.6) < 0.6 && abs(dy - 0.3) < 0.6 && k == 0 { col = RGBA(hex: 0x3A1A04) }   // trapped speck
                            c[X, Y] = col
                        } else if inside > -1.3 {
                            // The socket: stone darkened around the deposit (and a warm halo for glowing ores).
                            let shade = style.glow ? c[X, Y].mix(body, 0.35) : c[X, Y].shade(0.72)
                            c[X, Y] = shade
                        }
                    }
                }
                // A glint on the lit side of the biggest piece
                if k == 0 {
                    let gx = wrap(Int(floor(px - r * 0.35))), gy = wrap(Int(floor(py - r * 0.35)))
                    c[gx, gy] = spark
                    if r > 2.2 { c[wrap(gx + 1), gy] = spark.mix(light, 0.5) }
                }
            }
        }
        return c
    }

    /// Bedrock: dark, jagged chunks of rock with deep cracks and a few pale flecks.
    static func bedrock() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 1313)
        let tones: [UInt32] = [0x121214, 0x1E1E22, 0x2C2C32, 0x3C3C44, 0x50505A, 0x6A6A74]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let (d1, d2, id) = n.voronoi(u, v, cells: 5)
            let rim = d2 - d1
            if rim < 0.035 { return RGBA(hex: 0x0A0A0C) }                        // cracks between chunks
            var level = Int(id % 4) + 1
            if rim > 0.1 && Hashing.unit(3, Int32(x), Int32(y), 0) < 0.25 { level += 1 }   // raised faces catch light
            return RGBA(hex: tones[max(0, min(tones.count - 1, level))])
        }
        var rng = SplitMix64(seed: 77)
        for _ in 0..<6 { c[rng.nextInt(S), rng.nextInt(S)] = RGBA(hex: 0x8A8A96) }
        return c
    }

    /// Deep Slate: dark blue-grey rock in thin tilted layers.
    static func deepSlate() -> Canvas {
        let c = Canvas(S)
        let n = TileNoise(seed: 2525)
        let tones: [UInt32] = [0x1C1F28, 0x262A35, 0x303543, 0x3B4151, 0x4A5163]
        c.fill { x, y in
            let u = Double(x) / Double(S), v = Double(y) / Double(S)
            let layer = (y + x / 6) % 5
            let grain = n.fbm(u, v, period: 4, octaves: 3)
            var level = 2 + (layer == 0 ? -1 : 0) + (layer == 2 ? 1 : 0) + Int((grain - 0.5) * 3)
            if layer == 4 && x % 9 == 3 { level = 0 }
            return RGBA(hex: tones[max(0, min(tones.count - 1, level))])
        }
        return c
    }
}
