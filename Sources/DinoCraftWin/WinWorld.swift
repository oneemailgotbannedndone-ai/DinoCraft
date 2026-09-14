import Foundation
import DinoCraftCore

/// A finished chunk mesh on the CPU, waiting to be uploaded on the main thread.
final class MeshPayload {
    let vertices: [ChunkVertex]
    let opaqueQuads: Int
    let cutoutQuads: Int
    let translucentQuads: Int
    let maxY: Int

    init(buffers: MeshBuffers, maxY: Int) {
        vertices = buffers.opaque + buffers.cutout + buffers.translucent
        opaqueQuads = buffers.opaque.count / 4
        cutoutQuads = buffers.cutout.count / 4
        translucentQuads = buffers.translucent.count / 4
        self.maxY = maxY
    }
}

/// A chunk mesh in OpenGL: one vertex buffer with the opaque, cutout and translucent segments back to back.
final class GPUMesh {
    let vertexArray: UInt32
    let buffer: UInt32
    let opaqueQuads: Int
    let cutoutQuads: Int
    let translucentQuads: Int
    let maxY: Int

    init(vertexArray: UInt32, buffer: UInt32, payload: MeshPayload) {
        self.vertexArray = vertexArray
        self.buffer = buffer
        opaqueQuads = payload.opaqueQuads
        cutoutQuads = payload.cutoutQuads
        translucentQuads = payload.translucentQuads
        maxY = payload.maxY
    }
}

/// Worker threads for terrain generation and meshing; each owns a chunk mesher.
final class WinJobSystem: @unchecked Sendable {
    private struct Job {
        let priority: Int
        let sequence: UInt64
        let group: Int
        let work: (ChunkMesher) -> Void
    }

    private let condition = NSCondition()
    private var queue: [Job] = []
    private var sequence: UInt64 = 0
    private var running = true
    let workerCount: Int

    init(workerCount: Int, registry: BlockRegistry) {
        self.workerCount = workerCount
        for i in 0..<workerCount {
            let mesher = ChunkMesher(registry: registry)
            let thread = Thread { [unowned self] in self.workerLoop(mesher) }
            thread.name = "DinoCraft Worker \(i + 1)"
            thread.stackSize = 1 << 22
            thread.start()
        }
        Log.info("Job system started with \(workerCount) workers", category: "Jobs")
    }

    private func workerLoop(_ mesher: ChunkMesher) {
        while true {
            condition.lock()
            while queue.isEmpty && running { condition.wait() }
            if !running { condition.unlock(); return }
            var best = 0
            for i in 1..<queue.count where queue[i].priority < queue[best].priority ||
                (queue[i].priority == queue[best].priority && queue[i].sequence < queue[best].sequence) {
                best = i
            }
            queue.swapAt(best, queue.count - 1)
            let job = queue.removeLast()
            condition.unlock()
            job.work(mesher)
        }
    }

    func submit(priority: Int, group: Int, _ work: @escaping (ChunkMesher) -> Void) {
        condition.lock()
        sequence &+= 1
        queue.append(Job(priority: priority, sequence: sequence, group: group, work: work))
        condition.signal()
        condition.unlock()
    }

    func cancel(group: Int) {
        condition.lock()
        queue.removeAll { $0.group == group }
        condition.unlock()
    }

    func shutdown() {
        condition.lock()
        running = false
        queue.removeAll()
        condition.broadcast()
        condition.unlock()
    }
}

/// Streams chunks around the player (Windows version of the Mac `World`, without Metal).
final class WinWorld: BlockSource {
    final class Slot {
        let chunk: Chunk
        var mesh: GPUMesh?
        var needsMesh = true
        var urgentMesh = false
        var meshInFlight = false
        var meshToken: UInt64 = 0
        var firstMeshTime = -1.0
        init(chunk: Chunk) { self.chunk = chunk }
    }

    private final class Inbox: @unchecked Sendable {
        let lock = NSLock()
        var generated: [Chunk] = []
        var meshed: [(ChunkPos, UInt64, MeshPayload)] = []
        var cancelled = false
    }

    let registry: BlockRegistry
    let generator: WorldGenerator
    /// nil when playing on a friend's world (nothing is saved locally).
    let storage: WorldStorage?
    let worldID: String?
    let jobs: WinJobSystem

    private(set) var slots: [ChunkPos: Slot] = [:]
    private var pendingGeneration = Set<ChunkPos>()
    private let inbox = Inbox()
    private let jobGroup = 1
    private var inFlightMeshes = 0
    private var offsets: [(Int32, Int32)] = []
    private(set) var center = ChunkPos(0, 0)
    /// Multiplayer: chunks are requested from the host instead of generated.
    var remoteRequest: (([ChunkPos]) -> Void)?
    private var remoteRequestedAt: [ChunkPos: Double] = [:]

