import Foundation
import DinoCraftCore

/// The recipe book's rules, shared by the Windows screens: which recipes fit a grid, which you have
/// the ingredients for, and moving one set of ingredients from the inventory into the grid.
enum RecipeBook {
    static func ingredients(_ r: Recipe) -> [Ingredient] {
        switch r.kind {
        case .shaped(_, _, let cells): return cells.compactMap { $0 }
        case .shapeless(let list): return list
        }
    }

    /// Each ingredient (shown by a representative item) and how many are needed.
    static func summary(_ r: Recipe) -> [(ItemID, Int)] {
        var order: [ItemID] = [], counts: [ItemID: Int] = [:]
        for ing in ingredients(r) {
            let id = ing.displayItem
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        return order.map { ($0, counts[$0]!) }
    }

    /// Undamaged items available for crafting, from the inventory and the grid.
    static func pool(_ stacks: [ItemStack?]) -> [ItemID: Int] {
        var p: [ItemID: Int] = [:]
        for st in stacks { if let st, st.damage == 0 { p[st.item, default: 0] += st.count } }
        return p
    }

    static func canCraft(_ r: Recipe, pool: [ItemID: Int]) -> Bool {
        var p = pool
        let list = ingredients(r)
        let ordered = list.filter { if case .item = $0 { return true } else { return false } }
            + list.filter { if case .tag = $0 { return true } else { return false } }
        for ing in ordered {
            guard let id = p.first(where: { $0.value > 0 && ing.matches($0.key) })?.key else { return false }
            p[id]! -= 1
        }
        return true
    }

    /// Recipes that fit the grid, craftable ones first, then by name; optionally only craftable ones or a search.
    static func entries(_ recipes: RecipeRegistry, items: ItemRegistry, gridSize: Int, pool: [ItemID: Int],
                        craftableOnly: Bool, search: String = "") -> [(recipe: Recipe, craftable: Bool)] {
        let q = search.lowercased().trimmingCharacters(in: .whitespaces)
        var list = recipes.recipes.filter { $0.requiredGridSize <= gridSize }.compactMap { r -> (recipe: Recipe, craftable: Bool)? in
            guard let info = items[r.result.item] else { return nil }
            if !q.isEmpty && !info.displayName.lowercased().contains(q) { return nil }
            return (r, canCraft(r, pool: pool))
        }
        if craftableOnly { list = list.filter { $0.craftable } }
        list.sort { a, b in
            if a.craftable != b.craftable { return a.craftable }
            return (items[a.recipe.result.item]?.displayName ?? "") < (items[b.recipe.result.item]?.displayName ?? "")
        }
        return list
    }

    /// Moves one set of the recipe's ingredients into the grid (clearing a different recipe out first;
    /// clicking again adds another set). Returns a message when it can't.
    static func autofill(_ recipe: Recipe, grid: inout [ItemStack?], gridSize: Int, inventory inv: Inventory,
                         recipes: RecipeRegistry) -> String? {
        if recipes.match(grid: grid, size: gridSize)?.id != recipe.id {
            for i in grid.indices {
                guard let st = grid[i] else { continue }
                let left = inv.add(st)
                if left > 0 {
                    var rest = st
                    rest.count = left
                    grid[i] = rest
                    return "Inventory full"
                }
                grid[i] = nil
            }
        }
        var cells: [(Int, Ingredient)] = []
        switch recipe.kind {
        case .shaped(let w, let h, let ings):
            for row in 0..<h { for col in 0..<w { if let ing = ings[row * w + col] { cells.append((row * gridSize + col, ing)) } } }
        case .shapeless(let list):
            for (i, ing) in list.enumerated() { cells.append((i, ing)) }
        }
        var taken: [(Int, ItemID)] = []
        for (cell, ing) in cells {
            let existing = grid[cell]
            let index = inv.slots.indices.first { i in
                guard let st = inv.slots[i], st.damage == 0 else { return false }
                if let existing { return st.item == existing.item && existing.count < inv.maxStack(existing.item) }
                return ing.matches(st.item)
            }
            guard let index, var st = inv.slots[index] else {
                // Put back what was moved so far.
                for (cell, item) in taken {
                    if var g = grid[cell] {
                        g.count -= 1
                        grid[cell] = g.count > 0 ? g : nil
                    }
                    inv.add(ItemStack(item: item, count: 1))
                }
                return "Not enough ingredients"
            }
            let item = st.item
            st.count -= 1
            inv.slots[index] = st.count > 0 ? st : nil
            if var g = grid[cell] { g.count += 1; grid[cell] = g } else { grid[cell] = ItemStack(item: item, count: 1) }
            taken.append((cell, item))
        }
        inv.markChanged()
        return nil
    }
}
