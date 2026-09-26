import Foundation
import DinoCraftCore

/// The built-in texture packs. Each one restyles DinoCraft's own art but keeps its natural
/// colours (grass stays green, water stays blue), so blocks are easy to recognise in every pack.
struct PackStyle {
    let id: String
    let name: String
    let description: String
    let title: String
    let titleTop: String
    let titleBottom: String
    /// Restyles one texture; `tile` is true for full block faces (not plants, torches or items).
    let restyle: (Canvas, _ tile: Bool) -> Canvas

    var manifest: String {
        """
        {
          "id": "\(id)",
          "name": "\(name)",
          "description": "\(description)",
          "title": "\(title)",
          "titleTop": "\(titleTop)",
          "titleBottom": "\(titleBottom)"
        }

        """
    }
}

enum TexturePackForge {
    static let styles: [PackStyle] = [
        PackStyle(id: "tunefulcraft", name: "TunefulCraft", description: "A bright, musical remix with equalizer stripes. Rebrands the game as TunefulCraft.",
                  title: "TunefulCraft", titleTop: "FF8AE0", titleBottom: "38C8F0", restyle: tuneful),
        PackStyle(id: "pastel", name: "Pastel Picnic", description: "Soft, sunny pastel colours.",
                  title: "DinoCraft", titleTop: "FFE3F1", titleBottom: "9FD8F0", restyle: pastel),
        PackStyle(id: "retro", name: "Retro Pixels", description: "Chunky 16-pixel blocks with a limited palette, like an old console.",
                  title: "DinoCraft", titleTop: "F8F0A0", titleBottom: "58B858", restyle: retro),
        PackStyle(id: "autumn", name: "Autumn Woods", description: "Golden grass and red and orange leaves.",
                  title: "DinoCraft", titleTop: "FFD36A", titleBottom: "D2531E", restyle: autumn),
        PackStyle(id: "comic", name: "Comic Ink", description: "Flat comic-book colours with bold ink outlines.",
                  title: "DinoCraft", titleTop: "FFF36A", titleBottom: "FF4A3A", restyle: comic),
        PackStyle(id: "frostbite", name: "Frostbite", description: "An icy winter look: cool blues and frosted edges.",
                  title: "DinoCraft", titleTop: "EAFBFF", titleBottom: "5AB8F0", restyle: frostbite),
        PackStyle(id: "neon", name: "Neon Nights", description: "Dark blocks with glowing neon edges.",
                  title: "DinoCraft", titleTop: "7AF8FF", titleBottom: "FF3AD8", restyle: neon),
        PackStyle(id: "tunefulremix", name: "TunefulCraft Remix", description: "TunefulCraft after dark: glowing equalizers and deep purple shadows. For our first reviewer!",
                  title: "TunefulCraft", titleTop: "C9A2FF", titleBottom: "3AF0D8", restyle: tunefulRemix),
        PackStyle(id: "candy", name: "Candy Land", description: "Sugary pinks and sprinkles on everything.",
                  title: "DinoCraft", titleTop: "FFD1EC", titleBottom: "FF6AB8", restyle: candy),
        PackStyle(id: "desert", name: "Desert Sun", description: "Sun-bleached, sandy and warm.",
                  title: "DinoCraft", titleTop: "FFF0C8", titleBottom: "E0923A", restyle: desert),
        PackStyle(id: "midnight", name: "Midnight", description: "A moonlit world in deep blues, with silver edges.",
                  title: "DinoCraft", titleTop: "DDE6FF", titleBottom: "5A6AD8", restyle: midnight),
        PackStyle(id: "deepsea", name: "Deep Sea", description: "Everything underwater: teal light and rippling caustics.",
                  title: "DinoCraft", titleTop: "B8FFF4", titleBottom: "1A8AA0", restyle: deepSea),
        PackStyle(id: "inferno", name: "Inferno", description: "Charred blocks with glowing lava cracks.",
                  title: "DinoCraft", titleTop: "FFD27A", titleBottom: "E0301A", restyle: inferno),
        PackStyle(id: "gameboy", name: "Pocket Green", description: "Four shades of green, like an old handheld.",
                  title: "DinoCraft", titleTop: "C4DC5A", titleBottom: "306230", restyle: pocketGreen),
        PackStyle(id: "sketchbook", name: "Sketchbook", description: "Coloured pencil on paper, with hatching in the shadows.",
                  title: "DinoCraft", titleTop: "FFFFFF", titleBottom: "8A8A8A", restyle: sketchbook),
        PackStyle(id: "stainedglass", name: "Stained Glass", description: "Glowing panes of colour held in dark lead lines.",
                  title: "DinoCraft", titleTop: "FFE08A", titleBottom: "7A3AE0", restyle: stainedGlass),
        PackStyle(id: "blueprint", name: "Blueprint", description: "Every block drawn as an architect's plan.",
                  title: "DinoCraft", titleTop: "FFFFFF", titleBottom: "7AB8FF", restyle: blueprint),
        PackStyle(id: "watercolor", name: "Watercolour", description: "Soft washes of paint that pool at the edges.",
                  title: "DinoCraft", titleTop: "FFE6F0", titleBottom: "7AB8E0", restyle: watercolor),
        PackStyle(id: "gilded", name: "Gilded", description: "Everything cast in shining gold.",
                  title: "DinoCraft", titleTop: "FFF6B8", titleBottom: "C8901A", restyle: gilded),
    ]

