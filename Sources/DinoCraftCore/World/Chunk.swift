import Foundation

public enum WorldConst {
    public static let chunkSize = 16
    /// Layers of deep slate under the old bedrock: the bottom of the world is Y -70.
    public static let deepLayers = 70
    public static let height = 256 + deepLayers
    /// Sea level in new (deep) overworlds. Worlds from before the deep update keep theirs at 62
    /// (see `WorldGenerator.seaLevel`).
    public static let seaLevel = 62 + deepLayers
    public static let blocksPerChunk = chunkSize * chunkSize * height
}

/// A 16 × 326 × 16 column of blocks.
///
/// Storage is a single contiguous byte buffer indexed as `y << 8 | z << 4 | x`.
/// Chunks are mutated only on the main (game) thread; background meshing jobs
/// retain the chunk and read it concurrently. Byte-sized reads are benign on
/// ARM64, and every mutation bumps `version`, which invalidates any mesh built
/// from stale data so it is rebuilt on the next pass.
public final class Chunk: @unchecked Sendable {
    public let pos: ChunkPos
    public let blocks: UnsafeMutablePointer<BlockID>
    /// Per-column height of the highest non-air block + 1 (0 for empty columns).
    public let heightMap: UnsafeMutablePointer<UInt16>
    /// Highest non-air y + 1 in the whole chunk; bounds meshing and lighting.
    public private(set) var maxHeight: Int = 0

    /// Incremented on every block change.
    public private(set) var version: UInt64 = 1
    /// True when blocks differ from what is saved on disk.
    public var needsSave = false
    /// True once the player (or anything but the generator) changed this chunk.
    public var isModified = false

    public init(pos: ChunkPos) {
        self.pos = pos
        blocks = .allocate(capacity: WorldConst.blocksPerChunk)
        blocks.initialize(repeating: Blocks.air, count: WorldConst.blocksPerChunk)
        heightMap = .allocate(capacity: 256)
        heightMap.initialize(repeating: 0, count: 256)
    }

    deinit {
        blocks.deallocate()
        heightMap.deallocate()
    }

    @inline(__always) public static func index(_ x: Int, _ y: Int, _ z: Int) -> Int { (y << 8) | (z << 4) | x }

    /// Local coordinates (0..<16, 0..<256, 0..<16). Out-of-range y reads return air.
    @inline(__always) public func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID {
        guard y >= 0 && y < WorldConst.height else { return Blocks.air }
        return blocks[Chunk.index(x, y, z)]
    }

    /// Generator-side write (no version bump / heightmap maintenance).
    @inline(__always) public func setRaw(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        blocks[Chunk.index(x, y, z)] = id
    }

    /// Gameplay write: updates heightmap and marks the chunk dirty.
    public func set(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        guard y >= 0 && y < WorldConst.height else { return }
        let i = Chunk.index(x, y, z)
        guard blocks[i] != id else { return }
        blocks[i] = id
        version &+= 1
        needsSave = true
        isModified = true
        let col = (z << 4) | x
        let h = Int(heightMap[col])
        if id != Blocks.air {
            if y + 1 > h { heightMap[col] = UInt16(y + 1) }
            if y + 1 > maxHeight { maxHeight = y + 1 }
        } else if y + 1 == h {
            var ny = y
            while ny > 0 && blocks[Chunk.index(x, ny - 1, z)] == Blocks.air { ny -= 1 }
            heightMap[col] = UInt16(ny)
        }
    }

    /// Rebuilds the heightmap and max height from block data (after generation or load).
    public func recomputeHeights() {
        var maxH = 0
        for z in 0..<16 {
            for x in 0..<16 {
                var y = WorldConst.height - 1
                while y >= 0 && blocks[Chunk.index(x, y, z)] == Blocks.air { y -= 1 }
                heightMap[(z << 4) | x] = UInt16(y + 1)
                maxH = max(maxH, y + 1)
            }
        }
        maxHeight = maxH
    }

    public func markVersionChanged() { version &+= 1 }

    // MARK: Serialization

    private static let magic: UInt32 = 0x4843_4344   // "DCCH"
    /// 2 = portable run-length codec (every platform). 1 = LZFSE, still readable on Apple platforms.
    private static let formatVersion: UInt16 = 2

    public enum ChunkIOError: Error, CustomStringConvertible {
        case badHeader, badVersion(UInt16), wrongPosition, sizeMismatch, compressionFailed
        public var description: String {
            switch self {
            case .badHeader: return "chunk file has an invalid header"
            case .badVersion(let v): return "chunk file format version \(v) is not supported"
            case .wrongPosition: return "chunk file position does not match its name"
            case .sizeMismatch: return "chunk file block data has the wrong size"
            case .compressionFailed: return "chunk data could not be (de)compressed"
            }
        }
    }

    /// Serializes blocks with the portable run-length codec, so saves and multiplayer
    /// chunks work the same on macOS and Windows.
    public func serialize() throws -> Data {
        let compressed = BlockRLE.encode(UnsafeBufferPointer(start: blocks, count: WorldConst.blocksPerChunk))
        var out = Data(capacity: compressed.count + 16)
        withUnsafeBytes(of: Chunk.magic.littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: Chunk.formatVersion.littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt16(0)) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: pos.x.littleEndian) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: pos.z.littleEndian) { out.append(contentsOf: $0) }
        out.append(compressed)
        return out
    }

    public static func deserialize(_ data: Data, expected: ChunkPos) throws -> Chunk {
        guard data.count > 16 else { throw ChunkIOError.badHeader }
        func read<T: FixedWidthInteger>(_ offset: Int, _: T.Type) -> T {
            data.withUnsafeBytes { T(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: T.self)) }
        }
        guard read(0, UInt32.self) == magic else { throw ChunkIOError.badHeader }
        let version = read(4, UInt16.self)
        guard read(8, Int32.self) == expected.x, read(12, Int32.self) == expected.z else { throw ChunkIOError.wrongPosition }
        let payload = data.subdata(in: 16..<data.count)
        let chunk = Chunk(pos: expected)
        switch version {
        case 2:
            guard let written = BlockRLE.decode(payload, into: chunk.blocks, capacity: WorldConst.blocksPerChunk) else {
                throw ChunkIOError.compressionFailed
            }
            // Chunks saved before the deep update are 256 blocks tall; the extra layers above them stay air.
            guard written == WorldConst.blocksPerChunk || written == 256 * 256 else { throw ChunkIOError.sizeMismatch }
        #if canImport(Darwin)
        case 1:
            let raw: NSData
            do { raw = try (payload as NSData).decompressed(using: .lzfse) } catch { throw ChunkIOError.compressionFailed }
            guard raw.length == WorldConst.blocksPerChunk || raw.length == 256 * 256 else { throw ChunkIOError.sizeMismatch }
            raw.getBytes(chunk.blocks, length: raw.length)
        #endif
        default:
            throw ChunkIOError.badVersion(version)
        }
        chunk.recomputeHeights()
        chunk.isModified = true
        return chunk
    }
}
