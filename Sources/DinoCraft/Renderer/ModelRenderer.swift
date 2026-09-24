import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

struct ModelVertex {
    var px: Float, py: Float, pz: Float
    var nx: Float, ny: Float, nz: Float
    var u: Float, v: Float
    var r: Float, g: Float, b: Float, a: Float
    var layer: Float, set: Float, cutout: Float, emissive: Float
}

struct ModelUniforms {
    var mvp: Mat4
    var model: Mat4
    var light: SIMD4<Float>
    var tint: SIMD4<Float>
    var viewPos: SIMD4<Float>
}

final class ModelMesh {
    let buffer: MTLBuffer
    let quads: Int

    init?(device: MTLDevice, vertices: [ModelVertex], label: String) {
        guard !vertices.isEmpty,
              let buf = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<ModelVertex>.stride,
                                          options: .storageModeShared) else { return nil }
        buf.label = "Model \(label)"
        buffer = buf
        quads = vertices.count / 4
    }
}

/// Geometry helpers for item and creature models.
enum ModelBuilder {
    static let setBlocks: Float = 0, setItems: Float = 1, setColor: Float = 2

    static func quad(_ out: inout [ModelVertex], _ p: [SIMD3<Float>], normal n: SIMD3<Float>, uv: [SIMD2<Float>],
                     color: SIMD4<Float> = SIMD4(1, 1, 1, 1), layer: Float, set: Float, cutout: Float, emissive: Float = 0) {
        for i in 0..<4 {
            out.append(ModelVertex(px: p[i].x, py: p[i].y, pz: p[i].z, nx: n.x, ny: n.y, nz: n.z, u: uv[i].x, v: uv[i].y,
                                   r: color.x, g: color.y, b: color.z, a: color.w, layer: layer, set: set, cutout: cutout, emissive: emissive))
        }
    }

    static let faceUV: [SIMD2<Float>] = [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]

