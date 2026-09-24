import Foundation
import DinoCraftCore
@testable import DinoCraftGame

struct WinCamera {
    var position = DVec3(0, 100, 0)
    var yaw: Double = 0
    var pitch: Double = 0
    var fovY: Double = 75 * .pi / 180

    var forward: SIMD3<Float> {
        SIMD3(Float(-sin(yaw) * cos(pitch)), Float(sin(pitch)), Float(-cos(yaw) * cos(pitch)))
    }

    /// OpenGL perspective (depth -1…1) times a rotation-only view; geometry is drawn camera-relative.
    func viewProjection(aspect: Float) -> Mat4 {
        let f = 1 / Float(tan(fovY / 2))
        let near: Float = 0.08, far: Float = 1600
        let projection = Mat4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, (far + near) / (near - far), -1),
            SIMD4(0, 0, 2 * far * near / (near - far), 0)))
        return projection * MathUtil.rotationX(Float(-pitch)) * MathUtil.rotationY(Float(-yaw))
    }
}

/// Day/night sky colours (overworld), matching the Mac `SkyModel`.
struct SkyState {
    var sunDirection = SIMD3<Float>(0, 1, 0)
    var daylight: Float = 1
    var zenith = SIMD3<Float>(0.2, 0.4, 0.9)
    var horizon = SIMD3<Float>(0.6, 0.75, 1)
    var sunsetGlow: Float = 0
    var stars: Float = 0
    var skyLight = SIMD3<Float>(1, 1, 1)

    static let dayLength = 1200.0

    private static func lin(_ r: Float, _ g: Float, _ b: Float) -> SIMD3<Float> {
        SIMD3(pow(r, 2.2), pow(g, 2.2), pow(b, 2.2))
    }

    static func at(worldTime: Double) -> SkyState {
        let angle = Float((worldTime / dayLength).truncatingRemainder(dividingBy: 1) * 2 * .pi)
        let sun = simd_normalize(SIMD3<Float>(cos(angle), sin(angle), 0.28))
        let e = sun.y
        let t = MathUtil.smoothstep(-0.22, 0.28, e)
        var s = SkyState()
        s.sunDirection = sun
        s.daylight = MathUtil.lerp(0.14, 1.0, MathUtil.smoothstep(-0.14, 0.3, e))
        let dayZ = lin(0.24, 0.47, 0.93), nightZ = lin(0.015, 0.024, 0.07)
        let dayH = lin(0.68, 0.82, 0.98), nightH = lin(0.05, 0.07, 0.14)
        let sunsetH = lin(0.99, 0.6, 0.38)
        s.zenith = simd_mix(nightZ, dayZ, SIMD3(repeating: t))
        let sunset = exp(-(e * e) / 0.035) * (e > -0.3 ? 1 : 0)
        s.horizon = simd_mix(simd_mix(nightH, dayH, SIMD3(repeating: t)), sunsetH, SIMD3(repeating: sunset * 0.7))
        s.sunsetGlow = sunset
        s.stars = 1 - MathUtil.smoothstep(-0.28, 0.02, e)
        let nightLight = SIMD3<Float>(0.42, 0.5, 0.82)
        s.skyLight = simd_mix(nightLight, SIMD3(1, 1, 1), SIMD3(repeating: t))
        s.skyLight = simd_mix(s.skyLight, SIMD3(1.0, 0.82, 0.68), SIMD3(repeating: sunset * 0.35))
        return s
    }

    /// The sky for any dimension, dimmed and greyed by rain and storms in the overworld.
    static func at(worldTime: Double, dimension: WorldDimension, weather: Float) -> SkyState {
        switch dimension {
        case .underworld:
            var s = SkyState()
            s.sunDirection = SIMD3(0, -1, 0)
            s.daylight = 0.35
            s.zenith = lin(0.12, 0.03, 0.02)
            s.horizon = lin(0.32, 0.09, 0.04)
            s.skyLight = SIMD3(1, 0.62, 0.45)
            return s
        case .skylands:
            var s = SkyState.at(worldTime: 300)
            s.zenith = lin(0.55, 0.62, 0.95)
            s.horizon = lin(1.0, 0.86, 0.6)
            s.skyLight = SIMD3(1, 0.95, 0.85)
            return s
        case .toonland:
            var s = SkyState.at(worldTime: 300)
            s.zenith = lin(0.78, 0.8, 0.84)
            s.horizon = lin(0.97, 0.97, 0.97)
            s.skyLight = SIMD3(1, 1, 1)
            return s
        default:
            var s = SkyState.at(worldTime: worldTime)
            guard weather > 0 else { return s }
            let grey = SIMD3<Float>(repeating: simd_dot(s.horizon, SIMD3(0.3, 0.55, 0.15)))
            s.horizon = simd_mix(s.horizon, grey * 0.8, SIMD3(repeating: weather * 0.75))
            s.zenith = simd_mix(s.zenith, grey * 0.6, SIMD3(repeating: weather * 0.75))
            s.daylight *= 1 - weather * 0.35
            s.sunsetGlow *= 1 - weather
            s.stars *= 1 - weather
            return s
        }
    }
}

