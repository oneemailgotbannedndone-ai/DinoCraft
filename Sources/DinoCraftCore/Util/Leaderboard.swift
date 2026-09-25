import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Your stats

/// Lifetime stats for this player across every world (and friends' worlds), saved in `stats.json`
/// and shared on the global leaderboard. Used from the game's main thread.
public final class PlayerStats: @unchecked Sendable {
    public struct Values: Codable, Equatable, Sendable {
        public var playSeconds: Double = 0
        public var deaths = 0
        public var kills = 0
        public var bossesBeaten = 0
        public var blocksMined = 0
        public var blocksPlaced = 0
        public var itemsCrafted = 0
        public var metresWalked: Double = 0
        public var foodEaten = 0
        public init() {}
    }

    public static let shared = PlayerStats(url: GamePaths.root.appendingPathComponent("stats.json"))

    public private(set) var values = Values()
    private let url: URL
    private var unsaved = 0.0
    private var sinceSubmit = 0.0
    /// Called every few minutes of play (and when asked) to share the stats; the game sets it up.
    public var onSubmit: ((Values) -> Void)?

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Values.self, from: data) { values = saved }
    }

    /// Counts a gameplay event (the same ones advancements use: "break", "place", "kill", "die", …).
    public func record(_ type: String, _ target: String = "", amount: Int = 1) {
        switch type {
        case "break": values.blocksMined += amount
        case "place": values.blocksPlaced += amount
        case "kill":
            values.kills += amount
            if target == "grumblesaurus" { values.bossesBeaten += 1 }
        case "die": values.deaths += amount
        case "craft": values.itemsCrafted += amount
        case "eat": values.foodEaten += amount
        default: return
        }
        unsaved += 5
    }

    /// Adds play time and distance walked; saves now and then and shares every five minutes.
    public func tick(dt: Double, walked: Double) {
        values.playSeconds += dt
        if walked > 0 && walked < 20 { values.metresWalked += walked }
        unsaved += dt
        sinceSubmit += dt
        if unsaved > 30 { save() }
        if sinceSubmit > 300 {
            sinceSubmit = 0
            onSubmit?(values)
        }
    }

    public func save() {
        unsaved = 0
        guard let data = try? JSONEncoder().encode(values) else { return }
        try? AtomicFile.write(data, to: url)
    }

    /// Shares the stats right away (e.g. when leaving a world or opening the launcher).
    public func submitNow() {
        save()
        sinceSubmit = 0
        onSubmit?(values)
    }
}

// MARK: - The global leaderboard

/// Everyone's stats, on a free dreamlo board. The entry name is the player's one-of-a-kind name
/// and tag; its score is their play time in seconds (dreamlo keeps the higher score, and play time only
/// grows); the other stats travel in the entry's text, like `d3k10b0m200p50c12w1500e4`.
public final class Leaderboard: @unchecked Sendable {
    public struct Entry: Equatable, Sendable {
        public var name: String
        public var tag: String
        public var stats: PlayerStats.Values
        public var display: String { tag.isEmpty ? name : "\(name)#\(tag)" }
    }

    public enum State: Sendable {
        case idle, loading
        case loaded([Entry])
        case failed(String)
    }

    /// What the leaderboard can be sorted by.
    public enum Category: String, CaseIterable, Sendable {
        case playtime, kills, mined, placed, walked, crafted, deaths, bosses

        public var title: String {
            switch self {
            case .playtime: return "Play Time"
            case .kills: return "Kills"
            case .mined: return "Blocks Mined"
            case .placed: return "Blocks Placed"
            case .walked: return "Distance"
            case .crafted: return "Crafted"
            case .deaths: return "Deaths"
            case .bosses: return "Bosses"
            }
        }

        /// A shorter name for tabs.
        public var tab: String {
            switch self {
            case .mined: return "Mined"
            case .placed: return "Placed"
            default: return title
            }
        }

        public func value(_ s: PlayerStats.Values) -> Double {
            switch self {
            case .playtime: return s.playSeconds
            case .kills: return Double(s.kills)
            case .mined: return Double(s.blocksMined)
            case .placed: return Double(s.blocksPlaced)
            case .walked: return s.metresWalked
            case .crafted: return Double(s.itemsCrafted)
            case .deaths: return Double(s.deaths)
            case .bosses: return Double(s.bossesBeaten)
            }
        }

        public func format(_ s: PlayerStats.Values) -> String {
            switch self {
            case .playtime:
                let minutes = Int(s.playSeconds / 60)
                return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
            case .walked:
                return s.metresWalked >= 1000 ? String(format: "%.1f km", s.metresWalked / 1000) : "\(Int(s.metresWalked)) m"
            default:
                return "\(Int(value(s)))"
            }
        }
    }

