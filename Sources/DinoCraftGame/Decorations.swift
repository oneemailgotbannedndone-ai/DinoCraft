import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Paintings, item frames and armour stands.
enum Decorations {
    static let painting = "painting"
    static let paintings = ["rex", "sunset", "fern", "volcano", "ptero", "village"]
    static let armorStand = "armor_stand"
    /// Armour materials an armour stand can show, in `Mob.variant` digit order (0 is bare).
    static let materials = ["", "hide", "iron", "diamond"]
    static let pieces = ["helmet", "chestplate", "leggings", "boots"]

    /// The armour material in each slot (head, chest, legs, feet) of a stand's `variant`.
    static func armor(_ variant: Int) -> [Int] { (0..<4).map { (max(0, variant) >> ($0 * 2)) & 3 } }

    static func variant(_ armor: [Int]) -> Int { armor.enumerated().reduce(0) { $0 | ($1.element & 3) << ($1.offset * 2) } }

    /// (slot, material) for an armour item name like "iron_chestplate".
    static func slot(of item: String) -> (Int, Int)? {
        for (m, material) in materials.enumerated() where m > 0 {
            for (i, piece) in pieces.enumerated() where item == "\(material)_\(piece)" { return (i, m) }
        }
        return nil
    }
}

/// Items shown in item frames, by the frame's position.
final class FrameManager {
    private(set) var items: [BlockPos: ItemStack] = [:]

    func item(at pos: BlockPos) -> ItemStack? { items[pos] }
    func set(_ stack: ItemStack?, at pos: BlockPos) { items[pos] = stack }
    func clear() { items.removeAll() }

    private struct Saved: Codable { var x: Int32, y: Int32, z: Int32; var stack: SavedStack }

    func save(to url: URL, registry: ItemRegistry) {
        let list = items.compactMap { pos, st -> Saved? in
            guard let name = registry[st.item]?.name else { return nil }
            return Saved(x: pos.x, y: pos.y, z: pos.z, stack: SavedStack(slot: 0, item: name, count: st.count, damage: st.damage > 0 ? st.damage : nil, enchant: st.enchant))
        }
        do { try AtomicFile.write(JSONEncoder().encode(list), to: url) } catch { Log.error("Failed to save item frames: \(error)", category: "Save") }
    }

    func load(from url: URL, registry: ItemRegistry) {
        items.removeAll()
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([Saved].self, from: data) else { return }
        for s in list {
            guard let id = registry.id(named: s.stack.item) else { continue }
            items[BlockPos(s.x, s.y, s.z)] = ItemStack(item: id, count: 1, damage: s.stack.damage ?? 0, enchant: UInt16(clamping: s.stack.enchant ?? 0))
        }
    }
}