/// Extra things drawn in the world, built by `EffectBuilder` (11 floats per vertex).
struct WorldEffects {
    /// Dropped items and other solid textured shapes, drawn with the creatures.
    var solid: [Float] = []
    /// Particles, rain and snow, blended over the world.
    var blended: [Float] = []
    /// The held item or arm, drawn last so it never goes inside walls.
    var hand: [Float] = []
}

/// Draws the sky, the voxel world, players and creatures, and the 2D overlay with OpenGL 3.3.
final class WinRenderer {
    private struct ChunkProgram {
        let id: UInt32
        let viewProj, origin, worldOrigin, time, blocks, sunDaylight, skyLight, fogColorStart, fogParams, skyHorizon, brightness: Int32

        init(gl: GL, id: UInt32) {
            self.id = id
            viewProj = gl.uniform(id, "uViewProj")
            origin = gl.uniform(id, "uOrigin")
            worldOrigin = gl.uniform(id, "uWorldOrigin")
            time = gl.uniform(id, "uTime")
            blocks = gl.uniform(id, "uBlocks")
            sunDaylight = gl.uniform(id, "uSunDaylight")
            skyLight = gl.uniform(id, "uSkyLight")
            fogColorStart = gl.uniform(id, "uFogColorStart")
            fogParams = gl.uniform(id, "uFogParams")
            skyHorizon = gl.uniform(id, "uSkyHorizon")
            brightness = gl.uniform(id, "uBrightness")
        }
    }

    let gl: GL
    private let chunkPrograms: [ChunkProgram]
    private let skyProgram: UInt32
    private let overlayProgram: UInt32
    private let modelProgram: UInt32
    private let effectProgram: UInt32
    private let postProgram: UInt32
    /// Offscreen scene for shader packs: colour texture, depth buffer and framebuffer, sized to the window.
    private var sceneTarget: (framebuffer: UInt32, color: UInt32, depth: UInt32, width: Int32, height: Int32)?
    /// Shader pack: 0 off, 1 vibrant, 2 cinematic, 3 retro, 4 dreamy (the Mac's `ShaderPack` order).
    var shaderPack = 0
    /// 1 while in Toonland: the scene is shown as an old black-and-white cartoon.
    var mono: Float = 0
    /// Set when the driver can't render offscreen, so post-processing stays off.
    private var postUnavailable = false
    var shaderStrength: Float = 1
    private let effectVertexArray: UInt32
    private let effectBuffer: UInt32
    private var blockTexture: UInt32
    private var itemTexture: UInt32
    /// Texture-array layer for each block and item texture name.
    let blockLayers: [String: UInt16]
    let itemLayers: [String: UInt16]
    /// Average colour (linear) of each block and item texture layer, for dropped items.
    private var blockLayerColors: [SIMD3<Float>]
    private var itemLayerColors: [SIMD3<Float>]
    /// Which pixels of each texture are solid, for 3D (extruded) items.
    private var blockLayerMasks: [[Bool]] = []
    private var itemLayerMasks: [[Bool]] = []
    private let blockNames: [String]
    private let itemNames: [String]
    /// The texture pack whose art is loaded ("dino" is DinoCraft's own).
    private(set) var texturePack = TexturePackLibrary.defaultPack
    private let quadIndices: UInt32
    private let maxQuads = 1 << 18
    private let emptyVertexArray: UInt32
    private let overlayVertexArray: UInt32
    private let overlayBuffer: UInt32
    private let modelVertexArray: UInt32
    private let modelBuffer: UInt32
    private(set) var visibleChunks = 0
    /// The Brightness setting (0 moody … 1 bright), used by the chunk shader.
    var brightness: Float = 0.5

