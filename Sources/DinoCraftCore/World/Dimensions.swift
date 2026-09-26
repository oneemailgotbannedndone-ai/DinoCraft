import Foundation

public enum WorldDimension: String, Codable, CaseIterable, Sendable {
    case overworld, underworld, skylands, toonland

    public var displayName: String {
        switch self {
        case .overworld: return "Overworld"
        case .underworld: return "The Underworld"
        case .skylands: return "Amber Skylands"
        case .toonland: return "Toonland"
        }
    }

    /// Save folder for this dimension's chunks inside the world directory (nil = legacy root).
    public var storageFolder: String? { self == .overworld ? nil : "dim_\(rawValue)" }

    /// Horizontal distance scale relative to the overworld (1 underworld block = 8 overworld blocks).
    public var coordinateScale: Double { self == .underworld ? 8 : 1 }

    /// Whether this dimension has a sky and a day/night cycle.
    public var hasSky: Bool { self != .underworld }

    /// Frame material and portal block for gateways leading from the overworld here.
    public var frameBlock: BlockID? {
        switch self {
        case .overworld: return nil
        case .underworld: return Blocks.boneBlock
        case .skylands: return Blocks.amberBlock
        case .toonland: return Blocks.checkerBlock
        }
    }

    public var portalBlock: BlockID? {
        switch self {
        case .overworld: return nil
        case .underworld: return Blocks.underworldPortal
        case .skylands: return Blocks.skylandsPortal
        case .toonland: return Blocks.toonlandPortal
        }
    }

    /// Where a gateway of `portal` type leads when used from this dimension.
    public func destination(through portal: BlockID) -> WorldDimension {
        guard self == .overworld else { return .overworld }
        return WorldDimension.forPortal(portal) ?? .skylands
    }

    public static func forPortal(_ id: BlockID) -> WorldDimension? {
        allCases.first { $0.portalBlock == id }
    }

    /// Every gateway block, and the frame block each one is built from.
    public static var gateways: [(portal: BlockID, frame: BlockID)] {
        allCases.compactMap { d in d.portalBlock.flatMap { p in d.frameBlock.map { (p, $0) } } }
    }

    /// `deep`: overworlds made since the deep update go down to Y -70 (older worlds keep their old floor).
    public func makeGenerator(seed: UInt64, deep: Bool = true) -> WorldGenerator {
        switch self {
        case .overworld: return TerrainGenerator(seed: seed, deep: deep)
        case .underworld: return UnderworldGenerator(seed: Hashing.hash(seed, 0, 0, 0, salt: 0xDEAD))
        case .skylands: return SkylandsGenerator(seed: Hashing.hash(seed, 0, 0, 0, salt: 0xA3BE))
        case .toonland: return ToonlandGenerator(seed: Hashing.hash(seed, 0, 0, 0, salt: 0x7005))
        }
    }
}

/// A deterministic, thread-safe chunk source for one dimension.
public protocol WorldGenerator: AnyObject, Sendable {
    var seed: UInt64 { get }
    var dimension: WorldDimension { get }
    func generate(_ pos: ChunkPos) -> Chunk
    /// A column near the origin that is good for spawning.
    func findSpawnColumn() -> (x: Int, z: Int)
    func biome(x: Int, z: Int) -> Biome
    /// Rough standing height used before chunks exist (players are placed precisely later).
    func estimatedSurface(x: Int, z: Int) -> Int
    /// Sea level, for underground checks and cave spawning.
    var seaLevel: Int { get }
    /// How far below 0 the world goes: shown Y = stored Y - `depthOffset` (70 in deep overworlds).
    var depthOffset: Int { get }
}

extension WorldGenerator {
    public var seaLevel: Int { TerrainGenerator.baseSeaLevel }
    public var depthOffset: Int { 0 }
}

