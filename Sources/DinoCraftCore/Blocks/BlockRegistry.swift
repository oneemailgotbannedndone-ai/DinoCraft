import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif

public typealias BlockID = UInt16

public enum RenderLayer: String, Codable, Sendable {
    case opaque, cutout, translucent, invisible
}

public enum BlockShape: String, Codable, Sendable {
    case cube, cross, torch, liquid, none
    /// A single axis-aligned cuboid inside the cell (doors, chests, slabs); see `BlockDefinition.box`.
    case box
    /// A torch leaning against the wall on its `facing` side.
    case wallTorch
}

/// A cuboid inside a block cell, in 1/16-block units (0…16).
public struct BlockBox: Sendable, Equatable {
    public let x0: UInt8, y0: UInt8, z0: UInt8, x1: UInt8, y1: UInt8, z1: UInt8
    public init(_ v: [Int]) {
        let c = v.map { UInt8(max(0, min(16, $0))) }
        x0 = min(c[0], c[3]); y0 = min(c[1], c[4]); z0 = min(c[2], c[5])
        x1 = max(c[0], c[3]); y1 = max(c[1], c[4]); z1 = max(c[2], c[5])
    }
    public var minBlocks: SIMD3<Double> { SIMD3(Double(x0), Double(y0), Double(z0)) / 16 }
    public var maxBlocks: SIMD3<Double> { SIMD3(Double(x1), Double(y1), Double(z1)) / 16 }
    public func union(_ o: BlockBox) -> BlockBox {
        BlockBox([Int(Swift.min(x0, o.x0)), Int(Swift.min(y0, o.y0)), Int(Swift.min(z0, o.z0)),
                  Int(Swift.max(x1, o.x1)), Int(Swift.max(y1, o.y1)), Int(Swift.max(z1, o.z1))])
    }
}

public enum ToolKind: String, Codable, Sendable, CaseIterable {
    case none, pickaxe, axe, shovel, sword, hoe, spear, shield
}

public enum SoundGroup: String, Codable, Sendable, CaseIterable {
    case none, stone, grass, dirt, wood, sand, gravel, leaves, glass, water, snow, metal
}