    init(gl: GL, blocks: BlockRegistry, items: ItemRegistry, pack: TexturePack = TexturePackLibrary.defaultPack) throws {
        self.gl = gl
        chunkPrograms = try ["OPAQUE", "CUTOUT", "TRANSLUCENT"].map { pass in
            ChunkProgram(gl: gl, id: try gl.makeProgram(vertex: Shaders.chunkVertex, fragment: Shaders.chunkFragment(pass: pass), label: "chunk \(pass)"))
        }
        skyProgram = try gl.makeProgram(vertex: Shaders.skyVertex, fragment: Shaders.skyFragment, label: "sky")
        overlayProgram = try gl.makeProgram(vertex: Shaders.overlayVertex, fragment: Shaders.overlayFragment, label: "overlay")
        modelProgram = try gl.makeProgram(vertex: Shaders.boxVertex, fragment: Shaders.boxFragment, label: "models")
        effectProgram = try gl.makeProgram(vertex: Shaders.effectVertex, fragment: Shaders.effectFragment, label: "effects")
        postProgram = try gl.makeProgram(vertex: Shaders.postVertex, fragment: Shaders.postFragment, label: "shader pack")

        blockNames = blocks.textureNames
        itemNames = items.textureNames
        texturePack = pack
        let blockArray = WinRenderer.loadTextureArray(gl: gl, names: blocks.textureNames, folders: ["blocks"], pack: pack)
        blockTexture = blockArray.texture
        blockLayers = blockArray.layers
        blockLayerColors = blockArray.colors
        blockLayerMasks = blockArray.masks
        let layers = blockArray.layers
        blocks.bindTextureLayers { layers[$0] ?? 0 }
        let itemArray = WinRenderer.loadTextureArray(gl: gl, names: items.textureNames, folders: ["items", "blocks"], pack: pack)
        itemTexture = itemArray.texture
        itemLayers = itemArray.layers
        itemLayerColors = itemArray.colors
        itemLayerMasks = itemArray.masks
        gl.activeTexture(GLC.TEXTURE0)

        // Shared quad index buffer: (0,1,2)(0,2,3) per quad.
        emptyVertexArray = gl.makeVertexArray()
        quadIndices = gl.makeBuffer()
        gl.bindVertexArray(emptyVertexArray)
        var indices = [UInt32](repeating: 0, count: maxQuads * 6)
        for q in 0..<maxQuads {
            let b = UInt32(q * 4)
            indices[q * 6] = b; indices[q * 6 + 1] = b + 1; indices[q * 6 + 2] = b + 2
            indices[q * 6 + 3] = b; indices[q * 6 + 4] = b + 2; indices[q * 6 + 5] = b + 3
        }
        gl.bindBuffer(GLC.ELEMENT_ARRAY_BUFFER, quadIndices)
        indices.withUnsafeBytes { gl.bufferData(GLC.ELEMENT_ARRAY_BUFFER, $0.count, $0.baseAddress, GLC.STATIC_DRAW) }
        gl.bindVertexArray(0)

        overlayVertexArray = gl.makeVertexArray()
        overlayBuffer = gl.makeBuffer()
        gl.bindVertexArray(overlayVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, overlayBuffer)
        gl.vertexAttribPointer(0, 2, GLC.FLOAT, 0, 36, nil)
        gl.vertexAttribPointer(1, 2, GLC.FLOAT, 0, 36, UnsafeRawPointer(bitPattern: 8))
        gl.vertexAttribPointer(2, 1, GLC.FLOAT, 0, 36, UnsafeRawPointer(bitPattern: 16))
        gl.vertexAttribPointer(3, 4, GLC.FLOAT, 0, 36, UnsafeRawPointer(bitPattern: 20))
        for i: UInt32 in 0..<4 { gl.enableVertexAttribArray(i) }
        gl.bindVertexArray(0)

        modelVertexArray = gl.makeVertexArray()
        modelBuffer = gl.makeBuffer()
        gl.bindVertexArray(modelVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, modelBuffer)
        gl.vertexAttribPointer(0, 3, GLC.FLOAT, 0, 28, nil)
        gl.vertexAttribPointer(1, 3, GLC.FLOAT, 0, 28, UnsafeRawPointer(bitPattern: 12))
        gl.vertexAttribPointer(2, 1, GLC.FLOAT, 0, 28, UnsafeRawPointer(bitPattern: 24))
        for i: UInt32 in 0..<3 { gl.enableVertexAttribArray(i) }
        gl.bindVertexArray(0)

        effectVertexArray = gl.makeVertexArray()
        effectBuffer = gl.makeBuffer()
        gl.bindVertexArray(effectVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, effectBuffer)
        let stride = Int32(EffectBuilder.floatsPerVertex * 4)
        gl.vertexAttribPointer(0, 3, GLC.FLOAT, 0, stride, nil)
        gl.vertexAttribPointer(1, 2, GLC.FLOAT, 0, stride, UnsafeRawPointer(bitPattern: 12))
        gl.vertexAttribPointer(2, 1, GLC.FLOAT, 0, stride, UnsafeRawPointer(bitPattern: 20))
        gl.vertexAttribPointer(3, 4, GLC.FLOAT, 0, stride, UnsafeRawPointer(bitPattern: 24))
        gl.vertexAttribPointer(4, 1, GLC.FLOAT, 0, stride, UnsafeRawPointer(bitPattern: 40))
        for i: UInt32 in 0..<5 { gl.enableVertexAttribArray(i) }
        gl.bindVertexArray(0)
    }

    /// Loads 32×32 PNGs into an sRGB texture array (premultiplied alpha), trying each folder in order.
    /// Switches to another texture pack's art. Layers keep their numbers, so chunk meshes stay valid.
    func applyTexturePack(_ pack: TexturePack) {
        guard pack.id != texturePack.id else { return }
        let blockArray = WinRenderer.loadTextureArray(gl: gl, names: blockNames, folders: ["blocks"], pack: pack)
        let itemArray = WinRenderer.loadTextureArray(gl: gl, names: itemNames, folders: ["items", "blocks"], pack: pack)
        gl.deleteTexture(blockTexture)
        gl.deleteTexture(itemTexture)
        blockTexture = blockArray.texture
        blockLayerColors = blockArray.colors
        blockLayerMasks = blockArray.masks
        itemTexture = itemArray.texture
        itemLayerColors = itemArray.colors
        itemLayerMasks = itemArray.masks
        texturePack = pack
        EffectBuilder.extrusionCache.removeAll()
        Log.info("Texture pack '\(pack.name)' active", category: "Renderer")
    }