extension GameSession {
    /// Framed items to draw: where each sits (just off the wall) and which way it turns.
    var framedItems: [(position: DVec3, yaw: Float, stack: ItemStack)] {
        frames.items.compactMap { pos, stack in
            guard let facing = frameFacing(world.block(pos)) else { return nil }
            let n = facing.normal
            let center = DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.5, Double(pos.z) + 0.5)
                - DVec3(Double(n.x), Double(n.y), Double(n.z)) * 0.43
            let yaw: Float
            switch facing {
            case .south: yaw = 0
            case .north: yaw = .pi
            case .east: yaw = .pi / 2
            default: yaw = -.pi / 2
            }
            return (center, yaw, stack)
        }
    }

    /// The way an item frame block faces (its front), or nil if it isn't one.
    func frameFacing(_ id: BlockID) -> BlockFace? {
        guard let name = blocks[id]?.name, name.hasPrefix("item_frame_") else { return nil }
        return blocks[id]?.facing
    }

    /// Right-click on an item frame: put what you're holding in it, or take its item back.
    func useItemFrame(_ pos: BlockPos) -> Bool {
        if let shown = frames.item(at: pos) {
            frames.set(nil, at: pos)
            let left = inventory.add(shown)
            if left > 0 { dropStack(shown.with(count: left), thrown: false) }
            onSound?("pickup", 0.5, 1.1)
            swing()
            return true
        }
        guard let held = inventory.selectedStack else { return true }
        frames.set(held.with(count: 1), at: pos)
        if player.gameMode == .survival { inventory.consumeSelected() }
        onSound?("place_wood", 0.5, 1.4)
        swing()
        advancements.record("decorate", "item_frame")
        return true
    }

    /// When a frame goes, its item drops out.
    func spillFrame(at pos: BlockPos) {
        guard let shown = frames.item(at: pos) else { return }
        frames.set(nil, at: pos)
        entities.spawnItem(shown, at: DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.5, Double(pos.z) + 0.5),
                           velocity: DVec3(0, 2, 0), pickupDelay: 0.3)
    }

    /// Hangs a random painting on the wall you're looking at.
    func placePainting() -> Bool {
        guard let hit = target, hit.face != .up, hit.face != .down, blocks.isSolid[Int(hit.id)] else {
            onToast?("Paintings go on walls.")
            return false
        }
        let pos = hit.adjacent
        guard blocks[world.block(pos)]?.replaceable ?? true else { return false }
        let motif = Decorations.paintings.randomElement() ?? "rex"
        guard let id = blocks.id(named: "painting_\(motif)_\(BlockRegistry.name(of: hit.face))"), naturalPlaceChecked(pos, id) else { return false }
        if player.gameMode == .survival { inventory.consumeSelected() }
        onSound?("place_wood", 0.7, 1)
        swing()
        advancements.record("decorate", "painting")
        return true
    }

    /// Stands an armour stand on the ground you're looking at, facing you.
    func placeArmorStand() -> Bool {
        guard !isRemote else {
            onToast?("Armour stands work in your own worlds (or ones you host) for now.")
            return false
        }
        guard let hit = target, hit.face == .up else { return false }
        let pos = hit.adjacent
        guard blocks[world.block(pos)]?.replaceable ?? true, blocks[world.block(pos.offset(.up))]?.replaceable ?? true else { return false }
        let stand = mobs.spawn(.armorStand, at: DVec3(Double(pos.x) + 0.5, Double(pos.y), Double(pos.z) + 0.5))
        let to = player.position - stand.position
        stand.yaw = atan2(-to.x, -to.z) + .pi
        if player.gameMode == .survival { inventory.consumeSelected() }
        onSound?("place_wood", 0.7, 0.9)
        swing()
        advancements.record("decorate", "armor_stand")
        return true
    }

    /// Right-click an armour stand: hang the armour you're holding on it, or take everything back off.
    func useArmorStand(_ stand: Mob) -> Bool {
        var armor = Decorations.armor(stand.variant)
        if let held = inventory.selectedStack, let name = items[held.item]?.name, let (slot, material) = Decorations.slot(of: name) {
            let old = armor[slot]
            armor[slot] = material
            stand.variant = Decorations.variant(armor)
            if player.gameMode == .survival { inventory.consumeSelected() }
            if old > 0 { giveArmorPiece(slot: slot, material: old) }
            onSound?("break_metal", 0.4, 1.4)
            swing()
            return true
        }
        guard armor.contains(where: { $0 > 0 }) else { return false }
        for (slot, material) in armor.enumerated() where material > 0 { giveArmorPiece(slot: slot, material: material) }
        stand.variant = 0
        onSound?("pickup", 0.5, 1)
        swing()
        return true
    }

    private func giveArmorPiece(slot: Int, material: Int) {
        guard let id = items.id(named: "\(Decorations.materials[material])_\(Decorations.pieces[slot])") else { return }
        let left = inventory.add(ItemStack(item: id, count: 1))
        if left > 0 { dropStack(ItemStack(item: id, count: left), thrown: false) }
    }
}

extension MobManager {
    /// An armour stand knocked down: it drops itself and whatever it was wearing.
    func breakArmorStand(_ m: Mob, session s: GameSession) {
        guard !m.removed else { return }
        m.removed = true
        let center = m.position + DVec3(0, 1, 0)
        var drops = [Decorations.armorStand]
        for (slot, material) in Decorations.armor(m.variant).enumerated() where material > 0 {
            drops.append("\(Decorations.materials[material])_\(Decorations.pieces[slot])")
        }
        for name in drops {
            guard let id = s.items.id(named: name) else { continue }
            s.entities.spawnItem(ItemStack(item: id, count: 1), at: center,
                                 velocity: DVec3(Double.random(in: -1.5...1.5), 3, Double.random(in: -1.5...1.5)), pickupDelay: 0.4)
        }
        s.onSound?("break_wood", 0.7, 1)
    }
}
