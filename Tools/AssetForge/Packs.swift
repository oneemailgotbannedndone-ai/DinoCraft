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
