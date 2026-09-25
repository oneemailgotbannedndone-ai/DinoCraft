import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// The float on the end of your fishing line.
final class Bobber {
    var position: DVec3
    var velocity: DVec3
    var inWater = false
    var landed = false
    var age = 0.0
    /// Seconds until a fish bites (counting once it's in the water).
    var waitTimer = Double.random(in: 5...18)
    /// Seconds left to reel in a fish that's biting.
    var biteTimer = 0.0
    /// Little nibbles before the bite.
    var nibbleTimer = 0.0

    init(position: DVec3, velocity: DVec3) {
        self.position = position
        self.velocity = velocity
    }

    var biting: Bool { biteTimer > 0 }
}

/// Fishing: cast a rod into water, wait for the float to dip, and reel in fish (and now and then treasure).
enum Fishing {
    static let rod = "fishing_rod"

    struct Catch {
        let item: String
        let weight: Double
        let treasure: Bool
    }

    static let fish: [Catch] = [
        Catch(item: "raw_fish", weight: 60, treasure: false),
        Catch(item: "tropical_fish", weight: 12, treasure: false),
    ]
    static let junk: [Catch] = [
        Catch(item: "stick", weight: 10, treasure: false),
        Catch(item: "dried_kelp", weight: 8, treasure: false),
        Catch(item: "dino_bone", weight: 8, treasure: false),
        Catch(item: "dino_hide", weight: 6, treasure: false),
        Catch(item: "string", weight: 5, treasure: false),
    ]
    static let treasure: [Catch] = [
        Catch(item: "emerald", weight: 5, treasure: true),
        Catch(item: "amber", weight: 5, treasure: true),
        Catch(item: "saddle", weight: 3, treasure: true),
        Catch(item: "bow", weight: 2, treasure: true),
        Catch(item: "diamond", weight: 1, treasure: true),
    ]

    /// What comes up: mostly fish, some junk, a little treasure (a bit more at night and in the rain).
    static func roll(reef: Bool, lucky: Bool) -> Catch {
        let r = Double.random(in: 0..<1)
        let pool: [Catch]
        if r < (lucky ? 0.1 : 0.06) { pool = treasure }
        else if r < 0.2 { pool = junk }
        else if reef { pool = [Catch(item: "tropical_fish", weight: 1, treasure: false)] }
        else { pool = fish }
        let total = pool.reduce(0) { $0 + $1.weight }
        var pick = Double.random(in: 0..<total)
        for c in pool {
            pick -= c.weight
            if pick < 0 { return c }
        }
        return pool[0]
    }
}

extension GameSession {
    /// Right-click with a rod: cast, or reel in (catching whatever is biting).
    func useFishingRod() -> Bool {
        swing()
        if let b = bobber {
            reelIn(b)
            return true
        }
        let look = player.lookDirection
        bobber = Bobber(position: player.eyePosition + look * 0.6 - DVec3(0, 0.1, 0), velocity: look * 13 + DVec3(0, 3, 0))
        onSound?("bow_shoot", 0.4, 0.7)
        return true
    }

    private func reelIn(_ b: Bobber) {
        bobber = nil
        onSound?("bow_shoot", 0.3, 1.4)
        guard b.biting else {
            if b.inWater { onToast?("Too soon! Wait for the float to dip under, then reel in.") }
            return
        }
        guard !isRemote else { return }
        let reef = (world.generator as? TerrainGenerator)?.isReef(x: Int(floor(b.position.x)), z: Int(floor(b.position.z))) ?? false
        let caught = Fishing.roll(reef: reef, lucky: isNight || weather.kind != .clear)
        guard let item = items.id(named: caught.item) else { return }
        // It flies out of the water toward you.
        let to = player.eyePosition - b.position
        let flat = DVec3(to.x, 0, to.z)
        let velocity = flat * 1.1 + DVec3(0, max(4, to.y * 1.2 + simd_length(flat) * 0.45), 0)
        entities.spawnItem(ItemStack(item: item, count: 1), at: b.position + DVec3(0, 0.3, 0), velocity: velocity, pickupDelay: 0)
        effectBursts.append((b.position, .splash))
        onSound?("splash", 0.6, 1.1)
        advancements.record("fish", caught.item)
        if caught.treasure {
            onToast?("Treasure! You fished up \(items[item]?.displayName ?? caught.item).")
            advancements.record("fish", "treasure")
        }
        Log.info("Fished up \(caught.item)", category: "Game")
    }

    /// Moves the float: it flies, lands on water and bobs there until a fish bites.
    func updateFishing(_ dt: Double) {
        guard let b = bobber else { return }
        let holdingRod = inventory.selectedStack.flatMap { items[$0.item]?.name } == Fishing.rod
        if !holdingRod || isDead || simd_distance(b.position, player.position) > 32 || b.age > 300 {
            bobber = nil
            return
        }
        b.age += dt
        let reg = world.registry
        func wet(_ p: DVec3) -> Bool { reg.isWet[Int(world.block(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z))))] }
        if b.inWater {
            // Float at the surface; dip under while a fish bites.
            let x = Int(floor(b.position.x)), z = Int(floor(b.position.z))
            var top = Int(floor(b.position.y))
            while top < Int(floor(b.position.y)) + 3 && reg.isWet[Int(world.block(x, top + 1, z))] { top += 1 }
            let surface = Double(top + 1)
            let bob = sin(b.age * 3) * 0.03
            let target = surface - (b.biting ? 0.35 : 0.08) + bob
            b.position.y += (target - b.position.y) * min(1, dt * 8)
            b.velocity = .zero
            if b.biting {
                b.biteTimer -= dt
                if b.biteTimer <= 0 {
                    // It got away.
                    b.waitTimer = Double.random(in: 6...16)
                }
            } else {
                b.waitTimer -= dt * (weather.kind == .clear ? 1 : 1.35)
                b.nibbleTimer -= dt
                if b.waitTimer < 2.5 && b.nibbleTimer <= 0 {
                    b.nibbleTimer = Double.random(in: 0.5...1.1)
                    effectBursts.append((DVec3(b.position.x, surface, b.position.z), .splash))
                }
                if b.waitTimer <= 0 {
                    b.biteTimer = 1.1
                    effectBursts.append((DVec3(b.position.x, surface, b.position.z), .splash))
                    onSound?("splash", 0.7, 1.3)
                }
            }
            return
        }
        guard !b.landed else { return }
        b.velocity.y -= 22 * dt
        b.velocity *= 1 - 0.3 * dt
        let next = b.position + b.velocity * dt
        if wet(next) {
            b.position = next
            b.inWater = true
            onSound?("splash", 0.4, 1.6)
            effectBursts.append((next, .splash))
            return
        }
        if reg.isSolid[Int(world.block(Int(floor(next.x)), Int(floor(next.y)), Int(floor(next.z))))] {
            b.landed = true
            b.velocity = .zero
            return
        }
        b.position = next
    }

    /// Where the fishing line leaves the rod, for drawing it.
    func rodTip(firstPerson: Bool) -> DVec3 {
        let look = player.lookDirection
        let flat = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(look.x, 0, look.z)) : DVec3(0, 0, -1)
        let right = DVec3(-flat.z, 0, flat.x)
        if firstPerson {
            return player.eyePosition + look * 0.9 + right * 0.62 - DVec3(0, 0.12, 0)
        }
        return player.position + DVec3(0, 1.9, 0) + flat * 0.9 + right * 0.35
    }
}
