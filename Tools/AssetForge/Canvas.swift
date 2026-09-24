import Foundation
import DinoCraftCore

struct RGBA {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
    init(hex: UInt32, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255; g = Double((hex >> 8) & 0xFF) / 255; b = Double(hex & 0xFF) / 255; a = alpha
    }
    static let clear = RGBA(0, 0, 0, 0)

    func mix(_ o: RGBA, _ t: Double) -> RGBA {
        RGBA(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t, a + (o.a - a) * t)
    }
    func shade(_ k: Double) -> RGBA { RGBA(r * k, g * k, b * k, a) }
    func lighten(_ t: Double) -> RGBA { mix(RGBA(1, 1, 1, a), t) }
    func withAlpha(_ na: Double) -> RGBA { RGBA(r, g, b, na) }
}

/// Tiny RGBA raster used to paint textures procedurally. Coordinates wrap so
/// every painted texture tiles seamlessly across greedy-merged block faces.
final class Canvas {
    let size: Int
    var px: [RGBA]

    init(_ size: Int, fill: RGBA = .clear) {
        self.size = size
        px = Array(repeating: fill, count: size * size)
    }

    @inline(__always) func wrap(_ v: Int) -> Int { ((v % size) + size) % size }

    subscript(x: Int, y: Int) -> RGBA {
        get { px[wrap(y) * size + wrap(x)] }
        set { px[wrap(y) * size + wrap(x)] = newValue }
    }

    func fill(_ body: (Int, Int) -> RGBA) {
        for y in 0..<size { for x in 0..<size { px[y * size + x] = body(x, y) } }
    }

    func rect(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ c: RGBA) {
        for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { self[x, y] = c } }
    }

    /// Non-wrapping pixel set (for sprites).
    func plot(_ x: Int, _ y: Int, _ c: RGBA) {
        guard x >= 0, y >= 0, x < size, y < size else { return }
        px[y * size + x] = c
    }

    func line(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, width: Double, _ c: (Double) -> RGBA) {
        let len = max(abs(x1 - x0), abs(y1 - y0))
        let steps = max(1, Int(len * 3))
        for i in 0...steps {
            let t = Double(i) / Double(steps)
            let x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t
            disc(x, y, width / 2, c(t))
        }
    }

    func disc(_ cx: Double, _ cy: Double, _ r: Double, _ c: RGBA) {
        let x0 = Int(floor(cx - r)), x1 = Int(ceil(cx + r)), y0 = Int(floor(cy - r)), y1 = Int(ceil(cy + r))
        for y in y0...y1 {
            for x in x0...x1 {
                let dx = Double(x) + 0.5 - cx, dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= r * r { plot(x, y, c) }
            }
        }
    }

    /// Adds a dark outline around opaque sprite pixels for legibility on any background.
    func outline(_ color: RGBA = RGBA(hex: 0x1B1410, alpha: 0.95)) {
        let src = px
        for y in 0..<size {
            for x in 0..<size where src[y * size + x].a < 0.1 {
                var near = false
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    if nx >= 0, ny >= 0, nx < size, ny < size, src[ny * size + nx].a > 0.5 { near = true }
                }
                if near { px[y * size + x] = color }
            }
        }
    }

    func write(to url: URL) throws {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let p = px[i]
            let a = max(0, min(1, p.a))
            guard a > 0 else { continue }
            bytes[i * 4] = UInt8(max(0, min(255, (p.r * 255).rounded())))
            bytes[i * 4 + 1] = UInt8(max(0, min(255, (p.g * 255).rounded())))
            bytes[i * 4 + 2] = UInt8(max(0, min(255, (p.b * 255).rounded())))
            bytes[i * 4 + 3] = UInt8((a * 255).rounded())
        }
        try PNG.encode(width: size, height: size, rgba: bytes).write(to: url)
    }

    /// Loads a square PNG (for restyling textures that were already painted).
    static func read(_ url: URL) throws -> Canvas {
        let image = try PNG.decode(Data(contentsOf: url))
        let canvas = Canvas(image.width)
        for i in 0..<(image.width * min(image.width, image.height)) {
            let b = image.rgba
            canvas.px[i] = RGBA(Double(b[i * 4]) / 255, Double(b[i * 4 + 1]) / 255, Double(b[i * 4 + 2]) / 255, Double(b[i * 4 + 3]) / 255)
        }
        return canvas
    }
}