/// Stable numeric IDs for blocks the engine refers to directly (terrain
/// generation, physics). Their properties still come from `blocks.json`; the
/// registry validates at load time that the names and IDs agree.
public enum Blocks {
    public static let air: BlockID = 0
    public static let stone: BlockID = 1
    public static let grass: BlockID = 2
    public static let dirt: BlockID = 3
    public static let cobblestone: BlockID = 4
    public static let planks: BlockID = 5
    public static let sand: BlockID = 6
    public static let gravel: BlockID = 7
    public static let log: BlockID = 8
    public static let leaves: BlockID = 9
    public static let water: BlockID = 10
    public static let coalOre: BlockID = 11
    public static let ironOre: BlockID = 12
    public static let goldOre: BlockID = 13
    public static let diamondOre: BlockID = 14
    public static let bedrock: BlockID = 15
    public static let glass: BlockID = 16
    public static let sandstone: BlockID = 17
    public static let craftingBench: BlockID = 18
    public static let tallGrass: BlockID = 19
    public static let fern: BlockID = 20
    public static let emberbloom: BlockID = 21
    public static let sunpetal: BlockID = 22
    public static let snowyGrass: BlockID = 23
    public static let snow: BlockID = 24
    public static let clay: BlockID = 25
    public static let ice: BlockID = 26
    public static let amberLantern: BlockID = 27
    public static let torch: BlockID = 28
    public static let mossyCobblestone: BlockID = 29
    public static let fossilStone: BlockID = 30
    public static let deadBush: BlockID = 31
    public static let redwoodLog: BlockID = 32
    public static let redwoodNeedles: BlockID = 33
    public static let stoneBricks: BlockID = 34
    public static let amberOre: BlockID = 35
    public static let mud: BlockID = 36
    public static let boneBlock: BlockID = 37
    public static let lava: BlockID = 38
    public static let basalt: BlockID = 39
    public static let ash: BlockID = 40
    public static let magmaRock: BlockID = 41
    public static let obsidian: BlockID = 42
    public static let emberCrystal: BlockID = 43
    public static let skyGrass: BlockID = 44
    public static let skySoil: BlockID = 45
    public static let cloud: BlockID = 46
    public static let amberBlock: BlockID = 47
    public static let skybloom: BlockID = 48
    public static let underworldPortal: BlockID = 49
    public static let skylandsPortal: BlockID = 50
    public static let emeraldOre: BlockID = 83
    public static let bookshelf: BlockID = 89
    public static let planksSlab: BlockID = 91
    public static let mossyStoneBricks: BlockID = 93
    public static let blueBloom: BlockID = 96
    public static let whiteDaisy: BlockID = 97
    public static let pinkPetal: BlockID = 98
    public static let redMushroom: BlockID = 99
    public static let brownMushroom: BlockID = 100
    public static let glowMushroom: BlockID = 101
    public static let cattail: BlockID = 102
    public static let horsetail: BlockID = 103
    public static let stalagmite: BlockID = 104
    public static let cactus: BlockID = 105
    public static let lilyPad: BlockID = 106
    public static let pebbles: BlockID = 107
    public static let mossBlock: BlockID = 108
    public static let dryGrass: BlockID = 109
    public static let marble: BlockID = 116
    public static let slate: BlockID = 118
    public static let redRock: BlockID = 120
    public static let palmLog: BlockID = 218
    public static let palmFronds: BlockID = 220
    public static let packedIce: BlockID = 224
    public static let berryBush: BlockID = 226
    /// Orientation variants, indexed north, east, south, west.
    public static let doorLowerClosed: [BlockID] = [51, 52, 53, 54]
    public static let doorUpperClosed: [BlockID] = [59, 60, 61, 62]
    public static let wallTorch: [BlockID] = [67, 68, 69, 70]
    public static let furnace: [BlockID] = [71, 72, 73, 74]
    public static let chest: [BlockID] = [79, 80, 81, 82]

    public static let pinkLeaves: BlockID = 227
    public static let silverLog: BlockID = 228
    public static let silverLeaves: BlockID = 229
    public static let mushroomCap: BlockID = 230
    public static let mushroomStem: BlockID = 231
    public static let bed: BlockID = 232
    public static let farmland: BlockID = 233
    /// Growth stages 0…3.
    public static let wheat: [BlockID] = Array(234...237)
    public static let carrots: [BlockID] = Array(238...241)
    public static let terracotta: BlockID = 94
    /// Dyed clay, indexed white, black, red, orange, yellow, green, cyan, blue, purple, pink.
    public static let dyedClay: [BlockID] = Array(136...145)

    // Toonland, the black-and-white cartoon dimension
    public static let toonGrass: BlockID = 242
    public static let toonSoil: BlockID = 243
    public static let toonStone: BlockID = 244
    public static let smileFlower: BlockID = 245
    public static let toonLog: BlockID = 246
    public static let toonLeaves: BlockID = 247
    public static let checkerBlock: BlockID = 248
    public static let toonlandPortal: BlockID = 249
    /// The dark rock of the deep layers, below Y 0.
    public static let deepSlate: BlockID = 250
    // The sea floor
    public static let kelp: BlockID = 251
    public static let seagrass: BlockID = 252
    public static let coralBlock: BlockID = 253
    public static let coral: BlockID = 254
    public static let seaLantern: BlockID = 255
    public static let enchantingTable: BlockID = 256
    public static let fossilDeposit: BlockID = 257
    public static let displayCase: BlockID = 258
    /// Display cases with a fossil inside: skull, claw, rib, tooth, fern.
    public static let displayCases: [BlockID] = [259, 260, 261, 262, 263]
    public static let meteoriteOre: BlockID = 264

    /// Water, or a plant growing in it (you can drown there, and breaking the plant leaves water).
    @inlinable public static func holdsWater(_ id: BlockID, _ registry: BlockRegistry) -> Bool {
        id == water || registry.isSubmerged[Int(id)]
    }

