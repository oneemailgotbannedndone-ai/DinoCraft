import Foundation
import simd
import DinoCraftCore

enum ContainerKind: String, Codable {
    case chest, furnace

    var slotCount: Int { self == .chest ? 27 : 3 }
    var displayName: String { self == .chest ? "Chest" : "Furnace" }
}

/// Storage attached to a chest or furnace block.
final class Container {
    static let furnaceInput = 0, furnaceFuel = 1, furnaceOutput = 2

    let kind: ContainerKind
    var slots: [ItemStack?]
    var burnLeft = 0.0
    var burnTotal = 0.0
    var cook = 0.0
    var cookTotal = 10.0

    init(kind: ContainerKind) {
        self.kind = kind
        slots = Array(repeating: nil, count: kind.slotCount)
    }

    var isBurning: Bool { burnLeft > 0 }
}

private struct SavedContainer: Codable {
    var x: Int32, y: Int32, z: Int32
    var kind: String
    var slots: [SavedStack]
    var burnLeft: Double?
    var burnTotal: Double?
    var cook: Double?
}

private struct SavedContainerFile: Codable {
    var containers: [SavedContainer]
    var looted: [[Int32]]?
}

/// All chests and furnaces of the current dimension: persistence, furnace
/// smelting, and multiplayer mirroring.
final class ContainerManager {
    private(set) var containers: [BlockPos: Container] = [:]
    /// Containers changed since the multiplayer host last broadcast them.
    var dirty: Set<BlockPos> = []
    /// Generated structure chests whose loot has already been rolled.
    var looted: Set<BlockPos> = []

    func clear() {
        containers.removeAll()
        dirty.removeAll()
        looted.removeAll()
    }

    func get(_ pos: BlockPos) -> Container? { containers[pos] }

    @discardableResult
    func ensure(_ pos: BlockPos, kind: ContainerKind) -> Container {
        if let c = containers[pos], c.kind == kind { return c }
        let c = Container(kind: kind)
        containers[pos] = c
        return c
    }

    func remove(_ pos: BlockPos) -> Container? {
        dirty.remove(pos)
        return containers.removeValue(forKey: pos)
    }

    // MARK: Furnaces

    /// Advances every furnace. `setLit` swaps the block between lit and unlit variants.
    func tick(dt: Double, smelting: SmeltingRegistry, maxStack: (ItemID) -> Int, setLit: (BlockPos, Bool) -> Void) {
        for (pos, c) in containers where c.kind == .furnace {
            let wasBurning = c.isBurning
            var changed = false
            if c.burnLeft > 0 {
                c.burnLeft = max(0, c.burnLeft - dt)
                changed = true
            }
            let input = c.slots[Container.furnaceInput]
            let recipe = input.flatMap { smelting.recipe(for: $0.item) }
            var canOutput = false
            if let recipe {
                if let out = c.slots[Container.furnaceOutput] {
                    canOutput = out.item == recipe.result && out.damage == 0 && out.count + recipe.count <= maxStack(out.item)
                } else {
                    canOutput = true
                }
            }
            if let recipe, canOutput {
                if c.burnLeft <= 0, let fuel = c.slots[Container.furnaceFuel], let burn = smelting.burnTime(fuel.item) {
                    c.burnLeft = burn
                    c.burnTotal = burn
                    var f = fuel
                    f.count -= 1
                    c.slots[Container.furnaceFuel] = f.count > 0 ? f : nil
                    changed = true
                }
                if c.burnLeft > 0 {
                    c.cookTotal = recipe.seconds
                    c.cook += dt
                    changed = true
                    if c.cook >= recipe.seconds {
                        c.cook = 0
                        if var inStack = c.slots[Container.furnaceInput] {
                            inStack.count -= 1
                            c.slots[Container.furnaceInput] = inStack.count > 0 ? inStack : nil
                        }
                        if var out = c.slots[Container.furnaceOutput] {
                            out.count += recipe.count
                            c.slots[Container.furnaceOutput] = out
                        } else {
                            c.slots[Container.furnaceOutput] = ItemStack(item: recipe.result, count: recipe.count)
                        }
                    }
                }
            } else if c.cook > 0 {
                c.cook = max(0, c.cook - dt * 2)
                changed = true
            }
            if wasBurning != c.isBurning { setLit(pos, c.isBurning) }
            if changed { dirty.insert(pos) }
        }
    }

