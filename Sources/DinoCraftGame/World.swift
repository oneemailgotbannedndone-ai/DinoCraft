import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Streams chunks around a moving point: loads saved chunks or generates new
/// ones on worker threads, schedules lighting + meshing once all neighbours
/// exist, integrates results on the main thread within a time budget, and
/// unloads (saving if modified) chunks that fall out of range. Chunk meshes are
/// created by the platform renderer through a `ChunkMeshFactory`.
final class World: BlockSource {
    final class Slot {
        let chunk: Chunk
        var mesh: ChunkMeshHandle?
        /// Light of this chunk (`sky << 4 | block`) from its last mesh, used to light entities and the held item.
        var light: [UInt8] = []
        var lightHeight = 0
        var needsMesh = true
        var urgentMesh = false
        var meshInFlight = false
        var meshToken: UInt64 = 0
        /// When the first mesh arrived (drives the fade-in); -1 until then.
        var firstMeshTime: Double = -1
        init(chunk: Chunk) { self.chunk = chunk }
    }

    private struct MeshResult {
        let pos: ChunkPos
        let token: UInt64
        let prepared: PreparedChunkMesh
        let light: [UInt8]
        let lightHeight: Int
        let seconds: Double
    }

    /// Results written by workers, drained by the main thread.
    private final class Inbox: @unchecked Sendable {
        let lock = NSLock()
        var generated: [(Chunk, Double, Bool)] = []          // chunk, seconds, fromDisk
        var meshed: [MeshResult] = []
        var cancelled = false
    }

    struct Stats {
        var loadedChunks = 0
        var meshedChunks = 0
        var pendingGeneration = 0
        var pendingMeshes = 0
        var avgGenerationMs = 0.0
        var avgMeshMs = 0.0
        var generatedTotal = 0
        var meshedTotal = 0
        var gpuMeshBytes = 0
    }

    let registry: BlockRegistry
    let generator: WorldGenerator
    let storage: WorldStorage?
    let worldID: String?
    let meshFactory: ChunkMeshFactory
    let jobs: JobSystem

    private(set) var slots: [ChunkPos: Slot] = [:]
    private var pendingGeneration = Set<ChunkPos>()
    private var inbox = Inbox()
    private let jobGroup: Int
    private static var nextGroup = 1

    var renderDistance: Int { didSet { if renderDistance != oldValue { rebuildOffsets() } } }
    private(set) var center = ChunkPos(0, 0)
    private var offsets: [(Int32, Int32)] = []
    private(set) var stats = Stats()
    private var inFlightMeshes = 0
    private var gpuBytes = 0

    /// Called after every gameplay block change (used by the multiplayer host).
    var onBlockChanged: ((BlockPos, BlockID) -> Void)?
    /// When set (multiplayer client), chunks are requested from the host instead of generated.
    var remoteRequest: (([ChunkPos]) -> Void)?
    private var remoteRequestedAt: [ChunkPos: Double] = [:]

    init(registry: BlockRegistry, generator: WorldGenerator, storage: WorldStorage?, worldID: String?,
         meshFactory: ChunkMeshFactory, jobs: JobSystem, renderDistance: Int) {
        self.registry = registry
        self.generator = generator
        self.storage = storage
        self.worldID = worldID
        self.meshFactory = meshFactory
        self.jobs = jobs
        self.renderDistance = renderDistance
        jobGroup = World.nextGroup
        World.nextGroup += 1
        rebuildOffsets()
    }

    private static func now() -> Double { Date.timeIntervalSinceReferenceDate }