    /// Writes every pack into `root` (Resources/TexturePacks). Returns the texture count per pack.
    static func generate(into root: URL, blocks: [String: Canvas], items: [String: Canvas]) throws -> [String: Int] {
        let fm = FileManager.default
        var counts: [String: Int] = [:]
        for style in styles {
            let dir = root.appendingPathComponent(style.id)
            let blocksDir = dir.appendingPathComponent("blocks"), itemsDir = dir.appendingPathComponent("items")
            try fm.createDirectory(at: blocksDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: itemsDir, withIntermediateDirectories: true)
            var count = 0
            for (name, canvas) in blocks {
                let tile = canvas.px.allSatisfy { $0.a > 0.98 }
                try style.restyle(canvas, tile).write(to: blocksDir.appendingPathComponent("\(name).png"))
                count += 1
            }
            for (name, canvas) in items {
                try style.restyle(canvas, false).write(to: itemsDir.appendingPathComponent("\(name).png"))
                count += 1
            }
            try style.manifest.write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
            counts[style.id] = count
        }
        return counts
    }

    // MARK: Styles

    /// Saturated, posterized colours with faint equalizer bars and dark tile edges.
    static func tuneful(_ src: Canvas, tile: Bool) -> Canvas {
        map(src) { p, x, y, size in
            var (h, s, v) = hsv(p)
            s = min(1, s * 1.35 + 0.08)
            v = min(1, (v * 6).rounded() / 6 * 0.85 + 0.15)
            var c = rgb(h, s, v)
            if tile && (x == 0 || y == 0 || x == size - 1 || y == size - 1) { c = c.shade(0.72) }
            if tile && x % 8 == 3 && Double(size - y) / Double(size) < hash01(7, x / 8, 0) * 0.6 + 0.2 { c = c.lighten(0.12) }
            return c
        }
    }

    /// Lighter, softer colours.
    static func pastel(_ src: Canvas, tile: Bool) -> Canvas {
        let cream = RGBA(hex: 0xFFF6E8)
        return map(src) { p, _, _, _ in
            var (h, s, v) = hsv(p)
            s *= 0.55
            v = 0.42 + v * 0.58
            return rgb(h, s, v).mix(cream, 0.12)
        }
    }

    /// Each 2×2 block of pixels becomes one, with brightness and saturation in a few steps (hues stay).
    static func retro(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let out = Canvas(size)
        for y in stride(from: 0, to: size, by: 2) {
            for x in stride(from: 0, to: size, by: 2) {
                var sum = RGBA(0, 0, 0, 0), alpha = 0.0
                for dy in 0..<2 { for dx in 0..<2 {
                    let p = src.px[(y + dy) * size + x + dx]
                    sum = RGBA(sum.r + p.r * p.a, sum.g + p.g * p.a, sum.b + p.b * p.a, 0)
                    alpha += p.a
                } }
                guard alpha / 4 > 0.45 else { continue }
                var (h, s, v) = hsv(RGBA(sum.r / alpha, sum.g / alpha, sum.b / alpha))
                s = (s * 4).rounded() / 4
                v = max(0.08, (v * 7).rounded() / 7)
                var c = rgb(h, s, v)
                if tile && (x == 0 || y == 0) { c = c.lighten(0.1) }
                if tile && (x == size - 2 || y == size - 2) { c = c.shade(0.75) }
                for dy in 0..<2 { for dx in 0..<2 { out.px[(y + dy) * size + x + dx] = c } }
            }
        }
        return out
    }

