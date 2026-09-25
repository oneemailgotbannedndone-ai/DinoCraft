import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Boats: placed on water (or land) from the boat item, ridden like a saddled dinosaur, and broken
/// back into the item with a hit. They float at the surface, glide fast on water and crawl on land.
enum Boats {
    static let item = "boat"
    /// Where the rider sits, above the bottom of the boat.
    static let seat = 0.2
    static let waterSpeed = 6.2
    static let sprintSpeed = 8.4
    static let landSpeed = 1.0
}

extension MobManager {
    /// The top of the water under a boat, if there's water within a block of its bottom.
    private func waterSurface(under m: Mob, world: World) -> Double? {
        let reg = world.registry
        let x = Int(floor(m.position.x)), z = Int(floor(m.position.z))
        let base = Int(floor(m.position.y + 0.3))
        for y in stride(from: base + 1, through: base - 1, by: -1) where reg.isWet[Int(world.block(x, y, z))] {
            return Double(y + 1)
        }
        return nil
    }

    func boatPhysics(_ m: Mob, dt: Double, session s: GameSession) {
        let world = s.world
        let surface = waterSurface(under: m, world: world)
        m.inLiquid = surface != nil
        if let surface {
            // Float with the deck just above the water, rocking gently.
            let target = surface - 0.12 + sin(s.clock * 1.7 + Double(m.id)) * 0.02
            m.velocity.y += ((target - m.position.y) * 7 - m.velocity.y) * min(1, dt * 6)
        } else {
            m.velocity.y = max(-40, m.velocity.y - 26 * dt)
        }
        let input = m.rideInput ?? .zero
        let top = m.inLiquid ? (m.rideSprint ? Boats.sprintSpeed : Boats.waterSpeed) : Boats.landSpeed
        let k = 1 - exp(-(m.inLiquid ? (simd_length(input) > 0 ? 1.8 : 0.9) : 8) * dt)
        m.velocity.x += (input.x * top - m.velocity.x) * k
        m.velocity.z += (input.z * top - m.velocity.z) * k
        let blocked = move(m, m.velocity * dt, world)
        // Nudge up onto a low bank so you can land the boat.
        if blocked && simd_length(input) > 0 && (m.onGround || m.inLiquid) { m.velocity.y = max(m.velocity.y, 5.5) }

        let horizontal = DVec3(m.velocity.x, 0, m.velocity.z)
        let hs = simd_length(horizontal)
        if hs > 0.4 {
            m.yaw = MobManager.lerpAngle(m.yaw, atan2(-horizontal.x, -horizontal.z), 1 - exp(-4 * dt))
        }
        // The oars row while it's moving.
        m.moveAmount += (min(1, hs / 3) - m.moveAmount) * (1 - exp(-6 * dt))
        m.walkPhase += dt * (1.5 + 5 * m.moveAmount)
        if hs > 3 && m.inLiquid && Double.random(in: 0..<1) < dt * 3 {
            s.effectBursts.append((m.position + DVec3(0, 0.1, 0) - horizontal / hs * 0.9, .splash))
        }
        if m.position.y < -80 { m.removed = true }
    }

    /// A hit breaks a boat back into the item (none in Creative).
    func breakBoat(_ m: Mob, session s: GameSession) {
        guard !m.removed else { return }
        m.removed = true
        if s.riding === m { s.dismount() }
        s.onSound?("break_wood", 0.7, 1.1)
        s.effectBursts.append((m.position + DVec3(0, 0.3, 0), .dust))
        if s.player.gameMode == .survival, let item = s.items.id(named: Boats.item) {
            s.entities.spawnItem(ItemStack(item: item, count: 1), at: m.position + DVec3(0, 0.4, 0),
                                 velocity: DVec3(0, 3, 0), pickupDelay: 0.3)
        }
    }
}

extension GameSession {
    /// Puts a boat on the water you're looking at (or on the ground).
    func placeBoat() -> Bool {
        let eye = player.eyePosition
        let look = player.lookDirection
        let reg = world.registry
        var spot: DVec3?
        var t = 0.0
        while t < 5.5 {
            let p = eye + look * t
            let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
            let id = world.block(x, y, z)
            if reg.isWet[Int(id)] {
                // Float it on the surface of this water.
                var top = y
                while top < y + 4 && reg.isWet[Int(world.block(x, top + 1, z))] { top += 1 }
                guard !reg.isSolid[Int(world.block(x, top + 1, z))] else { return false }
                spot = DVec3(p.x, Double(top + 1) - 0.12, p.z)
                break
            }
            if reg.isSolid[Int(id)] {
                guard !reg.isSolid[Int(world.block(x, y + 1, z))] else { return false }
                spot = DVec3(p.x, Double(y + 1), p.z)
                break
            }
            t += 0.1
        }
        guard let spot else { return false }
        swing()
        let yaw = atan2(-look.x, -look.z)
        if !(network?.spawnMob(.boat, at: spot) ?? false) {
            let boat = mobs.spawn(.boat, at: spot)
            boat.yaw = yaw
        }
        onSound?("place_wood", 0.8, 1)
        if player.gameMode == .survival { inventory.consumeSelected() }
        advancements.record("place", Boats.item)
        return true
    }
}
