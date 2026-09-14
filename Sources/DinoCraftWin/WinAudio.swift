import Foundation
import CSDL3
import DinoCraftCore

/// SDL3 audio for Windows: pitched sound effects, fading ambience loops and music, mixed on SDL's
/// audio thread. Sound names follow the Mac app ("step_grass" picks one of step_grass_1…4).
/// Without an audio device the game continues silently.
final class WinAudio {
    private final class Clip {
        let samples: [Float]
        let rate: Double
        init(samples: [Float], rate: Double) { self.samples = samples; self.rate = rate }
    }

    private enum Bus { case sfx, ambient, music }

    private struct Voice {
        let clip: Clip
        var position: Double
        let step: Double
        var gain: Float
        let bus: Bus
        let loopName: String?
    }

    private static let outputRate = 44_100.0
    private let lock = NSLock()
    private var voices: [Voice] = []
    private var clips: [String: Clip] = [:]
    private var files: [String: URL] = [:]
    private var variants: [String: [String]] = [:]
    private var loopTargets: [String: Float] = [:]
    private var loopGains: [String: Float] = [:]
    private var stream: OpaquePointer?
    private var mixBuffer: [Float] = []
    private var masterVolume: Float = 0.8
    private var soundVolume: Float = 0.9
    private var ambientVolume: Float = 0.7
    private var musicVolume: Float = 0.5
    private(set) var available = false
    private(set) var currentTrack: String?

    init() {
        for url in ResourceLocator.files(in: "Sounds", withExtension: "wav") {
            let name = url.deletingPathExtension().lastPathComponent
            files[name] = url
            if let underscore = name.lastIndex(of: "_"), Int(name[name.index(after: underscore)...]) != nil {
                variants[String(name[..<underscore]), default: []].append(name)
            }
        }
        guard SDL_InitSubSystem(SDL_INIT_AUDIO) else {
            Log.warning("No audio: \(String(cString: SDL_GetError()))", category: "Audio")
            return
        }
        var spec = SDL_AudioSpec(format: SDL_AUDIO_F32LE, channels: 1, freq: 44100)
        let callback: SDL_AudioStreamCallback = { userdata, stream, additional, _ in
            guard let userdata, additional > 0 else { return }
            Unmanaged<WinAudio>.fromOpaque(userdata).takeUnretainedValue().mix(stream: stream, bytes: Int(additional))
        }
        stream = SDL_OpenAudioDeviceStream(0xFFFF_FFFF, &spec, callback, Unmanaged.passUnretained(self).toOpaque())
        guard let stream else {
            Log.warning("Could not open an audio device: \(String(cString: SDL_GetError()))", category: "Audio")
            return
        }
        _ = SDL_ResumeAudioStreamDevice(stream)
        available = true
        Log.info("Audio started with \(files.count) sounds", category: "Audio")
    }

    func apply(_ settings: GameSettings) {
        lock.lock()
        masterVolume = Float(settings.masterVolume)
        soundVolume = Float(settings.soundVolume)
        ambientVolume = Float(settings.ambientVolume)
        musicVolume = Float(settings.musicVolume)
        lock.unlock()
    }

    // MARK: Playing

    private func clip(_ name: String) -> Clip? {
        if let clip = clips[name] { return clip }
        guard let url = files[name] else { return nil }
        guard let clip = WinAudio.loadWAV(url) else {
            Log.warning("Sound \(name) could not be read", category: "Audio")
            files[name] = nil
            return nil
        }
        clips[name] = clip
        return clip
    }

    /// Plays a one-shot sound (or a random variant of a group).
    func play(_ name: String, volume: Float = 1, pitch: Float = 1) {
        guard available else { return }
        let candidates = variants[name] ?? (files[name] != nil ? [name] : [])
        guard let chosen = candidates.randomElement(), let clip = clip(chosen) else { return }
        let rate = max(0.25, min(4, pitch * Float.random(in: 0.94...1.06)))
        lock.lock()
        if voices.filter({ $0.bus == .sfx }).count >= 28, let oldest = voices.firstIndex(where: { $0.bus == .sfx }) {
            voices.remove(at: oldest)
        }
        voices.append(Voice(clip: clip, position: 0, step: clip.rate / WinAudio.outputRate * Double(rate), gain: volume, bus: .sfx, loopName: nil))
        lock.unlock()
    }

    /// Fades a looping ambience track toward `volume` (0 silences it).
    func setLoop(_ name: String, volume: Float) {
        guard available else { return }
        if loopTargets[name] == nil && volume <= 0 { return }
        loopTargets[name] = volume
        if loopGains[name] == nil, let clip = clip(name) {
            loopGains[name] = 0
            lock.lock()
            voices.append(Voice(clip: clip, position: 0, step: clip.rate / WinAudio.outputRate, gain: 0, bus: .ambient, loopName: name))
            lock.unlock()
        }
    }

