import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// A stack of items lying in the world.
final class ItemEntity {
    var stack: ItemStack
    var position: DVec3
    var velocity: DVec3
    var age: Double = 0
    var pickupDelay: Double
    let spinOffset = Double.random(in: 0..<10)
    var onGround = false
    var removed = false
    let id = ItemEntity.makeID()
    var remoteID: Int?
    var netTarget: DVec3?

    private static var counter = 0
    private static func makeID() -> Int { counter += 1; return counter }

    static let halfWidth = 0.125

    init(stack: ItemStack, position: DVec3, velocity: DVec3, pickupDelay: Double) {
        self.stack = stack
        self.position = position
        self.velocity = velocity
        self.pickupDelay = pickupDelay
    }
}

private struct SavedItemEntity: Codable {
    var item: String
    var count: Int
    var damage: Int?
    var x: Double, y: Double, z: Double
    var age: Double
}

/// Simulates dropped items: gravity, voxel collision, buoyancy, magnet pickup,
/// merging of nearby identical stacks, despawning, and persistence.
final class EntityManager {
    private(set) var items: [ItemEntity] = []
    private var scratch: [DBox] = []
    private var mergeTimer = 0.0

    func clear() { items.removeAll() }

    // MARK: Multiplayer

    func snapshot(items registry: ItemRegistry) -> ItemSnapshotMessage {
        ItemSnapshotMessage(items: items.filter { !$0.removed }.compactMap { e in
            registry[e.stack.item].map { ItemState(id: e.id, item: $0.name, count: e.stack.count, x: e.position.x, y: e.position.y, z: e.position.z) }
        })
    }

    func mirror(_ message: ItemSnapshotMessage, items registry: ItemRegistry) {
        var existing: [Int: ItemEntity] = [:]
        for e in items { if let r = e.remoteID { existing[r] = e } }
        var next: [ItemEntity] = []
        for st in message.items {
            guard let item = registry.id(named: st.item) else { continue }
            let e: ItemEntity
            if let found = existing[st.id], found.stack.item == item {
                e = found
            } else {
                e = ItemEntity(stack: ItemStack(item: item, count: st.count), position: DVec3(st.x, st.y, st.z), velocity: .zero, pickupDelay: 999)
                e.remoteID = st.id
            }
            e.stack.count = st.count
            e.netTarget = DVec3(st.x, st.y, st.z)
            next.append(e)
        }
        items = next
    }

    func updateMirrors(dt: Double) {
        for e in items { if let t = e.netTarget { e.position += (t - e.position) * min(1, dt * 10) } }
    }

    /// Removes and returns stacks lying within `radius` of a point (multiplayer pickups).
    func collect(near point: DVec3, radius: Double) -> [ItemStack] {
        var out: [ItemStack] = []
        for e in items where !e.removed && e.pickupDelay <= 0 && simd_distance(e.position, point) < radius {
            out.append(e.stack)
            e.removed = true
        }
        if !out.isEmpty { items.removeAll { $0.removed } }
        return out
    }

    static let maxItems = 400
    static let lifetime = 300.0
    static let pickupRadius = 1.1
    static let magnetRadius = 1.7

    func spawnItem(_ stack: ItemStack, at position: DVec3, velocity: DVec3, pickupDelay: Double) {
        guard stack.count > 0 else { return }
        items.append(ItemEntity(stack: stack, position: position, velocity: velocity, pickupDelay: pickupDelay))
        if items.count > EntityManager.maxItems { items.removeFirst(items.count - EntityManager.maxItems) }
    }

    func update(dt: Double, world: World, player: PlayerController, inventory: Inventory, pickUp: Bool = true, onPickup: (ItemStack) -> Void) {
        let registry = world.registry
        let target = player.position + DVec3(0, 0.8, 0)
        for e in items where !e.removed {
            let bx = Int(floor(e.position.x)), bz = Int(floor(e.position.z))
            guard world.isLoaded(bx, bz) else { continue }
            e.age += dt
            e.pickupDelay -= dt
            if e.age > EntityManager.lifetime { e.removed = true; continue }

            let toPlayer = target - e.position
            let distance = simd_length(toPlayer)
            let canPickUp = pickUp && e.pickupDelay <= 0 && EntityManager.fits(e.stack, in: inventory)
            let attracted = canPickUp && distance < EntityManager.magnetRadius && distance > 0.001
            let by = Int(floor(e.position.y + 0.1))
            if world.block(bx, by, bz) == Blocks.lava { e.removed = true; continue }
            let inLiquid = registry.isWet[Int(world.block(bx, by, bz))]

            if attracted {
                e.velocity += (toPlayer / distance) * (EntityManager.magnetRadius - distance) * 32 * dt
                e.velocity *= exp(-5 * dt)
            } else if inLiquid {
                e.velocity.y += (1.2 - e.velocity.y) * min(1, dt * 3)
                e.velocity.x *= exp(-3 * dt)
                e.velocity.z *= exp(-3 * dt)
            } else {
                e.velocity.y = max(-40, e.velocity.y - 22 * dt)
            }
            move(e, e.velocity * dt, world)
            if e.onGround && !attracted {
                e.velocity.x *= exp(-9 * dt)
                e.velocity.z *= exp(-9 * dt)
            }

            if canPickUp && distance < EntityManager.pickupRadius {
                let before = e.stack.count
                let left = inventory.add(e.stack)
                if left < before {
                    var picked = e.stack
                    picked.count = before - left
                    onPickup(picked)
                    if left == 0 { e.removed = true } else { e.stack.count = left }
                }
            }
        }

        mergeTimer -= dt
        if mergeTimer <= 0 {
            mergeTimer = 0.5
            mergeNearby(maxStack: inventory.maxStack)
        }
        items.removeAll { $0.removed }
    }

