import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Spring, summer, autumn and winter, a few days each. Leaves and grass change colour, winter dusts the tops of
/// plants with snow and turns rain to snow, and crops grow faster in spring and slowly in winter.
enum Season: Int, CaseIterable {
    case spring, summer, autumn, winter

    static let daysPerSeason = 6

    var displayName: String { ["Spring", "Summer", "Autumn", "Winter"][rawValue] }

    /// Leaf and grass colour: a target shade (times the pixel's brightness) and how far to blend toward it.
    var tint: SIMD4<Float> {
        switch self {
        case .spring: return SIMD4(1.05, 1.4, 0.55, 0.22)
        case .summer: return SIMD4(1, 1, 1, 0)
        case .autumn: return SIMD4(1.8, 0.95, 0.3, 0.7)
        case .winter: return SIMD4(1.0, 0.96, 0.86, 0.5)
        }
    }

    /// Snow on the tops of grass and leaves.
    var snow: Float { self == .winter ? 0.72 : 0 }

    /// How fast crops grow.
    var cropSpeed: Double {
        switch self {
        case .spring: return 1.3
        case .summer: return 1.0
        case .autumn: return 0.8
        case .winter: return 0.35
        }
    }

    static func at(worldTime: Double) -> Season {
        let day = Int(floor(worldTime / SkyModel.dayLength))
        return Season(rawValue: ((day / daysPerSeason) % 4 + 4) % 4) ?? .spring
    }

    /// The colouring for the renderers, blending into the next season over the last day of each.
    static func look(worldTime: Double, dimension: WorldDimension) -> (tint: SIMD4<Float>, snow: Float) {
        guard dimension == .overworld else { return (SIMD4(1, 1, 1, 0), 0) }
        let days = worldTime / SkyModel.dayLength
        let season = at(worldTime: worldTime)
        let into = days - floor(days / Double(daysPerSeason)) * Double(daysPerSeason)   // days into this season
        let blend = Float(max(0, min(1, into - Double(daysPerSeason - 1))))
        let next = Season(rawValue: (season.rawValue + 1) % 4) ?? .spring
        return (simd_mix(season.tint, next.tint, SIMD4(repeating: blend)), season.snow + (next.snow - season.snow) * blend)
    }
}

extension GameSession {
    var season: Season { Season.at(worldTime: worldTime) }

    /// What falls from the sky here: winter turns rain to snow.
    var precipitation: Precipitation {
        let p = WeatherSystem.precipitation(for: biome)
        return p == .rain && dimension == .overworld && season == .winter ? .snow : p
    }

    /// Announces a new season once as it arrives.
    func updateSeason() {
        guard dimension == .overworld else { return }
        let now = season
        if let last = lastSeason, last != now {
            onToast?("\(now.displayName) has come." + (now == .winter ? " Crops grow slowly in the cold." : (now == .spring ? " Crops grow faster!" : "")))
            advancements.record("season", now.displayName.lowercased())
        }
        lastSeason = now
    }
}
