import Foundation

/// A generated village: the plaza center (surface height `y`) and its layout seed.
public struct VillageInfo: Sendable, Equatable {
    public let x: Int
    public let y: Int
    public let z: Int
    public let seed: UInt64
}

/// Deterministic villages for the overworld: a well on a gravel plaza, four
/// paths ending in lantern posts, and small houses with doors, windows, a
/// wall torch and furniture. Villages are pure functions of the seed, so
/// every chunk can build its slice of a village independently.
extension TerrainGenerator {
    public static let villageCell = 384
    static let villageReach = 48
    static let villageArm = 30

    struct HousePlan {
        let cx: Int, cz: Int, y: Int
        let halfX: Int, halfZ: Int
        let door: Int     // 0 north, 1 east, 2 south, 3 west
        let kind: Int
    }

    private static let directions = [(0, -1), (1, 0), (0, 1), (-1, 0)]

    /// The village in a village grid cell, if the site is suitable.
    public func village(inCell cx: Int, _ cz: Int) -> VillageInfo? {
        let h = Hashing.hash(seed, Int32(cx), 7, Int32(cz), salt: 404)
        guard Double(h >> 11) / Double(1 << 53) < 0.6 else { return nil }
        let cell = TerrainGenerator.villageCell
        let span = UInt64(cell - 160)
        let x = cx * cell + 80 + Int((h >> 8) % span)
        let z = cz * cell + 80 + Int((h >> 24) % span)
        let info = columnInfo(x: x, z: z)
        let suitable: Set<Biome> = [.plains, .forest, .desert, .snowyTundra, .redwoodTaiga, .savanna, .flowerMeadow]
        guard suitable.contains(info.biome), info.height > WorldConst.seaLevel + 1, info.height < WorldConst.seaLevel + 36,
              !isCarved(x: x, y: info.height - 1, z: z, surfaceHeight: info.height) else { return nil }
        return VillageInfo(x: x, y: info.height, z: z, seed: h)
    }

    /// Villages whose area comes within `radius` blocks of (x, z), nearest first.
    public func villages(near x: Int, z: Int, radius: Int) -> [VillageInfo] {
        let cell = Double(TerrainGenerator.villageCell)
        let reach = radius + TerrainGenerator.villageReach
        let x0 = Int(floor(Double(x - reach) / cell)), x1 = Int(floor(Double(x + reach) / cell))
        let z0 = Int(floor(Double(z - reach) / cell)), z1 = Int(floor(Double(z + reach) / cell))
        var out: [VillageInfo] = []
        for cz in z0...z1 {
            for cx in x0...x1 {
                if let v = village(inCell: cx, cz), abs(v.x - x) <= reach, abs(v.z - z) <= reach { out.append(v) }
            }
        }
        return out.sorted { ($0.x - x) * ($0.x - x) + ($0.z - z) * ($0.z - z) < ($1.x - x) * ($1.x - x) + ($1.z - z) * ($1.z - z) }
    }

    func housePlans(for v: VillageInfo) -> [HousePlan] {
        var rng = SplitMix64(seed: v.seed)
        var plans: [HousePlan] = []
        for arm in 0..<4 {
            let (dx, dz) = TerrainGenerator.directions[arm]
            let (px, pz) = (-dz, dx)
            for slot in 0..<2 {
                let roll = rng.nextInt(100), sideRoll = rng.nextInt(2), kind = rng.nextInt(4)
                guard roll < 85 else { continue }
                let side = sideRoll == 0 ? 1 : -1
                let big = kind == 3
                let along = 10 + slot * 12
                let offset = big ? 7 : 6
                let hx = v.x + dx * along + px * side * offset
                let hz = v.z + dz * along + pz * side * offset
                let info = columnInfo(x: hx, z: hz)
                guard info.height > WorldConst.seaLevel, abs(info.height - v.y) <= 6 else { continue }
                let toPath = (-px * side, -pz * side)
                let door = TerrainGenerator.directions.firstIndex { $0 == toPath } ?? 0
                plans.append(HousePlan(cx: hx, cz: hz, y: info.height, halfX: big ? 3 : 2, halfZ: big ? 3 : 2, door: door, kind: kind))
            }
        }
        return plans
    }

