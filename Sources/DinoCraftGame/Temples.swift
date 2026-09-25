import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Ocean temples and their guardian: a Mosasaurus that circles the temple and hunts anyone who swims near.
extension MobManager {
    static func templeKey(_ t: StructureInfo) -> String { "mosasaurus_\(t.x)_\(t.z)" }

    /// Keeps a Mosasaurus at each nearby temple until it's been beaten.
    func spawnTempleGuardian(_ s: GameSession) {
        guard s.dimension == .overworld, s.meta.difficulty != .peaceful, let generator = s.world.generator as? TerrainGenerator else { return }
        let p = s.player.position
        for t in generator.structures(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: 56) where t.kind == .oceanTemple {
            guard !s.isBossDefeated(MobManager.templeKey(t)) else { continue }
            let center = DVec3(Double(t.x) + 0.5, Double(t.y) + 8, Double(t.z) + 0.5)
            guard !mobs.contains(where: { $0.species.kind == .mosasaurus && !$0.removed && simd_distance($0.position, center) < 60 }),
                  s.world.isLoaded(t.x, t.z) else { continue }
            let m = spawn(.mosasaurus, at: center + DVec3(Double.random(in: -4...4), 0, Double.random(in: -4...4)))
            m.home = center
            Log.info("A Mosasaurus guards the ocean temple at \(t.x), \(t.z)", category: "Game")
        }
    }

    /// Circles its temple; when someone swims close, it charges and bites.
    func updateMosasaurus(_ m: Mob, target: (id: Int, pos: DVec3)?, dt: Double, session s: GameSession) {
        var desired = DVec3.zero, speed = 0.0
        let home = m.home ?? m.position
        if let target, simd_distance(target.pos, home) < 36, simd_distance(target.pos, m.position) < m.species.detectRange,
           s.world.registry.isWet[Int(s.world.block(Int(floor(target.pos.x)), Int(floor(target.pos.y + 0.5)), Int(floor(target.pos.z))))] {
            let aim = target.pos + DVec3(0, 0.6, 0) - (m.position + DVec3(0, m.species.height * 0.5, 0))
            let d = simd_length(aim)
            desired = d > 0.01 ? aim / d : .zero
            speed = m.attackTimer > m.species.attackCooldown * 0.5 ? m.species.walkSpeed : m.species.runSpeed
            if d < m.species.attackReach + 0.6 && m.attackTimer <= 0 {
                m.attackTimer = m.species.attackCooldown
                m.lunge = 1
                s.damageTarget(id: target.id, amount: m.species.damage, cause: "Swallowed by a Mosasaurus", attacker: "Mosasaurus",
                               knockback: simd_length(DVec3(desired.x, 0, desired.z)) > 0.01 ? simd_normalize(DVec3(desired.x, 0, desired.z)) : .zero)
                s.onSound?("amb_dino_low", 0.8, 0.5)
            }
            m.aggroTimer = 5
        } else {
            // Patrol: a slow loop around the temple.
            let angle = atan2(m.position.z - home.z, m.position.x - home.x) + 0.6
            let waypoint = home + DVec3(cos(angle) * 12, sin(s.clock * 0.3) * 2, sin(angle) * 12)
            let to = waypoint - m.position
            let d = simd_length(to)
            desired = d > 0.01 ? to / d : .zero
            speed = m.species.walkSpeed
        }
        swimPhysics(m, desired: desired, speed: speed, dt: dt, session: s)
    }

    /// Beating a temple's Mosasaurus: it's gone for good, and the temple's treasure is yours.
    func mosasaurusDefeated(_ m: Mob, _ s: GameSession) {
        guard let generator = s.world.generator as? TerrainGenerator, let home = m.home else { return }
        if let t = generator.structures(near: Int(floor(home.x)), z: Int(floor(home.z)), radius: 8).first(where: { $0.kind == .oceanTemple }) {
            s.markBossDefeated(MobManager.templeKey(t))
        }
        s.onToast?("You defeated the Mosasaurus! The temple's treasure is yours.")
        s.advancements.record("kill", "mosasaurus")
    }
}
