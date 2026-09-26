import Foundation
import Metal
import QuartzCore
import DinoCraftCore
@testable import DinoCraftGame

/// GPU mesh for one chunk: a single shared-storage buffer holding the opaque,
/// cutout and translucent vertex segments back to back.
final class ChunkMesh: ChunkMeshHandle {
    let buffer: MTLBuffer?
    let opaqueQuads: Int
    let cutoutQuads: Int
    let translucentQuads: Int
    let cutoutOffset: Int
    let translucentOffset: Int
    let maxY: Int

    init(device: MTLDevice, buffers: MeshBuffers, maxY: Int, label: String) {
        let o = buffers.opaque.count, c = buffers.cutout.count, t = buffers.translucent.count
        let stride = MemoryLayout<ChunkVertex>.stride
        opaqueQuads = o / 4; cutoutQuads = c / 4; translucentQuads = t / 4
        cutoutOffset = o * stride
        translucentOffset = (o + c) * stride
        self.maxY = maxY
        let total = (o + c + t) * stride
        if total > 0, let buf = device.makeBuffer(length: total, options: [.storageModeShared, .cpuCacheModeWriteCombined]) {
            let dst = buf.contents()
            buffers.opaque.withUnsafeBytes { dst.copyMemory(from: $0.baseAddress!, byteCount: $0.count) }
            buffers.cutout.withUnsafeBytes { if $0.count > 0 { (dst + o * stride).copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
            buffers.translucent.withUnsafeBytes { if $0.count > 0 { (dst + (o + c) * stride).copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
            buf.label = label
            buffer = buf
        } else {
            buffer = nil
        }
    }

    var memoryBytes: Int { buffer?.length ?? 0 }
}

/// Builds chunk meshes straight into shared-storage Metal buffers on the worker threads.
final class MetalChunkMeshFactory: ChunkMeshFactory {
    let device: MTLDevice

    init(device: MTLDevice) { self.device = device }

    func prepare(buffers: MeshBuffers, maxY: Int, label: String) -> PreparedChunkMesh {
        ChunkMesh(device: device, buffers: buffers, maxY: maxY, label: label)
    }

    func finish(_ prepared: PreparedChunkMesh) -> ChunkMeshHandle? { prepared as? ChunkMesh }

    func release(_ mesh: ChunkMeshHandle) {}

    var clock: Double { CACurrentMediaTime() }
}
