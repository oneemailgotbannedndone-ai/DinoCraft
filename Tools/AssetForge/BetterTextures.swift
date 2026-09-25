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