extension TerrainGenerator: WorldGenerator {
    public var dimension: WorldDimension { .overworld }
    public var depthOffset: Int { depth }
    public func biome(x: Int, z: Int) -> Biome { columnInfo(x: x, z: z).biome }
    public func estimatedSurface(x: Int, z: Int) -> Int { columnInfo(x: x, z: z).height }
}

/// Shared helpers for noise-lattice terrain.
enum LatticeSampler {
    /// Trilinearly samples a lattice laid out `(ly * 5 + lz) * 5 + lx` with stride 4.
    @inline(__always) static func sample(_ lattice: [Float], _ x: Int, _ y: Int, _ z: Int, yOffset: Int = 0) -> Float {
        let ly = (y - yOffset) >> 2, lx = x >> 2, lz = z >> 2
        let tx = Float(x & 3) / 4, ty = Float((y - yOffset) & 3) / 4, tz = Float(z & 3) / 4
        @inline(__always) func v(_ dx: Int, _ dy: Int, _ dz: Int) -> Float { lattice[((ly + dy) * 5 + lz + dz) * 5 + lx + dx] }
        let x00 = v(0, 0, 0) + (v(1, 0, 0) - v(0, 0, 0)) * tx
        let x10 = v(0, 1, 0) + (v(1, 1, 0) - v(0, 1, 0)) * tx
        let x01 = v(0, 0, 1) + (v(1, 0, 1) - v(0, 0, 1)) * tx
        let x11 = v(0, 1, 1) + (v(1, 1, 1) - v(0, 1, 1)) * tx
        let y0 = x00 + (x10 - x00) * ty, y1 = x01 + (x11 - x01) * ty
        return y0 + (y1 - y0) * tz
    }

    static func vein(_ chunk: Chunk, _ rng: inout SplitMix64, block: BlockID, replace: BlockID, attempts: Int,
                     minY: Int, maxY: Int, size: Int) {
        for _ in 0..<attempts {
            var x = rng.nextInt(16), z = rng.nextInt(16), y = minY + rng.nextInt(max(1, maxY - minY))
            for _ in 0..<(size / 2 + rng.nextInt(size / 2 + 1)) {
                if chunk.block(x, y, z) == replace { chunk.setRaw(x, y, z, block) }
                switch rng.nextInt(3) {
                case 0: x = max(0, min(15, x + (rng.nextInt(2) == 0 ? -1 : 1)))
                case 1: y = max(1, min(WorldConst.height - 2, y + (rng.nextInt(2) == 0 ? -1 : 1)))
                default: z = max(0, min(15, z + (rng.nextInt(2) == 0 ? -1 : 1)))
                }
            }
        }
    }
}

// MARK: - Underworld

/// A sealed volcanic cavern world: bedrock floor and ceiling, huge basalt
/// caverns and pillars, a lava sea, ash dunes, magma veins and hanging ember crystals.
public final class UnderworldGenerator: WorldGenerator, @unchecked Sendable {
    public let seed: UInt64
    public var dimension: WorldDimension { .underworld }
    public static let ceiling = 127
    public static let lavaLevel = 31

    private let density: SimplexNoise
    private let detail: SimplexNoise
    private let ashNoise: SimplexNoise

    public init(seed: UInt64) {
        self.seed = seed
        density = SimplexNoise(seed: Hashing.hash(seed, 1, 0, 0, salt: 601))
        detail = SimplexNoise(seed: Hashing.hash(seed, 2, 0, 0, salt: 602))
        ashNoise = SimplexNoise(seed: Hashing.hash(seed, 3, 0, 0, salt: 603))
    }

    @inline(__always) func field(_ x: Int, _ y: Int, _ z: Int) -> Float {
        let fx = Double(x), fy = Double(y), fz = Double(z)
        let n = density.fbm3(fx / 70, fy / 40, fz / 70, octaves: 3)
        let vertical = Double(abs(y - 68)) / 58
        let pillars = max(0, detail.noise2(fx / 34, fz / 34) - 0.45) * 2.2
        return Float(n * 1.15 + pow(vertical, 3) * 1.7 + pillars - 0.08)
    }

