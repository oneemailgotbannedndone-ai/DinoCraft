import Foundation
import DinoCraftCore

/// Algorithmic composer for DinoCraft's soundtrack. Each track is rendered
/// deterministically from a seed: chord progressions over a pentatonic mode,
/// motif-based melodies with variation, pads, plucked strings (Karplus–Strong),
/// kalimba-like bells, a sub drone and a stereo reverb bus.
enum MusicComposer {
    struct TrackSpec {
        let file: String
        let title: String
        let seed: UInt64
        let rootMidi: Int
        let minor: Bool
        let bpm: Double
        let bars: Int
        let progression: [Int]     // scale degrees for chord roots (0-based, diatonic)
        let lead: Lead
        let percussion: Bool
        let brightness: Double
    }
    enum Lead { case kalimba, pluck, bell }

    static let tracks: [TrackSpec] = [
        TrackSpec(file: "fernlight", title: "Fernlight", seed: 11, rootMidi: 50, minor: false, bpm: 74, bars: 44,
                  progression: [0, 4, 5, 3], lead: .kalimba, percussion: false, brightness: 0.8),
        TrackSpec(file: "amber_dusk", title: "Amber Dusk", seed: 23, rootMidi: 45, minor: true, bpm: 66, bars: 40,
                  progression: [0, 5, 3, 4], lead: .pluck, percussion: false, brightness: 0.55),
        TrackSpec(file: "deep_strata", title: "Deep Strata", seed: 37, rootMidi: 38, minor: true, bpm: 56, bars: 32,
                  progression: [0, 0, 5, 6], lead: .bell, percussion: false, brightness: 0.35),
        TrackSpec(file: "titan_valley", title: "Titan Valley", seed: 41, rootMidi: 47, minor: false, bpm: 88, bars: 52,
                  progression: [0, 3, 4, 5, 0, 3, 1, 4], lead: .pluck, percussion: true, brightness: 0.9),
        TrackSpec(file: "menu_theme", title: "Where Giants Roamed", seed: 53, rootMidi: 43, minor: false, bpm: 70, bars: 36,
                  progression: [0, 5, 3, 4], lead: .kalimba, percussion: false, brightness: 0.7),
    ]

    static let majorScale = [0, 2, 4, 5, 7, 9, 11]
    static let minorScale = [0, 2, 3, 5, 7, 8, 10]