    /// Greens turn gold, orange and red; everything else warms slightly.
    static func autumn(_ src: Canvas, tile: Bool) -> Canvas {
        map(src) { p, x, y, _ in
            var (h, s, v) = hsv(p)
            if h > 0.14 && h < 0.48 && s > 0.18 {
                // Dark greens turn red, light greens gold; a few patches lean one way so canopies look mixed.
                let patch = hash01(3, x / 8, y / 8) * 0.04
                h = min(0.13, 0.005 + v * 0.12 + patch)
                s = min(1, s * 1.05 + 0.12)
                v = min(1, v * 1.08)
            } else {
                let warm = rgb(h, s, v)
                return warm.mix(RGBA(1, 0.72, 0.4), 0.08)
            }
            return rgb(h, s, v)
        }
    }

    /// Colours flattened to a few bright steps, with dark ink wherever the colour changes sharply.
    static func comic(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let flat = map(src) { p, _, _, _ in
            var (h, s, v) = hsv(p)
            s = min(1, (s * 3).rounded() / 3 * 1.2 + 0.05)
            v = min(1, (v * 3).rounded() / 3 * 0.8 + 0.22)
            return rgb(h, s, v)
        }
        let ink = RGBA(hex: 0x16121C)
        return map(flat) { p, x, y, _ in
            let right = flat.px[y * size + (x + 1) % size], down = flat.px[((y + 1) % size) * size + x]
            let diff = abs(hsv(p).2 - hsv(right).2) + abs(hsv(p).2 - hsv(down).2)
            if diff > 0.55 || (right.a < 0.5 || down.a < 0.5) && !tile { return ink }
            if tile && (x == 0 || y == 0) { return ink }
            return p
        }
    }

    /// Cool, pale colours with frost creeping in from the edges.
    static func frostbite(_ src: Canvas, tile: Bool) -> Canvas {
        let ice = RGBA(hex: 0xDFF4FF)
        return map(src) { p, x, y, size in
            let (h, s, v) = hsv(p)
            var c = rgb(h, s * 0.7, min(1, v * 0.9 + 0.1)).mix(RGBA(hex: 0x9FD2F0), 0.22)
            if tile {
                let edge = min(min(x, size - 1 - x), min(y, size - 1 - y))
                if edge < 3 && hash01(11, x, y) < 0.6 - Double(edge) * 0.18 { c = c.mix(ice, 0.7) }
            }
            if hash01(5, x, y) < 0.03 { c = ice }
            return c
        }
    }

    /// Dark bodies with bright, saturated neon edges.
    static func neon(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        return map(src) { p, x, y, _ in
            var (h, s, v) = hsv(p)
            let right = src.px[y * size + (x + 1) % size], down = src.px[((y + 1) % size) * size + x]
            let edge = abs(v - hsv(right).2) + abs(v - hsv(down).2) > 0.2 || (tile && (x == 0 || y == 0 || x == size - 1 || y == size - 1))
            if edge {
                s = min(1, max(0.75, s * 1.6))
                v = 1
            } else {
                s = min(1, s * 1.2)
                v *= 0.28
            }
            return rgb(h, s, v)
        }
    }