    func update(dt: Double) {
        guard available else { return }
        let k = 1 - exp(-Float(dt) * 1.2)
        for (name, target) in loopTargets {
            let current = loopGains[name] ?? 0
            loopGains[name] = current + (target - current) * k
        }
        let gains = loopGains
        lock.lock()
        for i in voices.indices {
            if let name = voices[i].loopName { voices[i].gain = gains[name] ?? 0 }
        }
        lock.unlock()
    }

    func playMusic(_ track: String) {
        guard available, track != currentTrack || !isMusicPlaying else { return }
        currentTrack = track
        lock.lock()
        voices.removeAll { $0.bus == .music }
        lock.unlock()
        guard let url = try? ResourceLocator.url("Music/\(track).wav") else {
            Log.warning("Music track \(track) not found", category: "Audio")
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let clip = WinAudio.loadWAV(url), let self else { return }
            self.lock.lock()
            if self.currentTrack == track {
                self.voices.append(Voice(clip: clip, position: 0, step: clip.rate / WinAudio.outputRate, gain: 1, bus: .music, loopName: nil))
            }
            self.lock.unlock()
            Log.info("Music: \(track)", category: "Audio")
        }
    }

    func stopMusic() {
        currentTrack = nil
        lock.lock()
        voices.removeAll { $0.bus == .music }
        lock.unlock()
    }

    var isMusicPlaying: Bool {
        lock.lock()
        defer { lock.unlock() }
        return voices.contains { $0.bus == .music }
    }

    func stopLoops() {
        for name in loopTargets.keys { loopTargets[name] = 0 }
    }

    func shutdown() {
        if let stream { SDL_DestroyAudioStream(stream) }
        stream = nil
        available = false
    }

    // MARK: Mixing (audio thread)

    private func mix(stream: OpaquePointer?, bytes: Int) {
        let frames = bytes / 4
        guard frames > 0 else { return }
        if mixBuffer.count < frames { mixBuffer = [Float](repeating: 0, count: frames) }
        for f in 0..<frames { mixBuffer[f] = 0 }
        lock.lock()
        var index = 0
        while index < voices.count {
            var voice = voices[index]
            let bus: Float = voice.bus == .sfx ? soundVolume : (voice.bus == .ambient ? ambientVolume : musicVolume)
            let gain = voice.gain * bus * masterVolume
            let samples = voice.clip.samples
            let count = samples.count
            var finished = count < 2
            if !finished {
                for f in 0..<frames {
                    var i = Int(voice.position)
                    if i >= count - 1 {
                        if voice.loopName == nil {
                            finished = true
                            break
                        }
                        voice.position -= Double(count - 1)
                        i = Int(voice.position)
                    }
                    let t = Float(voice.position - Double(i))
                    mixBuffer[f] += (samples[i] + (samples[i + 1] - samples[i]) * t) * gain
                    voice.position += voice.step
                }
            }
            if finished {
                voices.remove(at: index)
            } else {
                voices[index] = voice
                index += 1
            }
        }
        lock.unlock()
        for f in 0..<frames { mixBuffer[f] = max(-1, min(1, mixBuffer[f])) }
        mixBuffer.withUnsafeBytes { raw in _ = SDL_PutAudioStreamData(stream, raw.baseAddress, Int32(frames * 4)) }
    }

    // MARK: WAV files

    /// Reads 16-bit PCM WAV (any channel count, mixed to mono).
    private static func loadWAV(_ url: URL) -> Clip? {
        guard let data = try? Data(contentsOf: url), data.count > 44 else { return nil }
        let bytes = [UInt8](data)
        func u16(_ i: Int) -> Int { Int(bytes[i]) | Int(bytes[i + 1]) << 8 }
        func u32(_ i: Int) -> Int { u16(i) | u16(i + 2) << 16 }
        guard String(decoding: bytes[0..<4], as: UTF8.self) == "RIFF", String(decoding: bytes[8..<12], as: UTF8.self) == "WAVE" else { return nil }
        var pos = 12
        var channels = 1, rate = 44100, bits = 16, format = 1
        while pos + 8 <= bytes.count {
            let id = String(decoding: bytes[pos..<(pos + 4)], as: UTF8.self)
            let size = u32(pos + 4)
            let start = pos + 8
            if id == "fmt " && start + 16 <= bytes.count {
                format = u16(start)
                channels = max(1, u16(start + 2))
                rate = u32(start + 4)
                bits = u16(start + 14)
            } else if id == "data" {
                guard format == 1 || format == 0xFFFE, bits == 16 else { return nil }
                let end = min(bytes.count, start + size)
                let frames = (end - start) / (2 * channels)
                var samples = [Float](repeating: 0, count: frames)
                for f in 0..<frames {
                    var sum = 0
                    for c in 0..<channels {
                        let o = start + (f * channels + c) * 2
                        sum += Int(Int16(bitPattern: UInt16(bytes[o]) | UInt16(bytes[o + 1]) << 8))
                    }
                    samples[f] = Float(sum) / Float(channels) / 32768
                }
                return Clip(samples: samples, rate: Double(rate))
            }
            pos = start + size + (size & 1)
        }
        return nil
    }
}
