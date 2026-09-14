import Foundation
import DinoCraftCore

/// One advancement from `Data/advancements.json`.
struct AdvancementDef: Codable, Identifiable {
    let id: String
    let category: String
    let title: String
    let description: String
    let icon: String
    /// Event type: pickup, craft, smelt, break, place, kill, eat, trade, loot, visit, near, dimension, depth, height, die.
    let type: String
    /// Optional target pattern: alternatives separated by "|", "*" wildcards.
    let target: String?
    let count: Int?
    /// Count distinct matching targets instead of occurrences.
    let distinct: Bool?

    var required: Int { max(1, count ?? 1) }
}

private struct AdvancementFile: Codable { var advancements: [AdvancementDef] }

private struct AdvancementSave: Codable {
    var unlocked: [String: Date]
    var progress: [String: Int]
    var seen: [String: [String]]?
}

/// Tracks a player's advancements for one world: progress, unlocks and persistence.
final class AdvancementTracker {
    static let definitions: [AdvancementDef] = {
        do {
            return try JSONDecoder().decode(AdvancementFile.self, from: ResourceLocator.data("Data/advancements.json")).advancements
        } catch {
            Log.error("Could not load advancements: \(error)", category: "Game")
            return []
        }
    }()

    static let categories: [String] = {
        var seen: [String] = []
        for d in definitions where !seen.contains(d.category) { seen.append(d.category) }
        return seen
    }()

    private(set) var unlocked: [String: Date] = [:]
    private(set) var progress: [String: Int] = [:]
    private var seenTargets: [String: Set<String>] = [:]
    private var byType: [String: [AdvancementDef]] = [:]
    var onUnlock: ((AdvancementDef) -> Void)?

    init() {
        for d in AdvancementTracker.definitions { byType[d.type, default: []].append(d) }
    }

    var unlockedCount: Int { unlocked.count }

    func isUnlocked(_ id: String) -> Bool { unlocked[id] != nil }

    func progress(of def: AdvancementDef) -> Int {
        isUnlocked(def.id) ? def.required : min(def.required, progress[def.id] ?? 0)
    }

    /// Records a gameplay event such as ("pickup", "diamond") or ("kill", "rex").
    func record(_ type: String, _ target: String = "", amount: Int = 1) {
        guard let defs = byType[type] else { return }
        for def in defs where unlocked[def.id] == nil {
            if let pattern = def.target, !AdvancementTracker.matches(target, pattern) { continue }
            if def.distinct == true {
                var set = seenTargets[def.id] ?? []
                guard set.insert(target).inserted else { continue }
                seenTargets[def.id] = set
                progress[def.id] = set.count
            } else {
                progress[def.id, default: 0] += amount
            }
            if (progress[def.id] ?? 0) >= def.required {
                unlocked[def.id] = Date()
                progress[def.id] = nil
                seenTargets[def.id] = nil
                Log.info("Advancement made: \(def.title)", category: "Game")
                onUnlock?(def)
            }
        }
    }

    static func matches(_ value: String, _ pattern: String) -> Bool {
        pattern.split(separator: "|").contains { glob(value, String($0)) }
    }

    private static func glob(_ value: String, _ pattern: String) -> Bool {
        guard pattern.contains("*") else { return value == pattern }
        let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        var rest = Substring(value)
        for (i, part) in parts.enumerated() {
            if part.isEmpty { continue }
            if i == 0 {
                guard rest.hasPrefix(part) else { return false }
                rest = rest.dropFirst(part.count)
            } else if i == parts.count - 1 {
                return rest.hasSuffix(part)
            } else {
                guard let r = rest.range(of: part) else { return false }
                rest = rest[r.upperBound...]
            }
        }
        return true
    }

    // MARK: Persistence

    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let save = try decoder.decode(AdvancementSave.self, from: data)
            unlocked = save.unlocked
            progress = save.progress
            seenTargets = (save.seen ?? [:]).mapValues { Set($0) }
        } catch {
            Log.error("Could not read advancements: \(error)", category: "Save")
        }
    }

    func save(to url: URL) {
        guard !unlocked.isEmpty || !progress.isEmpty else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let save = AdvancementSave(unlocked: unlocked, progress: progress, seen: seenTargets.mapValues { Array($0) })
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(save).write(to: url, options: .atomic)
        } catch {
            Log.error("Could not save advancements: \(error)", category: "Save")
        }
    }
}