    /// TunefulCraft's colours in the dark, with glowing equalizer bars and neon tile edges.
    static func tunefulRemix(_ src: Canvas, tile: Bool) -> Canvas {
        let purple = RGBA(hex: 0x2A1248)
        return map(src) { p, x, y, size in
            var (h, s, v) = hsv(p)
            s = min(1, s * 1.4 + 0.1)
            v = (v * 5).rounded() / 5 * 0.62 + 0.08
            var c = rgb(h, s, v).mix(purple, 0.28)
            guard tile else { return c.mix(RGBA(hex: 0xC9A2FF), 0.1) }
            let bar = Double(size - y) / Double(size) < hash01(9, x / 6, 0) * 0.7 + 0.15
            if x % 6 == 2 && bar { c = rgb(0.5 + Double(x) / Double(size) * 0.35, 0.8, 1) }
            if x == 0 || y == 0 { c = RGBA(hex: 0xFF8AE0) } else if x == size - 1 || y == size - 1 { c = RGBA(hex: 0x3AF0D8) }
            return c
        }
    }

    /// Bright and sugary, tinted pink, with sprinkles on block faces.
    static func candy(_ src: Canvas, tile: Bool) -> Canvas {
        let sprinkles: [RGBA] = [RGBA(hex: 0xFF5AA8), RGBA(hex: 0x6AD8FF), RGBA(hex: 0xFFE45A), RGBA(hex: 0x8AF07A), RGBA(hex: 0xFFFFFF)]
        return map(src) { p, x, y, _ in
            let (h, s, v) = hsv(p)
            let c = rgb(h, min(1, s * 0.85 + 0.1), 0.45 + v * 0.55).mix(RGBA(hex: 0xFFB8DC), 0.16)
            if tile && hash01(21, x, y) < 0.035 { return sprinkles[Int(hash01(22, x, y) * 5) % 5] }
            return c
        }
    }

    /// Warm, sandy and faded, a little lighter towards the top of each block.
    static func desert(_ src: Canvas, tile: Bool) -> Canvas {
        let sand = RGBA(hex: 0xE8C890)
        return map(src) { p, x, y, size in
            let (h, s, v) = hsv(p)
            var c = rgb(h, s * 0.72, min(1, v * 1.02 + 0.04)).mix(sand, 0.2)
            if tile { c = c.lighten(0.12 * (1 - Double(y) / Double(size))) }
            if hash01(31, x, y) < 0.05 { c = c.shade(0.9) }
            return c
        }
    }

    /// Dark and blue, lit from above by moonlight, with the odd star-like fleck.
    static func midnight(_ src: Canvas, tile: Bool) -> Canvas {
        let night = RGBA(hex: 0x14204A)
        return map(src) { p, x, y, size in
            let (h, s, v) = hsv(p)
            var c = rgb(h, s * 0.8, v * 0.62).mix(night, 0.3)
            if tile && (y == 0 || (y == 1 && hash01(41, x, 0) < 0.5)) { c = c.mix(RGBA(hex: 0xC8D4FF), 0.45) }
            if tile && (x == size - 1 || y == size - 1) { c = c.shade(0.7) }
            if hash01(42, x, y) < 0.012 { c = RGBA(hex: 0xEEF2FF) }
            return c
        }
    }

    /// A teal underwater tint with rippling bands of light.
    static func deepSea(_ src: Canvas, tile: Bool) -> Canvas {
        let sea = RGBA(hex: 0x10687A)
        return map(src) { p, x, y, size in
            let (h, s, v) = hsv(p)
            var c = rgb(h, s * 0.85, v * 0.82).mix(sea, 0.3)
            let fx = Double(x) / Double(size) * 2 * .pi, fy = Double(y) / Double(size) * 2 * .pi
            let ripple = sin(fx * 2 + sin(fy * 3) * 1.4) + sin(fy * 2 - fx)
            if ripple > 1.35 { c = c.mix(RGBA(hex: 0xB8FFF4), 0.3) }
            if hash01(51, x, y) < 0.01 { c = RGBA(hex: 0xDFFFFA) }   // bubbles
            return c
        }
    }

