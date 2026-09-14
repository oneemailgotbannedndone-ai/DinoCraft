import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Blocky explorer avatars for other players; shirt colour derives from the username.
final class PlayerModelLibrary {
    private struct Part { let mesh: ModelMesh; let pivot: SIMD3<Float>; let kind: Int }  // 0 body 1 head 2 armL 3 armR 4 legL 5 legR
    private var cache: [UInt32: [Part]] = [:]
    let device: MTLDevice

    init(device: MTLDevice) { self.device = device }

    private func parts(shirt: UInt32) -> [Part] {
        if let p = cache[shirt] { return p }
        let c = MobModelLibrary.c
        let skin = c(0xD9A77E), hat = c(0xC8A46A), band = c(0x6A4A2A), pants = c(0x5A4632), boots = c(0x3A2A1E), shirtColor = c(shirt)
        let belt = c(0x2A2016), eye = c(0x2A1E14)
        func part(_ kind: Int, _ pivot: SIMD3<Float>, _ boxes: [(SIMD3<Float>, SIMD3<Float>, SIMD4<Float>)]) -> Part? {
            var v: [ModelVertex] = []
            for b in boxes { ModelBuilder.box(&v, min: b.0, max: b.1, color: b.2) }
            return ModelMesh(device: device, vertices: v, label: "Player part").map { Part(mesh: $0, pivot: pivot, kind: kind) }
        }
        let list = [
            part(0, SIMD3(0, 0.75, 0), [(SIMD3(-0.25, 0, -0.13), SIMD3(0.25, 0.72, 0.13), shirtColor),
                                        (SIMD3(-0.26, 0, -0.14), SIMD3(0.26, 0.07, 0.14), belt)]),
            part(1, SIMD3(0, 1.47, 0), [(SIMD3(-0.22, 0, -0.22), SIMD3(0.22, 0.42, 0.22), skin),
                                        (SIMD3(-0.13, 0.22, -0.23), SIMD3(-0.06, 0.28, -0.22), eye),
                                        (SIMD3(0.06, 0.22, -0.23), SIMD3(0.13, 0.28, -0.22), eye),
                                        (SIMD3(-0.34, 0.38, -0.34), SIMD3(0.34, 0.43, 0.34), hat),
                                        (SIMD3(-0.24, 0.43, -0.24), SIMD3(0.24, 0.62, 0.24), hat),
                                        (SIMD3(-0.245, 0.43, -0.245), SIMD3(0.245, 0.49, 0.245), band)]),
            part(2, SIMD3(-0.37, 1.4, 0), [(SIMD3(-0.12, -0.66, -0.12), SIMD3(0.12, 0.04, 0.12), shirtColor),
                                           (SIMD3(-0.115, -0.72, -0.115), SIMD3(0.115, -0.5, 0.115), skin)]),
            part(3, SIMD3(0.37, 1.4, 0), [(SIMD3(-0.12, -0.66, -0.12), SIMD3(0.12, 0.04, 0.12), shirtColor),
                                          (SIMD3(-0.115, -0.72, -0.115), SIMD3(0.115, -0.5, 0.115), skin)]),
            part(4, SIMD3(-0.13, 0.75, 0), [(SIMD3(-0.12, -0.75, -0.12), SIMD3(0.12, 0, 0.12), pants),
                                            (SIMD3(-0.125, -0.75, -0.14), SIMD3(0.125, -0.58, 0.13), boots)]),
            part(5, SIMD3(0.13, 0.75, 0), [(SIMD3(-0.12, -0.75, -0.12), SIMD3(0.12, 0, 0.12), pants),
                                           (SIMD3(-0.125, -0.75, -0.14), SIMD3(0.125, -0.58, 0.13), boots)]),
        ].compactMap { $0 }
        cache[shirt] = list
        return list
    }

    static let shirtPalette: [UInt32] = [0x3A7BD5, 0xD5563A, 0x3AA66A, 0x9A4AD5, 0xD5A33A, 0x2FB5B0, 0xD54A8A, 0x6A7A3A]

    static func shirt(for name: String) -> UInt32 {
        shirtPalette[Int(Hashing.seed(from: name.lowercased()) % UInt64(shirtPalette.count))]
    }

    func encode(_ enc: MTLRenderCommandEncoder, players: [RemotePlayer], world: World, camera: Camera,
                frame: inout FrameUniforms, renderer: ModelRenderer, items: ItemRegistry) {
        guard !players.isEmpty else { return }
        renderer.begin(enc, &frame)
        for p in players where !p.dead {
            let rel = SIMD3<Float>(Float(p.position.x - camera.position.x), Float(p.position.y - camera.position.y),
                                   Float(p.position.z - camera.position.z))
            let light = world.light(at: p.position + DVec3(0, 1.5, 0))
            let tint: SIMD4<Float> = p.hurtTimer > 0 ? SIMD4(0.9, 0.1, 0.1, Float(p.hurtTimer / 0.35) * 0.6) : .zero
            let base = MathUtil.translation(rel - SIMD3(0, p.sneaking ? 0.25 : 0, 0)) * MathUtil.rotationY(Float(p.yaw))
            let swingLeg = Float(sin(p.walkPhase)) * 0.8 * Float(min(1, p.moving))
            let armSwing = Float(sin(p.swing * .pi))
            for part in parts(shirt: PlayerModelLibrary.shirt(for: p.name)) {
                var local = MathUtil.translation(part.pivot)
                switch part.kind {
                case 0: if p.sneaking { local = local * MathUtil.rotationX(-0.4) }
                case 1: local = local * MathUtil.rotationX(Float(p.pitch) * 0.8)
                case 2: local = local * MathUtil.rotationX(swingLeg)
                case 3: local = local * MathUtil.rotationX(-swingLeg - armSwing * 1.6)
                case 4: local = local * MathUtil.rotationX(-swingLeg)
                default: local = local * MathUtil.rotationX(swingLeg)
                }
                let model = base * local
                var u = ModelUniforms(mvp: frame.viewProj * model, model: model, light: SIMD4(light.sky, light.block, 0, 0),
                                      tint: tint, viewPos: SIMD4(rel, 1))
                renderer.draw(enc, part.mesh, uniforms: &u)
            }
            if let heldName = p.held, let info = items.info(named: heldName), let mesh = renderer.mesh(for: info) {
                let hand = base * MathUtil.translation(SIMD3(0.37, 1.4, 0)) * MathUtil.rotationX(-swingLeg - armSwing * 1.6)
                    * MathUtil.translation(SIMD3(0, -0.72, -0.18)) * MathUtil.rotationX(-.pi / 2)
                    * MathUtil.scale(SIMD3(repeating: renderer.isCube(info) ? 0.25 : 0.45))
                var u = ModelUniforms(mvp: frame.viewProj * hand, model: hand, light: SIMD4(light.sky, light.block, 0, 0),
                                      tint: .zero, viewPos: SIMD4(rel, 1))
                renderer.draw(enc, mesh, uniforms: &u)
            }
        }
    }
}
