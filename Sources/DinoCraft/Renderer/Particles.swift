import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

struct ParticleVertex {
    var px: Float, py: Float, pz: Float
    var u: Float, v: Float
    var r: Float, g: Float, b: Float, a: Float
    var layer: Float, sky: Float, block: Float, emissive: Float
}

/// Draws particles plus rain streaks and snowflakes as camera-facing quads in one call.
final class ParticleRenderer {
    private let renderer: Renderer
    private let pipeline: MTLRenderPipelineState
    private var buffers: [MTLBuffer] = []
    private var next = 0
    private let maxQuads = 16_000
    private(set) var lastQuadCount = 0

    init(renderer: Renderer) throws {
        self.renderer = renderer
        guard let vertex = renderer.library.makeFunction(name: "particle_vertex"),
              let fragment = renderer.library.makeFunction(name: "particle_fragment") else {
            throw Renderer.RendererError.resource("Particle shader functions not found")
        }
        let vd = MTLVertexDescriptor()
        let attrs: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float2, 12), (.float4, 20), (.float4, 36)]
        for (i, (format, offset)) in attrs.enumerated() {
            vd.attributes[i].format = format
            vd.attributes[i].offset = offset
            vd.attributes[i].bufferIndex = 0
        }
        vd.layouts[0].stride = MemoryLayout<ParticleVertex>.stride
        let d = MTLRenderPipelineDescriptor()
        d.label = "Particles"
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = renderer.colorFormat
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .one
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d.depthAttachmentPixelFormat = renderer.depthFormat
        do {
            pipeline = try renderer.device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw Renderer.RendererError.pipeline("Particles", error)
        }
        guard MemoryLayout<ParticleVertex>.stride == 52 else { throw Renderer.RendererError.resource("ParticleVertex layout mismatch") }
        for _ in 0..<3 {
            guard let b = renderer.device.makeBuffer(length: maxQuads * 4 * MemoryLayout<ParticleVertex>.stride, options: .storageModeShared) else {
                throw Renderer.RendererError.resource("Could not allocate particle buffers")
            }
            b.label = "Particles"
            buffers.append(b)
        }
    }

    @inline(__always) private static func hash(_ x: Int, _ z: Int, _ k: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: (x &* 73_856_093) ^ (z &* 19_349_663) ^ (k &* 83_492_791))
        h ^= h >> 13
        h = h &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }

    func encode(_ enc: MTLRenderCommandEncoder, particles: ParticleSystem, session s: GameSession, world: World, camera: Camera,
                frame: inout FrameUniforms, time: Double) {
        let buffer = buffers[next]
        next = (next + 1) % buffers.count
        let out = buffer.contents().bindMemory(to: ParticleVertex.self, capacity: maxQuads * 4)
        var quads = 0

        let yaw = Float(camera.yaw), pitch = Float(camera.pitch)
        let forward = SIMD3<Float>(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
        let flatRight = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
        let crossRight = simd_cross(forward, SIMD3(0, 1, 0))
        let right = simd_length(crossRight) > 0.05 ? simd_normalize(crossRight) : flatRight
        let up = simd_cross(right, forward)

        func quad(_ c: SIMD3<Float>, _ rx: SIMD3<Float>, _ uy: SIMD3<Float>, uv: SIMD2<Float>, uvSize: Float, color: SIMD4<Float>,
                  layer: Float, sky: Float, block: Float, emissive: Bool) {
            guard quads < maxQuads else { return }
            let base = quads * 4
            let corners: [(SIMD3<Float>, SIMD2<Float>)] = [
                (c - rx - uy, SIMD2(uv.x, uv.y + uvSize)), (c + rx - uy, SIMD2(uv.x + uvSize, uv.y + uvSize)),
                (c + rx + uy, SIMD2(uv.x + uvSize, uv.y)), (c - rx + uy, uv),
            ]
            for (k, corner) in corners.enumerated() {
                out[base + k] = ParticleVertex(px: corner.0.x, py: corner.0.y, pz: corner.0.z, u: corner.1.x, v: corner.1.y,
                                               r: color.x, g: color.y, b: color.z, a: color.w,
                                               layer: layer, sky: sky, block: block, emissive: emissive ? 1 : 0)
            }
            quads += 1
        }

        for p in particles.particles {
            let rel = SIMD3<Float>(Float(p.position.x - camera.position.x), Float(p.position.y - camera.position.y),
                                   Float(p.position.z - camera.position.z))
            guard simd_length_squared(rel) < 64 * 64 else { continue }
            let t = p.life / p.maxLife
            let size = p.shrink ? p.size * max(0.25, t) : p.size
            var color = p.color
            if p.fade { color.w *= min(1, t * 2.5) }
            let light = p.emissive ? (sky: Float(1), block: Float(1)) : world.light(at: p.position)
            quad(rel, right * size, up * size, uv: p.uv, uvSize: p.uvSize, color: color, layer: p.layer,
                 sky: light.sky, block: light.block, emissive: p.emissive)
        }

        // Arrows: a crossed shaft with a grey tip and pale fletching, pointing along their flight.
        for a in s.arrows.arrows where !a.done {
            let rel = SIMD3<Float>(Float(a.position.x - camera.position.x), Float(a.position.y - camera.position.y),
                                   Float(a.position.z - camera.position.z))
            guard simd_length_squared(rel) < 64 * 64 else { continue }
            var d = SIMD3<Float>(Float(a.velocity.x), Float(a.velocity.y), Float(a.velocity.z))
            let len = simd_length(d)
            guard len > 0.001 else { continue }
            d /= len
            let across = simd_cross(d, SIMD3(0, 1, 0))
            let s0 = simd_length(across) > 0.05 ? simd_normalize(across) : SIMD3<Float>(1, 0, 0)
            let s1 = simd_normalize(simd_cross(d, s0))
            let light = world.light(at: a.position)
            let center = rel - d * 0.3
            for side in [s0, s1] {
                quad(center, side * 0.018, d * 0.3, uv: .zero, uvSize: 1, color: SIMD4(0.52, 0.36, 0.2, 1), layer: -2,
                     sky: light.sky, block: light.block, emissive: false)
                quad(rel - d * 0.04, side * 0.032, d * 0.04, uv: .zero, uvSize: 1, color: SIMD4(0.42, 0.43, 0.47, 1), layer: -2,
                     sky: light.sky, block: light.block, emissive: false)
                quad(center - d * 0.24, side * 0.05, d * 0.07, uv: .zero, uvSize: 1, color: SIMD4(0.93, 0.92, 0.88, 1), layer: -2,
                     sky: light.sky, block: light.block, emissive: false)
            }
        }

        // Weather around the camera (overworld only).
        let strength = s.weather.intensity
        let precipitation = WeatherSystem.precipitation(for: s.biome)
        if s.dimension == .overworld, strength > 0.02, precipitation != .none {
            let light = world.light(at: camera.position)
            let radius = precipitation == .snow ? 12 : 14
            let cx = Int(floor(camera.position.x)), cz = Int(floor(camera.position.z))
            let density = strength * (precipitation == .snow ? 0.5 : 0.85)
            for dz in -radius...radius {
                for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                    let x = cx + dx, z = cz + dz
                    guard ParticleRenderer.hash(x, z, 1) < density,
                          let slot = world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4))) else { continue }
                    let ground = Double(slot.chunk.heightMap[(z & 15) * 16 + (x & 15)])
                    let top = camera.position.y + 16, bottom = max(ground, camera.position.y - 12)
                    guard top > bottom else { continue }
                    let span = top - bottom
                    for k in 0..<2 {
                        let phase = Double(ParticleRenderer.hash(x, z, 7 + k)) * span
                        let jx = Double(ParticleRenderer.hash(x, z, 20 + k)), jz = Double(ParticleRenderer.hash(x, z, 30 + k))
                        let wx = Double(x) + jx - camera.position.x, wz = Double(z) + jz - camera.position.z
                        if precipitation == .rain {
                            let y = top - (time * 15 + phase).truncatingRemainder(dividingBy: span)
                            let c = SIMD3<Float>(Float(wx), Float(y - camera.position.y), Float(wz))
                            quad(c, flatRight * 0.032, SIMD3(0, 0.5, 0), uv: .zero, uvSize: 1,
                                 color: SIMD4(0.78, 0.84, 0.95, 0.72 * strength), layer: -2, sky: light.sky, block: light.block, emissive: false)
                        } else {
                            let y = top - (time * 1.7 + phase).truncatingRemainder(dividingBy: span)
                            let sway = Float(sin(time * 1.3 + phase)) * 0.35
                            let c = SIMD3<Float>(Float(wx) + sway, Float(y - camera.position.y), Float(wz) + sway * 0.6)
                            quad(c, right * 0.055, up * 0.055, uv: .zero, uvSize: 1,
                                 color: SIMD4(1, 1, 1, 0.9 * strength), layer: -1, sky: max(0.6, light.sky), block: light.block, emissive: false)
                        }
                    }
                }
            }
        }

        lastQuadCount = quads
        guard quads > 0 else { return }
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(renderer.depthReadOnly)
        enc.setCullMode(.none)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentTexture(renderer.blockTextures.texture, index: 0)
        enc.setFragmentSamplerState(renderer.nearestSampler, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: quads * 6, indexType: .uint32, indexBuffer: renderer.quadIndices, indexBufferOffset: 0)
        enc.setCullMode(.back)
        enc.setDepthStencilState(renderer.depthWrite)
    }
}
