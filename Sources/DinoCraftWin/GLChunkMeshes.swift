import Foundation
import DinoCraftCore
@testable import DinoCraftGame

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
final class GPUMesh: ChunkMeshHandle {
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

    var memoryBytes: Int { (opaqueQuads + cutoutQuads + translucentQuads) * 4 * MemoryLayout<ChunkVertex>.stride }
}

/// Lets the shared world build chunk meshes for OpenGL: workers copy the geometry out,
/// and the main thread uploads it (OpenGL calls must stay on the thread that owns the context).
final class GLChunkMeshFactory: ChunkMeshFactory {
    private unowned let renderer: WinRenderer

    init(renderer: WinRenderer) { self.renderer = renderer }

    func prepare(buffers: MeshBuffers, maxY: Int, label: String) -> PreparedChunkMesh {
        MeshPayload(buffers: buffers, maxY: maxY)
    }

    func finish(_ prepared: PreparedChunkMesh) -> ChunkMeshHandle? {
        guard let payload = prepared as? MeshPayload else { return nil }
        return renderer.makeMesh(payload)
    }

    func release(_ mesh: ChunkMeshHandle) {
        if let mesh = mesh as? GPUMesh { renderer.deleteMesh(mesh) }
    }

    var clock: Double { Date.timeIntervalSinceReferenceDate }
}

extension JobSystem {
    /// Worker threads for terrain generation and meshing, each with its own chunk mesher.
    static func forWindows(blocks: BlockRegistry, fancyLeaves: Bool) -> JobSystem {
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        return JobSystem(workerCount: workers) { index in
            let mesher = ChunkMesher(registry: blocks)
            mesher.fancyLeaves = fancyLeaves
            return WorkerContext(index: index, mesher: mesher)
        }
    }
}
