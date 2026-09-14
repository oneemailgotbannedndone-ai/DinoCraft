import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif

public typealias DVec3 = SIMD3<Double>

/// Read access to blocks in world coordinates (implemented by `World`).
public protocol BlockSource: AnyObject {
    /// Returns nil when the chunk is not loaded.
    func blockIfLoaded(_ x: Int, _ y: Int, _ z: Int) -> BlockID?
    var registry: BlockRegistry { get }
}

public struct DBox: Sendable {
    public var min: DVec3
    public var max: DVec3
    public init(min: DVec3, max: DVec3) { self.min = min; self.max = max }

    public func offset(_ d: DVec3) -> DBox { DBox(min: min + d, max: max + d) }
    public func expanded(_ d: DVec3) -> DBox { DBox(min: simd_min(min, min + d), max: simd_max(max, max + d)) }
    public func intersects(_ o: DBox) -> Bool {
        min.x < o.max.x && max.x > o.min.x && min.y < o.max.y && max.y > o.min.y && min.z < o.max.z && max.z > o.min.z
    }
}

public struct RaycastHit: Sendable {
    public var block: BlockPos
    public var face: BlockFace
    public var id: BlockID
    public var distance: Double
    /// The empty cell in front of the hit face (where a block would be placed).
    public var adjacent: BlockPos { block.offset(face) }
}

public enum VoxelPhysics {
    private static let epsilon = 1e-7

    /// Voxel traversal (Amanatides & Woo). Skips air and liquids.
    public static func raycast(_ world: BlockSource, origin: DVec3, direction dir: DVec3, maxDistance: Double) -> RaycastHit? {
        let d = simd_normalize(dir)
        var x = Int(floor(origin.x)), y = Int(floor(origin.y)), z = Int(floor(origin.z))
        let stepX = d.x > 0 ? 1 : -1, stepY = d.y > 0 ? 1 : -1, stepZ = d.z > 0 ? 1 : -1
        func initial(_ o: Double, _ cell: Int, _ dd: Double) -> Double {
            guard abs(dd) > epsilon else { return .infinity }
            return (dd > 0 ? (Double(cell + 1) - o) : (o - Double(cell))) / abs(dd)
        }
        var tMaxX = initial(origin.x, x, d.x), tMaxY = initial(origin.y, y, d.y), tMaxZ = initial(origin.z, z, d.z)
        let tDeltaX = abs(d.x) > epsilon ? 1 / abs(d.x) : .infinity
        let tDeltaY = abs(d.y) > epsilon ? 1 / abs(d.y) : .infinity
        let tDeltaZ = abs(d.z) > epsilon ? 1 / abs(d.z) : .infinity
        var face = BlockFace.up
        var t = 0.0
        let reg = world.registry
        while t <= maxDistance {
            if y >= 0 && y < WorldConst.height, let id = world.blockIfLoaded(x, y, z) {
                let shape = reg.shape[Int(id)]
                if shape != .none && shape != .liquid {
                    return RaycastHit(block: BlockPos(x, y, z), face: face, id: id, distance: t)
                }
            }
            if tMaxX < tMaxY && tMaxX < tMaxZ {
                x += stepX; t = tMaxX; tMaxX += tDeltaX; face = stepX > 0 ? .west : .east
            } else if tMaxY < tMaxZ {
                y += stepY; t = tMaxY; tMaxY += tDeltaY; face = stepY > 0 ? .down : .up
            } else {
                z += stepZ; t = tMaxZ; tMaxZ += tDeltaZ; face = stepZ > 0 ? .north : .south
            }
        }
        return nil
    }

