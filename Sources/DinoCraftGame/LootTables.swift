import Foundation
import DinoCraftCore

/// What generated chests contain. Rolled once, the first time a structure's
/// chest is opened (or broken).
enum LootTables {
    struct Entry {
        let item: String
        let min: Int
        let max: Int
        let chance: Double
    }

    static let tables: [String: [Entry]] = [
        "dungeon": [
            Entry(item: "dino_bone", min: 2, max: 6, chance: 0.8),
            Entry(item: "coal", min: 3, max: 10, chance: 0.7),
            Entry(item: "iron_ingot", min: 1, max: 5, chance: 0.6),
            Entry(item: "gold_ingot", min: 1, max: 4, chance: 0.4),
            Entry(item: "emerald", min: 1, max: 4, chance: 0.35),
            Entry(item: "amber", min: 2, max: 5, chance: 0.4),
            Entry(item: "diamond", min: 1, max: 2, chance: 0.18),
            Entry(item: "raptor_claw", min: 1, max: 2, chance: 0.3),
            Entry(item: "flint", min: 1, max: 3, chance: 0.3),
            Entry(item: "trail_mix", min: 1, max: 2, chance: 0.4),
            Entry(item: "iron_pickaxe", min: 1, max: 1, chance: 0.12),
            Entry(item: "diamond_sword", min: 1, max: 1, chance: 0.05),
            Entry(item: "ember_lighter", min: 1, max: 1, chance: 0.1),
        ],
        "ruin": [
            Entry(item: "emerald", min: 2, max: 6, chance: 0.6),
            Entry(item: "gold_ingot", min: 2, max: 5, chance: 0.5),
            Entry(item: "amber", min: 2, max: 6, chance: 0.5),
            Entry(item: "berries", min: 3, max: 8, chance: 0.5),
            Entry(item: "torch", min: 4, max: 10, chance: 0.5),
            Entry(item: "dino_hide", min: 2, max: 4, chance: 0.4),
            Entry(item: "bone_club", min: 1, max: 1, chance: 0.25),
            Entry(item: "iron_sword", min: 1, max: 1, chance: 0.2),
            Entry(item: "diamond", min: 1, max: 1, chance: 0.1),
        ],
        "desertRuin": [
            Entry(item: "gold_ingot", min: 3, max: 7, chance: 0.6),
            Entry(item: "emerald", min: 3, max: 8, chance: 0.6),
            Entry(item: "dino_bone", min: 4, max: 8, chance: 0.6),
            Entry(item: "amber_block", min: 1, max: 2, chance: 0.3),
            Entry(item: "ember_shard", min: 1, max: 3, chance: 0.3),
            Entry(item: "diamond", min: 1, max: 3, chance: 0.25),
            Entry(item: "cooked_dino_steak", min: 2, max: 5, chance: 0.4),
        ],
        "digSite": [
            Entry(item: "iron_pickaxe", min: 1, max: 1, chance: 0.35),
            Entry(item: "stone_shovel", min: 1, max: 1, chance: 0.5),
            Entry(item: "torch", min: 4, max: 10, chance: 0.7),
            Entry(item: "dino_bone", min: 3, max: 8, chance: 0.7),
            Entry(item: "paper", min: 2, max: 6, chance: 0.5),
            Entry(item: "map", min: 1, max: 1, chance: 0.25),
            Entry(item: "fossil_tooth", min: 1, max: 1, chance: 0.3),
            Entry(item: "display_case", min: 1, max: 2, chance: 0.3),
            Entry(item: "trail_mix", min: 1, max: 3, chance: 0.5),
        ],
        "oceanTemple": [
            Entry(item: "gold_ingot", min: 4, max: 10, chance: 0.8),
            Entry(item: "diamond", min: 2, max: 5, chance: 0.6),
            Entry(item: "emerald", min: 4, max: 10, chance: 0.7),
            Entry(item: "sea_lantern", min: 2, max: 6, chance: 0.5),
            Entry(item: "starmetal_sword", min: 1, max: 1, chance: 0.15),
            Entry(item: "fossil_skull", min: 1, max: 1, chance: 0.3),
            Entry(item: "map", min: 1, max: 1, chance: 0.3),
        ],
        "buriedTreasure": [
            Entry(item: "gold_ingot", min: 6, max: 14, chance: 1),
            Entry(item: "diamond", min: 2, max: 6, chance: 0.8),
            Entry(item: "emerald", min: 5, max: 12, chance: 0.8),
            Entry(item: "amber_block", min: 1, max: 3, chance: 0.5),
            Entry(item: "starmetal_pickaxe", min: 1, max: 1, chance: 0.12),
            Entry(item: "fossil_skull", min: 1, max: 1, chance: 0.2),
            Entry(item: "meteorite_shard", min: 1, max: 4, chance: 0.3),
        ],
        "shipwreck": [
            Entry(item: "treasure_map", min: 1, max: 1, chance: 0.6),
            Entry(item: "gold_ingot", min: 1, max: 5, chance: 0.5),
            Entry(item: "emerald", min: 1, max: 4, chance: 0.5),
            Entry(item: "iron_ingot", min: 2, max: 6, chance: 0.5),
            Entry(item: "paper", min: 2, max: 6, chance: 0.4),
            Entry(item: "raw_fish", min: 2, max: 6, chance: 0.4),
            Entry(item: "string", min: 2, max: 5, chance: 0.4),
            Entry(item: "iron_sword", min: 1, max: 1, chance: 0.15),
            Entry(item: "crossbow", min: 1, max: 1, chance: 0.1),
        ],
        "village": [
            Entry(item: "berries", min: 4, max: 10, chance: 0.6),
            Entry(item: "trail_mix", min: 1, max: 3, chance: 0.4),
            Entry(item: "planks", min: 4, max: 12, chance: 0.5),
            Entry(item: "stick", min: 2, max: 6, chance: 0.4),
            Entry(item: "torch", min: 2, max: 6, chance: 0.5),
            Entry(item: "iron_ingot", min: 1, max: 3, chance: 0.4),
            Entry(item: "emerald", min: 1, max: 2, chance: 0.3),
        ],
    ]

    static func fill(_ container: Container, table: String, items: ItemRegistry) {
        guard let entries = tables[table] else { return }
        var free = Array(0..<container.slots.count).shuffled()
        for entry in entries where Double.random(in: 0..<1) < entry.chance {
            guard let id = items.id(named: entry.item), let slot = free.popLast() else { continue }
            container.slots[slot] = ItemStack(item: id, count: Int.random(in: entry.min...entry.max))
        }
        if container.slots.allSatisfy({ $0 == nil }), let first = entries.first, let id = items.id(named: first.item), let slot = free.popLast() {
            container.slots[slot] = ItemStack(item: id, count: first.max)
        }
    }
}
