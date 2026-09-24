import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

enum FontFace: Int {
    case body = 0      // the 5×7 pixel font
    case display = 1   // the pixel font in bold (each pixel doubled to the right)
}

struct Glyph {
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
    /// Quad top-left relative to the pen on the baseline (em units, y down).
    var offset: SIMD2<Float>
    var size: SIMD2<Float>
    var advance: Float
}

/// Signed-distance-field glyph atlas built at startup from DinoCraft's 5×7 pixel font
/// (`PixelFont`, the same letters the Windows version draws). SDF text stays crisp at every
/// size and Retina scale from a single texture and supports cheap shadows and outlines in the shader.
final class FontAtlas {
    /// Atlas texels per font pixel.
    static let texelsPerPixel = 8
    /// Font pixels per em: 7-pixel capitals are 0.7 em tall, like the system font they replace.
    static let pixelsPerEm = 10
    static let sourceSize = Float(texelsPerPixel * pixelsPerEm)
    static let padding = 8
    static let spread: Float = 7

    let texture: MTLTexture
    private var glyphs: [[UInt32: Glyph]] = [[:], [:]]
    private(set) var ascent: [Float] = [0, 0]
    private(set) var descent: [Float] = [0, 0]
    private(set) var capHeight: [Float] = [0, 0]

    static let characters: String = {
        var s = ""
        for v in 32...126 { s.unicodeScalars.append(UnicodeScalar(v)!) }
        let extra = "•…–—©×✓✗←→↑↓°·★♪♥●○▸’‘“”éèêáàüöäñ€£±÷≈∞"
        return s + String(extra.filter { PixelFont.hasGlyph($0) })
    }()

    enum FontError: Error { case atlasFull, textureFailed }

