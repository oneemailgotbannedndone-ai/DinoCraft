import Foundation

public enum StructureKind: String, Sendable, CaseIterable {
    case dungeon, ruin, desertRuin

    public var displayName: String {
        switch self {
        case .dungeon: return "Dungeon"
        case .ruin: return "Ruins"
        case .desertRuin: return "Desert Ruins"
        }
    }
}

public struct StructureInfo: Sendable, Equatable {
    public let kind: StructureKind
    public let x: Int
    public let y: Int
    public let z: Int
    public let seed: UInt64
}

/// Dungeons (hidden mossy rooms underground with loot chests, guarded by
/// Bone Walkers) and surface ruins (crumbling walls with a half-buried chest;
/// desert ruins hide their chest at the bottom of a pit). Like villages they
/// are pure functions of the world seed.
extension TerrainGenerator {
    static let dungeonCell = 80
    static let ruinCell = 176
    static let structureReach = 10

    public func dungeon(inCell cx: Int, _ cz: Int) -> StructureInfo? {
        let h = Hashing.hash(seed, Int32(cx), 11, Int32(cz), salt: 505)
        guard Double(h >> 11) / Double(1 << 53) < 0.45 else { return nil }
        let cell = TerrainGenerator.dungeonCell
        let x = cx * cell + 10 + Int((h >> 8) % UInt64(cell - 20))
        let z = cz * cell + 10 + Int((h >> 20) % UInt64(cell - 20))
        let y = 14 + Int((h >> 32) % 34)
        let info = baseColumnInfo(x: x, z: z)
        guard info.height > y + 10, info.biome != .ocean, info.biome != .river else { return nil }
        return StructureInfo(kind: .dungeon, x: x, y: y, z: z, seed: h)
    }

    public func ruin(inCell cx: Int, _ cz: Int) -> StructureInfo? {
        let h = Hashing.hash(seed, Int32(cx), 13, Int32(cz), salt: 606)
        guard Double(h >> 11) / Double(1 << 53) < 0.5 else { return nil }
        let cell = TerrainGenerator.ruinCell
        let x = cx * cell + 16 + Int((h >> 8) % UInt64(cell - 32))
        let z = cz * cell + 16 + Int((h >> 20) % UInt64(cell - 32))
        let info = baseColumnInfo(x: x, z: z)
        guard info.height > TerrainGenerator.baseSeaLevel + 1, info.height < TerrainGenerator.baseSeaLevel + 60,
              !isCarved(x: x, y: info.height - 1, z: z, surfaceHeight: info.height) else { return nil }
        let kind: StructureKind
        switch info.biome {
        case .desert, .redMesa: kind = .desertRuin
        case .plains, .forest, .fernJungle, .redwoodTaiga, .snowyTundra, .swamp, .mountains, .savanna, .blossomGrove, .silverForest, .flowerMeadow, .fungalMarsh: kind = .ruin
        default: return nil
        }
        guard baseVillages(near: x, z: z, radius: 24).isEmpty else { return nil }
        return StructureInfo(kind: kind, x: x, y: info.height, z: z, seed: h)
    }

    /// Dungeons and ruins within `radius` blocks of (x, z), nearest first.
    func baseStructures(near x: Int, z: Int, radius: Int) -> [StructureInfo] {
        let reach = radius + TerrainGenerator.structureReach
        var out: [StructureInfo] = []
        func scan(_ cell: Int, _ find: (Int, Int) -> StructureInfo?) {
            let c = Double(cell)
            let x0 = Int(floor(Double(x - reach) / c)), x1 = Int(floor(Double(x + reach) / c))
            let z0 = Int(floor(Double(z - reach) / c)), z1 = Int(floor(Double(z + reach) / c))
            for cz in z0...z1 {
                for cx in x0...x1 {
                    if let s = find(cx, cz), abs(s.x - x) <= reach, abs(s.z - z) <= reach { out.append(s) }
                }
            }
        }
        scan(TerrainGenerator.dungeonCell) { dungeon(inCell: $0, $1) }
        scan(TerrainGenerator.ruinCell) { ruin(inCell: $0, $1) }
        return out.sorted { ($0.x - x) * ($0.x - x) + ($0.z - z) * ($0.z - z) < ($1.x - x) * ($1.x - x) + ($1.z - z) * ($1.z - z) }
    }