    /// Charred and dark, with lava glowing in the cracks between colours.
    static func inferno(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let ash = RGBA(hex: 0x2A0C08)
        return map(src) { p, x, y, _ in
            let (h, s, v) = hsv(p)
            let right = src.px[y * size + (x + 1) % size], down = src.px[((y + 1) % size) * size + x]
            let crack = abs(v - hsv(right).2) + abs(v - hsv(down).2)
            if tile && crack > 0.42 && v < 0.6 {
                return RGBA(hex: 0xFF7A1A).mix(RGBA(hex: 0xFFD27A), min(1, (crack - 0.42) * 2))
            }
            var c = rgb(h, s * 0.9, v * 0.5).mix(ash, 0.32)
            if tile && hash01(61, x, y) < 0.02 { c = RGBA(hex: 0xFF5A14) }   // embers
            return c
        }
    }

    /// Brightness in four shades of green, like an old handheld's screen.
    static func pocketGreen(_ src: Canvas, tile: Bool) -> Canvas {
        let shades = [RGBA(hex: 0x0F380F), RGBA(hex: 0x306230), RGBA(hex: 0x8BAC0F), RGBA(hex: 0xC4DC5A)]
        return map(src) { p, x, y, _ in
            let l = 0.3 * p.r + 0.59 * p.g + 0.11 * p.b
            // A little ordered dither keeps gradients from banding.
            let dither = ((x % 2) * 2 + (y % 2) * 3) % 4
            let level = min(3, max(0, Int(l * 4.2 + Double(dither) * 0.08 - 0.1)))
            return shades[level]
        }
    }

    /// Coloured pencil on cream paper: soft colour, hatching in the shadows and pencil tile edges.
    static func sketchbook(_ src: Canvas, tile: Bool) -> Canvas {
        let paper = RGBA(hex: 0xF4EFE2), pencil = RGBA(hex: 0x3A3A44)
        return map(src) { p, x, y, size in
            let (h, s, v) = hsv(p)
            var c = paper.mix(rgb(h, s * 0.8, v), 0.62)
            if v < 0.55 && (x + y) % 4 == 0 { c = c.mix(pencil, 0.55) }
            if v < 0.32 && (x - y + size) % 4 == 0 { c = c.mix(pencil, 0.6) }
            if tile && (x == 0 || y == 0) && hash01(71, x, y) < 0.8 { c = c.mix(pencil, 0.7) }
            if hash01(72, x, y) < 0.08 { c = c.lighten(0.15) }   // paper grain
            return c
        }
    }

    /// Glowing panes of colour (each 4×4 area's average) held in dark lead lines.
    static func stainedGlass(_ src: Canvas, tile: Bool) -> Canvas {
        map(src) { (_: RGBA, x: Int, y: Int, _: Int) -> RGBA in pane(src, x, y, tile: tile) }
    }

    private static func pane(_ src: Canvas, _ x: Int, _ y: Int, tile: Bool) -> RGBA {
        let size = src.size
        let lead = RGBA(hex: 0x1A1620)
        // Panes are 8×8 with jittered corners so they don't look like a plain grid.
        let cx = x / 8, cy = y / 8
        let jx = Int(hash01(81, cx, cy) * 3) - 1, jy = Int(hash01(82, cx, cy) * 3) - 1
        let lx = (x + jx + 8) % 8, ly = (y + jy + 8) % 8
        if tile && (lx == 0 || ly == 0) { return lead }
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        let x0 = x / 4 * 4, y0 = y / 4 * 4
        for dy in 0..<4 {
            for dx in 0..<4 {
                let row: Int = (y0 + dy) % size, col: Int = (x0 + dx) % size
                let q = src.px[row * size + col]
                guard q.a > 0.01 else { continue }
                r += q.r; g += q.g; b += q.b; n += 1
            }
        }
        guard n > 0 else { return lead }
        let (h, s, v) = hsv(RGBA(r / n, g / n, b / n))
        let offCentre: Double = abs(Double(lx) - 3.5) + abs(Double(ly) - 3.5)
        let glow: Double = 1 - offCentre / 14
        let value: Double = min(1, v * 0.85 + 0.12) * (0.8 + glow * 0.25)
        return rgb(h, min(1, s * 1.35 + 0.1), value)
    }

