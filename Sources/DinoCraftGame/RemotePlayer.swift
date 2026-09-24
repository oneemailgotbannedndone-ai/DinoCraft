import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
#endif
import DinoCraftCore

/// Another player in a multiplayer game, interpolated from network snapshots.
final class RemotePlayer {
    let id: Int
    var name: String
    var position: DVec3
    var targetPosition: DVec3
    var yaw: Double = 0
    var targetYaw: Double = 0
    var pitch: Double = 0
    var moving: Double = 0
    var walkPhase: Double = 0
    var sneaking = false
    var swing: Double = 0
    var held: String?
    /// Their cosmetics (`PlayerLook.encoded`), or nil for the default look.
    var look: String?
    var health: Double = 20
    var dead = false
    var hurtTimer: Double = 0
    var lastUpdate = 0.0

    init(id: Int, name: String, position: DVec3) {
        self.id = id
        self.name = name
        self.position = position
        self.targetPosition = position
    }

    func apply(_ s: PlayerStateMessage, now: Double) {
        let newTarget = DVec3(s.x, s.y, s.z)
        if simd_distance(newTarget, position) > 16 { position = newTarget }
        if s.health < Float(health) { hurtTimer = 0.35 }
        targetPosition = newTarget
        targetYaw = Double(s.yaw)
        pitch = Double(s.pitch)
        moving = Double(s.moving)
        sneaking = s.sneaking
        if s.swinging { swing = 1 }
        held = s.held
        if let l = s.look { look = l }
        health = Double(s.health)
        dead = s.dead
        lastUpdate = now
    }

    func update(dt: Double) {
        position += (targetPosition - position) * min(1, dt * 14)
        yaw = MobManager.lerpAngle(yaw, targetYaw, min(1, dt * 14))
        walkPhase += moving * dt * 7
        swing = max(0, swing - dt * 3.5)
        hurtTimer = max(0, hurtTimer - dt)
    }

    var box: DBox {
        DBox(min: position - DVec3(0.3, 0, 0.3), max: position + DVec3(0.3, sneaking ? 1.5 : 1.8, 0.3))
    }
}
