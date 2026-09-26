import Foundation

// MARK: - Toonland

/// A cheerful black-and-white cartoon world: rolling chalk-white hills, puffball
/// trees, smiling flowers and floating clouds. Checkered roads run along a grid
/// and meet at round stages where King Grumblesaurus holds court.
public final class ToonlandGenerator: WorldGenerator, @unchecked Sendable {
    public let seed: UInt64
    public var dimension: WorldDimension { .toonland }

    /// Stages sit on road crossings every `stageSpacing` blocks.
    public static let stageSpacing = 160
    public static let stageRadius = 12
    public static let stageFloor = 66
    public static let pondLevel = 58
    public static let cloudLevel = 112

    private let hills: SimplexNoise
    private let bumps: SimplexNoise
    private let clouds: SimplexNoise

    public init(seed: UInt64) {
        self.seed = seed
        hills = SimplexNoise(seed: Hashing.hash(seed, 1, 0, 0, salt: 801))
        bumps = SimplexNoise(seed: Hashing.hash(seed, 2, 0, 0, salt: 802))
        clouds = SimplexNoise(seed: Hashing.hash(seed, 3, 0, 0, salt: 803))
    }

    /// Centre of the stage nearest to a column.
    public static func nearestStage(x: Int, z: Int) -> (x: Int, z: Int) {
        func snap(_ v: Int) -> Int { Int((Double(v) / Double(stageSpacing)).rounded()) * stageSpacing }
        return (snap(x), snap(z))
    }

    /// Distance (in blocks) from a column to the nearest road centre line.
    private static func roadDistance(x: Int, z: Int) -> Int {
        func d(_ v: Int) -> Int {
            let m = ((v % stageSpacing) + stageSpacing) % stageSpacing
            return min(m, stageSpacing - m)
        }
        return min(d(x), d(z))
    }

    /// Height of the rolling hills (the top grass block sits at `height - 1`).
    private func hillHeight(x: Int, z: Int) -> Int {
        let fx = Double(x), fz = Double(z)
        let h = 65 + hills.fbm2(fx / 110, fz / 110, octaves: 3) * 11 + bumps.noise2(fx / 26, fz / 26) * 2.5
        return Int(h.rounded())
    }

    /// Final surface height: the hills ease down (or up) to meet each stage.
    private func surface(x: Int, z: Int) -> Int {
        let hill = Double(hillHeight(x: x, z: z))
        let stage = ToonlandGenerator.nearestStage(x: x, z: z)
        let dx = Double(x - stage.x), dz = Double(z - stage.z)
        let r = sqrt(dx * dx + dz * dz)
        let flat = Double(ToonlandGenerator.stageFloor + 1)
        let blend = max(0, min(1, (r - Double(ToonlandGenerator.stageRadius)) / 18))
        let t = blend * blend * (3 - 2 * blend)
        return Int((flat + (hill - flat) * t).rounded())
    }

