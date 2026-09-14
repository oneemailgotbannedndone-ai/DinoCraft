import Foundation

/// Furnace recipes and fuel burn times, loaded from `Data/smelting.json`.
public final class SmeltingRegistry: @unchecked Sendable {
    public struct Recipe: Sendable {
        public let input: ItemID
        public let result: ItemID
        public let count: Int
        public let seconds: Double
    }

    private struct File: Codable {
        struct Entry: Codable { var input: String; var result: String; var count: Int?; var seconds: Double? }
        var fuel: [String: Double]
        var recipes: [Entry]
    }

    public let recipes: [Recipe]
    private let byInput: [ItemID: Recipe]
    private let fuel: [ItemID: Double]

    public init(items: ItemRegistry, jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        func resolve(_ name: String) throws -> ItemID {
            guard let id = items.id(named: name) else { throw BlockRegistry.RegistryError.invalid("smelting references unknown item '\(name)'") }
            return id
        }
        var list: [Recipe] = []
        var map: [ItemID: Recipe] = [:]
        for e in file.recipes {
            let r = Recipe(input: try resolve(e.input), result: try resolve(e.result), count: max(1, e.count ?? 1), seconds: max(0.5, e.seconds ?? 10))
            guard map[r.input] == nil else { throw BlockRegistry.RegistryError.invalid("duplicate smelting input '\(e.input)'") }
            map[r.input] = r
            list.append(r)
        }
        var burn: [ItemID: Double] = [:]
        for (name, seconds) in file.fuel { burn[try resolve(name)] = seconds }
        recipes = list
        byInput = map
        fuel = burn
    }

    public static func loadDefault(items: ItemRegistry) throws -> SmeltingRegistry {
        try SmeltingRegistry(items: items, jsonData: ResourceLocator.data("Data/smelting.json"))
    }

    public func recipe(for item: ItemID) -> Recipe? { byInput[item] }
    public func burnTime(_ item: ItemID) -> Double? { fuel[item] }
}