    /// World positions of the chests a structure generates.
    public func chestPositions(_ s: StructureInfo) -> [(x: Int, y: Int, z: Int)] {
        switch s.kind {
        case .dungeon:
            var list = [(s.x - 3, s.y, s.z)]
            if (s.seed >> 40) & 1 == 1 { list.append((s.x + 3, s.y, s.z)) }
            return list
        case .ruin:
            return [(s.x, s.y - 1, s.z)]
        case .desertRuin:
            return [(s.x, s.y - 4, s.z)]
        }
    }

    func villageChestPositions(_ v: VillageInfo) -> [(x: Int, y: Int, z: Int)] {
        var out: [(x: Int, y: Int, z: Int)] = []
        let dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        for plan in housePlans(for: v) where plan.kind == 1 || plan.kind == 3 {
            let back = (plan.door + 2) % 4
            let (bx, bz) = dirs[back]
            let tx = plan.cx + bx * (plan.halfX - 1), tz = plan.cz + bz * (plan.halfZ - 1)
            let (px, pz) = (-bz, bx)
            out.append(plan.kind == 1 ? (tx - px, plan.y, tz - pz) : (tx + px, plan.y, tz + pz))
        }
        return out
    }

    /// The loot table for a generated chest at this position ("dungeon", "ruin",
    /// "desertRuin" or "village"), or nil if no structure put a chest there.
    func baseLootTable(x: Int, y: Int, z: Int) -> String? {
        for s in baseStructures(near: x, z: z, radius: 2) where chestPositions(s).contains(where: { $0 == (x, y, z) }) {
            return s.kind.rawValue
        }
        for v in baseVillages(near: x, z: z, radius: 2) where villageChestPositions(v).contains(where: { $0 == (x, y, z) }) {
            return "village"
        }
        return nil
    }

    func placeStructures(_ chunk: Chunk) {
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        for s in baseStructures(near: ox + 8, z: oz + 8, radius: 8) {
            switch s.kind {
            case .dungeon: buildDungeon(s, chunk: chunk, ox: ox, oz: oz)
            case .ruin, .desertRuin: buildRuin(s, chunk: chunk, ox: ox, oz: oz)
            }
        }
    }

    private func buildDungeon(_ s: StructureInfo, chunk: Chunk, ox: Int, oz: Int) {
        func inChunk(_ x: Int, _ z: Int) -> Bool { x >= ox && x < ox + 16 && z >= oz && z < oz + 16 }
        func set(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
            guard inChunk(x, z), y > 0, y < TerrainGenerator.baseHeight else { return }
            if chunk.block(x - ox, y, z - oz) == Blocks.bedrock { return }
            chunk.setRaw(x - ox, y, z - oz, id)
        }
        for dz in -4...4 {
            for dx in -4...4 {
                for dy in -1...4 {
                    let x = s.x + dx, y = s.y + dy, z = s.z + dz
                    guard inChunk(x, z) else { continue }
                    let shell = abs(dx) == 4 || abs(dz) == 4 || dy == -1 || dy == 4
                    if shell {
                        let r = Hashing.unit(seed, Int32(x), Int32(y), Int32(z), salt: 507)
                        let id = dy == -1 && r > 0.88 ? Blocks.fossilStone : (r < 0.45 ? Blocks.mossyCobblestone : Blocks.cobblestone)
                        set(x, y, z, id)
                    } else {
                        set(x, y, z, Blocks.air)
                    }
                }
            }
        }
        // Bone piles in two corners and a cracked pillar
        set(s.x - 3, s.y, s.z - 3, Blocks.boneBlock)
        set(s.x + 3, s.y, s.z + 3, Blocks.boneBlock)
        set(s.x + 3, s.y + 1, s.z + 3, Blocks.boneBlock)
        set(s.x - 3, s.y, s.z + 3, Blocks.mossyStoneBricks)
        // Chests face the middle of the room
        let chests = chestPositions(s)
        set(chests[0].x, chests[0].y, chests[0].z, Blocks.chest[1])
        if chests.count > 1 { set(chests[1].x, chests[1].y, chests[1].z, Blocks.chest[3]) }
    }