    /// Solid block boxes overlapping `box`. Unloaded chunks count as solid so the
    /// player can never fall out of the world while terrain streams in.
    public static func colliders(_ world: BlockSource, in box: DBox, into result: inout [DBox]) {
        result.removeAll(keepingCapacity: true)
        let x0 = Int(floor(box.min.x)), x1 = Int(floor(box.max.x - epsilon))
        let y0 = Int(floor(box.min.y)), y1 = Int(floor(box.max.y - epsilon))
        let z0 = Int(floor(box.min.z)), z1 = Int(floor(box.max.z - epsilon))
        let solid = world.registry.isSolid
        let boxes = world.registry.shapeBoxes
        for y in y0...max(y0, y1) {
            for z in z0...max(z0, z1) {
                for x in x0...max(x0, x1) {
                    let isSolid: Bool
                    var shape: [BlockBox] = []
                    if y < 0 {
                        isSolid = true
                    } else if y >= WorldConst.height {
                        isSolid = false
                    } else if let id = world.blockIfLoaded(x, y, z) {
                        isSolid = solid[Int(id)]
                        shape = boxes[Int(id)]
                    } else {
                        isSolid = true
                    }
                    if isSolid {
                        let origin = DVec3(Double(x), Double(y), Double(z))
                        if !shape.isEmpty {
                            for part in shape { result.append(DBox(min: origin + part.minBlocks, max: origin + part.maxBlocks)) }
                        } else {
                            result.append(DBox(min: origin, max: origin + DVec3(1, 1, 1)))
                        }
                    }
                }
            }
        }
    }

    public static func collides(_ world: BlockSource, _ box: DBox, scratch: inout [DBox]) -> Bool {
        colliders(world, in: box, into: &scratch)
        return scratch.contains { $0.intersects(box) }
    }

    /// Whether any block of the given predicate overlaps the box.
    public static func anyBlock(_ world: BlockSource, in box: DBox, where predicate: (BlockID) -> Bool) -> Bool {
        let x0 = Int(floor(box.min.x)), x1 = Int(floor(box.max.x - epsilon))
        let y0 = max(0, Int(floor(box.min.y))), y1 = min(WorldConst.height - 1, Int(floor(box.max.y - epsilon)))
        let z0 = Int(floor(box.min.z)), z1 = Int(floor(box.max.z - epsilon))
        guard y0 <= y1 else { return false }
        for y in y0...y1 {
            for z in z0...max(z0, z1) {
                for x in x0...max(x0, x1) {
                    if let id = world.blockIfLoaded(x, y, z), predicate(id) { return true }
                }
            }
        }
        return false
    }

    @inline(__always) public static func clipY(_ c: DBox, _ box: DBox, _ dy: Double) -> Double {
        guard box.max.x > c.min.x && box.min.x < c.max.x && box.max.z > c.min.z && box.min.z < c.max.z else { return dy }
        if dy > 0 && box.max.y <= c.min.y + epsilon { return min(dy, c.min.y - box.max.y) }
        if dy < 0 && box.min.y >= c.max.y - epsilon { return max(dy, c.max.y - box.min.y) }
        return dy
    }
    @inline(__always) public static func clipX(_ c: DBox, _ box: DBox, _ dx: Double) -> Double {
        guard box.max.y > c.min.y && box.min.y < c.max.y && box.max.z > c.min.z && box.min.z < c.max.z else { return dx }
        if dx > 0 && box.max.x <= c.min.x + epsilon { return min(dx, c.min.x - box.max.x) }
        if dx < 0 && box.min.x >= c.max.x - epsilon { return max(dx, c.max.x - box.min.x) }
        return dx
    }
    @inline(__always) public static func clipZ(_ c: DBox, _ box: DBox, _ dz: Double) -> Double {
        guard box.max.x > c.min.x && box.min.x < c.max.x && box.max.y > c.min.y && box.min.y < c.max.y else { return dz }
        if dz > 0 && box.max.z <= c.min.z + epsilon { return min(dz, c.min.z - box.max.z) }
        if dz < 0 && box.min.z >= c.max.z - epsilon { return max(dz, c.max.z - box.min.z) }
        return dz
    }
}
