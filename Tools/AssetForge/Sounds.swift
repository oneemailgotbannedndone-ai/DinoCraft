import Foundation
import DinoCraftCore

/// Synthesizes every DinoCraft sound effect and ambience loop from scratch
/// (filtered noise grains, resonant bodies, additive tones). Fully original.
enum SoundSynth {
    struct Material {
        var band: Double          // grain band-pass centre
        var q: Double
        var lowpass: Double
        var grainDecay: Double    // seconds
        var grainsPerSecond: Double
        var bodyFreq: Double?     // resonant knock
        var bodyGain: Float = 0.5
        var hiss: Float = 0.3     // continuous filtered noise level
        var ring: [Double] = []   // inharmonic partials (glass / metal)
    }

    static let materials: [String: Material] = [
        "stone": Material(band: 2100, q: 1.2, lowpass: 6000, grainDecay: 0.006, grainsPerSecond: 90, bodyFreq: 160, bodyGain: 0.35, hiss: 0.15),
        "grass": Material(band: 4200, q: 0.8, lowpass: 9000, grainDecay: 0.004, grainsPerSecond: 160, bodyFreq: nil, hiss: 0.45),
        "dirt": Material(band: 900, q: 0.9, lowpass: 2200, grainDecay: 0.008, grainsPerSecond: 110, bodyFreq: 95, bodyGain: 0.45, hiss: 0.35),
        "wood": Material(band: 1200, q: 2.5, lowpass: 4000, grainDecay: 0.01, grainsPerSecond: 40, bodyFreq: 210, bodyGain: 0.8, hiss: 0.1),
        "sand": Material(band: 5000, q: 0.6, lowpass: 11000, grainDecay: 0.003, grainsPerSecond: 260, bodyFreq: nil, hiss: 0.6),
        "gravel": Material(band: 1700, q: 1.0, lowpass: 7000, grainDecay: 0.007, grainsPerSecond: 220, bodyFreq: 120, bodyGain: 0.2, hiss: 0.2),
        "leaves": Material(band: 5200, q: 0.9, lowpass: 12000, grainDecay: 0.003, grainsPerSecond: 220, bodyFreq: nil, hiss: 0.5),
        "glass": Material(band: 5200, q: 3.0, lowpass: 14000, grainDecay: 0.004, grainsPerSecond: 50, bodyFreq: nil, hiss: 0.05, ring: [2800, 4130, 6210]),
        "snow": Material(band: 1500, q: 0.7, lowpass: 3500, grainDecay: 0.006, grainsPerSecond: 200, bodyFreq: nil, hiss: 0.5),
        "metal": Material(band: 3000, q: 4.0, lowpass: 12000, grainDecay: 0.005, grainsPerSecond: 30, bodyFreq: 420, bodyGain: 0.3, hiss: 0.05, ring: [1320, 2210, 3480]),
        "water": Material(band: 900, q: 0.8, lowpass: 2500, grainDecay: 0.01, grainsPerSecond: 60, bodyFreq: nil, hiss: 0.5),
    ]

    enum Kind { case step, hit, place, breakBlock }

