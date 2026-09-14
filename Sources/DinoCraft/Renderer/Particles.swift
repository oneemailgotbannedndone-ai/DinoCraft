import Foundation
import Metal
import simd
import DinoCraftCore

struct ParticleVertex {
    var px: Float, py: Float, pz: Float
    var u: Float, v: Float
    var r: Float, g: Float, b: Float, a: Float
    var layer: Float, sky: Float, block: Float, emissive: Float
}

struct Particle {
    var position: DVec3
    var velocity: DVec3
    var life: Float
    var maxLife: Float
    var size: Float
    var color: SIMD4<Float>
    /// Block texture layer (debris), -1 for a soft round dot, -2 for a hard square.
    var layer: Float = -1
    var uv = SIMD2<Float>(0, 0)
    var uvSize: Float = 1
    var gravity: Float = 0
    var drag: Float = 0
    var emissive = false
    var collide = false
    var fade = true
    var shrink = false

    init(_ position: DVec3, _ velocity: DVec3, life: Float, size: Float, color: SIMD4<Float>) {
        self.position = position
        self.velocity = velocity
        self.life = life
        self.maxLife = life
        self.size = size
        self.color = color
    }
}

/// Short-lived visual effects: block debris, mining chips, torch flames and
/// smoke, lava embers, portal sparkles, glowing motes, rain splashes and
/// dimension ash. Rain streaks and snowflakes are drawn by `ParticleRenderer`.
final class ParticleSystem {
    private(set) var particles: [Particle] = []
    private let maxParticles = 6000
    private var ambientTimer = 0.0
    /// Emitting blocks near the camera, rescanned twice a second so every torch flickers steadily.
    private var emitters: [(Int, Int, Int, BlockID)] = []
    private var scanTimer = 0.0
    private var splashBudget = 0.0

    func clear() { particles.removeAll() }

    func emit(_ p: Particle) {
        if particles.count < maxParticles { particles.append(p) }
    }

    // MARK: Emitters

    func blockBroken(_ pos: BlockPos, id: BlockID, blocks: BlockRegistry) {
        guard let info = blocks[id], info.shape != .none, info.shape != .liquid else { return }
        let layer = Float(blocks.faceLayers[Int(id) * 6])
        let origin = DVec3(Double(pos.x), Double(pos.y), Double(pos.z))
        for _ in 0..<30 {
            let local = DVec3(Double.random(in: 0.1...0.9), Double.random(in: 0.1...0.9), Double.random(in: 0.1...0.9))
            let push = (local - DVec3(0.5, 0.35, 0.5)) * 3.4 + DVec3(0, Double.random(in: 1.2...3.2), 0)
            var p = Particle(origin + local, push, life: Float.random(in: 0.55...1.2), size: Float.random(in: 0.07...0.13), color: SIMD4(1, 1, 1, 1))
            p.layer = layer
            p.uv = SIMD2(Float.random(in: 0...0.75), Float.random(in: 0...0.75))
            p.uvSize = 0.25
            p.gravity = 18
            p.drag = 0.6
            p.collide = true
            p.fade = false
            p.shrink = true
            p.emissive = info.emission > 8
            emit(p)
        }
    }