    // MARK: Persistence

    func load(from url: URL, items: ItemRegistry) {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoder = JSONDecoder()
            let saved: [SavedContainer]
            if let file = try? decoder.decode(SavedContainerFile.self, from: data) {
                saved = file.containers
                for p in file.looted ?? [] where p.count == 3 { looted.insert(BlockPos(p[0], p[1], p[2])) }
            } else {
                saved = try decoder.decode([SavedContainer].self, from: data)
            }
            for s in saved {
                guard let kind = ContainerKind(rawValue: s.kind) else { continue }
                let c = Container(kind: kind)
                for st in s.slots where (0..<kind.slotCount).contains(st.slot) {
                    if let id = items.id(named: st.item) {
                        c.slots[st.slot] = ItemStack(item: id, count: max(1, st.count), damage: st.damage ?? 0)
                    }
                }
                c.burnLeft = s.burnLeft ?? 0
                c.burnTotal = s.burnTotal ?? 0
                c.cook = s.cook ?? 0
                containers[BlockPos(s.x, s.y, s.z)] = c
            }
            Log.info("Loaded \(saved.count) containers", category: "Save")
        } catch {
            Log.error("Could not read containers (\(url.lastPathComponent)): \(error)", category: "Save")
        }
    }

    func save(to url: URL, items: ItemRegistry) {
        let saved: [SavedContainer] = containers.map { pos, c in
            let stacks = c.slots.enumerated().compactMap { i, s -> SavedStack? in
                guard let s, let info = items[s.item] else { return nil }
                return SavedStack(slot: i, item: info.name, count: s.count, damage: s.damage > 0 ? s.damage : nil)
            }
            return SavedContainer(x: pos.x, y: pos.y, z: pos.z, kind: c.kind.rawValue, slots: stacks,
                                  burnLeft: c.burnLeft > 0 ? c.burnLeft : nil, burnTotal: c.burnTotal > 0 ? c.burnTotal : nil,
                                  cook: c.cook > 0 ? c.cook : nil)
        }
        if saved.isEmpty && looted.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder().encode(SavedContainerFile(containers: saved, looted: looted.map { [$0.x, $0.y, $0.z] }))
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Could not save containers: \(error)", category: "Save")
        }
    }

    // MARK: Multiplayer

    func message(for pos: BlockPos, items: ItemRegistry) -> ContainerDataMessage? {
        guard let c = containers[pos] else { return nil }
        return ContainerDataMessage(x: pos.x, y: pos.y, z: pos.z, kind: c.kind.rawValue,
                                    slots: ContainerManager.netSlots(c.slots, items: items),
                                    burnLeft: c.burnLeft, burnTotal: c.burnTotal, cook: c.cook, cookTotal: c.cookTotal)
    }

    func apply(_ m: ContainerDataMessage, items: ItemRegistry) {
        guard let kind = ContainerKind(rawValue: m.kind) else { return }
        let c = ensure(BlockPos(m.x, m.y, m.z), kind: kind)
        c.slots = ContainerManager.stacks(m.slots, count: kind.slotCount, items: items)
        c.burnLeft = m.burnLeft
        c.burnTotal = m.burnTotal
        c.cook = m.cook
        c.cookTotal = m.cookTotal
    }

    static func netSlots(_ slots: [ItemStack?], items: ItemRegistry) -> [NetStack?] {
        slots.map { s in s.flatMap { st in items[st.item].map { NetStack(item: $0.name, count: st.count, damage: st.damage > 0 ? st.damage : nil) } } }
    }

    static func stacks(_ net: [NetStack?], count: Int, items: ItemRegistry) -> [ItemStack?] {
        var out = [ItemStack?](repeating: nil, count: count)
        for (i, s) in net.prefix(count).enumerated() {
            if let s, let id = items.id(named: s.item) { out[i] = ItemStack(item: id, count: max(1, min(64, s.count)), damage: s.damage ?? 0) }
        }
        return out
    }
}