    func placeVillages(_ chunk: Chunk) {
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        for v in villages(near: ox + 8, z: oz + 8, radius: 8) {
            buildVillage(v, chunk: chunk, ox: ox, oz: oz)
        }
    }

    private func buildVillage(_ v: VillageInfo, chunk: Chunk, ox: Int, oz: Int) {
        func inChunk(_ x: Int, _ z: Int) -> Bool { x >= ox && x < ox + 16 && z >= oz && z < oz + 16 }
        func set(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
            guard inChunk(x, z), y > 0, y < WorldConst.height else { return }
            chunk.setRaw(x - ox, y, z - oz, id)
        }
        func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard inChunk(x, z), y >= 0, y < WorldConst.height else { return Blocks.air }
            return chunk.block(x - ox, y, z - oz)
        }
        let soft: Set<BlockID> = [Blocks.air, Blocks.leaves, Blocks.redwoodNeedles, Blocks.tallGrass, Blocks.fern, Blocks.emberbloom,
                                  Blocks.sunpetal, Blocks.deadBush, Blocks.water, Blocks.redwoodLog, Blocks.log]
        let plants: Set<BlockID> = [Blocks.tallGrass, Blocks.fern, Blocks.emberbloom, Blocks.sunpetal, Blocks.deadBush]

        func path(_ x: Int, _ z: Int) {
            guard inChunk(x, z) else { return }
            let h = columnInfo(x: x, z: z).height
            guard h > WorldConst.seaLevel else { return }
            let top = get(x, h - 1, z)
            if [Blocks.grass, Blocks.dirt, Blocks.sand, Blocks.snowyGrass, Blocks.mud, Blocks.skyGrass].contains(top) {
                set(x, h - 1, z, Blocks.gravel)
            }
            if plants.contains(get(x, h, z)) { set(x, h, z, Blocks.air) }
        }

        // Plaza and paths
        for dz in -5...5 { for dx in -5...5 { path(v.x + dx, v.z + dz) } }
        let arm = TerrainGenerator.villageArm
        for (dx, dz) in TerrainGenerator.directions {
            for t in 6...arm {
                for p in -1...1 { path(v.x + dx * t - dz * p, v.z + dz * t + dx * p) }
            }
            let lx = v.x + dx * (arm + 2), lz = v.z + dz * (arm + 2)
            if inChunk(lx, lz) {
                let h = columnInfo(x: lx, z: lz).height
                if h > WorldConst.seaLevel {
                    set(lx, h, lz, Blocks.log)
                    set(lx, h + 1, lz, Blocks.log)
                    set(lx, h + 2, lz, Blocks.amberLantern)
                }
            }
        }

        // Well
        let wy = v.y
        for dz in -2...2 {
            for dx in -2...2 {
                let x = v.x + dx, z = v.z + dz
                guard inChunk(x, z) else { continue }
                let rim = abs(dx) == 2 || abs(dz) == 2
                let post = abs(dx) == 2 && abs(dz) == 2
                set(x, wy - 4, z, Blocks.cobblestone)
                set(x, wy - 3, z, Blocks.cobblestone)
                set(x, wy - 2, z, rim ? Blocks.cobblestone : Blocks.water)
                set(x, wy - 1, z, rim ? Blocks.cobblestone : Blocks.water)
                set(x, wy, z, rim ? Blocks.cobblestone : Blocks.air)
                set(x, wy + 1, z, post ? Blocks.log : Blocks.air)
                set(x, wy + 2, z, post ? Blocks.log : Blocks.air)
                set(x, wy + 3, z, Blocks.planksSlab)
            }
        }