    /// Corners of the six faces of an axis-aligned box, in BlockFace order (east, west, up, down, south, north).
    static func boxFaces(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>) -> [([SIMD3<Float>], SIMD3<Float>)] {
        [
            ([SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(hi.x, hi.y, hi.z)], SIMD3(1, 0, 0)),
            ([SIMD3(lo.x, lo.y, lo.z), SIMD3(lo.x, lo.y, hi.z), SIMD3(lo.x, hi.y, hi.z), SIMD3(lo.x, hi.y, lo.z)], SIMD3(-1, 0, 0)),
            ([SIMD3(lo.x, hi.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(lo.x, hi.y, lo.z)], SIMD3(0, 1, 0)),
            ([SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(lo.x, lo.y, hi.z)], SIMD3(0, -1, 0)),
            ([SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)], SIMD3(0, 0, 1)),
            ([SIMD3(hi.x, lo.y, lo.z), SIMD3(lo.x, lo.y, lo.z), SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z)], SIMD3(0, 0, -1)),
        ]
    }

    /// Unit cube centred on the origin, textured per face from the block texture array.
    static func cube(layer: (Int) -> Float, emissive: Float, cutout: Float) -> [ModelVertex] {
        var out: [ModelVertex] = []
        for (i, face) in boxFaces(SIMD3(repeating: -0.5), SIMD3(repeating: 0.5)).enumerated() {
            quad(&out, face.0, normal: face.1, uv: faceUV, layer: layer(i), set: setBlocks, cutout: cutout, emissive: emissive)
        }
        return out
    }

    /// Solid-coloured box (creature body parts, the player's arm).
    static func box(_ out: inout [ModelVertex], min lo: SIMD3<Float>, max hi: SIMD3<Float>, color: SIMD4<Float>, emissive: Float = 0) {
        for face in boxFaces(lo, hi) {
            quad(&out, face.0, normal: face.1, uv: faceUV, color: color, layer: 0, set: setColor, cutout: 0, emissive: emissive)
        }
    }

    /// A 1 × 1 sprite extruded to 1/16 thickness: front and back faces plus an
    /// edge wall for every opaque pixel bordering transparency.
    static func extruded(mask: [UInt8], size n: Int, layer: Float, set: Float) -> [ModelVertex] {
        var out: [ModelVertex] = []
        let t: Float = 1.0 / 16 / 2
        let px = 1 / Float(n)
        quad(&out, [SIMD3(-0.5, -0.5, t), SIMD3(0.5, -0.5, t), SIMD3(0.5, 0.5, t), SIMD3(-0.5, 0.5, t)], normal: SIMD3(0, 0, 1),
             uv: faceUV, layer: layer, set: set, cutout: 1)
        quad(&out, [SIMD3(0.5, -0.5, -t), SIMD3(-0.5, -0.5, -t), SIMD3(-0.5, 0.5, -t), SIMD3(0.5, 0.5, -t)], normal: SIMD3(0, 0, -1),
             uv: [SIMD2(1, 1), SIMD2(0, 1), SIMD2(0, 0), SIMD2(1, 0)], layer: layer, set: set, cutout: 1)
        func opaque(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < n && y < n && mask[y * n + x] > 127
        }
        for y in 0..<n {
            for x in 0..<n where opaque(x, y) {
                let x0 = -0.5 + Float(x) * px, x1 = x0 + px
                let y1 = 0.5 - Float(y) * px, y0 = y1 - px
                let uv = SIMD2<Float>((Float(x) + 0.5) * px, (Float(y) + 0.5) * px)
                let uvs = [uv, uv, uv, uv]
                if !opaque(x - 1, y) {
                    quad(&out, [SIMD3(x0, y0, -t), SIMD3(x0, y0, t), SIMD3(x0, y1, t), SIMD3(x0, y1, -t)], normal: SIMD3(-1, 0, 0),
                         uv: uvs, layer: layer, set: set, cutout: 0)
                }
                if !opaque(x + 1, y) {
                    quad(&out, [SIMD3(x1, y0, t), SIMD3(x1, y0, -t), SIMD3(x1, y1, -t), SIMD3(x1, y1, t)], normal: SIMD3(1, 0, 0),
                         uv: uvs, layer: layer, set: set, cutout: 0)
                }
                if !opaque(x, y - 1) {
                    quad(&out, [SIMD3(x0, y1, t), SIMD3(x1, y1, t), SIMD3(x1, y1, -t), SIMD3(x0, y1, -t)], normal: SIMD3(0, 1, 0),
                         uv: uvs, layer: layer, set: set, cutout: 0)
                }
                if !opaque(x, y + 1) {
                    quad(&out, [SIMD3(x0, y0, -t), SIMD3(x1, y0, -t), SIMD3(x1, y0, t), SIMD3(x0, y0, t)], normal: SIMD3(0, -1, 0),
                         uv: uvs, layer: layer, set: set, cutout: 0)
                }
            }
        }
        return out
    }
}

/// Renders dropped item entities in the world and the first-person held item / hand.
final class ModelRenderer {
    let renderer: Renderer
    let pipeline: MTLRenderPipelineState
    private var cache: [ItemID: ModelMesh] = [:]
    private var arm: ModelMesh?

