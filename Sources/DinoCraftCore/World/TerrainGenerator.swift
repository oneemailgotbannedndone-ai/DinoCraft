import Foundation

public enum Biome: UInt8, CaseIterable, Sendable {
    case ocean, beach, plains, forest, fernJungle, desert, redwoodTaiga, snowyTundra, mountains, snowyPeaks, swamp, river
    case underworld, skylands
    case savanna, redMesa, blossomGrove, silverForest, fungalMarsh, volcanicWastes, glacier, flowerMeadow
    case toonland

    public var displayName: String {
        switch self {
        case .ocean: return "Ocean"
        case .beach: return "Beach"
        case .plains: return "Plains"
        case .forest: return "Ginkgo Forest"
        case .fernJungle: return "Fern Jungle"
        case .desert: return "Badlands Desert"
        case .redwoodTaiga: return "Redwood Taiga"
        case .snowyTundra: return "Frozen Tundra"
        case .mountains: return "Mountains"
        case .snowyPeaks: return "Snowy Peaks"
        case .swamp: return "Swamp"
        case .river: return "River"
        case .savanna: return "Cycad Savanna"
        case .redMesa: return "Red Mesa"
        case .blossomGrove: return "Blossom Grove"
        case .silverForest: return "Silverbark Forest"
        case .fungalMarsh: return "Fungal Marsh"
        case .volcanicWastes: return "Volcanic Wastes"
        case .glacier: return "Glacier"
        case .flowerMeadow: return "Flower Meadow"
        case .underworld: return "Volcanic Underworld"
        case .skylands: return "Amber Skylands"
        case .toonland: return "Toonland"
        }
    }
}

public struct ColumnInfo: Sendable {
    /// Number of solid blocks in the column before caves: the top surface
    /// block sits at `height - 1`.
    public var height: Int
    public var biome: Biome
    public var temperature: Double
    public var humidity: Double
    public var detail: Double
}

/// Deterministic procedural terrain.
///
/// Every decision derives from the world seed through pure functions of world
/// coordinates, so any chunk can be generated independently, in any order, on
/// any thread, and the same seed always yields the same world.
///
/// Pipeline per chunk: column shaping (continents, erosion, ridged mountains,
/// river valleys) → biome selection (temperature / humidity / altitude) →
/// strata and surface blocks → water → caves (interpolated 3D noise) → ores →
/// trees and plants (placed from a world-aligned jittered grid so features
/// cross chunk borders seamlessly).
public final class TerrainGenerator: @unchecked Sendable {
    public let seed: UInt64

    private let warpX, warpZ, continent, erosion, ridge, detail, river: SimplexNoise
    private let temperatureNoise, humidityNoise, variantNoise: SimplexNoise
    private let caveA, caveB, cavern: SimplexNoise

    private static let caveStride = 4
    private static let treeCell = 5
    private static let treeMargin = 5

    public init(seed: UInt64) {
        self.seed = seed
        func sub(_ salt: UInt64) -> SimplexNoise { SimplexNoise(seed: Hashing.hash(seed, 0, 0, 0, salt: salt)) }
        warpX = sub(11); warpZ = sub(12)
        continent = sub(21); erosion = sub(22); ridge = sub(23); detail = sub(24); river = sub(25)
        temperatureNoise = sub(31); humidityNoise = sub(32); variantNoise = sub(33)
        caveA = sub(41); caveB = sub(42); cavern = sub(43)
    }

    // MARK: - Column shaping

    private static let continentSpline: [(Double, Double)] = [
        (-1.0, -40), (-0.40, -32), (-0.22, -18), (-0.10, -6), (-0.03, 0.5),
        (0.06, 3), (0.25, 10), (0.55, 20), (1.0, 30),
    ]

    @inline(__always) private static func spline(_ points: [(Double, Double)], _ x: Double) -> Double {
        if x <= points[0].0 { return points[0].1 }
        for i in 1..<points.count where x < points[i].0 {
            let (x0, y0) = points[i - 1], (x1, y1) = points[i]
            let t = (x - x0) / (x1 - x0)
            return y0 + (y1 - y0) * t
        }
        return points[points.count - 1].1
    }

