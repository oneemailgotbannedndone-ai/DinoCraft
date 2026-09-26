import Foundation

// MARK: - The deep layers

/// New overworlds go down to Y -70: the terrain is generated as before and lifted
/// `depth` blocks, and the space below the old bedrock is filled with Deep Slate —
/// winding caves, lava pools near the bottom and richer ores. The public queries
/// here return lifted (real) heights; the generator works in "base" heights inside.
extension TerrainGenerator {
    /// Sea level in this world's real coordinates.
    public var seaLevel: Int { TerrainGenerator.baseSeaLevel + depth }

    public func columnInfo(x: Int, z: Int) -> ColumnInfo {
        var info = baseColumnInfo(x: x, z: z)
        info.height += depth
        return info
    }

    public func villages(near x: Int, z: Int, radius: Int) -> [VillageInfo] {
        baseVillages(near: x, z: z, radius: radius).map { VillageInfo(x: $0.x, y: $0.y + depth, z: $0.z, seed: $0.seed) }
    }

    public func structures(near x: Int, z: Int, radius: Int) -> [StructureInfo] {
        baseStructures(near: x, z: z, radius: radius).map { StructureInfo(kind: $0.kind, x: $0.x, y: $0.y + depth, z: $0.z, seed: $0.seed) }
    }

    /// The loot table for a generated chest at this (real) position, or nil.
    public func lootTable(x: Int, y: Int, z: Int) -> String? { baseLootTable(x: x, y: y - depth, z: z) }

    public func generate(_ pos: ChunkPos) -> Chunk {
        let chunk = generateBase(pos)
        guard depth > 0 else { return chunk }
        let layer = 16 * 16
        // Lift everything, then carve the deep layers into the new space underneath.
        (chunk.blocks + depth * layer).update(from: chunk.blocks, count: TerrainGenerator.baseHeight * layer)
        fillDeepLayers(chunk)
        chunk.recomputeHeights()
        return chunk
    }

    private func fillDeepLayers(_ chunk: Chunk) {
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        let caves = SimplexNoise(seed: Hashing.hash(seed, 7, 0, 0, salt: 901))
        let tunnels = SimplexNoise(seed: Hashing.hash(seed, 8, 0, 0, salt: 902))
        let top = depth + 5   // the old bedrock floor sat in the bottom five layers of the base terrain
        for z in 0..<16 {
            for x in 0..<16 {
                let wx = Int32(ox + x), wz = Int32(oz + z)
                for y in 0..<top {
                    let id: BlockID
                    if y == 0 {
                        id = Blocks.bedrock
                    } else if y <= 4 && Hashing.unit(seed, wx, Int32(y), wz, salt: 911) < Float(5 - y) / 5 {
                        id = Blocks.bedrock
                    } else {
                        let fx = Double(wx), fy = Double(y), fz = Double(wz)
                        // Big caverns and long twisting tunnels
                        let cavern = caves.noise3(fx / 44, fy / 22, fz / 44)
                        let tunnel = abs(tunnels.noise3(fx / 26, fy / 16, fz / 26))
                        let open = (cavern > 0.44 || tunnel < 0.07) && y > 5 && y < top - 3
                        if open {
                            id = y <= 11 ? Blocks.lava : Blocks.air
                        } else {
                            id = Blocks.deepSlate
                        }
                    }
                    chunk.setRaw(x, y, z, id)
                }
            }
        }
        var rng = SplitMix64(seed: Hashing.hash(seed, chunk.pos.x, 11, chunk.pos.z, salt: 913))
        let hi = top - 2
        LatticeSampler.vein(chunk, &rng, block: Blocks.diamondOre, replace: Blocks.deepSlate, attempts: 4, minY: 5, maxY: 40, size: 6)
        LatticeSampler.vein(chunk, &rng, block: Blocks.goldOre, replace: Blocks.deepSlate, attempts: 6, minY: 5, maxY: hi, size: 8)
        LatticeSampler.vein(chunk, &rng, block: Blocks.ironOre, replace: Blocks.deepSlate, attempts: 10, minY: 5, maxY: hi, size: 9)
        LatticeSampler.vein(chunk, &rng, block: Blocks.emeraldOre, replace: Blocks.deepSlate, attempts: 2, minY: 5, maxY: hi, size: 4)
        LatticeSampler.vein(chunk, &rng, block: Blocks.amberOre, replace: Blocks.deepSlate, attempts: 3, minY: 5, maxY: hi, size: 5)
        LatticeSampler.vein(chunk, &rng, block: Blocks.fossilStone, replace: Blocks.deepSlate, attempts: 3, minY: 5, maxY: hi, size: 7)
        LatticeSampler.vein(chunk, &rng, block: Blocks.basalt, replace: Blocks.deepSlate, attempts: 4, minY: 5, maxY: 25, size: 14)
    }
}
