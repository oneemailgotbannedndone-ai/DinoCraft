import Foundation

/// GPU vertex for chunk geometry (18 bytes). Layout is mirrored by the Metal
/// vertex descriptor in `ChunkRenderer`.
///
/// Positions are chunk-local in 1/16-block fixed point so a single UInt16
/// covers the full 256-block world height with sub-block precision (torches,
/// plants, lowered water surfaces). UVs are in 1/16-block units and tile across
/// greedy-merged quads via a repeating sampler on a texture array.
public struct ChunkVertex: Sendable {
    public var x: UInt16, y: UInt16, z: UInt16
    public var layer: UInt16
    public var u: UInt16, v: UInt16
    public var normal: UInt8     // BlockFace raw value, 6 = omnidirectional (plants)
    public var ao: UInt8         // 0 (fully occluded) ... 3 (open)
    public var sky: UInt8        // smoothed sky light 0...255
    public var light: UInt8      // smoothed block light 0...255
    public var flags: UInt8
    public var pad: UInt8 = 0
}

public enum VertexFlags {
    public static let waving: UInt8 = 1
    public static let liquid: UInt8 = 2
    public static let rawUV: UInt8 = 4
    public static let wavingTop: UInt8 = 8
    public static let emissive: UInt8 = 16
    /// Leaves, grass and plants: tinted with the season (and dusted with snow on top in winter).
    public static let seasonal: UInt8 = 32
}

public final class MeshBuffers {
    public var opaque: [ChunkVertex] = []
    public var cutout: [ChunkVertex] = []
    public var translucent: [ChunkVertex] = []

    public init() {
        opaque.reserveCapacity(16_384)
        cutout.reserveCapacity(4_096)
        translucent.reserveCapacity(4_096)
    }

    public func reset() {
        opaque.removeAll(keepingCapacity: true)
        cutout.removeAll(keepingCapacity: true)
        translucent.removeAll(keepingCapacity: true)
    }

    public var isEmpty: Bool { opaque.isEmpty && cutout.isEmpty && translucent.isEmpty }
    public var quadCount: Int { (opaque.count + cutout.count + translucent.count) / 4 }
}

/// Builds lighting and a greedy-merged mesh for one chunk.
///
/// Each job copies the 3 × 3 chunk neighbourhood into a padded 48 × H × 48
/// scratch volume, computes sky and block light by flood fill inside that
/// volume (light never travels more than 15 blocks, so the padding fully
/// covers everything that can affect the centre chunk), then meshes only the
/// centre chunk with smooth lighting and ambient occlusion. Faces are merged
/// greedily when their texture, flags and all four corner light/AO values
/// match, which collapses large uniformly-lit surfaces into a handful of quads.
///
/// A mesher owns large scratch buffers and is **not** thread-safe: the engine
/// keeps one per worker thread.
public final class ChunkMesher {
    public static let regionSize = 48
    private let R = ChunkMesher.regionSize
    private let registry: BlockRegistry

    private let ids: UnsafeMutablePointer<BlockID>
    private let sky: UnsafeMutablePointer<UInt8>
    private let blk: UnsafeMutablePointer<UInt8>
    private var queue: UnsafeMutablePointer<Int32>
    private var queueCapacity: Int
    private let fullTop: UnsafeMutablePointer<Int16>
    private let litBottom: UnsafeMutablePointer<Int16>
    private let maskKey: UnsafeMutablePointer<UInt32>
    private let maskLight: UnsafeMutablePointer<UInt64>

    // Flat per-block tables copied out of the registry for tight loops.
    private let opaqueTable: UnsafeMutablePointer<Bool>
    private let filterTable: UnsafeMutablePointer<UInt8>
    private let emissionTable: UnsafeMutablePointer<UInt8>
    private let shapeTable: UnsafeMutablePointer<UInt8>   // 0 none, 1 cube, 2 cross, 3 torch, 4 liquid
    private let layerTable: UnsafeMutablePointer<UInt8>   // 0 opaque, 1 cutout, 2 translucent, 3 invisible
    private let wavingTable: UnsafeMutablePointer<Bool>
    private let seasonalTable: UnsafeMutablePointer<UInt8>
    private let leafLike: UnsafeMutablePointer<Bool>
    private let boxTable: [[BlockBox]]
    private let facingTable: [Int8]
    private var faceLayers: [UInt16]
    /// Double chest halves: front, back (side) and top/bottom textures.
    private var chestHalfLayers: (front: UInt16, side: UInt16, top: UInt16) = (0, 0, 0)
    /// Plants growing under water: their cell also holds water.
    private let submergedTable: [Bool]
    /// Per-position texture choices (coral colours), by id.
    private var variantLayers: [[UInt16]]
    /// World position of the centre chunk's corner, for per-position variants.
    private var originX = 0, originZ = 0

    private var H = 0

    public let out = MeshBuffers()
    public var fancyLeaves = true
    public private(set) var lastLightingSeconds: Double = 0
    public private(set) var lastMeshSeconds: Double = 0

    private static let emptyKey: UInt32 = 0xFFFF_FFFF

