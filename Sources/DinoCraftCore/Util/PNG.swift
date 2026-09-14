import Foundation

/// Minimal PNG reader and writer in pure Swift, so textures load and screenshots
/// save on platforms without ImageIO (Windows). Reads 8-bit, non-interlaced
/// grayscale, RGB, palette and alpha images, which covers everything DinoCraft's
/// asset tools produce. Writes uncompressed (stored) RGBA images.
public enum PNG {
    public struct Image: Sendable {
        public let width: Int
        public let height: Int
        /// Straight (non-premultiplied) RGBA bytes, row 0 at the top.
        public var rgba: [UInt8]

        public init(width: Int, height: Int, rgba: [UInt8]) {
            self.width = width
            self.height = height
            self.rgba = rgba
        }
    }

    public enum PNGError: Error, CustomStringConvertible {
        case notPNG
        case unsupported(String)
        case corrupt(String)

        public var description: String {
            switch self {
            case .notPNG: return "not a PNG file"
            case .unsupported(let what): return "unsupported PNG (\(what))"
            case .corrupt(let what): return "damaged PNG (\(what))"
            }
        }
    }

    private static let signature: [UInt8] = [137, 80, 78, 71, 13, 10, 26, 10]

    // MARK: Decoding

    public static func decode(_ data: Data) throws -> Image {
        let bytes = [UInt8](data)
        guard bytes.count > 33, Array(bytes[0..<8]) == signature else { throw PNGError.notPNG }

        func u32(_ i: Int) -> Int { Int(bytes[i]) << 24 | Int(bytes[i + 1]) << 16 | Int(bytes[i + 2]) << 8 | Int(bytes[i + 3]) }

        var width = 0, height = 0, bitDepth = 0, colorType = -1, interlace = 0
        var palette: [UInt8] = [], transparency: [UInt8] = [], compressed: [UInt8] = []
        var pos = 8
        chunks: while pos + 12 <= bytes.count {
            let length = u32(pos)
            let start = pos + 8
            guard start + length + 4 <= bytes.count else { throw PNGError.corrupt("chunk overruns the file") }
            let type = String(decoding: bytes[(pos + 4)..<start], as: UTF8.self)
            switch type {
            case "IHDR":
                guard length >= 13 else { throw PNGError.corrupt("short header") }
                width = u32(start)
                height = u32(start + 4)
                bitDepth = Int(bytes[start + 8])
                colorType = Int(bytes[start + 9])
                interlace = Int(bytes[start + 12])
            case "PLTE": palette = Array(bytes[start..<(start + length)])
            case "tRNS": transparency = Array(bytes[start..<(start + length)])
            case "IDAT": compressed.append(contentsOf: bytes[start..<(start + length)])
            case "IEND": break chunks
            default: break
            }
            pos = start + length + 4
        }

        guard width > 0, height > 0, width <= 16384, height <= 16384 else { throw PNGError.corrupt("bad size \(width)×\(height)") }
        guard bitDepth == 8 else { throw PNGError.unsupported("bit depth \(bitDepth)") }
        guard interlace == 0 else { throw PNGError.unsupported("interlaced") }
        let channels: Int
        switch colorType {
        case 0: channels = 1
        case 2: channels = 3
        case 3: channels = 1
        case 4: channels = 2
        case 6: channels = 4
        default: throw PNGError.unsupported("color type \(colorType)")
        }

        let stride = width * channels
        let raw = try Inflate.zlib(compressed, expectedSize: height * (stride + 1))
        guard raw.count >= height * (stride + 1) else { throw PNGError.corrupt("image data too short") }

        // Undo the per-row filters.
        var pixels = [UInt8](repeating: 0, count: height * stride)
        for y in 0..<height {
            let filter = raw[y * (stride + 1)]
            let src = y * (stride + 1) + 1
            let dst = y * stride
            for x in 0..<stride {
                let a = x >= channels ? Int(pixels[dst + x - channels]) : 0
                let b = y > 0 ? Int(pixels[dst - stride + x]) : 0
                let c = (y > 0 && x >= channels) ? Int(pixels[dst - stride + x - channels]) : 0
                let r = Int(raw[src + x])
                let value: Int
                switch filter {
                case 0: value = r
                case 1: value = r + a
                case 2: value = r + b
                case 3: value = r + (a + b) / 2
                case 4:
                    let p = a + b - c
                    let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
                    value = r + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))
                default: throw PNGError.corrupt("unknown row filter \(filter)")
                }
                pixels[dst + x] = UInt8(truncatingIfNeeded: value)
            }
        }

        var rgba = [UInt8](repeating: 255, count: width * height * 4)
        for i in 0..<(width * height) {
            let s = i * channels, d = i * 4
            switch colorType {
            case 0:
                rgba[d] = pixels[s]; rgba[d + 1] = pixels[s]; rgba[d + 2] = pixels[s]
            case 2:
                rgba[d] = pixels[s]; rgba[d + 1] = pixels[s + 1]; rgba[d + 2] = pixels[s + 2]
            case 3:
                let index = Int(pixels[s])
                guard index * 3 + 2 < palette.count else { throw PNGError.corrupt("palette index out of range") }
                rgba[d] = palette[index * 3]; rgba[d + 1] = palette[index * 3 + 1]; rgba[d + 2] = palette[index * 3 + 2]
                rgba[d + 3] = index < transparency.count ? transparency[index] : 255
            case 4:
                rgba[d] = pixels[s]; rgba[d + 1] = pixels[s]; rgba[d + 2] = pixels[s]; rgba[d + 3] = pixels[s + 1]
            default:
                rgba[d] = pixels[s]; rgba[d + 1] = pixels[s + 1]; rgba[d + 2] = pixels[s + 2]; rgba[d + 3] = pixels[s + 3]
            }
        }
        return Image(width: width, height: height, rgba: rgba)
    }

    // MARK: Encoding

    /// Encodes straight RGBA (row 0 at the top) as an uncompressed PNG.
    public static func encode(width: Int, height: Int, rgba: [UInt8]) -> Data {
        precondition(rgba.count >= width * height * 4, "not enough pixel data")
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (width * 4 + 1))
        for y in 0..<height {
            raw.append(0)
            raw.append(contentsOf: rgba[(y * width * 4)..<((y + 1) * width * 4)])
        }

        var zlib: [UInt8] = [0x78, 0x01]
        var i = 0
        repeat {
            let n = min(65535, raw.count - i)
            let last = i + n >= raw.count
            zlib.append(last ? 1 : 0)
            zlib.append(UInt8(n & 0xFF)); zlib.append(UInt8(n >> 8))
            zlib.append(UInt8(truncatingIfNeeded: ~n)); zlib.append(UInt8(truncatingIfNeeded: ~n >> 8))
            zlib.append(contentsOf: raw[i..<(i + n)])
            i += n
        } while i < raw.count
        var s1: UInt32 = 1, s2: UInt32 = 0
        for byte in raw {
            s1 = (s1 + UInt32(byte)) % 65521
            s2 = (s2 + s1) % 65521
        }
        let adler = s2 << 16 | s1
        zlib.append(contentsOf: [UInt8(adler >> 24), UInt8((adler >> 16) & 0xFF), UInt8((adler >> 8) & 0xFF), UInt8(adler & 0xFF)])

        var out = signature
        func chunk(_ type: String, _ body: [UInt8]) {
            let typeBytes = Array(type.utf8)
            let n = UInt32(body.count)
            out.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
            out.append(contentsOf: typeBytes)
            out.append(contentsOf: body)
            let crc = crc32(typeBytes + body)
            out.append(contentsOf: [UInt8(crc >> 24), UInt8((crc >> 16) & 0xFF), UInt8((crc >> 8) & 0xFF), UInt8(crc & 0xFF)])
        }
        let w = UInt32(width), h = UInt32(height)
        chunk("IHDR", [UInt8(w >> 24), UInt8((w >> 16) & 0xFF), UInt8((w >> 8) & 0xFF), UInt8(w & 0xFF),
                       UInt8(h >> 24), UInt8((h >> 16) & 0xFF), UInt8((h >> 8) & 0xFF), UInt8(h & 0xFF),
                       8, 6, 0, 0, 0])
        chunk("IDAT", zlib)
        chunk("IEND", [])
        return Data(out)
    }

    private static let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }
}