    @inline(__always) private static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(1, max(0, (x - e0) / (e1 - e0)))
        return t * t * (3 - 2 * t)
    }

    public func columnInfo(x: Int, z: Int) -> ColumnInfo {
        let fx = Double(x), fz = Double(z)
        let wx = fx + warpX.fbm2(fx / 320, fz / 320, octaves: 2) * 70
        let wz = fz + warpZ.fbm2(fx / 320, fz / 320, octaves: 2) * 70

        let c = continent.fbm2(wx / 1500, wz / 1500, octaves: 5) * 1.6 + 0.14
        let e = erosion.fbm2(wx / 750, wz / 750, octaves: 4) * 1.6
        let r = ridge.ridged2(wx / 520, wz / 520, octaves: 5)
        let d = detail.fbm2(fx / 96, fz / 96, octaves: 4) * 1.5

        let land = TerrainGenerator.smooth(-0.08, 0.06, c)
        let mountainMask = TerrainGenerator.smooth(0.02, 0.35, c) * (1 - TerrainGenerator.smooth(-0.45, 0.1, e))
        let hillAmp = (3 + 13 * (1 - TerrainGenerator.smooth(-0.3, 0.45, e))) * (0.35 + 0.65 * land)

        var h = Double(WorldConst.seaLevel)
            + TerrainGenerator.spline(TerrainGenerator.continentSpline, c)
            + d * hillAmp
            + pow(r, 1.7) * 125 * mountainMask
            + d * 10 * mountainMask

        // River valleys: carve toward just below sea level along noise zero-crossings.
        let rv = abs(river.fbm2(wx / 950, wz / 950, octaves: 3) * 1.6)
        let riverBed = Double(WorldConst.seaLevel - 4)
        if c > -0.12 && h > riverBed {
            let width = 0.05 + 0.12 * mountainMask
            let f = TerrainGenerator.smooth(0.008, width, rv)
            h = riverBed + (h - riverBed) * f
        }
        let height = Int(min(236, max(6, h.rounded())))

        let altitudeChill = max(0, Double(height - WorldConst.seaLevel - 28)) / 120
        let temperature = temperatureNoise.fbm2(fx / 1700, fz / 1700, octaves: 4) * 1.7 - altitudeChill
        let humidity = humidityNoise.fbm2(fx / 1400, fz / 1400, octaves: 4) * 1.7

        let biome: Biome
        let sea = WorldConst.seaLevel
        if height < sea - 1 {
            biome = (rv < 0.035 && c > -0.12) ? .river : .ocean
        } else if height <= sea + 1 && rv >= 0.035 && c < 0.12 {
            biome = .beach
        } else if height > sea + 78 {
            biome = .snowyPeaks
        } else if height > sea + 48 {
            biome = temperature < -0.35 ? .snowyPeaks : .mountains
        } else {
            // A slow "variant" field picks rarer sub-biomes inside each climate band.
            let v = variantNoise.fbm2(fx / 900, fz / 900, octaves: 3) * 1.7
            if temperature > 0.32 && humidity < -0.05 {
                biome = v > 0.32 ? .redMesa : (v < -0.42 ? .volcanicWastes : .desert)
            } else if temperature < -0.5 {
                biome = v > 0.25 ? .glacier : .snowyTundra
            } else if temperature < -0.22 {
                biome = v < -0.3 ? .silverForest : .redwoodTaiga
            } else if humidity > 0.3 && temperature > 0.15 {
                biome = .fernJungle
            } else if humidity > 0.3 && height < sea + 6 {
                biome = v > 0.3 ? .fungalMarsh : .swamp
            } else if humidity > -0.05 {
                biome = v > 0.32 ? .blossomGrove : (v < -0.32 ? .silverForest : .forest)
            } else if temperature > 0.18 {
                biome = .savanna
            } else {
                biome = v > 0.3 ? .flowerMeadow : .plains
            }
        }
        return ColumnInfo(height: height, biome: biome, temperature: temperature, humidity: humidity, detail: d)
    }

    // MARK: - Caves

    /// Raw cave field sample at a lattice point (world coordinates multiple of the stride).
    @inline(__always) private func caveSample(_ x: Int, _ y: Int, _ z: Int) -> (Float, Float, Float) {
        let fx = Double(x), fy = Double(y), fz = Double(z)
        let a = Float(caveA.noise3(fx / 52, fy / 34, fz / 52))
        let b = Float(caveB.noise3(fx / 52, fy / 34, fz / 52))
        let c = Float(cavern.fbm3(fx / 96, fy / 60, fz / 96, octaves: 2))
        return (a, b, c)
    }

    @inline(__always) private static func isCave(a: Float, b: Float, c: Float, y: Int, depthBelowSurface: Int) -> Bool {
        let surfaceFade: Float = depthBelowSurface < 8 ? Float(depthBelowSurface) / 8 : 1
        let tunnel = a * a + b * b < 0.0055 * (0.35 + 0.65 * surfaceFade)
        let cavernLimit: Float = y < 48 ? 0.34 + Float(y) / 48 * 0.2 : 1
        return tunnel || (c > cavernLimit && depthBelowSurface > 10)
    }

    /// Standalone cave query (identical to the interpolated per-chunk evaluation).
    public func isCarved(x: Int, y: Int, z: Int, surfaceHeight: Int) -> Bool {
        guard y > 4 else { return false }
        let s = TerrainGenerator.caveStride
        let lx = x >> 2, ly = y >> 2, lz = z >> 2
        let tx = Float(x - lx * s) / Float(s), ty = Float(y - ly * s) / Float(s), tz = Float(z - lz * s) / Float(s)
        var corners = [(Float, Float, Float)](repeating: (0, 0, 0), count: 8)
        for i in 0..<8 {
            corners[i] = caveSample((lx + (i & 1)) * s, (ly + ((i >> 1) & 1)) * s, (lz + ((i >> 2) & 1)) * s)
        }
        let v = TerrainGenerator.trilinear(corners, tx, ty, tz)
        return TerrainGenerator.isCave(a: v.0, b: v.1, c: v.2, y: y, depthBelowSurface: surfaceHeight - 1 - y)
    }

    @inline(__always) private static func trilinear(_ c: [(Float, Float, Float)], _ tx: Float, _ ty: Float, _ tz: Float) -> (Float, Float, Float) {
        func lerp3(_ p: (Float, Float, Float), _ q: (Float, Float, Float), _ t: Float) -> (Float, Float, Float) {
            (p.0 + (q.0 - p.0) * t, p.1 + (q.1 - p.1) * t, p.2 + (q.2 - p.2) * t)
        }
        let x00 = lerp3(c[0], c[1], tx), x10 = lerp3(c[2], c[3], tx)
        let x01 = lerp3(c[4], c[5], tx), x11 = lerp3(c[6], c[7], tx)
        let y0 = lerp3(x00, x10, ty), y1 = lerp3(x01, x11, ty)
        return lerp3(y0, y1, tz)
    }

    // MARK: - Chunk generation

    public func generate(_ pos: ChunkPos) -> Chunk {
        let chunk = Chunk(pos: pos)
        let ox = Int(pos.originX), oz = Int(pos.originZ)
        let sea = WorldConst.seaLevel

        var columns = [ColumnInfo]()
        columns.reserveCapacity(256)
        var maxH = sea
        for z in 0..<16 {
            for x in 0..<16 {
                let info = columnInfo(x: ox + x, z: oz + z)
                columns.append(info)
                maxH = max(maxH, info.height)
            }
        }

        // Cave lattice covering this chunk: 5 × ny × 5 samples at stride 4.
        let s = TerrainGenerator.caveStride
        let ny = maxH / s + 2
        var lattice = [(Float, Float, Float)](repeating: (0, 0, 0), count: 25 * ny)
        for ly in 0..<ny {
            for lz in 0..<5 {
                for lx in 0..<5 {
                    lattice[(ly * 5 + lz) * 5 + lx] = caveSample(ox + lx * s, ly * s, oz + lz * s)
                }
            }
        }

        for z in 0..<16 {
            for x in 0..<16 {
                let info = columns[z * 16 + x]
                fillColumn(chunk, x: x, z: z, info: info, worldX: ox + x, worldZ: oz + z, lattice: lattice, latticeHeight: ny)
            }
        }

        placeOres(chunk)
        placeTrees(chunk)
        placeVillages(chunk)
        placeStructures(chunk)
        placeDetails(chunk, columns: columns)
        placePlants(chunk, columns: columns)
        chunk.recomputeHeights()
        return chunk
    }

    private func fillColumn(_ chunk: Chunk, x: Int, z: Int, info: ColumnInfo, worldX: Int, worldZ: Int,
                            lattice: [(Float, Float, Float)], latticeHeight ny: Int) {
        let sea = WorldConst.seaLevel
        let h = info.height
        let underwater = h < sea
        let (top, filler, fillerDepth, deepFiller) = surfaceBlocks(info, worldX: worldX, worldZ: worldZ)

        for y in 0..<h {
            var id: BlockID
            if y == 0 {
                id = Blocks.bedrock
            } else if y <= 4 && Hashing.unit(seed, Int32(worldX), Int32(y), Int32(worldZ), salt: 5) < Float(5 - y) / 5 {
                id = Blocks.bedrock
            } else if y == h - 1 {
                id = top
            } else if y >= h - 1 - fillerDepth {
                id = filler
            } else if y >= h - 1 - fillerDepth - 3, let deep = deepFiller {
                id = deep
            } else {
                id = Blocks.stone
            }
            if info.biome == .redMesa && y < h - 1 && y >= h - 18 && id != Blocks.bedrock {
                id = mesaBand(y, worldX: worldX, worldZ: worldZ)
            }

            // Caves: never breach the sea floor or river beds.
            if y > 4 && id != Blocks.bedrock && !(underwater && y >= h - 6) && !(h <= sea + 2 && y >= sea - 3) {
                let s = TerrainGenerator.caveStride
                let lx = x / s, ly = y / s, lz = z / s
                if ly + 1 < ny {
                    let tx = Float(x - lx * s) / Float(s), ty = Float(y - ly * s) / Float(s), tz = Float(z - lz * s) / Float(s)
                    var corners = [(Float, Float, Float)](repeating: (0, 0, 0), count: 8)
                    for i in 0..<8 {
                        corners[i] = lattice[((ly + ((i >> 1) & 1)) * 5 + (lz + ((i >> 2) & 1))) * 5 + (lx + (i & 1))]
                    }
                    let v = TerrainGenerator.trilinear(corners, tx, ty, tz)
                    if TerrainGenerator.isCave(a: v.0, b: v.1, c: v.2, y: y, depthBelowSurface: h - 1 - y) {
                        id = Blocks.air
                    }
                }
            }
            chunk.setRaw(x, y, z, id)
        }

        if underwater {
            let frozen = info.temperature < -0.55 && info.biome != .river
            for y in h..<sea {
                chunk.setRaw(x, y, z, (frozen && y == sea - 1) ? Blocks.ice : Blocks.water)
            }
        }
    }

    private static let mesaBands: [BlockID] = [Blocks.terracotta, Blocks.dyedClay[3], Blocks.redRock, Blocks.dyedClay[4], Blocks.terracotta,
                                               Blocks.dyedClay[0], Blocks.redRock, Blocks.dyedClay[2], Blocks.terracotta, Blocks.redRock]

    /// Horizontal clay stripes of the Red Mesa, gently offset so they wander across the cliffs.
    private func mesaBand(_ y: Int, worldX: Int, worldZ: Int) -> BlockID {
        let wobble = Int(Hashing.hash(seed, Int32(worldX >> 5), 0, Int32(worldZ >> 5), salt: 44) % 2)
        return TerrainGenerator.mesaBands[(y + wobble) % TerrainGenerator.mesaBands.count]
    }

    /// (top block, filler block, filler depth, optional deeper layer)
    private func surfaceBlocks(_ info: ColumnInfo, worldX: Int, worldZ: Int) -> (BlockID, BlockID, Int, BlockID?) {
        let sea = WorldConst.seaLevel
        let jitter = Int(Hashing.hash(seed, Int32(worldX), 0, Int32(worldZ), salt: 9) % 2)
        switch info.biome {
        case .ocean, .river:
            let depth = sea - info.height
            if info.detail > 0.35 { return (Blocks.clay, Blocks.clay, 2, nil) }
            if depth > 9 || info.detail < -0.3 { return (Blocks.gravel, Blocks.gravel, 2, nil) }
            return (Blocks.sand, Blocks.sand, 3, nil)
        case .beach:
            if info.temperature < -0.4 { return (Blocks.gravel, Blocks.gravel, 3, nil) }
            return (Blocks.sand, Blocks.sand, 3 + jitter, Blocks.sandstone)
        case .desert:
            return (Blocks.sand, Blocks.sand, 3 + jitter, info.detail > 0.05 ? Blocks.redRock : Blocks.sandstone)
        case .snowyPeaks:
            return (Blocks.snow, info.detail > 0.2 ? Blocks.snow : Blocks.stone, 1, nil)
        case .mountains:
            if info.detail > 0.25 { return (Blocks.stone, Blocks.stone, 1, nil) }
            if info.detail < -0.35 { return (Blocks.gravel, Blocks.stone, 1, nil) }
            return (Blocks.grass, Blocks.dirt, 2, nil)
        case .snowyTundra:
            return (Blocks.snowyGrass, Blocks.dirt, 3 + jitter, nil)
        case .redwoodTaiga:
            return (info.temperature < -0.4 ? Blocks.snowyGrass : Blocks.grass, Blocks.dirt, 3 + jitter, nil)
        case .swamp:
            if info.detail > 0.15 { return (Blocks.mud, Blocks.mud, 3, Blocks.clay) }
            if info.detail > -0.05 { return (Blocks.mossBlock, Blocks.dirt, 3, nil) }
            return (Blocks.grass, Blocks.dirt, 3, nil)
        case .fernJungle where info.detail > 0.4:
            return (Blocks.mossBlock, Blocks.dirt, 3 + jitter, nil)
        case .redMesa:
            return (info.detail > 0.3 ? Blocks.terracotta : Blocks.redRock, Blocks.redRock, 2, Blocks.terracotta)
        case .volcanicWastes:
            if info.detail > 0.45 { return (Blocks.magmaRock, Blocks.basalt, 3, Blocks.obsidian) }
            return (info.detail > 0 ? Blocks.basalt : Blocks.ash, Blocks.basalt, 3 + jitter, nil)
        case .glacier:
            return (info.detail > 0.25 ? Blocks.snow : Blocks.packedIce, Blocks.packedIce, 4 + jitter, Blocks.ice)
        case .fungalMarsh:
            return (info.detail > 0.1 ? Blocks.mud : Blocks.mossBlock, Blocks.dirt, 3, Blocks.clay)
        case .savanna, .blossomGrove, .silverForest, .flowerMeadow:
            return (Blocks.grass, Blocks.dirt, 3 + jitter, nil)
        case .plains, .forest, .fernJungle, .underworld, .skylands, .toonland:
            return (Blocks.grass, Blocks.dirt, 3 + jitter, nil)
        }
    }

    // MARK: - Ores

    private struct OreSpec {
        let block: BlockID; let attempts: Int; let minY: Int; let maxY: Int; let size: Int
    }

    private static let ores: [OreSpec] = [
        OreSpec(block: Blocks.coalOre, attempts: 18, minY: 6, maxY: 130, size: 9),
        OreSpec(block: Blocks.ironOre, attempts: 12, minY: 6, maxY: 68, size: 7),
        OreSpec(block: Blocks.fossilStone, attempts: 3, minY: 28, maxY: 72, size: 5),
        OreSpec(block: Blocks.amberOre, attempts: 3, minY: 16, maxY: 58, size: 4),
        OreSpec(block: Blocks.goldOre, attempts: 3, minY: 6, maxY: 34, size: 6),
        OreSpec(block: Blocks.diamondOre, attempts: 2, minY: 5, maxY: 17, size: 5),
        OreSpec(block: Blocks.gravel, attempts: 6, minY: 6, maxY: 90, size: 20),
        OreSpec(block: Blocks.emeraldOre, attempts: 4, minY: 40, maxY: 150, size: 3),
        OreSpec(block: Blocks.marble, attempts: 2, minY: 10, maxY: 100, size: 36),
        OreSpec(block: Blocks.slate, attempts: 3, minY: 5, maxY: 60, size: 40),
    ]

    private func placeOres(_ chunk: Chunk) {
        var rng = SplitMix64(seed: Hashing.hash(seed, chunk.pos.x, 0, chunk.pos.z, salt: 77))
        for ore in TerrainGenerator.ores {
            for _ in 0..<ore.attempts {
                var x = rng.nextInt(16), z = rng.nextInt(16)
                var y = ore.minY + rng.nextInt(ore.maxY - ore.minY)
                let count = ore.size / 2 + rng.nextInt(ore.size / 2 + 1)
                for _ in 0..<count {
                    if chunk.block(x, y, z) == Blocks.stone { chunk.setRaw(x, y, z, ore.block) }
                    switch rng.nextInt(3) {
                    case 0: x = max(0, min(15, x + (rng.nextInt(2) == 0 ? -1 : 1)))
                    case 1: y = max(1, min(WorldConst.height - 1, y + (rng.nextInt(2) == 0 ? -1 : 1)))
                    default: z = max(0, min(15, z + (rng.nextInt(2) == 0 ? -1 : 1)))
                    }
                }
            }
        }
    }

    // MARK: - Trees

    private enum TreeKind { case ginkgo, tallGinkgo, redwood, swampGinkgo, palm, deadTree, bush, blossom, silver, acacia, giantMushroom }

    private func treeKind(for biome: Biome, roll: Float) -> TreeKind? {
        switch biome {
        case .forest: return roll < 0.62 ? .ginkgo : (roll < 0.7 ? .bush : nil)
        case .plains: return roll < 0.05 ? .ginkgo : (roll < 0.11 ? .bush : nil)
        case .beach: return roll < 0.09 ? .palm : nil
        case .desert: return roll < 0.018 ? .deadTree : nil
        case .fernJungle: return roll < 0.8 ? (roll < 0.35 ? .tallGinkgo : .ginkgo) : nil
        case .redwoodTaiga: return roll < 0.6 ? .redwood : nil
        case .snowyTundra: return roll < 0.05 ? .redwood : nil
        case .mountains: return roll < 0.07 ? .redwood : nil
        case .swamp: return roll < 0.3 ? .swampGinkgo : nil
        case .blossomGrove: return roll < 0.38 ? .blossom : (roll < 0.43 ? .bush : nil)
        case .silverForest: return roll < 0.55 ? .silver : (roll < 0.6 ? .bush : nil)
        case .savanna: return roll < 0.07 ? .acacia : (roll < 0.1 ? .bush : nil)
        case .fungalMarsh: return roll < 0.14 ? .giantMushroom : nil
        case .flowerMeadow: return roll < 0.015 ? .blossom : nil
        case .redMesa, .volcanicWastes: return roll < 0.012 ? .deadTree : nil
        default: return nil
        }
    }

    private func placeTrees(_ chunk: Chunk) {
        let cell = TerrainGenerator.treeCell
        let margin = TerrainGenerator.treeMargin
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        let minCX = Int(floor(Double(ox - margin) / Double(cell)))
        let maxCX = Int(floor(Double(ox + 15 + margin) / Double(cell)))
        let minCZ = Int(floor(Double(oz - margin) / Double(cell)))
        let maxCZ = Int(floor(Double(oz + 15 + margin) / Double(cell)))

        for cz in minCZ...maxCZ {
            for cx in minCX...maxCX {
                let h = Hashing.hash(seed, Int32(cx), 0, Int32(cz), salt: 101)
                let roll = Float(h >> 40) / 16_777_216
                let wx = cx * cell + Int((h >> 8) % UInt64(cell))
                let wz = cz * cell + Int((h >> 16) % UInt64(cell))
                guard abs(wx - (ox + 8)) <= 8 + margin, abs(wz - (oz + 8)) <= 8 + margin else { continue }
                // Cheap rejection before evaluating the column.
                guard roll < 0.8 else { continue }
                let info = columnInfo(x: wx, z: wz)
                guard info.height > WorldConst.seaLevel, let kind = treeKind(for: info.biome, roll: roll) else { continue }
                let (top, _, _, _) = surfaceBlocks(info, worldX: wx, worldZ: wz)
                guard top == Blocks.grass || top == Blocks.snowyGrass || top == Blocks.mud || top == Blocks.mossBlock
                        || ((kind == .palm || kind == .deadTree) && top == Blocks.sand)
                        || (kind == .deadTree && [Blocks.redRock, Blocks.terracotta, Blocks.ash, Blocks.basalt].contains(top)) else { continue }
                if isCarved(x: wx, y: info.height - 1, z: wz, surfaceHeight: info.height) { continue }
                var rng = SplitMix64(seed: h)
                buildTree(kind, chunk: chunk, baseX: wx - ox, baseY: info.height, baseZ: wz - oz, rng: &rng)
            }
        }
    }

    @inline(__always) private func put(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, _ id: BlockID, overwrite: Bool) {
        guard x >= 0, x < 16, z >= 0, z < 16, y > 0, y < WorldConst.height else { return }
        let cur = chunk.block(x, y, z)
        if overwrite {
            if cur == Blocks.air || cur == Blocks.leaves || cur == Blocks.redwoodNeedles || cur == Blocks.pinkLeaves || cur == Blocks.silverLeaves || cur == Blocks.tallGrass || cur == Blocks.fern {
                chunk.setRaw(x, y, z, id)
            }
        } else if cur == Blocks.air {
            chunk.setRaw(x, y, z, id)
        }
    }

    private func buildTree(_ kind: TreeKind, chunk: Chunk, baseX bx: Int, baseY by: Int, baseZ bz: Int, rng: inout SplitMix64) {
        switch kind {
        case .ginkgo, .swampGinkgo, .tallGinkgo:
            let trunk: Int
            switch kind {
            case .tallGinkgo: trunk = 9 + rng.nextInt(5)
            case .swampGinkgo: trunk = 4 + rng.nextInt(2)
            default: trunk = 5 + rng.nextInt(3)
            }
            let radius = kind == .tallGinkgo ? 4 : (kind == .swampGinkgo ? 3 : 2)
            let topY = by + trunk
            // Fan-shaped canopy: wide in the middle, tapering to the crown.
            for dy in -3...1 {
                let r: Int
                switch dy {
                case 1: r = 1
                case 0: r = radius - 1
                case -1, -2: r = radius
                default: r = kind == .swampGinkgo ? radius : radius - 1
                }
                for dz in -r...r {
                    for dx in -r...r {
                        let d2 = dx * dx + dz * dz
                        if d2 > r * r + 1 { continue }
                        if d2 >= r * r && rng.nextInt(3) == 0 { continue }
                        put(chunk, bx + dx, topY + dy, bz + dz, Blocks.leaves, overwrite: false)
                    }
                }
            }
            if kind == .swampGinkgo {
                // Drooping leaf curtains
                for _ in 0..<6 {
                    let dx = rng.nextInt(radius * 2 + 1) - radius, dz = rng.nextInt(radius * 2 + 1) - radius
                    for d in 1...(1 + rng.nextInt(3)) { put(chunk, bx + dx, topY - 3 - d, bz + dz, Blocks.leaves, overwrite: false) }
                }
            }
            for y in by..<topY { put(chunk, bx, y, bz, Blocks.log, overwrite: true) }

        case .palm:
            let trunk = 5 + rng.nextInt(4)
            let lean = rng.nextInt(2) == 0 ? 1 : -1
            let alongX = rng.nextInt(2) == 0
            var tx = bx, tz = bz
            for i in 0..<trunk {
                if i == trunk / 2 || i == trunk - 2 {
                    if alongX { tx += lean } else { tz += lean }
                }
                put(chunk, tx, by + i, tz, Blocks.palmLog, overwrite: true)
            }
            let crown = by + trunk
            put(chunk, tx, crown, tz, Blocks.palmFronds, overwrite: false)
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)] {
                let reach = abs(dx) + abs(dz) == 2 ? 2 : 3
                for step in 1...reach {
                    put(chunk, tx + dx * step, crown - (step == reach ? 1 : 0), tz + dz * step, Blocks.palmFronds, overwrite: false)
                }
            }

        case .deadTree:
            let trunk = 3 + rng.nextInt(3)
            for i in 0..<trunk { put(chunk, bx, by + i, bz, Blocks.log, overwrite: true) }
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where rng.nextInt(3) == 0 {
                put(chunk, bx + dx, by + trunk - 1 - rng.nextInt(2), bz + dz, Blocks.log, overwrite: true)
            }

        case .bush:
            put(chunk, bx, by, bz, Blocks.log, overwrite: true)
            for dy in 0...1 {
                for dz in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dz == 0 && dy == 0) {
                        if dy == 1 && abs(dx) + abs(dz) == 2 && rng.nextInt(2) == 0 { continue }
                        put(chunk, bx + dx, by + dy, bz + dz, Blocks.leaves, overwrite: false)
                    }
                }
            }

        case .blossom:
            let trunk = 4 + rng.nextInt(3)
            let topY = by + trunk
            for dy in -2...1 {
                let r = dy == 1 ? 1 : (dy == -2 ? 2 : 3)
                for dz in -r...r {
                    for dx in -r...r {
                        let d2 = dx * dx + dz * dz
                        if d2 > r * r + 1 || (d2 >= r * r && rng.nextInt(3) == 0) { continue }
                        put(chunk, bx + dx, topY + dy, bz + dz, Blocks.pinkLeaves, overwrite: false)
                    }
                }
            }
            for _ in 0..<5 {
                put(chunk, bx + rng.nextInt(7) - 3, topY - 3, bz + rng.nextInt(7) - 3, Blocks.pinkLeaves, overwrite: false)
            }
            for y in by..<topY { put(chunk, bx, y, bz, Blocks.log, overwrite: true) }

        case .silver:
            let trunk = 6 + rng.nextInt(4)
            let topY = by + trunk
            for dy in -4...1 {
                let r = dy >= 0 ? 1 : 2
                for dz in -r...r {
                    for dx in -r...r where !(abs(dx) == r && abs(dz) == r && rng.nextInt(2) == 0) {
                        put(chunk, bx + dx, topY + dy, bz + dz, Blocks.silverLeaves, overwrite: false)
                    }
                }
            }
            for y in by..<topY { put(chunk, bx, y, bz, Blocks.silverLog, overwrite: true) }

        case .acacia:
            let straight = 3 + rng.nextInt(2)
            let dir = [(1, 0), (-1, 0), (0, 1), (0, -1)][rng.nextInt(4)]
            var tx = bx, tz = bz, ty = by
            for _ in 0..<straight { put(chunk, tx, ty, tz, Blocks.log, overwrite: true); ty += 1 }
            for _ in 0..<2 { tx += dir.0; tz += dir.1; put(chunk, tx, ty, tz, Blocks.log, overwrite: true); ty += 1 }
            for dz in -3...3 {
                for dx in -3...3 where abs(dx) + abs(dz) <= 4 { put(chunk, tx + dx, ty, tz + dz, Blocks.leaves, overwrite: false) }
            }
            for dz in -1...1 { for dx in -1...1 { put(chunk, tx + dx, ty + 1, tz + dz, Blocks.leaves, overwrite: false) } }

        case .giantMushroom:
            let stem = 4 + rng.nextInt(3)
            let topY = by + stem
            for y in by..<topY { put(chunk, bx, y, bz, Blocks.mushroomStem, overwrite: true) }
            for dz in -3...3 {
                for dx in -3...3 {
                    let d2 = dx * dx + dz * dz
                    if d2 <= 5 { put(chunk, bx + dx, topY, bz + dz, Blocks.mushroomCap, overwrite: false) }
                    else if d2 <= 10 { put(chunk, bx + dx, topY - 1, bz + dz, Blocks.mushroomCap, overwrite: false) }
                }
            }
            put(chunk, bx, topY + 1, bz, Blocks.mushroomCap, overwrite: false)

        case .redwood:
            let trunk = 11 + rng.nextInt(8)
            let topY = by + trunk
            let foliageStart = by + 3 + rng.nextInt(2)
            var layer = 0
            var y = topY + 1
            while y >= foliageStart {
                let r = min(3, 1 + (layer % 3) + layer / 6)
                let rr = y > topY - 1 ? 0 : r
                for dz in -rr...rr {
                    for dx in -rr...rr where abs(dx) + abs(dz) <= rr + (rr > 1 ? 1 : 0) {
                        put(chunk, bx + dx, y, bz + dz, Blocks.redwoodNeedles, overwrite: false)
                    }
                }
                layer += 1
                y -= 1
            }
            for y in by..<topY { put(chunk, bx, y, bz, Blocks.redwoodLog, overwrite: true) }
        }
    }

    // MARK: - Details

    private static let detailCell = 14

    /// Boulders, fallen logs, ice spikes and desert fossils on a jittered grid, plus cave decorations.
    private func placeDetails(_ chunk: Chunk, columns: [ColumnInfo]) {
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        let cell = TerrainGenerator.detailCell
        let margin = 5
        let cz0 = Int(floor(Double(oz - margin) / Double(cell))), cz1 = Int(floor(Double(oz + 15 + margin) / Double(cell)))
        let cx0 = Int(floor(Double(ox - margin) / Double(cell))), cx1 = Int(floor(Double(ox + 15 + margin) / Double(cell)))
        for cz in cz0...cz1 {
            for cx in cx0...cx1 {
                let h = Hashing.hash(seed, Int32(cx), 3, Int32(cz), salt: 909)
                let roll = Float(h >> 40) / 16_777_216
                guard roll < 0.2 else { continue }
                let wx = cx * cell + Int((h >> 8) % UInt64(cell)), wz = cz * cell + Int((h >> 16) % UInt64(cell))
                guard abs(wx - (ox + 8)) <= 8 + margin, abs(wz - (oz + 8)) <= 8 + margin else { continue }
                let info = columnInfo(x: wx, z: wz)
                guard info.height > WorldConst.seaLevel + 1 else { continue }
                if isCarved(x: wx, y: info.height - 1, z: wz, surfaceHeight: info.height) { continue }
                guard villages(near: wx, z: wz, radius: 10).isEmpty,
                      !structures(near: wx, z: wz, radius: 8).contains(where: { $0.kind != .dungeon }) else { continue }
                var rng = SplitMix64(seed: h)
                let biome = info.biome
                if biome == .snowyTundra && roll < 0.08 {
                    iceSpike(chunk, wx - ox, info.height, wz - oz, rng: &rng)
                } else if biome == .desert && roll < 0.05 {
                    fossil(chunk, wx: wx, wz: wz, ox: ox, oz: oz, rng: &rng)
                } else if roll < 0.09 && [.plains, .forest, .redwoodTaiga, .mountains, .snowyTundra, .fernJungle, .savanna, .flowerMeadow, .silverForest].contains(biome) {
                    boulder(chunk, wx - ox, info.height, wz - oz, mossy: biome == .forest || biome == .fernJungle || biome == .redwoodTaiga, rng: &rng)
                } else if roll < 0.18 && [.forest, .redwoodTaiga, .fernJungle, .silverForest, .blossomGrove].contains(biome) {
                    let log = biome == .redwoodTaiga ? Blocks.redwoodLog : (biome == .silverForest ? Blocks.silverLog : Blocks.log)
                    fallenLog(chunk, wx: wx, wz: wz, ox: ox, oz: oz, log: log, rng: &rng)
                } else if biome == .volcanicWastes && roll < 0.1 {
                    lavaPool(chunk, wx - ox, info.height, wz - oz, rng: &rng)
                } else if biome == .volcanicWastes {
                    spire(chunk, wx - ox, info.height, wz - oz, block: Blocks.basalt, rng: &rng)
                } else if biome == .glacier && roll < 0.14 {
                    iceSpike(chunk, wx - ox, info.height, wz - oz, rng: &rng)
                } else if biome == .redMesa && roll < 0.1 {
                    spire(chunk, wx - ox, info.height, wz - oz, block: Blocks.redRock, rng: &rng)
                }
            }
        }

        // Caves: stalagmites and glowing mushrooms on the floor.
        var rng = SplitMix64(seed: Hashing.hash(seed, chunk.pos.x, 5, chunk.pos.z, salt: 919))
        for _ in 0..<18 {
            let x = rng.nextInt(16), z = rng.nextInt(16)
            let roofLimit = min(64, columns[z * 16 + x].height - 8)
            let pickY = rng.nextInt(64), glow = rng.nextInt(10) < 4
            guard roofLimit > 12 else { continue }
            var y = 8 + pickY % (roofLimit - 7)
            guard chunk.block(x, y, z) == Blocks.air else { continue }
            var steps = 0
            while y > 2 && chunk.block(x, y - 1, z) == Blocks.air && steps < 12 { y -= 1; steps += 1 }
            let floor = chunk.block(x, y - 1, z)
            guard floor == Blocks.stone || floor == Blocks.slate || floor == Blocks.marble || floor == Blocks.gravel else { continue }
            chunk.setRaw(x, y, z, glow && y < 48 ? Blocks.glowMushroom : Blocks.stalagmite)
        }
    }

    private func boulder(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, mossy: Bool, rng: inout SplitMix64) {
        let r = 1 + rng.nextInt(2)
        for dy in -1...r {
            for dz in -r...r {
                for dx in -r...r {
                    let variant = rng.nextInt(6)
                    guard dx * dx + dy * dy * 2 + dz * dz <= r * r + 1 else { continue }
                    let id = mossy && variant < 2 ? Blocks.mossyCobblestone : (variant == 5 ? Blocks.gravel : Blocks.cobblestone)
                    put(chunk, x + dx, y + dy, z + dz, id, overwrite: true)
                }
            }
        }
    }

    private func fallenLog(_ chunk: Chunk, wx: Int, wz: Int, ox: Int, oz: Int, log: BlockID, rng: inout SplitMix64) {
        let length = 3 + rng.nextInt(3)
        let alongX = rng.nextInt(2) == 0
        let mushrooms = rng.next()
        let base = columnInfo(x: wx, z: wz).height
        for i in 0..<length {
            let x = wx + (alongX ? i : 0), z = wz + (alongX ? 0 : i)
            guard x - ox >= 0, x - ox < 16, z - oz >= 0, z - oz < 16 else { continue }
            let h = columnInfo(x: x, z: z).height
            guard abs(h - base) <= 1 else { continue }
            put(chunk, x - ox, h, z - oz, log, overwrite: true)
            if (mushrooms >> UInt64(i * 3)) & 3 == 0 { put(chunk, x - ox, h + 1, z - oz, Blocks.brownMushroom, overwrite: false) }
        }
    }

    private func iceSpike(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, rng: inout SplitMix64) {
        let height = 4 + rng.nextInt(7)
        for dy in 0..<height {
            put(chunk, x, y + dy, z, Blocks.packedIce, overwrite: true)
            if dy < height / 3 {
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] { put(chunk, x + dx, y + dy, z + dz, Blocks.packedIce, overwrite: true) }
            }
        }
    }

    @inline(__always) private func force(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        guard x >= 0, x < 16, z >= 0, z < 16, y > 0, y < WorldConst.height else { return }
        chunk.setRaw(x, y, z, id)
    }

    /// A small glowing lava pool sunk into basalt, rimmed with magma rock.
    private func lavaPool(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, rng: inout SplitMix64) {
        let r = 1 + rng.nextInt(2)
        for dz in -(r + 1)...(r + 1) {
            for dx in -(r + 1)...(r + 1) {
                let d2 = dx * dx + dz * dz
                if d2 <= r * r {
                    force(chunk, x + dx, y, z + dz, Blocks.air)
                    force(chunk, x + dx, y - 1, z + dz, Blocks.lava)
                    force(chunk, x + dx, y - 2, z + dz, Blocks.basalt)
                } else if d2 <= (r + 1) * (r + 1) {
                    force(chunk, x + dx, y - 1, z + dz, Blocks.magmaRock)
                }
            }
        }
    }

    /// A rock pillar with a wider base (basalt in the Volcanic Wastes, red rock in the Mesa).
    private func spire(_ chunk: Chunk, _ x: Int, _ y: Int, _ z: Int, block: BlockID, rng: inout SplitMix64) {
        let height = 3 + rng.nextInt(7)
        for dy in 0..<height {
            put(chunk, x, y + dy, z, block, overwrite: true)
            if dy < 2 {
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where rng.nextInt(3) > 0 { put(chunk, x + dx, y + dy, z + dz, block, overwrite: true) }
            }
        }
    }

    /// A dinosaur skeleton half-buried in the sand: spine, rib arches and a fossil skull.
    private func fossil(_ chunk: Chunk, wx: Int, wz: Int, ox: Int, oz: Int, rng: inout SplitMix64) {
        let alongX = rng.nextInt(2) == 0
        let y = columnInfo(x: wx, z: wz).height
        for i in 0..<7 {
            let x = wx + (alongX ? i : 0) - ox, z = wz + (alongX ? 0 : i) - oz
            put(chunk, x, y + 2, z, Blocks.boneBlock, overwrite: true)
            if i % 2 == 1 && i < 6 {
                for side in [-1, 1] {
                    let rx = x + (alongX ? 0 : side), rz = z + (alongX ? side : 0)
                    put(chunk, rx, y, rz, Blocks.boneBlock, overwrite: true)
                    put(chunk, rx, y + 1, rz, Blocks.boneBlock, overwrite: true)
                }
            }
        }
        put(chunk, wx + (alongX ? -1 : 0) - ox, y + 2, wz + (alongX ? 0 : -1) - oz, Blocks.fossilStone, overwrite: true)
    }

    // MARK: - Plants

    private static func pick(_ r: Float, _ table: [(Float, BlockID)]) -> BlockID? {
        for (limit, id) in table where r < limit { return id }
        return nil
    }

    private static let plainsPlants: [(Float, BlockID)] = [(0.009, Blocks.emberbloom), (0.018, Blocks.sunpetal), (0.026, Blocks.whiteDaisy),
        (0.032, Blocks.blueBloom), (0.036, Blocks.berryBush), (0.04, Blocks.pebbles), (0.22, Blocks.tallGrass)]
    private static let forestPlants: [(Float, BlockID)] = [(0.01, Blocks.sunpetal), (0.018, Blocks.blueBloom), (0.024, Blocks.pinkPetal),
        (0.03, Blocks.redMushroom), (0.036, Blocks.brownMushroom), (0.044, Blocks.berryBush), (0.08, Blocks.fern), (0.18, Blocks.tallGrass)]
    private static let junglePlants: [(Float, BlockID)] = [(0.3, Blocks.fern), (0.42, Blocks.tallGrass), (0.43, Blocks.emberbloom),
        (0.44, Blocks.pinkPetal), (0.445, Blocks.redMushroom)]
    private static let taigaPlants: [(Float, BlockID)] = [(0.08, Blocks.fern), (0.1, Blocks.brownMushroom), (0.112, Blocks.berryBush),
        (0.116, Blocks.pebbles), (0.14, Blocks.tallGrass)]
    private static let swampPlants: [(Float, BlockID)] = [(0.05, Blocks.fern), (0.065, Blocks.brownMushroom), (0.075, Blocks.redMushroom),
        (0.1, Blocks.horsetail), (0.22, Blocks.tallGrass)]
    private static let mountainPlants: [(Float, BlockID)] = [(0.06, Blocks.tallGrass), (0.066, Blocks.whiteDaisy), (0.08, Blocks.pebbles)]

    private static let meadowPlants: [(Float, BlockID)] = [(0.07, Blocks.emberbloom), (0.14, Blocks.sunpetal), (0.21, Blocks.whiteDaisy),
        (0.28, Blocks.blueBloom), (0.35, Blocks.pinkPetal), (0.55, Blocks.tallGrass)]
    private static let blossomPlants: [(Float, BlockID)] = [(0.09, Blocks.pinkPetal), (0.11, Blocks.whiteDaisy), (0.13, Blocks.berryBush), (0.3, Blocks.tallGrass)]
    private static let silverPlants: [(Float, BlockID)] = [(0.02, Blocks.whiteDaisy), (0.03, Blocks.blueBloom), (0.05, Blocks.brownMushroom),
        (0.12, Blocks.fern), (0.28, Blocks.tallGrass)]
    private static let savannaPlants: [(Float, BlockID)] = [(0.16, Blocks.dryGrass), (0.3, Blocks.tallGrass), (0.305, Blocks.berryBush), (0.31, Blocks.pebbles)]
    private static let fungalPlants: [(Float, BlockID)] = [(0.05, Blocks.redMushroom), (0.1, Blocks.brownMushroom), (0.12, Blocks.glowMushroom),
        (0.16, Blocks.horsetail)]

    private func placePlants(_ chunk: Chunk, columns: [ColumnInfo]) {
        let ox = Int(chunk.pos.originX), oz = Int(chunk.pos.originZ)
        let sea = WorldConst.seaLevel
        for z in 0..<16 {
            for x in 0..<16 {
                let info = columns[z * 16 + x]
                let y = info.height
                let r = Float(Hashing.unit(seed, Int32(ox + x), Int32(y), Int32(oz + z), salt: 202))
                // Lily pads float on shallow, calm water.
                if y < sea {
                    if y >= sea - 3 && (info.biome == .swamp || info.biome == .river) && r < 0.07
                        && chunk.block(x, sea - 1, z) == Blocks.water && chunk.block(x, sea, z) == Blocks.air {
                        chunk.setRaw(x, sea, z, Blocks.lilyPad)
                    }
                    continue
                }
                guard y > sea, y < WorldConst.height - 3 else { continue }
                let ground = chunk.block(x, y - 1, z)
                guard chunk.block(x, y, z) == Blocks.air else { continue }

                // Reeds along the water's edge.
                if y <= sea + 2 && r < 0.3 && [Blocks.grass, Blocks.sand, Blocks.dirt, Blocks.mud, Blocks.mossBlock].contains(ground) {
                    var wet = false
                    for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, nz = z + dz
                        if nx >= 0, nx < 16, nz >= 0, nz < 16, chunk.block(nx, y - 1, nz) == Blocks.water { wet = true }
                    }
                    if wet {
                        chunk.setRaw(x, y, z, r < 0.15 ? Blocks.cattail : Blocks.horsetail)
                        continue
                    }
                }

                var plant: BlockID?
                if ground == Blocks.grass || ground == Blocks.mossBlock {
                    switch info.biome {
                    case .plains: plant = TerrainGenerator.pick(r, TerrainGenerator.plainsPlants)
                    case .forest: plant = TerrainGenerator.pick(r, TerrainGenerator.forestPlants)
                    case .fernJungle: plant = TerrainGenerator.pick(r, TerrainGenerator.junglePlants)
                    case .redwoodTaiga: plant = TerrainGenerator.pick(r, TerrainGenerator.taigaPlants)
                    case .swamp: plant = TerrainGenerator.pick(r, TerrainGenerator.swampPlants)
                    case .mountains: plant = TerrainGenerator.pick(r, TerrainGenerator.mountainPlants)
                    case .flowerMeadow: plant = TerrainGenerator.pick(r, TerrainGenerator.meadowPlants)
                    case .blossomGrove: plant = TerrainGenerator.pick(r, TerrainGenerator.blossomPlants)
                    case .silverForest: plant = TerrainGenerator.pick(r, TerrainGenerator.silverPlants)
                    case .savanna: plant = TerrainGenerator.pick(r, TerrainGenerator.savannaPlants)
                    case .fungalMarsh: plant = TerrainGenerator.pick(r, TerrainGenerator.fungalPlants)
                    default: plant = r < 0.08 ? Blocks.tallGrass : (r < 0.085 ? Blocks.pebbles : nil)
                    }
                } else if ground == Blocks.sand && info.biome == .desert {
                    if r < 0.012 {
                        plant = Blocks.deadBush
                    } else if r < 0.03 {
                        plant = Blocks.dryGrass
                    } else if r < 0.036 {
                        let height = 1 + Int(r * 1000) % 3
                        for i in 0..<height where chunk.block(x, y + i, z) == Blocks.air { chunk.setRaw(x, y + i, z, Blocks.cactus) }
                    }
                } else if (ground == Blocks.redRock || ground == Blocks.terracotta) && info.biome == .redMesa {
                    plant = r < 0.02 ? Blocks.deadBush : (r < 0.05 ? Blocks.dryGrass : nil)
                } else if ground == Blocks.mud && info.biome == .fungalMarsh {
                    plant = TerrainGenerator.pick(r, TerrainGenerator.fungalPlants)
                } else if (ground == Blocks.ash || ground == Blocks.basalt) && info.biome == .volcanicWastes {
                    plant = r < 0.004 ? Blocks.emberCrystal : nil
                } else if ground == Blocks.sand && info.biome == .beach {
                    plant = r < 0.02 ? Blocks.pebbles : nil
                } else if ground == Blocks.snowyGrass {
                    plant = r < 0.03 ? Blocks.tallGrass : nil
                } else if ground == Blocks.stone || ground == Blocks.gravel {
                    plant = r < 0.03 ? Blocks.pebbles : nil
                }
                if let plant { chunk.setRaw(x, y, z, plant) }
            }
        }
    }

    // MARK: - Spawn

    /// Finds a pleasant dry-land column near the origin (spiral search).
    /// Returns world x/z of the column; the world resolves the exact y after
    /// the chunk is generated.
    public func findSpawnColumn() -> (x: Int, z: Int) {
        let good: Set<Biome> = [.plains, .forest, .fernJungle, .redwoodTaiga, .swamp, .desert, .snowyTundra, .savanna, .flowerMeadow, .blossomGrove, .silverForest]
        var fallback: (Int, Int)? = nil
        for ring in 0..<64 {
            let r = ring * 24
            let steps = max(1, ring * 8)
            for i in 0..<steps {
                let angle = Double(i) / Double(steps) * 2 * .pi
                let x = Int((cos(angle) * Double(r)).rounded()), z = Int((sin(angle) * Double(r)).rounded())
                let info = columnInfo(x: x, z: z)
                guard info.height > WorldConst.seaLevel + 1, info.height < WorldConst.seaLevel + 40 else { continue }
                if isCarved(x: x, y: info.height - 1, z: z, surfaceHeight: info.height) { continue }
                if good.contains(info.biome) { return (x, z) }
                if fallback == nil { fallback = (x, z) }
            }
        }
        return fallback ?? (0, 0)
    }
}
