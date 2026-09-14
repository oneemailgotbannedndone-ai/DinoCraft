import Foundation

public typealias ItemID = UInt16

public struct ToolSpec: Codable, Sendable {
    public var kind: ToolKind
    /// 1 = wood, 2 = stone, 3 = iron, 4 = diamond.
    public var level: Int
    public var speed: Float
    public var durability: Int
    public var damage: Float?
}

public struct FoodSpec: Codable, Sendable {
    public var hunger: Int
    public var saturation: Float
}

public enum ArmorSlot: String, Codable, Sendable, CaseIterable {
    case head, chest, legs, feet
    public var index: Int { ArmorSlot.allCases.firstIndex(of: self)! }
}

public struct ArmorSpec: Codable, Sendable {
    public var slot: ArmorSlot
    /// Armor points; each blocks 4% of creature damage.
    public var protection: Int
    public var durability: Int
}

public struct ItemDefinition: Codable, Sendable {
    public var name: String
    public var displayName: String
    public var texture: String?
    public var maxStack: Int?
    public var tool: ToolSpec?
    public var food: FoodSpec?
    public var armor: ArmorSpec?
}

private struct ItemFile: Codable { var items: [ItemDefinition] }

public struct ItemInfo: Sendable {
    public let id: ItemID
    public let name: String
    public let displayName: String
    /// Flat icon texture name; nil for block items (rendered as a 3D block icon).
    public let texture: String?
    public let maxStack: Int
    public let tool: ToolSpec?
    public let food: FoodSpec?
    public var armor: ArmorSpec? = nil
    /// The block this item places, if any.
    public let block: BlockID?

    /// Uses before a tool or armor piece breaks.
    public var maxDurability: Int? { tool?.durability ?? armor?.durability }
}

/// Registry of every item. Block items share their numeric ID with the block
/// (0–255); other items start at 256. Saves always store item *names*, so
/// IDs may change between versions without corrupting inventories.
public final class ItemRegistry: @unchecked Sendable {
    public static let firstNonBlockID: ItemID = 256

    public let items: [ItemInfo?]
    private let byName: [String: ItemID]
    public let blocks: BlockRegistry

    public init(blocks: BlockRegistry, definitions: [ItemDefinition]) throws {
        self.blocks = blocks
        var table = [ItemInfo?](repeating: nil, count: Int(ItemRegistry.firstNonBlockID) + definitions.count)
        var names: [String: ItemID] = [:]
        for b in blocks.all where b.hasItem {
            guard names[b.itemName] == nil else {
                throw BlockRegistry.RegistryError.invalid("more than one block provides item '\(b.itemName)'")
            }
            table[Int(b.id)] = ItemInfo(id: ItemID(b.id), name: b.itemName, displayName: b.displayName,
                                        texture: b.itemTexture, maxStack: 64, tool: nil, food: nil, block: b.id)
            names[b.itemName] = ItemID(b.id)
        }
        for (i, def) in definitions.enumerated() {
            guard names[def.name] == nil else {
                throw BlockRegistry.RegistryError.invalid("item name '\(def.name)' collides with an existing item")
            }
            let id = ItemRegistry.firstNonBlockID + ItemID(i)
            let stack = def.tool != nil || def.armor != nil ? 1 : max(1, min(64, def.maxStack ?? 64))
            table[Int(id)] = ItemInfo(id: id, name: def.name, displayName: def.displayName,
                                      texture: def.texture ?? def.name, maxStack: stack,
                                      tool: def.tool, food: def.food, armor: def.armor, block: nil)
            names[def.name] = id
        }
        // Every block drop must reference a real item.
        for b in blocks.all {
            for d in b.drops where names[d.item] == nil {
                throw BlockRegistry.RegistryError.invalid("block '\(b.name)' drops unknown item '\(d.item)'")
            }
        }
        items = table
        byName = names
    }

    public convenience init(blocks: BlockRegistry, jsonData: Data) throws {
        let file = try JSONDecoder().decode(ItemFile.self, from: jsonData)
        try self.init(blocks: blocks, definitions: file.items)
    }

    public static func loadDefault(blocks: BlockRegistry) throws -> ItemRegistry {
        try ItemRegistry(blocks: blocks, jsonData: ResourceLocator.data("Data/items.json"))
    }

    public subscript(id: ItemID) -> ItemInfo? {
        Int(id) < items.count ? items[Int(id)] : nil
    }

    public func id(named name: String) -> ItemID? { byName[name] }
    public func info(named name: String) -> ItemInfo? { byName[name].flatMap { self[$0] } }

    public var all: [ItemInfo] { items.compactMap { $0 } }

    /// Flat icon textures referenced by non-block items.
    public var textureNames: [String] { all.compactMap { $0.texture } }
}