/// Seamlessly tiling value noise / fBm / Voronoi.
struct TileNoise {
    let seed: UInt64

    @inline(__always) private func lattice(_ x: Int, _ y: Int, _ period: Int) -> Double {
        let wx = ((x % period) + period) % period, wy = ((y % period) + period) % period
        return Double(Hashing.hash(seed, Int32(wx), Int32(wy), Int32(period)) >> 11) / Double(1 << 53)
    }

    /// Value noise in [0,1]; `u`, `v` in [0,1) texture space, `period` lattice cells across the tile.
    func value(_ u: Double, _ v: Double, period: Int) -> Double {
        let x = u * Double(period), y = v * Double(period)
        let xi = Int(floor(x)), yi = Int(floor(y))
        let fx = x - floor(x), fy = y - floor(y)
        let sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy)
        let a = lattice(xi, yi, period), b = lattice(xi + 1, yi, period)
        let c = lattice(xi, yi + 1, period), d = lattice(xi + 1, yi + 1, period)
        return (a + (b - a) * sx) + ((c + (d - c) * sx) - (a + (b - a) * sx)) * sy
    }

    func fbm(_ u: Double, _ v: Double, period: Int, octaves: Int = 4) -> Double {
        var sum = 0.0, amp = 0.5, norm = 0.0, p = period
        for o in 0..<octaves {
            sum += TileNoise(seed: seed &+ UInt64(o) &* 7919).value(u, v, period: p) * amp
            norm += amp
            amp *= 0.5
            p *= 2
        }
        return sum / norm
    }

    /// Tileable Voronoi: (distance to nearest, distance to second nearest, nearest cell id), distances in cell units.
    func voronoi(_ u: Double, _ v: Double, cells: Int) -> (Double, Double, UInt64) {
        let x = u * Double(cells), y = v * Double(cells)
        let xi = Int(floor(x)), yi = Int(floor(y))
        var d1 = 9.0, d2 = 9.0, id: UInt64 = 0
        for oy in -1...1 {
            for ox in -1...1 {
                let cx = xi + ox, cy = yi + oy
                let wx = ((cx % cells) + cells) % cells, wy = ((cy % cells) + cells) % cells
                let h = Hashing.hash(seed, Int32(wx), Int32(wy), 77)
                let jx = Double(h & 0xFFFF) / 65535 * 0.8 + 0.1
                let jy = Double((h >> 16) & 0xFFFF) / 65535 * 0.8 + 0.1
                let dx = Double(cx) + jx - x, dy = Double(cy) + jy - y
                let d = sqrt(dx * dx + dy * dy)
                if d < d1 { d2 = d1; d1 = d; id = h } else if d < d2 { d2 = d }
            }
        }
        return (d1, d2, id)
    }
}

struct Palette {
    let colors: [RGBA]
    init(_ hexes: [UInt32]) { colors = hexes.map { RGBA(hex: $0) } }
    /// Picks along the palette ramp for t in [0,1].
    func ramp(_ t: Double) -> RGBA {
        let tt = max(0, min(0.9999, t)) * Double(colors.count - 1)
        let i = Int(tt)
        return colors[i].mix(colors[min(colors.count - 1, i + 1)], tt - Double(i))
    }
    /// Quantised pick (crisper pixel-art look).
    func step(_ t: Double) -> RGBA {
        colors[max(0, min(colors.count - 1, Int(t * Double(colors.count))))]
    }
}
