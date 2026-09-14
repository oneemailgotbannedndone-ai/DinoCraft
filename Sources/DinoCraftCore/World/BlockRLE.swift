import Foundation

/// Portable run-length codec for chunk block arrays. Unlike LZFSE it works on every
/// platform, so Mac and Windows players can share saves and multiplayer chunks.
///
/// The stream is a sequence of tokens:
/// - `0xxxxxxx`: copy the next `x + 1` bytes as they are.
/// - `1xxxxxxx`: repeat the next byte `x + 3` times. When `x` is 127 a little-endian
///   UInt16 follows and is added to the count, so one token covers up to 65,665 bytes.
enum BlockRLE {
    private static let maxRun = 3 + 127 + Int(UInt16.max)

    static func encode(_ src: UnsafeBufferPointer<UInt8>) -> Data {
        var out: [UInt8] = []
        out.reserveCapacity(4096)
        let n = src.count
        var i = 0
        var literalStart = 0

        func flushLiterals(upTo end: Int) {
            var s = literalStart
            while s < end {
                let count = min(128, end - s)
                out.append(UInt8(count - 1))
                out.append(contentsOf: src[s..<(s + count)])
                s += count
            }
        }

        while i < n {
            let value = src[i]
            var run = 1
            while i + run < n && src[i + run] == value && run < maxRun { run += 1 }
            if run >= 3 {
                flushLiterals(upTo: i)
                let x = run - 3
                if x < 127 {
                    out.append(0x80 | UInt8(x))
                } else {
                    let extra = UInt16(x - 127)
                    out.append(0xFF)
                    out.append(UInt8(extra & 0xFF))
                    out.append(UInt8(extra >> 8))
                }
                out.append(value)
                i += run
                literalStart = i
            } else {
                i += run
            }
        }
        flushLiterals(upTo: n)
        return Data(out)
    }

    /// Decodes into `dst`. Returns the number of bytes written, or nil if the stream is malformed.
    static func decode(_ data: Data, into dst: UnsafeMutablePointer<UInt8>, capacity: Int) -> Int? {
        data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int? in
            let n = src.count
            var i = 0, o = 0
            while i < n {
                let token = src[i]
                i += 1
                if token & 0x80 == 0 {
                    let count = Int(token) + 1
                    guard i + count <= n, o + count <= capacity else { return nil }
                    for k in 0..<count { dst[o + k] = src[i + k] }
                    i += count
                    o += count
                } else {
                    var x = Int(token & 0x7F)
                    if x == 127 {
                        guard i + 2 <= n else { return nil }
                        x += Int(src[i]) | Int(src[i + 1]) << 8
                        i += 2
                    }
                    let count = x + 3
                    guard i < n, o + count <= capacity else { return nil }
                    (dst + o).initialize(repeating: src[i], count: count)
                    i += 1
                    o += count
                }
            }
            return o
        }
    }
}