    static let wellKnown: [(String, BlockID)] = [
        ("pink_leaves", pinkLeaves), ("silver_log", silverLog), ("silver_leaves", silverLeaves), ("mushroom_cap", mushroomCap), ("mushroom_stem", mushroomStem), ("bed", bed), ("farmland", farmland), ("wheat_stage0", wheat[0]), ("wheat_stage3", wheat[3]), ("carrots_stage0", carrots[0]), ("carrots_stage3", carrots[3]),
        ("toon_grass", toonGrass), ("toon_soil", toonSoil), ("toon_stone", toonStone), ("smile_flower", smileFlower), ("toon_log", toonLog),
        ("toon_leaves", toonLeaves), ("checker_block", checkerBlock), ("toonland_portal", toonlandPortal), ("deep_slate", deepSlate),
        ("kelp", kelp), ("seagrass", seagrass), ("coral_block", coralBlock), ("coral", coral), ("sea_lantern", seaLantern), ("enchanting_table", enchantingTable), ("fossil_deposit", fossilDeposit),
        ("display_case", displayCase), ("display_case_skull", displayCases[0]), ("display_case_fern", displayCases[4]), ("meteorite_ore", meteoriteOre),
        ("terracotta", terracotta), ("dyed_clay_white", dyedClay[0]), ("dyed_clay_pink", dyedClay[9]),
        ("air", air), ("stone", stone), ("grass", grass), ("dirt", dirt), ("cobblestone", cobblestone),
        ("planks", planks), ("sand", sand), ("gravel", gravel), ("log", log), ("leaves", leaves),
        ("water", water), ("coal_ore", coalOre), ("iron_ore", ironOre), ("gold_ore", goldOre),
        ("diamond_ore", diamondOre), ("bedrock", bedrock), ("glass", glass), ("sandstone", sandstone),
        ("crafting_bench", craftingBench), ("tall_grass", tallGrass), ("fern", fern),
        ("emberbloom", emberbloom), ("sunpetal", sunpetal), ("snowy_grass", snowyGrass), ("snow", snow),
        ("clay", clay), ("ice", ice), ("amber_lantern", amberLantern), ("torch", torch),
        ("mossy_cobblestone", mossyCobblestone), ("fossil_stone", fossilStone), ("dead_bush", deadBush),
        ("redwood_log", redwoodLog), ("redwood_needles", redwoodNeedles), ("stone_bricks", stoneBricks),
        ("amber_ore", amberOre), ("mud", mud), ("bone_block", boneBlock),
        ("lava", lava), ("basalt", basalt), ("ash", ash), ("magma_rock", magmaRock), ("obsidian", obsidian),
        ("ember_crystal", emberCrystal), ("sky_grass", skyGrass), ("sky_soil", skySoil), ("cloud", cloud),
        ("amber_block", amberBlock), ("skybloom", skybloom), ("underworld_portal", underworldPortal),
        ("skylands_portal", skylandsPortal), ("emerald_ore", emeraldOre),
        ("bookshelf", bookshelf), ("planks_slab", planksSlab), ("mossy_stone_bricks", mossyStoneBricks),
        ("blue_bloom", blueBloom), ("white_daisy", whiteDaisy), ("pink_petal", pinkPetal), ("red_mushroom", redMushroom),
        ("brown_mushroom", brownMushroom), ("glow_mushroom", glowMushroom), ("cattail", cattail), ("horsetail", horsetail),
        ("stalagmite", stalagmite), ("cactus", cactus), ("lily_pad", lilyPad), ("pebbles", pebbles), ("moss_block", mossBlock),
        ("dry_grass", dryGrass), ("marble", marble), ("slate", slate), ("red_rock", redRock), ("palm_log", palmLog),
        ("palm_fronds", palmFronds), ("packed_ice", packedIce), ("berry_bush", berryBush),
        ("door_lower_closed_north", 51), ("door_lower_closed_west", 54), ("door_upper_closed_north", 59), ("door_upper_closed_west", 62),
        ("wall_torch_north", 67), ("wall_torch_west", 70), ("furnace_north", 71), ("furnace_west", 74), ("chest_north", 79), ("chest_west", 82),
    ]
}

