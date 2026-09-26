import Foundation
import DinoCraftCore

/// A villager's request: bring items, defeat creatures or mine blocks, for emeralds and experience.
struct Quest: Codable, Equatable {
    enum Kind: String, Codable { case gather, slay, mine }

    var id: String
    /// The profession of the villager who asked.
    var giver: String
    var kind: Kind
    /// Item name (gather), creature kind (slay) or block name (mine).
    var target: String
    var count: Int
    /// Creatures defeated or blocks mined so far (gather counts your inventory instead).
    var progress = 0
    var emeralds: Int
    var xp: Int
}

enum Quests {
    static let book = "quest_book"
    static let maxActive = 3

    private struct Template {
        let kind: Quest.Kind
        let target: String
        let counts: ClosedRange<Int>
        let emeralds: ClosedRange<Int>
    }

    /// What each profession asks for, by `VillagerProfession.all` index.
    private static let pools: [[Template]] = [
        [Template(kind: .gather, target: "berries", counts: 12...20, emeralds: 2...3),       // Farmer
         Template(kind: .gather, target: "wheat", counts: 10...20, emeralds: 2...4),
         Template(kind: .gather, target: "carrot", counts: 8...14, emeralds: 2...3),
         Template(kind: .slay, target: "raptor", counts: 2...4, emeralds: 3...5)],
        [Template(kind: .mine, target: "coal_ore", counts: 10...18, emeralds: 2...4),       // Toolsmith
         Template(kind: .mine, target: "iron_ore", counts: 6...10, emeralds: 3...5),
         Template(kind: .gather, target: "iron_ingot", counts: 4...8, emeralds: 3...5),
         Template(kind: .slay, target: "crawler", counts: 2...4, emeralds: 3...5)],
        [Template(kind: .gather, target: "cobblestone", counts: 32...64, emeralds: 2...3),  // Mason
         Template(kind: .gather, target: "glass", counts: 8...16, emeralds: 2...4),
         Template(kind: .gather, target: "bricks", counts: 8...16, emeralds: 3...4),
         Template(kind: .mine, target: "stone", counts: 40...64, emeralds: 2...3)],
        [Template(kind: .gather, target: "dino_bone", counts: 6...12, emeralds: 2...4),     // Fossil Hunter
         Template(kind: .gather, target: "dino_hide", counts: 4...8, emeralds: 2...4),
         Template(kind: .mine, target: "amber_ore", counts: 3...6, emeralds: 4...6),
         Template(kind: .slay, target: "spitter", counts: 2...4, emeralds: 3...5),
         Template(kind: .slay, target: "rex", counts: 1...1, emeralds: 8...12)],
    ]

    /// The quest a villager offers today (the same all day, a new one each morning).
    static func offer(from mob: Mob, day: Int) -> Quest? {
        guard mob.species.kind == .villager else { return nil }
        let profession = ((mob.variant % pools.count) + pools.count) % pools.count
        let pool = pools[profession]
        var rng = SplitMix(UInt64(truncatingIfNeeded: mob.id &* 7919 &+ day &* 104_729))
        let t = pool[Int(rng.next() % UInt64(pool.count))]
        func pick(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(rng.next() % UInt64(r.count)) }
        let count = pick(t.counts)
        let emeralds = pick(t.emeralds)
        return Quest(id: "\(mob.id)-\(day)", giver: VillagerProfession.all[profession % VillagerProfession.all.count].name,
                     kind: t.kind, target: t.target, count: count, emeralds: emeralds, xp: 8 + emeralds * 4)
    }
}

extension GameSession {
    var day: Int { Int(worldTime / SkyModel.dayLength) }

    /// Readable name of a quest's target.
    func questTargetName(_ q: Quest) -> String {
        switch q.kind {
        case .gather: return items.info(named: q.target)?.displayName ?? q.target
        case .mine: return blocks[blocks.id(named: q.target) ?? 0]?.displayName ?? q.target
        case .slay: return MobKind(rawValue: q.target).map { MobSpecies.of($0).displayName } ?? q.target
        }
    }

    /// e.g. "Bring 12 Berries", "Defeat 3 Raptors", "Mine 10 Coal Ore".
    func questTitle(_ q: Quest) -> String {
        let name = questTargetName(q)
        switch q.kind {
        case .gather: return "Bring \(q.count) \(name)"
        case .slay: return "Defeat \(q.count) \(name)\(q.count == 1 || name.hasSuffix("s") ? "" : "s")"
        case .mine: return "Mine \(q.count) \(name)"
        }
    }

    /// How far along a quest is (gather quests count what you're carrying).
    func questProgress(_ q: Quest) -> Int {
        switch q.kind {
        case .gather: return min(q.count, items.id(named: q.target).map { inventory.count(of: $0) } ?? 0)
        case .slay, .mine: return min(q.count, q.progress)
        }
    }

    func questComplete(_ q: Quest) -> Bool { questProgress(q) >= q.count }

    /// The quest this villager offers, unless you've already taken it.
    func questOffer(from mob: Mob) -> Quest? {
        guard let q = Quests.offer(from: mob, day: day), !quests.contains(where: { $0.id == q.id }) else { return nil }
        return q
    }

    func acceptQuest(_ q: Quest) {
        guard quests.count < Quests.maxActive else {
            onToast?("You can only take \(Quests.maxActive) quests at a time. Finish or abandon one first.")
            return
        }
        quests.append(q)
        onSound?("ui_open", 0.5, 1.2)
        if let book = items.id(named: Quests.book), inventory.count(of: book) == 0 {
            let left = inventory.add(ItemStack(item: book, count: 1))
            if left > 0 { dropStack(ItemStack(item: book, count: 1), thrown: false) }
            onToast?("Quest accepted! Your Quest Book keeps track (right-click it).")
        } else {
            onToast?("Quest accepted: \(questTitle(q))")
        }
        advancements.record("quest_accept")
    }

    /// Hands in a finished quest (to any villager): gather quests take the items. Returns true if it paid out.
    @discardableResult
    func turnInQuest(_ q: Quest) -> Bool {
        guard let index = quests.firstIndex(where: { $0.id == q.id }), questComplete(quests[index]) else { return false }
        if q.kind == .gather, let id = items.id(named: q.target) {
            guard inventory.remove(item: id, count: q.count) == q.count else { return false }
        }
        quests.remove(at: index)
        if let emerald = items.id(named: "emerald") {
            let left = inventory.add(ItemStack(item: emerald, count: q.emeralds))
            if left > 0 { dropStack(ItemStack(item: emerald, count: left), thrown: false) }
        }
        addXP(q.xp)
        onSound?("discover", 0.7, 1.1)
        onToast?("Quest complete! +\(q.emeralds) emeralds, +\(q.xp) XP")
        advancements.record("quest", q.kind.rawValue)
        return true
    }

    func abandonQuest(_ q: Quest) {
        quests.removeAll { $0.id == q.id }
        onSound?("ui_back", 0.5, 1)
    }

    /// Counts defeated creatures and mined blocks toward your quests.
    func noteQuestEvent(_ type: String, _ target: String, amount: Int) {
        let kind: Quest.Kind
        switch type {
        case "kill": kind = .slay
        case "break": kind = .mine
        default: return
        }
        for i in quests.indices where quests[i].kind == kind && quests[i].target == target && quests[i].progress < quests[i].count {
            quests[i].progress += amount
            if quests[i].progress >= quests[i].count {
                onToast?("Quest ready to hand in: \(questTitle(quests[i]))")
                onSound?("discover", 0.5, 1.4)
            }
        }
    }
}
