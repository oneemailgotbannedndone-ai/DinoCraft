import Foundation

/// Two chests side by side, facing the same way, join into one big chest with twice the room.
///
/// Along a row of such chests they pair up from one end: 1+2, 3+4, … so a chest is never in two
/// pairs. The game (for the 54-slot screen) and the mesher (to draw one wide chest) both use this.
public enum DoubleChests {
    public static func isChest(_ id: BlockID) -> Bool { Blocks.chest.contains(id) }

    /// The direction (dx, dz) of the chest this one pairs with, or nil for a single chest.
    /// `facing` is the chest's `BlockFace.rawValue`; `block` reads the world around (x, y, z).
    public static func partner(x: Int, y: Int, z: Int, id: BlockID, facing: Int8,
                               block: (Int, Int, Int) -> BlockID) -> (dx: Int, dz: Int)? {
        guard isChest(id), let face = BlockFace(rawValue: Int(facing)) else { return nil }
        // Partners sit beside each other: along x when facing north/south, along z when facing east/west.
        let (ax, az) = (face == .north || face == .south) ? (1, 0) : (0, 1)
        // How many matching chests are in a row behind this one (towards -axis)?
        // (At most 15 back: the mesher can only see one chunk beyond the one it builds.)
        var behind = 0
        while behind < 15 && block(x - ax * (behind + 1), y, z - az * (behind + 1)) == id { behind += 1 }
        if behind % 2 == 1 { return (-ax, -az) }
        return block(x + ax, y, z + az) == id ? (ax, az) : nil
    }
}