// MARK: - JSON schema

public struct BlockTextureSpec: Codable, Sendable {
    public var all: String?
    public var top: String?
    public var bottom: String?
    public var side: String?
    public var front: String?   // north face (e.g. crafting bench)
}

public struct DropSpec: Codable, Sendable {
    public var item: String
    public var min: Int?
    public var max: Int?
    public var chance: Float?
}

public struct BlockDefinition: Codable, Sendable {
    public var id: Int
    public var name: String
    public var displayName: String
    public var textures: BlockTextureSpec?
    public var hardness: Float?
    public var solid: Bool?
    public var opaque: Bool?
    public var layer: RenderLayer?
    public var shape: BlockShape?
    public var emission: Int?
    public var lightFilter: Int?
    public var tool: ToolKind?
    public var toolLevel: Int?
    public var sound: SoundGroup?
    public var drops: [DropSpec]?
    public var replaceable: Bool?
    public var hasItem: Bool?
    public var waving: Bool?
    public var needsSupport: Bool?
    public var tint: [Float]?
    /// Cuboid for `shape: box`, as [x0, y0, z0, x1, y1, z1] in 1/16 units.
    public var box: [Int]?
    /// "north" | "east" | "south" | "west": front face for oriented blocks, wall side for wall torches.
    public var facing: String?
    /// Name of the item this block provides (defaults to the block name). Lets orientation variants share one item.
    public var itemName: String?
    /// Flat icon for the block's item instead of a 3D block icon.
    public var itemTexture: String?
    /// Several cuboids for `shape: box` (stairs); overrides `box`.
    public var boxes: [[Int]]?
    /// Orientation rule for facing families: "facePlayer" (front toward the player, default) or "look" (toward where the player looks).
    public var placement: String?
    /// Grows under water (kelp, seagrass, coral): the cell counts as water for swimming and drawing.
    public var submerged: Bool?
    /// Extra looks picked by position (coral colours); the first replaces `textures`.
    public var variants: [String]?
}

private struct BlockFile: Codable { var blocks: [BlockDefinition] }

// MARK: - Runtime block data

public struct BlockInfo: Sendable {
    public let id: BlockID
    public let name: String
    public let displayName: String
    /// Texture names per face, indexed by `BlockFace.rawValue`.
    public let faceTextureNames: [String]
    public let hardness: Float          // < 0 means unbreakable
    public let solid: Bool
    public let opaque: Bool
    public let layer: RenderLayer
    public let shape: BlockShape
    public let emission: UInt8
    public let lightFilter: UInt8
    public let tool: ToolKind
    public let toolLevel: Int
    public let sound: SoundGroup
    public let drops: [DropSpec]
    public let replaceable: Bool
    public let hasItem: Bool
    public let waving: Bool
    public let needsSupport: Bool
    public let box: BlockBox?
    public let facing: BlockFace?
    public let itemName: String
    public let itemTexture: String?
    /// Cuboids of a `box` block; `box` is their bounds.
    public let parts: [BlockBox]
    public let placement: String
    /// Grows under water: the cell is also full of water.
    public let submerged: Bool
    /// Textures picked per position, or empty.
    public let variants: [String]
    public var isLiquid: Bool { shape == .liquid }
    public var isBreakable: Bool { hardness >= 0 }
}

/// Immutable registry of all block types. Loaded once from `Data/blocks.json`
/// and shared across threads. Hot per-ID flags are stored in flat tables with one entry per possible id
/// tables so the mesher, lighting and physics can query without dictionary
/// lookups.
public final class BlockRegistry: @unchecked Sendable {
    /// Every possible block id has an entry in the lookup tables, so any id read from a save or the
    /// network can be looked up safely (ids no block uses behave like air).
    public static let capacity = Int(BlockID.max) + 1
    /// Blocks are numbered up to here; item ids for other items start just after.
    public static let maxDefinedID = 4095

    public let blocks: [BlockInfo?]            // indexed by id, `capacity` entries
    public let all: [BlockInfo]                // registered blocks in id order
    private let byName: [String: BlockID]

