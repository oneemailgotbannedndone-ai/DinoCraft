import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Treasure maps (found in shipwrecks) lead to chests buried under a beach: the paper map shows the X.
enum TreasureMaps {
    static let item = "treasure_map"
    private static let bias = Int(Int32.max) + 1

    /// A map remembers its treasure in its `damage`: both coordinates packed together (0 until first read).
    static func pack(x: Int, z: Int) -> Int { ((x + bias) << 32) | (z + bias) }
    static func unpack(_ v: Int) -> (x: Int, z: Int)? {
        guard v != 0 else { return nil }
        return ((v >> 32) - bias, (v & 0xFFFF_FFFF) - bias)
    }
}

extension GameSession {
    /// Where each treasure map you carry points.
    func treasureTargets() -> [(x: Int, z: Int)] {
        guard let id = items.id(named: TreasureMaps.item) else { return [] }
        return inventory.slots.compactMap { st in st?.item == id ? TreasureMaps.unpack(st!.damage) : nil }
    }

    /// Reading a treasure map: the first time, it fixes on the nearest buried treasure nobody has dug up yet.
    func readTreasureMap() {
        guard var stack = inventory.selectedStack, items[stack.item]?.name == TreasureMaps.item else { return }
        if stack.damage == 0 {
            guard dimension == .overworld, let generator = world.generator as? TerrainGenerator else {
                onToast?("The map's markings make no sense here.")
                return
            }
            let p = player.position
            let found = generator.structures(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: 3000).first { t in
                guard t.kind == .buriedTreasure, let chest = generator.chestPositions(t).first else { return false }
                return !containers.looted.contains(BlockPos(chest.x, chest.y, chest.z))
            }
            guard let found else {
                onToast?("The map is too faded to read.")
                return
            }
            stack.damage = TreasureMaps.pack(x: found.x, z: found.z)
            inventory.slots[inventory.selected] = stack
            inventory.markChanged()
            advancements.record("treasure_map")
        }
        if let target = TreasureMaps.unpack(stack.damage) {
            let dx = Double(target.x) - player.position.x, dz = Double(target.z) - player.position.z
            let distance = Int((dx * dx + dz * dz).squareRoot())
            if distance < 4 {
                onToast?("X marks the spot! Dig down right here.")
            } else {
                let dirs = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
                let angle = atan2(dx, -dz)   // 0 = north (-z), clockwise
                let i = (Int((angle / (.pi / 4)).rounded()) % 8 + 8) % 8
                onToast?("The X is about \(distance) blocks \(dirs[i]). Look for it on the beach.")
            }
        }
        onOpenMap?()
    }
}

extension MobManager {
    /// Crabs scuttle about the decks of shipwrecks.
    func spawnWreckCrabs(_ s: GameSession) {
        guard s.dimension == .overworld, s.meta.difficulty != .peaceful, let generator = s.world.generator as? TerrainGenerator else { return }
        let p = s.player.position
        for w in generator.structures(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: 32) where w.kind == .shipwreck {
            let center = DVec3(Double(w.x) + 0.5, Double(w.y) + 1, Double(w.z) + 0.5)
            guard s.world.isLoaded(w.x, w.z),
                  mobs.filter({ $0.species.kind == .crab && simd_distance($0.position, center) < 14 }).count < 3 else { continue }
            spawn(.crab, at: center + DVec3(Double.random(in: -2...2), 0, Double.random(in: -1...1)))
        }
    }
}
