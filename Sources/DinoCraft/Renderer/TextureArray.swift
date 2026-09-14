import Foundation
import Metal
import CoreGraphics
import ImageIO
import DinoCraftCore

/// Loads a set of same-sized PNG images into one `texture2d_array` with a
/// gamma-correct, premultiplied mip chain. Alpha-tested textures (leaves,
/// plants) get coverage-preserving mips so foliage doesn't thin out with
/// distance.
final class TextureArray {
    let texture: MTLTexture
    let index: [String: UInt16]
    let names: [String]
    let size: Int
    /// Level-0 alpha per layer (size × size, row 0 at the top) for building extruded item models.
    let alphaMasks: [[UInt8]]

    enum TextureError: Error, CustomStringConvertible {
        case createFailed(String)
        var description: String {
            switch self { case .createFailed(let s): return "Could not create texture array '\(s)'" }
        }
    }

    private static let toLinear: [Float] = (0..<256).map { i in
        let c = Float(i) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func toSRGB(_ l: Float) -> UInt8 {
        let c = max(0, min(1, l))
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((s * 255).rounded())
    }

    init(device: MTLDevice, label: String, entries: [(name: String, url: URL?)], size: Int, alphaTestNames: Set<String> = []) throws {
        self.size = size
        let levels = Int(log2(Double(size))) + 1
        let desc = MTLTextureDescriptor()
        desc.textureType = .type2DArray
        desc.pixelFormat = .rgba8Unorm_srgb
        desc.width = size
        desc.height = size
        desc.arrayLength = max(1, entries.count)
        desc.mipmapLevelCount = levels
        desc.storageMode = .shared
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { throw TextureError.createFailed(label) }
        tex.label = label
        texture = tex

        var idx: [String: UInt16] = [:]
        var masks: [[UInt8]] = []
        var missing = 0
        for (slice, entry) in entries.enumerated() {
            idx[entry.name] = UInt16(slice)
            var pixels: [Float]   // linear premultiplied RGBA
            if let url = entry.url, let loaded = TextureArray.loadLinearPremultiplied(url: url, size: size) {
                pixels = loaded
            } else {
                missing += 1
                pixels = TextureArray.missingPattern(size: size)
                Log.warning("Texture '\(entry.name)' missing or unreadable; using placeholder", category: "Assets")
            }
            masks.append((0..<(size * size)).map { UInt8(max(0, min(255, (pixels[$0 * 4 + 3] * 255).rounded()))) })
            let alphaTest = alphaTestNames.contains(entry.name)
            let baseCoverage = alphaTest ? TextureArray.coverage(pixels, scale: 1) : 0
            var levelSize = size
            for level in 0..<levels {
                if level > 0 {
                    pixels = TextureArray.downsample(pixels, size: levelSize * 2)
                    if alphaTest { TextureArray.preserveCoverage(&pixels, target: baseCoverage) }
                }
                var bytes = [UInt8](repeating: 0, count: levelSize * levelSize * 4)
                for i in 0..<(levelSize * levelSize) {
                    let a = max(0, min(1, pixels[i * 4 + 3]))
                    bytes[i * 4] = TextureArray.toSRGB(pixels[i * 4])
                    bytes[i * 4 + 1] = TextureArray.toSRGB(pixels[i * 4 + 1])
                    bytes[i * 4 + 2] = TextureArray.toSRGB(pixels[i * 4 + 2])
                    bytes[i * 4 + 3] = UInt8((a * 255).rounded())
                }
                tex.replace(region: MTLRegionMake2D(0, 0, levelSize, levelSize), mipmapLevel: level, slice: slice,
                            withBytes: bytes, bytesPerRow: levelSize * 4, bytesPerImage: levelSize * levelSize * 4)
                levelSize = max(1, levelSize / 2)
            }
        }
        index = idx
        alphaMasks = masks
        names = entries.map { $0.name }
        Log.info("Texture array '\(label)': \(entries.count) layers @ \(size)px, \(levels) mips\(missing > 0 ? ", \(missing) missing" : "")", category: "Assets")
    }

    func layer(_ name: String) -> UInt16 { index[name] ?? 0 }

    private static func loadLinearPremultiplied(url: URL, size: Int) -> [Float]? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
        var out = [Float](repeating: 0, count: size * size * 4)
        for i in 0..<(size * size) {
            let a = Float(bytes[i * 4 + 3]) / 255
            out[i * 4 + 3] = a
            guard a > 0 else { continue }
            for c in 0..<3 {
                // Unpremultiply in encoded space, linearize, premultiply in linear space.
                let encoded = min(255, Int((Float(bytes[i * 4 + c]) / a).rounded()))
                out[i * 4 + c] = toLinear[encoded] * a
            }
        }
        return out
    }

    private static func downsample(_ src: [Float], size: Int) -> [Float] {
        let half = max(1, size / 2)
        var out = [Float](repeating: 0, count: half * half * 4)
        for y in 0..<half {
            for x in 0..<half {
                for c in 0..<4 {
                    var sum: Float = 0
                    for dy in 0..<2 { for dx in 0..<2 {
                        sum += src[((min(size - 1, y * 2 + dy)) * size + min(size - 1, x * 2 + dx)) * 4 + c]
                    } }
                    out[(y * half + x) * 4 + c] = sum / 4
                }
            }
        }
        return out
    }

    private static func coverage(_ px: [Float], scale: Float) -> Float {
        let n = px.count / 4
        var covered = 0
        for i in 0..<n where px[i * 4 + 3] * scale >= 0.5 { covered += 1 }
        return Float(covered) / Float(max(1, n))
    }

    private static func preserveCoverage(_ px: inout [Float], target: Float) {
        var lo: Float = 0.1, hi: Float = 8
        for _ in 0..<16 {
            let mid = (lo + hi) / 2
            if coverage(px, scale: mid) < target { lo = mid } else { hi = mid }
        }
        let s = (lo + hi) / 2
        let n = px.count / 4
        for i in 0..<n {
            let a = px[i * 4 + 3]
            guard a > 0 else { continue }
            let na = min(1, a * s)
            let k = na / a
            px[i * 4] *= k; px[i * 4 + 1] *= k; px[i * 4 + 2] *= k
            px[i * 4 + 3] = na
        }
    }

    private static func missingPattern(size: Int) -> [Float] {
        var out = [Float](repeating: 1, count: size * size * 4)
        for y in 0..<size { for x in 0..<size {
            let on = ((x / max(1, size / 4)) + (y / max(1, size / 4))) % 2 == 0
            out[(y * size + x) * 4] = on ? 1 : 0
            out[(y * size + x) * 4 + 1] = 0
            out[(y * size + x) * 4 + 2] = on ? 1 : 0
        } }
        return out
    }
}
