import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// Builds textured, camera-relative triangles for the effects pass:
/// `x, y, z, u, v, layer, r, g, b, a, glow` per vertex (see `Shaders.effectVertex`).
struct EffectBuilder {
    static let floatsPerVertex = 11
    private(set) var vertices: [Float] = []

    var isEmpty: Bool { vertices.isEmpty }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       uv: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>), layer: Float, color: SIMD4<Float>, glow: Float = 0) {
        for (p, t) in [(a, uv.0), (b, uv.1), (c, uv.2), (a, uv.0), (c, uv.2), (d, uv.3)] {
            vertices += [p.x, p.y, p.z, t.x, t.y, layer, color.x, color.y, color.z, color.w, glow]
        }
    }

    /// A camera-facing square around `center` (half-extents `right` and `up`).
    mutating func billboard(_ center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, uv: SIMD2<Float> = .zero, uvSize: Float = 1,
                            layer: Float, color: SIMD4<Float>, glow: Float = 0) {
        quad(center - right + up, center + right + up, center + right - up, center - right - up,
             uv: (uv, uv + SIMD2(uvSize, 0), uv + SIMD2(uvSize, uvSize), uv + SIMD2(0, uvSize)), layer: layer, color: color, glow: glow)
    }

    /// A textured unit cube (-0.5…0.5) transformed by `m`, with one texture layer per face in `BlockFace` order.
    mutating func cube(_ m: Mat4, faceLayers: [Float], light: Float = 1, glow: Float = 0) {
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            let q = m * SIMD4<Float>(x, y, z, 1)
            return SIMD3(q.x, q.y, q.z)
        }
        let uv = (SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        let h: Float = 0.5
        // east, west, up, down, south, north — corners start top-left as seen from outside.
        let faces: [([SIMD3<Float>], Float)] = [
            ([p(h, h, h), p(h, h, -h), p(h, -h, -h), p(h, -h, h)], 0.7),
            ([p(-h, h, -h), p(-h, h, h), p(-h, -h, h), p(-h, -h, -h)], 0.7),
            ([p(-h, h, -h), p(h, h, -h), p(h, h, h), p(-h, h, h)], 1.0),
            ([p(-h, -h, h), p(h, -h, h), p(h, -h, -h), p(-h, -h, -h)], 0.5),
            ([p(-h, h, h), p(h, h, h), p(h, -h, h), p(-h, -h, h)], 0.85),
            ([p(h, h, -h), p(-h, h, -h), p(-h, -h, -h), p(h, -h, -h)], 0.85),
        ]
        for (i, face) in faces.enumerated() {
            let shade = face.1 * light
            quad(face.0[0], face.0[1], face.0[2], face.0[3], uv: uv, layer: faceLayers[i], color: SIMD4(shade, shade, shade, 1), glow: glow)
        }
    }

    /// Local-space geometry of extruded items, per texture layer: position, uv and shade per vertex.
    static var extrusionCache: [Float: [(SIMD3<Float>, SIMD2<Float>, Float)]] = [:]

    /// An item picture given thickness like on the Mac: front and back faces plus a wall along
    /// every edge between solid and see-through pixels (-0.5…0.5, 1/16 thick), transformed by `m`.
    mutating func extruded(_ m: Mat4, layer: Float, mask: [Bool], light: Float = 1, glow: Float = 0) {
        let geometry: [(SIMD3<Float>, SIMD2<Float>, Float)]
        if let cached = EffectBuilder.extrusionCache[layer] {
            geometry = cached
        } else {
            var g: [(SIMD3<Float>, SIMD2<Float>, Float)] = []
            let n = Int(Double(mask.count).squareRoot())
            let t: Float = 1.0 / 32, px = 1 / Float(n)
            func quad(_ p: [SIMD3<Float>], _ uv: [SIMD2<Float>], _ shade: Float) {
                for i in [0, 1, 2, 0, 2, 3] { g.append((p[i], uv[i], shade)) }
            }
            quad([SIMD3(-0.5, 0.5, t), SIMD3(0.5, 0.5, t), SIMD3(0.5, -0.5, t), SIMD3(-0.5, -0.5, t)],
                 [SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)], 1)
            quad([SIMD3(0.5, 0.5, -t), SIMD3(-0.5, 0.5, -t), SIMD3(-0.5, -0.5, -t), SIMD3(0.5, -0.5, -t)],
                 [SIMD2(1, 0), SIMD2(0, 0), SIMD2(0, 1), SIMD2(1, 1)], 0.8)
            func solid(_ x: Int, _ y: Int) -> Bool { x >= 0 && y >= 0 && x < n && y < n && mask[y * n + x] }
            for y in 0..<n {
                for x in 0..<n where solid(x, y) {
                    let x0 = -0.5 + Float(x) * px, x1 = x0 + px
                    let y1 = 0.5 - Float(y) * px, y0 = y1 - px
                    let uv = SIMD2<Float>((Float(x) + 0.5) * px, (Float(y) + 0.5) * px)
                    let uvs = [uv, uv, uv, uv]
                    if !solid(x - 1, y) { quad([SIMD3(x0, y0, -t), SIMD3(x0, y0, t), SIMD3(x0, y1, t), SIMD3(x0, y1, -t)], uvs, 0.7) }
                    if !solid(x + 1, y) { quad([SIMD3(x1, y0, t), SIMD3(x1, y0, -t), SIMD3(x1, y1, -t), SIMD3(x1, y1, t)], uvs, 0.7) }
                    if !solid(x, y - 1) { quad([SIMD3(x0, y1, t), SIMD3(x1, y1, t), SIMD3(x1, y1, -t), SIMD3(x0, y1, -t)], uvs, 0.9) }
                    if !solid(x, y + 1) { quad([SIMD3(x0, y0, -t), SIMD3(x1, y0, -t), SIMD3(x1, y0, t), SIMD3(x0, y0, t)], uvs, 0.55) }
                }
            }
            EffectBuilder.extrusionCache[layer] = g
            geometry = g
        }
        vertices.reserveCapacity(vertices.count + geometry.count * EffectBuilder.floatsPerVertex)
        for (p, uv, shade) in geometry {
            let q = m * SIMD4<Float>(p.x, p.y, p.z, 1)
            let c = shade * light
            vertices += [q.x, q.y, q.z, uv.x, uv.y, layer, c, c, c, 1, glow]
        }
    }

    /// An untextured box from `lo` to `hi` transformed by `m`, shaded per face.
    mutating func box(_ m: Mat4, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>, color: SIMD3<Float>, light: Float = 1) {
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            let q = m * SIMD4<Float>(x, y, z, 1)
            return SIMD3(q.x, q.y, q.z)
        }
        let uv = (SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        let faces: [([SIMD3<Float>], Float)] = [
            ([p(hi.x, hi.y, hi.z), p(hi.x, hi.y, lo.z), p(hi.x, lo.y, lo.z), p(hi.x, lo.y, hi.z)], 0.7),
            ([p(lo.x, hi.y, lo.z), p(lo.x, hi.y, hi.z), p(lo.x, lo.y, hi.z), p(lo.x, lo.y, lo.z)], 0.7),
            ([p(lo.x, hi.y, lo.z), p(hi.x, hi.y, lo.z), p(hi.x, hi.y, hi.z), p(lo.x, hi.y, hi.z)], 1.0),
            ([p(lo.x, lo.y, hi.z), p(hi.x, lo.y, hi.z), p(hi.x, lo.y, lo.z), p(lo.x, lo.y, lo.z)], 0.5),
            ([p(lo.x, hi.y, hi.z), p(hi.x, hi.y, hi.z), p(hi.x, lo.y, hi.z), p(lo.x, lo.y, hi.z)], 0.85),
            ([p(hi.x, hi.y, lo.z), p(lo.x, hi.y, lo.z), p(lo.x, lo.y, lo.z), p(hi.x, lo.y, lo.z)], 0.85),
        ]
        for face in faces {
            let c = color * face.1 * light
            quad(face.0[0], face.0[1], face.0[2], face.0[3], uv: uv, layer: -1, color: SIMD4(c, 1))
        }
    }

    /// A flat item picture (-0.5…0.5 in x and y) transformed by `m`, visible from both sides.
    mutating func card(_ m: Mat4, layer: Float, light: Float = 1) {
        func p(_ x: Float, _ y: Float) -> SIMD3<Float> {
            let q = m * SIMD4<Float>(x, y, 0, 1)
            return SIMD3(q.x, q.y, q.z)
        }
        let c = SIMD4<Float>(light, light, light, 1)
        quad(p(-0.5, 0.5), p(0.5, 0.5), p(0.5, -0.5), p(-0.5, -0.5),
             uv: (SIMD2(0, 0), SIMD2(1, 0), SIMD2(1, 1), SIMD2(0, 1)), layer: layer, color: c)
    }
}