    private func buildRuin(_ s: StructureInfo, chunk: Chunk, ox: Int, oz: Int) {
        func inChunk(_ x: Int, _ z: Int) -> Bool { x >= ox && x < ox + 16 && z >= oz && z < oz + 16 }
        func set(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
            guard inChunk(x, z), y > 0, y < TerrainGenerator.baseHeight else { return }
            chunk.setRaw(x - ox, y, z - oz, id)
        }
        func get(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
            guard inChunk(x, z), y >= 0, y < TerrainGenerator.baseHeight else { return Blocks.air }
            return chunk.block(x - ox, y, z - oz)
        }
        let desert = s.kind == .desertRuin
        let wallA = desert ? Blocks.sandstone : Blocks.stoneBricks
        let wallB = desert ? Blocks.sandstone : Blocks.mossyStoneBricks
        let clutter: Set<BlockID> = [Blocks.leaves, Blocks.redwoodNeedles, Blocks.tallGrass, Blocks.fern, Blocks.emberbloom,
                                     Blocks.sunpetal, Blocks.deadBush, Blocks.log, Blocks.redwoodLog]
        let y = s.y

        for dz in -5...5 {
            for dx in -5...5 {
                let x = s.x + dx, z = s.z + dz
                guard inChunk(x, z) else { continue }
                for cy in y..<(y + 8) where clutter.contains(get(x, cy, z)) { set(x, cy, z, Blocks.air) }
                let ring = max(abs(dx), abs(dz))
                guard ring <= 4 else { continue }
                for fy in (y - 4)..<(y - 1) where get(x, fy, z) == Blocks.air || get(x, fy, z) == Blocks.water { set(x, fy, z, wallA) }
                let r = Hashing.unit(seed, Int32(x), 0, Int32(z), salt: 611)
                if r < 0.75 {
                    set(x, y - 1, z, desert ? Blocks.sandstone : (r < 0.3 ? Blocks.mossyCobblestone : Blocks.stoneBricks))
                }
                if ring == 4 {
                    let corner = abs(dx) == 4 && abs(dz) == 4
                    let height = corner ? 4 + Int(r * 2) : Int(Hashing.unit(seed, Int32(x), 1, Int32(z), salt: 612) * 4)
                    for dy in 0..<height {
                        let broken = Hashing.unit(seed, Int32(x), Int32(y + dy), Int32(z), salt: 613)
                        set(x, y + dy, z, broken < 0.4 ? wallB : wallA)
                    }
                    if desert && corner { set(x, y + height, z, Blocks.amberBlock) }
                }
            }
        }

        // A fallen pillar lying just outside the walls
        var rng = SplitMix64(seed: s.seed)
        let dirs = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        let (fx, fz) = dirs[rng.nextInt(4)]
        let shift = rng.nextInt(5) - 2
        for t in 0..<4 {
            let x = s.x + fx * 7 + (-fz) * (t + shift - 2), z = s.z + fz * 7 + fx * (t + shift - 2)
            guard inChunk(x, z) else { continue }
            let h = baseColumnInfo(x: x, z: z).height
            if h > TerrainGenerator.baseSeaLevel { set(x, h, z, t % 2 == 0 ? wallA : wallB) }
        }

        let chest = chestPositions(s)[0]
        if desert {
            // A pit leads down to the treasure
            for dz in -2...2 {
                for dx in -2...2 {
                    let rim = abs(dx) == 2 || abs(dz) == 2
                    for dy in -5...(-1) {
                        let id: BlockID = dy == -5 ? Blocks.sandstone : (rim ? Blocks.sandstone : Blocks.air)
                        set(s.x + dx, y + dy, s.z + dz, id)
                    }
                }
            }
            set(chest.x, chest.y, chest.z, Blocks.chest[2])
            set(s.x - 1, y - 4, s.z - 1, Blocks.amberLantern)
        } else {
            set(chest.x, chest.y - 1, chest.z, Blocks.cobblestone)
            set(chest.x, chest.y, chest.z, Blocks.chest[2])
            if rng.nextInt(2) == 0 {
                set(s.x + 2, y, s.z - 2, Blocks.stoneBricks)
                set(s.x + 2, y + 1, s.z - 2, Blocks.amberLantern)
            }
        }
    }
}