    public let publicCode: String
    private let privateCode: String
    private let lock = NSLock()
    private var _state = State.idle

    public init(publicCode: String, privateCode: String) {
        self.publicCode = publicCode
        self.privateCode = privateCode
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        return _state
    }

    private func set(_ s: State) { lock.lock(); _state = s; lock.unlock() }

    /// dreamlo only answers on plain http for free boards (DINOCRAFT_LEADERBOARD_URL points elsewhere for tests).
    private var base: String { ProcessInfo.processInfo.environment["DINOCRAFT_LEADERBOARD_URL"] ?? "http://dreamlo.com/lb" }

    public func load() {
        if case .loading = state { return }
        set(.loading)
        guard let url = URL(string: "\(base)/\(publicCode)/json") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("DinoCraft", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if error != nil || data == nil {
                self.set(.failed("Couldn't reach the leaderboard. Check your internet connection."))
            } else if status != 200 {
                self.set(.failed("The leaderboard couldn't be loaded (HTTP \(status))."))
            } else {
                self.set(.loaded(Leaderboard.parse(data!)))
            }
        }.resume()
    }

    /// Shares one player's stats. Runs in the background; failures are ignored (it tries again later).
    public func submit(name: String, playerID: String, stats: PlayerStats.Values) {
        let key = Leaderboard.entryName(name: name, playerID: playerID)
        let text = Leaderboard.encode(stats)
        guard stats.playSeconds >= 60,
              let url = URL(string: "\(base)/\(privateCode)/add/\(key)/\(Int(stats.playSeconds))/\(stats.kills)/\(text)") else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("DinoCraft", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error { Log.warning("Couldn't share stats: \(error.localizedDescription)", category: "Stats") }
        }.resume()
    }

    /// "Rex_K7Q2": the name (letters, digits and _) and the player's tag.
    public static func entryName(name: String, playerID: String) -> String {
        let clean = PlayerIdentity.cleanName(name)
        return "\(clean.isEmpty ? "Explorer" : clean)_\(PlayerIdentity.tag(for: playerID))"
    }

    static let fields: [(Character, WritableKeyPath<PlayerStats.Values, Int>)] = [
        ("d", \.deaths), ("k", \.kills), ("b", \.bossesBeaten), ("m", \.blocksMined), ("p", \.blocksPlaced), ("c", \.itemsCrafted), ("e", \.foodEaten),
    ]

    public static func encode(_ s: PlayerStats.Values) -> String {
        fields.map { "\($0.0)\(s[keyPath: $0.1])" }.joined() + "w\(Int(s.metresWalked))"
    }

    public static func decode(_ text: String, playSeconds: Double) -> PlayerStats.Values {
        var s = PlayerStats.Values()
        s.playSeconds = playSeconds
        var letter: Character?
        var digits = ""
        func flush() {
            guard let letter, let n = Int(digits) else { return }
            let value = max(0, min(n, 100_000_000))
            if letter == "w" { s.metresWalked = Double(value) }
            else if let field = fields.first(where: { $0.0 == letter }) { s[keyPath: field.1] = value }
        }
        for ch in text {
            if ch.isLetter { flush(); letter = ch; digits = "" } else if ch.isNumber { digits.append(ch) }
        }
        flush()
        return s
    }

    /// Reads dreamlo's JSON (a single entry comes as an object, several as a list, none as null).
    public static func parse(_ data: Data) -> [Entry] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let board = (root["dreamlo"] as? [String: Any])?["leaderboard"] as? [String: Any] else { return [] }
        let raw: [[String: Any]]
        if let list = board["entry"] as? [[String: Any]] { raw = list } else if let one = board["entry"] as? [String: Any] { raw = [one] } else { raw = [] }
        return raw.compactMap { e in
            guard let key = e["name"].map({ "\($0)" }) else { return nil }
            let score = Double("\(e["score"] ?? 0)") ?? 0
            guard score >= 0, score < 100_000_000 else { return nil }
            var name = key, tag = ""
            if let cut = key.lastIndex(of: "_"), key.distance(from: cut, to: key.endIndex) == 5 {
                name = String(key[..<cut])
                tag = String(key[key.index(after: cut)...])
            }
            return Entry(name: name, tag: tag, stats: decode("\(e["text"] ?? "")", playSeconds: score))
        }
    }

    /// Entries sorted best-first for a category (ties by play time).
    public static func ranked(_ entries: [Entry], by category: Category) -> [Entry] {
        entries.sorted {
            let a = category.value($0.stats), b = category.value($1.stats)
            return a != b ? a > b : $0.stats.playSeconds > $1.stats.playSeconds
        }
    }
}
