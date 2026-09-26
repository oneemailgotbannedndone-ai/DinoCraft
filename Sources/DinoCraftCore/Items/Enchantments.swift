import Foundation

/// Magic an enchanting table can put on tools, weapons and armour. Each has levels 1-3.
public enum Enchantment: Int, CaseIterable, Sendable {
    /// Tools dig faster.
    case efficiency
    /// Melee weapons hit harder.
    case sharpness
    /// Wears out more slowly.
    case unbreaking
    /// Bows, crossbows and spears hit harder.
    case power
    /// Armour soaks up more damage.
    case protection
    /// Pickaxes sometimes get extra drops from ores.
    case fortune

    public static let maxLevel = 3

    public var displayName: String {
        switch self {
        case .efficiency: return "Efficiency"
        case .sharpness: return "Sharpness"
        case .unbreaking: return "Unbreaking"
        case .power: return "Power"
        case .protection: return "Protection"
        case .fortune: return "Fortune"
        }
    }
}

/// Enchantments are stored in `ItemStack.enchant`, two bits (a level 0-3) per `Enchantment`.
public enum Enchantments {
    public static func level(_ e: Enchantment, in packed: UInt16) -> Int {
        Int((packed >> UInt16(e.rawValue * 2)) & 0b11)
    }

    public static func setting(_ e: Enchantment, to level: Int, in packed: UInt16) -> UInt16 {
        let shift = UInt16(e.rawValue * 2)
        let clamped = UInt16(max(0, min(Enchantment.maxLevel, level)))
        return (packed & ~(0b11 << shift)) | (clamped << shift)
    }

    /// Everything on an item, strongest first.
    public static func list(_ packed: UInt16) -> [(Enchantment, Int)] {
        Enchantment.allCases.compactMap { e in
            let l = level(e, in: packed)
            return l > 0 ? (e, l) : nil
        }
    }

    public static func roman(_ level: Int) -> String { ["", "I", "II", "III"][max(0, min(3, level))] }

    /// e.g. "Efficiency II, Unbreaking I".
    public static func describe(_ packed: UInt16) -> String {
        list(packed).map { "\($0.0.displayName) \(roman($0.1))" }.joined(separator: ", ")
    }
}
