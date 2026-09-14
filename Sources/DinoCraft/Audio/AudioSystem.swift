import Foundation
import AVFoundation
import QuartzCore
import DinoCraftCore

/// AVAudioEngine-based audio: a pool of pitched one-shot voices for effects,
/// fading ambience loops on their own bus, and streamed music tracks.
/// If no audio device is available the game continues silently.
final class AudioSystem {
    private final class Voice {
        let player = AVAudioPlayerNode()
        let varispeed = AVAudioUnitVarispeed()
        var startedAt: Double = 0
        var endsAt: Double = 0
    }

    private final class Loop {
        let player = AVAudioPlayerNode()
        var volume: Float = 0
        var target: Float = 0
        var playing = false
    }

    private let engine = AVAudioEngine()
    private let sfxBus = AVAudioMixerNode()
    private let ambientBus = AVAudioMixerNode()
    private let monoFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
    private var voices: [Voice] = []
    private var loops: [String: Loop] = [:]
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var files: [String: URL] = [:]
    private var variants: [String: [String]] = [:]
    private var music: AVAudioPlayer?
    private(set) var currentTrack: String?
    private var masterVolume: Float = 0.8
    private var musicVolume: Float = 0.5
    private(set) var available = false

    init() {
        for url in ResourceLocator.files(in: "Sounds", withExtension: "wav") {
            let name = url.deletingPathExtension().lastPathComponent
            files[name] = url
            if let r = name.range(of: "_[0-9]+$", options: .regularExpression) {
                variants[String(name[..<r.lowerBound]), default: []].append(name)
            }
        }
        engine.attach(sfxBus)
        engine.attach(ambientBus)
        engine.connect(sfxBus, to: engine.mainMixerNode, format: nil)
        engine.connect(ambientBus, to: engine.mainMixerNode, format: nil)
        for _ in 0..<24 {
            let v = Voice()
            engine.attach(v.player)
            engine.attach(v.varispeed)
            engine.connect(v.player, to: v.varispeed, format: monoFormat)
            engine.connect(v.varispeed, to: sfxBus, format: monoFormat)
            voices.append(v)
        }
        for name in files.keys where !name.hasPrefix("amb_") { _ = buffer(name) }
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.handleConfigurationChange()
        }
        start()
        Log.info("Audio: \(files.count) sounds indexed, \(buffers.count) preloaded, running=\(available)", category: "Audio")
    }

    private func start() {
        do {
            engine.prepare()
            try engine.start()
            available = true
        } catch {
            available = false
            Log.error("Audio engine failed to start (\(error)); continuing without sound", category: "Audio")
        }
    }

    private func handleConfigurationChange() {
        Log.info("Audio output configuration changed; restarting audio engine", category: "Audio")
        for l in loops.values { l.playing = false }
        if !engine.isRunning { start() }
    }

    private func buffer(_ name: String) -> AVAudioPCMBuffer? {
        if let b = buffers[name] { return b }
        guard let url = files[name] else { return nil }
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.processingFormat.channelCount == 1, file.processingFormat.sampleRate == 44100,
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
                Log.warning("Sound \(name) has an unsupported format", category: "Audio")
                files[name] = nil
                return nil
            }
            try file.read(into: buf)
            buffers[name] = buf
            return buf
        } catch {
            Log.error("Could not load sound \(name): \(error)", category: "Audio")
            files[name] = nil
            return nil
        }
    }

    /// Plays a one-shot. `name` may be a variant group ("step_grass" → step_grass_1…4).
    func play(_ name: String, volume: Float = 1, pitch: Float = 1) {
        guard available, engine.isRunning else { return }
        let candidates = variants[name] ?? (files[name] != nil ? [name] : [])
        guard let chosen = candidates.randomElement(), let buf = buffer(chosen) else { return }
        let now = CACurrentMediaTime()
        let voice = voices.first(where: { $0.endsAt < now }) ?? voices.min(by: { $0.startedAt < $1.startedAt })!
        let rate = max(0.25, min(4, pitch * Float.random(in: 0.94...1.06)))
        voice.player.stop()
        voice.varispeed.rate = rate
        voice.player.volume = volume
        voice.player.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        voice.player.play()
        voice.startedAt = now
        voice.endsAt = now + Double(buf.frameLength) / 44100 / Double(rate) + 0.05
    }

    /// Sets the target volume of a looping ambience track (0 fades it out).
    func setLoop(_ name: String, volume: Float) {
        guard available else { return }
        if let l = loops[name] { l.target = volume; return }
        guard volume > 0, buffer(name) != nil else { return }
        let l = Loop()
        engine.attach(l.player)
        engine.connect(l.player, to: ambientBus, format: monoFormat)
        l.target = volume
        loops[name] = l
    }

    func stopAllLoops() {
        for l in loops.values { l.target = 0 }
    }

    func update(dt: Double) {
        guard available else { return }
        let k = 1 - exp(-Float(dt) * 1.2)
        for (name, l) in loops {
            l.volume += (l.target - l.volume) * k
            if l.target > 0 && !l.playing, engine.isRunning, let buf = buffer(name) {
                l.player.scheduleBuffer(buf, at: nil, options: .loops, completionHandler: nil)
                l.player.play()
                l.playing = true
            }
            if l.target == 0 && l.volume < 0.003 && l.playing {
                l.player.stop()
                l.playing = false
            }
            l.player.volume = l.volume
        }
    }

    // MARK: Music

    func playMusic(_ track: String, loop: Bool, fade: Double) {
        guard let url = try? ResourceLocator.url("Music/\(track).m4a") else {
            Log.warning("Music track \(track) not found", category: "Audio")
            return
        }
        stopMusic(fade: min(fade, 1.5))
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = loop ? -1 : 0
            player.volume = 0
            player.prepareToPlay()
            player.play()
            player.setVolume(musicVolume * masterVolume, fadeDuration: fade)
            music = player
            currentTrack = track
            Log.info("Music: \(track)", category: "Audio")
        } catch {
            Log.error("Could not play music \(track): \(error)", category: "Audio")
        }
    }

    func stopMusic(fade: Double) {
        guard let old = music else { return }
        old.setVolume(0, fadeDuration: fade)
        DispatchQueue.main.asyncAfter(deadline: .now() + fade + 0.1) { old.stop() }
        music = nil
        currentTrack = nil
    }

    var isMusicPlaying: Bool { music?.isPlaying ?? false }

    func applyVolumes(_ s: GameSettings) {
        masterVolume = Float(s.masterVolume)
        musicVolume = Float(s.musicVolume)
        engine.mainMixerNode.outputVolume = masterVolume
        sfxBus.outputVolume = Float(s.soundVolume)
        ambientBus.outputVolume = Float(s.ambientVolume)
        music?.volume = musicVolume * masterVolume
    }

    func shutdown() {
        music?.stop()
        engine.stop()
    }
}