    func blockHit(_ pos: BlockPos, id: BlockID, blocks: BlockRegistry, eye: DVec3) {
        guard let info = blocks[id], info.shape != .none else { return }
        let center = DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.5, Double(pos.z) + 0.5)
        let toEye = eye - center
        let onFace = center + (simd_length(toEye) > 0.01 ? simd_normalize(toEye) * 0.55 : .zero)
        for _ in 0..<4 {
            let jitter = DVec3(Double.random(in: -0.3...0.3), Double.random(in: -0.3...0.3), Double.random(in: -0.3...0.3))
            var p = Particle(onFace + jitter, DVec3(Double.random(in: -1.5...1.5), Double.random(in: 0.5...2.5), Double.random(in: -1.5...1.5)),
                             life: Float.random(in: 0.3...0.6), size: 0.06, color: SIMD4(1, 1, 1, 1))
            p.layer = Float(blocks.faceLayers[Int(id) * 6])
            p.uv = SIMD2(Float.random(in: 0...0.8), Float.random(in: 0...0.8))
            p.uvSize = 0.2
            p.gravity = 16
            p.collide = true
            p.fade = false
            p.shrink = true
            emit(p)
        }
    }

    // MARK: Simulation

    func update(dt: Double, session s: GameSession, blocks: BlockRegistry) {
        guard dt > 0 else { return }
        let world = s.world
        let solid = blocks.isSolid
        let f = Float(dt)
        var i = 0
        while i < particles.count {
            var p = particles[i]
            p.life -= f
            if p.life <= 0 {
                particles.swapAt(i, particles.count - 1)
                particles.removeLast()
                continue
            }
            p.velocity.y -= Double(p.gravity) * dt
            p.velocity *= max(0, 1 - Double(p.drag) * dt)
            let next = p.position + p.velocity * dt
            if p.collide, let id = world.blockIfLoaded(Int(floor(next.x)), Int(floor(next.y)), Int(floor(next.z))), solid[Int(id)] {
                p.velocity = DVec3(p.velocity.x * 0.3, 0, p.velocity.z * 0.3)
            } else {
                p.position = next
            }
            particles[i] = p
            i += 1
        }
        ambient(dt: dt, session: s, blocks: blocks)
    }

    private func ambient(dt: Double, session s: GameSession, blocks: BlockRegistry) {
        let world = s.world
        let eye = s.player.eyePosition

        // Rain splashes where drops land near the player.
        if s.dimension == .overworld, s.weather.intensity > 0.2, WeatherSystem.precipitation(for: s.biome) == .rain {
            splashBudget += dt * 45 * Double(s.weather.intensity)
            while splashBudget >= 1 {
                splashBudget -= 1
                let x = Int(floor(eye.x)) + Int.random(in: -9...9), z = Int(floor(eye.z)) + Int.random(in: -9...9)
                guard let slot = world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4))) else { continue }
                let ground = Double(slot.chunk.heightMap[(z & 15) * 16 + (x & 15)])
                guard abs(ground - eye.y) < 16 else { continue }
                let spot = DVec3(Double(x) + Double.random(in: 0...1), ground + 0.05, Double(z) + Double.random(in: 0...1))
                for _ in 0..<2 {
                    var p = Particle(spot, DVec3(Double.random(in: -0.8...0.8), Double.random(in: 1...2.2), Double.random(in: -0.8...0.8)),
                                     life: 0.28, size: 0.04, color: SIMD4(0.75, 0.82, 0.95, 0.8))
                    p.gravity = 14
                    emit(p)
                }
            }
        }

        ambientTimer -= dt
        guard ambientTimer <= 0 else { return }
        ambientTimer = 0.1

        if s.dimension == .underworld {
            for _ in 0..<5 {
                var p = Particle(eye + DVec3(Double.random(in: -14...14), Double.random(in: -6...10), Double.random(in: -14...14)),
                                 DVec3(Double.random(in: -0.3...0.3), -0.35, Double.random(in: -0.3...0.3)),
                                 life: 5, size: 0.035, color: SIMD4(0.55, 0.5, 0.5, 0.8))
                p.layer = -2
                emit(p)
            }
        } else if s.dimension == .skylands {
            for _ in 0..<2 {
                var p = Particle(eye + DVec3(Double.random(in: -12...12), Double.random(in: -6...6), Double.random(in: -12...12)),
                                 DVec3(0, Double.random(in: 0.1...0.35), 0), life: 4, size: 0.05, color: SIMD4(1, 0.8, 0.4, 0.8))
                p.emissive = true
                emit(p)
            }
        }

        scanTimer -= 0.1
        if scanTimer <= 0 {
            scanTimer = 0.5
            rescanEmitters(world: world, eye: eye)
        }
        let wallOffsets: [(Double, Double)] = [(0, -1), (1, 0), (0, 1), (-1, 0)]
        for (x, y, z, id) in emitters {
            let base = DVec3(Double(x), Double(y), Double(z))
            if id == Blocks.torch || Blocks.wallTorch.contains(id) {
                guard Int.random(in: 0..<2) == 0 else { continue }
                var tip = base + DVec3(0.5, 0.72, 0.5)
                if let wall = Blocks.wallTorch.firstIndex(of: id) {
                    let (ox, oz) = wallOffsets[wall]
                    tip = base + DVec3(0.5 + ox * 0.19, 0.9, 0.5 + oz * 0.19)
                }
                var flame = Particle(tip, DVec3(0, Double.random(in: 0.15...0.35), 0), life: 0.45, size: 0.06, color: SIMD4(1, 0.72, 0.3, 1))
                flame.emissive = true
                flame.shrink = true
                emit(flame)
                if Int.random(in: 0..<3) == 0 {
                    var smoke = Particle(tip + DVec3(0, 0.15, 0), DVec3(Double.random(in: -0.08...0.08), 0.55, Double.random(in: -0.08...0.08)),
                                         life: 1.6, size: 0.07, color: SIMD4(0.35, 0.35, 0.38, 0.55))
                    smoke.drag = 0.4
                    emit(smoke)
                }
            } else if id == Blocks.lava, Int.random(in: 0..<14) == 0 {
                var ember = Particle(base + DVec3(Double.random(in: 0.2...0.8), 1.02, Double.random(in: 0.2...0.8)),
                                     DVec3(Double.random(in: -0.8...0.8), Double.random(in: 2.5...4.5), Double.random(in: -0.8...0.8)),
                                     life: 1.4, size: 0.06, color: SIMD4(1, 0.5, 0.15, 1))
                ember.gravity = 6
                ember.emissive = true
                ember.shrink = true
                ember.collide = true
                emit(ember)
            } else if id == Blocks.underworldPortal || id == Blocks.skylandsPortal, Int.random(in: 0..<3) == 0 {
                let tint: SIMD4<Float> = id == Blocks.underworldPortal ? SIMD4(1, 0.35, 0.45, 1) : SIMD4(1, 0.8, 0.35, 1)
                var spark = Particle(base + DVec3(Double.random(in: 0...1), Double.random(in: 0...1), Double.random(in: 0...1)),
                                     DVec3(Double.random(in: -0.4...0.4), Double.random(in: -0.2...0.6), Double.random(in: -0.4...0.4)),
                                     life: 1.2, size: 0.05, color: tint)
                spark.emissive = true
                emit(spark)
            } else if id == Blocks.glowMushroom || id == Blocks.emberCrystal || id == Blocks.amberLantern, Int.random(in: 0..<8) == 0 {
                let tint: SIMD4<Float> = id == Blocks.glowMushroom ? SIMD4(0.4, 1, 0.9, 0.9) : SIMD4(1, 0.65, 0.25, 0.9)
                var mote = Particle(base + DVec3(Double.random(in: 0.2...0.8), Double.random(in: 0.3...1.0), Double.random(in: 0.2...0.8)),
                                    DVec3(Double.random(in: -0.1...0.1), Double.random(in: 0.08...0.25), Double.random(in: -0.1...0.1)),
                                    life: 2.5, size: 0.035, color: tint)
                mote.emissive = true
                emit(mote)
            }
        }
    }

    private func rescanEmitters(world: World, eye: DVec3) {
        emitters.removeAll(keepingCapacity: true)
        let bx = Int(floor(eye.x)), by = Int(floor(eye.y)), bz = Int(floor(eye.z))
        for y in (by - 8)...(by + 8) {
            for z in (bz - 14)...(bz + 14) {
                for x in (bx - 14)...(bx + 14) {
                    guard let id = world.blockIfLoaded(x, y, z), id != Blocks.air else { continue }
                    let wanted: Bool
                    if id == Blocks.lava {
                        wanted = world.blockIfLoaded(x, y + 1, z) == Blocks.air
                    } else {
                        wanted = id == Blocks.torch || Blocks.wallTorch.contains(id) || id == Blocks.underworldPortal || id == Blocks.skylandsPortal
                            || id == Blocks.glowMushroom || id == Blocks.emberCrystal || id == Blocks.amberLantern
                    }
                    guard wanted else { continue }
                    emitters.append((x, y, z, id))
                    if emitters.count >= 500 { return }
                }
            }
        }
    }
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
