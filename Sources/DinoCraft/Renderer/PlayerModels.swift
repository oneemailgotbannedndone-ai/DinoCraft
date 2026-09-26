import Foundation
import Metal
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Blocky explorer avatars for other players, wearing the cosmetics they chose (see `PlayerAvatar`).
final class PlayerModelLibrary {
    private struct Part { let mesh: ModelMesh; let pivot: SIMD3<Float>; let kind: Int }
    private var cache: [String: [Part]] = [:]
    let device: MTLDevice

    init(device: MTLDevice) { self.device = device }

    private func parts(_ look: PlayerLook) -> [Part] {
        let key = look.encoded
        if let p = cache[key] { return p }
        let list: [Part] = PlayerAvatar.parts(look).compactMap { part in
            var v: [ModelVertex] = []
            for b in part.boxes { ModelBuilder.box(&v, min: b.0, max: b.1, color: b.2) }
            return ModelMesh(device: device, vertices: v, label: "Player part").map { Part(mesh: $0, pivot: part.pivot, kind: part.kind) }
        }
        cache[key] = list
        return list
    }

    func encode(_ enc: MTLRenderCommandEncoder, players: [RemotePlayer], world: World, camera: Camera,
                frame: inout FrameUniforms, renderer: ModelRenderer, items: ItemRegistry) {
        guard !players.isEmpty else { return }
        renderer.begin(enc, &frame)
        for p in players where !p.dead {
            let rel = SIMD3<Float>(Float(p.position.x - camera.position.x), Float(p.position.y - camera.position.y),
                                   Float(p.position.z - camera.position.z))
            // Skip a friend standing right where the camera is (you'd see the inside of their model).
            if simd_length(rel + SIMD3(0, 0.9, 0)) < 1.0 { continue }
            let light = world.light(at: p.position + DVec3(0, 1.5, 0))
            let tint: SIMD4<Float> = p.hurtTimer > 0 ? SIMD4(0.9, 0.1, 0.1, Float(p.hurtTimer / 0.35) * 0.6) : .zero
            let base = MathUtil.translation(rel - SIMD3(0, p.sneaking ? 0.25 : 0, 0)) * MathUtil.rotationY(Float(p.yaw))
            let idle = Float(Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 3600)) + Float(p.name.hashValue & 63)
            for part in parts(PlayerLook.resolve(p.look, name: p.name)) {
                let local = MathUtil.translation(part.pivot)
                    * PlayerAvatar.pose(kind: part.kind, pitch: Float(p.pitch), walk: Float(p.walkPhase), moving: Float(p.moving),
                                        sneaking: p.sneaking, swing: Float(p.swing), idle: idle)
                let model = base * local
                var u = ModelUniforms(mvp: frame.viewProj * model, model: model, light: SIMD4(light.sky, light.block, 0, 0),
                                      tint: tint, viewPos: SIMD4(rel, 1))
                renderer.draw(enc, part.mesh, uniforms: &u)
            }
            if let heldName = p.held, let info = items.info(named: heldName), let mesh = renderer.mesh(for: info) {
                let hand = base * MathUtil.translation(SIMD3(0.37, 1.4, 0))
                    * PlayerAvatar.pose(kind: 3, pitch: 0, walk: Float(p.walkPhase), moving: Float(p.moving), sneaking: p.sneaking,
                                        swing: Float(p.swing), idle: idle)
                    * MathUtil.translation(SIMD3(0, -0.72, -0.18)) * MathUtil.rotationX(-.pi / 2)
                    * MathUtil.scale(SIMD3(repeating: renderer.isCube(info) ? 0.25 : 0.45))
                var u = ModelUniforms(mvp: frame.viewProj * hand, model: hand, light: SIMD4(light.sky, light.block, 0, 0),
                                      tint: .zero, viewPos: SIMD4(rel, 1))
                renderer.draw(enc, mesh, uniforms: &u)
            }
        }
    }
}