    static func renderMaterial(_ m: Material, kind: Kind, seed: UInt64) -> [Float] {
        let duration: Double, attack: Double, decay: Double, grainScale: Double
        switch kind {
        case .step: duration = 0.22; attack = 0.004; decay = 0.07; grainScale = 0.6
        case .hit: duration = 0.16; attack = 0.002; decay = 0.045; grainScale = 0.5
        case .place: duration = 0.28; attack = 0.002; decay = 0.08; grainScale = 0.8
        case .breakBlock: duration = 0.55; attack = 0.003; decay = 0.16; grainScale = 1.6
        }
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var bp = Biquad(.bandpass, freq: m.band * (0.85 + noise.unit() * 0.3), q: m.q)
        var lp = Biquad(.lowpass, freq: m.lowpass)
        var grainBP = Biquad(.bandpass, freq: m.band * (0.7 + noise.unit() * 0.6), q: m.q * 1.5)

        // Grain schedule
        var grainEnv: Float = 0
        let grainK = Float(exp(-1 / (m.grainDecay * SR)))
        let density = m.grainsPerSecond * grainScale / SR

        let bodyFreq = (m.bodyFreq ?? 0) * (0.9 + noise.unit() * 0.2)
        let bodyDecay = kind == .place ? 0.09 : 0.05
        var phase = 0.0

        for i in 0..<n {
            let t = Double(i) / SR
            let env = Float(t < attack ? t / attack : exp(-(t - attack) / decay))
            let tail = Float(exp(-t / (duration * 0.45)))
            if noise.unit() < density * Double(tail) * 3 { grainEnv = 0.6 + Float(noise.unit()) * 0.4 }
            grainEnv *= grainK
            let w = noise.white()
            var s = bp.process(w) * m.hiss * env * 2.5
            s += grainBP.process(w * grainEnv) * 3.0 * tail
            if m.bodyFreq != nil {
                phase += 2 * .pi * bodyFreq * (1 - t * 1.2) / SR
                s += Float(sin(phase) * exp(-t / bodyDecay)) * m.bodyGain
            }
            for (k, f) in m.ring.enumerated() {
                s += Float(sin(2 * .pi * f * (1 + Double(k) * 0.003) * t) * exp(-t / (0.08 + Double(k) * 0.02))) * 0.12 * (kind == .breakBlock ? 1.6 : 0.8)
            }
            out[i] = lp.process(s)
        }
        if kind == .breakBlock {
            // Secondary crumble burst
            let start = Int(0.06 * SR)
            var crumble = Noise(seed ^ 0xABCD)
            var cbp = Biquad(.bandpass, freq: m.band * 0.6, q: 0.9)
            for i in start..<n {
                let t = Double(i - start) / SR
                out[i] += cbp.process(crumble.white()) * Float(exp(-t / 0.12)) * m.hiss * 1.5
            }
        }
        AudioIO.normalize(&out, peak: kind == .step ? 0.55 : (kind == .hit ? 0.5 : 0.8))
        AudioIO.fade(&out, inSeconds: 0.001, outSeconds: 0.03)
        return out
    }

    // MARK: - Tonal helpers

    static func tone(_ freqs: [(Double, Double)], duration: Double, decay: Double, attack: Double = 0.003,
                     partials: [(Double, Float)] = [(1, 1)], gain: Float = 0.6) -> [Float] {
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        for (freq, startTime) in freqs {
            let start = Int(startTime * SR)
            for i in start..<n {
                let t = Double(i - start) / SR
                let env = t < attack ? t / attack : exp(-(t - attack) / decay)
                var s = 0.0
                for (mult, amp) in partials {
                    s += sin(2 * .pi * freq * mult * t) * Double(amp) * exp(-t * mult * 0.5)
                }
                out[i] += Float(s * env)
            }
        }
        AudioIO.normalize(&out, peak: gain)
        AudioIO.fade(&out, inSeconds: 0.001, outSeconds: 0.02)
        return out
    }