        // Houses
        for plan in housePlans(for: v) {
            let x0 = plan.cx - plan.halfX, x1 = plan.cx + plan.halfX
            let z0 = plan.cz - plan.halfZ, z1 = plan.cz + plan.halfZ
            guard x1 >= ox - 1, x0 <= ox + 16, z1 >= oz - 1, z0 <= oz + 16 else { continue }
            let y = plan.y
            let (fx, fz) = TerrainGenerator.directions[plan.door]
            let doorX = plan.cx + fx * plan.halfX, doorZ = plan.cz + fz * plan.halfZ

            for x in (x0 - 1)...(x1 + 1) {
                for z in (z0 - 1)...(z1 + 1) where inChunk(x, z) {
                    let inside = x >= x0 && x <= x1 && z >= z0 && z <= z1
                    guard inside else {
                        // Clear a one-block margin so trees don't grow into walls.
                        for cy in y..<(y + 5) where soft.contains(get(x, cy, z)) && get(x, cy, z) != Blocks.water { set(x, cy, z, Blocks.air) }
                        continue
                    }
                    let edgeX = x == x0 || x == x1, edgeZ = z == z0 || z == z1
                    let edge = edgeX || edgeZ, corner = edgeX && edgeZ
                    for fy in (y - 6)..<(y - 1) where soft.contains(get(x, fy, z)) || get(x, fy, z) == Blocks.air {
                        set(x, fy, z, Blocks.cobblestone)
                    }
                    set(x, y - 1, z, edge ? Blocks.cobblestone : Blocks.planks)
                    for dy in 0..<3 {
                        let id: BlockID
                        if corner {
                            id = Blocks.log
                        } else if edge {
                            id = (dy == 1 && (x == plan.cx || z == plan.cz)) ? Blocks.glass : Blocks.planks
                        } else {
                            id = Blocks.air
                        }
                        set(x, y + dy, z, id)
                    }
                    set(x, y + 3, z, edge ? Blocks.log : Blocks.planks)
                    set(x, y + 4, z, edge ? Blocks.air : Blocks.planksSlab)
                    for cy in (y + 5)..<(y + 10) where get(x, cy, z) != Blocks.air { set(x, cy, z, Blocks.air) }
                }
            }

            // Door and doorstep
            set(doorX, y, doorZ, Blocks.doorLowerClosed[plan.door])
            set(doorX, y + 1, doorZ, Blocks.doorUpperClosed[plan.door])
            set(doorX + fx, y - 1, doorZ + fz, Blocks.gravel)
            set(doorX + fx, y, doorZ + fz, Blocks.air)
            set(doorX + fx, y + 1, doorZ + fz, Blocks.air)

            // Furniture along the back wall, lit by a wall torch
            let back = (plan.door + 2) % 4
            let (bx, bz) = TerrainGenerator.directions[back]
            let tx = plan.cx + bx * (plan.halfX - 1), tz = plan.cz + bz * (plan.halfZ - 1)
            set(tx, y + 2, tz, Blocks.wallTorch[back])
            let (px, pz) = (-bz, bx)
            let left = (tx + px, tz + pz), right = (tx - px, tz - pz)
            switch plan.kind {
            case 0:
                set(left.0, y, left.1, Blocks.craftingBench)
                set(right.0, y, right.1, Blocks.bookshelf)
            case 1:
                set(left.0, y, left.1, Blocks.furnace[plan.door])
                set(right.0, y, right.1, Blocks.chest[plan.door])
            case 2:
                set(left.0, y, left.1, Blocks.bookshelf)
                set(right.0, y, right.1, Blocks.bookshelf)
            default:
                set(left.0, y, left.1, Blocks.chest[plan.door])
                set(right.0, y, right.1, Blocks.craftingBench)
                set(tx, y, tz, Blocks.furnace[plan.door])
            }
        }
    }
}