extension WinSolo {
    /// True when an item is drawn as a little block (not a flat picture).
    func isCubeItem(_ info: ItemInfo) -> Bool {
        guard let b = info.block, info.texture == nil else { return false }
        let shape = blocks.shape[Int(b)]
        return shape != .cross && shape != .torch && shape != .wallTorch
    }

    /// Draws an item as a textured cube or a flat card.
    func appendItem(_ fx: inout EffectBuilder, _ item: ItemID, _ m: Mat4, light: Float = 1) {
        guard let info = items[item] else { return }
        if isCubeItem(info), let b = info.block {
            let layers = (0..<6).map { Float(blocks.faceLayers[Int(b) * 6 + $0]) }
            fx.cube(m, faceLayers: layers, light: light, glow: blocks.emission[Int(b)] > 8 ? 1 : 0)
        } else {
            let layer = renderer.iconLayer(item, items: items, blocks: blocks)
            guard layer >= 0 else { return }
            if let mask = renderer.alphaMask(layer: layer) {
                fx.extruded(m, layer: layer, mask: mask, light: light)
            } else {
                fx.card(m, layer: layer, light: light)
            }
        }
    }

    /// Dropped items, particles, rain and snow, and the item in your hand.
    func worldEffects(camera: WinCamera) -> WorldEffects {
        guard let s = session, !s.isLoading else { return WorldEffects() }
        var solid = EffectBuilder(), blended = EffectBuilder(), hand = EffectBuilder()
        let time = clock
        let maxDistance = Double(s.world.renderDistance * 16)
        func rel(_ p: DVec3) -> SIMD3<Float> { SIMD3(Float(p.x - camera.position.x), Float(p.y - camera.position.y), Float(p.z - camera.position.z)) }

        // Dropped items spin and bob, like on the Mac.
        for e in s.entities.items where !e.removed {
            let r = rel(e.position)
            guard Double(simd_length(r)) < maxDistance, let info = items[e.stack.item] else { continue }
            let cube = isCubeItem(info)
            let scale: Float = cube ? 0.25 : 0.42
            let bob = Float(sin((time + e.spinOffset) * 2.6)) * 0.06 + 0.08 + scale * 0.5
            let spin = Float(time * 1.7 + e.spinOffset)
            let copies = e.stack.count > 32 ? 3 : (e.stack.count > 1 ? 2 : 1)
            let light = brightness(s.world.light(at: e.position + DVec3(0, 0.25, 0)))
            for k in 0..<copies {
                let offset = SIMD3<Float>(Float(k) * 0.06, Float(k) * 0.05, Float(k) * -0.05)
                let m = MathUtil.translation(r + SIMD3(0, bob, 0) + offset) * MathUtil.rotationY(spin) * MathUtil.scale(SIMD3(repeating: scale))
                appendItem(&solid, e.stack.item, m, light: light)
            }
        }

        // Camera-facing axes for particles.
        let forward = camera.forward
        let crossRight = simd_cross(forward, SIMD3<Float>(0, 1, 0))
        let flatRight = SIMD3<Float>(Float(cos(camera.yaw)), 0, Float(-sin(camera.yaw)))
        let right = simd_length(crossRight) > 0.05 ? simd_normalize(crossRight) : flatRight
        let up = simd_cross(right, forward)
        for p in particles.particles {
            let r = rel(p.position)
            guard simd_length_squared(r) < 64 * 64 else { continue }
            let t = p.life / p.maxLife
            let size = p.shrink ? p.size * max(0.25, t) : p.size
            var color = p.color
            if p.fade { color.w *= min(1, t * 2.5) }
            if !p.emissive {
                let light = brightness(s.world.light(at: p.position))
                color = SIMD4(color.x * light, color.y * light, color.z * light, color.w)
            }
            blended.billboard(r, right: right * size, up: up * size, uv: p.uv, uvSize: p.uvSize, layer: p.layer >= 0 ? p.layer : -1,
                              color: color, glow: p.emissive ? 1 : 0)
        }

        // Rain streaks and snowflakes around the camera (overworld only).
        let strength = s.weather.intensity
        let precipitation = WeatherSystem.precipitation(for: s.biome)
        if s.dimension == .overworld, strength > 0.02, precipitation != .none {
            let radius = precipitation == .snow ? 12 : 14
            let cx = Int(floor(camera.position.x)), cz = Int(floor(camera.position.z))
            let density = strength * (precipitation == .snow ? 0.5 : 0.85)
            for dz in -radius...radius {
                for dx in -radius...radius where dx * dx + dz * dz <= radius * radius {
                    let x = cx + dx, z = cz + dz
                    guard WinSolo.hash(x, z, 1) < density, let slot = s.world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4))) else { continue }
                    let ground = Double(slot.chunk.heightMap[(z & 15) * 16 + (x & 15)])
                    let top = camera.position.y + 16, bottom = max(ground, camera.position.y - 12)
                    guard top > bottom else { continue }
                    let span = top - bottom
                    for k in 0..<2 {
                        let phase = Double(WinSolo.hash(x, z, 7 + k)) * span
                        let wx = Double(x) + Double(WinSolo.hash(x, z, 20 + k)) - camera.position.x
                        let wz = Double(z) + Double(WinSolo.hash(x, z, 30 + k)) - camera.position.z
                        if precipitation == .rain {
                            let y = top - (time * 15 + phase).truncatingRemainder(dividingBy: span)
                            let c = SIMD3<Float>(Float(wx), Float(y - camera.position.y), Float(wz))
                            blended.billboard(c, right: flatRight * 0.03, up: SIMD3(0, 0.5, 0), layer: -1,
                                              color: SIMD4(0.72, 0.78, 0.9, 0.6 * strength))
                        } else {
                            let y = top - (time * 1.7 + phase).truncatingRemainder(dividingBy: span)
                            let sway = Float(sin(time * 1.3 + phase)) * 0.35
                            let c = SIMD3<Float>(Float(wx) + sway, Float(y - camera.position.y), Float(wz) + sway * 0.6)
                            blended.billboard(c, right: right * 0.055, up: up * 0.055, layer: -1, color: SIMD4(1, 1, 1, 0.9 * strength), glow: 0.5)
                        }
                    }
                }
            }
        }

        // The held item (or your arm), swinging and bobbing like on the Mac.
        if !s.spectator, !hudHidden, cameraView == .firstPerson {
            let stack = s.inventory.selectedStack, info = stack.flatMap { items[$0.item] }
            let t = Float(s.swingProgress)
            let swingA = sin(t * .pi), swingB = sin(sqrt(t) * .pi)
            let equip = Float(s.equipOffset)
            let phase = Float(s.bobPhase * .pi), amount = Float(s.bobAmount)
            let bobX = sin(phase) * 0.018 * amount, bobY = -abs(cos(phase)) * 0.022 * amount
            let view = MathUtil.rotationY(Float(camera.yaw)) * MathUtil.rotationX(Float(camera.pitch))
            let light = brightness(s.world.light(at: s.player.eyePosition))
            let motion = s.hand.motion
            let handMotion = MathUtil.translation(motion.offset) * MathUtil.rotationZ(motion.roll) * MathUtil.rotationY(motion.yaw)
                * MathUtil.rotationX(motion.pitch)
            let local: Mat4
            if let stack, let info {
            if isCubeItem(info) {
                local = MathUtil.translation(SIMD3(0.56 + bobX - swingB * 0.18, -0.46 + bobY - equip * 0.6 + swingA * 0.12, -0.9 - swingA * 0.12))
                    * MathUtil.rotationX(-swingA * 0.9) * MathUtil.rotationY(0.78) * MathUtil.scale(SIMD3(repeating: 0.26))
            } else {
                // A 3D item held at an angle so its thickness shows, like on the Mac
                local = MathUtil.translation(SIMD3(0.5 + bobX - swingB * 0.16, -0.38 + bobY - equip * 0.6 + swingA * 0.1, -0.76 - swingA * 0.1))
                    * MathUtil.rotationX(-swingA * 1.2) * MathUtil.rotationY(-1.25) * MathUtil.rotationZ(0.35) * MathUtil.scale(SIMD3(repeating: 0.55))
            }
            appendItem(&hand, stack.item, view * handMotion * local, light: light)
            } else {
                // Empty hand: your gloved arm
                local = MathUtil.translation(SIMD3(0.56 + bobX - swingB * 0.2, -0.54 + bobY - equip * 0.5 + swingA * 0.16, -0.4 - swingA * 0.18))
                    * MathUtil.rotationY(-0.28) * MathUtil.rotationX(0.45 - swingA * 1.1)
                let m = view * handMotion * local
                let skin = SIMD3<Float>(0.8, 0.58, 0.42), glove = SIMD3<Float>(0.36, 0.24, 0.16), cuff = SIMD3<Float>(0.62, 0.42, 0.18)
                hand.box(m, SIMD3(-0.1, -0.1, -0.55), SIMD3(0.1, 0.1, -0.22), color: glove * glove, light: light)
                hand.box(m, SIMD3(-0.105, -0.105, -0.25), SIMD3(0.105, 0.105, -0.17), color: cuff * cuff, light: light)
                hand.box(m, SIMD3(-0.095, -0.095, -0.17), SIMD3(0.095, 0.095, 0.4), color: skin * skin, light: light)
            }
        }
        return WorldEffects(solid: solid.vertices, blended: blended.vertices, hand: hand.vertices)
    }

    /// How lit something is from its sky and torch light (never fully black).
    private func brightness(_ light: (sky: Float, block: Float)) -> Float { max(0.35, light.sky, light.block * 0.95) }

    static func hash(_ x: Int, _ z: Int, _ k: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: (x &* 73_856_093) ^ (z &* 19_349_663) ^ (k &* 83_492_791))
        h ^= h >> 13
        h = h &* 1_274_126_177
        h ^= h >> 16
        return Float(h & 0xFFFF) / 65535
    }
}
