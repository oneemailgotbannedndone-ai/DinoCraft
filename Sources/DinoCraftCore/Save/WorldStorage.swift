import Foundation

public struct WorldMetadata: Codable, Sendable, Identifiable {
    public static let currentFormat = 1

    public var formatVersion: Int
    public var id: String                  // folder name
    public var name: String
    public var seedText: String
    public var seed: String                // UInt64 as decimal string (JSON-safe)
    public var gameMode: GameMode
    public var difficulty: Difficulty
    public var createdAt: Date
    public var lastPlayed: Date
    public var playTimeSeconds: Double
    public var worldTime: Double           // in-game time of day, seconds into the cycle
    public var spawnX: Int?
    public var spawnY: Int?
    public var spawnZ: Int?
    /// One life: the world locks into spectator mode when the player dies.
    public var hardcore: Bool?
    public var hardcoreDead: Bool?
    /// Place a chest of starter supplies next to spawn when the world first loads.
    public var bonusChest: Bool?
    /// World rules changed with /gamerule (missing entries use the defaults).
    public var gameRules: [String: Bool]?
    /// Set with /sethome, as [x, y, z].
    public var home: [Double]?
    /// Current weather ("clear", "rain", "thunder") and seconds until it changes.
    public var weather: String?
    public var weatherTimer: Double?
    /// Whether commands like /give and /time work in this world (missing = allowed).
    public var allowCommands: Bool?

    /// Hardcore worlds never allow commands.
    public var commandsAllowed: Bool { !isHardcore && (allowCommands ?? true) }

    public static let gameRuleDefaults: [String: Bool] = ["keepInventory": false, "doDaylightCycle": true, "doMobSpawning": true, "doWeatherCycle": true]

    public func rule(_ name: String) -> Bool { gameRules?[name] ?? WorldMetadata.gameRuleDefaults[name] ?? true }

    public mutating func setRule(_ name: String, _ value: Bool) {
        var rules = gameRules ?? [:]
        rules[name] = value
        gameRules = rules
    }

    public var isHardcore: Bool { hardcore ?? false }

    public init(formatVersion: Int = WorldMetadata.currentFormat, id: String, name: String, seedText: String, seed: String,
                gameMode: GameMode, difficulty: Difficulty, createdAt: Date, lastPlayed: Date, playTimeSeconds: Double,
                worldTime: Double, spawnX: Int? = nil, spawnY: Int? = nil, spawnZ: Int? = nil, hardcore: Bool? = nil, hardcoreDead: Bool? = nil) {
        self.formatVersion = formatVersion; self.id = id; self.name = name; self.seedText = seedText; self.seed = seed
        self.gameMode = gameMode; self.difficulty = difficulty; self.createdAt = createdAt; self.lastPlayed = lastPlayed
        self.playTimeSeconds = playTimeSeconds; self.worldTime = worldTime; self.spawnX = spawnX; self.spawnY = spawnY
        self.spawnZ = spawnZ; self.hardcore = hardcore; self.hardcoreDead = hardcoreDead
    }

    public var numericSeed: UInt64 { UInt64(seed) ?? Hashing.seed(from: seedText) }
}

public struct SavedStack: Codable, Sendable {
    public var slot: Int
    public var item: String
    public var count: Int
    public var damage: Int?

    public init(slot: Int, item: String, count: Int, damage: Int?) {
        self.slot = slot; self.item = item; self.count = count; self.damage = damage
    }
}

public struct PlayerSave: Codable, Sendable {
    public var x: Double, y: Double, z: Double
    public var yaw: Double, pitch: Double
    public var health: Double
    public var hunger: Double
    public var saturation: Double
    public var air: Double?
    public var flying: Bool
    public var selectedSlot: Int
    public var inventory: [SavedStack]
    /// WorldDimension the player was in (nil = overworld).
    public var dimension: String?
    /// Worn armor; `slot` is 0 head … 3 feet.
    public var armor: [SavedStack]?

