import Foundation
import DinoCraftCore

/// Toonland's songs, written note by note in the style of an old cartoon: an oom-pah band,
/// a whistler, slide-whistle swoops and a sung melody (a formant voice), plus the lyrics
/// timed to the beat for the on-screen sing-along.
enum SongComposer {
    /// One sung (or whistled) note: a syllable, a scale degree and a length in beats.
    struct Note { let syllable: String; let degree: Int; let beats: Double }

    /// A two-bar line of melody; `chords` are the chord roots (scale degrees) for its two bars.
    struct Line {
        let text: String
        let notes: [Note]
        let chords: [Int]
        init(_ text: String, _ syllables: [String], _ degrees: [Int], _ beats: [Double], chords: [Int]) {
            precondition(syllables.count == degrees.count && degrees.count == beats.count, "line '\(text)' is uneven")
            precondition(abs(beats.reduce(0, +) - 8) < 0.001, "line '\(text)' must last two bars")
            self.text = text
            notes = zip(zip(syllables, degrees), beats).map { Note(syllable: $0.0, degree: $0.1, beats: $1) }
            self.chords = chords
        }
    }

    enum Section { case sung([Line]), whistled([Line]), outro }

    static let verse1: [Line] = [
        Line("The sky is white, the ground is too,", ["the", "sky", "is", "white", "the", "ground", "is", "too"],
             [4, 7, 6, 4, 4, 7, 6, 5], [0.5, 1, 0.5, 1.5, 0.5, 1, 0.5, 2.5], chords: [0, 0]),
        Line("there's not a single shade of blue,", ["theres", "not", "a", "sin", "gle", "shade", "of", "blue"],
             [5, 6, 5, 4, 2, 4, 3, 2], [0.5, 1, 0.5, 1, 0.5, 1.5, 0.5, 2.5], chords: [4, 0]),
        Line("but every flower wears a grin,", ["but", "ev", "ry", "flow", "er", "wears", "a", "grin"],
             [4, 7, 6, 4, 4, 7, 8, 9], [0.5, 1, 0.5, 1, 0.5, 1.5, 0.5, 2.5], chords: [0, 5]),
        Line("so come on in, come on in!", ["so", "come", "on", "in", "come", "on", "in"],
             [9, 8, 7, 8, 7, 6, 7], [0.5, 1, 0.5, 2, 1, 1, 2], chords: [3, 0]),
    ]
    static let verse2: [Line] = [
        Line("Old King Grumble stomps and roars,", ["old", "king", "grum", "ble", "stomps", "and", "roars"],
             [4, 7, 6, 4, 4, 3, 2], [1, 0.5, 1, 0.5, 1.5, 0.5, 3], chords: [0, 0]),
        Line("he's grumpy on his checkered floors,", ["hees", "grump", "ee", "on", "his", "check", "erd", "floors"],
             [2, 3, 2, 1, 2, 3, 4, 5], [0.5, 1, 0.5, 0.5, 0.5, 1, 0.5, 3.5], chords: [4, 4]),
        Line("so bring a sword and bring a smile,", ["so", "bring", "a", "sword", "and", "bring", "a", "smile"],
             [4, 7, 6, 4, 4, 7, 8, 9], [0.5, 1, 0.5, 1.5, 0.5, 1, 0.5, 2.5], chords: [0, 5]),
        Line("and cheer him up in cartoon style!", ["and", "cheer", "him", "up", "in", "car", "toon", "style"],
             [9, 8, 7, 6, 5, 6, 6, 7], [0.5, 1, 0.5, 1, 0.5, 1, 0.5, 3], chords: [4, 0]),
    ]
    static let chorus: [Line] = [
        Line("Sunny side up in Toonland town,", ["sun", "ny", "side", "up", "in", "toon", "land", "town"],
             [7, 7, 9, 7, 5, 4, 5, 7], [1, 0.5, 1, 1.5, 0.5, 1, 0.5, 2], chords: [0, 0]),
        Line("turn that frown upside down!", ["turn", "that", "frown", "up", "side", "down"],
             [8, 8, 7, 6, 5, 4], [1, 0.5, 1.5, 1, 1, 3], chords: [3, 0]),
        Line("Hop on the checkers, one, two, three,", ["hop", "on", "the", "check", "ers", "one", "two", "three"],
             [4, 5, 6, 7, 6, 7, 8, 9], [0.5, 0.5, 0.5, 1, 0.5, 1, 1, 3], chords: [3, 4]),
        Line("happy as a dino can be!", ["hap", "py", "as", "a", "dy", "no", "can", "bee"],
             [9, 8, 7, 6, 5, 6, 4, 7], [1, 0.5, 0.5, 0.5, 1, 0.5, 1, 3], chords: [4, 0]),
    ]