    init(device: MTLDevice) throws {
        let t0 = Date.timeIntervalSinceReferenceDate
        let width = 2048, height = 1024
        var atlas = [UInt8](repeating: 0, count: width * height)
        var penX = 1, penY = 1, rowH = 0
        let size = FontAtlas.sourceSize
        let em = Float(FontAtlas.pixelsPerEm)

        for face in [FontFace.body, .display] {
            let bold = face == .display
            // Line metrics match the system font this replaced, so every screen keeps its layout.
            ascent[face.rawValue] = 9.5 / em
            descent[face.rawValue] = 2.4 / em
            capHeight[face.rawValue] = Float(PixelFont.height) / em
            let advance = Float(PixelFont.advance + (bold ? 1 : 0)) / em

            for scalar in FontAtlas.characters.unicodeScalars {
                let character = Character(scalar)
                let rows = PixelFont.rows(for: character)
                if scalar == " " || rows.allSatisfy({ $0 == 0 }) {
                    glyphs[face.rawValue][scalar.value] = Glyph(uvMin: .zero, uvMax: .zero, offset: .zero, size: .zero, advance: advance)
                    continue
                }
                let cell = FontAtlas.rasterize(rows, bold: bold)
                let gw = cell.width, gh = cell.height
                if penX + gw + 1 > width { penX = 1; penY += rowH + 1; rowH = 0 }
                guard penY + gh + 1 < height else { throw FontError.atlasFull }

                let sdf = FontAtlas.signedDistance(cell.coverage, w: gw, h: gh, spread: FontAtlas.spread)
                for y in 0..<gh {
                    for x in 0..<gw {
                        atlas[(penY + y) * width + penX + x] = sdf[y * gw + x]
                    }
                }
                let pad = Float(FontAtlas.padding)
                let uvMin = SIMD2<Float>(Float(penX) / Float(width), Float(penY) / Float(height))
                let uvMax = SIMD2<Float>(Float(penX + gw) / Float(width), Float(penY + gh) / Float(height))
                // The glyph's bottom row sits on the baseline.
                let top = Float(PixelFont.height * FontAtlas.texelsPerPixel)
                let offset = SIMD2<Float>(-pad / size, -(top + pad) / size)
                glyphs[face.rawValue][scalar.value] = Glyph(uvMin: uvMin, uvMax: uvMax, offset: offset,
                                                            size: SIMD2(Float(gw) / size, Float(gh) / size), advance: advance)
                penX += gw + 1
                rowH = max(rowH, gh)
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { throw FontError.textureFailed }
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: atlas, bytesPerRow: width)
        tex.label = "SDF Pixel Font Atlas"
        texture = tex
        Log.info(String(format: "Font atlas built: %d + %d glyphs in %.0f ms", glyphs[0].count, glyphs[1].count, (Date.timeIntervalSinceReferenceDate - t0) * 1000), category: "UI")
    }

    /// One glyph's coverage (0 or 255) with `padding` empty texels around it. Bold glyphs
    /// repeat every pixel one to the right, so they are one font pixel wider.
    static func rasterize(_ rows: [UInt8], bold: Bool) -> (coverage: [UInt8], width: Int, height: Int) {
        let p = texelsPerPixel, pad = padding
        let columns = PixelFont.width + (bold ? 1 : 0)
        let w = columns * p + pad * 2, h = PixelFont.height * p + pad * 2
        var coverage = [UInt8](repeating: 0, count: w * h)
        for (row, bits) in rows.enumerated() {
            for column in 0..<columns {
                let on = { (c: Int) -> Bool in c >= 0 && c < PixelFont.width && bits & (UInt8(16) >> UInt8(c)) != 0 }
                guard on(column) || (bold && on(column - 1)) else { continue }
                for y in 0..<p {
                    let base = (pad + row * p + y) * w + pad + column * p
                    for x in 0..<p { coverage[base + x] = 255 }
                }
            }
        }
        return (coverage, w, h)
    }

    func glyph(_ scalar: UInt32, _ face: FontFace) -> Glyph? {
        glyphs[face.rawValue][scalar] ?? glyphs[face.rawValue][63]   // "?"
    }

    func measure(_ text: String, size: Float, face: FontFace = .body, tracking: Float = 0) -> Float {
        var w: Float = 0
        for s in text.unicodeScalars {
            if let g = glyph(s.value, face) { w += (g.advance + tracking) * size }
        }
        return max(0, w - tracking * size)
    }

    // MARK: Distance transform (Felzenszwalb & Huttenlocher)

    private static func signedDistance(_ coverage: [UInt8], w: Int, h: Int, spread: Float) -> [UInt8] {
        let inf: Float = 1e20
        var outside = [Float](repeating: 0, count: w * h)   // distance to nearest inside pixel
        var inside = [Float](repeating: 0, count: w * h)    // distance to nearest outside pixel
        for i in 0..<(w * h) {
            let isIn = coverage[i] >= 128
            outside[i] = isIn ? 0 : inf
            inside[i] = isIn ? inf : 0
        }
        edt2D(&outside, w: w, h: h)
        edt2D(&inside, w: w, h: h)
        var out = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            // Sub-pixel correction from anti-aliased coverage.
            let cov = Float(coverage[i]) / 255
            let sd = sqrt(outside[i]) - sqrt(inside[i]) - (cov - 0.5) * (coverage[i] > 0 && coverage[i] < 255 ? 1 : 0)
            let v = 0.5 - sd / (2 * spread)
            out[i] = UInt8(max(0, min(255, (v * 255).rounded())))
        }
        return out
    }

    private static func edt2D(_ grid: inout [Float], w: Int, h: Int) {
        let n = max(w, h)
        var f = [Float](repeating: 0, count: n), d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n), z = [Float](repeating: 0, count: n + 1)
        for x in 0..<w {
            for y in 0..<h { f[y] = grid[y * w + x] }
            edt1D(f, h, &d, &v, &z)
            for y in 0..<h { grid[y * w + x] = d[y] }
        }
        for y in 0..<h {
            for x in 0..<w { f[x] = grid[y * w + x] }
            edt1D(f, w, &d, &v, &z)
            for x in 0..<w { grid[y * w + x] = d[x] }
        }
    }

    private static func edt1D(_ f: [Float], _ n: Int, _ d: inout [Float], _ v: inout [Int], _ z: inout [Float]) {
        var k = 0
        v[0] = 0
        z[0] = -.greatestFiniteMagnitude
        z[1] = .greatestFiniteMagnitude
        if n > 1 {
            for q in 1..<n {
                var s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * q - 2 * v[k])
                while s <= z[k] {
                    k -= 1
                    s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k]))) / Float(2 * q - 2 * v[k])
                }
                k += 1
                v[k] = q
                z[k] = s
                z[k + 1] = .greatestFiniteMagnitude
            }
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            let dq = Float(q - v[k])
            d[q] = dq * dq + f[v[k]]
        }
    }
}