    static func sweep(from f0: Double, to f1: Double, duration: Double, decay: Double, gain: Float, noiseMix: Float = 0, seed: UInt64 = 1) -> [Float] {
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        var phase = 0.0
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: max(f0, f1) * 2)
        for i in 0..<n {
            let t = Double(i) / SR
            let f = f0 * pow(f1 / f0, t / duration)
            phase += 2 * .pi * f / SR
            let env = exp(-t / decay) * min(1, t / 0.004)
            out[i] = lp.process(Float(sin(phase) * env) + noise.white() * noiseMix * Float(env))
        }
        AudioIO.normalize(&out, peak: gain)
        AudioIO.fade(&out, inSeconds: 0.001, outSeconds: 0.02)
        return out
    }

    static func noiseSweep(from f0: Double, to f1: Double, duration: Double, gain: Float, q: Double = 1.2, seed: UInt64) -> [Float] {
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var bp = Biquad(.bandpass, freq: f0, q: q)
        for i in 0..<n {
            let t = Double(i) / duration / SR
            if i % 32 == 0 { bp.set(.bandpass, freq: f0 * pow(f1 / f0, t), q: q) }
            let env = sin(.pi * t)
            out[i] = bp.process(noise.white()) * Float(env * env)
        }
        AudioIO.normalize(&out, peak: gain)
        return out
    }

    static func withReverb(_ dry: [Float], wet: Float, tail: Double, size: Double = 1.0) -> [Float] {
        var rv = Reverb(size: size, feedback: 0.86, damp: 0.35)
        var out = dry + [Float](repeating: 0, count: Int(tail * SR))
        for i in out.indices { out[i] = out[i] * (1 - wet * 0.3) + rv.process(out[i]) * wet }
        AudioIO.fade(&out, inSeconds: 0, outSeconds: tail * 0.5)
        return out
    }

    // MARK: - Ambience

    static func windLoop(seed: UInt64) -> [Float] {
        let n = Int(12 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 500, q: 0.9)
        var bp = Biquad(.bandpass, freq: 800, q: 3)
        for i in 0..<n {
            let t = Double(i) / SR
            let gust = 0.55 + 0.3 * sin(t * 0.52 * 2 * .pi / 6) + 0.15 * sin(t * 1.3)
            if i % 64 == 0 {
                lp.set(.lowpass, freq: 250 + 650 * gust, q: 0.9)
                bp.set(.bandpass, freq: 500 + 900 * gust, q: 4)
            }
            let p = noise.pink()
            out[i] = lp.process(p) * Float(gust) + bp.process(p) * 0.25 * Float(gust * gust)
        }
        AudioIO.normalize(&out, peak: 0.5)
        return AudioIO.makeLoop(out, crossfadeSeconds: 2)
    }

    static func rainLoop(seed: UInt64) -> [Float] {
        let n = Int(10 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var hp = Biquad(.highpass, freq: 900, q: 0.7)
        var lp = Biquad(.lowpass, freq: 6500, q: 0.7)
        var body = Biquad(.lowpass, freq: 650, q: 0.8)
        for i in 0..<n {
            out[i] = lp.process(hp.process(noise.white())) * 0.32 + body.process(noise.pink()) * 0.28
        }
        var rng = SplitMix64(seed: seed &+ 7)
        let dropLength = Int(0.02 * SR)
        for _ in 0..<1100 {
            let start = rng.nextInt(n), freq = 1800 + rng.nextDouble() * 3000, amp = Float(0.04 + rng.nextDouble() * 0.12)
            for k in 0..<dropLength where start + k < n {
                let t = Double(k) / SR
                out[start + k] += Float(sin(2 * .pi * freq * t) * exp(-t * 180)) * amp
            }
        }
        AudioIO.normalize(&out, peak: 0.5)
        return AudioIO.makeLoop(out, crossfadeSeconds: 1.5)
    }

    static func thunder(seed: UInt64) -> [Float] {
        let n = Int(4.5 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 170, q: 0.9)
        var crack = Biquad(.bandpass, freq: 1500, q: 0.8)
        var rng = SplitMix64(seed: seed)
        let rumbles = (0..<6).map { _ in (Double(rng.nextInt(1000)) / 1000 * 2.4, 0.4 + rng.nextDouble() * 0.6) }
        for i in 0..<n {
            let t = Double(i) / SR
            var env = 0.0
            for (start, amp) in rumbles where t >= start { env += amp * exp(-(t - start) * 1.4) }
            out[i] = lp.process(noise.brownian()) * Float(env) * 3 + crack.process(noise.white()) * Float(exp(-t * 9)) * 0.8
        }
        AudioIO.normalize(&out, peak: 0.85)
        return out
    }

    static func birdPhrase(seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let chirps = 3 + rng.nextInt(5)
        let base = 2600 + Double(rng.nextInt(1800))
        let n = Int(1.8 * SR)
        var out = [Float](repeating: 0, count: n)
        var t0 = 0.05
        for _ in 0..<chirps {
            let len = 0.05 + rng.nextDouble() * 0.09
            let up = rng.nextInt(2) == 0
            let f0 = base * (up ? 0.8 : 1.25), f1 = base * (up ? 1.3 : 0.75)
            var phase = 0.0
            let start = Int(t0 * SR)
            for i in 0..<Int(len * SR) where start + i < n {
                let t = Double(i) / SR
                let f = f0 + (f1 - f0) * (t / len) + sin(t * 2 * .pi * 38) * 120
                phase += 2 * .pi * f / SR
                out[start + i] += Float(sin(phase) * sin(.pi * t / len))
            }
            t0 += len + 0.02 + rng.nextDouble() * 0.12
        }
        AudioIO.normalize(&out, peak: 0.35)
        return withReverb(out, wet: 0.25, tail: 0.4, size: 0.8)
    }

    static func cricketsLoop(seed: UInt64) -> [Float] {
        let n = Int(8 * SR)
        var out = [Float](repeating: 0, count: n)
        var rng = SplitMix64(seed: seed)
        for voice in 0..<3 {
            let freq = 4300.0 + Double(voice) * 380 + Double(rng.nextInt(200))
            let rate = 2.2 + rng.nextDouble() * 1.2
            let offset = rng.nextDouble()
            for i in 0..<n {
                let t = Double(i) / SR
                let cycle = (t * rate + offset).truncatingRemainder(dividingBy: 1)
                guard cycle < 0.32 else { continue }
                let pulse = max(0, sin(t * 2 * .pi * 34))
                out[i] += Float(sin(2 * .pi * freq * t) * pulse * sin(.pi * cycle / 0.32)) * 0.3
            }
        }
        AudioIO.normalize(&out, peak: 0.28)
        return AudioIO.makeLoop(out, crossfadeSeconds: 0.5)
    }

    static func caveLoop(seed: UInt64) -> [Float] {
        let n = Int(12 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 110, q: 0.7)
        for i in 0..<n {
            let t = Double(i) / SR
            let swell = 0.7 + 0.3 * sin(t * 2 * .pi / 12)
            out[i] = lp.process(noise.brownian()) * Float(swell) + Float(sin(2 * .pi * 55 * t) * 0.04 * swell)
        }
        AudioIO.normalize(&out, peak: 0.5)
        return AudioIO.makeLoop(out, crossfadeSeconds: 2)
    }

    static func drip(seed: UInt64) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let f = 1100 + Double(rng.nextInt(700))
        let dry = sweep(from: f * 1.6, to: f, duration: 0.12, decay: 0.03, gain: 0.4)
        return withReverb(dry, wet: 0.55, tail: 1.6, size: 1.3)
    }

    static func surfLoop(seed: UInt64) -> [Float] {
        let n = Int(14 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 900, q: 0.6)
        for i in 0..<n {
            let t = Double(i) / SR
            let wave = pow(max(0, sin(t * 2 * .pi / 7)), 2) * 0.8 + 0.2
            if i % 128 == 0 { lp.set(.lowpass, freq: 400 + 1400 * wave, q: 0.6) }
            out[i] = lp.process(noise.pink()) * Float(wave)
        }
        AudioIO.normalize(&out, peak: 0.45)
        return AudioIO.makeLoop(out, crossfadeSeconds: 2)
    }

    static func jungleLoop(seed: UInt64) -> [Float] {
        let n = Int(12 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var bp1 = Biquad(.bandpass, freq: 6200, q: 6), bp2 = Biquad(.bandpass, freq: 3400, q: 8)
        for i in 0..<n {
            let t = Double(i) / SR
            let buzz1 = 0.5 + 0.5 * sin(t * 2 * .pi * 17) * (0.6 + 0.4 * sin(t * 0.9))
            let buzz2 = max(0, sin(t * 2 * .pi * 0.35)) * (0.5 + 0.5 * sin(t * 2 * .pi * 9))
            let w = noise.white()
            out[i] = bp1.process(w) * Float(buzz1) * 0.6 + bp2.process(w) * Float(buzz2) * 0.8
        }
        var rng = SplitMix64(seed: seed + 5)
        for k in 0..<4 {
            let phrase = birdPhrase(seed: seed &+ UInt64(k * 13))
            let start = Int(Double(k) * 3 * SR) + rng.nextInt(Int(SR))
            for (j, s) in phrase.enumerated() where start + j < n { out[start + j] += s * 0.4 }
        }
        AudioIO.normalize(&out, peak: 0.35)
        return AudioIO.makeLoop(out, crossfadeSeconds: 1.5)
    }

    static func underwaterLoop(seed: UInt64) -> [Float] {
        let n = Int(8 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 320, q: 0.9)
        var rng = SplitMix64(seed: seed + 1)
        for i in 0..<n { out[i] = lp.process(noise.pink()) * 0.8 }
        for _ in 0..<14 {
            let bubble = sweep(from: 350 + Double(rng.nextInt(500)), to: 900 + Double(rng.nextInt(800)), duration: 0.05, decay: 0.02, gain: 0.25)
            let start = rng.nextInt(n - bubble.count)
            for (j, s) in bubble.enumerated() { out[start + j] += s }
        }
        AudioIO.normalize(&out, peak: 0.45)
        return AudioIO.makeLoop(out, crossfadeSeconds: 1)
    }

    /// Distant prehistoric calls: vocal-tract-like formant filtering of a buzzy source.
    static func dinoCall(seed: UInt64, low: Bool) -> [Float] {
        var rng = SplitMix64(seed: seed)
        let duration = low ? 3.2 : 1.4
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        var f1 = Biquad(.bandpass, freq: low ? 320 : 900, q: 5)
        var f2 = Biquad(.bandpass, freq: low ? 780 : 2300, q: 7)
        var noise = Noise(seed)
        let base = low ? 58 + Double(rng.nextInt(20)) : 260 + Double(rng.nextInt(120))
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / duration / SR
            let contour = low ? (1 + 0.55 * sin(.pi * t) - 0.25 * t) : (1 + 1.6 * sin(.pi * pow(t, 0.6)) * (1 - t * 0.4))
            let f = base * contour + sin(Double(i) / SR * 2 * .pi * 6) * (low ? 2 : 14)
            phase += f / SR
            let saw = Float(2 * (phase - floor(phase)) - 1)
            let env = Float(sin(.pi * min(1, t * 1.15)) * (low ? 1 : pow(1 - t, 0.5)))
            let src = saw + noise.white() * 0.15
            out[i] = (f1.process(src) + f2.process(src) * 0.7) * env
        }
        var lp = Biquad(.lowpass, freq: low ? 1400 : 3200)
        for i in out.indices { out[i] = lp.process(out[i]) }
        AudioIO.normalize(&out, peak: 0.5)
        return withReverb(out, wet: 0.8, tail: 2.5, size: 1.4)
    }

    /// A short voiced animal call: buzzy source through two formant filters, with vibrato and tremolo.
    static func animalCall(seed: UInt64, base: Double, glide: Double, duration: Double, f1: Double, f2: Double,
                           vibratoRate: Double, vibratoDepth: Double, tremolo: Double, noise: Float) -> [Float] {
        let n = Int(duration * SR)
        var out = [Float](repeating: 0, count: n)
        var b1 = Biquad(.bandpass, freq: f1, q: 4)
        var b2 = Biquad(.bandpass, freq: f2, q: 6)
        var rnd = Noise(seed)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / SR
            let u = t / duration
            let f = base * (1 + glide * u) + sin(t * 2 * .pi * vibratoRate) * vibratoDepth
            phase += f / SR
            let saw = Float(2 * (phase - floor(phase)) - 1)
            let trem = Float(1 - tremolo * (0.5 + 0.5 * sin(t * 2 * .pi * vibratoRate)))
            let env = Float(min(1, t / 0.02) * pow(max(0, 1 - u), 0.6)) * trem
            let src = saw + rnd.white() * noise
            out[i] = (b1.process(src) + b2.process(src) * 0.6) * env
        }
        AudioIO.normalize(&out, peak: 0.6)
        AudioIO.fade(&out, inSeconds: 0.002, outSeconds: 0.03)
        return out
    }

    /// The Pookpook's two-note "pook-pook".
    static func pookpook(seed: UInt64, pitch: Double) -> [Float] {
        let one = sweep(from: 820 * pitch, to: 430 * pitch, duration: 0.11, decay: 0.05, gain: 0.7, noiseMix: 0.05, seed: seed)
        let two = sweep(from: 760 * pitch, to: 400 * pitch, duration: 0.13, decay: 0.06, gain: 0.65, noiseMix: 0.05, seed: seed + 1)
        var out = one + [Float](repeating: 0, count: Int(0.07 * SR)) + two
        AudioIO.normalize(&out, peak: 0.6)
        return withReverb(out, wet: 0.15, tail: 0.25)
    }

    // MARK: - Generation

    static func generateEffects(into dir: URL) throws -> Int {
        var count = 0
        func save(_ name: String, _ samples: [Float]) throws {
            try AudioIO.writeWAV(samples, to: dir.appendingPathComponent("\(name).wav"))
            count += 1
        }

        for (name, m) in materials.sorted(by: { $0.key < $1.key }) {
            let salt = UInt64(abs(name.hashValue) % 10_000) &+ Hashing.seed(from: name)
            for v in 1...4 { try save("step_\(name)_\(v)", renderMaterial(m, kind: .step, seed: salt &+ UInt64(v))) }
            for v in 1...3 { try save("hit_\(name)_\(v)", renderMaterial(m, kind: .hit, seed: salt &+ UInt64(100 + v))) }
            for v in 1...2 { try save("place_\(name)_\(v)", renderMaterial(m, kind: .place, seed: salt &+ UInt64(200 + v))) }
            for v in 1...3 { try save("break_\(name)_\(v)", renderMaterial(m, kind: .breakBlock, seed: salt &+ UInt64(300 + v))) }
        }

        // UI
        try save("ui_hover", tone([(1760, 0)], duration: 0.06, decay: 0.012, gain: 0.25))
        try save("ui_click", tone([(660, 0), (990, 0.012)], duration: 0.22, decay: 0.05, partials: [(1, 1), (2.76, 0.35)], gain: 0.5))
        try save("ui_back", tone([(880, 0), (587, 0.05)], duration: 0.25, decay: 0.05, partials: [(1, 1), (2.76, 0.3)], gain: 0.45))
        try save("ui_open", noiseSweep(from: 400, to: 2200, duration: 0.22, gain: 0.35, seed: 71))
        try save("ui_close", noiseSweep(from: 2200, to: 400, duration: 0.2, gain: 0.3, seed: 72))
        try save("ui_toggle", tone([(1200, 0)], duration: 0.08, decay: 0.02, partials: [(1, 1), (2, 0.3)], gain: 0.35))
        try save("craft", withReverb(tone([(1046.5, 0), (1318.5, 0.07), (1568, 0.14)], duration: 0.7, decay: 0.18, partials: [(1, 1), (2.0, 0.4), (3.01, 0.2)], gain: 0.5), wet: 0.3, tail: 0.6))
        try save("discover", withReverb(tone([(784, 0), (988, 0.12), (1318.5, 0.24)], duration: 1.1, decay: 0.35, partials: [(1, 1), (2.76, 0.25)], gain: 0.45), wet: 0.45, tail: 1.2))
        try save("pickup_1", sweep(from: 600, to: 1250, duration: 0.08, decay: 0.04, gain: 0.35))
        try save("pickup_2", sweep(from: 700, to: 1400, duration: 0.08, decay: 0.04, gain: 0.35))
        for v in 1...3 {
            var eat = renderMaterial(materials["dirt"]!, kind: .breakBlock, seed: UInt64(900 + v))
            eat = Array(eat.prefix(Int(0.3 * SR)))
            try save("eat_\(v)", eat)
        }
        try save("burp_full", tone([(180, 0)], duration: 0.3, decay: 0.12, partials: [(1, 1), (2, 0.5), (3, 0.3)], gain: 0.35))
        for v in 1...2 {
            var hurt = sweep(from: 150, to: 70, duration: 0.22, decay: 0.08, gain: 0.7, noiseMix: 0.6, seed: UInt64(40 + v))
            AudioIO.normalize(&hurt, peak: 0.7)
            try save("hurt_\(v)", hurt)
        }
        try save("land", sweep(from: 110, to: 55, duration: 0.18, decay: 0.05, gain: 0.6, noiseMix: 0.8, seed: 44))
        try save("splash", withReverb(noiseSweep(from: 2500, to: 500, duration: 0.45, gain: 0.55, q: 0.6, seed: 45), wet: 0.2, tail: 0.3))
        var twang = sweep(from: 340, to: 170, duration: 0.3, decay: 0.09, gain: 0.55, noiseMix: 0.25, seed: 47)
        AudioIO.normalize(&twang, peak: 0.6)
        try save("bow_shoot", withReverb(twang, wet: 0.15, tail: 0.2))
        try save("arrow_hit", Array(renderMaterial(materials["wood"]!, kind: .hit, seed: 48).prefix(Int(0.18 * SR))))
        try save("tool_break", withReverb(renderMaterial(materials["metal"]!, kind: .breakBlock, seed: 46), wet: 0.2, tail: 0.3))
        try save("death", withReverb(tone([(392, 0), (311, 0.25), (261.6, 0.5), (196, 0.75)], duration: 2.0, decay: 0.45, partials: [(1, 1), (2, 0.3)], gain: 0.5), wet: 0.5, tail: 1.5))

        // Ambience
        try save("amb_wind", windLoop(seed: 501))
        for v in 1...4 { try save("amb_bird_\(v)", birdPhrase(seed: UInt64(600 + v))) }
        try save("amb_crickets", cricketsLoop(seed: 701))
        try save("amb_cave", caveLoop(seed: 801))
        for v in 1...3 { try save("amb_drip_\(v)", drip(seed: UInt64(850 + v))) }
        try save("amb_surf", surfLoop(seed: 901))
        try save("amb_jungle", jungleLoop(seed: 951))
        try save("amb_underwater", underwaterLoop(seed: 971))
        try save("amb_rain", rainLoop(seed: 981))
        for v in 1...3 { try save("thunder_\(v)", thunder(seed: UInt64(990 + v))) }
        try save("amb_dino_low_1", dinoCall(seed: 1001, low: true))
        try save("amb_dino_low_2", dinoCall(seed: 1002, low: true))
        try save("amb_dino_high_1", dinoCall(seed: 1003, low: false))

        // Farm animals and the Pookpook
        try save("pookpook_1", pookpook(seed: 1101, pitch: 1.0))
        try save("pookpook_2", pookpook(seed: 1103, pitch: 1.12))
        try save("animal_moo_1", animalCall(seed: 1201, base: 110, glide: -0.2, duration: 1.3, f1: 420, f2: 900, vibratoRate: 5, vibratoDepth: 3, tremolo: 0.1, noise: 0.08))
        try save("animal_moo_2", animalCall(seed: 1202, base: 98, glide: 0.1, duration: 1.1, f1: 380, f2: 820, vibratoRate: 4, vibratoDepth: 2, tremolo: 0.1, noise: 0.08))
        try save("animal_oink_1", animalCall(seed: 1301, base: 210, glide: -0.35, duration: 0.28, f1: 900, f2: 2100, vibratoRate: 30, vibratoDepth: 20, tremolo: 0.3, noise: 0.35))
        try save("animal_oink_2", animalCall(seed: 1302, base: 240, glide: -0.25, duration: 0.22, f1: 980, f2: 2300, vibratoRate: 34, vibratoDepth: 24, tremolo: 0.35, noise: 0.35))
        try save("animal_baa_1", animalCall(seed: 1401, base: 330, glide: -0.1, duration: 0.8, f1: 1000, f2: 2600, vibratoRate: 18, vibratoDepth: 22, tremolo: 0.55, noise: 0.1))
        try save("animal_baa_2", animalCall(seed: 1402, base: 370, glide: -0.15, duration: 0.7, f1: 1100, f2: 2800, vibratoRate: 20, vibratoDepth: 26, tremolo: 0.6, noise: 0.1))
        var cluck = [Float]()
        for k in 0..<3 {
            cluck += sweep(from: 1100 + Double(k) * 60, to: 620, duration: 0.07, decay: 0.03, gain: 0.6, noiseMix: 0.2, seed: UInt64(1500 + k))
            cluck += [Float](repeating: 0, count: Int(0.06 * SR))
        }
        try save("animal_cluck_1", cluck)
        return count
    }
}
