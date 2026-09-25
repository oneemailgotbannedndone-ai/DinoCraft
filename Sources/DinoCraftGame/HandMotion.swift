import Foundation
import DinoCraftCore

/// Extra movement for the first-person hand and held item, shared by both renderers: the hand
/// lags a little behind the camera when you turn, dips when you land, leans into a sprint,
/// raises food to your mouth, and swords slash sideways while tools chop down.
/// Renderers apply it as `translation(offset) * rotationZ(roll) * rotationY(yaw) * rotationX(pitch)`
/// on top of their usual hand transform.
struct HandMotion {
    var offset = SIMD3<Float>(repeating: 0)
    var pitch: Float = 0
    var yaw: Float = 0
    var roll: Float = 0
}

/// State behind `HandMotion`, advanced every frame by the session.
struct HandAnimator {
    private var swayX: Double = 0, swayY: Double = 0
    private var lastYaw: Double?, lastPitch: Double = 0
    private var landDip: Double = 0
    private var sprintLean: Double = 0
    private var strokePhase: Double = 0
    private var strokeAmount: Double = 0
    private(set) var eatTimer: Double = -1
    private(set) var motion = HandMotion()

    mutating func startEating() { eatTimer = 0 }

    mutating func landed(fallDistance: Double) {
        landDip = min(1, max(landDip, fallDistance / 4))
    }

    mutating func update(dt: Double, player: PlayerController, swing: Double, tool: ToolKind?) {
        // Sway: the hand trails behind quick turns, then springs back.
        if let last = lastYaw {
            var dy = player.yaw - last
            if dy > .pi { dy -= 2 * .pi }
            if dy < -.pi { dy += 2 * .pi }
            swayX += dy * 0.6
            swayY += (player.pitch - lastPitch) * 0.6
        }
        lastYaw = player.yaw
        lastPitch = player.pitch
        let spring = exp(-12 * dt)
        swayX = max(-0.25, min(0.25, swayX * spring))
        swayY = max(-0.25, min(0.25, swayY * spring))
        landDip *= exp(-7 * dt)
        sprintLean += ((player.isSprinting && player.onGround ? 1 : 0) - sprintLean) * (1 - exp(-6 * dt))
        if eatTimer >= 0 {
            eatTimer += dt
            if eatTimer > 0.6 { eatTimer = -1 }
        }

        var m = HandMotion()
        m.offset = SIMD3(Float(swayX) * 0.35, Float(-swayY) * 0.3 - Float(landDip) * 0.12, 0)
        m.yaw = Float(swayX) * 0.6
        m.pitch = Float(-swayY) * 0.4 - Float(sprintLean) * 0.12
        m.roll = Float(sprintLean) * 0.08
        // Swimming strokes: the arm sweeps back and forth while you move through water
        let stroking = player.inWater && !player.onGround && player.horizontalSpeed > 0.6
        strokeAmount += ((stroking ? 1 : 0) - strokeAmount) * (1 - exp(-6 * dt))
        strokePhase += dt * (player.isSwimming ? 7 : 5)
        if strokeAmount > 0.01 {
            let k = Float(sin(strokePhase)) * Float(strokeAmount)
            m.offset += SIMD3(k * 0.1, abs(k) * 0.06, -abs(k) * 0.05)
            m.yaw += k * 0.35
        }
        // Tool-specific swings (on top of the usual chop)
        let s = Float(sin(swing * .pi))
        switch tool {
        case .sword:
            m.roll += s * 0.55
            m.offset.x -= s * 0.1
        case .axe, .pickaxe:
            m.pitch -= s * 0.25
        case .shovel, .hoe:
            m.offset.z -= s * 0.08
        default:
            break
        }
        // Eating: lift toward the mouth and nibble
        if eatTimer >= 0 {
            let t = eatTimer / 0.6
            let lift = Float(sin(min(1, t * 1.6) * .pi / 2) * (t > 0.8 ? (1 - t) * 5 : 1))
            let nibble = Float(abs(sin(eatTimer * 22))) * 0.03 * lift
            m.offset += SIMD3(-0.28 * lift, 0.14 * lift + nibble, 0.12 * lift)
            m.yaw += 0.5 * lift
        }
        motion = m
    }
}