    public init(registry: BlockRegistry) {
        self.registry = registry
        let volume = R * R * WorldConst.height
        ids = .allocate(capacity: volume)
        sky = .allocate(capacity: volume)
        blk = .allocate(capacity: volume)
        queueCapacity = 1 << 16
        queue = .allocate(capacity: queueCapacity)
        fullTop = .allocate(capacity: R * R)
        litBottom = .allocate(capacity: R * R)
        maskKey = .allocate(capacity: 16 * WorldConst.height)
        maskLight = .allocate(capacity: 16 * WorldConst.height)

        opaqueTable = .allocate(capacity: BlockRegistry.capacity)
        filterTable = .allocate(capacity: BlockRegistry.capacity)
        emissionTable = .allocate(capacity: BlockRegistry.capacity)
        shapeTable = .allocate(capacity: BlockRegistry.capacity)
        layerTable = .allocate(capacity: BlockRegistry.capacity)
        wavingTable = .allocate(capacity: BlockRegistry.capacity)
        seasonalTable = .allocate(capacity: BlockRegistry.capacity)
        leafLike = .allocate(capacity: BlockRegistry.capacity)
        boxTable = registry.shapeBoxes
        submergedTable = registry.isSubmerged
        variantLayers = registry.variantLayers
        facingTable = registry.facingIndex
        for i in 0..<BlockRegistry.capacity {
            let info = registry.blocks[i]
            opaqueTable[i] = registry.isOpaque[i]
            filterTable[i] = registry.lightFilter[i]
            emissionTable[i] = registry.emission[i]
            switch registry.shape[i] {
            case .none: shapeTable[i] = 0
            case .cube: shapeTable[i] = 1
            case .cross: shapeTable[i] = 2
            case .torch: shapeTable[i] = 3
            case .liquid: shapeTable[i] = 4
            case .box: shapeTable[i] = 5
            case .wallTorch: shapeTable[i] = 6
            }
            switch registry.layer[i] {
            case .opaque: layerTable[i] = 0
            case .cutout: layerTable[i] = 1
            case .translucent: layerTable[i] = 2
            case .invisible: layerTable[i] = 3
            }
            wavingTable[i] = info?.waving ?? false
            seasonalTable[i] = info?.seasonal ?? 0
            leafLike[i] = (info?.waving ?? false) && registry.shape[i] == .cube
        }
        faceLayers = registry.faceLayers
        refreshChestLayers()
    }

    /// The texture layer of a face, picking a variant by position for blocks that have them.
    /// `patch` groups neighbouring blocks into same-coloured clumps.
    @inline(__always) private func faceLayer(_ id: Int, _ face: Int, _ x: Int, _ y: Int, _ z: Int, patch: Int = 0) -> UInt16 {
        let variants = variantLayers[id]
        if variants.isEmpty { return faceLayers[id * 6 + face] }
        let wx = (originX + x) >> patch, wy = y >> patch, wz = (originZ + z) >> patch
        var h = UInt32(truncatingIfNeeded: wx &* 73_856_093 ^ wy &* 19_349_663 ^ wz &* 83_492_791)
        h ^= h >> 13; h = h &* 0x5bd1e995; h ^= h >> 15
        return variants[Int(h % UInt32(variants.count))]
    }

    /// Water, or a plant growing in it (for water that meets another water cell).
    @inline(__always) private func waterMeets(_ id: Int, _ nb: Int) -> Bool {
        nb == id || (id == Int(Blocks.water) && submergedTable[nb])
    }

    private func refreshChestLayers() {
        let l = registry.extraLayers
        chestHalfLayers = (l["chest_front_half"] ?? 0, l["chest_side_half"] ?? 0, l["chest_top_half"] ?? 0)
    }

    deinit {
        ids.deallocate(); sky.deallocate(); blk.deallocate(); queue.deallocate()
        fullTop.deallocate(); litBottom.deallocate(); maskKey.deallocate(); maskLight.deallocate()
        opaqueTable.deallocate(); filterTable.deallocate(); emissionTable.deallocate()
        shapeTable.deallocate(); layerTable.deallocate(); wavingTable.deallocate(); leafLike.deallocate()
        seasonalTable.deallocate()
    }

    /// Refreshes texture layer bindings (call after the atlas is rebuilt).
    public func refreshTextureLayers() {
        faceLayers = registry.faceLayers
        variantLayers = registry.variantLayers
        refreshChestLayers()
    }

    @inline(__always) private func ri(_ x: Int, _ y: Int, _ z: Int) -> Int { (y * R + z) * R + x }

    // MARK: - Entry point

