import Foundation
import Metal
import MetalKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

struct FrameUniforms {
    var viewProj = matrix_identity_float4x4
    var invViewProj = matrix_identity_float4x4
    var cameraPosTime = SIMD4<Float>(0, 0, 0, 0)
    var sunDirDaylight = SIMD4<Float>(0, 1, 0, 1)
    var fogColorStart = SIMD4<Float>(0.7, 0.8, 1, 100)
    var fogParams = SIMD4<Float>(180, 0, 0.5, 0.45)
    var skyZenith = SIMD4<Float>(0.2, 0.4, 0.9, 0)
    var skyHorizon = SIMD4<Float>(0.6, 0.75, 1, 0)
    var skyLight = SIMD4<Float>(1, 1, 1, 1)
    var viewport = SIMD4<Float>(1, 1, 1, 1)
    var dimension = SIMD4<Float>(0, 200, 1, 0)
    var season = SIMD4<Float>(1, 1, 1, 0)
}

struct ChunkUniforms {
    var origin: SIMD4<Float>
    var worldOrigin: SIMD4<Float>
}

/// Owns the Metal device state shared by all render passes: the shader
/// library, pipelines, depth states, samplers and texture arrays.
final class Renderer {
    let device: MTLDevice
    let blockRegistry: BlockRegistry
    let queue: MTLCommandQueue
    let library: MTLLibrary
    let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
    let depthFormat: MTLPixelFormat = .depth32Float

    let chunkOpaque: MTLRenderPipelineState
    let chunkCutout: MTLRenderPipelineState
    let chunkTranslucent: MTLRenderPipelineState
    let sky: MTLRenderPipelineState

    let depthWrite: MTLDepthStencilState
    let depthReadOnly: MTLDepthStencilState
    let depthSky: MTLDepthStencilState
    let depthDisabled: MTLDepthStencilState

    let blockSampler: MTLSamplerState
    let nearestSampler: MTLSamplerState
    let linearSampler: MTLSamplerState

    private(set) var blockTextures: TextureArray
    private(set) var itemTextures: TextureArray
    let crackTextures: TextureArray

    /// Shared index buffer: quad i uses vertices 4i...4i+3 as (0,1,2)(0,2,3).
    let quadIndices: MTLBuffer
    let maxQuadsPerDraw: Int

    let inflight = DispatchSemaphore(value: 3)

    enum RendererError: Error, CustomStringConvertible {
        case shaders(String)
        case pipeline(String, Error)
        case resource(String)
        var description: String {
            switch self {
            case .shaders(let m): return "Shader compilation failed:\n\(m)"
            case .pipeline(let name, let e): return "Could not create the \(name) render pipeline: \(e)"
            case .resource(let m): return m
            }
        }
    }