    /// Blue paper with white lines wherever the picture changes, and a faint drafting grid.
    static func blueprint(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let paper = RGBA(hex: 0x1E4E8C), ink = RGBA(hex: 0xE4F0FF)
        return map(src) { p, x, y, _ in
            let v = hsv(p).2
            let right = src.px[y * size + (x + 1) % size], down = src.px[((y + 1) % size) * size + x]
            let edge = abs(v - hsv(right).2) + abs(v - hsv(down).2) > 0.38 || (!tile && (right.a < 0.5 || down.a < 0.5))
            if edge || (tile && (x == 0 || y == 0)) { return ink }
            var c = paper.mix(RGBA(hex: 0x3A78C0), v * 0.6)
            if tile && (x % 8 == 4 || y % 8 == 4) { c = c.mix(ink, 0.15) }
            return c
        }
    }

    /// Softened colour on paper, with pigment pooling darker where colours meet.
    static func watercolor(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let paper = RGBA(hex: 0xFBF7EE)
        return map(src) { p, x, y, _ in
            var sum = RGBA(0, 0, 0, 0), n = 0.0
            for dy in -1...1 { for dx in -1...1 {
                let q = src.px[((y + dy + size) % size) * size + (x + dx + size) % size]
                guard q.a > 0.01 else { continue }
                sum = RGBA(sum.r + q.r, sum.g + q.g, sum.b + q.b); n += 1
            } }
            let blur = RGBA(sum.r / n, sum.g / n, sum.b / n)
            let (h, s, v) = hsv(blur)
            var c = rgb(h, s * 0.8, min(1, v * 0.95 + 0.08)).mix(paper, 0.18)
            let pool = abs(hsv(p).2 - v)
            if pool > 0.1 { c = c.shade(1 - min(0.25, pool)) }
            if hash01(91, x / 2, y / 2) < 0.12 { c = c.mix(paper, 0.2) }   // paper showing through
            return c
        }
    }

    /// Brightness mapped onto a gold ramp, keeping a hint of each block's colour, with a diagonal shine.
    static func gilded(_ src: Canvas, tile: Bool) -> Canvas {
        let dark = RGBA(hex: 0x4A2C06), mid = RGBA(hex: 0xC8901A), bright = RGBA(hex: 0xFFF2A8)
        return map(src) { p, x, y, size in
            let v = hsv(p).2
            var c = v < 0.5 ? dark.mix(mid, v * 2) : mid.mix(bright, (v - 0.5) * 2)
            c = c.mix(p, 0.22)
            if tile && (x + y) % size < 3 { c = c.lighten(0.3) }
            return c
        }
    }

    // MARK: Helpers

    private static func map(_ src: Canvas, _ body: (RGBA, Int, Int, Int) -> RGBA) -> Canvas {
        let size = src.size
        let out = Canvas(size)
        for y in 0..<size {
            for x in 0..<size {
                let p = src.px[y * size + x]
                guard p.a > 0.01 else { continue }
                var c = body(p, x, y, size)
                c.a = p.a
                out.px[y * size + x] = c
            }
        }
        return out
    }

    private static func hash01(_ seed: UInt64, _ x: Int, _ y: Int) -> Double {
        var h = seed &* 0x9E37_79B9_7F4A_7C15 ^ UInt64(bitPattern: Int64(x)) &* 0xBF58_476D_1CE4_E5B9 ^ UInt64(bitPattern: Int64(y)) &* 0x94D0_49BB_1331_11EB
        h ^= h >> 31
        h = h &* 0xD6E8_FEB8_6659_FD93
        h ^= h >> 32
        return Double(h % 10_000) / 10_000
    }

    static func hsv(_ c: RGBA) -> (Double, Double, Double) {
        let mx = max(c.r, c.g, c.b), mn = min(c.r, c.g, c.b), d = mx - mn
        var h = 0.0
        if d > 1e-6 {
            if mx == c.r { h = ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == c.g { h = (c.b - c.r) / d + 2 }
            else { h = (c.r - c.g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx > 0 ? d / mx : 0, mx)
    }

    static func rgb(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
        let i = Int(h * 6) % 6, f = h * 6 - floor(h * 6)
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return RGBA(v, t, p)
        case 1: return RGBA(q, v, p)
        case 2: return RGBA(p, v, t)
        case 3: return RGBA(p, q, v)
        case 4: return RGBA(t, p, v)
        default: return RGBA(v, p, q)
        }
    }
}
