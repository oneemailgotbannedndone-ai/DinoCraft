import AppKit
import CoreText
import Metal
import simd
import DinoCraftCore

enum FontFace: Int {
    case body = 0      // SF Pro Rounded Semibold
    case display = 1   // SF Pro Rounded Heavy
}

struct Glyph {
    var uvMin: SIMD2<Float>
    var uvMax: SIMD2<Float>
    /// Quad top-left relative to the pen on the baseline (em units, y down).
    var offset: SIMD2<Float>
    var size: SIMD2<Float>
    var advance: Float
}

/// Signed-distance-field glyph atlas rendered from the system rounded font at
/// startup. SDF text stays crisp at every size and Retina scale from a single
/// texture and supports cheap shadows and outlines in the shader.
final class FontAtlas {
    static let sourceSize: CGFloat = 56
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
        return s + "•…–—©×✓←→↑↓°·★♪♥●○’‘“”éèêáàüöäñ€£¥§¶±÷≈∞"
    }()

    enum FontError: Error { case atlasFull, textureFailed }

    init(device: MTLDevice) throws {
        let t0 = CFAbsoluteTimeGetCurrent()
        let width = 2048, height = 2048
        var atlas = [UInt8](repeating: 0, count: width * height)
        var penX = 1, penY = 1, rowH = 0

        for face in [FontFace.body, .display] {
            let font = FontAtlas.makeFont(face)
            let size = Float(FontAtlas.sourceSize)
            ascent[face.rawValue] = Float(CTFontGetAscent(font)) / size
            descent[face.rawValue] = Float(CTFontGetDescent(font)) / size
            capHeight[face.rawValue] = Float(CTFontGetCapHeight(font)) / size

            for scalar in FontAtlas.characters.unicodeScalars {
                var utf16 = Array(String(scalar).utf16)
                var cgGlyphs = [CGGlyph](repeating: 0, count: utf16.count)
                guard CTFontGetGlyphsForCharacters(font, &utf16, &cgGlyphs, utf16.count), cgGlyphs[0] != 0 else { continue }
                var glyph = cgGlyphs[0]
                var bbox = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(font, .default, &glyph, &bbox, 1)
                var adv = CGSize.zero
                CTFontGetAdvancesForGlyphs(font, .default, &glyph, &adv, 1)

                let pad = FontAtlas.padding
                let gw = max(1, Int(ceil(bbox.width))) + pad * 2
                let gh = max(1, Int(ceil(bbox.height))) + pad * 2
                if scalar == " " || bbox.isEmpty {
                    glyphs[face.rawValue][scalar.value] = Glyph(uvMin: .zero, uvMax: .zero, offset: .zero, size: .zero,
                                                                advance: Float(adv.width) / size)
                    continue
                }
                if penX + gw + 1 > width { penX = 1; penY += rowH + 1; rowH = 0 }
                guard penY + gh + 1 < height else { throw FontError.atlasFull }

                // Rasterise coverage
                var coverage = [UInt8](repeating: 0, count: gw * gh)
                let drawn = coverage.withUnsafeMutableBytes { raw -> Bool in
                    guard let ctx = CGContext(data: raw.baseAddress, width: gw, height: gh, bitsPerComponent: 8, bytesPerRow: gw,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
                    ctx.setFillColor(gray: 1, alpha: 1)
                    ctx.setShouldAntialias(true)
                    var position = CGPoint(x: CGFloat(pad) - bbox.minX, y: CGFloat(pad) - bbox.minY)
                    CTFontDrawGlyphs(font, &glyph, &position, 1, ctx)
                    return true
                }
                guard drawn else { continue }

                let sdf = FontAtlas.signedDistance(coverage, w: gw, h: gh, spread: FontAtlas.spread)
                for y in 0..<gh {
                    for x in 0..<gw {
                        atlas[(penY + y) * width + penX + x] = sdf[y * gw + x]
                    }
                }
                let uvMin = SIMD2<Float>(Float(penX) / Float(width), Float(penY) / Float(height))
                let uvMax = SIMD2<Float>(Float(penX + gw) / Float(width), Float(penY + gh) / Float(height))
                let offset = SIMD2<Float>((Float(bbox.minX) - Float(pad)) / size, -(Float(bbox.maxY) + Float(pad)) / size)
                glyphs[face.rawValue][scalar.value] = Glyph(uvMin: uvMin, uvMax: uvMax, offset: offset,
                                                            size: SIMD2(Float(gw) / size, Float(gh) / size),
                                                            advance: Float(adv.width) / size)
                penX += gw + 1
                rowH = max(rowH, gh)
            }
        }

        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { throw FontError.textureFailed }
        tex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: atlas, bytesPerRow: width)
        tex.label = "SDF Font Atlas"
        texture = tex
        Log.info(String(format: "Font atlas built: %d + %d glyphs in %.0f ms", glyphs[0].count, glyphs[1].count, (CFAbsoluteTimeGetCurrent() - t0) * 1000), category: "UI")
    }

    static func makeFont(_ face: FontFace) -> CTFont {
        let weight: NSFont.Weight = face == .display ? .heavy : .semibold
        let base = NSFont.systemFont(ofSize: sourceSize, weight: weight)
        if let rounded = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: rounded, size: sourceSize) {
            return f as CTFont
        }
        return base as CTFont
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