    private static func fits(_ stack: ItemStack, in inventory: Inventory) -> Bool {
        let limit = inventory.maxStack(stack.item)
        for slot in inventory.slots {
            guard let s = slot else { return true }
            if s.canStack(with: stack) && s.count < limit { return true }
        }
        return false
    }

    private func mergeNearby(maxStack: (ItemID) -> Int) {
        guard items.count > 1 else { return }
        for i in 0..<(items.count - 1) {
            let a = items[i]
            guard !a.removed, a.stack.count < maxStack(a.stack.item) else { continue }
            for j in (i + 1)..<items.count {
                let b = items[j]
                guard !b.removed, a.stack.canStack(with: b.stack), simd_distance(a.position, b.position) < 0.9 else { continue }
                let moved = min(maxStack(a.stack.item) - a.stack.count, b.stack.count)
                guard moved > 0 else { continue }
                a.stack.count += moved
                b.stack.count -= moved
                a.age = min(a.age, b.age)
                if b.stack.count == 0 { b.removed = true }
            }
        }
    }

    private func move(_ e: ItemEntity, _ d: DVec3, _ world: World) {
        let h = ItemEntity.halfWidth
        var box = DBox(min: e.position - DVec3(h, 0, h), max: e.position + DVec3(h, 2 * h, h))
        if VoxelPhysics.collides(world, box, scratch: &scratch) {
            // Buried (e.g. a block was placed on it): float up out of the terrain.
            e.position.y += 0.15
            e.velocity = .zero
            return
        }
        var dx = d.x, dy = d.y, dz = d.z
        let sweep = box.expanded(d)
        VoxelPhysics.colliders(world, in: DBox(min: sweep.min - 0.01, max: sweep.max + 0.01), into: &scratch)
        for c in scratch { dy = VoxelPhysics.clipY(c, box, dy) }
        box = box.offset(DVec3(0, dy, 0))
        for c in scratch { dx = VoxelPhysics.clipX(c, box, dx) }
        box = box.offset(DVec3(dx, 0, 0))
        for c in scratch { dz = VoxelPhysics.clipZ(c, box, dz) }
        box = box.offset(DVec3(0, 0, dz))
        e.onGround = d.y < 0 && dy != d.y
        if dy != d.y { e.velocity.y = 0 }
        if dx != d.x { e.velocity.x *= -0.25 }
        if dz != d.z { e.velocity.z *= -0.25 }
        e.position = DVec3((box.min.x + box.max.x) / 2, box.min.y, (box.min.z + box.max.z) / 2)
    }

    // MARK: Persistence

    func save(to url: URL, items registry: ItemRegistry) {
        let saved = items.filter { !$0.removed }.compactMap { e -> SavedItemEntity? in
            guard let name = registry[e.stack.item]?.name else { return nil }
            return SavedItemEntity(item: name, count: e.stack.count, damage: e.stack.damage > 0 ? e.stack.damage : nil,
                                   x: e.position.x, y: e.position.y, z: e.position.z, age: e.age)
        }
        do {
            try AtomicFile.write(JSONEncoder().encode(saved), to: url)
        } catch {
            Log.error("Failed to save dropped items: \(error)", category: "Save")
        }
    }

    func load(from url: URL, items registry: ItemRegistry) {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let saved = try JSONDecoder().decode([SavedItemEntity].self, from: data)
            for s in saved {
                guard let id = registry.id(named: s.item) else { continue }
                let e = ItemEntity(stack: ItemStack(item: id, count: s.count, damage: s.damage ?? 0),
                                   position: DVec3(s.x, s.y, s.z), velocity: .zero, pickupDelay: 0)
                e.age = s.age
                items.append(e)
            }
            Log.info("Restored \(items.count) dropped item stacks", category: "Save")
        } catch {
            Log.error("Dropped items file is unreadable (\(error)); ignoring it", category: "Save")
        }
    }
}