    init(device: MTLDevice, blocks: BlockRegistry, items: ItemRegistry) throws {
        self.device = device
        blockRegistry = blocks
        guard let q = device.makeCommandQueue() else { throw RendererError.resource("Could not create a Metal command queue") }
        q.label = "DinoCraft Main Queue"
        queue = q

        try Renderer.validateVertexLayout()

        // Shaders are compiled from source at startup (no Xcode toolchain required).
        let t0 = CFAbsoluteTimeGetCurrent()
        let files = ResourceLocator.files(in: "Shaders", withExtension: "metal")
        guard !files.isEmpty else { throw RendererError.resource("No shader sources found in Resources/Shaders") }
        var source = ""
        for f in files { source += (try String(contentsOf: f, encoding: .utf8)) + "\n" }
        let options = MTLCompileOptions()
        options.languageVersion = .version3_0
        if #available(iOS 18.0, *) { options.mathMode = .fast } else { options.fastMathEnabled = true }
        let lib: MTLLibrary
        do {
            lib = try device.makeLibrary(source: source, options: options)
        } catch {
            throw RendererError.shaders(String(describing: error))
        }
        library = lib
        // Locals so the nested helpers below never capture a partially initialised self.
        let colorFormat: MTLPixelFormat = .bgra8Unorm_srgb
        let depthFormat: MTLPixelFormat = .depth32Float
        Log.info(String(format: "Compiled %d shader files in %.0f ms", files.count, (CFAbsoluteTimeGetCurrent() - t0) * 1000), category: "Renderer")

        func fn(_ name: String) throws -> MTLFunction {
            guard let f = lib.makeFunction(name: name) else { throw RendererError.resource("Shader function '\(name)' not found") }
            return f
        }

        let chunkVD = MTLVertexDescriptor()
        let attrs: [(MTLVertexFormat, Int)] = [(.ushort3, 0), (.ushort, 6), (.ushort2, 8), (.uchar, 12), (.uchar, 13), (.ucharNormalized, 14), (.ucharNormalized, 15), (.uchar, 16)]
        for (i, (format, offset)) in attrs.enumerated() {
            chunkVD.attributes[i].format = format
            chunkVD.attributes[i].offset = offset
            chunkVD.attributes[i].bufferIndex = 0
        }
        chunkVD.layouts[0].stride = MemoryLayout<ChunkVertex>.stride

        func pipeline(_ name: String, vertex: String, fragment: String, vd: MTLVertexDescriptor?, blend: Bool, depth: Bool = true) throws -> MTLRenderPipelineState {
            let d = MTLRenderPipelineDescriptor()
            d.label = name
            d.vertexFunction = try fn(vertex)
            d.fragmentFunction = try fn(fragment)
            d.vertexDescriptor = vd
            d.colorAttachments[0].pixelFormat = colorFormat
            if blend {
                d.colorAttachments[0].isBlendingEnabled = true
                d.colorAttachments[0].sourceRGBBlendFactor = .one
                d.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                d.colorAttachments[0].sourceAlphaBlendFactor = .one
                d.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            d.depthAttachmentPixelFormat = depth ? depthFormat : .invalid
            do { return try device.makeRenderPipelineState(descriptor: d) } catch { throw RendererError.pipeline(name, error) }
        }

        chunkOpaque = try pipeline("Chunk Opaque", vertex: "chunk_vertex", fragment: "chunk_fragment_opaque", vd: chunkVD, blend: false)
        chunkCutout = try pipeline("Chunk Cutout", vertex: "chunk_vertex", fragment: "chunk_fragment_cutout", vd: chunkVD, blend: false)
        chunkTranslucent = try pipeline("Chunk Translucent", vertex: "chunk_vertex", fragment: "chunk_fragment_translucent", vd: chunkVD, blend: true)
        sky = try pipeline("Sky", vertex: "sky_vertex", fragment: "sky_fragment", vd: nil, blend: false)

        func depthState(_ compare: MTLCompareFunction, write: Bool) -> MTLDepthStencilState {
            let d = MTLDepthStencilDescriptor()
            d.depthCompareFunction = compare
            d.isDepthWriteEnabled = write
            return device.makeDepthStencilState(descriptor: d)!
        }
        // Reverse-Z: nearer fragments have larger depth.
        depthWrite = depthState(.greater, write: true)
        depthReadOnly = depthState(.greater, write: false)
        depthSky = depthState(.greaterEqual, write: false)
        depthDisabled = depthState(.always, write: false)

        let bs = MTLSamplerDescriptor()
        bs.minFilter = .linear; bs.magFilter = .nearest; bs.mipFilter = .linear
        bs.sAddressMode = .repeat; bs.tAddressMode = .repeat
        bs.maxAnisotropy = 8
        blockSampler = device.makeSamplerState(descriptor: bs)!
        let ns = MTLSamplerDescriptor()
        ns.minFilter = .nearest; ns.magFilter = .nearest; ns.mipFilter = .notMipmapped
        ns.sAddressMode = .clampToEdge; ns.tAddressMode = .clampToEdge
        nearestSampler = device.makeSamplerState(descriptor: ns)!
        let ls = MTLSamplerDescriptor()
        ls.minFilter = .linear; ls.magFilter = .linear; ls.mipFilter = .linear
        ls.sAddressMode = .clampToEdge; ls.tAddressMode = .clampToEdge
        linearSampler = device.makeSamplerState(descriptor: ls)!

        // Textures
        let blockNames = blocks.textureNames
        let alphaTested = Set(blocks.all.filter { $0.layer == .cutout }.flatMap { $0.faceTextureNames })
        let blockArray = try TextureArray(device: device, label: "Blocks",
                                          entries: blockNames.map { ($0, try? ResourceLocator.url("Textures/blocks/\($0).png")) },
                                          size: 32, alphaTestNames: alphaTested)
        blockTextures = blockArray
        blocks.bindTextureLayers { blockArray.layer($0) }
        itemTextures = try TextureArray(device: device, label: "Items",
                                        entries: items.textureNames.map { ($0, try? ResourceLocator.url("Textures/items/\($0).png")) }, size: 32)
        crackTextures = try TextureArray(device: device, label: "Cracks",
                                         entries: (0..<10).map { ("crack_\($0)", try? ResourceLocator.url("Textures/misc/crack_\($0).png")) }, size: 32)

        let maxQuads = 1 << 20
        maxQuadsPerDraw = maxQuads
        var indices = [UInt32](repeating: 0, count: maxQuads * 6)
        for q in 0..<maxQuads {
            let b = UInt32(q * 4), i = q * 6
            indices[i] = b; indices[i + 1] = b + 1; indices[i + 2] = b + 2
            indices[i + 3] = b; indices[i + 4] = b + 2; indices[i + 5] = b + 3
        }
        guard let ib = device.makeBuffer(bytes: indices, length: indices.count * 4, options: .storageModeShared) else {
            throw RendererError.resource("Could not allocate the quad index buffer")
        }
        ib.label = "Quad Indices"
        quadIndices = ib
    }

    /// Guards against Swift struct layout drifting from the Metal vertex descriptor.
    private static func validateVertexLayout() throws {
        let checks: [(String, Int?, Int)] = [
            ("x", MemoryLayout<ChunkVertex>.offset(of: \.x), 0),
            ("layer", MemoryLayout<ChunkVertex>.offset(of: \.layer), 6),
            ("u", MemoryLayout<ChunkVertex>.offset(of: \.u), 8),
            ("normal", MemoryLayout<ChunkVertex>.offset(of: \.normal), 12),
            ("sky", MemoryLayout<ChunkVertex>.offset(of: \.sky), 14),
            ("flags", MemoryLayout<ChunkVertex>.offset(of: \.flags), 16),
        ]
        for (name, actual, expected) in checks where actual != expected {
            throw RendererError.resource("ChunkVertex.\(name) is at offset \(actual ?? -1), expected \(expected)")
        }
        // FrameUniforms: 2 × float4x4 + 10 × float4 (matching 00_Common.metal). ChunkUniforms: 2 × float4.
        // Update this whenever a field is added to FrameUniforms, or the game refuses to start.
        guard MemoryLayout<ChunkVertex>.stride == 18,
              MemoryLayout<FrameUniforms>.stride == 2 * 64 + 10 * 16,
              MemoryLayout<ChunkUniforms>.stride == 2 * 16 else {
            throw RendererError.resource("Uniform/vertex struct sizes do not match the shaders")
        }
    }

    func configure(view: MTKView) {
        view.device = device
        view.colorPixelFormat = colorFormat
        view.depthStencilPixelFormat = depthFormat
        view.clearDepth = 0.0
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.framebufferOnly = false
        view.autoResizeDrawable = true
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.preferredFramesPerSecond = view.window?.screen.maximumFramesPerSecond ?? 60
    }
}

extension Renderer {
    /// Swaps in a texture pack. Texture names (and therefore layer indices) are
    /// unchanged, so existing chunk meshes stay valid.
    func loadTextures(blocks: BlockRegistry, items: ItemRegistry, pack: TexturePack) throws {
        let alphaTested = Set(blocks.all.filter { $0.layer == .cutout }.flatMap { $0.faceTextureNames })
        let b = try TextureArray(device: device, label: "Blocks", entries: blocks.textureNames.map { ($0, pack.url("blocks", $0)) },
                                 size: 32, alphaTestNames: alphaTested)
        let i = try TextureArray(device: device, label: "Items", entries: items.textureNames.map { ($0, pack.url("items", $0)) }, size: 32)
        blockTextures = b
        itemTextures = i
    }
}