    public init(x: Double, y: Double, z: Double, yaw: Double, pitch: Double, health: Double, hunger: Double,
                saturation: Double, air: Double?, flying: Bool, selectedSlot: Int, inventory: [SavedStack], dimension: String? = nil) {
        self.dimension = dimension
        self.x = x; self.y = y; self.z = z; self.yaw = yaw; self.pitch = pitch
        self.health = health; self.hunger = hunger; self.saturation = saturation; self.air = air
        self.flying = flying; self.selectedSlot = selectedSlot; self.inventory = inventory
    }
}

public enum WorldStorageError: Error, CustomStringConvertible {
    case invalidName
    case notFound(String)
    case incompatible(Int)
    public var description: String {
        switch self {
        case .invalidName: return "The world name is empty."
        case .notFound(let id): return "World '\(id)' could not be found."
        case .incompatible(let v): return "This world was saved by a newer version of DinoCraft (format \(v))."
        }
    }
}

/// On-disk layout:
/// ```
/// worlds/<id>/world.json     metadata
/// worlds/<id>/player.json    player state + inventory
/// worlds/<id>/chunks/c.<x>.<z>.dcc   LZFSE-compressed modified chunks
/// ```
public final class WorldStorage: @unchecked Sendable {
    public let root: URL
    /// Serial queue for all disk writes so saves never interleave.
    public let ioQueue = DispatchQueue(label: "com.dinocraft.save", qos: .utility)

    public init(root: URL = GamePaths.worlds) {
        self.root = root
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public func directory(for id: String) -> URL { root.appendingPathComponent(id, isDirectory: true) }
    /// `dimension` is a dimension storage folder (nil for the overworld).
    public func chunksDirectory(for id: String, dimension: String? = nil) -> URL {
        var base = directory(for: id)
        if let dimension { base = base.appendingPathComponent(dimension, isDirectory: true) }
        return base.appendingPathComponent("chunks", isDirectory: true)
    }

    // MARK: Listing

    public func listWorlds() -> [WorldMetadata] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        var worlds: [WorldMetadata] = []
        for dir in dirs {
            let metaURL = dir.appendingPathComponent("world.json")
            guard fm.fileExists(atPath: metaURL.path) else { continue }
            do {
                var meta = try WorldStorage.decoder().decode(WorldMetadata.self, from: Data(contentsOf: metaURL))
                meta.id = dir.lastPathComponent
                worlds.append(meta)
            } catch {
                Log.error("Skipping unreadable world at \(dir.lastPathComponent): \(error)", category: "Save")
            }
        }
        return worlds.sorted { $0.lastPlayed > $1.lastPlayed }
    }

    // MARK: Create / delete

