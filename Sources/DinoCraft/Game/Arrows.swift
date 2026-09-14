import Foundation
import simd
import DinoCraftCore

final class Arrow {
    var position: DVec3
    /// Keeps its last flight direction once stuck, so it renders pointing into the block.
    var velocity: DVec3
    let origin: DVec3
    let damage: Double
    /// Survival arrows can be picked back up after they land.
    let pickup: Bool
    var stuck = false
    var done = false
    var age = 0.0

    init(position: DVec3, velocity: DVec3, damage: Double, pickup: Bool) {
        self.position = position
        self.velocity = velocity
        origin = position
        self.damage = damage
        self.pickup = pickup
    }
}

/// Arrows fired from bows. Each player simulates their own arrows; hits on creatures
/// go through the same path as melee attacks, so they work for friends in multiplayer too.
final class ArrowSystem {
    private(set) var arrows: [Arrow] = []

    func fire(from position: DVec3, velocity: DVec3, damage: Double, pickup: Bool) {
        arrows.append(Arrow(position: position, velocity: velocity, damage: damage, pickup: pickup))
        if arrows.count > 64 { arrows.removeFirst() }
    }

    func clear() { arrows.removeAll() }

    func update(dt: Double, session s: GameSession) {
        for a in arrows where !a.done {
            a.age += dt
            guard !a.stuck else { continue }
            let steps = 4
            let h = dt / Double(steps)
            for _ in 0..<steps {
                a.velocity.y -= 20 * h
                a.velocity *= 1 - 0.2 * h
                let next = a.position + a.velocity * h
                let segment = next - a.position
                let length = simd_length(segment)
                if length > 1e-6 {
                    let dir = segment / length
                    var best: (Mob, Double)?
                    for m in s.mobs.mobs where !m.isDying {
                        if let t = MobManager.rayBox(a.position, dir, m.box), t <= length, t < (best?.1 ?? .infinity) { best = (m, t) }
                    }
                    if let (mob, _) = best {
                        s.arrowHit(mob, arrow: a)
                        a.done = true
                        break
                    }
                }
                let id = s.world.block(Int(floor(next.x)), Int(floor(next.y)), Int(floor(next.z)))
                if s.world.registry.isSolid[Int(id)] {
                    a.stuck = true
                    a.age = 0
                    s.onSound?("arrow_hit", 0.5, Float.random(in: 0.9...1.2))
                    break
                }
                a.position = next
            }
        }
        arrows.removeAll { $0.done || $0.age > ($0.stuck ? 30 : 8) }
    }
}
