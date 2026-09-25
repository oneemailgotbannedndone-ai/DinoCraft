import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

enum WeatherKind: String, Codable, CaseIterable {
    case clear, rain, thunder, storm

    /// Thunderstorms and full storms: lightning, darker skies, monsters about.
    var stormy: Bool { self == .thunder || self == .storm }
}

enum Precipitation {
    case none, rain, snow
}

/// Rain, snow and thunderstorms. Single-player worlds and multiplayer hosts roll
/// the weather; friends who joined mirror what the host sends.
final class WeatherSystem {
    private(set) var kind: WeatherKind = .clear
    /// Seconds until the weather changes on its own.
    private(set) var timer: Double = Double.random(in: 600...1500)
    /// Smoothed 0…1 strength of the current rain or snow.
    private(set) var intensity: Float = 0
    /// Brief sky flash after a lightning strike.
    private(set) var flash: Float = 0
    private var strikeTimer = 6.0
    /// Called on each lightning strike with a 0…1 closeness.
    var onThunder: ((Float) -> Void)?
    /// Storm wind (east, south) in blocks per second: slants the rain and pushes you about in gusts.
    private(set) var wind = SIMD2<Float>(0, 0)
    private var windAngle = Float.random(in: 0..<(2 * .pi))
    private var gustPhase = 0.0
    /// How much heavier than normal rain falls (storms pour).
    var downpour: Float { kind == .storm ? 1.35 : 1 }

    func set(_ kind: WeatherKind, duration: Double? = nil) {
        self.kind = kind
        timer = duration ?? (kind == .clear ? Double.random(in: 600...1500) : Double.random(in: 240...600))
    }

    func mirror(_ kind: WeatherKind) {
        self.kind = kind
    }

    func update(dt: Double, authoritative: Bool, cycle: Bool) {
        if authoritative && cycle {
            timer -= dt
            if timer <= 0 {
                let roll = Double.random(in: 0..<1)
                set(kind == .clear ? (roll < 0.1 ? .storm : (roll < 0.3 ? .thunder : .rain)) : .clear)
                Log.info("Weather changed to \(kind.rawValue)", category: "Game")
            }
        }
        let target: Float = kind == .clear ? 0 : 1
        intensity += (target - intensity) * Float(min(1, dt * 0.3))
        if intensity < 0.001 { intensity = 0 }
        flash = max(0, flash - Float(dt) * 2.4)
        // Storm wind: a slowly turning direction with gusts.
        gustPhase += dt
        windAngle += Float(dt) * 0.02
        let gust = Float(0.6 + 0.4 * sin(gustPhase * 0.7) * sin(gustPhase * 0.23 + 1))
        let targetWind = kind == .storm ? SIMD2(cos(windAngle), sin(windAngle)) * 7 * gust * intensity : SIMD2<Float>(0, 0)
        wind += (targetWind - wind) * Float(min(1, dt * 0.8))
        if kind.stormy && intensity > 0.5 {
            strikeTimer -= dt
            if strikeTimer <= 0 {
                strikeTimer = kind == .storm ? Double.random(in: 3...9) : Double.random(in: 7...20)
                flash = 1
                onThunder?(Float.random(in: 0.2...1))
            }
        }
    }

    static func precipitation(for biome: Biome) -> Precipitation {
        switch biome {
        case .desert, .redMesa, .volcanicWastes, .savanna, .underworld, .skylands, .toonland: return .none
        case .snowyTundra, .snowyPeaks, .glacier: return .snow
        default: return .rain
        }
    }

    /// Greys and darkens the sky during rain; brightens it during lightning.
    func apply(to sky: inout SkyState) {
        let k = intensity * (kind == .storm ? 1.1 : (kind == .thunder ? 1 : 0.7))
        if k > 0.001 {
            let luma = simd_dot(sky.horizon, SIMD3(0.3, 0.59, 0.11))
            sky.horizon = simd_mix(sky.horizon, SIMD3(repeating: luma * 0.8), SIMD3(repeating: k * 0.8))
            sky.zenith = simd_mix(sky.zenith, SIMD3(repeating: luma * 0.62), SIMD3(repeating: k * 0.85))
            sky.daylight *= 1 - 0.45 * k
            sky.skyLight = simd_mix(sky.skyLight, SIMD3(0.7, 0.72, 0.78), SIMD3(repeating: k * 0.6))
            sky.sunsetGlow *= 1 - k
            sky.stars *= 1 - k
        }
        if flash > 0 {
            let f = flash * flash
            sky.horizon += SIMD3(repeating: f * 0.55)
            sky.zenith += SIMD3(repeating: f * 0.45)
            sky.daylight = min(1, sky.daylight + f * 0.6)
        }
    }
}
