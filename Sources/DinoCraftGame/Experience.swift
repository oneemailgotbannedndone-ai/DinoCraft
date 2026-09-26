import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// A glowing experience orb: drifts to the ground, then floats to a nearby player.
final class XPOrb {
    var position: DVec3
    var velocity: DVec3
    let value: Int
    var age = 0.0
    var removed = false

    init(position: DVec3, velocity: DVec3, value: Int) {
        self.position = position
        self.velocity = velocity
        self.value = value
    }
}

/// Experience: orbs from defeating creatures, mining ore and smelting; levels spent at the enchanting table.
enum Experience {
    /// Points from one level to the next (the same curve as the classic game).
    static func pointsToNext(level: Int) -> Int {
        if level < 16 { return 2 * level + 7 }
        if level < 31 { return 5 * level - 38 }
        return 9 * level - 158
    }

    /// Level and progress (0…1) toward the next for a total number of points.
    static func level(forTotal total: Int) -> (level: Int, progress: Double) {
        var level = 0, left = max(0, total)
        while left >= pointsToNext(level: level) && level < 1000 {
            left -= pointsToNext(level: level)
            level += 1
        }
        return (level, Double(left) / Double(pointsToNext(level: level)))
    }

    /// Total points needed to reach `level` from nothing.
    static func total(forLevel level: Int) -> Int {
        (0..<max(0, level)).reduce(0) { $0 + pointsToNext(level: $1) }
    }

    /// Orbs from mining a block (ores only).
    static func points(forMining name: String) -> Int {
        switch name {
        case "coal_ore", "deepslate_coal_ore": return Int.random(in: 0...2)
        case "iron_ore", "copper_ore", "deepslate_iron_ore": return Int.random(in: 1...2)
        case "gold_ore", "deepslate_gold_ore", "amber_ore": return Int.random(in: 1...3)
        case "redstone_ore", "lapis_ore": return Int.random(in: 2...5)
        case "diamond_ore", "deepslate_diamond_ore", "emerald_ore", "meteorite_ore": return Int.random(in: 3...7)
        case "fossil_deposit": return Int.random(in: 1...3)
        default: return name.hasSuffix("_ore") ? Int.random(in: 1...3) : 0
        }
    }

    /// Orbs from defeating a creature.
    static func points(forDefeating species: MobSpecies) -> Int {
        switch species.kind {
        case .grumblesaurus: return 250
        case .mosasaurus: return 120
        case .egg, .boat: return 0
        default:
            if species.hostile { return max(3, Int(species.maxHealth / 4)) + Int.random(in: 0...2) }
            return species.aquatic ? Int.random(in: 1...3) : Int.random(in: 1...3)
        }
    }

    static let pickupRange = 7.0
}

extension GameSession {
    var xpLevel: Int { Experience.level(forTotal: xpPoints).level }
    var xpProgress: Double { Experience.level(forTotal: xpPoints).progress }

    /// Drops `points` of experience as a few orbs at `position` (in joined games you get it straight away).
    func spawnXP(_ points: Int, at position: DVec3) {
        guard points > 0 else { return }
        if isRemote { addXP(points); return }
        var left = points
        while left > 0 {
            let value = left >= 20 ? 10 : (left >= 7 ? 5 : (left >= 3 ? 3 : 1))
            left -= value
            let v = DVec3(Double.random(in: -1.5...1.5), Double.random(in: 2.5...4.5), Double.random(in: -1.5...1.5))
            orbs.append(XPOrb(position: position, velocity: v, value: value))
        }
        if orbs.count > 200 { orbs.removeFirst(orbs.count - 200) }
    }

    func addXP(_ points: Int) {
        guard points > 0 else { return }
        let before = xpLevel
        xpPoints = min(xpPoints + points, Experience.total(forLevel: 200))
        let after = xpLevel
        onSound?("pickup", 0.3, Float.random(in: 1.4...1.9))
        if after > before {
            onSound?("discover", 0.5, 1.2)
            if after % 5 == 0 { onToast?("Level \(after)!") }
            advancements.record("level", amount: after - before)
        }
    }

    /// Spends `levels` whole levels (keeping the progress within the current one where possible).
    @discardableResult
    func spendLevels(_ levels: Int) -> Bool {
        guard player.gameMode == .creative || xpLevel >= levels else { return false }
        guard player.gameMode != .creative else { return true }
        let (level, progress) = Experience.level(forTotal: xpPoints)
        let target = level - levels
        xpPoints = Experience.total(forLevel: target) + Int(progress * Double(Experience.pointsToNext(level: target)))
        return true
    }

    /// Orbs fall, settle and float to you when you're close.
    func updateOrbs(_ dt: Double) {
        guard !orbs.isEmpty else { return }
        let target = player.position + DVec3(0, 0.8, 0)
        let pickUp = !isDead && !spectator
        for o in orbs where !o.removed {
            o.age += dt
            if o.age > 300 { o.removed = true; continue }
            if o.age < 0 { continue }   // held in place (screenshots)
            let to = target - o.position
            let d = simd_length(to)
            if pickUp && d < Experience.pickupRange && o.age > 0.5 {
                if d < 1.1 {
                    o.removed = true
                    addXP(o.value)
                    continue
                }
                // Home in faster as it gets close.
                let pull = (1 - d / Experience.pickupRange) * 22 + 3
                o.velocity += (to / d * pull - o.velocity) * min(1, dt * 4)
                o.position += o.velocity * dt
                continue
            }
            o.velocity.y -= 14 * dt
            o.velocity.x *= exp(-2 * dt)
            o.velocity.z *= exp(-2 * dt)
            var next = o.position + o.velocity * dt
            let bx = Int(floor(next.x)), by = Int(floor(next.y - 0.1)), bz = Int(floor(next.z))
            if blocks.isSolid[Int(world.block(bx, by, bz))] {
                next.y = Double(by + 1) + 0.1
                o.velocity.y = 0
                o.velocity.x *= 0.5
                o.velocity.z *= 0.5
            }
            if blocks.isSolid[Int(world.block(bx, Int(floor(next.y)), bz))] {
                next.x = o.position.x
                next.z = o.position.z
            }
            o.position = next
            if o.position.y < -80 { o.removed = true }
        }
        orbs.removeAll { $0.removed }
    }
}

extension GameSession {
    /// Experience for defeating a creature (once per creature).
    func rewardKill(_ mob: Mob) {
        guard !mob.rewarded else { return }
        mob.rewarded = true
        spawnXP(Experience.points(forDefeating: mob.species), at: mob.position + DVec3(0, mob.species.height * 0.5, 0))
    }
}
