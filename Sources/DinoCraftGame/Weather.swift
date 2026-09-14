import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

enum WeatherKind: String, Codable, CaseIterable {
    case clear, rain, thunder
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
                set(kind == .clear ? (Double.random(in: 0..<1) < 0.25 ? .thunder : .rain) : .clear)
                Log.info("Weather changed to \(kind.rawValue)", category: "Game")
            }
        }
        let target: Float = kind == .clear ? 0 : 1
        intensity += (target - intensity) * Float(min(1, dt * 0.3))
        if intensity < 0.001 { intensity = 0 }
        flash = max(0, flash - Float(dt) * 2.4)
        if kind == .thunder && intensity > 0.5 {
            strikeTimer -= dt
            if strikeTimer <= 0 {
                strikeTimer = Double.random(in: 7...20)
                flash = 1
                onThunder?(Float.random(in: 0.2...1))
            }
        }
    }

    static func precipitation(for biome: Biome) -> Precipitation {
        switch biome {
        case .desert, .redMesa, .volcanicWastes, .savanna, .underworld, .skylands: return .none
        case .snowyTundra, .snowyPeaks, .glacier: return .snow
        default: return .rain
        }
    }

    /// Greys and darkens the sky during rain; brightens it during lightning.
    func apply(to sky: inout SkyState) {
        let k = intensity * (kind == .thunder ? 1 : 0.7)
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
