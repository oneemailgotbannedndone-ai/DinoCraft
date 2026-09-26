import Foundation
import Metal
import CoreGraphics
import ImageIO
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Draws the targeted-block outline and the progressive break cracks.
final class OverlayRenderer {
    struct Vertex {
        var x: Float, y: Float, z: Float
        var u: Float, v: Float
        var r: Float, g: Float, b: Float, a: Float
        var mode: Float, layer: Float
    }

    let renderer: Renderer
    let pipeline: MTLRenderPipelineState
    private var vertices: [Vertex] = []
    private var buffers: [MTLBuffer]
    private var cursor = 0

    init(renderer: Renderer) throws {
        self.renderer = renderer
        let vd = MTLVertexDescriptor()
        let attrs: [(MTLVertexFormat, Int)] = [(.float3, 0), (.float2, 12), (.float4, 20), (.float2, 36)]
        for (i, (f, o)) in attrs.enumerated() {
            vd.attributes[i].format = f
            vd.attributes[i].offset = o
            vd.attributes[i].bufferIndex = 0
        }
        vd.layouts[0].stride = MemoryLayout<Vertex>.stride
        precondition(MemoryLayout<Vertex>.stride == 44, "Overlay vertex layout mismatch")

        let d = MTLRenderPipelineDescriptor()
        d.label = "Overlay"
        guard let vf = renderer.library.makeFunction(name: "overlay_vertex"),
              let ff = renderer.library.makeFunction(name: "overlay_fragment") else {
            throw Renderer.RendererError.resource("Overlay shader functions missing")
        }
        d.vertexFunction = vf
        d.fragmentFunction = ff
        d.vertexDescriptor = vd
        d.colorAttachments[0].pixelFormat = renderer.colorFormat
        d.colorAttachments[0].isBlendingEnabled = true
        d.colorAttachments[0].sourceRGBBlendFactor = .one
        d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        d.colorAttachments[0].sourceAlphaBlendFactor = .one
        d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        d.depthAttachmentPixelFormat = renderer.depthFormat
        pipeline = try renderer.device.makeRenderPipelineState(descriptor: d)
        buffers = (0..<3).compactMap { _ in renderer.device.makeBuffer(length: 32_768, options: .storageModeShared) }
    }

