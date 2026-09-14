import Foundation
import simd
import DinoCraftCore

/// Looks up orientation/state variants of doors, wall torches, furnaces, chests
/// and stairs, which are stored as separate block IDs (one byte per voxel).
struct DoorState {
    let upper: Bool
    let open: Bool
    let facing: BlockFace
}

final class BlockVariants {
    static let horizontal: [BlockFace] = [.north, .east, .south, .west]

    private let registry: BlockRegistry
    private var doors: [String: BlockID] = [:]
    private var doorStates: [BlockID: DoorState] = [:]
    private var wallTorches: [BlockFace: BlockID] = [:]
    private var wallTorchFacing: [BlockID: BlockFace] = [:]
    private var furnaces: [String: BlockID] = [:]
    private var furnaceStates: [BlockID: (facing: BlockFace, lit: Bool)] = [:]
    private var chests: [BlockFace: BlockID] = [:]
    private var chestIDs: Set<BlockID> = []
    /// Placeable orientation families ("furnace", "chest", "cobblestone_stairs", …) by facing.
    private var families: [String: [BlockFace: BlockID]] = [:]
    private var familyOf: [BlockID: String] = [:]

    init(blocks: BlockRegistry) {
        registry = blocks
        for f in BlockVariants.horizontal {
            let fn = BlockRegistry.name(of: f)
            for upper in [false, true] {
                for open in [false, true] {
                    if let id = blocks.id(named: "door_\(upper ? "upper" : "lower")_\(open ? "open" : "closed")_\(fn)") {
                        doors["\(upper)\(open)\(fn)"] = id
                        doorStates[id] = DoorState(upper: upper, open: open, facing: f)
                    }
                }
            }
            if let id = blocks.id(named: "wall_torch_\(fn)") {
                wallTorches[f] = id
                wallTorchFacing[id] = f
            }
            for lit in [false, true] {
                if let id = blocks.id(named: "\(lit ? "lit_" : "")furnace_\(fn)") {
                    furnaces["\(lit)\(fn)"] = id
                    furnaceStates[id] = (f, lit)
                }
            }
            if let id = blocks.id(named: "chest_\(fn)") {
                chests[f] = id
                chestIDs.insert(id)
            }
        }
        if let barrel = blocks.id(named: "barrel") { chestIDs.insert(barrel) }

        for b in blocks.all {
            guard let facing = b.facing, b.shape != .wallTorch, !b.name.hasPrefix("door_"), !b.name.hasPrefix("lit_") else { continue }
            let suffix = "_" + BlockRegistry.name(of: facing)
            guard b.name.hasSuffix(suffix) else { continue }
            let base = String(b.name.dropLast(suffix.count))
            families[base, default: [:]][facing] = b.id
            familyOf[b.id] = base
        }
    }

    func door(upper: Bool, open: Bool, facing: BlockFace) -> BlockID? { doors["\(upper)\(open)\(BlockRegistry.name(of: facing))"] }
    func doorState(_ id: BlockID) -> DoorState? { doorStates[id] }
    func wallTorch(facing: BlockFace) -> BlockID? { wallTorches[facing] }
    func wallTorchWall(_ id: BlockID) -> BlockFace? { wallTorchFacing[id] }
    func furnace(facing: BlockFace, lit: Bool) -> BlockID? { furnaces["\(lit)\(BlockRegistry.name(of: facing))"] }
    func furnaceState(_ id: BlockID) -> (facing: BlockFace, lit: Bool)? { furnaceStates[id] }
    func chest(facing: BlockFace) -> BlockID? { chests[facing] }

    /// The orientation variants a placed block can turn into, if it has any.
    func family(of id: BlockID) -> [BlockFace: BlockID]? {
        familyOf[id].flatMap { families[$0] }
    }

    func containerKind(_ id: BlockID) -> ContainerKind? {
        if chestIDs.contains(id) { return .chest }
        if furnaceStates[id] != nil { return .furnace }
        return nil
    }

    /// The horizontal direction a look vector points in.
    static func horizontalFacing(_ dir: DVec3) -> BlockFace {
        abs(dir.x) > abs(dir.z) ? (dir.x > 0 ? .east : .west) : (dir.z > 0 ? .south : .north)
    }
}