    // Flat tables (`capacity` entries each)
    public let isOpaque: [Bool]
    public let isSolid: [Bool]
    public let emission: [UInt8]
    public let lightFilter: [UInt8]
    public let layer: [RenderLayer]
    public let shape: [BlockShape]
    public let boxes: [BlockBox?]
    /// Every cuboid of each block (collision and meshing).
    public let shapeBoxes: [[BlockBox]]
    /// Facing per id as `BlockFace.rawValue`, or -1.
    public let facingIndex: [Int8]
    /// Plants growing under water (their cell is also water).
    public let isSubmerged: [Bool]
    /// Water, lava, or a plant under water: you swim in it.
    public let isWet: [Bool]

    /// Texture-array layer per (id * 6 + face). Filled after the texture atlas is built.
    public private(set) var faceLayers: [UInt16] = Array(repeating: 0, count: BlockRegistry.capacity * 6)

    public enum RegistryError: Error, CustomStringConvertible {
        case invalid(String)
        public var description: String {
            switch self { case .invalid(let m): return "Block registry error: \(m)" }
        }
    }

    public init(definitions: [BlockDefinition]) throws {
        var table = [BlockInfo?](repeating: nil, count: BlockRegistry.capacity)
        var names: [String: BlockID] = [:]
        for def in definitions {
            guard (0...BlockRegistry.maxDefinedID).contains(def.id) else { throw RegistryError.invalid("block '\(def.name)' has out-of-range id \(def.id)") }
            guard table[def.id] == nil else { throw RegistryError.invalid("duplicate block id \(def.id) ('\(def.name)')") }
            guard names[def.name] == nil else { throw RegistryError.invalid("duplicate block name '\(def.name)'") }
            let shape = def.shape ?? .cube
            let layer = def.layer ?? (shape == .cube ? .opaque : .cutout)
            let opaque = def.opaque ?? (shape == .cube && layer == .opaque)
            let tex = def.textures ?? BlockTextureSpec(all: def.variants?.first ?? def.name)
            let side = tex.side ?? tex.all ?? def.name
            var facing: BlockFace?
            if let f = def.facing {
                guard let parsed = BlockRegistry.face(named: f) else { throw RegistryError.invalid("block '\(def.name)' has invalid facing '\(f)'") }
                facing = parsed
            }
            var faces = [
                side,                               // east
                side,                               // west
                tex.top ?? tex.all ?? side,         // up
                tex.bottom ?? tex.all ?? side,      // down
                side,                               // south
                tex.front ?? side,                  // north
            ]
            if let facing, shape != .wallTorch, let front = tex.front {
                faces[5] = side
                faces[facing.rawValue] = front
            }
            var parts: [BlockBox] = []
            if shape == .box {
                if let list = def.boxes { parts = list.filter { $0.count == 6 }.map { BlockBox($0) } }
                else if let b = def.box, b.count == 6 { parts = [BlockBox(b)] }
                guard !parts.isEmpty else { throw RegistryError.invalid("block '\(def.name)' has shape box but no 6-value box") }
            }
            let box: BlockBox? = parts.isEmpty ? nil : parts.dropFirst().reduce(parts[0]) { $0.union($1) }
            let info = BlockInfo(
                id: BlockID(def.id), name: def.name, displayName: def.displayName,
                faceTextureNames: faces,
                hardness: def.hardness ?? 1.0,
                solid: def.solid ?? (shape == .cube || shape == .box),
                opaque: opaque,
                layer: layer, shape: shape,
                emission: UInt8(max(0, min(15, def.emission ?? 0))),
                lightFilter: UInt8(max(0, min(15, def.lightFilter ?? (opaque ? 15 : 0)))),
                tool: def.tool ?? .none,
                toolLevel: def.toolLevel ?? 0,
                sound: def.sound ?? .stone,
                drops: def.drops ?? [DropSpec(item: def.name, min: 1, max: 1, chance: 1)],
                replaceable: def.replaceable ?? false,
                hasItem: def.hasItem ?? true,
                waving: def.waving ?? false,
                needsSupport: def.needsSupport ?? false,
                box: box, facing: facing, itemName: def.itemName ?? def.name, itemTexture: def.itemTexture,
                parts: parts, placement: def.placement ?? "facePlayer",
                submerged: def.submerged ?? false, variants: def.variants ?? [])
            table[def.id] = info
            names[def.name] = BlockID(def.id)
        }
        for (name, id) in Blocks.wellKnown {
            guard names[name] == id else {
                throw RegistryError.invalid("engine expects block '\(name)' to have id \(id)")
            }
        }
        blocks = table
        all = table.compactMap { $0 }
        byName = names
        isOpaque = table.map { $0?.opaque ?? false }
        isSolid = table.map { $0?.solid ?? false }
        emission = table.map { $0?.emission ?? 0 }
        lightFilter = table.map { $0?.lightFilter ?? 0 }
        layer = table.map { $0?.layer ?? .invisible }
        shape = table.map { $0?.shape ?? .none }
        boxes = table.map { $0?.box }
        shapeBoxes = table.map { $0?.parts ?? [] }
        facingIndex = table.map { Int8($0?.facing?.rawValue ?? -1) }
        isSubmerged = table.map { $0?.submerged ?? false }
        isWet = table.map { ($0?.shape == .liquid) || ($0?.submerged ?? false) }
    }