    static func midiToFreq(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

    final class Mix {
        var left: [Float], right: [Float], send: [Float]
        init(count: Int) {
            left = [Float](repeating: 0, count: count)
            right = [Float](repeating: 0, count: count)
            send = [Float](repeating: 0, count: count)
        }
        func add(_ s: [Float], at start: Int, gain: Float, pan: Float, reverb: Float) {
            let gl = gain * sqrt(0.5 * (1 - pan)), gr = gain * sqrt(0.5 * (1 + pan))
            for (i, v) in s.enumerated() {
                let j = start + i
                guard j < left.count else { break }
                left[j] += v * gl; right[j] += v * gr; send[j] += v * reverb * gain
            }
        }
    }

    // MARK: Instruments

    static let padTable: [Float] = {
        let n = 4096
        return (0..<n).map { i in
            let p = Double(i) / Double(n) * 2 * .pi
            var s = 0.0
            for h in 1...8 { s += sin(p * Double(h)) / Double(h) * (h % 2 == 0 ? 0.6 : 1) }
            return Float(s * 0.5)
        }
    }()

    static func pad(freq: Double, duration: Double, brightness: Double) -> [Float] {
        let n = Int((duration + 2.5) * SR)
        var out = [Float](repeating: 0, count: n)
        let table = padTable
        let tn = Double(table.count)
        var lp = Biquad(.lowpass, freq: 500 + 2200 * brightness, q: 0.6)
        for detune in [-0.0045, 0.0, 0.0052] {
            var phase = Double.random(in: 0..<1, using: &FixedRNG.shared)
            let inc = freq * (1 + detune) / SR
            for i in 0..<n {
                phase += inc
                if phase >= 1 { phase -= 1 }
                let idx = phase * tn
                let i0 = Int(idx) % table.count
                let frac = Float(idx - floor(idx))
                out[i] += table[i0] + (table[(i0 + 1) % table.count] - table[i0]) * frac
            }
        }
        for i in 0..<n {
            let t = Double(i) / SR
            let env = min(1, t / 1.6) * (t > duration ? exp(-(t - duration) / 0.9) : 1)
            out[i] = lp.process(out[i] * Float(env) * 0.33)
        }
        return out
    }

    static func pluck(freq: Double, duration: Double, seed: UInt64, brightness: Double) -> [Float] {
        let n = Int((duration + 1.5) * SR)
        let period = max(2, Int(SR / freq))
        var buffer = [Float](repeating: 0, count: period)
        var noise = Noise(seed)
        var lp = Biquad(.lowpass, freq: 1500 + 4000 * brightness)
        for i in 0..<period { buffer[i] = lp.process(noise.white()) }
        var out = [Float](repeating: 0, count: n)
        var idx = 0
        let decay: Float = 0.996 + Float(min(0.0035, 40 / freq * 0.001))
        for i in 0..<n {
            let a = buffer[idx], b = buffer[(idx + 1) % period]
            let v = (a + b) * 0.5 * decay
            buffer[idx] = v
            out[i] = a
            idx = (idx + 1) % period
        }
        return out
    }

    static func kalimba(freq: Double, duration: Double) -> [Float] {
        let n = Int((duration + 1.2) * SR)
        var out = [Float](repeating: 0, count: n)
        let partials: [(Double, Double, Double)] = [(1, 1, 1.1), (2.76, 0.28, 0.35), (5.4, 0.12, 0.12), (8.93, 0.05, 0.05)]
        for i in 0..<n {
            let t = Double(i) / SR
            var s = 0.0
            for (m, a, d) in partials { s += sin(2 * .pi * freq * m * t) * a * exp(-t / d) }
            out[i] = Float(s * min(1, t / 0.002) * 0.6)
        }
        return out
    }

    static func bell(freq: Double, duration: Double) -> [Float] {
        let n = Int((duration + 3) * SR)
        var out = [Float](repeating: 0, count: n)
        let partials: [(Double, Double, Double)] = [(0.5, 0.4, 2.5), (1, 1, 2.0), (1.19, 0.35, 1.4), (2.0, 0.3, 1.0), (2.74, 0.2, 0.7), (4.07, 0.08, 0.4)]
        for i in 0..<n {
            let t = Double(i) / SR
            var s = 0.0
            for (m, a, d) in partials { s += sin(2 * .pi * freq * m * t) * a * exp(-t / d) }
            out[i] = Float(s * min(1, t / 0.004) * 0.4)
        }
        return out
    }

    static func drum(low: Bool, seed: UInt64) -> [Float] {
        let n = Int(0.5 * SR)
        var out = [Float](repeating: 0, count: n)
        var noise = Noise(seed)
        var hp = Biquad(.highpass, freq: 6000)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / SR
            if low {
                let f = 55 + 70 * exp(-t / 0.04)
                phase += 2 * .pi * f / SR
                out[i] = Float(sin(phase) * exp(-t / 0.18)) + noise.white() * Float(exp(-t / 0.01)) * 0.2
            } else {
                out[i] = hp.process(noise.white()) * Float(exp(-t / 0.035)) * 0.6
            }
        }
        return out
    }

    // MARK: Composition