    /// Builds the mesh for `neighborhood[4]`. `neighborhood` holds the 3 × 3 chunks
    /// ordered `(dz + 1) * 3 + (dx + 1)`. Results are left in `out`.
    public func build(neighborhood: [Chunk]) {
        precondition(neighborhood.count == 9, "mesher requires a full 3x3 neighbourhood")
        out.reset()
        let t0 = Date.timeIntervalSinceReferenceDate
        let center = neighborhood[4]
        originX = Int(center.pos.x) * 16
        originZ = Int(center.pos.z) * 16
        var top = 1
        for c in neighborhood { top = max(top, c.maxHeight) }
        H = min(WorldConst.height, top + 1)

        copyRegion(neighborhood)
        computeSkyLight()
        computeBlockLight()
        let t1 = Date.timeIntervalSinceReferenceDate

        let hc = min(WorldConst.height, center.maxHeight)
        if hc > 0 {
            for face in 0..<6 { greedyFaces(face: face, centerHeight: hc) }
            specialShapes(centerHeight: hc)
        }
        let t2 = Date.timeIntervalSinceReferenceDate
        lastLightingSeconds = t1 - t0
        lastMeshSeconds = t2 - t1
    }

    /// Packed light (`sky << 4 | block`) of the centre chunk from the last `build`,
    /// indexed `(y * 16 + z) * 16 + x`, covering `0..<height`. Above `height`
    /// everything is open sky.
    public func centerLight() -> (data: [UInt8], height: Int) {
        var out = [UInt8](repeating: 0, count: 256 * H)
        out.withUnsafeMutableBufferPointer { dst in
            for y in 0..<H {
                for z in 0..<16 {
                    for x in 0..<16 {
                        let i = ri(x + 16, y, z + 16)
                        dst[(y * 16 + z) * 16 + x] = (sky[i] << 4) | blk[i]
                    }
                }
            }
        }
        return (out, H)
    }

    // MARK: - Region copy