    private func quad(_ p: [SIMD3<Float>], color: SIMD4<Float>, mode: Float, layer: Float) {
        let uvs: [SIMD2<Float>] = [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
        for i in 0..<4 {
            vertices.append(Vertex(x: p[i].x, y: p[i].y, z: p[i].z, u: uvs[i].x, v: uvs[i].y,
                                   r: color.x, g: color.y, b: color.z, a: color.w, mode: mode, layer: layer))
        }
    }

    func encode(_ enc: MTLRenderCommandEncoder, session: GameSession, camera: Camera, uniforms: inout FrameUniforms) {
        guard let hit = session.target else { return }
        vertices.removeAll(keepingCapacity: true)
        let origin = SIMD3<Float>(Float(Double(hit.block.x) - camera.position.x),
                                  Float(Double(hit.block.y) - camera.position.y),
                                  Float(Double(hit.block.z) - camera.position.z))

        // Crack overlay on all faces
        if session.breakProgress > 0, session.breakingPos == hit.block {
            let stage = Float(min(9, Int(session.breakProgress * 10)))
            let e: Float = 0.003
            let lo = origin - e, hi = origin + 1 + e
            let faces: [[SIMD3<Float>]] = [
                [SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(hi.x, hi.y, hi.z)],
                [SIMD3(lo.x, lo.y, lo.z), SIMD3(lo.x, lo.y, hi.z), SIMD3(lo.x, hi.y, hi.z), SIMD3(lo.x, hi.y, lo.z)],
                [SIMD3(lo.x, hi.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(hi.x, hi.y, lo.z), SIMD3(lo.x, hi.y, lo.z)],
                [SIMD3(lo.x, lo.y, lo.z), SIMD3(hi.x, lo.y, lo.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(lo.x, lo.y, hi.z)],
                [SIMD3(lo.x, lo.y, hi.z), SIMD3(hi.x, lo.y, hi.z), SIMD3(hi.x, hi.y, hi.z), SIMD3(lo.x, hi.y, hi.z)],
                [SIMD3(hi.x, lo.y, lo.z), SIMD3(lo.x, lo.y, lo.z), SIMD3(lo.x, hi.y, lo.z), SIMD3(hi.x, hi.y, lo.z)],
            ]
            for f in faces { quad(f, color: SIMD4(1, 1, 1, 1), mode: 1, layer: stage) }
        }

        // Outline: each edge as two thin perpendicular quads
        let e: Float = 0.004, w: Float = 0.009
        let lo = origin - e, hi = origin + 1 + e
        let color = SIMD4<Float>(0.02, 0.02, 0.03, 0.62)
        let xs = [lo.x, hi.x], ys = [lo.y, hi.y], zs = [lo.z, hi.z]
        for y in ys { for z in zs {
            quad([SIMD3(lo.x, y - w, z), SIMD3(hi.x, y - w, z), SIMD3(hi.x, y + w, z), SIMD3(lo.x, y + w, z)], color: color, mode: 0, layer: 0)
            quad([SIMD3(lo.x, y, z - w), SIMD3(hi.x, y, z - w), SIMD3(hi.x, y, z + w), SIMD3(lo.x, y, z + w)], color: color, mode: 0, layer: 0)
        } }
        for x in xs { for z in zs {
            quad([SIMD3(x - w, lo.y, z), SIMD3(x + w, lo.y, z), SIMD3(x + w, hi.y, z), SIMD3(x - w, hi.y, z)], color: color, mode: 0, layer: 0)
            quad([SIMD3(x, lo.y, z - w), SIMD3(x, lo.y, z + w), SIMD3(x, hi.y, z + w), SIMD3(x, hi.y, z - w)], color: color, mode: 0, layer: 0)
        } }
        for x in xs { for y in ys {
            quad([SIMD3(x - w, y, lo.z), SIMD3(x + w, y, lo.z), SIMD3(x + w, y, hi.z), SIMD3(x - w, y, hi.z)], color: color, mode: 0, layer: 0)
            quad([SIMD3(x, y - w, lo.z), SIMD3(x, y + w, lo.z), SIMD3(x, y + w, hi.z), SIMD3(x, y - w, hi.z)], color: color, mode: 0, layer: 0)
        } }

        cursor = (cursor + 1) % buffers.count
        let buffer = buffers[cursor]
        let bytes = vertices.count * MemoryLayout<Vertex>.stride
        guard bytes <= buffer.length else { return }
        vertices.withUnsafeBytes { buffer.contents().copyMemory(from: $0.baseAddress!, byteCount: bytes) }

        enc.pushDebugGroup("Overlay")
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(renderer.depthReadOnly)
        enc.setCullMode(.none)
        enc.setVertexBuffer(buffer, offset: 0, index: 0)
        enc.setVertexBytes(&uniforms, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        enc.setFragmentTexture(renderer.crackTextures.texture, index: 0)
        enc.setFragmentSamplerState(renderer.nearestSampler, index: 0)
        enc.drawIndexedPrimitives(type: .triangle, indexCount: vertices.count / 4 * 6, indexType: .uint32,
                                  indexBuffer: renderer.quadIndices, indexBufferOffset: 0)
        enc.popDebugGroup()
    }
}

enum ImageLoader {
    /// Loads an image as a premultiplied sRGB texture, downscaled to at most `maxSize`.
    static func texture(url: URL, device: MTLDevice, maxSize: Int = 512) -> MTLTexture? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            Log.warning("Could not read image \(url.lastPathComponent)", category: "Assets")
            return nil
        }
        let scale = min(1, Double(maxSize) / Double(max(image.width, image.height)))
        let w = max(1, Int(Double(image.width) * scale)), h = max(1, Int(Double(image.height) * scale))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &bytes, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: w, height: h, mipmapped: false)
        desc.storageMode = .shared
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: bytes, bytesPerRow: w * 4)
        tex.label = url.lastPathComponent
        return tex
    }
}
