import Foundation
import DinoCraftCore

/// Generates the built-in "TunefulCraft" texture pack: a neon, posterized remix
/// of every DinoCraft texture, plus a manifest that rebrands the title.
enum Tuneful {
    static let neon = Palette([0x1B0B3A, 0x4A1A7A, 0xB02E9C, 0xFF6AC1, 0x5FF2F0, 0xF4F0FF])

    static let manifest = """
    {
      "id": "tunefulcraft",
      "name": "TunefulCraft",
      "description": "A neon, musical remix of every block and item. Rebrands the game as TunefulCraft.",
      "title": "TunefulCraft",
      "titleTop": "FF8AE0",
      "titleBottom": "38C8F0"
    }

    """

    static func generate(into dir: URL, blocks: [String: Canvas], blockNames: [String], itemNames: [String]) throws -> Int {
        let fm = FileManager.default
        let blocksDir = dir.appendingPathComponent("blocks"), itemsDir = dir.appendingPathComponent("items")
        try fm.createDirectory(at: blocksDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: itemsDir, withIntermediateDirectories: true)
        var count = 0
        for name in blockNames {
            guard let canvas = blocks[name] else { continue }
            try stylize(canvas, tile: true).write(to: blocksDir.appendingPathComponent("\(name).png"))
            count += 1
        }
        for name in itemNames {
            try stylize(TexturePainter.paintItem(name), tile: false).write(to: itemsDir.appendingPathComponent("\(name).png"))
            count += 1
        }
        try manifest.write(to: dir.appendingPathComponent("pack.json"), atomically: true, encoding: .utf8)
        return count
    }

    static func stylize(_ src: Canvas, tile: Bool) -> Canvas {
        let size = src.size
        let out = Canvas(size)
        let opaque = src.px.allSatisfy { $0.a > 0.98 }
        for y in 0..<size {
            for x in 0..<size {
                let p = src.px[y * size + x]
                guard p.a > 0.01 else { continue }
                var (h, s, v) = hsv(p)
                h = (h + 0.52).truncatingRemainder(dividingBy: 1)
                s = min(1, s * 1.3 + 0.12)
                v = min(1, (v * 6).rounded() / 6 * 0.9 + 0.1)
                let lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b
                var c = rgb(h, s, v).mix(neon.ramp(lum), 0.3)
                if opaque && tile && (x == 0 || y == 0 || x == size - 1 || y == size - 1) { c = c.shade(0.78) }
                // Faint "equalizer" stripes on solid tiles
                if opaque && tile && (x % 8 == 3) && Double(size - y) / Double(size) < TexturePainter.hash01(7, x / 8, 0) * 0.6 + 0.2 {
                    c = c.lighten(0.06)
                }
                c.a = p.a
                out.px[y * size + x] = c
            }
        }
        return out
    }

    private static func hsv(_ c: RGBA) -> (Double, Double, Double) {
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

    private static func rgb(_ h: Double, _ s: Double, _ v: Double) -> RGBA {
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
