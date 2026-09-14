import Foundation
import DinoCraftCore

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
    private let blockTexture: UInt32
    private let itemTexture: UInt32
    /// Texture-array layer for each block and item texture name.
    let blockLayers: [String: UInt16]
    let itemLayers: [String: UInt16]
    private let quadIndices: UInt32
    private let maxQuads = 1 << 18
    private let emptyVertexArray: UInt32
    private let overlayVertexArray: UInt32
    private let overlayBuffer: UInt32
    private let modelVertexArray: UInt32
    private let modelBuffer: UInt32
    private(set) var visibleChunks = 0

    init(gl: GL, blocks: BlockRegistry, items: ItemRegistry) throws {
        self.gl = gl
        chunkPrograms = try ["OPAQUE", "CUTOUT", "TRANSLUCENT"].map { pass in
            ChunkProgram(gl: gl, id: try gl.makeProgram(vertex: Shaders.chunkVertex, fragment: Shaders.chunkFragment(pass: pass), label: "chunk \(pass)"))
        }
        skyProgram = try gl.makeProgram(vertex: Shaders.skyVertex, fragment: Shaders.skyFragment, label: "sky")
        overlayProgram = try gl.makeProgram(vertex: Shaders.overlayVertex, fragment: Shaders.overlayFragment, label: "overlay")
        modelProgram = try gl.makeProgram(vertex: Shaders.boxVertex, fragment: Shaders.boxFragment, label: "models")

        let blockArray = WinRenderer.loadTextureArray(gl: gl, names: blocks.textureNames, folders: ["blocks"])
        blockTexture = blockArray.texture
        blockLayers = blockArray.layers
        let layers = blockArray.layers
        blocks.bindTextureLayers { layers[$0] ?? 0 }
        let itemArray = WinRenderer.loadTextureArray(gl: gl, names: items.textureNames, folders: ["items", "blocks"])
        itemTexture = itemArray.texture
        itemLayers = itemArray.layers
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
    }

    /// Loads 32×32 PNGs into an sRGB texture array (premultiplied alpha), trying each folder in order.
    private static func loadTextureArray(gl: GL, names rawNames: [String], folders: [String]) -> (texture: UInt32, layers: [String: UInt16]) {
        var seen = Set<String>()
        let names = rawNames.filter { seen.insert($0).inserted }
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4 * max(1, names.count))
        var layers: [String: UInt16] = [:]
        var missing = 0
        for (i, name) in names.enumerated() {
            layers[name] = UInt16(i)
            var rgba: [UInt8]?
            for folder in folders where rgba == nil {
                if let url = try? ResourceLocator.url("Textures/\(folder)/\(name).png"),
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
        return (texture, layers)
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
    func renderMenu(width: Int32, height: Int32, time: Double, ui: [Float]) {
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
        drawSky(camera: camera, aspect: aspect, sky: SkyState.at(worldTime: 520 + time * 0.5), time: Float(time.truncatingRemainder(dividingBy: 3600)))
        drawOverlay(width: width, height: height, vertices: ui)
        gl.bindVertexArray(0)
    }

    func render(world: WinWorld, camera: WinCamera, sky: SkyState, time: Double, now: Double,
                width: Int32, height: Int32, ui: [Float], models: [Float] = []) {
        let aspect = Float(width) / Float(max(1, height))
        let viewProj = camera.viewProjection(aspect: aspect)
        let t = Float(time.truncatingRemainder(dividingBy: 3600))

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
            guard let mesh = slot.mesh else { continue }
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
            if pass == 2 && !models.isEmpty { drawModels(models, viewProj: viewProj, sky: sky, fogEnd: fogEnd) }
            gl.useProgram(program.id)
            gl.setMatrix(program.viewProj, viewProj)
            gl.uniform1f(program.time, t)
            gl.uniform1i(program.blocks, 0)
            gl.uniform4f(program.sunDaylight, sky.sunDirection.x, sky.sunDirection.y, sky.sunDirection.z, sky.daylight)
            gl.uniform3f(program.skyLight, sky.skyLight.x, sky.skyLight.y, sky.skyLight.z)
            gl.uniform4f(program.fogColorStart, sky.horizon.x, sky.horizon.y, sky.horizon.z, fogEnd * 0.55)
            gl.uniform2f(program.fogParams, fogEnd, 0)
            gl.uniform3f(program.skyHorizon, sky.horizon.x, sky.horizon.y, sky.horizon.z)
            gl.uniform1f(program.brightness, 0.5)
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
