import Foundation
import AVFAudio
import DinoCraftCore

let SR = 44100.0

struct Noise {
    var rng: SplitMix64
    var brown: Float = 0
    var pinkB: (Float, Float, Float) = (0, 0, 0)
    init(_ seed: UInt64) { rng = SplitMix64(seed: seed) }

    mutating func white() -> Float { rng.nextFloat() * 2 - 1 }
    mutating func brownian() -> Float {
        brown = (brown + white() * 0.02) * 0.998
        return brown * 3.5
    }
    mutating func pink() -> Float {
        let w = white()
        pinkB.0 = 0.99765 * pinkB.0 + w * 0.0990460
        pinkB.1 = 0.96300 * pinkB.1 + w * 0.2965164
        pinkB.2 = 0.57000 * pinkB.2 + w * 1.0526913
        return (pinkB.0 + pinkB.1 + pinkB.2 + w * 0.1848) * 0.2
    }
    mutating func unit() -> Double { rng.nextDouble() }
}

/// RBJ cookbook biquad (transposed direct form II).
struct Biquad {
    var b0: Float = 1, b1: Float = 0, b2: Float = 0, a1: Float = 0, a2: Float = 0
    var z1: Float = 0, z2: Float = 0

    enum Kind { case lowpass, highpass, bandpass }

    init(_ kind: Kind, freq: Double, q: Double = 0.707) { set(kind, freq: freq, q: q) }

    mutating func set(_ kind: Kind, freq: Double, q: Double) {
        let w0 = 2 * Double.pi * min(freq, SR * 0.45) / SR
        let alpha = sin(w0) / (2 * q), c = cos(w0)
        var nb0: Double, nb1: Double, nb2: Double
        switch kind {
        case .lowpass: nb0 = (1 - c) / 2; nb1 = 1 - c; nb2 = (1 - c) / 2
        case .highpass: nb0 = (1 + c) / 2; nb1 = -(1 + c); nb2 = (1 + c) / 2
        case .bandpass: nb0 = alpha; nb1 = 0; nb2 = -alpha
        }
        let a0 = 1 + alpha
        b0 = Float(nb0 / a0); b1 = Float(nb1 / a0); b2 = Float(nb2 / a0)
        a1 = Float(-2 * c / a0); a2 = Float((1 - alpha) / a0)
    }

    @inline(__always) mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}

/// Freeverb-style mono reverb (4 damped combs + 2 allpasses).
struct Reverb {
    private var combs: [[Float]], combIdx: [Int], combStore: [Float]
    private var allpasses: [[Float]], apIdx: [Int]
    var feedback: Float, damp: Float

    init(size: Double = 1.0, feedback: Float = 0.84, damp: Float = 0.3, spread: Int = 0) {
        let combLens = [1116, 1188, 1277, 1356].map { Int(Double($0 + spread) * size) }
        let apLens = [556, 441].map { $0 + spread }
        combs = combLens.map { [Float](repeating: 0, count: $0) }
        combIdx = [0, 0, 0, 0]; combStore = [0, 0, 0, 0]
        allpasses = apLens.map { [Float](repeating: 0, count: $0) }
        apIdx = [0, 0]
        self.feedback = feedback; self.damp = damp
    }

    mutating func process(_ x: Float) -> Float {
        var out: Float = 0
        for i in 0..<4 {
            let y = combs[i][combIdx[i]]
            combStore[i] = y * (1 - damp) + combStore[i] * damp
            combs[i][combIdx[i]] = x + combStore[i] * feedback
            combIdx[i] += 1
            if combIdx[i] == combs[i].count { combIdx[i] = 0 }
            out += y
        }
        for i in 0..<2 {
            let buf = allpasses[i][apIdx[i]]
            let y = -out + buf
            allpasses[i][apIdx[i]] = out + buf * 0.5
            apIdx[i] += 1
            if apIdx[i] == allpasses[i].count { apIdx[i] = 0 }
            out = y
        }
        return out * 0.25
    }
}

enum AudioIO {
    static func normalize(_ s: inout [Float], peak: Float) {
        let m = s.reduce(Float(0)) { max($0, abs($1)) }
        guard m > 0 else { return }
        let k = peak / m
        for i in s.indices { s[i] *= k }
    }

    static func fade(_ s: inout [Float], inSeconds: Double, outSeconds: Double) {
        let fi = min(s.count, Int(inSeconds * SR)), fo = min(s.count, Int(outSeconds * SR))
        for i in 0..<fi { s[i] *= Float(i) / Float(max(1, fi)) }
        for i in 0..<fo { s[s.count - 1 - i] *= Float(i) / Float(max(1, fo)) }
    }

    /// Makes a loop seamless by cross-fading the tail into the head.
    static func makeLoop(_ s: [Float], crossfadeSeconds: Double) -> [Float] {
        let n = Int(crossfadeSeconds * SR)
        guard s.count > n * 2 else { return s }
        var out = Array(s[0..<(s.count - n)])
        for i in 0..<n {
            let t = Float(i) / Float(n)
            out[i] = out[i] * t + s[s.count - n + i] * (1 - t)
        }
        return out
    }

    /// 16-bit PCM mono WAV.
    static func writeWAV(_ samples: [Float], to url: URL) throws {
        var data = Data()
        let count = samples.count
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + count * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(count * 2))
        data.reserveCapacity(44 + count * 2)
        for s in samples {
            let v = Int16(max(-32767, min(32767, (s * 32767).rounded())))
            u16(UInt16(bitPattern: v))
        }
        try data.write(to: url, options: .atomic)
    }

    /// Stereo AAC (.m4a) via AVAudioFile.
    static func writeM4A(left: [Float], right: [Float], to url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 160_000,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let block = 32_768
        var offset = 0
        while offset < left.count {
            let n = min(block, left.count - offset)
            guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(n)) else { break }
            buf.frameLength = AVAudioFrameCount(n)
            left.withUnsafeBufferPointer { src in buf.floatChannelData![0].update(from: src.baseAddress! + offset, count: n) }
            right.withUnsafeBufferPointer { src in buf.floatChannelData![1].update(from: src.baseAddress! + offset, count: n) }
            try file.write(from: buf)
            offset += n
        }
    }
}
