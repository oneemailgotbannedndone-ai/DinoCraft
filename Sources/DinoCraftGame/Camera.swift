import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

struct Camera {
    var position = DVec3(0, 100, 0)
    var yaw: Double = 0
    var pitch: Double = 0
    var roll: Double = 0
    var fovY: Double = 75 * .pi / 180
    var near: Float = 0.05
    var far: Float = 1200

    /// Rotation-only view matrix: world geometry is submitted camera-relative so
    /// precision never degrades far from the origin.
    var rotation: Mat4 {
        MathUtil.rotationZ(Float(-roll)) * MathUtil.rotationX(Float(-pitch)) * MathUtil.rotationY(Float(-yaw))
    }

    func projection(aspect: Float) -> Mat4 {
        MathUtil.perspectiveReverseZ(fovyRadians: Float(fovY), aspect: aspect, near: near, far: far)
    }

    func viewProjection(aspect: Float) -> Mat4 { projection(aspect: aspect) * rotation }

    var forward: DVec3 { DVec3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) }
}

struct SkyState {
    var sunDirection = SIMD3<Float>(0, 1, 0)
    var daylight: Float = 1
    var zenith = SIMD3<Float>(0.2, 0.4, 0.9)
    var horizon = SIMD3<Float>(0.6, 0.75, 1)
    var sunsetGlow: Float = 0
    var stars: Float = 0
    var skyLight = SIMD3<Float>(1, 1, 1)
    var isNight: Bool { sunDirection.y < -0.05 }
}

/// Day/night cycle. `worldTime` 0 is sunrise; one full day lasts 20 minutes.
enum SkyModel {
    static let dayLength: Double = 1200

    static func state(worldTime: Double, dimension: WorldDimension) -> SkyState {
        switch dimension {
        case .overworld:
            return state(worldTime: worldTime)
        case .underworld:
            var s = SkyState()
            s.sunDirection = SIMD3(0, -1, 0)
            s.daylight = 0
            s.zenith = lin(0.22, 0.05, 0.03)
            s.horizon = lin(0.36, 0.09, 0.04)
            s.skyLight = SIMD3(1.0, 0.52, 0.34)
            return s
        case .skylands:
            var s = state(worldTime: worldTime)
            s.horizon = simd_mix(s.horizon, lin(1.0, 0.83, 0.58), SIMD3(repeating: 0.35 * s.daylight))
            s.zenith = simd_mix(s.zenith, lin(0.32, 0.64, 0.92), SIMD3(repeating: 0.3 * s.daylight))
            return s
        }
    }

    private static func lin(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        SIMD3(pow(r, 2.2), pow(g, 2.2), pow(b, 2.2))
    }

    static func state(worldTime: Double) -> SkyState {
        let angle = Float((worldTime / dayLength).truncatingRemainder(dividingBy: 1) * 2 * .pi)
        let sun = simd_normalize(SIMD3<Float>(cos(angle), sin(angle), 0.28))
        let e = sun.y
        let t = MathUtil.smoothstep(-0.22, 0.28, e)
        var s = SkyState()
        s.sunDirection = sun
        s.daylight = MathUtil.lerp(0.14, 1.0, MathUtil.smoothstep(-0.14, 0.3, e))
        let dayZ = lin(0.24, 0.47, 0.93), nightZ = lin(0.015, 0.024, 0.07)
        let dayH = lin(0.68, 0.82, 0.98), nightH = lin(0.05, 0.07, 0.14)
        let sunsetH = lin(0.99, 0.6, 0.38)
        s.zenith = simd_mix(nightZ, dayZ, SIMD3(repeating: t))
        let sunset = exp(-(e * e) / 0.035) * (e > -0.3 ? 1 : 0)
        s.horizon = simd_mix(simd_mix(nightH, dayH, SIMD3(repeating: t)), sunsetH, SIMD3(repeating: sunset * 0.7))
        s.sunsetGlow = sunset
        s.stars = 1 - MathUtil.smoothstep(-0.28, 0.02, e)
        let nightLight = SIMD3<Float>(0.42, 0.5, 0.82)
        s.skyLight = simd_mix(nightLight, SIMD3(1, 1, 1), SIMD3(repeating: t))
        s.skyLight = simd_mix(s.skyLight, SIMD3(1.0, 0.82, 0.68), SIMD3(repeating: sunset * 0.35))
        return s
    }

    /// Human-friendly clock text, e.g. "Dawn", "Midday".
    static func periodName(worldTime: Double) -> String {
        let f = (worldTime / dayLength).truncatingRemainder(dividingBy: 1)
        switch f {
        case 0..<0.06: return "Dawn"
        case 0.06..<0.2: return "Morning"
        case 0.2..<0.3: return "Midday"
        case 0.3..<0.44: return "Afternoon"
        case 0.44..<0.54: return "Dusk"
        default: return "Night"
        }
    }
}