    public static func face(named name: String) -> BlockFace? {
        switch name {
        case "north": return .north
        case "south": return .south
        case "east": return .east
        case "west": return .west
        default: return nil
        }
    }

    public static func name(of face: BlockFace) -> String {
        switch face {
        case .north: return "north"
        case .south: return "south"
        case .east: return "east"
        case .west: return "west"
        case .up: return "up"
        case .down: return "down"
        }
    }

    public convenience init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(BlockFile.self, from: jsonData)
        try self.init(definitions: file.blocks)
    }

    public static func loadDefault() throws -> BlockRegistry {
        try BlockRegistry(jsonData: ResourceLocator.data("Data/blocks.json"))
    }

    @inlinable public subscript(id: BlockID) -> BlockInfo? { blocks[Int(id)] }
    public func id(named name: String) -> BlockID? { byName[name] }

    /// Textures the mesher uses besides the blocks' own faces: the halves of a double chest, whose
    /// border stops at the seam so the two chests read as one.
    public static let extraTextureNames = ["chest_front_half", "chest_side_half", "chest_top_half"]

    /// Texture-array layers of `extraTextureNames`, filled with the other layers.
    public private(set) var extraLayers: [String: UInt16] = [:]

    /// Texture-array layers of each block's `variants` (empty for most blocks), indexed by id.
    public private(set) var variantLayers: [[UInt16]] = Array(repeating: [], count: BlockRegistry.capacity)

    /// All distinct texture names referenced by blocks (and the mesher's extras).
    public var textureNames: [String] {
        var seen = Set<String>(), out: [String] = []
        for b in all where b.shape != .none {
            for t in b.faceTextureNames where seen.insert(t).inserted { out.append(t) }
        }
        for b in all { for t in b.variants where seen.insert(t).inserted { out.append(t) } }
        for t in BlockRegistry.extraTextureNames where seen.insert(t).inserted { out.append(t) }
        return out
    }

    /// Resolves face textures into texture-array layers once the atlas exists.
    public func bindTextureLayers(_ lookup: (String) -> UInt16) {
        var layers = [UInt16](repeating: 0, count: BlockRegistry.capacity * 6)
        for b in all {
            for f in 0..<6 { layers[Int(b.id) * 6 + f] = lookup(b.faceTextureNames[f]) }
        }
        faceLayers = layers
        extraLayers = Dictionary(uniqueKeysWithValues: BlockRegistry.extraTextureNames.map { ($0, lookup($0)) })
        var variants = [[UInt16]](repeating: [], count: BlockRegistry.capacity)
        for b in all where !b.variants.isEmpty { variants[Int(b.id)] = b.variants.map(lookup) }
        variantLayers = variants
    }
}