    private func rebuildOffsets() {
        let r = Int32(renderDistance + 2)
        var list: [(Int32, Int32)] = []
        for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + r { list.append((dx, dz)) } }
        list.sort { ($0.0 * $0.0 + $0.1 * $0.1) < ($1.0 * $1.0 + $1.1 * $1.1) }
        offsets = list
    }

    // MARK: Block access

    @inline(__always) func slot(at pos: ChunkPos) -> Slot? { slots[pos] }

    func blockIfLoaded(_ x: Int, _ y: Int, _ z: Int) -> BlockID? {
        guard y >= 0 && y < WorldConst.height else { return Blocks.air }
        guard let s = slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))] else { return nil }
        return s.chunk.block(x & 15, y, z & 15)
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID { blockIfLoaded(x, y, z) ?? Blocks.air }
    func block(_ p: BlockPos) -> BlockID { block(Int(p.x), Int(p.y), Int(p.z)) }

    func isLoaded(_ x: Int, _ z: Int) -> Bool { slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))] != nil }

    /// Sets a block and schedules urgent remeshing of the chunk and its neighbours
    /// (lighting can change up to 15 blocks away).
    @discardableResult
    func setBlock(_ p: BlockPos, _ id: BlockID) -> Bool {
        guard p.y >= 0 && p.y < Int32(WorldConst.height), let s = slots[p.chunk] else { return false }
        let lx = Int(p.x) & 15, lz = Int(p.z) & 15
        guard s.chunk.block(lx, Int(p.y), lz) != id else { return false }
        s.chunk.set(lx, Int(p.y), lz, id)
        onBlockChanged?(p, id)
        for dz: Int32 in -1...1 {
            for dx: Int32 in -1...1 {
                if let n = slots[ChunkPos(p.chunk.x + dx, p.chunk.z + dz)] {
                    n.needsMesh = true
                    if dx == 0 && dz == 0 { n.urgentMesh = true }
                    else if abs(Int(lx) - (dx < 0 ? 0 : 15)) < 15 || abs(Int(lz) - (dz < 0 ? 0 : 15)) < 15 { n.urgentMesh = true }
                }
            }
        }
        return true
    }

    /// Sky and block light (0...1) at a world position, from the chunk's last mesh.
    func light(at p: DVec3) -> (sky: Float, block: Float) {
        let x = Int(floor(p.x)), y = Int(floor(p.y)), z = Int(floor(p.z))
        guard y >= 0 else { return (0, 0) }
        guard let s = slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))], !s.light.isEmpty else { return (1, 0) }
        guard y < s.lightHeight else { return (1, 0) }
        let v = s.light[(y * 16 + (z & 15)) * 16 + (x & 15)]
        return (Float(v >> 4) / 15, Float(v & 15) / 15)
    }

    /// Nearest y (searching outward from `near`) where a player-sized creature can stand.
    func findStandingY(_ x: Int, _ z: Int, near: Int) -> Int? {
        guard isLoaded(x, z) else { return nil }
        func ok(_ y: Int) -> Bool {
            guard y > 0, y < WorldConst.height - 2 else { return false }
            let below = block(x, y - 1, z), feet = block(x, y, z), head = block(x, y + 1, z)
            return registry.isSolid[Int(below)] && !registry.isSolid[Int(feet)] && !registry.isSolid[Int(head)]
                && !registry.isWet[Int(feet)] && !registry.isWet[Int(head)]
                && below != Blocks.leaves && below != Blocks.redwoodNeedles && below != Blocks.bedrock
        }
        for d in 0..<WorldConst.height {
            if ok(near + d) { return near + d }
            if d > 0 && ok(near - d) { return near - d }
        }
        return nil
    }

    /// Highest solid block y at a column, if loaded.
    func topSolidY(_ x: Int, _ z: Int) -> Int? {
        guard let s = slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))] else { return nil }
        let c = s.chunk
        var y = min(WorldConst.height - 1, c.maxHeight)
        while y > 0 {
            let id = c.block(x & 15, y, z & 15)
            if registry.isSolid[Int(id)] { return y }
            y -= 1
        }
        return nil
    }

    // MARK: Streaming

    /// Call once per frame. `budget` bounds main-thread integration time (seconds).
    func update(focus: DVec3, budget: Double = 0.004) {
        let start = World.now()
        center = ChunkPos(Int32(floor(focus.x / 16)), Int32(floor(focus.z / 16)))

        integrateResults(deadline: start + budget)
        unloadDistant()
        scheduleGeneration()
        scheduleMeshing()

        stats.loadedChunks = slots.count
        stats.pendingGeneration = pendingGeneration.count
        stats.pendingMeshes = inFlightMeshes
        stats.gpuMeshBytes = gpuBytes
    }

    private func integrateResults(deadline: Double) {
        inbox.lock.lock()
        var generated = inbox.generated
        var meshed = inbox.meshed
        inbox.generated.removeAll(keepingCapacity: true)
        inbox.meshed.removeAll(keepingCapacity: true)
        inbox.lock.unlock()

        // Apply meshes first.
        for result in meshed {
            inFlightMeshes = max(0, inFlightMeshes - 1)
            stats.avgMeshMs = stats.avgMeshMs * 0.95 + result.seconds * 1000 * 0.05
            stats.meshedTotal += 1
            guard let s = slots[result.pos] else { continue }
            s.meshInFlight = false
            guard result.token == s.meshToken else { continue }
            let mesh = meshFactory.finish(result.prepared)
            if let old = s.mesh {
                gpuBytes -= old.memoryBytes
                meshFactory.release(old)
            }
            s.mesh = mesh
            s.light = result.light
            s.lightHeight = result.lightHeight
            if s.firstMeshTime < 0 { s.firstMeshTime = meshFactory.clock }
            gpuBytes += mesh?.memoryBytes ?? 0
        }
        meshed.removeAll()

        var index = 0
        let radius = Int32(renderDistance + 2)
        while index < generated.count {
            let (chunk, seconds, _) = generated[index]
            index += 1
            pendingGeneration.remove(chunk.pos)
            stats.avgGenerationMs = stats.avgGenerationMs * 0.95 + seconds * 1000 * 0.05
            stats.generatedTotal += 1
            let dx = chunk.pos.x - center.x, dz = chunk.pos.z - center.z
            if dx * dx + dz * dz > (radius + 1) * (radius + 1) && !chunk.needsSave { continue }
            guard slots[chunk.pos] == nil else { continue }
            slots[chunk.pos] = Slot(chunk: chunk)
            for dz2: Int32 in -1...1 {
                for dx2: Int32 in -1...1 where !(dx2 == 0 && dz2 == 0) {
                    slots[ChunkPos(chunk.pos.x + dx2, chunk.pos.z + dz2)]?.needsMesh = true
                }
            }
            if World.now() > deadline { break }
        }
        if index < generated.count {
            // Put back what we didn't integrate this frame.
            generated.removeFirst(index)
            inbox.lock.lock()
            inbox.generated.insert(contentsOf: generated, at: 0)
            inbox.lock.unlock()
        }
    }

    private func unloadDistant() {
        let limit = Int32(renderDistance + 3)
        var toRemove: [ChunkPos] = []
        for (pos, _) in slots {
            let dx = pos.x - center.x, dz = pos.z - center.z
            if dx * dx + dz * dz > limit * limit { toRemove.append(pos) }
        }
        for pos in toRemove {
            guard let s = slots.removeValue(forKey: pos) else { continue }
            if let mesh = s.mesh {
                gpuBytes -= mesh.memoryBytes
                meshFactory.release(mesh)
            }
            if s.chunk.needsSave { saveChunk(s.chunk) }
        }
    }

    private func scheduleGeneration() {
        if let remoteRequest {
            let now = World.now()
            let radius = Int32(renderDistance + 2)
            var batch: [ChunkPos] = []
            for (dx, dz) in offsets {
                if batch.count >= 48 { break }
                if dx * dx + dz * dz > radius * radius + radius { continue }
                let pos = ChunkPos(center.x + dx, center.z + dz)
                if slots[pos] != nil { continue }
                if let t = remoteRequestedAt[pos], now - t < 6 { continue }
                remoteRequestedAt[pos] = now
                batch.append(pos)
            }
            if !batch.isEmpty { remoteRequest(batch) }
            return
        }
        let maxQueued = jobs.workerCount * 3
        guard pendingGeneration.count < maxQueued else { return }
        let genRadius = Int32(renderDistance + 2)
        for (dx, dz) in offsets {
            if pendingGeneration.count >= maxQueued { break }
            if dx * dx + dz * dz > genRadius * genRadius + genRadius { continue }
            let pos = ChunkPos(center.x + dx, center.z + dz)
            if slots[pos] != nil || pendingGeneration.contains(pos) { continue }
            pendingGeneration.insert(pos)
            let priority = Int(dx * dx + dz * dz) * 4
            let generator = self.generator, storage = self.storage, worldID = self.worldID, inbox = self.inbox
            let folder = generator.dimension.storageFolder
            jobs.submit(priority: priority, group: jobGroup) { _ in
                guard !inbox.cancelled else { return }
                let t0 = World.now()
                var chunk: Chunk? = nil
                var fromDisk = false
                if let storage, let worldID {
                    chunk = storage.loadChunk(worldID: worldID, pos: pos, dimension: folder)
                    fromDisk = chunk != nil
                }
                let result = chunk ?? generator.generate(pos)
                let dt = World.now() - t0
                inbox.lock.lock()
                inbox.generated.append((result, dt, fromDisk))
                inbox.lock.unlock()
            }
        }
    }

    private func scheduleMeshing() {
        let maxInFlight = jobs.workerCount * 2
        let r = Int32(renderDistance)
        // Urgent (edited) chunks first, regardless of queue pressure.
        for (pos, s) in slots where s.urgentMesh && s.needsMesh && !s.meshInFlight {
            submitMesh(pos, s, priority: -1_000_000)
        }
        guard inFlightMeshes < maxInFlight else { return }
        for (dx, dz) in offsets {
            if inFlightMeshes >= maxInFlight { break }
            if dx * dx + dz * dz > r * r + r { break }
            let pos = ChunkPos(center.x + dx, center.z + dz)
            guard let s = slots[pos], s.needsMesh, !s.meshInFlight else { continue }
            submitMesh(pos, s, priority: Int(dx * dx + dz * dz) * 4 - 2)
        }
    }

    private func submitMesh(_ pos: ChunkPos, _ s: Slot, priority: Int) {
        var hood: [Chunk] = []
        hood.reserveCapacity(9)
        for dz: Int32 in -1...1 {
            for dx: Int32 in -1...1 {
                guard let n = slots[ChunkPos(pos.x + dx, pos.z + dz)] else { return }
                hood.append(n.chunk)
            }
        }
        s.needsMesh = false
        s.urgentMesh = false
        s.meshInFlight = true
        s.meshToken &+= 1
        inFlightMeshes += 1
        let token = s.meshToken, factory = self.meshFactory, inbox = self.inbox
        let label = "Chunk \(pos.x),\(pos.z)"
        jobs.submit(priority: priority, group: jobGroup) { ctx in
            let t0 = World.now()
            let mesher = ctx.mesher
            mesher.build(neighborhood: hood)
            let (light, lightHeight) = mesher.centerLight()
            let prepared = factory.prepare(buffers: mesher.out, maxY: hood[4].maxHeight, label: label)
            let result = MeshResult(pos: pos, token: token, prepared: prepared, light: light, lightHeight: lightHeight,
                                    seconds: World.now() - t0)
            inbox.lock.lock()
            inbox.meshed.append(result)
            inbox.lock.unlock()
        }
    }

    /// Integrates a chunk received from a multiplayer host.
    func receiveRemoteChunk(_ chunk: Chunk) {
        remoteRequestedAt[chunk.pos] = nil
        if let existing = slots[chunk.pos] {
            existing.chunk.blocks.update(from: chunk.blocks, count: WorldConst.blocksPerChunk)
            existing.chunk.recomputeHeights()
            existing.chunk.markVersionChanged()
            for dz: Int32 in -1...1 { for dx: Int32 in -1...1 { slots[ChunkPos(chunk.pos.x + dx, chunk.pos.z + dz)]?.needsMesh = true } }
            return
        }
        inbox.lock.lock()
        inbox.generated.append((chunk, 0, true))
        inbox.lock.unlock()
    }

    /// Drops every chunk (a multiplayer host moved to another dimension).
    func resetRemote() {
        for (_, s) in slots { if let mesh = s.mesh { meshFactory.release(mesh) } }
        slots.removeAll()
        pendingGeneration.removeAll()
        remoteRequestedAt.removeAll()
        inbox.lock.lock()
        inbox.generated.removeAll()
        inbox.meshed.removeAll()
        inbox.lock.unlock()
        inFlightMeshes = 0
        gpuBytes = 0
    }

    /// Forces every loaded chunk to rebuild its mesh (e.g. graphics quality changed).
    func invalidateAllMeshes() {
        for (_, s) in slots { s.needsMesh = true }
    }

    // MARK: Readiness (loading screen)

    /// Fraction of chunks within `radius` of `pos` that are generated and meshed.
    func readiness(around pos: ChunkPos, radius: Int32) -> (generated: Int, meshed: Int, total: Int) {
        var g = 0, m = 0, t = 0
        for dz in -radius...radius {
            for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                t += 1
                if let s = slots[ChunkPos(pos.x + dx, pos.z + dz)] {
                    g += 1
                    if s.firstMeshTime >= 0 { m += 1 }
                }
            }
        }
        return (g, m, t)
    }

    // MARK: Saving

    private func saveChunk(_ chunk: Chunk) {
        guard let storage, let worldID else {
            chunk.needsSave = false
            return
        }
        let copy = Chunk(pos: chunk.pos)
        copy.blocks.update(from: chunk.blocks, count: WorldConst.blocksPerChunk)
        chunk.needsSave = false
        let folder = generator.dimension.storageFolder
        storage.ioQueue.async {
            do {
                try storage.writeChunkData(copy.serialize(), worldID: worldID, pos: copy.pos, dimension: folder)
            } catch {
                Log.error("Failed to save chunk \(copy.pos): \(error)", category: "Save")
                DispatchQueue.main.async { chunk.needsSave = true }
            }
        }
    }

    /// Queues every modified chunk for writing. Returns how many were queued.
    @discardableResult
    func saveModifiedChunks() -> Int {
        var n = 0
        for (_, s) in slots where s.chunk.needsSave {
            saveChunk(s.chunk)
            n += 1
        }
        return n
    }

    /// Blocks until queued disk writes finish.
    func flushSaves() {
        storage?.ioQueue.sync {}
    }

    func shutdown() {
        inbox.cancelled = true
        jobs.cancel(group: jobGroup)
        saveModifiedChunks()
        flushSaves()
        for (_, s) in slots { if let mesh = s.mesh { meshFactory.release(mesh) } }
        slots.removeAll()
        gpuBytes = 0
    }
}