    init(renderer: Renderer) throws {
        self.renderer = renderer
        precondition(MemoryLayout<ModelVertex>.stride == 64, "ModelVertex layout mismatch")
        precondition(MemoryLayout<ModelUniforms>.stride == 176, "ModelUniforms layout mismatch")
        let vd = MTLVertexDescriptor()
        let attrs: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float3, 12), (.float2, 24), (.float4, 32), (.float4, 48)]
        for (i, (f, o)) in attrs.enumerated() {
            vd.attributes[i].format = f
            vd.attributes[i].offset = o
            vd.attributes[i].bufferIndex = 0
        }
        vd.layouts[0].stride = MemoryLayout<ModelVertex>.stride
        let d = MTLRenderPipelineDescriptor()
        d.label = "Models"
        guard let vf = renderer.library.makeFunction(name: "model_vertex"),
              let ff = renderer.library.makeFunction(name: "model_fragment") else {
            throw Renderer.RendererError.resource("Model shader functions missing")
        }
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = renderer.colorFormat
        d.depthAttachmentPixelFormat = renderer.depthFormat
        pipeline = try renderer.device.makeRenderPipelineState(descriptor: d)

        var armVerts: [ModelVertex] = []
        let skin = SIMD4<Float>(0.80, 0.58, 0.42, 1), glove = SIMD4<Float>(0.36, 0.24, 0.16, 1), cuff = SIMD4<Float>(0.62, 0.42, 0.18, 1)
        ModelBuilder.box(&armVerts, min: SIMD3(-0.1, -0.1, -0.55), max: SIMD3(0.1, 0.1, -0.22), color: glove)
        ModelBuilder.box(&armVerts, min: SIMD3(-0.105, -0.105, -0.25), max: SIMD3(0.105, 0.105, -0.17), color: cuff)
        ModelBuilder.box(&armVerts, min: SIMD3(-0.095, -0.095, -0.17), max: SIMD3(0.095, 0.095, 0.4), color: skin)
        arm = ModelMesh(device: renderer.device, vertices: armVerts, label: "Arm")
    }

    func clearCache() { cache.removeAll() }

    func isCube(_ item: ItemInfo) -> Bool {
        guard let b = item.block, item.texture == nil else { return false }
        let shape = renderer.blockRegistry.shape[Int(b)]
        return shape != .cross && shape != .torch && shape != .wallTorch
    }

    func mesh(for item: ItemInfo) -> ModelMesh? {
        if let m = cache[item.id] { return m }
        let blocks = renderer.blockRegistry
        var verts: [ModelVertex] = []
        if let b = item.block, item.texture == nil, let info = blocks[b] {
            if isCube(item) {
                verts = ModelBuilder.cube(layer: { Float(blocks.faceLayers[Int(b) * 6 + $0]) },
                                          emissive: info.emission > 8 ? 1 : 0, cutout: info.layer == .opaque ? 0 : 1)
            } else {
                let layer = Int(blocks.faceLayers[Int(b) * 6])
                verts = ModelBuilder.extruded(mask: renderer.blockTextures.alphaMasks[layer], size: renderer.blockTextures.size,
                                              layer: Float(layer), set: ModelBuilder.setBlocks)
            }
        } else if let tex = item.texture {
            let layer = Int(renderer.itemTextures.layer(tex))
            verts = ModelBuilder.extruded(mask: renderer.itemTextures.alphaMasks[layer], size: renderer.itemTextures.size,
                                          layer: Float(layer), set: ModelBuilder.setItems)
        }
        guard let mesh = ModelMesh(device: renderer.device, vertices: verts, label: item.name) else { return nil }
        cache[item.id] = mesh
        return mesh
    }

    func begin(_ enc: MTLRenderCommandEncoder, _ frame: inout FrameUniforms) {
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(renderer.depthWrite)
        enc.setCullMode(.none)
        enc.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentTexture(renderer.blockTextures.texture, index: 0)
        enc.setFragmentTexture(renderer.itemTextures.texture, index: 1)
        enc.setFragmentSamplerState(renderer.nearestSampler, index: 0)
    }

    func draw(_ enc: MTLRenderCommandEncoder, _ mesh: ModelMesh, uniforms: inout ModelUniforms) {
        enc.setVertexBuffer(mesh.buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<ModelUniforms>.stride, index: 2)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: mesh.quads * 6, indexType: .uint32,
                                  indexBuffer: renderer.quadIndices, indexBufferOffset: 0)
    }

    /// Dropped items: spinning, bobbing, lit by the chunk light at their position.
    func encodeItems(_ enc: MTLRenderCommandEncoder, session: GameSession, camera: Camera, frame: inout FrameUniforms, time: Double) {
        let list = session.entities.items
        guard !list.isEmpty else { return }
        begin(enc, &frame)
        let maxDist = Float(session.world.renderDistance * 16)
        for e in list where !e.removed {
            let rel = SIMD3<Float>(Float(e.position.x - camera.position.x), Float(e.position.y - camera.position.y),
                                   Float(e.position.z - camera.position.z))
            guard simd_length(rel) < maxDist, let info = session.items[e.stack.item], let mesh = mesh(for: info) else { continue }
            let cube = isCube(info)
            let scale: Float = cube ? 0.25 : 0.42
            let bob = Float(sin((time + e.spinOffset) * 2.6)) * 0.06 + 0.08 + scale * 0.5
            let spin = Float(time * 1.7 + e.spinOffset)
            let copies = e.stack.count > 32 ? 3 : (e.stack.count > 1 ? 2 : 1)
            let light = session.world.light(at: e.position + DVec3(0, 0.25, 0))
            for k in 0..<copies {
                let offset = SIMD3<Float>(Float(k) * 0.06, Float(k) * 0.05, Float(k) * -0.05)
                let rotation = MathUtil.rotationY(spin) * MathUtil.scale(SIMD3(repeating: scale))
                let model = MathUtil.translation(rel + SIMD3(0, bob, 0) + offset) * rotation
                var u = ModelUniforms(mvp: frame.viewProj * model, model: rotation,
                                      light: SIMD4(light.sky, light.block, 0, 0), tint: .zero,
                                      viewPos: SIMD4(rel, 1))
                draw(enc, mesh, uniforms: &u)
            }
        }
    }

    /// First-person held item or bare arm, drawn into the nearest slice of the depth range.
    func encodeHand(_ enc: MTLRenderCommandEncoder, session s: GameSession, camera: Camera, frame: inout FrameUniforms,
                    aspect: Float, drawableSize: SIMD2<Float>, bobbing: Bool) {
        begin(enc, &frame)
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(drawableSize.x), height: Double(drawableSize.y), znear: 0.92, zfar: 1))
        let projection = MathUtil.perspectiveReverseZ(fovyRadians: 70 * .pi / 180, aspect: aspect, near: 0.05, far: 10)
        let light = s.world.light(at: s.player.eyePosition)
        let t = Float(s.swingProgress)
        let swingA = sin(t * .pi)
        let swingB = sin(sqrt(t) * .pi)
        let equip = Float(s.equipOffset)
        var bobX: Float = 0, bobY: Float = 0
        if bobbing {
            let phase = Float(s.bobPhase * .pi), amount = Float(s.bobAmount)
            bobX = sin(phase) * 0.018 * amount
            bobY = -abs(cos(phase)) * 0.022 * amount
        }
        let toWorld = camera.rotation.inverse
        let motion = s.hand.motion
        let handMotion = MathUtil.translation(motion.offset) * MathUtil.rotationZ(motion.roll) * MathUtil.rotationY(motion.yaw)
            * MathUtil.rotationX(motion.pitch)

        if let stack = s.inventory.selectedStack, let info = s.items[stack.item], let mesh = mesh(for: info) {
            var model: Mat4
            if isCube(info) {
                model = MathUtil.translation(SIMD3(0.5 + bobX - swingB * 0.18, -0.42 + bobY - equip * 0.6 + swingA * 0.12, -0.78 - swingA * 0.12))
                    * MathUtil.rotationX(-swingA * 0.9)
                    * MathUtil.rotationY(0.78)
                    * MathUtil.scale(SIMD3(repeating: 0.32))
            } else {
                model = MathUtil.translation(SIMD3(0.46 + bobX - swingB * 0.16, -0.36 + bobY - equip * 0.6 + swingA * 0.1, -0.7 - swingA * 0.1))
                    * MathUtil.rotationX(-swingA * 1.2)
                    * MathUtil.rotationY(-1.25)
                    * MathUtil.rotationZ(0.35)
                    * MathUtil.scale(SIMD3(repeating: 0.6))
            }
            model = handMotion * model
            var u = ModelUniforms(mvp: projection * model, model: toWorld * model,
                                  light: SIMD4(light.sky, light.block, 1, 0), tint: .zero, viewPos: .zero)
            draw(enc, mesh, uniforms: &u)
        } else if let arm {
            let model = handMotion * MathUtil.translation(SIMD3(0.52 + bobX - swingB * 0.2, -0.5 + bobY - equip * 0.5 + swingA * 0.16, -0.36 - swingA * 0.18))
                * MathUtil.rotationY(-0.28)
                * MathUtil.rotationX(0.45 - swingA * 1.1)
            var u = ModelUniforms(mvp: projection * model, model: toWorld * model,
                                  light: SIMD4(light.sky, light.block, 1, 0), tint: .zero, viewPos: .zero)
            draw(enc, arm, uniforms: &u)
        }
        enc.setViewport(MTLViewport(originX: 0, originY: 0, width: Double(drawableSize.x), height: Double(drawableSize.y), znear: 0, zfar: 1))
    }
}
