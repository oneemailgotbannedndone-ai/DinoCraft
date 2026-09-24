import Foundation
import Metal
import QuartzCore
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Encodes the voxel world: frustum-culled opaque and cutout chunk passes,
/// the procedural sky (drawn only where no geometry was written), then
/// back-to-front translucent chunks.
final class WorldRenderer {
    let renderer: Renderer

    struct Stats {
        var visibleChunks = 0
        var drawCalls = 0
        var quads = 0
    }
    private(set) var stats = Stats()

    private struct Visible {
        let slot: World.Slot
        let mesh: ChunkMesh
        var uniforms: ChunkUniforms
        let distanceSq: Double
    }
    private var visible: [Visible] = []

    init(renderer: Renderer) {
        self.renderer = renderer
        visible.reserveCapacity(2048)
    }

    /// Fills the camera- and sky-dependent parts of the frame uniforms.
    func prepareUniforms(_ u: inout FrameUniforms, camera: Camera, aspect: Float, sky: SkyState, time: Double,
                         renderDistance: Int, brightness: Double, underwater: Bool, clouds: Bool, drawableSize: SIMD2<Float>,
                         dimension: WorldDimension = .overworld) {
        let viewProj = camera.viewProjection(aspect: aspect)
        u.viewProj = viewProj
        u.invViewProj = viewProj.inverse
        u.cameraPosTime = SIMD4(Float(camera.position.x.truncatingRemainder(dividingBy: 65536)),
                                Float(camera.position.y),
                                Float(camera.position.z.truncatingRemainder(dividingBy: 65536)),
                                Float(time.truncatingRemainder(dividingBy: 3600)))
        u.sunDirDaylight = SIMD4(sky.sunDirection, sky.daylight)
        let fogEnd = Float(renderDistance * 16) - 6
        u.fogColorStart = SIMD4(sky.horizon, fogEnd * 0.55)
        u.fogParams = SIMD4(fogEnd, underwater ? 1 : 0, Float(brightness), 0.42)
        u.skyZenith = SIMD4(sky.zenith, sky.stars)
        u.skyHorizon = SIMD4(sky.horizon, sky.sunsetGlow)
        u.skyLight = SIMD4(sky.skyLight, clouds ? 1 : 0)
        u.viewport = SIMD4(drawableSize.x, drawableSize.y, 1 / max(1, drawableSize.x), 1 / max(1, drawableSize.y))
        switch dimension {
        case .overworld, .toonland:
            u.dimension = SIMD4(0, 200, 1, 0)
        case .skylands:
            u.dimension = SIMD4(0.06, 22, 1, 0)
        case .underworld:
            u.dimension = SIMD4(0.32, 0, 0, 0)
            u.fogColorStart = SIMD4(sky.horizon, 6)
            u.fogParams.x = min(fogEnd, 104)
            u.skyLight.w = 0
        }
    }

    func encode(_ enc: MTLRenderCommandEncoder, world: World, camera: Camera, uniforms u: inout FrameUniforms) {
        let r = renderer
        let frustum = Frustum(viewProjection: u.viewProj)
        let now = CACurrentMediaTime()
        let maxDist = Double((world.renderDistance + 1) * 16)

        visible.removeAll(keepingCapacity: true)
        for (pos, slot) in world.slots {
            guard let mesh = slot.mesh as? ChunkMesh, mesh.buffer != nil else { continue }
            let ox = Double(pos.originX) - camera.position.x
            let oz = Double(pos.originZ) - camera.position.z
            let oy = -camera.position.y
            let cx = ox + 8, cz = oz + 8
            let d2 = cx * cx + cz * cz
            if d2 > maxDist * maxDist { continue }
            let minV = Vec3(Float(ox), Float(oy), Float(oz))
            let box = AABB(min: minV, max: minV + Vec3(16, Float(max(1, mesh.maxY)), 16))
            guard frustum.contains(box) else { continue }
            let fade = slot.firstMeshTime < 0 ? 1 : Float(min(1, (now - slot.firstMeshTime) / 0.7))
            let eased = 1 - (1 - fade) * (1 - fade)
            let uni = ChunkUniforms(
                origin: SIMD4(Float(ox), Float(oy), Float(oz), eased),
                worldOrigin: SIMD4(Float(Int(pos.originX) % 4096), 0, Float(Int(pos.originZ) % 4096), 0))
            visible.append(Visible(slot: slot, mesh: mesh, uniforms: uni, distanceSq: d2))
        }

        var drawCalls = 0, quads = 0
        enc.setFrontFacing(.counterClockwise)
        enc.setCullMode(.back)
        enc.setDepthStencilState(r.depthWrite)
        enc.setVertexBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentTexture(r.blockTextures.texture, index: 0)
        enc.setFragmentSamplerState(r.blockSampler, index: 0)

        // Opaque
        enc.setRenderPipelineState(r.chunkOpaque)
        for i in visible.indices where visible[i].mesh.opaqueQuads > 0 {
            let v = visible[i]
            enc.setVertexBuffer(v.mesh.buffer, offset: 0, index: 0)
            enc.setVertexBytes(&visible[i].uniforms, length: MemoryLayout<ChunkUniforms>.stride, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: v.mesh.opaqueQuads * 6, indexType: .uint32,
                                      indexBuffer: r.quadIndices, indexBufferOffset: 0)
            drawCalls += 1; quads += v.mesh.opaqueQuads
        }
        // Cutout (leaves, plants, glass)
        enc.setRenderPipelineState(r.chunkCutout)
        for i in visible.indices where visible[i].mesh.cutoutQuads > 0 {
            let v = visible[i]
            enc.setVertexBuffer(v.mesh.buffer, offset: v.mesh.cutoutOffset, index: 0)
            enc.setVertexBytes(&visible[i].uniforms, length: MemoryLayout<ChunkUniforms>.stride, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: v.mesh.cutoutQuads * 6, indexType: .uint32,
                                      indexBuffer: r.quadIndices, indexBufferOffset: 0)
            drawCalls += 1; quads += v.mesh.cutoutQuads
        }

        encodeSky(enc, uniforms: &u)

        // Translucent, far to near
        enc.setRenderPipelineState(r.chunkTranslucent)
        enc.setDepthStencilState(r.depthReadOnly)
        enc.setCullMode(.none)
        enc.setFragmentTexture(r.blockTextures.texture, index: 0)
        enc.setFragmentSamplerState(r.blockSampler, index: 0)
        let translucent = visible.indices.filter { visible[$0].mesh.translucentQuads > 0 }
            .sorted { visible[$0].distanceSq > visible[$1].distanceSq }
        for i in translucent {
            let v = visible[i]
            enc.setVertexBuffer(v.mesh.buffer, offset: v.mesh.translucentOffset, index: 0)
            enc.setVertexBytes(&visible[i].uniforms, length: MemoryLayout<ChunkUniforms>.stride, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: v.mesh.translucentQuads * 6, indexType: .uint32,
                                      indexBuffer: r.quadIndices, indexBufferOffset: 0)
            drawCalls += 1; quads += v.mesh.translucentQuads
        }
        enc.setCullMode(.back)
        enc.setDepthStencilState(r.depthWrite)

        stats = Stats(visibleChunks: visible.count, drawCalls: drawCalls + 1, quads: quads)
    }

    /// Sky only (used when no world is loaded).
    func encodeSky(_ enc: MTLRenderCommandEncoder, uniforms u: inout FrameUniforms) {
        enc.setRenderPipelineState(renderer.sky)
        enc.setDepthStencilState(renderer.depthSky)
        enc.setCullMode(.none)
        enc.setFragmentBytes(&u, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
