import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

struct PostUniforms {
    var params: SIMD4<Float>   // preset, time, width, height
    var extra: SIMD4<Float>    // strength
}

/// Shader packs: the scene renders into an offscreen target, then a fullscreen
/// pass grades it into the drawable before the interface is drawn on top.
final class PostProcessor {
    private let renderer: Renderer
    private let pipeline: MTLRenderPipelineState
    private var target: MTLTexture?

    init(renderer: Renderer) throws {
        self.renderer = renderer
        guard let vertex = renderer.library.makeFunction(name: "post_vertex"),
              let fragment = renderer.library.makeFunction(name: "post_fragment") else {
            throw Renderer.RendererError.resource("Post-processing shader functions not found")
        }
        let d = MTLRenderPipelineDescriptor()
        d.label = "Post Process"
        d.vertexFunction = vertex
        d.fragmentFunction = fragment
        d.colorAttachments[0].pixelFormat = renderer.colorFormat
        d.depthAttachmentPixelFormat = renderer.depthFormat
        do {
            pipeline = try renderer.device.makeRenderPipelineState(descriptor: d)
        } catch {
            throw Renderer.RendererError.pipeline("Post Process", error)
        }
    }

    /// Offscreen scene color target matching the drawable size.
    func sceneTarget(width: Int, height: Int) -> MTLTexture? {
        guard width > 0, height > 0 else { return nil }
        if let t = target, t.width == width, t.height == height { return t }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: renderer.colorFormat, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        desc.storageMode = .private
        target = renderer.device.makeTexture(descriptor: desc)
        target?.label = "Scene Color"
        return target
    }

    func encode(_ enc: MTLRenderCommandEncoder, source: MTLTexture, pack: ShaderPack, strength: Float, time: Float, size: SIMD2<Float>) {
        enc.setRenderPipelineState(pipeline)
        enc.setDepthStencilState(renderer.depthDisabled)
        enc.setCullMode(.none)
        var u = PostUniforms(params: SIMD4(pack.index, time, size.x, size.y), extra: SIMD4(strength, 0, 0, 0))
        enc.setFragmentTexture(source, index: 0)
        enc.setFragmentSamplerState(renderer.linearSampler, index: 0)
        enc.setFragmentBytes(&u, length: MemoryLayout<PostUniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
