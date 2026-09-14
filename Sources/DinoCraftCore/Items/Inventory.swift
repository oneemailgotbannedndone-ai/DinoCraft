import Foundation

public struct ItemStack: Equatable, Sendable {
    public var item: ItemID
    public var count: Int
    /// Uses consumed so far (tools only).
    public var damage: Int

    public init(item: ItemID, count: Int = 1, damage: Int = 0) {
        self.item = item; self.count = count; self.damage = damage
    }

    public func canStack(with other: ItemStack) -> Bool {
        item == other.item && damage == 0 && other.damage == 0
    }
}

public enum SlotButton: Sendable { case left, right }

/// Player inventory: 9 hotbar slots (0–8) followed by 27 storage slots (9–35).
public final class Inventory {
    public static let hotbarCount = 9
    public static let size = 36

    public let registry: ItemRegistry
    public var slots: [ItemStack?]
    public var selected = 0 {
        didSet { selected = ((selected % Inventory.hotbarCount) + Inventory.hotbarCount) % Inventory.hotbarCount }
    }
    /// Incremented on any change so UI / Discord / autosave can react cheaply.
    public private(set) var revision = 0

    public init(registry: ItemRegistry) {
        self.registry = registry
        slots = Array(repeating: nil, count: Inventory.size)
    }

    public func markChanged() { revision &+= 1 }

    public var selectedStack: ItemStack? { slots[selected] }

    public func maxStack(_ item: ItemID) -> Int { registry[item]?.maxStack ?? 64 }

    /// Adds items, filling matching stacks first (hotbar before storage), then
    /// empty slots. Returns the number of items that did not fit.
    @discardableResult
    public func add(_ stack: ItemStack) -> Int {
        var remaining = stack.count
        let limit = maxStack(stack.item)
        if limit > 1 && stack.damage == 0 {
            for i in 0..<Inventory.size where remaining > 0 {
                if var s = slots[i], s.canStack(with: stack), s.count < limit {
                    let moved = min(limit - s.count, remaining)
                    s.count += moved
                    remaining -= moved
                    slots[i] = s
                }
            }
        }
        for i in 0..<Inventory.size where remaining > 0 && slots[i] == nil {
            let moved = min(limit, remaining)
            slots[i] = ItemStack(item: stack.item, count: moved, damage: stack.damage)
            remaining -= moved
        }
        if remaining != stack.count { markChanged() }
        return remaining
    }

    public func count(of item: ItemID) -> Int {
        slots.reduce(0) { $0 + (($1?.item == item) ? $1!.count : 0) }
    }

    /// Removes `amount` from the selected hotbar slot.
    public func consumeSelected(_ amount: Int = 1) {
        guard var s = slots[selected] else { return }
        s.count -= amount
        slots[selected] = s.count > 0 ? s : nil
        markChanged()
    }

    /// Applies wear to the selected tool. Returns true if it broke.
    @discardableResult
    public func damageSelectedTool(_ amount: Int = 1) -> Bool {
        guard var s = slots[selected], let tool = registry[s.item]?.tool else { return false }
        s.damage += amount
        if s.damage >= tool.durability {
            slots[selected] = nil
            markChanged()
            return true
        }
        slots[selected] = s
        markChanged()
        return false
    }

    /// Creative "pick block": selects a matching hotbar slot or places the item in the current one.
    public func pick(item: ItemID, creative: Bool) {
        if let idx = (0..<Inventory.hotbarCount).first(where: { slots[$0]?.item == item }) {
            selected = idx
            return
        }
        if creative {
            let target = (0..<Inventory.hotbarCount).first(where: { slots[$0] == nil }) ?? selected
            selected = target
            slots[target] = ItemStack(item: item, count: maxStack(item))
            markChanged()
        } else if let idx = (Inventory.hotbarCount..<Inventory.size).first(where: { slots[$0]?.item == item }) {
            slots.swapAt(idx, selected)
            markChanged()
        }
    }

    public func clear() {
        slots = Array(repeating: nil, count: Inventory.size)
        markChanged()
    }
}

/// Container click semantics shared by the inventory, crafting grids and creative palette.
public enum SlotInteraction {
    /// Standard click on a normal slot with a cursor ("held") stack.
    public static func click(_ slot: inout ItemStack?, cursor: inout ItemStack?, button: SlotButton, maxStack: (ItemID) -> Int) {
        switch (slot, cursor, button) {
        case (nil, nil, _):
            return
        case (let s?, nil, .left):
            cursor = s; slot = nil
        case (var s?, nil, .right):
            let take = (s.count + 1) / 2
            cursor = ItemStack(item: s.item, count: take, damage: s.damage)
            s.count -= take
            slot = s.count > 0 ? s : nil
        case (nil, var c?, .left):
            slot = c; c.count = 0; cursor = nil
        case (nil, var c?, .right):
            slot = ItemStack(item: c.item, count: 1, damage: c.damage)
            c.count -= 1
            cursor = c.count > 0 ? c : nil
        case (var s?, var c?, .left):
            if s.canStack(with: c) {
                let moved = min(maxStack(s.item) - s.count, c.count)
                s.count += moved; c.count -= moved
                slot = s; cursor = c.count > 0 ? c : nil
            } else {
                slot = c; cursor = s
            }
        case (var s?, var c?, .right):
            if s.canStack(with: c) && s.count < maxStack(s.item) {
                s.count += 1; c.count -= 1
                slot = s; cursor = c.count > 0 ? c : nil
            } else if !s.canStack(with: c) {
                slot = c; cursor = s
            }
        }
    }

    /// Moves a stack into `targets` indices of `slots` (merge first, then empty). Returns leftover.
    public static func quickMove(_ stack: ItemStack, into slots: inout [ItemStack?], indices: [Int], maxStack: (ItemID) -> Int) -> ItemStack? {
        var remaining = stack
        let limit = maxStack(stack.item)
        for i in indices where remaining.count > 0 {
            if var s = slots[i], s.canStack(with: remaining), s.count < limit {
                let moved = min(limit - s.count, remaining.count)
                s.count += moved; remaining.count -= moved
                slots[i] = s
            }
        }
        for i in indices where remaining.count > 0 && slots[i] == nil {
            let moved = min(limit, remaining.count)
            slots[i] = ItemStack(item: remaining.item, count: moved, damage: remaining.damage)
            remaining.count -= moved
        }
        return remaining.count > 0 ? remaining : nil
    }
}
