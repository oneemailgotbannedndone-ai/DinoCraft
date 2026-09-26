import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

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
        for burst in s.effectBursts { emitBurst(burst.kind, at: burst.position) }
        s.effectBursts.removeAll()
        ambient(dt: dt, session: s, blocks: blocks)
    }

    /// Big one-off effects: a stomp's dust ring, cheer-up confetti, a splash of mud.
    func emitBurst(_ kind: EffectBurst, at center: DVec3) {
        switch kind {
        case .dust:
            for k in 0..<60 {
                let a = Double(k) / 60 * 2 * .pi
                var p = Particle(center + DVec3(cos(a) * 1.5, 0.2, sin(a) * 1.5), DVec3(cos(a) * 7, Double.random(in: 0.5...2), sin(a) * 7),
                                 life: 0.9, size: 0.18, color: SIMD4(0.85, 0.85, 0.85, 0.8))
                p.drag = 2.5
                p.shrink = true
                emit(p)
            }
        case .confetti:
            let colors: [SIMD4<Float>] = [SIMD4(1, 0.3, 0.3, 1), SIMD4(1, 0.85, 0.2, 1), SIMD4(0.3, 0.8, 1, 1), SIMD4(0.5, 1, 0.4, 1), SIMD4(1, 0.5, 0.9, 1), SIMD4(1, 1, 1, 1)]
            for k in 0..<220 {
                var p = Particle(center, DVec3(Double.random(in: -6...6), Double.random(in: 4...12), Double.random(in: -6...6)),
                                 life: Float.random(in: 2...3.5), size: 0.09, color: colors[k % colors.count])
                p.layer = -2
                p.gravity = 7
                p.drag = 1.2
                p.emissive = true
                emit(p)
            }
        case .crumbs:
            for _ in 0..<10 {
                var p = Particle(center + DVec3(Double.random(in: -0.1...0.1), 0, Double.random(in: -0.1...0.1)),
                                 DVec3(Double.random(in: -0.8...0.8), Double.random(in: 0.5...1.5), Double.random(in: -0.8...0.8)),
                                 life: 0.6, size: 0.035, color: SIMD4(0.72, 0.52, 0.3, 1))
                p.layer = -2
                p.gravity = 12
                emit(p)
            }
        case .splash:
            for _ in 0..<18 {
                var p = Particle(center + DVec3(Double.random(in: -0.15...0.15), 0, Double.random(in: -0.15...0.15)),
                                 DVec3(Double.random(in: -1.4...1.4), Double.random(in: 2...4.5), Double.random(in: -1.4...1.4)),
                                 life: Float.random(in: 0.4...0.8), size: 0.05, color: SIMD4(0.75, 0.88, 1, 0.9))
                p.layer = -2
                p.gravity = 14
                p.fade = true
                emit(p)
            }
        case .smoke:
            // A volcano's plume: big dark puffs billowing up and spreading.
            for _ in 0..<6 {
                var p = Particle(center + DVec3(Double.random(in: -2...2), Double.random(in: 0...1.5), Double.random(in: -2...2)),
                                 DVec3(Double.random(in: -1.2...1.2), Double.random(in: 4...8), Double.random(in: -1.2...1.2)),
                                 life: Float.random(in: 3.5...6), size: Float.random(in: 0.9...1.6), color: SIMD4(0.2, 0.18, 0.18, 0.7))
                p.drag = 0.35
                emit(p)
            }
        case .lavaSpray:
            for _ in 0..<24 {
                var p = Particle(center, DVec3(Double.random(in: -5...5), Double.random(in: 6...14), Double.random(in: -5...5)),
                                 life: Float.random(in: 1...2), size: Float.random(in: 0.08...0.16), color: SIMD4(1, Float.random(in: 0.35...0.7), 0.1, 1))
                p.layer = -2
                p.gravity = 14
                p.emissive = true
                p.shrink = true
                emit(p)
            }
        case .impact:
            // A fireball hitting the ground: sparks, rock chips and a smoke ring.
            for k in 0..<70 {
                let a = Double(k) / 70 * 2 * .pi
                var p = Particle(center, DVec3(cos(a) * Double.random(in: 3...9), Double.random(in: 3...10), sin(a) * Double.random(in: 3...9)),
                                 life: Float.random(in: 0.6...1.4), size: Float.random(in: 0.06...0.14),
                                 color: k % 3 == 0 ? SIMD4(0.3, 0.26, 0.24, 1) : SIMD4(1, Float.random(in: 0.4...0.85), 0.15, 1))
                p.layer = -2
                p.gravity = 16
                p.emissive = k % 3 != 0
                p.collide = true
                emit(p)
            }
            for k in 0..<24 {
                let a = Double(k) / 24 * 2 * .pi
                var p = Particle(center + DVec3(0, 0.3, 0), DVec3(cos(a) * 4, Double.random(in: 0.5...2), sin(a) * 4),
                                 life: 2.2, size: 0.7, color: SIMD4(0.3, 0.28, 0.27, 0.6))
                p.drag = 1.5
                emit(p)
            }
        case .trail:
            // Behind a lava bomb or meteorite: a glowing ember and a wisp of smoke.
            var ember = Particle(center, DVec3(Double.random(in: -0.4...0.4), Double.random(in: -0.2...0.6), Double.random(in: -0.4...0.4)),
                                 life: 0.5, size: 0.22, color: SIMD4(1, 0.55, 0.12, 1))
            ember.emissive = true
            ember.shrink = true
            emit(ember)
            var smoke = Particle(center, DVec3(0, 0.8, 0), life: 1.6, size: 0.35, color: SIMD4(0.25, 0.22, 0.22, 0.45))
            smoke.drag = 0.8
            emit(smoke)
        case .starTrail:
            var p = Particle(center, .zero, life: 0.7, size: 0.35, color: SIMD4(0.85, 0.9, 1, 1))
            p.emissive = true
            p.shrink = true
            emit(p)
        case .ink:
            for _ in 0..<80 {
                var p = Particle(center + DVec3(Double.random(in: -1...1), Double.random(in: 0...3), Double.random(in: -1...1)),
                                 DVec3(Double.random(in: -3...3), Double.random(in: 1...5), Double.random(in: -3...3)),
                                 life: 1.4, size: 0.16, color: SIMD4(0.14, 0.09, 0.05, 1))   // thick mud
                p.gravity = 9
                p.collide = true
                emit(p)
            }
        }
    }

    private func ambient(dt: Double, session s: GameSession, blocks: BlockRegistry) {
        let world = s.world
        let eye = s.player.eyePosition

        // Rain splashes where drops land near the player.
        if s.dimension == .overworld, s.weather.intensity > 0.2, s.precipitation == .rain {
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
        } else if s.dimension == .toonland {
            // Happy bubbles drifting up through the air.
            for _ in 0..<2 {
                var p = Particle(eye + DVec3(Double.random(in: -12...12), Double.random(in: -5...5), Double.random(in: -12...12)),
                                 DVec3(Double.random(in: -0.15...0.15), Double.random(in: 0.25...0.6), Double.random(in: -0.15...0.15)),
                                 life: 4, size: 0.07, color: SIMD4(1, 1, 1, 0.75))
                p.emissive = true
                p.shrink = true
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
            } else if WorldDimension.forPortal(id) != nil, Int.random(in: 0..<3) == 0 {
                let tint: SIMD4<Float> = id == Blocks.underworldPortal ? SIMD4(1, 0.35, 0.45, 1)
                    : (id == Blocks.toonlandPortal ? SIMD4(1, 1, 1, 1) : SIMD4(1, 0.8, 0.35, 1))
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
                        wanted = id == Blocks.torch || Blocks.wallTorch.contains(id) || WorldDimension.forPortal(id) != nil
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