    public func generate(_ pos: ChunkPos) -> Chunk {
        let chunk = Chunk(pos: pos)
        let ox = Int(pos.originX), oz = Int(pos.originZ)
        let levels = 34
        var lattice = [Float](repeating: 0, count: 25 * levels)
        for ly in 0..<levels {
            for lz in 0..<5 {
                for lx in 0..<5 { lattice[(ly * 5 + lz) * 5 + lx] = field(ox + lx * 4, ly * 4, oz + lz * 4) }
            }
        }
        let top = UnderworldGenerator.ceiling
        for z in 0..<16 {
            for x in 0..<16 {
                let wx = Int32(ox + x), wz = Int32(oz + z)
                for y in 0...top {
                    var id: BlockID
                    if y == 0 || y == top {
                        id = Blocks.bedrock
                    } else if y <= 3 && Hashing.unit(seed, wx, Int32(y), wz, salt: 3) < Float(4 - y) / 4 {
                        id = Blocks.bedrock
                    } else if y >= top - 4 && Hashing.unit(seed, wx, Int32(y), wz, salt: 4) < Float(y - (top - 5)) / 5 {
                        id = Blocks.bedrock
                    } else if LatticeSampler.sample(lattice, x, y, z) > 0.12 {
                        id = Blocks.basalt
                    } else {
                        id = y <= UnderworldGenerator.lavaLevel ? Blocks.lava : Blocks.air
                    }
                    chunk.setRaw(x, y, z, id)
                }
            }
        }

        // Surface dressing
        for z in 0..<16 {
            for x in 0..<16 {
                let wx = Int32(ox + x), wz = Int32(oz + z)
                let ash = ashNoise.noise2(Double(wx) / 26, Double(wz) / 26)
                for y in 2..<(top - 1) where chunk.block(x, y, z) == Blocks.basalt {
                    let above = chunk.block(x, y + 1, z), below = chunk.block(x, y - 1, z)
                    let r = Hashing.unit(seed, wx, Int32(y), wz, salt: 21)
                    if above == Blocks.lava || (above == Blocks.air && y <= UnderworldGenerator.lavaLevel + 1) {
                        if r < 0.3 { chunk.setRaw(x, y, z, Blocks.obsidian) } else if r < 0.6 { chunk.setRaw(x, y, z, Blocks.magmaRock) }
                    } else if above == Blocks.air {
                        if ash > 0.2 {
                            chunk.setRaw(x, y, z, Blocks.ash)
                            if chunk.block(x, y - 1, z) == Blocks.basalt { chunk.setRaw(x, y - 1, z, Blocks.ash) }
                        } else if r < 0.06 {
                            chunk.setRaw(x, y, z, Blocks.magmaRock)
                        }
                    }
                    if below == Blocks.air && y > UnderworldGenerator.lavaLevel + 6 && r > 0.965 {
                        chunk.setRaw(x, y - 1, z, Blocks.emberCrystal)
                    }
                }
            }
        }

        var rng = SplitMix64(seed: Hashing.hash(seed, pos.x, 9, pos.z, salt: 911))
        LatticeSampler.vein(chunk, &rng, block: Blocks.magmaRock, replace: Blocks.basalt, attempts: 10, minY: 5, maxY: 120, size: 12)
        LatticeSampler.vein(chunk, &rng, block: Blocks.goldOre, replace: Blocks.basalt, attempts: 8, minY: 10, maxY: 118, size: 7)
        LatticeSampler.vein(chunk, &rng, block: Blocks.amberOre, replace: Blocks.basalt, attempts: 5, minY: 10, maxY: 118, size: 5)
        LatticeSampler.vein(chunk, &rng, block: Blocks.fossilStone, replace: Blocks.basalt, attempts: 5, minY: 10, maxY: 118, size: 6)
        LatticeSampler.vein(chunk, &rng, block: Blocks.diamondOre, replace: Blocks.basalt, attempts: 1, minY: 5, maxY: 40, size: 4)
        chunk.recomputeHeights()
        return chunk
    }