    static func render(_ spec: TrackSpec) -> (left: [Float], right: [Float]) {
        FixedRNG.shared = FixedRNG(seed: spec.seed)
        var rng = SplitMix64(seed: spec.seed)
        let beat = 60 / spec.bpm
        let bar = beat * 4
        let total = Double(spec.bars) * bar + 6
        let mix = Mix(count: Int(total * SR))
        let scale = spec.minor ? minorScale : majorScale
        let penta = spec.minor ? [0, 2, 3, 4, 6] : [0, 1, 2, 4, 5]   // indices into the diatonic scale

        func note(_ degree: Int, octave: Int) -> Double {
            let oct = Int(floor(Double(degree) / 7))
            let d = ((degree % 7) + 7) % 7
            return Double(spec.rootMidi + scale[d] + 12 * (oct + octave))
        }

        // Motif: 8 eighth-note slots, pentatonic degrees (nil = rest)
        func makeMotif() -> [Int?] {
            var m: [Int?] = []
            var deg = penta[rng.nextInt(penta.count)]
            for i in 0..<8 {
                if i > 0 && rng.nextInt(10) < 4 { m.append(nil); continue }
                let step = rng.nextInt(5) - 2
                let idx = max(0, min(penta.count * 2 - 1, (penta.firstIndex(of: deg % 7) ?? 0) + step + (deg >= 7 ? penta.count : 0)))
                deg = penta[idx % penta.count] + (idx >= penta.count ? 7 : 0)
                m.append(deg)
            }
            return m
        }
        let motifA = makeMotif(), motifB = makeMotif()

        let introBars = 4, outroBars = 4
        for b in 0..<spec.bars {
            let start = Double(b) * bar
            let chordRoot = spec.progression[b % spec.progression.count]
            let startSample = Int(start * SR)

            // Pad chord every bar (root, third, fifth, + ninth colour)
            for (i, interval) in [0, 2, 4, 8].enumerated() where i < 3 || spec.brightness > 0.6 {
                let f = midiToFreq(note(chordRoot + interval, octave: 0))
                mix.add(pad(freq: f, duration: bar * 1.02, brightness: spec.brightness), at: startSample,
                        gain: 0.16, pan: Float(i - 1) * 0.35, reverb: 0.5)
            }
            // Sub drone
            if b % 2 == 0 {
                let f = midiToFreq(note(chordRoot, octave: -1))
                let sub = (0..<Int(bar * 2 * SR)).map { i -> Float in
                    let t = Double(i) / SR
                    return Float(sin(2 * .pi * f * t) * min(1, t / 1.0) * min(1, (bar * 2 - t) / 1.0)) * 0.5
                }
                mix.add(sub, at: startSample, gain: 0.22, pan: 0, reverb: 0.1)
            }
            // Melody
            let section = (b / 8) % 4
            let playsLead = b >= introBars && b < spec.bars - outroBars && section != 2
            if playsLead {
                let motif = (section == 3 || b % 4 >= 2) ? motifB : motifA
                for (slot, deg) in motif.enumerated() {
                    guard var d = deg else { continue }
                    if b % 8 >= 6 && rng.nextInt(3) == 0 { d += 1 }   // variation
                    let f = midiToFreq(note(d + chordRoot % 2, octave: spec.lead == .bell ? 1 : 1))
                    let t0 = start + Double(slot) * beat / 2 + (rng.nextDouble() - 0.5) * 0.012
                    let samples: [Float]
                    switch spec.lead {
                    case .kalimba: samples = kalimba(freq: f, duration: beat)
                    case .pluck: samples = pluck(freq: f, duration: beat * 1.5, seed: rng.next(), brightness: spec.brightness)
                    case .bell: samples = bell(freq: f, duration: beat * 2)
                    }
                    mix.add(samples, at: Int(t0 * SR), gain: spec.lead == .pluck ? 0.33 : 0.3,
                            pan: Float(rng.nextDouble() - 0.5) * 0.6, reverb: 0.55)
                }
            } else if section == 2 && b % 2 == 0 {
                // Sparse bells in the breakdown
                let f = midiToFreq(note(chordRoot + 4, octave: 1))
                mix.add(bell(freq: f, duration: bar), at: startSample + Int(beat * SR), gain: 0.18, pan: 0.3, reverb: 0.8)
            }
            // Arpeggio shimmer
            if b >= introBars && spec.brightness > 0.5 && b % 2 == 1 {
                for k in 0..<4 {
                    let f = midiToFreq(note(chordRoot + [0, 2, 4, 7][k], octave: 2))
                    mix.add(kalimba(freq: f, duration: beat * 0.5), at: startSample + Int(Double(k) * beat * SR),
                            gain: 0.08, pan: Float(k) * 0.25 - 0.4, reverb: 0.7)
                }
            }
            // Percussion
            if spec.percussion && b >= introBars && b < spec.bars - 2 {
                for k in 0..<4 {
                    let t = startSample + Int(Double(k) * beat * SR)
                    if k == 0 || k == 2 { mix.add(drum(low: true, seed: rng.next()), at: t, gain: 0.35, pan: 0, reverb: 0.15) }
                    mix.add(drum(low: false, seed: rng.next()), at: t + Int(beat * 0.5 * SR), gain: 0.12, pan: 0.4, reverb: 0.2)
                }
            }
        }

        // Stereo reverb bus
        var rvL = Reverb(size: 1.5, feedback: 0.88, damp: 0.4, spread: 0)
        var rvR = Reverb(size: 1.5, feedback: 0.88, damp: 0.4, spread: 23)
        var l = mix.left, r = mix.right
        for i in l.indices {
            let s = mix.send[i]
            l[i] += rvL.process(s) * 0.9
            r[i] += rvR.process(s) * 0.9
        }
        // Master: gentle saturation, normalize, fades
        let peak = max(l.reduce(Float(0)) { max($0, abs($1)) }, r.reduce(Float(0)) { max($0, abs($1)) })
        let k = peak > 0 ? 0.9 / peak : 1
        for i in l.indices {
            l[i] = tanh(l[i] * k * 1.1) * 0.92
            r[i] = tanh(r[i] * k * 1.1) * 0.92
        }
        AudioIO.fade(&l, inSeconds: 3, outSeconds: 6)
        AudioIO.fade(&r, inSeconds: 3, outSeconds: 6)
        return (l, r)
    }

    static func generate(into dir: URL) throws -> Int {
        for spec in tracks {
            let t0 = Date()
            let (l, r) = render(spec)
            try AudioIO.writeM4A(left: l, right: r, to: dir.appendingPathComponent("\(spec.file).m4a"))
            print(String(format: "  ♪ %@ — %.0fs rendered in %.1fs", spec.title, Double(l.count) / SR, Date().timeIntervalSince(t0)))
        }
        return tracks.count
    }
}

/// Deterministic RandomNumberGenerator for APIs that take `using:`.
struct FixedRNG: RandomNumberGenerator {
    static var shared = FixedRNG(seed: 1)
    var inner: SplitMix64
    init(seed: UInt64) { inner = SplitMix64(seed: seed) }
    mutating func next() -> UInt64 { inner.next() }
}