    var renderDistance: Int { didSet { if renderDistance != oldValue { rebuildOffsets() } } }
    /// Uploads a finished mesh (main thread, with the GL context current).
    var uploadMesh: (MeshPayload) -> GPUMesh? = { _ in nil }
    /// Frees a mesh's GL objects.
    var releaseMesh: (GPUMesh) -> Void = { _ in }

    init(registry: BlockRegistry, generator: WorldGenerator, storage: WorldStorage?, worldID: String?, jobs: WinJobSystem, renderDistance: Int) {
        self.registry = registry
        self.generator = generator
        self.storage = storage
        self.worldID = worldID
        self.jobs = jobs
        self.renderDistance = renderDistance
        rebuildOffsets()
    }

    private func rebuildOffsets() {
        let r = Int32(renderDistance + 2)
        var list: [(Int32, Int32)] = []
        for dz in -r...r { for dx in -r...r where dx * dx + dz * dz <= r * r + r { list.append((dx, dz)) } }
        list.sort { ($0.0 * $0.0 + $0.1 * $0.1) < ($1.0 * $1.0 + $1.1 * $1.1) }
        offsets = list
    }

    // MARK: Block access

    func blockIfLoaded(_ x: Int, _ y: Int, _ z: Int) -> BlockID? {
        guard y >= 0 && y < WorldConst.height else { return Blocks.air }
        guard let s = slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))] else { return nil }
        return s.chunk.block(x & 15, y, z & 15)
    }

    func block(_ x: Int, _ y: Int, _ z: Int) -> BlockID { blockIfLoaded(x, y, z) ?? Blocks.air }
    func block(_ p: BlockPos) -> BlockID { block(Int(p.x), Int(p.y), Int(p.z)) }
    func isLoaded(_ x: Int, _ z: Int) -> Bool { slots[ChunkPos(Int32(x >> 4), Int32(z >> 4))] != nil }

    @discardableResult
    func setBlock(_ p: BlockPos, _ id: BlockID) -> Bool {
        guard p.y >= 0 && p.y < Int32(WorldConst.height), let s = slots[p.chunk] else { return false }
        let lx = Int(p.x) & 15, lz = Int(p.z) & 15
        guard s.chunk.block(lx, Int(p.y), lz) != id else { return false }
        s.chunk.set(lx, Int(p.y), lz, id)
        for dz: Int32 in -1...1 {
            for dx: Int32 in -1...1 {
                if let n = slots[ChunkPos(p.chunk.x + dx, p.chunk.z + dz)] {
                    n.needsMesh = true
                    n.urgentMesh = true
                }
            }
        }
        return true
    }

    func findStandingY(_ x: Int, _ z: Int, near: Int) -> Int? {
        guard isLoaded(x, z) else { return nil }
        func ok(_ y: Int) -> Bool {
            guard y > 0, y < WorldConst.height - 2 else { return false }
            let below = block(x, y - 1, z), feet = block(x, y, z), head = block(x, y + 1, z)
            return registry.isSolid[Int(below)] && !registry.isSolid[Int(feet)] && !registry.isSolid[Int(head)]
                && registry.shape[Int(feet)] != .liquid && registry.shape[Int(head)] != .liquid
        }
        for d in 0..<WorldConst.height {
            if ok(near + d) { return near + d }
            if d > 0 && ok(near - d) { return near - d }
        }
        return nil
    }

    // MARK: Streaming

    func update(focus: DVec3, now: Double, budget: Double = 0.006) {
        center = ChunkPos(Int32(floor(focus.x / 16)), Int32(floor(focus.z / 16)))
        integrate(now: now, deadline: Date.timeIntervalSinceReferenceDate + budget)
        unloadDistant()
        scheduleGeneration()
        scheduleMeshing()
    }

    private func integrate(now: Double, deadline: Double) {
        inbox.lock.lock()
        let meshed = inbox.meshed
        var generated = inbox.generated
        inbox.meshed.removeAll(keepingCapacity: true)
        inbox.generated.removeAll(keepingCapacity: true)
        inbox.lock.unlock()

        for (pos, token, payload) in meshed {
            inFlightMeshes = max(0, inFlightMeshes - 1)
            guard let s = slots[pos] else { continue }
            s.meshInFlight = false
            guard token == s.meshToken else { continue }
            if let old = s.mesh { releaseMesh(old) }
            s.mesh = uploadMesh(payload)
            if s.firstMeshTime < 0 { s.firstMeshTime = now }
        }

        var index = 0
        let radius = Int32(renderDistance + 2)
        while index < generated.count {
            let chunk = generated[index]
            index += 1
            pendingGeneration.remove(chunk.pos)
            let dx = chunk.pos.x - center.x, dz = chunk.pos.z - center.z
            if dx * dx + dz * dz > (radius + 1) * (radius + 1) && !chunk.needsSave { continue }
            guard slots[chunk.pos] == nil else { continue }
            slots[chunk.pos] = Slot(chunk: chunk)
            for dz2: Int32 in -1...1 {
                for dx2: Int32 in -1...1 where !(dx2 == 0 && dz2 == 0) {
                    slots[ChunkPos(chunk.pos.x + dx2, chunk.pos.z + dz2)]?.needsMesh = true
                }
            }
            if Date.timeIntervalSinceReferenceDate > deadline { break }
        }
        if index < generated.count {
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
            if let mesh = s.mesh { releaseMesh(mesh) }
            if s.chunk.needsSave { saveChunk(s.chunk) }
        }
    }

    private func scheduleGeneration() {
        if let remoteRequest {
            let now = Date.timeIntervalSinceReferenceDate
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
            let generator = self.generator, storage = self.storage, worldID = self.worldID, inbox = self.inbox
            let folder = generator.dimension.storageFolder
            jobs.submit(priority: Int(dx * dx + dz * dz) * 4, group: jobGroup) { _ in
                guard !inbox.cancelled else { return }
                let saved = worldID.flatMap { id in storage?.loadChunk(worldID: id, pos: pos, dimension: folder) }
                let chunk = saved ?? generator.generate(pos)
                inbox.lock.lock()
                inbox.generated.append(chunk)
                inbox.lock.unlock()
            }
        }
    }

    private func scheduleMeshing() {
        let maxInFlight = jobs.workerCount * 2
        let r = Int32(renderDistance)
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
        let token = s.meshToken, inbox = self.inbox
        jobs.submit(priority: priority, group: jobGroup) { mesher in
            mesher.build(neighborhood: hood)
            let payload = MeshPayload(buffers: mesher.out, maxY: hood[4].maxHeight)
            inbox.lock.lock()
            inbox.meshed.append((pos, token, payload))
            inbox.lock.unlock()
        }
    }

    /// How many chunks within `radius` of `pos` are loaded and meshed.
    func readiness(around pos: ChunkPos, radius: Int32) -> (meshed: Int, total: Int) {
        var m = 0, t = 0
        for dz in -radius...radius {
            for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                t += 1
                if slots[ChunkPos(pos.x + dx, pos.z + dz)]?.firstMeshTime ?? -1 >= 0 { m += 1 }
            }
        }
        return (m, t)
    }

    // MARK: Multiplayer

    /// Integrates a chunk sent by the host.
    func receiveRemoteChunk(_ chunk: Chunk) {
        remoteRequestedAt[chunk.pos] = nil
        if let existing = slots[chunk.pos] {
            existing.chunk.blocks.update(from: chunk.blocks, count: WorldConst.blocksPerChunk)
            existing.chunk.recomputeHeights()
            for dz: Int32 in -1...1 {
                for dx: Int32 in -1...1 { slots[ChunkPos(chunk.pos.x + dx, chunk.pos.z + dz)]?.needsMesh = true }
            }
            return
        }
        inbox.lock.lock()
        inbox.generated.append(chunk)
        inbox.lock.unlock()
    }

    /// Drops every chunk (the host moved to another dimension).
    func resetRemote() {
        for (_, s) in slots { if let mesh = s.mesh { releaseMesh(mesh) } }
        slots.removeAll()
        pendingGeneration.removeAll()
        remoteRequestedAt.removeAll()
        inbox.lock.lock()
        inbox.generated.removeAll()
        inbox.meshed.removeAll()
        inbox.lock.unlock()
        inFlightMeshes = 0
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
            }
        }
    }

    @discardableResult
    func saveModifiedChunks() -> Int {
        var n = 0
        for (_, s) in slots where s.chunk.needsSave {
            saveChunk(s.chunk)
            n += 1
        }
        return n
    }

    func shutdown() {
        inbox.cancelled = true
        jobs.cancel(group: jobGroup)
        saveModifiedChunks()
        storage?.ioQueue.sync {}
        for (_, s) in slots { if let mesh = s.mesh { releaseMesh(mesh) } }
        slots.removeAll()
    }
}
