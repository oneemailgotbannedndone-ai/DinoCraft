import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// A lightning bolt's jagged path, shown for a moment after it strikes.
struct LightningBolt {
    var points: [DVec3]
    var age = 0.0
    static let lifetime = 0.35

    /// Points every half block along the bolt, for drawing it as a chain of glowing specks.
    var samples: [DVec3] {
        var out: [DVec3] = []
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            let steps = max(1, Int(simd_distance(a, b) * 2))
            for k in 0..<steps { out.append(a + (b - a) * (Double(k) / Double(steps))) }
        }
        return out
    }
}

/// Fire: lit by lightning or an Ember Lighter. It spreads to flammable blocks next to it, burns them away,
/// dies down after a while, and rain puts it out. Only the world's owner (or host) runs it.
final class FireManager {
    let fireID: BlockID?
    private var flammable = [Bool](repeating: false, count: BlockRegistry.capacity)
    /// Burning blocks and how long each has left.
    private(set) var fires: [BlockPos: Double] = [:]
    private var tick = 0.0
    static let maxFires = 160

    init(blocks: BlockRegistry) {
        fireID = blocks.id(named: "fire")
        let words = ["log", "leaves", "planks", "needles", "wool", "carpet", "hay", "bookshelf", "fronds", "tall_grass", "dry_grass",
                     "fern", "bush", "barrel", "painting", "item_frame", "horsetail", "cattail"]
        for b in blocks.all where words.contains(where: { b.name.contains($0) }) && !b.name.hasPrefix("toon_") {
            flammable[Int(b.id)] = true
        }
    }

    func isFlammable(_ id: BlockID) -> Bool { flammable[Int(id)] }

    func noteChange(_ pos: BlockPos, _ id: BlockID) {
        if id == fireID {
            if fires[pos] == nil { fires[pos] = Double.random(in: 7...14) }
        } else {
            fires[pos] = nil
        }
    }

    func clear() { fires.removeAll() }

    // Fires still burning when you leave keep burning (and go out) when you come back.
    func save(to url: URL) {
        let list = fires.map { [Double($0.key.x), Double($0.key.y), Double($0.key.z), $0.value] }
        do { try AtomicFile.write(JSONEncoder().encode(list), to: url) } catch { Log.error("Failed to save fires: \(error)", category: "Save") }
    }

    func load(from url: URL) {
        fires.removeAll()
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([[Double]].self, from: data) else { return }
        for f in list where f.count == 4 { fires[BlockPos(Int(f[0]), Int(f[1]), Int(f[2]))] = f[3] }
    }

    func update(dt: Double, session s: GameSession) {
        guard let fireID, !fires.isEmpty else { return }
        tick -= dt
        guard tick <= 0 else { return }
        let step = 0.5
        tick = step
        let world = s.world
        let raining = s.weather.intensity > 0.4 && s.precipitation != .none
        let spread = s.meta.rule("doFireTick")
        for (pos, left) in fires {
            guard world.block(pos) == fireID else { fires[pos] = nil; continue }
            // Rain puts out fires under the open sky.
            if raining && world.light(at: DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.5, Double(pos.z) + 0.5)).sky > 0.9 {
                s.naturalPlace(pos, Blocks.air)
                continue
            }
            let remaining = left - step
            if spread {
                for f in CircuitManager.faces {
                    let n = pos.offset(f)
                    let id = world.block(n)
                    guard flammable[Int(id)], fires.count < FireManager.maxFires, Double.random(in: 0..<1) < 0.06 else { continue }
                    // The block catches: it burns away into flames.
                    s.naturalPlace(n, fireID)
                }
            }
            if remaining <= 0 {
                // Dying down: sometimes the block it sat on is burnt up too.
                let below = pos.offset(.down)
                if spread && flammable[Int(world.block(below))] && Double.random(in: 0..<1) < 0.5 { s.naturalPlace(below, Blocks.air) }
                s.naturalPlace(pos, Blocks.air)
            } else {
                fires[pos] = remaining
            }
        }
    }
}

extension GameSession {
    /// Lights a fire in `pos` if it's empty and there's something under it to burn on.
    @discardableResult
    func lightFire(at pos: BlockPos) -> Bool {
        guard let fire = fires.fireID else { return false }
        let here = world.block(pos)
        guard here == Blocks.air || blocks[here]?.replaceable == true, !blocks.isWet[Int(here)] else { return false }
        let below = world.block(pos.offset(.down))
        guard blocks.isSolid[Int(below)] || fires.isFlammable(below) else { return false }
        return naturalPlaceChecked(pos, fire)
    }

    /// A lightning strike somewhere near you (`closeness` 1 is right on top of you).
    func lightningStrike(closeness: Float) {
        guard dimension == .overworld else { return }
        let distance = 6 + Double(1 - closeness) * 50
        let a = Double.random(in: 0..<(2 * .pi))
        let x = Int(floor(player.position.x + cos(a) * distance)), z = Int(floor(player.position.z + sin(a) * distance))
        guard world.isLoaded(x, z), let slot = world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4))) else { return }
        let top = Int(slot.chunk.heightMap[(z & 15) * 16 + (x & 15)]) - 1
        guard top > 0 else { return }
        let ground = DVec3(Double(x) + 0.5, Double(top) + 1, Double(z) + 0.5)
        // A jagged path down from the clouds.
        var points: [DVec3] = []
        var p = ground + DVec3(Double.random(in: -6...6), 70, Double.random(in: -6...6))
        for i in 0..<14 {
            points.append(p)
            let t = Double(i + 1) / 14
            let target = ground + (points[0] - ground) * (1 - t)
            p = target + DVec3(Double.random(in: -1.6...1.6), 0, Double.random(in: -1.6...1.6))
        }
        points.append(ground)
        hazards.bolts.append(LightningBolt(points: points))
        effectBursts.append((ground, .impact))
        // Anyone standing right there gets a nasty shock.
        if simd_distance(player.position, ground) < 3.5 {
            takeDamage(8, cause: "Struck by lightning", knockback: nil)
            advancements.record("struck")
        }
        if !isRemote {
            for m in mobs.mobs where !m.isDying && !m.removed && simd_distance(m.position, ground) < 3 {
                mobs.hurt(m, amount: 10, knockback: .zero, session: self)
            }
            // Lightning sets grass, leaves and wood alight (unless the rain is heavy enough to stop it).
            if Double.random(in: 0..<1) < 0.55, lightFire(at: BlockPos(x, top + 1, z)) {
                Log.info("Lightning started a fire at \(x), \(top + 1), \(z)", category: "Game")
            }
        }
    }

    /// Fire: standing in it burns.
    func updateFire(_ dt: Double) {
        if !isRemote { fires.update(dt: dt, session: self) }
        for i in hazards.bolts.indices { hazards.bolts[i].age += dt }
        hazards.bolts.removeAll { $0.age > LightningBolt.lifetime }
        guard let fire = fires.fireID, !isDead, !spectator else { return }
        let feet = BlockPos(Int(floor(player.position.x)), Int(floor(player.position.y + 0.1)), Int(floor(player.position.z)))
        if world.block(feet) == fire || world.block(feet.offset(.up)) == fire {
            burnTimer -= dt
            if burnTimer <= 0 {
                burnTimer = 0.5
                takeDamage(1, cause: "Burned to a crisp", knockback: nil)
            }
        } else {
            burnTimer = 0
        }
    }
}