    struct Spec {
        let file: String
        let title: String
        let bpm: Double
        let minor: Bool
        let root: Int
        let sections: [Section]
        let introBars: Int
    }

    static let sunnySideUp = Spec(file: "sunny_side_up", title: "Sunny Side Up", bpm: 132, minor: false, root: 60,
                                  sections: [.sung(verse1), .sung(chorus), .sung(verse2), .sung(chorus),
                                             .whistled(Array(chorus[2...3])), .sung(chorus), .outro],
                                  introBars: 4)
    static let grumbleStomp = Spec(file: "grumble_stomp", title: "Grumble Stomp", bpm: 152, minor: true, root: 57,
                                   sections: [.whistled(chorus), .whistled(verse2), .whistled(chorus), .whistled(verse1), .whistled(chorus), .outro],
                                   introBars: 2)

    static let major = [0, 2, 4, 5, 7, 9, 11]
    static let minorScale = [0, 2, 3, 5, 7, 8, 10]

    static func midi(_ spec: Spec, _ degree: Int) -> Double {
        let scale = spec.minor ? minorScale : major
        let oct = Int(floor(Double(degree) / 7)), d = ((degree % 7) + 7) % 7
        return Double(spec.root + scale[d] + 12 * oct)
    }

    static func freq(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

    // MARK: Instruments

    /// A tuba-ish bass: a few harmonics with a soft attack.
    static func tuba(_ f: Double, _ dur: Double) -> [Float] {
        let n = Int((dur + 0.1) * SR)
        return (0..<n).map { i in
            let t = Double(i) / SR
            let env = min(1, t / 0.02) * exp(-t / max(0.12, dur * 0.8))
            let s = sin(2 * .pi * f * t) + 0.45 * sin(4 * .pi * f * t) + 0.2 * sin(6 * .pi * f * t)
            return Float(s * env * 0.5)
        }
    }

    /// A honky-tonk piano stab: two slightly detuned decaying tones per note.
    static func piano(_ f: Double, _ dur: Double) -> [Float] {
        let n = Int((dur + 0.3) * SR)
        return (0..<n).map { i in
            let t = Double(i) / SR
            let env = min(1, t / 0.004) * exp(-t / 0.22)
            var s = 0.0
            for (m, a) in [(1.0, 1.0), (2.0, 0.45), (3.0, 0.2), (4.0, 0.1)] {
                s += a * (sin(2 * .pi * f * m * t) + sin(2 * .pi * f * m * 1.004 * t)) * 0.5
            }
            return Float(s * env * 0.35)
        }
    }

    /// A whistler: a sine with vibrato and a little breath.
    static func whistle(_ f: Double, _ dur: Double, seed: UInt64) -> [Float] {
        let n = Int(dur * SR)
        var noise = Noise(seed)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / SR
            let vib = t > 0.12 ? sin(2 * .pi * 5.8 * t) * 0.012 : 0
            phase += 2 * .pi * f * (1 + vib) / SR
            let env = min(1, t / 0.03) * min(1, (dur - t) / 0.05)
            return Float((sin(phase) * 0.9 + Double(noise.white()) * 0.04) * env * 0.45)
        }
    }

    /// A cartoon slide whistle swooping from one pitch to another.
    static func slide(from f0: Double, to f1: Double, _ dur: Double) -> [Float] {
        let n = Int(dur * SR)
        var phase = 0.0
        return (0..<n).map { i in
            let t = Double(i) / Double(n)
            let f = f0 * pow(f1 / f0, t)
            phase += 2 * .pi * f / SR
            return Float(sin(phase) * sin(.pi * t) * 0.4)
        }
    }

    static func snare(seed: UInt64) -> [Float] {
        var noise = Noise(seed)
        var bp = Biquad(.bandpass, freq: 2600, q: 0.7)
        return (0..<Int(0.18 * SR)).map { i in
            let t = Double(i) / SR
            return bp.process(noise.white()) * Float(exp(-t / 0.05)) * 0.9
        }
    }

