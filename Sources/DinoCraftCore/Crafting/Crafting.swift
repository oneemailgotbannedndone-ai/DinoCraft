import Foundation

// MARK: - JSON schema

private struct RecipeFile: Codable {
    var tags: [String: [String]]
    var recipes: [RecipeDefinition]
}

public struct RecipeDefinition: Codable, Sendable {
    public var id: String
    public var type: String                 // "shaped" | "shapeless"
    public var pattern: [String]?           // shaped: rows, ' ' = empty
    public var key: [String: String]?       // shaped: symbol → item name or #tag
    public var ingredients: [String]?       // shapeless
    public var result: String
    public var count: Int?
}

// MARK: - Runtime

public enum Ingredient: Sendable, Equatable {
    case item(ItemID)
    case tag(String, Set<ItemID>)

    public func matches(_ id: ItemID) -> Bool {
        switch self {
        case .item(let i): return i == id
        case .tag(_, let set): return set.contains(id)
        }
    }

    /// Representative item for recipe-book display.
    public var displayItem: ItemID {
        switch self {
        case .item(let i): return i
        case .tag(_, let set): return set.min() ?? 0
        }
    }
}

public struct Recipe: Sendable {
    public enum Kind: Sendable {
        case shaped(width: Int, height: Int, cells: [Ingredient?])
        case shapeless([Ingredient])
    }
    public let id: String
    public let kind: Kind
    public let result: ItemStack

    /// Smallest square grid able to hold the recipe (2 = inventory, 3 = bench).
    public var requiredGridSize: Int {
        switch kind {
        case .shaped(let w, let h, _): return max(w, h) <= 2 ? 2 : 3
        case .shapeless(let list): return list.count <= 4 ? 2 : 3
        }
    }
}

/// Data-driven recipe registry loaded from `Data/recipes.json`.
public final class RecipeRegistry: @unchecked Sendable {
    public let recipes: [Recipe]
    public let items: ItemRegistry

    public enum RecipeError: Error, CustomStringConvertible {
        case invalid(String)
        public var description: String {
            switch self { case .invalid(let m): return "Recipe error: \(m)" }
        }
    }

    public init(items: ItemRegistry, jsonData: Data) throws {
        self.items = items
        let file = try JSONDecoder().decode(RecipeFile.self, from: jsonData)
        var tags: [String: Set<ItemID>] = [:]
        for (name, members) in file.tags {
            var set = Set<ItemID>()
            for m in members {
                guard let id = items.id(named: m) else { throw RecipeError.invalid("tag #\(name) references unknown item '\(m)'") }
                set.insert(id)
            }
            tags[name] = set
        }
        func ingredient(_ s: String, recipe: String) throws -> Ingredient {
            if s.hasPrefix("#") {
                let name = String(s.dropFirst())
                guard let set = tags[name] else { throw RecipeError.invalid("recipe '\(recipe)' uses unknown tag \(s)") }
                return .tag(name, set)
            }
            guard let id = items.id(named: s) else { throw RecipeError.invalid("recipe '\(recipe)' uses unknown item '\(s)'") }
            return .item(id)
        }

        var list: [Recipe] = []
        for def in file.recipes {
            guard let resultID = items.id(named: def.result) else {
                throw RecipeError.invalid("recipe '\(def.id)' produces unknown item '\(def.result)'")
            }
            let result = ItemStack(item: resultID, count: max(1, def.count ?? 1))
            switch def.type {
            case "shaped":
                guard let pattern = def.pattern, !pattern.isEmpty, let key = def.key else {
                    throw RecipeError.invalid("shaped recipe '\(def.id)' needs a pattern and key")
                }
                let width = pattern.map { $0.count }.max() ?? 0
                guard width <= 3, pattern.count <= 3 else { throw RecipeError.invalid("recipe '\(def.id)' is larger than 3x3") }
                var cells: [Ingredient?] = []
                for row in pattern {
                    let chars = Array(row)
                    for i in 0..<width {
                        let ch = i < chars.count ? chars[i] : " "
                        if ch == " " { cells.append(nil); continue }
                        guard let name = key[String(ch)] else {
                            throw RecipeError.invalid("recipe '\(def.id)' pattern symbol '\(ch)' has no key")
                        }
                        cells.append(try ingredient(name, recipe: def.id))
                    }
                }
                list.append(Recipe(id: def.id, kind: .shaped(width: width, height: pattern.count, cells: cells), result: result))
            case "shapeless":
                guard let ings = def.ingredients, !ings.isEmpty, ings.count <= 9 else {
                    throw RecipeError.invalid("shapeless recipe '\(def.id)' needs 1-9 ingredients")
                }
                list.append(Recipe(id: def.id, kind: .shapeless(try ings.map { try ingredient($0, recipe: def.id) }), result: result))
            default:
                throw RecipeError.invalid("recipe '\(def.id)' has unknown type '\(def.type)'")
            }
        }
        recipes = list
    }

    public static func loadDefault(items: ItemRegistry) throws -> RecipeRegistry {
        try RecipeRegistry(items: items, jsonData: ResourceLocator.data("Data/recipes.json"))
    }

    /// Finds the recipe matching a square crafting grid (size 2 or 3, row-major).
    public func match(grid: [ItemStack?], size: Int) -> Recipe? {
        precondition(grid.count == size * size)
        var minR = size, maxR = -1, minC = size, maxC = -1
        for r in 0..<size {
            for c in 0..<size where grid[r * size + c] != nil {
                minR = min(minR, r); maxR = max(maxR, r); minC = min(minC, c); maxC = max(maxC, c)
            }
        }
        guard maxR >= 0 else { return nil }
        let h = maxR - minR + 1, w = maxC - minC + 1
        let filled = grid.compactMap { $0 }

        for recipe in recipes {
            switch recipe.kind {
            case .shaped(let rw, let rh, let cells):
                guard rw == w, rh == h else { continue }
                for mirrored in [false, true] {
                    var ok = true
                    check: for r in 0..<h {
                        for c in 0..<w {
                            let cc = mirrored ? (w - 1 - c) : c
                            let want = cells[r * w + cc]
                            let have = grid[(minR + r) * size + (minC + c)]
                            switch (want, have) {
                            case (nil, nil): continue
                            case (let i?, let s?) where i.matches(s.item): continue
                            default: ok = false; break check
                            }
                        }
                    }
                    if ok { return recipe }
                }
            case .shapeless(let ings):
                guard ings.count == filled.count else { continue }
                var remaining = filled.map { $0.item }
                var ok = true
                // Match specific items before tags so tags don't steal exact matches.
                let ordered = ings.filter { if case .item = $0 { return true } else { return false } }
                    + ings.filter { if case .tag = $0 { return true } else { return false } }
                for ing in ordered {
                    if let idx = remaining.firstIndex(where: { ing.matches($0) }) {
                        remaining.remove(at: idx)
                    } else {
                        ok = false; break
                    }
                }
                if ok { return recipe }
            }
        }
        return nil
    }

    /// Consumes one of each ingredient from the grid after a craft.
    public static func consumeIngredients(grid: inout [ItemStack?]) {
        for i in grid.indices {
            guard var s = grid[i] else { continue }
            s.count -= 1
            grid[i] = s.count > 0 ? s : nil
        }
    }

    public func recipes(producing item: ItemID) -> [Recipe] {
        recipes.filter { $0.result.item == item }
    }
}