    public func findSpawnColumn() -> (x: Int, z: Int) {
        for ring in 0..<40 {
            let r = ring * 12
            let steps = max(1, ring * 8)
            for i in 0..<steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let x = Int((cos(a) * Double(r)).rounded()), z = Int((sin(a) * Double(r)).rounded())
                if estimatedSurface(x: x, z: z) > 0 { return (x, z) }
            }
        }
        return (0, 0)
    }

    public func biome(x: Int, z: Int) -> Biome { .underworld }

    /// First open standing spot scanning down from the middle of the cavern (0 if none).
    public func estimatedSurface(x: Int, z: Int) -> Int {
        var y = 100
        while y > UnderworldGenerator.lavaLevel + 2 {
            if field(x, y - 1, z) > 0.12 && field(x, y, z) <= 0.12 && field(x, y + 1, z) <= 0.12 { return y }
            y -= 1
        }
        return 0
    }
}

// MARK: - Skylands

/// Floating islands of skygrass and stone drifting above a sea of walkable
/// clouds, dotted with glowing skyblooms, amber deposits and small ginkgo groves.
public final class SkylandsGenerator: WorldGenerator, @unchecked Sendable {
    public let seed: UInt64
    public var dimension: WorldDimension { .skylands }
    public static let minY = 36
    public static let maxY = 172
    public static let cloudLevel = 44

    private let islands: SimplexNoise
    private let shape: SimplexNoise
    private let clouds: SimplexNoise
    private let heightNoise: SimplexNoise

    public init(seed: UInt64) {
        self.seed = seed
        islands = SimplexNoise(seed: Hashing.hash(seed, 1, 0, 0, salt: 701))
        shape = SimplexNoise(seed: Hashing.hash(seed, 2, 0, 0, salt: 702))
        clouds = SimplexNoise(seed: Hashing.hash(seed, 3, 0, 0, salt: 703))
        heightNoise = SimplexNoise(seed: Hashing.hash(seed, 4, 0, 0, salt: 704))
    }

    @inline(__always) func field(_ x: Int, _ y: Int, _ z: Int) -> Float {
        let fx = Double(x), fy = Double(y), fz = Double(z)
        let mask = islands.fbm2(fx / 240, fz / 240, octaves: 4) * 1.6
        let center = 104 + heightNoise.noise2(fx / 380, fz / 380) * 28
        let top = 8 + max(0, mask + 0.3) * 26
        let bottom = 14 + max(0, mask + 0.3) * 60
        let dy = fy - center
        let falloff = dy > 0 ? dy / top : -dy / bottom
        let n = shape.fbm3(fx / 46, fy / 30, fz / 46, octaves: 3)
        return Float(mask * 1.4 + n * 0.5 - falloff * falloff * 0.8 + 0.1)
    }