    static func woodblock() -> [Float] {
        (0..<Int(0.08 * SR)).map { i in
            let t = Double(i) / SR
            return Float((sin(2 * .pi * 1200 * t) + 0.5 * sin(2 * .pi * 1830 * t)) * exp(-t / 0.018) * 0.5)
        }
    }

    // MARK: Voice

    /// Formant frequencies (F1, F2, F3) for a sung vowel.
    static func formants(for syllable: String) -> (Double, Double, Double) {
        let s = syllable.lowercased()
        if s.contains("ee") || s.contains("ea") || s.hasSuffix("y") || s.contains("i") { return (300, 2250, 2950) }   // ee
        if s.contains("oo") || s.contains("ue") || s.contains("u") && s.count <= 3 { return (320, 880, 2250) }        // oo
        if s.contains("ow") || s.contains("ou") { return (700, 1150, 2450) }                                           // ah(w)
        if s.contains("o") { return (560, 860, 2400) }                                                                 // oh
        if s.contains("e") { return (530, 1840, 2480) }                                                                // eh
        return (740, 1180, 2440)                                                                                       // ah
    }

    /// Sings one syllable: a buzzing voice through three vowel formants, with a consonant at the front.
    static func sing(_ syllable: String, _ f: Double, _ dur: Double, seed: UInt64) -> [Float] {
        let n = Int(dur * SR)
        var out = [Float](repeating: 0, count: n)
        let (f1, f2, f3) = formants(for: syllable)
        var b1 = Biquad(.bandpass, freq: f1, q: 6), b2 = Biquad(.bandpass, freq: f2, q: 9), b3 = Biquad(.bandpass, freq: f3, q: 11)
        var noise = Noise(seed)
        var phase = 0.0
        let first = syllable.first.map(String.init) ?? ""
        let hiss = ["s", "c", "f", "t", "h"].contains(first) ? (first == "s" || first == "c" ? 0.07 : 0.025) : 0
        var hp = Biquad(.highpass, freq: 4200)
        for i in 0..<n {
            let t = Double(i) / SR
            let vib = t > 0.15 ? sin(2 * .pi * 5.5 * t) * 0.018 : 0
            // Scoop up into the note like a cartoon crooner
            let scoop = t < 0.06 ? -0.03 * (1 - t / 0.06) : 0
            phase += f * (1 + vib + scoop) / SR
            if phase >= 1 { phase -= 1 }
            let saw = Float(phase * 2 - 1)
            let src = saw + noise.white() * 0.05
            var v = b1.process(src) * 1.0 + b2.process(src) * 0.55 + b3.process(src) * 0.3
            let attack = min(1, (t - hiss * 0.6) / 0.035)
            let env = Float(max(0, attack) * min(1, (dur - t) / 0.07))
            v *= env
            if t < hiss { v += hp.process(noise.white()) * Float(0.5 * (1 - t / max(hiss, 0.001))) }
            out[i] = v
        }
        return out
    }

    // MARK: Arrangement

    struct Lyric: Codable { let t: Double; let line: String }

    static func render(_ spec: Spec) -> (samples: [Float], lyrics: [Lyric]) {
        let beat = 60 / spec.bpm, bar = beat * 4
        var bars = spec.introBars
        for section in spec.sections {
            switch section {
            case .sung(let lines), .whistled(let lines): bars += lines.count * 2
            case .outro: bars += 2
            }
        }
        let total = Double(bars) * bar + 3
        var mix = [Float](repeating: 0, count: Int(total * SR))
        var send = [Float](repeating: 0, count: mix.count)
        func add(_ s: [Float], at time: Double, gain: Float, reverb: Float = 0.15) {
            let start = Int(time * SR)
            for (i, v) in s.enumerated() {
                let j = start + i
                guard j >= 0, j < mix.count else { continue }
                mix[j] += v * gain
                send[j] += v * gain * reverb
            }
        }
        var rng = SplitMix64(seed: spec.file.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })
        var lyrics: [Lyric] = []

