import Foundation
import DinoCraftCore

/// One of the three things an enchanting table offers for the item in your hand.
struct EnchantOffer: Equatable {
    let enchantment: Enchantment
    let level: Int
    /// Levels spent (and amber used).
    let cost: Int
    /// Level you need to have to pick it.
    let required: Int
}

/// The enchanting table: hold a tool, weapon or armour piece, spend levels and amber, get magic.
enum Enchanting {
    static let table = "enchanting_table"
    static let catalyst = "amber"
    /// What each of the three offers needs: (levels spent, level required).
    static let tiers: [(cost: Int, required: Int)] = [(1, 3), (2, 10), (3, 20)]

    /// Which enchantments suit an item.
    static func applicable(_ info: ItemInfo) -> [Enchantment] {
        if info.armor != nil { return [.protection, .unbreaking] }
        switch info.name {
        case "bow", "crossbow": return [.power]
        default: break
        }
        guard let tool = info.tool else { return [] }
        switch tool.kind {
        case .pickaxe: return [.efficiency, .fortune, .unbreaking]
        case .axe: return [.efficiency, .sharpness, .unbreaking]
        case .shovel, .hoe: return [.efficiency, .unbreaking]
        case .sword: return [.sharpness, .unbreaking]
        case .spear: return [.power, .sharpness, .unbreaking]
        case .shield: return [.unbreaking]
        case .none: return []
        }
    }

    /// The table's three offers for `stack`, fixed until you enchant something (`seed` changes then).
    static func offers(for stack: ItemStack, info: ItemInfo, seed: UInt64) -> [EnchantOffer] {
        let options = applicable(info)
        guard !options.isEmpty, stack.count == 1 else { return [] }
        var rng = SplitMix(seed ^ (UInt64(stack.item) &* 0x9E37_79B9_7F4A_7C15))
        var out: [EnchantOffer] = []
        for (i, tier) in tiers.enumerated() {
            // Prefer something that can still go up; a stronger tier aims higher.
            var upgradable = options.filter { Enchantments.level($0, in: stack.enchant) < Enchantment.maxLevel }
            guard !upgradable.isEmpty else { break }
            let fresh = upgradable.filter { e in !out.contains { $0.enchantment == e } }
            if !fresh.isEmpty { upgradable = fresh }
            let pick = upgradable[Int(rng.next() % UInt64(upgradable.count))]
            let current = Enchantments.level(pick, in: stack.enchant)
            let level = min(Enchantment.maxLevel, max(current + 1, i + 1))
            out.append(EnchantOffer(enchantment: pick, level: level, cost: tier.cost, required: tier.required))
        }
        return out
    }
}

/// A tiny deterministic random generator (so the offers don't change every frame).
struct SplitMix {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension GameSession {
    /// Level of an enchantment on the item in your hand.
    func heldEnchantLevel(_ e: Enchantment) -> Double {
        Double(inventory.selectedStack.map { Enchantments.level(e, in: $0.enchant) } ?? 0)
    }

    /// What the enchanting table offers for the item in your hand (empty if it can't be enchanted).
    var enchantOffers: [EnchantOffer] {
        guard let stack = inventory.selectedStack, let info = items[stack.item] else { return [] }
        return Enchanting.offers(for: stack, info: info, seed: enchantSeed)
    }

    var amberCount: Int { items.id(named: Enchanting.catalyst).map { inventory.count(of: $0) } ?? 0 }

    /// Why an offer can't be taken right now, or nil if it can.
    func enchantProblem(_ offer: EnchantOffer) -> String? {
        if player.gameMode == .creative { return nil }
        if xpLevel < offer.required { return "Needs level \(offer.required)" }
        if amberCount < offer.cost { return "Needs \(offer.cost) amber" }
        return nil
    }

    /// Enchants the item in your hand with `offer`, paying levels and amber. Returns false if you can't.
    @discardableResult
    func enchantHeld(_ offer: EnchantOffer) -> Bool {
        guard var stack = inventory.selectedStack, enchantOffers.contains(offer) else { return false }
        if let problem = enchantProblem(offer) {
            onToast?(problem)
            return false
        }
        if player.gameMode != .creative {
            spendLevels(offer.cost)
            if let amber = items.id(named: Enchanting.catalyst) { inventory.remove(item: amber, count: offer.cost) }
        }
        stack.enchant = Enchantments.setting(offer.enchantment, to: offer.level, in: stack.enchant)
        inventory.slots[inventory.selected] = stack
        inventory.markChanged()
        enchantSeed = UInt64.random(in: 1...UInt64.max)
        onSound?("discover", 0.7, 1.5)
        let name = items[stack.item]?.displayName ?? "item"
        onToast?("\(name): \(offer.enchantment.displayName) \(Enchantments.roman(offer.level))")
        advancements.record("enchant", offer.enchantment.displayName.lowercased())
        Log.info("Enchanted \(name) with \(offer.enchantment.displayName) \(offer.level)", category: "Game")
        return true
    }
}