    public func generate(_ pos: ChunkPos) -> Chunk {
        let chunk = Chunk(pos: pos)
        let ox = Int(pos.originX), oz = Int(pos.originZ)
        let base = SkylandsGenerator.minY
        let levels = (SkylandsGenerator.maxY - base) / 4 + 2
        var lattice = [Float](repeating: 0, count: 25 * levels)
        for ly in 0..<levels {
            for lz in 0..<5 {
                for lx in 0..<5 { lattice[(ly * 5 + lz) * 5 + lx] = field(ox + lx * 4, base + ly * 4, oz + lz * 4) }
            }
        }
        for z in 0..<16 {
            for x in 0..<16 {
                for y in base..<SkylandsGenerator.maxY where LatticeSampler.sample(lattice, x, y, z, yOffset: base) > 0.3 {
                    chunk.setRaw(x, y, z, Blocks.stone)
                }
                // Cloud sea
                let wx = Double(ox + x), wz = Double(oz + z)
                let c = clouds.fbm2(wx / 64, wz / 64, octaves: 3)
                if c > 0.12 { chunk.setRaw(x, SkylandsGenerator.cloudLevel, z, Blocks.cloud) }
                if c > 0.28 { chunk.setRaw(x, SkylandsGenerator.cloudLevel + 1, z, Blocks.cloud) }
            }
        }
        // Surfaces
        for z in 0..<16 {
            for x in 0..<16 {
                let wx = Int32(ox + x), wz = Int32(oz + z)
                var y = SkylandsGenerator.maxY - 1
                while y > base {
                    if chunk.block(x, y, z) == Blocks.stone && chunk.block(x, y + 1, z) == Blocks.air {
                        chunk.setRaw(x, y, z, Blocks.skyGrass)
                        for d in 1...3 where chunk.block(x, y - d, z) == Blocks.stone { chunk.setRaw(x, y - d, z, Blocks.skySoil) }
                        let r = Hashing.unit(seed, wx, Int32(y), wz, salt: 31)
                        if r < 0.04 { chunk.setRaw(x, y + 1, z, Blocks.skybloom) }
                        else if r < 0.16 { chunk.setRaw(x, y + 1, z, Blocks.tallGrass) }
                        y -= 4
                        continue
                    }
                    y -= 1
                }
            }
        }
        // Small ginkgo groves kept inside the chunk so chunks stay independent
        var rng = SplitMix64(seed: Hashing.hash(seed, pos.x, 3, pos.z, salt: 777))
        for _ in 0..<3 {
            let x = 3 + rng.nextInt(10), z = 3 + rng.nextInt(10)
            guard rng.nextInt(3) == 0, chunk.maxHeight > 0 else { continue }
            var y = SkylandsGenerator.maxY - 2
            while y > base && chunk.block(x, y, z) != Blocks.skyGrass { y -= 1 }
            guard y > base, chunk.block(x, y + 1, z) != Blocks.cloud else { continue }
            let trunk = 4 + rng.nextInt(2)
            for dy in 1...trunk { chunk.setRaw(x, y + dy, z, Blocks.log) }
            let top = y + trunk
            for dy in -2...1 {
                let r = dy == 1 ? 1 : 2
                for dz in -r...r {
                    for dx in -r...r where dx * dx + dz * dz <= r * r + 1 {
                        if chunk.block(x + dx, top + dy, z + dz) == Blocks.air { chunk.setRaw(x + dx, top + dy, z + dz, Blocks.leaves) }
                    }
                }
            }
        }
        LatticeSampler.vein(chunk, &rng, block: Blocks.amberOre, replace: Blocks.stone, attempts: 6, minY: base, maxY: 150, size: 6)
        LatticeSampler.vein(chunk, &rng, block: Blocks.amberBlock, replace: Blocks.stone, attempts: 1, minY: base, maxY: 150, size: 5)
        LatticeSampler.vein(chunk, &rng, block: Blocks.goldOre, replace: Blocks.stone, attempts: 4, minY: base, maxY: 150, size: 6)
        LatticeSampler.vein(chunk, &rng, block: Blocks.diamondOre, replace: Blocks.stone, attempts: 2, minY: base, maxY: 150, size: 4)
        chunk.recomputeHeights()
        return chunk
    }

    public func findSpawnColumn() -> (x: Int, z: Int) {
        for ring in 0..<60 {
            let r = ring * 16
            let steps = max(1, ring * 8)
            for i in 0..<steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let x = Int((cos(a) * Double(r)).rounded()), z = Int((sin(a) * Double(r)).rounded())
                if estimatedSurface(x: x, z: z) > 0 { return (x, z) }
            }
        }
        return (0, 0)
    }

    public func biome(x: Int, z: Int) -> Biome { .skylands }

    public func estimatedSurface(x: Int, z: Int) -> Int {
        var y = SkylandsGenerator.maxY - 2
        while y > SkylandsGenerator.minY + 4 {
            if field(x, y - 1, z) > 0.3 && field(x, y, z) <= 0.3 { return y }
            y -= 1
        }
        return 0
    }
}