    private func copyRegion(_ chunks: [Chunk]) {
        for dz in 0..<3 {
            for dx in 0..<3 {
                let chunk = chunks[dz * 3 + dx]
                let limit = min(H, chunk.maxHeight)
                for y in 0..<H {
                    for z in 0..<16 {
                        let dst = ids + ri(dx * 16, y, dz * 16 + z)
                        if y < limit {
                            dst.update(from: chunk.blocks + Chunk.index(0, y, z), count: 16)
                        } else {
                            dst.update(repeating: 0, count: 16)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Lighting

    @inline(__always) private func push(_ i: Int, _ tail: inout Int, _ head: inout Int) {
        if tail == queueCapacity {
            let live = tail - head
            if head > queueCapacity / 2 {
                (queue).update(from: queue + head, count: live)
            } else {
                let bigger = UnsafeMutablePointer<Int32>.allocate(capacity: queueCapacity * 2)
                bigger.update(from: queue + head, count: live)
                queue.deallocate()
                queue = bigger
                queueCapacity *= 2
            }
            head = 0
            tail = live
        }
        queue[tail] = Int32(i)
        tail += 1
    }

    private func computeSkyLight() {
        let volume = R * R * H
        sky.update(repeating: 0, count: volume)
        for z in 0..<R {
            for x in 0..<R {
                var level = 15
                var y = H - 1
                var full = H
                var lowest = H
                while y >= 0 {
                    let f = Int(filterTable[Int(ids[ri(x, y, z)])])
                    if f > 0 {
                        level -= f
                        if level <= 0 { break }
                    }
                    if level == 15 { full = y }
                    sky[ri(x, y, z)] = UInt8(level)
                    lowest = y
                    y -= 1
                }
                fullTop[z * R + x] = Int16(full)
                litBottom[z * R + x] = Int16(lowest)
            }
        }

        var head = 0, tail = 0
        for z in 0..<R {
            for x in 0..<R {
                let c = z * R + x
                var neighborFull = Int(fullTop[c])
                if x > 0 { neighborFull = max(neighborFull, Int(fullTop[c - 1])) }
                if x < R - 1 { neighborFull = max(neighborFull, Int(fullTop[c + 1])) }
                if z > 0 { neighborFull = max(neighborFull, Int(fullTop[c - R])) }
                if z < R - 1 { neighborFull = max(neighborFull, Int(fullTop[c + R])) }
                let start = Int(litBottom[c])
                let end = min(H, max(Int(fullTop[c]), neighborFull) + 1)
                if start < end {
                    for y in start..<end {
                        let i = ri(x, y, z)
                        if sky[i] > 1 { push(i, &tail, &head) }
                    }
                }
            }
        }
        flood(sky, &head, &tail)
    }

    private func computeBlockLight() {
        let volume = R * R * H
        blk.update(repeating: 0, count: volume)
        var head = 0, tail = 0
        for i in 0..<volume {
            let e = emissionTable[Int(ids[i])]
            if e > 0 {
                blk[i] = e
                push(i, &tail, &head)
            }
        }
        if tail > 0 { flood(blk, &head, &tail) }
    }

    private func flood(_ light: UnsafeMutablePointer<UInt8>, _ head: inout Int, _ tail: inout Int) {
        let plane = R * R
        while head < tail {
            let i = Int(queue[head]); head += 1
            let level = Int(light[i])
            if level <= 1 { continue }
            let y = i / plane
            let rem = i - y * plane
            let z = rem / R
            let x = rem - z * R
            @inline(__always) func spread(_ n: Int) {
                let f = Int(filterTable[Int(ids[n])])
                if f >= 15 { return }
                let nl = level - 1 - f
                if nl > Int(light[n]) {
                    light[n] = UInt8(nl)
                    push(n, &tail, &head)
                }
            }
            if x > 0 { spread(i - 1) }
            if x < R - 1 { spread(i + 1) }
            if z > 0 { spread(i - R) }
            if z < R - 1 { spread(i + R) }
            if y > 0 { spread(i - plane) }
            if y < H - 1 { spread(i + plane) }
        }
    }

    // MARK: - Sampling helpers

    @inline(__always) private func idAt(_ x: Int, _ y: Int, _ z: Int) -> Int {
        (y < 0 || y >= H) ? 0 : Int(ids[ri(x, y, z)])
    }
    @inline(__always) private func opaqueAt(_ x: Int, _ y: Int, _ z: Int) -> Bool {
        (y < 0 || y >= H) ? false : opaqueTable[Int(ids[ri(x, y, z)])]
    }
    @inline(__always) private func skyAt(_ x: Int, _ y: Int, _ z: Int) -> Int {
        if y >= H { return 15 }
        if y < 0 { return 0 }
        return Int(sky[ri(x, y, z)])
    }
    @inline(__always) private func blkAt(_ x: Int, _ y: Int, _ z: Int) -> Int {
        (y < 0 || y >= H) ? 0 : Int(blk[ri(x, y, z)])
    }

    private static let cornerSigns: [(Int, Int)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]

    /// Face descriptors: normal, u-axis, v-axis, counter-clockwise order flag.
    private struct FaceAxes {
        let n: (Int, Int, Int), u: (Int, Int, Int), v: (Int, Int, Int), ccw: Bool
    }
    private static let axes: [FaceAxes] = [
        FaceAxes(n: (1, 0, 0), u: (0, 0, 1), v: (0, 1, 0), ccw: false),   // east
        FaceAxes(n: (-1, 0, 0), u: (0, 0, 1), v: (0, 1, 0), ccw: true),   // west
        FaceAxes(n: (0, 1, 0), u: (1, 0, 0), v: (0, 0, 1), ccw: false),   // up
        FaceAxes(n: (0, -1, 0), u: (1, 0, 0), v: (0, 0, 1), ccw: true),   // down
        FaceAxes(n: (0, 0, 1), u: (1, 0, 0), v: (0, 1, 0), ccw: true),    // south
        FaceAxes(n: (0, 0, -1), u: (1, 0, 0), v: (0, 1, 0), ccw: false),  // north
    ]

    /// Packs smooth light + AO for the four corners of a face whose open side
    /// is the cell (ax, ay, az). 14 bits per corner: sky sum (6), block sum (6), AO (2).
    @inline(__always) private func cornerData(_ ax: Int, _ ay: Int, _ az: Int, _ fa: FaceAxes, ao useAO: Bool) -> UInt64 {
        let ls = skyAt(ax, ay, az), lb = blkAt(ax, ay, az)
        var packed: UInt64 = 0
        for k in 0..<4 {
            let (su, sv) = ChunkMesher.cornerSigns[k]
            let s1x = ax + su * fa.u.0, s1y = ay + su * fa.u.1, s1z = az + su * fa.u.2
            let s2x = ax + sv * fa.v.0, s2y = ay + sv * fa.v.1, s2z = az + sv * fa.v.2
            let cx = s1x + sv * fa.v.0, cy = s1y + sv * fa.v.1, cz = s1z + sv * fa.v.2
            let o1 = opaqueAt(s1x, s1y, s1z), o2 = opaqueAt(s2x, s2y, s2z)
            let oc = (o1 && o2) ? true : opaqueAt(cx, cy, cz)
            let skySum = ls + (o1 ? ls : skyAt(s1x, s1y, s1z)) + (o2 ? ls : skyAt(s2x, s2y, s2z)) + (oc ? ls : skyAt(cx, cy, cz))
            let blkSum = lb + (o1 ? lb : blkAt(s1x, s1y, s1z)) + (o2 ? lb : blkAt(s2x, s2y, s2z)) + (oc ? lb : blkAt(cx, cy, cz))
            let ao = !useAO ? 3 : ((o1 && o2) ? 0 : 3 - (o1 ? 1 : 0) - (o2 ? 1 : 0) - (oc ? 1 : 0))
            let bits = UInt64(skySum) | (UInt64(blkSum) << 6) | (UInt64(ao) << 12)
            packed |= bits << UInt64(14 * k)
        }
        return packed
    }

    // MARK: - Greedy cube faces

    private func greedyFaces(face: Int, centerHeight hc: Int) {
        let fa = ChunkMesher.axes[face]
        let isY = fa.n.1 != 0
        let isX = fa.n.0 != 0
        let sliceCount = isY ? hc : 16
        let uCount = 16
        let vCount = isY ? 16 : hc
        let positive = fa.n.0 + fa.n.1 + fa.n.2 > 0

        for slice in 0..<sliceCount {
            var any = false
            for v in 0..<vCount {
                for u in 0..<uCount {
                    let x: Int, y: Int, z: Int
                    if isX { x = slice; y = v; z = u } else if isY { x = u; y = slice; z = v } else { x = u; y = v; z = slice }
                    let mi = v * uCount + u
                    maskKey[mi] = ChunkMesher.emptyKey
                    let rx = x + 16, rz = z + 16
                    let id = Int(ids[ri(rx, y, rz)])
                    let shape = shapeTable[id]
                    guard shape == 1 || shape == 4 else { continue }
                    let nx = rx + fa.n.0, ny = y + fa.n.1, nz = rz + fa.n.2
                    if ny < 0 { continue }
                    let nb = idAt(nx, ny, nz)
                    if opaqueTable[nb] { continue }
                    var flags: UInt8 = 0
                    if shape == 4 {
                        // Liquids: skip internal faces; side faces are emitted per block.
                        if waterMeets(id, nb) || !isY { continue }
                        flags |= VertexFlags.liquid
                        if face == 2 && !waterMeets(id, idAt(rx, y + 1, rz)) { flags |= VertexFlags.rawUV }   // lowered surface marker
                    } else if nb == id {
                        if !leafLike[id] || !fancyLeaves { continue }
                    }
                    if wavingTable[id] { flags |= VertexFlags.waving }
                    if emissionTable[id] > 0 { flags |= VertexFlags.emissive }
                    if seasonalTable[id] == 1 || (seasonalTable[id] == 2 && face == 2) { flags |= VertexFlags.seasonal }
                    let layer = UInt32(faceLayer(id, face, x, y, z, patch: 1))
                    maskKey[mi] = layer | (UInt32(flags) << 16) | (UInt32(layerTable[id]) << 24)
                    maskLight[mi] = cornerData(nx, ny, nz, fa, ao: shape != 4)
                    any = true
                }
            }
            guard any else { continue }

            for v in 0..<vCount {
                var u = 0
                while u < uCount {
                    let mi = v * uCount + u
                    let key = maskKey[mi]
                    if key == ChunkMesher.emptyKey { u += 1; continue }
                    let light = maskLight[mi]
                    // Water surfaces ripple per vertex, so they stay one quad per block: a merged quad's long
                    // edge wouldn't follow its smaller neighbours' corners and would open cracks.
                    let rippling = face == 2 && (key >> 16) & UInt32(VertexFlags.liquid) != 0
                    var w = 1
                    while !rippling && u + w < uCount && maskKey[mi + w] == key && maskLight[mi + w] == light { w += 1 }
                    var h = 1
                    extend: while !rippling && v + h < vCount {
                        let row = (v + h) * uCount + u
                        for k in 0..<w where maskKey[row + k] != key || maskLight[row + k] != light {
                            break extend
                        }
                        h += 1
                    }
                    for dv in 0..<h {
                        let row = (v + dv) * uCount + u
                        for k in 0..<w { maskKey[row + k] = ChunkMesher.emptyKey }
                    }
                    emitGreedyQuad(face: face, fa: fa, slice: slice, positive: positive, isX: isX, isY: isY,
                                   u: u, v: v, w: w, h: h, key: key, light: light)
                    u += w
                }
            }
        }
    }

    @inline(__always) private func buffer(forLayer layer: UInt8) -> ReferenceWritableKeyPath<MeshBuffers, [ChunkVertex]> {
        switch layer {
        case 0: return \.opaque
        case 1: return \.cutout
        default: return \.translucent
        }
    }

    private func emitGreedyQuad(face: Int, fa: FaceAxes, slice: Int, positive: Bool, isX: Bool, isY: Bool,
                                u: Int, v: Int, w: Int, h: Int, key: UInt32, light: UInt64) {
        let layer = UInt16(key & 0xFFFF)
        var flags = UInt8((key >> 16) & 0xFF)
        let renderLayer = UInt8((key >> 24) & 0xFF)
        let lowered = (flags & VertexFlags.liquid) != 0 && (flags & VertexFlags.rawUV) != 0
        flags &= ~VertexFlags.rawUV
        var plane = (slice + (positive ? 1 : 0)) * 16
        if lowered { plane -= 2 }

        let us = [u, u + w, u + w, u]
        let vs = [v, v, v + h, v + h]
        var corners = [ChunkVertex]()
        corners.reserveCapacity(4)
        for k in 0..<4 {
            let bits = light >> UInt64(14 * k)
            let skySum = Int(bits & 63), blkSum = Int((bits >> 6) & 63), ao = UInt8((bits >> 12) & 3)
            let cu = UInt16(us[k] * 16), cv = UInt16(vs[k] * 16)
            let px: UInt16, py: UInt16, pz: UInt16
            if isX { px = UInt16(plane); py = cv; pz = cu } else if isY { px = cu; py = UInt16(plane); pz = cv } else { px = cu; py = cv; pz = UInt16(plane) }
            corners.append(ChunkVertex(x: px, y: py, z: pz, layer: layer, u: cu, v: cv, normal: UInt8(face), ao: ao,
                                       sky: UInt8(skySum * 255 / 60), light: UInt8(blkSum * 255 / 60), flags: flags))
        }
        let a0 = Int(corners[0].ao) + Int(corners[2].ao)
        let a1 = Int(corners[1].ao) + Int(corners[3].ao)
        let order: [Int]
        if fa.ccw {
            order = a0 < a1 ? [1, 2, 3, 0] : [0, 1, 2, 3]
        } else {
            order = a0 < a1 ? [3, 2, 1, 0] : [0, 3, 2, 1]
        }
        let path = buffer(forLayer: renderLayer)
        for k in order { out[keyPath: path].append(corners[k]) }
    }

    // MARK: - Plants, torches, liquid sides

    private func specialShapes(centerHeight hc: Int) {
        for y in 0..<hc {
            for z in 0..<16 {
                for x in 0..<16 {
                    let rx = x + 16, rz = z + 16
                    let id = Int(ids[ri(rx, y, rz)])
                    switch shapeTable[id] {
                    case 2:
                        emitCross(id: id, x: x, y: y, z: z)
                        if submergedTable[id] { emitSubmergedWater(x: x, y: y, z: z) }
                    case 3: emitTorch(id: id, x: x, y: y, z: z)
                    case 4: emitLiquidSides(id: id, x: x, y: y, z: z)
                    case 5: emitBox(id: id, x: x, y: y, z: z)
                    case 6: emitWallTorch(id: id, x: x, y: y, z: z)
                    default: break
                    }
                }
            }
        }
    }

    @inline(__always) private func cellLight(_ rx: Int, _ y: Int, _ rz: Int) -> (UInt8, UInt8) {
        (UInt8(skyAt(rx, y, rz) * 17), UInt8(blkAt(rx, y, rz) * 17))
    }

    private func emitRaw(_ positions: [(Int, Int, Int)], _ uvs: [(Int, Int)], layer: UInt16, normal: UInt8,
                         sky: UInt8, light: UInt8, flags: [UInt8], into path: ReferenceWritableKeyPath<MeshBuffers, [ChunkVertex]>,
                         origin: (Int, Int, Int)) {
        for k in 0..<4 {
            let p = positions[k]
            out[keyPath: path].append(ChunkVertex(
                x: UInt16(origin.0 * 16 + p.0), y: UInt16(origin.1 * 16 + p.1), z: UInt16(origin.2 * 16 + p.2),
                layer: layer, u: UInt16(uvs[k].0), v: UInt16(uvs[k].1), normal: normal, ao: 3,
                sky: sky, light: light, flags: flags[k]))
        }
    }

    private func emitCross(id: Int, x: Int, y: Int, z: Int) {
        let (s, l) = cellLight(x + 16, y, z + 16)
        let layer = faceLayer(id, 0, x, y, z)
        let base = VertexFlags.rawUV | (emissionTable[id] > 0 ? VertexFlags.emissive : 0) | (seasonalTable[id] != 0 ? VertexFlags.seasonal : 0)
        let waveTop = wavingTable[id] ? VertexFlags.wavingTop : 0
        // A stack of the same plant (kelp) sways as one: each piece's foot follows the one below.
        let waveFoot = wavingTable[id] && idAt(x + 16, y - 1, z + 16) == id ? VertexFlags.wavingTop : 0
        let flags = [base | waveFoot, base | waveFoot, base | waveTop, base | waveTop]
        let uvs = [(0, 16), (16, 16), (16, 0), (0, 0)]
        let a = 2, b = 14
        let quads: [[(Int, Int, Int)]] = [
            [(a, 0, a), (b, 0, b), (b, 16, b), (a, 16, a)],
            [(b, 0, b), (a, 0, a), (a, 16, a), (b, 16, b)],
            [(b, 0, a), (a, 0, b), (a, 16, b), (b, 16, a)],
            [(a, 0, b), (b, 0, a), (b, 16, a), (a, 16, b)],
        ]
        for q in quads {
            emitRaw(q, uvs, layer: layer, normal: 6, sky: s, light: l, flags: flags, into: \.cutout, origin: (x, y, z))
        }
    }

    private func emitTorch(id: Int, x: Int, y: Int, z: Int) {
        let (s, _) = cellLight(x + 16, y, z + 16)
        let layer = faceLayers[id * 6]
        let f = VertexFlags.rawUV | VertexFlags.emissive
        let flags = [f, f, f, f]
        let side = [(7, 16), (9, 16), (9, 6), (7, 6)]
        let faces: [([(Int, Int, Int)], [(Int, Int)], UInt8)] = [
            ([(9, 0, 9), (9, 0, 7), (9, 10, 7), (9, 10, 9)], side, 0),
            ([(7, 0, 7), (7, 0, 9), (7, 10, 9), (7, 10, 7)], side, 1),
            ([(7, 10, 9), (9, 10, 9), (9, 10, 7), (7, 10, 7)], [(7, 8), (9, 8), (9, 6), (7, 6)], 2),
            ([(7, 0, 9), (9, 0, 9), (9, 10, 9), (7, 10, 9)], side, 4),
            ([(9, 0, 7), (7, 0, 7), (7, 10, 7), (9, 10, 7)], side, 5),
        ]
        for (pos, uv, n) in faces {
            emitRaw(pos, uv, layer: layer, normal: n, sky: s, light: 255, flags: flags, into: \.cutout, origin: (x, y, z))
        }
    }

    private func emitBox(id: Int, x: Int, y: Int, z: Int) {
        if DoubleChests.isChest(BlockID(id)), let boxes = boxTable[id].first,
           let partner = DoubleChests.partner(x: x + 16, y: y, z: z + 16, id: BlockID(id), facing: facingTable[id],
                                              block: { BlockID(idAt($0, $1, $2)) }) {
            emitDoubleChestHalf(id: id, x: x, y: y, z: z, b: boxes, partner: partner)
            return
        }
        for b in boxTable[id] { emitCuboid(id: id, x: x, y: y, z: z, b: b) }
    }

    /// One half of a double chest: the box reaches across to its partner, the face between them is
    /// left out, and the faces running along the pair use half textures turned so their open
    /// (border-less) edge meets the seam.
    private func emitDoubleChestHalf(id: Int, x: Int, y: Int, z: Int, b: BlockBox, partner: (dx: Int, dz: Int)) {
        let box = BlockBox([partner.dx < 0 ? 0 : Int(b.x0), Int(b.y0), partner.dz < 0 ? 0 : Int(b.z0),
                            partner.dx > 0 ? 16 : Int(b.x1), Int(b.y1), partner.dz > 0 ? 16 : Int(b.z1)])
        let towardPartner = partner.dx > 0 ? 0 : partner.dx < 0 ? 1 : partner.dz > 0 ? 4 : 5
        let awayFromPartner = towardPartner ^ 1
        let front = Int(facingTable[id]), back = front ^ 1
        let halves = chestHalfLayers
        emitCuboid(id: id, x: x, y: y, z: z, b: box, skip: towardPartner) { face, positions, uvs in
            guard face != awayFromPartner else { return nil }
            let layer = face == front ? halves.front : face == back ? halves.side : halves.top
            // Corners on the seam, in the face's own texture coordinates.
            let seam = positions.indices.filter { k in
                let p = positions[k]
                return (partner.dx > 0 && p.0 == 16) || (partner.dx < 0 && p.0 == 0) || (partner.dz > 0 && p.2 == 16) || (partner.dz < 0 && p.2 == 0)
            }
            guard let k = seam.first else { return nil }
            let turned: [(Int, Int)]
            if seam.allSatisfy({ uvs[$0].0 == uvs[k].0 }) {
                turned = uvs[k].0 == 16 ? uvs : uvs.map { (16 - $0.0, $0.1) }
            } else {
                turned = uvs[k].1 == 16 ? uvs.map { ($0.1, $0.0) } : uvs.map { (16 - $0.1, $0.0) }
            }
            return (layer, turned)
        }
    }

    private func emitCuboid(id: Int, x: Int, y: Int, z: Int, b: BlockBox, skip: Int = -1,
                            restyle: ((Int, [(Int, Int, Int)], [(Int, Int)]) -> (UInt16, [(Int, Int)])?)? = nil) {
        let rx = x + 16, rz = z + 16
        let x0 = Int(b.x0), y0 = Int(b.y0), z0 = Int(b.z0), x1 = Int(b.x1), y1 = Int(b.y1), z1 = Int(b.z1)
        let f = VertexFlags.rawUV | (emissionTable[id] > 0 ? VertexFlags.emissive : 0)
        let flags = [f, f, f, f]
        let path = buffer(forLayer: layerTable[id] == 0 ? 0 : 1)
        let (s, l) = cellLight(rx, y, rz)
        // (face, positions, uvs, touches the cell boundary)
        let faces: [(Int, [(Int, Int, Int)], [(Int, Int)], Bool)] = [
            (0, [(x1, y0, z1), (x1, y0, z0), (x1, y1, z0), (x1, y1, z1)], [(16 - z1, 16 - y0), (16 - z0, 16 - y0), (16 - z0, 16 - y1), (16 - z1, 16 - y1)], x1 == 16),
            (1, [(x0, y0, z0), (x0, y0, z1), (x0, y1, z1), (x0, y1, z0)], [(z0, 16 - y0), (z1, 16 - y0), (z1, 16 - y1), (z0, 16 - y1)], x0 == 0),
            (2, [(x0, y1, z1), (x1, y1, z1), (x1, y1, z0), (x0, y1, z0)], [(x0, z1), (x1, z1), (x1, z0), (x0, z0)], y1 == 16),
            (3, [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], [(x0, z0), (x1, z0), (x1, z1), (x0, z1)], y0 == 0),
            (4, [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], [(x0, 16 - y0), (x1, 16 - y0), (x1, 16 - y1), (x0, 16 - y1)], z1 == 16),
            (5, [(x1, y0, z0), (x0, y0, z0), (x0, y1, z0), (x1, y1, z0)], [(16 - x1, 16 - y0), (16 - x0, 16 - y0), (16 - x0, 16 - y1), (16 - x1, 16 - y1)], z0 == 0),
        ]
        for (face, pos, uv, boundary) in faces where face != skip {
            if boundary {
                let fa = ChunkMesher.axes[face]
                let nb = idAt(rx + fa.n.0, y + fa.n.1, rz + fa.n.2)
                if opaqueTable[nb] { continue }
            }
            let (layer, uvs) = restyle?(face, pos, uv) ?? (faceLayers[id * 6 + face], uv)
            emitRaw(pos, uvs, layer: layer, normal: UInt8(face), sky: s, light: l, flags: flags, into: path, origin: (x, y, z))
        }
    }

    private func emitWallTorch(id: Int, x: Int, y: Int, z: Int) {
        let (s, _) = cellLight(x + 16, y, z + 16)
        let layer = faceLayers[id * 6]
        let f = VertexFlags.rawUV | VertexFlags.emissive
        let flags = [f, f, f, f]
        let facing = facingTable[id]
        let (nx, nz): (Int, Int) = facing == 0 ? (1, 0) : facing == 1 ? (-1, 0) : facing == 4 ? (0, 1) : (0, -1)
        func lean(_ p: (Int, Int, Int)) -> (Int, Int, Int) {
            let off = p.1 == 0 ? 6 : 3
            return (p.0 + nx * off, p.1 + 3, p.2 + nz * off)
        }
        let side = [(7, 16), (9, 16), (9, 6), (7, 6)]
        let faces: [([(Int, Int, Int)], [(Int, Int)], UInt8)] = [
            ([(9, 0, 9), (9, 0, 7), (9, 10, 7), (9, 10, 9)], side, 0),
            ([(7, 0, 7), (7, 0, 9), (7, 10, 9), (7, 10, 7)], side, 1),
            ([(7, 10, 9), (9, 10, 9), (9, 10, 7), (7, 10, 7)], [(7, 8), (9, 8), (9, 6), (7, 6)], 2),
            ([(7, 0, 9), (9, 0, 9), (9, 10, 9), (7, 10, 9)], side, 4),
            ([(9, 0, 7), (7, 0, 7), (7, 10, 7), (9, 10, 7)], side, 5),
        ]
        for (pos, uv, n) in faces {
            emitRaw(pos.map(lean), uv, layer: layer, normal: n, sky: s, light: 255, flags: flags, into: \.cutout, origin: (x, y, z))
        }
    }

    /// The water around a plant growing under water: a surface on top if nothing wet is above,
    /// and sides wherever it meets air.
    private func emitSubmergedWater(x: Int, y: Int, z: Int) {
        let water = Int(Blocks.water)
        let rx = x + 16, rz = z + 16
        emitLiquidSides(id: water, x: x, y: y, z: z)
        let above = idAt(rx, y + 1, rz)
        guard !waterMeets(water, above), !opaqueTable[above] else { return }
        let (s, l) = cellLight(rx, y + 1, rz)
        let positions = [(0, 14, 16), (16, 14, 16), (16, 14, 0), (0, 14, 0)]
        let uvs = positions.map { (x * 16 + $0.0, z * 16 + $0.2) }
        emitRaw(positions, uvs, layer: faceLayers[water * 6 + 2], normal: 2, sky: s, light: l,
                flags: [VertexFlags.liquid, VertexFlags.liquid, VertexFlags.liquid, VertexFlags.liquid], into: \.translucent, origin: (x, y, z))
    }

    private func emitLiquidSides(id: Int, x: Int, y: Int, z: Int) {
        let rx = x + 16, rz = z + 16
        let top = waterMeets(id, idAt(rx, y + 1, rz)) ? 16 : 14
        let layer = faceLayers[id * 6]
        let flags = [VertexFlags.liquid, VertexFlags.liquid, VertexFlags.liquid, VertexFlags.liquid]
        let sides: [(Int, [(Int, Int, Int)])] = [
            (0, [(16, 0, 16), (16, 0, 0), (16, top, 0), (16, top, 16)]),
            (1, [(0, 0, 0), (0, 0, 16), (0, top, 16), (0, top, 0)]),
            (4, [(0, 0, 16), (16, 0, 16), (16, top, 16), (0, top, 16)]),
            (5, [(16, 0, 0), (0, 0, 0), (0, top, 0), (16, top, 0)]),
        ]
        for (face, pos) in sides {
            let fa = ChunkMesher.axes[face]
            let nx = rx + fa.n.0, nz = rz + fa.n.2
            let nb = idAt(nx, y, nz)
            if waterMeets(id, nb) || opaqueTable[nb] { continue }
            let (s, l) = cellLight(nx, y, nz)
            let uvs = pos.map { p -> (Int, Int) in
                let u = (face == 0 || face == 1) ? p.2 : p.0
                return (u + x * 16 + z * 16, (WorldConst.height - y) * 16 - p.1)
            }
            emitRaw(pos, uvs, layer: layer, normal: UInt8(face), sky: s, light: l,
                    flags: flags.map { $0 | VertexFlags.rawUV }, into: \.translucent, origin: (x, y, z))
        }
    }
}