    private static func loadTextureArray(gl: GL, names rawNames: [String], folders: [String], pack: TexturePack)
        -> (texture: UInt32, layers: [String: UInt16], colors: [SIMD3<Float>], masks: [[Bool]]) {
        var seen = Set<String>()
        let names = rawNames.filter { seen.insert($0).inserted }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4 * max(1, names.count))
        var layers: [String: UInt16] = [:]
        var colors: [SIMD3<Float>] = []
        var masks: [[Bool]] = []
        var missing = 0
        for (i, name) in names.enumerated() {
            layers[name] = UInt16(i)
            var rgba: [UInt8]?
            for folder in folders where rgba == nil {
                if let url = pack.url(folder, name),
                   let image = try? PNG.decode(Data(contentsOf: url)), image.width == size, image.height == size {
                    rgba = image.rgba
                }
            }
            if rgba == nil {
                missing += 1
                var checker = [UInt8](repeating: 255, count: size * size * 4)
                for p in 0..<(size * size) where ((p / size) / 4 + (p % size) / 4) % 2 == 0 {
                    checker[p * 4] = 255; checker[p * 4 + 1] = 0; checker[p * 4 + 2] = 255
                }
                rgba = checker
            }
            let source = rgba!
            let base = i * size * size * 4
            var sum = SIMD3<Float>(0, 0, 0), weight: Float = 0
            for p in 0..<(size * size) where source[p * 4 + 3] > 127 {
                sum += SIMD3(pow(Float(source[p * 4]) / 255, 2.2), pow(Float(source[p * 4 + 1]) / 255, 2.2), pow(Float(source[p * 4 + 2]) / 255, 2.2))
                weight += 1
            }
            colors.append(weight > 0 ? sum / weight : SIMD3(0.5, 0.5, 0.5))
            masks.append((0..<(size * size)).map { source[$0 * 4 + 3] > 127 })
            for p in 0..<(size * size) {
                let a = UInt16(source[p * 4 + 3])
                pixels[base + p * 4] = UInt8(UInt16(source[p * 4]) * a / 255)
                pixels[base + p * 4 + 1] = UInt8(UInt16(source[p * 4 + 1]) * a / 255)
                pixels[base + p * 4 + 2] = UInt8(UInt16(source[p * 4 + 2]) * a / 255)
                pixels[base + p * 4 + 3] = UInt8(a)
            }
        }
        if missing > 0 { Log.warning("\(missing) textures missing from \(folders.first ?? "?")", category: "Renderer") }

