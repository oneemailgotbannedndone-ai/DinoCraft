import Foundation
import DinoCraftCore

struct Trade {
    let cost: String
    let costCount: Int
    let result: String
    let resultCount: Int
}

/// Villager jobs and what they trade. A villager's profession is `Mob.variant`.
struct VillagerProfession {
    let name: String
    let blurb: String
    let trades: [Trade]

    static let all: [VillagerProfession] = [
        VillagerProfession(name: "Farmer", blurb: "Grows cycad berries and cooks for the village.", trades: [
            Trade(cost: "berries", costCount: 10, result: "emerald", resultCount: 1),
            Trade(cost: "raw_dino_meat", costCount: 6, result: "emerald", resultCount: 1),
            Trade(cost: "emerald", costCount: 1, result: "trail_mix", resultCount: 4),
            Trade(cost: "emerald", costCount: 1, result: "cooked_dino_steak", resultCount: 3),
        ]),
        VillagerProfession(name: "Toolsmith", blurb: "Forges iron and diamond tools.", trades: [
            Trade(cost: "coal", costCount: 12, result: "emerald", resultCount: 1),
            Trade(cost: "iron_ingot", costCount: 4, result: "emerald", resultCount: 1),
            Trade(cost: "emerald", costCount: 3, result: "iron_pickaxe", resultCount: 1),
            Trade(cost: "emerald", costCount: 4, result: "iron_sword", resultCount: 1),
            Trade(cost: "emerald", costCount: 12, result: "diamond_pickaxe", resultCount: 1),
        ]),
        VillagerProfession(name: "Mason", blurb: "Builds with stone, brick and glass.", trades: [
            Trade(cost: "cobblestone", costCount: 20, result: "emerald", resultCount: 1),
            Trade(cost: "emerald", costCount: 1, result: "bricks", resultCount: 8),
            Trade(cost: "emerald", costCount: 1, result: "stone_bricks", resultCount: 10),
            Trade(cost: "emerald", costCount: 2, result: "glass", resultCount: 6),
        ]),
        VillagerProfession(name: "Fossil Hunter", blurb: "Collects bones, hides and amber from the wilds.", trades: [
            Trade(cost: "dino_bone", costCount: 8, result: "emerald", resultCount: 1),
            Trade(cost: "dino_hide", costCount: 5, result: "emerald", resultCount: 1),
            Trade(cost: "emerald", costCount: 1, result: "amber", resultCount: 4),
            Trade(cost: "emerald", costCount: 6, result: "diamond", resultCount: 1),
            Trade(cost: "emerald", costCount: 2, result: "ember_lighter", resultCount: 1),
        ]),
    ]

    static func of(_ mob: Mob) -> VillagerProfession {
        all[((mob.variant % all.count) + all.count) % all.count]
    }
}
