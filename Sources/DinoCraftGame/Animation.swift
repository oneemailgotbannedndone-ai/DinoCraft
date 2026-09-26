import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Extra life for creature models, worked out once per creature and drawn the same way on Mac and Windows:
/// heads turn to watch you, plant-eaters dip to graze, tails swing out when they turn, and everyone breathes.
extension Mob {
    /// Called every frame (also for friends' copies of the host's creatures).
    func animate(dt: Double, watcher: DVec3, clock: Double) {
        let k = 1 - exp(-6 * dt)
        // Tail lag: swing out opposite the way it's turning.
        var turn = yaw - lastAnimYaw
        while turn > .pi { turn -= 2 * .pi }
        while turn < -.pi { turn += 2 * .pi }
        lastAnimYaw = yaw
        let turnRate = dt > 0 ? turn / dt : 0
        tailSwing += (max(-0.6, min(0.6, -turnRate * 0.18)) - tailSwing) * k

        // Watching: turn the head toward someone close by (not while charging or eating).
        var targetYaw = 0.0, targetPitch = 0.0
        let to = watcher - position
        let flat = DVec3(to.x, 0, to.z)
        let distance = simd_length(flat)
        if distance < 10 && distance > 0.5 && moveAmount < 0.6 && !isDying && species.kind != .boat && species.kind != .armorStand {
            var rel = atan2(-flat.x, -flat.z) - yaw
            while rel > .pi { rel -= 2 * .pi }
            while rel < -.pi { rel += 2 * .pi }
            if abs(rel) < 1.9 { targetYaw = max(-0.9, min(0.9, rel)) }
        }
        // Grazing: plant-eaters standing still now and then lower their heads.
        if !species.hostile && !species.flying && !species.aquatic && moveAmount < 0.1 {
            grazeTimer -= dt
            if grazeTimer <= 0 { grazeTimer = Double.random(in: 8...20); grazeLeft = Double.random(in: 1.5...3.5) }
        }
        if grazeLeft > 0 {
            grazeLeft -= dt
            if moveAmount > 0.2 { grazeLeft = 0 }
            targetPitch = 0.55
            targetYaw *= 0.2
        }
        headYaw += (targetYaw - headYaw) * k
        headPitch += (targetPitch - headPitch) * (1 - exp(-4 * dt))
        breath = sin(clock * 1.9 + Double(id % 97) * 0.7)
    }
}

extension MobManager {
    func animateAll(dt: Double, session s: GameSession) {
        let eye = s.player.position + DVec3(0, 1.4, 0)
        for m in mobs where !m.removed { m.animate(dt: dt, watcher: eye, clock: s.clock) }
    }
}