/// DEFLATE decompressor (RFC 1951) in the style of zlib's "puff" reference decoder.
enum Inflate {
    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int]

        init(lengths: [Int]) {
            symbols = [Int](repeating: 0, count: max(1, lengths.count))
            for l in lengths { counts[l] += 1 }
            var offsets = [Int](repeating: 0, count: 16)
            for len in 1..<15 { offsets[len + 1] = offsets[len] + counts[len] }
            for (symbol, l) in lengths.enumerated() where l != 0 {
                symbols[offsets[l]] = symbol
                offsets[l] += 1
            }
        }
    }

    private struct Reader {
        let src: [UInt8]
        var pos: Int
        var bitBuffer = 0
        var bitCount = 0

        mutating func bits(_ need: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < need {
                guard pos < src.count else { throw PNG.PNGError.corrupt("compressed data ends early") }
                value |= Int(src[pos]) << bitCount
                pos += 1
                bitCount += 8
            }
            bitBuffer = value >> need
            bitCount -= need
            return value & ((1 << need) - 1)
        }

        mutating func decode(_ h: Huffman) throws -> Int {
            var code = 0, first = 0, index = 0
            for len in 1...15 {
                code |= try bits(1)
                let count = h.counts[len]
                if code - count < first { return h.symbols[index + (code - first)] }
                index += count
                first += count
                first <<= 1
                code <<= 1
            }
            throw PNG.PNGError.corrupt("invalid Huffman code")
        }
    }

    private static let lengthBase = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
    private static let lengthExtra = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
    private static let distanceBase = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
                                       2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
    private static let distanceExtra = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

    private static let fixed: (Huffman, Huffman) = {
        var lengths = [Int](repeating: 8, count: 288)
        for i in 144..<256 { lengths[i] = 9 }
        for i in 256..<280 { lengths[i] = 7 }
        return (Huffman(lengths: lengths), Huffman(lengths: [Int](repeating: 5, count: 30)))
    }()

    /// Decompresses a zlib stream (2-byte header, DEFLATE data; the checksum is not verified).
    static func zlib(_ src: [UInt8], expectedSize: Int = 0) throws -> [UInt8] {
        guard src.count >= 2, src[0] & 0x0F == 8, (Int(src[0]) << 8 | Int(src[1])) % 31 == 0 else {
            throw PNG.PNGError.corrupt("bad zlib header")
        }
        var reader = Reader(src: src, pos: 2)
        var out: [UInt8] = []
        out.reserveCapacity(expectedSize)
        var last = false
        while !last {
            last = try reader.bits(1) == 1
            switch try reader.bits(2) {
            case 0: try stored(&reader, &out)
            case 1: try codes(&reader, &out, fixed.0, fixed.1)
            case 2:
                let (lengthCode, distanceCode) = try dynamicTables(&reader)
                try codes(&reader, &out, lengthCode, distanceCode)
            default: throw PNG.PNGError.corrupt("invalid block type")
            }
        }
        return out
    }

    private static func stored(_ r: inout Reader, _ out: inout [UInt8]) throws {
        r.bitBuffer = 0
        r.bitCount = 0
        guard r.pos + 4 <= r.src.count else { throw PNG.PNGError.corrupt("stored block header") }
        let len = Int(r.src[r.pos]) | Int(r.src[r.pos + 1]) << 8
        let nlen = Int(r.src[r.pos + 2]) | Int(r.src[r.pos + 3]) << 8
        guard len == (~nlen & 0xFFFF) else { throw PNG.PNGError.corrupt("stored block length") }
        r.pos += 4
        guard r.pos + len <= r.src.count else { throw PNG.PNGError.corrupt("stored block data") }
        out.append(contentsOf: r.src[r.pos..<(r.pos + len)])
        r.pos += len
    }

    private static func codes(_ r: inout Reader, _ out: inout [UInt8], _ lengthCode: Huffman, _ distanceCode: Huffman) throws {
        while true {
            var symbol = try r.decode(lengthCode)
            if symbol < 256 {
                out.append(UInt8(symbol))
            } else if symbol == 256 {
                return
            } else {
                symbol -= 257
                guard symbol < 29 else { throw PNG.PNGError.corrupt("invalid length symbol") }
                let length = lengthBase[symbol] + (try r.bits(lengthExtra[symbol]))
                let d = try r.decode(distanceCode)
                guard d < 30 else { throw PNG.PNGError.corrupt("invalid distance symbol") }
                let distance = distanceBase[d] + (try r.bits(distanceExtra[d]))
                guard distance <= out.count else { throw PNG.PNGError.corrupt("distance too far back") }
                let start = out.count - distance
                for k in 0..<length { out.append(out[start + k]) }
            }
        }
    }

    private static func dynamicTables(_ r: inout Reader) throws -> (Huffman, Huffman) {
        let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
        let nlen = try r.bits(5) + 257
        let ndist = try r.bits(5) + 1
        let ncode = try r.bits(4) + 4
        guard nlen <= 286, ndist <= 30 else { throw PNG.PNGError.corrupt("too many codes") }

        var codeLengths = [Int](repeating: 0, count: 19)
        for i in 0..<ncode { codeLengths[order[i]] = try r.bits(3) }
        let lengthsCode = Huffman(lengths: codeLengths)

        var lengths = [Int](repeating: 0, count: nlen + ndist)
        var index = 0
        while index < nlen + ndist {
            let symbol = try r.decode(lengthsCode)
            if symbol < 16 {
                lengths[index] = symbol
                index += 1
            } else {
                var value = 0, repeatCount: Int
                switch symbol {
                case 16:
                    guard index > 0 else { throw PNG.PNGError.corrupt("repeat with no previous length") }
                    value = lengths[index - 1]
                    repeatCount = 3 + (try r.bits(2))
                case 17: repeatCount = 3 + (try r.bits(3))
                default: repeatCount = 11 + (try r.bits(7))
                }
                guard index + repeatCount <= nlen + ndist else { throw PNG.PNGError.corrupt("too many lengths") }
                for _ in 0..<repeatCount {
                    lengths[index] = value
                    index += 1
                }
            }
        }
        guard lengths[256] != 0 else { throw PNG.PNGError.corrupt("missing end-of-block code") }
        return (Huffman(lengths: Array(lengths[0..<nlen])), Huffman(lengths: Array(lengths[nlen...])))
    }
}