    public func generate(_ pos: ChunkPos) -> Chunk {
        let chunk = Chunk(pos: pos)
        let ox = Int(pos.originX), oz = Int(pos.originZ)
        for z in 0..<16 {
            for x in 0..<16 {
                let wx = ox + x, wz = oz + z
                let height = surface(x: wx, z: wz)
                let stage = ToonlandGenerator.nearestStage(x: wx, z: wz)
                let dx = wx - stage.x, dz = wz - stage.z
                let r2 = dx * dx + dz * dz
                let sr = ToonlandGenerator.stageRadius
                let onStage = r2 <= sr * sr
                let road = ToonlandGenerator.roadDistance(x: wx, z: wz) <= 1

                chunk.setRaw(x, 0, z, Blocks.bedrock)
                let top = onStage ? ToonlandGenerator.stageFloor : height - 1
                if top >= 1 {
                    for y in 1...top {
                        let id: BlockID
                        if y == top {
                            id = onStage || road ? Blocks.checkerBlock : (top < ToonlandGenerator.pondLevel ? Blocks.toonSoil : Blocks.toonGrass)
                        } else if y >= top - 3 {
                            id = Blocks.toonSoil
                        } else {
                            id = Blocks.toonStone
                        }
                        chunk.setRaw(x, y, z, id)
                    }
                }
                // Ponds in the dips
                if !onStage && top < ToonlandGenerator.pondLevel {
                    for y in (top + 1)...ToonlandGenerator.pondLevel { chunk.setRaw(x, y, z, Blocks.water) }
                }
                // A raised rim around each stage, open where the roads come in
                let r = sqrt(Double(r2))
                if abs(r - Double(sr) - 0.5) < 0.75 && abs(dx) > 1 && abs(dz) > 1 {
                    chunk.setRaw(x, ToonlandGenerator.stageFloor + 1, z, Blocks.checkerBlock)
                }
                if onStage || (r < Double(sr) + 2) {
                    for y in (ToonlandGenerator.stageFloor + (onStage ? 1 : 2))..<(ToonlandGenerator.stageFloor + 14) where chunk.block(x, y, z) != Blocks.checkerBlock {
                        chunk.setRaw(x, y, z, Blocks.air)
                    }
                }
                // Lanterns on posts around the stage
                if abs(dx) == sr - 4 && abs(dz) == sr - 4 {
                    chunk.setRaw(x, ToonlandGenerator.stageFloor + 1, z, Blocks.toonLog)
                    chunk.setRaw(x, ToonlandGenerator.stageFloor + 2, z, Blocks.toonLog)
                    chunk.setRaw(x, ToonlandGenerator.stageFloor + 3, z, Blocks.amberLantern)
                }
                // Puffy clouds
                let c = clouds.fbm2(Double(wx) / 48, Double(wz) / 48, octaves: 3)
                if c > 0.34 {
                    let thick = c > 0.5 ? 3 : (c > 0.42 ? 2 : 1)
                    for dy in 0..<thick { chunk.setRaw(x, ToonlandGenerator.cloudLevel + dy, z, Blocks.cloud) }
                }
                // Flowers and grass on open hills
                if !onStage && !road && top >= ToonlandGenerator.pondLevel && r > Double(sr) + 2 {
                    let roll = Hashing.unit(seed, Int32(wx), Int32(top), Int32(wz), salt: 41)
                    if roll < 0.045 { chunk.setRaw(x, top + 1, z, Blocks.smileFlower) }
                    else if roll < 0.07 { chunk.setRaw(x, top + 1, z, Blocks.whiteDaisy) }
                    else if roll < 0.2 { chunk.setRaw(x, top + 1, z, Blocks.tallGrass) }
                }
            }
        }

        // Puffball trees, kept inside the chunk so chunks stay independent
        var rng = SplitMix64(seed: Hashing.hash(seed, pos.x, 5, pos.z, salt: 815))
        for _ in 0..<3 {
            let x = 3 + rng.nextInt(10), z = 3 + rng.nextInt(10)
            guard rng.nextInt(3) == 0 else { continue }
            let wx = ox + x, wz = oz + z
            let stage = ToonlandGenerator.nearestStage(x: wx, z: wz)
            let dx = Double(wx - stage.x), dz = Double(wz - stage.z)
            guard sqrt(dx * dx + dz * dz) > Double(ToonlandGenerator.stageRadius) + 6,
                  ToonlandGenerator.roadDistance(x: wx, z: wz) > 3 else { continue }
            var y = 120
            while y > 1 && chunk.block(x, y, z) != Blocks.toonGrass { y -= 1 }
            guard y > ToonlandGenerator.pondLevel else { continue }
            let trunk = 3 + rng.nextInt(3)
            for dy in 1...trunk { chunk.setRaw(x, y + dy, z, Blocks.toonLog) }
            let cy = y + trunk + 2
            for oy in -2...2 {
                for oz2 in -3...3 {
                    for ox2 in -3...3 where ox2 * ox2 + oy * oy * 2 + oz2 * oz2 <= 10 {
                        let id = chunk.block(x + ox2, cy + oy, z + oz2)
                        if id == Blocks.air || id == Blocks.tallGrass { chunk.setRaw(x + ox2, cy + oy, z + oz2, Blocks.toonLeaves) }
                    }
                }
            }
        }
        LatticeSampler.vein(chunk, &rng, block: Blocks.coalOre, replace: Blocks.toonStone, attempts: 8, minY: 5, maxY: 60, size: 10)
        LatticeSampler.vein(chunk, &rng, block: Blocks.ironOre, replace: Blocks.toonStone, attempts: 5, minY: 5, maxY: 55, size: 7)
        LatticeSampler.vein(chunk, &rng, block: Blocks.diamondOre, replace: Blocks.toonStone, attempts: 1, minY: 5, maxY: 20, size: 4)
        chunk.recomputeHeights()
        return chunk
    }

    public func findSpawnColumn() -> (x: Int, z: Int) {
        (ToonlandGenerator.stageRadius + 20, 1)
    }

    public func biome(x: Int, z: Int) -> Biome { .toonland }

    public func estimatedSurface(x: Int, z: Int) -> Int {
        let stage = ToonlandGenerator.nearestStage(x: x, z: z)
        let dx = x - stage.x, dz = z - stage.z
        let sr = ToonlandGenerator.stageRadius
        if dx * dx + dz * dz <= sr * sr { return ToonlandGenerator.stageFloor + 1 }
        return max(surface(x: x, z: z), ToonlandGenerator.pondLevel + 1)
    }
}