        let texture = gl.makeTexture()
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindTexture(GLC.TEXTURE_2D_ARRAY, texture)
        gl.pixelStorei(GLC.UNPACK_ALIGNMENT, 1)
        gl.texImage3D(GLC.TEXTURE_2D_ARRAY, 0, GLC.SRGB8_ALPHA8, Int32(size), Int32(size), Int32(max(1, names.count)), 0,
                      GLC.RGBA, GLC.UNSIGNED_BYTE, pixels)
        gl.generateMipmap(GLC.TEXTURE_2D_ARRAY)
        gl.texParameteri(GLC.TEXTURE_2D_ARRAY, GLC.TEXTURE_MIN_FILTER, GLC.NEAREST_MIPMAP_LINEAR)
        gl.texParameteri(GLC.TEXTURE_2D_ARRAY, GLC.TEXTURE_MAG_FILTER, GLC.NEAREST)
        gl.texParameteri(GLC.TEXTURE_2D_ARRAY, GLC.TEXTURE_WRAP_S, GLC.REPEAT)
        gl.texParameteri(GLC.TEXTURE_2D_ARRAY, GLC.TEXTURE_WRAP_T, GLC.REPEAT)
        Log.info("Loaded \(names.count) textures from \(folders.first ?? "?")", category: "Renderer")
        return (texture, layers, colors, masks)
    }

    /// The overlay layer for an item's icon (see `UIBuilder.icon`), or -1 when it has none.
    func iconLayer(_ item: ItemID, items: ItemRegistry, blocks: BlockRegistry) -> Float {
        guard let info = items[item] else { return -1 }
        if let texture = info.texture {
            if let layer = itemLayers[texture] { return UIBuilder.itemLayerOffset + Float(layer) }
            if let layer = blockLayers[texture] { return Float(layer) }
        }
        if let block = info.block { return Float(blocks.faceLayers[Int(block) * 6 + BlockFace.south.rawValue]) }
        return -1
    }

    /// Solid pixels of an icon layer (from `iconLayer`), for drawing it as a 3D item.
    func alphaMask(layer: Float) -> [Bool]? {
        if layer >= UIBuilder.itemLayerOffset {
            let i = Int(layer - UIBuilder.itemLayerOffset)
            return i < itemLayerMasks.count ? itemLayerMasks[i] : nil
        }
        let i = Int(layer)
        return i >= 0 && i < blockLayerMasks.count ? blockLayerMasks[i] : nil
    }

    /// The average colour of an item's icon, for drawing it as a small model.
    func itemColor(_ item: ItemID, items: ItemRegistry, blocks: BlockRegistry) -> SIMD4<Float> {
        let layer = iconLayer(item, items: items, blocks: blocks)
        let color: SIMD3<Float>
        if layer >= UIBuilder.itemLayerOffset {
            let i = Int(layer - UIBuilder.itemLayerOffset)
            color = i < itemLayerColors.count ? itemLayerColors[i] : SIMD3(0.5, 0.5, 0.5)
        } else if layer >= 0 {
            let i = Int(layer)
            color = i < blockLayerColors.count ? blockLayerColors[i] : SIMD3(0.5, 0.5, 0.5)
        } else {
            color = SIMD3(0.5, 0.5, 0.5)
        }
        return SIMD4(color, 1)
    }

    // MARK: Chunk meshes

    func makeMesh(_ payload: MeshPayload) -> GPUMesh? {
        let quads = payload.opaqueQuads + payload.cutoutQuads + payload.translucentQuads
        guard quads > 0 else { return nil }
        guard payload.opaqueQuads <= maxQuads, payload.cutoutQuads <= maxQuads, payload.translucentQuads <= maxQuads else {
            Log.warning("Chunk mesh too large (\(quads) quads)", category: "Renderer")
            return nil
        }
        let vao = gl.makeVertexArray()
        let vbo = gl.makeBuffer()
        gl.bindVertexArray(vao)
        gl.bindBuffer(GLC.ARRAY_BUFFER, vbo)
        payload.vertices.withUnsafeBytes { gl.bufferData(GLC.ARRAY_BUFFER, $0.count, $0.baseAddress, GLC.STATIC_DRAW) }
        gl.bindBuffer(GLC.ELEMENT_ARRAY_BUFFER, quadIndices)

        let stride = Int32(MemoryLayout<ChunkVertex>.stride)
        func offset(_ key: PartialKeyPath<ChunkVertex>) -> UnsafeRawPointer? {
            UnsafeRawPointer(bitPattern: MemoryLayout<ChunkVertex>.offset(of: key) ?? 0)
        }
        gl.vertexAttribPointer(0, 3, GLC.UNSIGNED_SHORT, 0, stride, offset(\ChunkVertex.x))
        gl.vertexAttribPointer(1, 1, GLC.UNSIGNED_SHORT, 0, stride, offset(\ChunkVertex.layer))
        gl.vertexAttribPointer(2, 2, GLC.UNSIGNED_SHORT, 0, stride, offset(\ChunkVertex.u))
        gl.vertexAttribPointer(3, 1, GLC.UNSIGNED_BYTE, 0, stride, offset(\ChunkVertex.normal))
        gl.vertexAttribPointer(4, 1, GLC.UNSIGNED_BYTE, 0, stride, offset(\ChunkVertex.ao))
        gl.vertexAttribPointer(5, 1, GLC.UNSIGNED_BYTE, 1, stride, offset(\ChunkVertex.sky))
        gl.vertexAttribPointer(6, 1, GLC.UNSIGNED_BYTE, 1, stride, offset(\ChunkVertex.light))
        gl.vertexAttribIPointer(7, 1, GLC.UNSIGNED_BYTE, stride, offset(\ChunkVertex.flags))
        for i: UInt32 in 0..<8 { gl.enableVertexAttribArray(i) }
        gl.bindVertexArray(0)
        return GPUMesh(vertexArray: vao, buffer: vbo, payload: payload)
    }

    func deleteMesh(_ mesh: GPUMesh) {
        gl.deleteBuffer(mesh.buffer)
        gl.deleteVertexArray(mesh.vertexArray)
    }

    // MARK: Frame

    private func drawSky(camera: WinCamera, aspect: Float, sky: SkyState, time: Float) {
        gl.disable(GLC.DEPTH_TEST)
        gl.disable(GLC.BLEND)
        gl.useProgram(skyProgram)
        let forward = camera.forward
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let tanY = Float(tan(camera.fovY / 2))
        gl.uniform3f(gl.uniform(skyProgram, "uCamForward"), forward.x, forward.y, forward.z)
        gl.uniform3f(gl.uniform(skyProgram, "uCamRight"), right.x, right.y, right.z)
        gl.uniform3f(gl.uniform(skyProgram, "uCamUp"), up.x, up.y, up.z)
        gl.uniform2f(gl.uniform(skyProgram, "uTanHalfFov"), tanY * aspect, tanY)
        gl.uniform4f(gl.uniform(skyProgram, "uSunDaylight"), sky.sunDirection.x, sky.sunDirection.y, sky.sunDirection.z, sky.daylight)
        gl.uniform4f(gl.uniform(skyProgram, "uZenithStars"), sky.zenith.x, sky.zenith.y, sky.zenith.z, sky.stars)
        gl.uniform4f(gl.uniform(skyProgram, "uHorizonGlow"), sky.horizon.x, sky.horizon.y, sky.horizon.z, sky.sunsetGlow)
        gl.uniform3f(gl.uniform(skyProgram, "uCamPos"), Float(camera.position.x.truncatingRemainder(dividingBy: 65536)),
                     Float(camera.position.y), Float(camera.position.z.truncatingRemainder(dividingBy: 65536)))
        gl.uniform1f(gl.uniform(skyProgram, "uTime"), time)
        gl.bindVertexArray(emptyVertexArray)
        gl.drawArrays(GLC.TRIANGLES, 0, 3)
    }

    /// Menu background: a slowly turning evening sky with drifting clouds, plus the menu UI.
    func renderMenu(width: Int32, height: Int32, time: Double, ui: [Float], models: [Float] = []) {
        gl.viewport(0, 0, width, height)
        gl.enable(GLC.FRAMEBUFFER_SRGB)
        gl.depthMask(1)
        gl.clearColor(0.02, 0.01, 0.05, 1)
        gl.clear(GLC.COLOR_BUFFER_BIT | GLC.DEPTH_BUFFER_BIT)
        var camera = WinCamera()
        camera.position = DVec3(time * 3, 90, time * 1.5)
        camera.yaw = time * 0.02
        camera.pitch = 0.18
        let aspect = Float(width) / Float(max(1, height))
        let sky = SkyState.at(worldTime: 520 + time * 0.5)
        drawSky(camera: camera, aspect: aspect, sky: sky, time: Float(time.truncatingRemainder(dividingBy: 3600)))
        if !models.isEmpty {
            // Models in front of a fixed camera looking down -Z (for the cosmetics preview).
            gl.enable(GLC.DEPTH_TEST)
            gl.depthFunc(GLC.LESS)
            gl.clear(GLC.DEPTH_BUFFER_BIT)
            var lit = sky
            lit.daylight = 1
            drawModels(models, viewProj: WinCamera().viewProjection(aspect: aspect), sky: lit, fogEnd: 1000)
        }
        drawOverlay(width: width, height: height, vertices: ui)
        gl.bindVertexArray(0)
    }

    func render(world: World, camera: WinCamera, sky: SkyState, time: Double, now: Double,
                width: Int32, height: Int32, ui: [Float], models: [Float] = [], effects: WorldEffects = WorldEffects()) {
        let aspect = Float(width) / Float(max(1, height))
        let viewProj = camera.viewProjection(aspect: aspect)
        let t = Float(time.truncatingRemainder(dividingBy: 3600))
        let post = (shaderPack > 0 || mono > 0) && !postUnavailable && bindSceneTarget(width: width, height: height)

        gl.viewport(0, 0, width, height)
        gl.enable(GLC.FRAMEBUFFER_SRGB)
        gl.depthMask(1)
        gl.clearColor(sky.horizon.x, sky.horizon.y, sky.horizon.z, 1)
        gl.clear(GLC.COLOR_BUFFER_BIT | GLC.DEPTH_BUFFER_BIT)
        gl.disable(GLC.CULL_FACE)
        drawSky(camera: camera, aspect: aspect, sky: sky, time: t)

        // Visible chunks
        var frustum = Frustum(viewProjection: viewProj)
        frustum.planes = Array(frustum.planes.prefix(4))
        let maxDist = Double((world.renderDistance + 1) * 16)
        var visible: [(mesh: GPUMesh, ox: Float, oy: Float, oz: Float, fade: Float, d2: Double, pos: ChunkPos)] = []
        for (pos, slot) in world.slots {
            guard let mesh = slot.mesh as? GPUMesh else { continue }
            let ox = Double(pos.originX) - camera.position.x
            let oz = Double(pos.originZ) - camera.position.z
            let oy = -camera.position.y
            let cx = ox + 8, cz = oz + 8
            let d2 = cx * cx + cz * cz
            if d2 > maxDist * maxDist { continue }
            let minV = Vec3(Float(ox), Float(oy), Float(oz))
            guard frustum.contains(AABB(min: minV, max: minV + Vec3(16, Float(max(1, mesh.maxY)), 16))) else { continue }
            let fade = slot.firstMeshTime < 0 ? 1 : Float(min(1, (now - slot.firstMeshTime) / 0.7))
            visible.append((mesh, Float(ox), Float(oy), Float(oz), 1 - (1 - fade) * (1 - fade), d2, pos))
        }
        visibleChunks = visible.count

        gl.enable(GLC.DEPTH_TEST)
        gl.depthFunc(GLC.LESS)
        let fogEnd = Float(world.renderDistance * 16) - 6
        for (pass, program) in chunkPrograms.enumerated() {
            if pass == 2 {
                if !models.isEmpty { drawModels(models, viewProj: viewProj, sky: sky, fogEnd: fogEnd) }
                if !effects.solid.isEmpty { drawEffects(effects.solid, viewProj: viewProj, sky: sky, fogEnd: fogEnd, blended: false) }
            }
            gl.useProgram(program.id)
            gl.setMatrix(program.viewProj, viewProj)
            gl.uniform1f(program.time, t)
            gl.uniform1i(program.blocks, 0)
            gl.uniform4f(program.sunDaylight, sky.sunDirection.x, sky.sunDirection.y, sky.sunDirection.z, sky.daylight)
            gl.uniform3f(program.skyLight, sky.skyLight.x, sky.skyLight.y, sky.skyLight.z)
            gl.uniform4f(program.fogColorStart, sky.horizon.x, sky.horizon.y, sky.horizon.z, fogEnd * 0.55)
            gl.uniform2f(program.fogParams, fogEnd, 0)
            gl.uniform3f(program.skyHorizon, sky.horizon.x, sky.horizon.y, sky.horizon.z)
            gl.uniform1f(program.brightness, brightness)
            gl.activeTexture(GLC.TEXTURE0)
            gl.bindTexture(GLC.TEXTURE_2D_ARRAY, blockTexture)

            var order = Array(visible.indices)
            if pass == 2 {
                gl.enable(GLC.BLEND)
                gl.blendFunc(GLC.ONE, GLC.ONE_MINUS_SRC_ALPHA)
                gl.depthMask(0)
                order.sort { visible[$0].d2 > visible[$1].d2 }
            }
            for i in order {
                let v = visible[i]
                let quads: Int, base: Int
                switch pass {
                case 0: quads = v.mesh.opaqueQuads; base = 0
                case 1: quads = v.mesh.cutoutQuads; base = v.mesh.opaqueQuads * 4
                default: quads = v.mesh.translucentQuads; base = (v.mesh.opaqueQuads + v.mesh.cutoutQuads) * 4
                }
                guard quads > 0 else { continue }
                gl.uniform4f(program.origin, v.ox, v.oy, v.oz, v.fade)
                gl.uniform3f(program.worldOrigin, Float(Int(v.pos.originX) % 4096), 0, Float(Int(v.pos.originZ) % 4096))
                gl.bindVertexArray(v.mesh.vertexArray)
                gl.drawElementsBaseVertex(GLC.TRIANGLES, Int32(quads * 6), GLC.UNSIGNED_INT, nil, Int32(base))
            }
            if pass == 2 {
                gl.depthMask(1)
                gl.disable(GLC.BLEND)
            }
        }
        if !effects.blended.isEmpty { drawEffects(effects.blended, viewProj: viewProj, sky: sky, fogEnd: fogEnd, blended: true) }
        if !effects.hand.isEmpty {
            gl.clear(GLC.DEPTH_BUFFER_BIT)
            drawEffects(effects.hand, viewProj: viewProj, sky: sky, fogEnd: 10_000, blended: false)
        }
        if post { drawShaderPack(width: width, height: height, time: t) }

        drawOverlay(width: width, height: height, vertices: ui)
        gl.bindVertexArray(0)
    }

    /// Camera-relative triangles: x, y, z, r, g, b, glow per vertex.
    private func drawModels(_ v: [Float], viewProj: Mat4, sky: SkyState, fogEnd: Float) {
        gl.useProgram(modelProgram)
        gl.setMatrix(gl.uniform(modelProgram, "uViewProj"), viewProj)
        gl.uniform4f(gl.uniform(modelProgram, "uFogColorStart"), sky.horizon.x, sky.horizon.y, sky.horizon.z, fogEnd * 0.55)
        gl.uniform1f(gl.uniform(modelProgram, "uFogEnd"), fogEnd)
        gl.uniform1f(gl.uniform(modelProgram, "uDaylight"), sky.daylight)
        gl.bindVertexArray(modelVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, modelBuffer)
        v.withUnsafeBytes { gl.bufferData(GLC.ARRAY_BUFFER, $0.count, $0.baseAddress, GLC.DYNAMIC_DRAW) }
        gl.drawArrays(GLC.TRIANGLES, 0, Int32(v.count / 7))
    }

    private func drawEffects(_ v: [Float], viewProj: Mat4, sky: SkyState, fogEnd: Float, blended: Bool) {
        gl.useProgram(effectProgram)
        gl.setMatrix(gl.uniform(effectProgram, "uViewProj"), viewProj)
        gl.uniform4f(gl.uniform(effectProgram, "uFogColorStart"), sky.horizon.x, sky.horizon.y, sky.horizon.z, fogEnd * 0.55)
        gl.uniform1f(gl.uniform(effectProgram, "uFogEnd"), fogEnd)
        gl.uniform1f(gl.uniform(effectProgram, "uDaylight"), sky.daylight)
        gl.uniform1i(gl.uniform(effectProgram, "uBlocks"), 0)
        gl.uniform1i(gl.uniform(effectProgram, "uItems"), 1)
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindTexture(GLC.TEXTURE_2D_ARRAY, blockTexture)
        gl.activeTexture(GLC.TEXTURE0 + 1)
        gl.bindTexture(GLC.TEXTURE_2D_ARRAY, itemTexture)
        gl.activeTexture(GLC.TEXTURE0)
        if blended {
            gl.enable(GLC.BLEND)
            gl.blendFunc(GLC.ONE, GLC.ONE_MINUS_SRC_ALPHA)
            gl.depthMask(0)
        }
        gl.bindVertexArray(effectVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, effectBuffer)
        v.withUnsafeBytes { gl.bufferData(GLC.ARRAY_BUFFER, $0.count, $0.baseAddress, GLC.DYNAMIC_DRAW) }
        gl.drawArrays(GLC.TRIANGLES, 0, Int32(v.count / EffectBuilder.floatsPerVertex))
        if blended {
            gl.depthMask(1)
            gl.disable(GLC.BLEND)
        }
    }

    /// Points drawing at the offscreen scene (made or resized as needed). Returns false if the driver can't.
    private func bindSceneTarget(width: Int32, height: Int32) -> Bool {
        if let target = sceneTarget, target.width == width, target.height == height {
            gl.bindFramebuffer(GLC.FRAMEBUFFER, target.framebuffer)
            return true
        }
        if let old = sceneTarget {
            var fb = old.framebuffer, depth = old.depth
            gl.deleteFramebuffers(1, &fb)
            gl.deleteRenderbuffers(1, &depth)
            gl.deleteTexture(old.color)
            sceneTarget = nil
        }
        let color = gl.makeTexture()
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindTexture(GLC.TEXTURE_2D, color)
        gl.texImage2D(GLC.TEXTURE_2D, 0, GLC.RGBA16F, width, height, 0, GLC.RGBA, GLC.FLOAT, nil)
        gl.texParameteri(GLC.TEXTURE_2D, GLC.TEXTURE_MIN_FILTER, GLC.LINEAR)
        gl.texParameteri(GLC.TEXTURE_2D, GLC.TEXTURE_MAG_FILTER, GLC.LINEAR)
        gl.texParameteri(GLC.TEXTURE_2D, GLC.TEXTURE_WRAP_S, GLC.CLAMP_TO_EDGE)
        gl.texParameteri(GLC.TEXTURE_2D, GLC.TEXTURE_WRAP_T, GLC.CLAMP_TO_EDGE)
        var depth: UInt32 = 0
        gl.genRenderbuffers(1, &depth)
        gl.bindRenderbuffer(GLC.RENDERBUFFER, depth)
        gl.renderbufferStorage(GLC.RENDERBUFFER, GLC.DEPTH_COMPONENT24, width, height)
        var framebuffer: UInt32 = 0
        gl.genFramebuffers(1, &framebuffer)
        gl.bindFramebuffer(GLC.FRAMEBUFFER, framebuffer)
        gl.framebufferTexture2D(GLC.FRAMEBUFFER, GLC.COLOR_ATTACHMENT0, GLC.TEXTURE_2D, color, 0)
        gl.framebufferRenderbuffer(GLC.FRAMEBUFFER, GLC.DEPTH_ATTACHMENT, GLC.RENDERBUFFER, depth)
        guard gl.checkFramebufferStatus(GLC.FRAMEBUFFER) == GLC.FRAMEBUFFER_COMPLETE else {
            Log.warning("Shader packs aren't available on this graphics driver", category: "Renderer")
            gl.bindFramebuffer(GLC.FRAMEBUFFER, 0)
            gl.deleteFramebuffers(1, &framebuffer)
            gl.deleteRenderbuffers(1, &depth)
            gl.deleteTexture(color)
            shaderPack = 0
            postUnavailable = true
            return false
        }
        sceneTarget = (framebuffer, color, depth, width, height)
        return true
    }

    /// Draws the offscreen scene to the window through the chosen shader pack.
    private func drawShaderPack(width: Int32, height: Int32, time: Float) {
        guard let target = sceneTarget else { return }
        gl.bindFramebuffer(GLC.FRAMEBUFFER, 0)
        gl.viewport(0, 0, width, height)
        gl.disable(GLC.DEPTH_TEST)
        gl.disable(GLC.BLEND)
        gl.useProgram(postProgram)
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindTexture(GLC.TEXTURE_2D, target.color)
        gl.uniform1i(gl.uniform(postProgram, "uScene"), 0)
        gl.uniform4f(gl.uniform(postProgram, "uParams"), Float(shaderPack), time, Float(width), Float(height))
        gl.uniform1f(gl.uniform(postProgram, "uStrength"), shaderStrength)
        gl.uniform1f(gl.uniform(postProgram, "uMono"), mono)
        gl.bindVertexArray(emptyVertexArray)
        gl.drawArrays(GLC.TRIANGLES, 0, 3)
    }

    /// The linear colour of a block texture layer (for untextured stand-ins).
    func blockLayerColor(_ layer: Int) -> SIMD3<Float> {
        layer >= 0 && layer < blockLayerColors.count ? blockLayerColors[layer] : SIMD3(0.5, 0.5, 0.5)
    }

    private func drawOverlay(width: Int32, height: Int32, vertices v: [Float]) {
        guard !v.isEmpty else { return }
        gl.disable(GLC.DEPTH_TEST)
        gl.enable(GLC.BLEND)
        gl.blendFunc(GLC.ONE, GLC.ONE_MINUS_SRC_ALPHA)
        gl.useProgram(overlayProgram)
        gl.uniform2f(gl.uniform(overlayProgram, "uScreen"), Float(width), Float(height))
        gl.uniform1i(gl.uniform(overlayProgram, "uBlocks"), 0)
        gl.uniform1i(gl.uniform(overlayProgram, "uItems"), 1)
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindTexture(GLC.TEXTURE_2D_ARRAY, blockTexture)
        gl.activeTexture(GLC.TEXTURE0 + 1)
        gl.bindTexture(GLC.TEXTURE_2D_ARRAY, itemTexture)
        gl.activeTexture(GLC.TEXTURE0)
        gl.bindVertexArray(overlayVertexArray)
        gl.bindBuffer(GLC.ARRAY_BUFFER, overlayBuffer)
        v.withUnsafeBytes { gl.bufferData(GLC.ARRAY_BUFFER, $0.count, $0.baseAddress, GLC.DYNAMIC_DRAW) }
        gl.drawArrays(GLC.TRIANGLES, 0, Int32(v.count / 9))
        gl.disable(GLC.BLEND)
    }

    /// Reads the back buffer (call before swapping) as a top-down RGBA image.
    func capture(width: Int32, height: Int32) -> PNG.Image {
        let w = Int(width), h = Int(height)
        var bottomUp = [UInt8](repeating: 0, count: w * h * 4)
        gl.pixelStorei(GLC.PACK_ALIGNMENT, 1)
        bottomUp.withUnsafeMutableBytes { gl.readPixels(0, 0, width, height, GLC.RGBA, GLC.UNSIGNED_BYTE, $0.baseAddress) }
        var topDown = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h {
            let src = (h - 1 - y) * w * 4, dst = y * w * 4
            for x in 0..<(w * 4) where x % 4 != 3 { topDown[dst + x] = bottomUp[src + x] }
        }
        return PNG.Image(width: w, height: h, rgba: topDown)
    }
}