    public func createWorld(name: String, seedText: String, gameMode: GameMode, difficulty: Difficulty, hardcore: Bool = false) throws -> WorldMetadata {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw WorldStorageError.invalidName }
        let seedString = seedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let seed: UInt64
        let storedSeedText: String
        if seedString.isEmpty {
            var rng = SystemRandomNumberGenerator()
            seed = rng.next()
            storedSeedText = String(Int64(bitPattern: seed))
        } else {
            seed = Hashing.seed(from: seedString)
            storedSeedText = seedString
        }
        let id = uniqueFolderName(for: trimmed)
        let now = Date()
        var meta = WorldMetadata(formatVersion: WorldMetadata.currentFormat, id: id, name: trimmed,
                                 seedText: storedSeedText, seed: String(seed), gameMode: hardcore ? .survival : gameMode,
                                 difficulty: hardcore ? .hard : difficulty,
                                 createdAt: now, lastPlayed: now, playTimeSeconds: 0, worldTime: 60)
        if hardcore { meta.hardcore = true }
        try FileManager.default.createDirectory(at: chunksDirectory(for: id), withIntermediateDirectories: true)
        try saveMetadata(meta)
        Log.info("Created world '\(trimmed)' (\(id)) seed=\(storedSeedText) mode=\(gameMode.rawValue) difficulty=\(difficulty.rawValue)", category: "Save")
        return meta
    }

    private func uniqueFolderName(for name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        var base = String(name.unicodeScalars.filter { allowed.contains($0) })
            .replacingOccurrences(of: " ", with: "_")
        if base.isEmpty { base = "World" }
        base = String(base.prefix(40))
        var candidate = base
        var n = 2
        while FileManager.default.fileExists(atPath: directory(for: candidate).path) {
            candidate = "\(base)_\(n)"
            n += 1
        }
        return candidate
    }

    /// Moves the world to the Trash (recoverable) — falls back to removal if the
    /// Trash is unavailable.
    public func deleteWorld(id: String) throws {
        let dir = directory(for: id)
        guard FileManager.default.fileExists(atPath: dir.path) else { throw WorldStorageError.notFound(id) }
        do {
            try FileManager.default.trashItem(at: dir, resultingItemURL: nil)
            Log.info("Moved world \(id) to the Trash", category: "Save")
        } catch {
            Log.warning("Could not move world \(id) to Trash (\(error)); deleting directly", category: "Save")
            try FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: Metadata & player

    public func loadMetadata(id: String) throws -> WorldMetadata {
        let url = directory(for: id).appendingPathComponent("world.json")
        guard FileManager.default.fileExists(atPath: url.path) else { throw WorldStorageError.notFound(id) }
        var meta = try WorldStorage.decoder().decode(WorldMetadata.self, from: Data(contentsOf: url))
        guard meta.formatVersion <= WorldMetadata.currentFormat else { throw WorldStorageError.incompatible(meta.formatVersion) }
        meta.id = id
        return meta
    }

    public func saveMetadata(_ meta: WorldMetadata) throws {
        try AtomicFile.write(WorldStorage.encoder().encode(meta), to: directory(for: meta.id).appendingPathComponent("world.json"))
    }

    public func loadPlayer(id: String) -> PlayerSave? {
        let url = directory(for: id).appendingPathComponent("player.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try WorldStorage.decoder().decode(PlayerSave.self, from: data)
        } catch {
            Log.error("Player data for \(id) is unreadable: \(error). The player will respawn.", category: "Save")
            return nil
        }
    }

    public func savePlayer(_ player: PlayerSave, id: String) throws {
        try AtomicFile.write(WorldStorage.encoder().encode(player), to: directory(for: id).appendingPathComponent("player.json"))
    }

    // MARK: Chunks

    public func chunkURL(worldID: String, pos: ChunkPos, dimension: String? = nil) -> URL {
        chunksDirectory(for: worldID, dimension: dimension).appendingPathComponent("c.\(pos.x).\(pos.z).dcc")
    }

    /// Returns a saved chunk, nil if never saved. Corrupt files are quarantined
    /// and regenerated rather than crashing the game.
    public func loadChunk(worldID: String, pos: ChunkPos, dimension: String? = nil) -> Chunk? {
        let url = chunkURL(worldID: worldID, pos: pos, dimension: dimension)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try Chunk.deserialize(data, expected: pos)
        } catch {
            Log.error("Chunk \(pos) in world \(worldID) is corrupt (\(error)); regenerating it", category: "Save")
            try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt"))
            return nil
        }
    }

    public func writeChunkData(_ data: Data, worldID: String, pos: ChunkPos, dimension: String? = nil) throws {
        try AtomicFile.write(data, to: chunkURL(worldID: worldID, pos: pos, dimension: dimension))
    }

    public func savedChunkCount(worldID: String) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: chunksDirectory(for: worldID).path).filter { $0.hasSuffix(".dcc") }.count) ?? 0
    }

    public func sizeOnDisk(worldID: String) -> Int64 {
        let dir = directory(for: worldID)
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in e {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