        func band(bar b: Int, chord: Int) {
            let t0 = Double(b) * bar
            let root = midi(spec, chord - 7), fifth = midi(spec, chord - 3)
            add(tuba(freq(root), beat * 0.9), at: t0, gain: 0.55)
            add(tuba(freq(fifth), beat * 0.9), at: t0 + 2 * beat, gain: 0.5)
            for k in [1, 3] {
                for d in [0, 2, 4] { add(piano(freq(midi(spec, chord + d)), beat * 0.5), at: t0 + Double(k) * beat, gain: 0.16) }
                add(snare(seed: rng.next()), at: t0 + Double(k) * beat, gain: 0.22)
            }
            if b % 2 == 1 { add(woodblock(), at: t0 + 3.5 * beat, gain: 0.3) }
        }

        // Intro: the band vamps and a slide whistle swoops in
        for b in 0..<spec.introBars { band(bar: b, chord: b % 2 == 0 ? 0 : 4) }
        add(slide(from: 300, to: 1400, bar * 0.9), at: Double(spec.introBars - 1) * bar, gain: 0.5, reverb: 0.3)

        var b = spec.introBars
        for section in spec.sections {
            switch section {
            case .sung(let lines), .whistled(let lines):
                var sung = false
                if case .sung = section { sung = true }
                for line in lines {
                    let t0 = Double(b) * bar
                    band(bar: b, chord: line.chords[0])
                    band(bar: b + 1, chord: line.chords[1])
                    if sung { lyrics.append(Lyric(t: (t0 * 100).rounded() / 100, line: line.text)) }
                    var t = t0
                    for note in line.notes {
                        let f = freq(midi(spec, note.degree))
                        let len = note.beats * beat
                        if sung {
                            add(sing(note.syllable, f, len * 0.94, seed: rng.next()), at: t, gain: 0.5, reverb: 0.25)
                            add(whistle(f * 2, len * 0.9, seed: rng.next()), at: t, gain: 0.06, reverb: 0.3)
                        } else {
                            add(whistle(f * 2, len * 0.9, seed: rng.next()), at: t, gain: 0.42, reverb: 0.3)
                        }
                        t += len
                    }
                    b += 2
                }
            case .outro:
                band(bar: b, chord: 4)
                let end = Double(b + 1) * bar
                for d in [0, 2, 4, 7] { add(piano(freq(midi(spec, d)), bar), at: end, gain: 0.2) }
                add(tuba(freq(midi(spec, -7)), bar), at: end, gain: 0.6)
                add(slide(from: 1400, to: 250, beat * 1.5), at: end + beat * 0.5, gain: 0.45, reverb: 0.3)
                b += 2
            }
        }

        var rv = Reverb(size: 0.8, feedback: 0.8, damp: 0.35)
        for i in mix.indices { mix[i] += rv.process(send[i]) * 0.8 }
        AudioIO.normalize(&mix, peak: 0.9)
        for i in mix.indices { mix[i] = tanh(mix[i] * 1.05) }
        AudioIO.fade(&mix, inSeconds: 0.05, outSeconds: 2)
        return (mix, lyrics)
    }

    /// 16-bit mono WAV at 22 050 Hz (what the other music tracks use).
    static func writeWAV22k(_ s: [Float], to url: URL) throws {
        var half = [Float](repeating: 0, count: s.count / 2)
        for i in half.indices { half[i] = (s[i * 2] + s[i * 2 + 1]) * 0.5 }
        var data = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + half.count * 2))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1); u32(22050); u32(44100); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(half.count * 2))
        for v in half { u16(UInt16(bitPattern: Int16(max(-32767, min(32767, (v * 32767).rounded()))))) }
        try data.write(to: url, options: .atomic)
    }

    /// Writes both songs to Music/ and the sing-along lyrics to Data/lyrics.json.
    static func generate(music: URL, data: URL) throws -> Int {
        var all: [String: [Lyric]] = [:]
        for spec in [sunnySideUp, grumbleStomp] {
            let t0 = Date()
            let (samples, lyrics) = render(spec)
            try writeWAV22k(samples, to: music.appendingPathComponent("\(spec.file).wav"))
            #if canImport(AVFAudio)
            try AudioIO.writeM4A(left: samples, right: samples, to: music.appendingPathComponent("\(spec.file).m4a"))
            #endif
            if !lyrics.isEmpty { all[spec.file] = lyrics }
            print(String(format: "  ♪ %@ — %.0fs rendered in %.1fs", spec.title, Double(samples.count) / SR, Date().timeIntervalSince(t0)))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(all).write(to: data.appendingPathComponent("lyrics.json"))
        return 2
    }
}
