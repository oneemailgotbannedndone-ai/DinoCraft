import Foundation
import DinoCraftCore
@testable import DinoCraftGame

// Creature and player models for the Windows renderer. The creature box definitions are copied from
// Sources/DinoCraft/Renderer/MobModels.swift and the player from PlayerModels.swift (keep them in sync).

/// Creature kinds, matching `MobKind` raw values in the Mac app.
enum CreatureKind: String, CaseIterable {
    case trikey, dodo, longneck, raptor, spitter, crawler, magmaRaptor, villager, stego, ankylo, rex, compy, ptero, parasaur,
         sailback, boneWalker, scorpion, pig, cow, sheep, chicken, pookpook, carnotaurus, allosaurus, baryonyx, troodon, spinosaurus,
         grumblesaurus, grinasaurus, cod, salmon, clownfish, blueTang,
         pachy, iguanodon, therizino, gallimimus, oviraptor, microraptor, boat, egg
}

enum PartRole {
    case body
    case head
    case leg(Float)
    case tail
    case segment(Int)
    case wing(Float)
}

struct CreaturePart {
    let role: PartRole
    let pivot: SIMD3<Float>
    let boxes: [(SIMD3<Float>, SIMD3<Float>, SIMD4<Float>, Bool)]
}

enum CreatureModels {
    static func c(_ hex: UInt32) -> SIMD4<Float> {
        func lin(_ v: UInt32) -> Float {
            let x = Float(v) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return SIMD4(lin((hex >> 16) & 0xFF), lin((hex >> 8) & 0xFF), lin(hex & 0xFF), 1)
    }

    typealias Box = (SIMD3<Float>, SIMD3<Float>, SIMD4<Float>, Bool)

    private struct Builder {
        var parts: [CreaturePart] = []
        mutating func add(_ role: PartRole, _ pivot: SIMD3<Float>, _ boxes: [Box]) {
            parts.append(CreaturePart(role: role, pivot: pivot, boxes: boxes))
        }
    }

    private static func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float,
                          _ col: SIMD4<Float>, glow: Bool = false, s: Float = 1) -> Box {
        (SIMD3(x0, y0, z0) * s, SIMD3(x1, y1, z1) * s, col, glow)
    }

    /// A fish seen side-on along -Z: slim body, eyes, dorsal fin, wagging tail and paddling side fins.
    private static func fish(_ m: inout Builder, body: SIMD4<Float>, belly: SIMD4<Float>, fin: SIMD4<Float>, tail: SIMD4<Float>,
                             stripe: SIMD4<Float>?, tall: Float, s: Float) {
        let h0: Float = 0.06, h1: Float = 0.06 + 0.22 * tall, mid = (h0 + h1) / 2
        let eye = c(0x111111)
        var boxes = [b(-0.07, h0, -0.22, 0.07, h1, 0.18, body, s: s), b(-0.066, h0 - 0.02, -0.18, 0.066, h0 + 0.05, 0.14, belly, s: s),
                     b(-0.012, h1, -0.1, 0.012, h1 + 0.07 * tall, 0.1, fin, s: s),
                     b(-0.074, mid, -0.19, -0.066, mid + 0.04, -0.15, eye, s: s), b(0.066, mid, -0.19, 0.074, mid + 0.04, -0.15, eye, s: s)]
        if let stripe {
            boxes += [b(-0.075, h0, -0.13, 0.075, h1, -0.09, stripe, s: s), b(-0.075, h0, 0.03, 0.075, h1, 0.07, stripe, s: s)]
        }
        m.add(.body, .zero, boxes)
        m.add(.head, SIMD3(0, mid, -0.22) * s, [b(-0.055, -(mid - h0) * 0.75, -0.07, 0.055, (h1 - mid) * 0.7, 0.0, body, s: s)])
        m.add(.tail, SIMD3(0, mid, 0.18) * s, [b(-0.02, -0.035, 0, 0.02, 0.035, 0.06, body, s: s),
                                              b(-0.01, -0.13 * tall, 0.05, 0.01, 0.13 * tall, 0.17, tail, s: s)])
        m.add(.wing(-1), SIMD3(-0.07, h0 + 0.05, -0.1) * s, [b(-0.09, -0.01, -0.03, 0, 0.01, 0.05, fin, s: s)])
        m.add(.wing(1), SIMD3(0.07, h0 + 0.05, -0.1) * s, [b(0, -0.01, -0.03, 0.09, 0.01, 0.05, fin, s: s)])
    }

    private static func role(_ r: ShapeRole) -> PartRole {
        switch r {
        case .body: return .body
        case .head: return .head
        case .tail: return .tail
        case .leg(let phase): return .leg(phase)
        case .segment(let i): return .segment(i)
        case .wing(let side): return .wing(side)
        }
    }

    static func build(_ kind: CreatureKind, variant: Int = 0) -> [CreaturePart] {
        // Villagers and the newer dinosaurs share one definition with the Mac.
        if let mob = MobKind(rawValue: kind.rawValue), let shared = CreatureShapes.parts(mob, variant: variant) {
            return shared.map { part in CreaturePart(role: role(part.role), pivot: part.pivot, boxes: part.boxes.map { ($0.min, $0.max, c($0.color), $0.glow) }) }
        }
        var m = Builder()
        switch kind {
        case .trikey:
            let body = c(0x7FA35A), belly = c(0xC9B37A), frill = c(0xD9824A), horn = c(0xF2EBD6), dark = c(0x5A7A3E)
            m.add(.body, .zero, [b(-0.42, 0.38, -0.55, 0.42, 0.95, 0.6, body), b(-0.38, 0.34, -0.5, 0.38, 0.4, 0.55, belly),
                                 b(-0.3, 0.95, -0.4, 0.3, 1.0, 0.45, dark)])
            m.add(.head, SIMD3(0, 0.72, -0.55), [b(-0.28, -0.22, -0.5, 0.28, 0.2, 0.02, body), b(-0.46, -0.08, -0.06, 0.46, 0.48, 0.04, frill),
                                                 b(-0.22, 0.1, -0.68, -0.13, 0.19, -0.36, horn), b(0.13, 0.1, -0.68, 0.22, 0.19, -0.36, horn),
                                                 b(-0.05, -0.06, -0.64, 0.05, 0.06, -0.48, horn), b(-0.2, -0.24, -0.46, 0.2, -0.16, -0.1, belly),
                                                 b(-0.29, 0.02, -0.34, -0.27, 0.08, -0.28, c(0x1A1A1A)), b(0.27, 0.02, -0.34, 0.29, 0.08, -0.28, c(0x1A1A1A))])
            for (x, z, phase) in [(-0.28, -0.35, Float(0)), (0.28, -0.35, .pi), (-0.28, 0.4, .pi), (0.28, 0.4, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.42, z), [b(-0.11, -0.42, -0.11, 0.11, 0.02, 0.11, dark)])
            }
            m.add(.tail, SIMD3(0, 0.72, 0.58), [b(-0.13, -0.12, 0, 0.13, 0.1, 0.55, body), b(-0.07, -0.08, 0.5, 0.07, 0.05, 0.8, dark)])

        case .dodo:
            let body = c(0x8A9BA8), belly = c(0xE8E4D8), beak = c(0xE8B84A)
            m.add(.body, .zero, [b(-0.25, 0.35, -0.3, 0.25, 0.75, 0.3, body), b(-0.22, 0.33, -0.26, 0.22, 0.4, 0.2, belly)])
            m.add(.head, SIMD3(0, 0.72, -0.25), [b(-0.14, 0, -0.18, 0.14, 0.3, 0.06, body), b(-0.06, 0.06, -0.38, 0.06, 0.16, -0.18, beak),
                                                 b(-0.15, 0.18, -0.12, -0.13, 0.23, -0.07, c(0x111111)), b(0.13, 0.18, -0.12, 0.15, 0.23, -0.07, c(0x111111))])
            m.add(.leg(0), SIMD3(-0.12, 0.38, 0), [b(-0.04, -0.38, -0.04, 0.04, 0, 0.04, beak), b(-0.06, -0.38, -0.12, 0.06, -0.34, 0.04, beak)])
            m.add(.leg(.pi), SIMD3(0.12, 0.38, 0), [b(-0.04, -0.38, -0.04, 0.04, 0, 0.04, beak), b(-0.06, -0.38, -0.12, 0.06, -0.34, 0.04, beak)])
            m.add(.tail, SIMD3(0, 0.6, 0.3), [b(-0.14, -0.05, 0, 0.14, 0.2, 0.16, belly)])

        case .longneck:
            let body = c(0x6E8F7A), belly = c(0xA8B898), spot = c(0x4E6A5A)
            m.add(.body, .zero, [b(-0.8, 1.4, -1.1, 0.8, 2.5, 1.2, body), b(-0.72, 1.32, -0.95, 0.72, 1.42, 1.05, belly),
                                 b(-0.5, 2.5, -0.6, -0.1, 2.56, -0.2, spot), b(0.2, 2.5, 0.2, 0.6, 2.56, 0.6, spot), b(-0.3, 2.5, 0.7, 0.1, 2.56, 1.0, spot)])
            var neck: [Box] = []
            for i in 0..<6 {
                let fi = Float(i)
                neck.append(b(-0.22, fi * 0.3, -0.12 - fi * 0.14, 0.22, fi * 0.3 + 0.42, 0.28 - fi * 0.14, i % 2 == 0 ? body : belly))
            }
            neck.append(b(-0.26, 1.7, -1.2, 0.26, 2.05, -0.6, body))
            neck.append(b(-0.27, 1.85, -1.0, -0.25, 1.92, -0.92, c(0x111111)))
            neck.append(b(0.25, 1.85, -1.0, 0.27, 1.92, -0.92, c(0x111111)))
            m.add(.head, SIMD3(0, 2.2, -1.0), neck)
            for (x, z, phase) in [(-0.55, -0.8, Float(0)), (0.55, -0.8, .pi), (-0.55, 0.9, .pi), (0.55, 0.9, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 1.5, z), [b(-0.22, -1.5, -0.22, 0.22, 0, 0.22, body), b(-0.24, -1.5, -0.24, 0.24, -1.3, 0.24, spot)])
            }
            m.add(.tail, SIMD3(0, 2.0, 1.2), [b(-0.2, -0.2, 0, 0.2, 0.15, 1.6, body), b(-0.1, -0.35, 1.5, 0.1, -0.12, 2.4, body)])

        case .raptor:
            raptor(&m, body: c(0x8A5A3A), stripe: c(0x4A2A1A), belly: c(0xD8B890), glow: false, frill: nil, s: 1)
        case .magmaRaptor:
            raptor(&m, body: c(0x2A2228), stripe: c(0xFF7A1A), belly: c(0x4A3A40), glow: true, frill: nil, s: 1.08)
        case .spitter:
            raptor(&m, body: c(0x4F8A3A), stripe: c(0x2F5A22), belly: c(0xC8D890), glow: false, frill: c(0xE0C23A), s: 1.25)
        case .rex:
            raptor(&m, body: c(0x5E4A36), stripe: c(0x3A2A1E), belly: c(0xB89A70), glow: false, frill: nil, s: 2.6)
        case .compy:
            raptor(&m, body: c(0x6A9A3A), stripe: c(0x3A6A22), belly: c(0xD8E0A0), glow: false, frill: nil, s: 0.5)
        case .carnotaurus:
            raptor(&m, body: c(0xA83A2A), stripe: c(0x5A1A12), belly: c(0xD8A080), glow: false, frill: nil, s: 1.9)
            m.add(.head, SIMD3(0, 0.9, -0.3) * 1.9, [b(-0.18, 0.36, -0.36, -0.1, 0.52, -0.26, c(0xF2EBD6), s: 1.9),
                                                    b(0.1, 0.36, -0.36, 0.18, 0.52, -0.26, c(0xF2EBD6), s: 1.9)])
        case .cod:
            fish(&m, body: c(0x8A9AA6), belly: c(0xDCE0E2), fin: c(0x5E6A74), tail: c(0x6A7680), stripe: nil, tall: 1, s: 1.1)
        case .salmon:
            fish(&m, body: c(0xB85A4A), belly: c(0xF0B8A0), fin: c(0x3E5A6E), tail: c(0x8A3A30), stripe: nil, tall: 1, s: 1.3)
        case .clownfish:
            fish(&m, body: c(0xF08A1A), belly: c(0xF8A840), fin: c(0x1E1E1E), tail: c(0xF08A1A), stripe: c(0xFFFFFF), tall: 1.2, s: 0.8)
        case .blueTang:
            fish(&m, body: c(0x2A6AE0), belly: c(0x5A90F0), fin: c(0x1A1A48), tail: c(0xF2D83A), stripe: nil, tall: 1.5, s: 0.9)
        case .grumblesaurus, .grinasaurus:
            // King Grumblesaurus: a huge, scarred bronze rex wearing a gold crown. His brows are drawn
            // down in a scowl until he's won over, then they relax.
            let s: Float = 3.4
            let happy = kind == .grinasaurus
            let eye = c(0xE8A020), pupil = c(0x1A1008), gold = c(0xE8B83A), goldDark = c(0xA8781E), brow = c(0x1E2410)
            raptor(&m, body: c(0x4A5A2E), stripe: c(0x2A3418), belly: c(0xC8B488), glow: false, frill: nil, s: s)
            var face: [Box] = [
                b(-0.16, 0.42, -0.5, -0.1, 0.47, -0.44, eye, s: s), b(0.1, 0.42, -0.5, 0.16, 0.47, -0.44, eye, s: s),
                b(-0.14, 0.43, -0.505, -0.12, 0.46, -0.5, pupil, s: s), b(0.12, 0.43, -0.505, 0.14, 0.46, -0.5, pupil, s: s),
                b(-0.12, 0.52, -0.3, 0.12, 0.58, -0.08, gold, s: s),
                b(-0.12, 0.58, -0.3, -0.07, 0.66, -0.25, gold, s: s), b(-0.03, 0.58, -0.22, 0.03, 0.68, -0.16, gold, s: s),
                b(0.07, 0.58, -0.3, 0.12, 0.66, -0.25, gold, s: s),
                b(-0.12, 0.52, -0.31, 0.12, 0.54, -0.29, goldDark, s: s),
            ]
            if !happy {
                face += [b(-0.18, 0.48, -0.52, -0.08, 0.51, -0.43, brow, s: s), b(0.08, 0.48, -0.52, 0.18, 0.51, -0.43, brow, s: s)]
            }
            m.add(.head, SIMD3(0, 0.9, -0.3) * s, face)
        case .allosaurus:
            raptor(&m, body: c(0x6A7A5A), stripe: c(0x3A4A2E), belly: c(0xC8C0A0), glow: false, frill: nil, s: 2.2)
        case .baryonyx:
            raptor(&m, body: c(0x4A6A7A), stripe: c(0x2A3A4A), belly: c(0xC8D0C8), glow: false, frill: nil, s: 1.8)
            m.add(.head, SIMD3(0, 0.9, -0.3) * 1.8, [b(-0.08, 0.14, -0.9, 0.08, 0.26, -0.6, c(0x4A6A7A), s: 1.8)])
        case .troodon:
            raptor(&m, body: c(0x5A4A7A), stripe: c(0x2A1A3A), belly: c(0xB8A8C8), glow: true, frill: nil, s: 0.8)
        case .spinosaurus:
            raptor(&m, body: c(0x7A5A3A), stripe: c(0x4A2E1A), belly: c(0xC8A878), glow: false, frill: nil, s: 2.8)
            var sail: [Box] = []
            for i in 0..<6 {
                let z = -0.32 + Float(i) * 0.12
                let height = 0.2 + 0.35 * sin(Float(i) / 5 * .pi)
                sail.append(b(-0.02, 0.95, z, 0.02, 0.95 + height, z + 0.12, i % 2 == 0 ? c(0xC8402A) : c(0xE07A3A), s: 2.8))
            }
            m.add(.body, .zero, sail)

        case .pookpook:
            // Round white bird with a long pointed orange beak, as drawn.
            let white = c(0xF4F4F0), shade = c(0xD8D8D4), beak = c(0xF08A2A), black = c(0x141414)
            m.add(.body, .zero, [b(-0.34, 0.45, -0.32, 0.34, 1.12, 0.34, white), b(-0.28, 1.12, -0.26, 0.28, 1.2, 0.28, white),
                                 b(-0.28, 0.4, -0.26, 0.28, 0.46, 0.28, shade), b(-0.37, 0.55, -0.24, -0.34, 1.0, 0.26, white),
                                 b(0.34, 0.55, -0.24, 0.37, 1.0, 0.26, white)])
            m.add(.head, SIMD3(0, 0.86, -0.32), [b(-0.11, -0.09, -0.3, 0.11, 0.09, 0.0, beak), b(-0.08, -0.07, -0.55, 0.08, 0.06, -0.3, beak),
                                                 b(-0.05, -0.05, -0.78, 0.05, 0.04, -0.55, beak), b(-0.025, -0.03, -0.95, 0.025, 0.02, -0.78, beak),
                                                 b(-0.2, -0.005, -0.02, 0.2, 0.012, 0.02, black),
                                                 b(-0.355, 0.12, -0.04, -0.345, 0.16, 0.0, black), b(0.345, 0.12, -0.04, 0.355, 0.16, 0.0, black)])
            m.add(.wing(-1), SIMD3(-0.375, 0.8, 0.02), [b(-0.015, -0.12, -0.14, 0, 0.03, 0.16, shade), b(-0.02, -0.02, -0.02, 0, 0.0, 0.12, black)])
            m.add(.wing(1), SIMD3(0.375, 0.8, 0.02), [b(0, -0.12, -0.14, 0.015, 0.03, 0.16, shade), b(0, -0.02, -0.02, 0.02, 0.0, 0.12, black)])
            for (x, phase) in [(Float(-0.11), Float(0)), (0.11, .pi)] {
                m.add(.leg(phase), SIMD3(x, 0.45, 0.02), [b(-0.022, -0.45, -0.022, 0.022, 0, 0.022, black),
                                                          b(-0.07, -0.45, -0.12, 0.07, -0.42, 0.02, black)])
            }

        case .pig:
            let pink = c(0xE8A0A0), dark = c(0xC87880), eye = c(0x141414)
            m.add(.body, .zero, [b(-0.3, 0.32, -0.45, 0.3, 0.78, 0.45, pink)])
            m.add(.head, SIMD3(0, 0.62, -0.45), [b(-0.22, -0.16, -0.34, 0.22, 0.24, 0.0, pink), b(-0.1, -0.08, -0.41, 0.1, 0.06, -0.34, dark),
                                                 b(-0.23, 0.02, -0.28, -0.21, 0.08, -0.22, eye), b(0.21, 0.02, -0.28, 0.23, 0.08, -0.22, eye),
                                                 b(-0.2, 0.24, -0.16, -0.08, 0.32, -0.06, dark), b(0.08, 0.24, -0.16, 0.2, 0.32, -0.06, dark)])
            for (x, z, phase) in [(-0.18, -0.3, Float(0)), (0.18, -0.3, .pi), (-0.18, 0.3, .pi), (0.18, 0.3, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.32, z), [b(-0.08, -0.32, -0.08, 0.08, 0, 0.08, pink)])
            }
            m.add(.tail, SIMD3(0, 0.66, 0.45), [b(-0.03, -0.03, 0, 0.03, 0.05, 0.08, dark)])

        case .cow:
            let hide = c(0xECECE6), patch = c(0x2A2826), muzzle = c(0xD8A0A0), horn = c(0xE6DCC0), eye = c(0x141414)
            m.add(.body, .zero, [b(-0.38, 0.62, -0.6, 0.38, 1.22, 0.6, hide), b(-0.385, 0.85, -0.2, 0.385, 1.12, 0.22, patch),
                                 b(-0.2, 1.21, 0.15, 0.25, 1.225, 0.5, patch), b(-0.385, 0.7, 0.3, 0.1, 0.95, 0.605, patch)])
            m.add(.head, SIMD3(0, 1.08, -0.6), [b(-0.24, -0.26, -0.36, 0.24, 0.2, 0.0, hide), b(-0.19, -0.26, -0.43, 0.19, -0.08, -0.34, muzzle),
                                                b(-0.34, 0.1, -0.14, -0.24, 0.18, -0.06, horn), b(0.24, 0.1, -0.14, 0.34, 0.18, -0.06, horn),
                                                b(-0.245, 0.0, -0.3, -0.235, 0.06, -0.24, eye), b(0.235, 0.0, -0.3, 0.245, 0.06, -0.24, eye),
                                                b(-0.1, 0.05, -0.365, 0.1, 0.18, -0.355, patch)])
            for (x, z, phase) in [(-0.24, -0.42, Float(0)), (0.24, -0.42, .pi), (-0.24, 0.42, .pi), (0.24, 0.42, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.62, z), [b(-0.1, -0.62, -0.1, 0.1, 0, 0.1, hide), b(-0.105, -0.62, -0.105, 0.105, -0.52, 0.105, patch)])
            }
            m.add(.tail, SIMD3(0, 1.15, 0.6), [b(-0.03, -0.55, 0, 0.03, 0, 0.05, hide), b(-0.05, -0.65, -0.02, 0.05, -0.5, 0.07, patch)])

        case .sheep:
            let wool = c(0xF0EEE8), face = c(0x4A4440), eye = c(0x141414)
            m.add(.body, .zero, [b(-0.36, 0.48, -0.5, 0.36, 1.08, 0.5, wool), b(-0.3, 1.08, -0.4, 0.3, 1.16, 0.42, wool)])
            m.add(.head, SIMD3(0, 0.92, -0.5), [b(-0.16, -0.2, -0.32, 0.16, 0.14, 0.0, face), b(-0.19, 0.06, -0.24, 0.19, 0.22, 0.02, wool),
                                                b(-0.165, -0.02, -0.26, -0.155, 0.04, -0.2, eye), b(0.155, -0.02, -0.26, 0.165, 0.04, -0.2, eye)])
            for (x, z, phase) in [(-0.2, -0.32, Float(0)), (0.2, -0.32, .pi), (-0.2, 0.32, .pi), (0.2, 0.32, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.48, z), [b(-0.07, -0.48, -0.07, 0.07, 0, 0.07, face)])
            }

        case .chicken:
            let feathers = c(0xF4F2EC), beakCol = c(0xF0C030), comb = c(0xD02A2A), eye = c(0x141414)
            m.add(.body, .zero, [b(-0.15, 0.3, -0.2, 0.15, 0.62, 0.22, feathers), b(-0.17, 0.4, -0.12, 0.17, 0.58, 0.16, feathers)])
            m.add(.head, SIMD3(0, 0.6, -0.18), [b(-0.1, 0, -0.12, 0.1, 0.26, 0.04, feathers), b(-0.04, 0.08, -0.2, 0.04, 0.14, -0.12, beakCol),
                                                b(-0.03, 0.26, -0.1, 0.03, 0.34, 0.02, comb), b(-0.03, 0.0, -0.15, 0.03, 0.08, -0.11, comb),
                                                b(-0.105, 0.15, -0.08, -0.095, 0.2, -0.04, eye), b(0.095, 0.15, -0.08, 0.105, 0.2, -0.04, eye)])
            for (x, phase) in [(Float(-0.07), Float(0)), (0.07, .pi)] {
                m.add(.leg(phase), SIMD3(x, 0.3, 0), [b(-0.02, -0.3, -0.02, 0.02, 0, 0.02, beakCol), b(-0.05, -0.3, -0.08, 0.05, -0.28, 0.02, beakCol)])
            }

        case .boneWalker:
            raptor(&m, body: c(0xD9CEB2), stripe: c(0x3A3228), belly: c(0x8A7F68), glow: false, frill: nil, s: 1.15)

        case .ptero:
            let body = c(0x7A5A8A), wing = c(0xC89AAA), crest = c(0xE0703A), beak = c(0xE8C87A), eye = c(0x111111)
            m.add(.body, .zero, [b(-0.14, 0.2, -0.3, 0.14, 0.44, 0.3, body)])
            m.add(.head, SIMD3(0, 0.4, -0.3), [b(-0.1, -0.06, -0.22, 0.1, 0.14, 0.02, body), b(-0.04, -0.02, -0.62, 0.04, 0.06, -0.2, beak),
                                              b(-0.03, 0.08, 0.0, 0.03, 0.2, 0.34, crest), b(-0.11, 0.06, -0.14, -0.09, 0.1, -0.1, eye),
                                              b(0.09, 0.06, -0.14, 0.11, 0.1, -0.1, eye)])
            m.add(.wing(-1), SIMD3(-0.14, 0.38, -0.05), [b(-1.3, -0.02, -0.25, 0, 0.03, 0.22, wing), b(-1.3, -0.03, -0.26, -1.1, 0.04, 0.3, body)])
            m.add(.wing(1), SIMD3(0.14, 0.38, -0.05), [b(0, -0.02, -0.25, 1.3, 0.03, 0.22, wing), b(1.1, -0.03, -0.26, 1.3, 0.04, 0.3, body)])
            m.add(.tail, SIMD3(0, 0.3, 0.3), [b(-0.04, -0.03, 0, 0.04, 0.03, 0.3, body)])

        case .parasaur:
            let body = c(0x5E8A7A), belly = c(0xD8C89A), crest = c(0xD8603A), dark = c(0x3E5E52), eye = c(0x111111)
            m.add(.body, .zero, [b(-0.4, 0.95, -0.7, 0.4, 1.65, 0.7, body), b(-0.36, 0.9, -0.6, 0.36, 0.98, 0.6, belly),
                                 b(-0.36, 1.05, -0.85, -0.26, 1.25, -0.65, dark), b(0.26, 1.05, -0.85, 0.36, 1.25, -0.65, dark)])
            m.add(.head, SIMD3(0, 1.5, -0.7), [b(-0.15, 0, -0.3, 0.15, 0.55, 0.05, body), b(-0.16, 0.35, -0.72, 0.16, 0.62, -0.2, body),
                                               b(-0.14, 0.38, -0.86, 0.14, 0.5, -0.7, belly), b(-0.06, 0.58, -0.35, 0.06, 0.72, 0.55, crest),
                                               b(-0.17, 0.5, -0.5, -0.15, 0.56, -0.44, eye), b(0.15, 0.5, -0.5, 0.17, 0.56, -0.44, eye)])
            m.add(.leg(0), SIMD3(-0.26, 1.0, 0.25), [b(-0.14, -1.0, -0.16, 0.14, 0, 0.18, dark), b(-0.15, -1.0, -0.3, 0.15, -0.9, 0.18, dark)])
            m.add(.leg(.pi), SIMD3(0.26, 1.0, 0.25), [b(-0.14, -1.0, -0.16, 0.14, 0, 0.18, dark), b(-0.15, -1.0, -0.3, 0.15, -0.9, 0.18, dark)])
            m.add(.tail, SIMD3(0, 1.35, 0.7), [b(-0.2, -0.2, 0, 0.2, 0.18, 1.3, body)])

        case .sailback:
            let body = c(0x8A5A3A), belly = c(0xC8A070), sail = c(0xD86A3A), sail2 = c(0xF2B24A), dark = c(0x5A3A22), eye = c(0x111111)
            var boxes = [b(-0.32, 0.25, -0.7, 0.32, 0.62, 0.7, body), b(-0.3, 0.22, -0.6, 0.3, 0.28, 0.6, belly)]
            for i in 0..<7 {
                let z = -0.54 + Float(i) * 0.18
                let height = 0.3 + 0.6 * sin(Float(i) / 6 * .pi)
                boxes.append(b(-0.03, 0.62, z - 0.09, 0.03, 0.62 + height, z + 0.09, i % 2 == 0 ? sail : sail2))
            }
            m.add(.body, .zero, boxes)
            m.add(.head, SIMD3(0, 0.48, -0.7), [b(-0.17, -0.14, -0.5, 0.17, 0.14, 0.02, body), b(-0.16, -0.18, -0.46, 0.16, -0.12, -0.1, belly),
                                                b(-0.18, 0.04, -0.34, -0.16, 0.09, -0.28, eye), b(0.16, 0.04, -0.34, 0.18, 0.09, -0.28, eye)])
            for (x, z, phase) in [(-0.36, -0.45, Float(0)), (0.36, -0.45, .pi), (-0.36, 0.45, .pi), (0.36, 0.45, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.3, z), [b(-0.08, -0.3, -0.08, 0.08, 0, 0.08, dark)])
            }
            m.add(.tail, SIMD3(0, 0.45, 0.7), [b(-0.12, -0.1, 0, 0.12, 0.08, 1.0, body)])

        case .scorpion:
            let shell = c(0xC89A4A), dark = c(0x7A5A2A), sting = c(0xFF5A3A)
            m.add(.body, .zero, [b(-0.3, 0.15, -0.35, 0.3, 0.4, 0.35, shell), b(-0.26, 0.4, -0.3, 0.26, 0.45, 0.3, dark)])
            m.add(.head, SIMD3(0, 0.28, -0.35), [b(-0.2, -0.1, -0.2, 0.2, 0.1, 0, shell),
                                                 b(-0.42, -0.06, -0.5, -0.2, 0.1, -0.2, shell), b(-0.46, -0.06, -0.68, -0.26, 0.08, -0.48, dark),
                                                 b(0.2, -0.06, -0.5, 0.42, 0.1, -0.2, shell), b(0.26, -0.06, -0.68, 0.46, 0.08, -0.48, dark),
                                                 b(-0.1, 0.1, -0.21, -0.04, 0.14, -0.19, c(0xFF3A2A), glow: true),
                                                 b(0.04, 0.1, -0.21, 0.1, 0.14, -0.19, c(0xFF3A2A), glow: true)])
            for (i, z) in [Float(-0.22), 0, 0.22].enumerated() {
                m.add(.leg(Float(i) * 2), SIMD3(-0.36, 0.25, z), [b(-0.04, -0.25, -0.04, 0.04, 0, 0.04, dark)])
                m.add(.leg(Float(i) * 2 + .pi), SIMD3(0.36, 0.25, z), [b(-0.04, -0.25, -0.04, 0.04, 0, 0.04, dark)])
            }
            m.add(.tail, SIMD3(0, 0.35, 0.35), [b(-0.08, 0, 0, 0.08, 0.14, 0.3, shell), b(-0.07, 0.12, 0.25, 0.07, 0.45, 0.4, shell),
                                                b(-0.07, 0.42, 0.05, 0.07, 0.56, 0.38, shell), b(-0.05, 0.36, -0.08, 0.05, 0.5, 0.06, sting, glow: true)])

        case .stego:
            let body = c(0x8A7A4A), belly = c(0xC8B888), plate = c(0xC8602A), plate2 = c(0xE0A03A), dark = c(0x5E5230)
            var boxes = [b(-0.55, 0.72, -0.9, 0.55, 1.5, 1.0, body), b(-0.5, 0.66, -0.8, 0.5, 0.74, 0.9, belly)]
            for i in 0..<5 {
                let z = -0.7 + Float(i) * 0.38
                let height: Float = i == 2 ? 0.6 : (i == 1 || i == 3 ? 0.48 : 0.32)
                boxes.append(b(-0.05, 1.5, z - 0.15, 0.05, 1.5 + height, z + 0.15, i % 2 == 0 ? plate : plate2))
            }
            m.add(.body, .zero, boxes)
            m.add(.head, SIMD3(0, 1.0, -0.9), [b(-0.15, -0.22, -0.6, 0.15, 0.1, 0.02, body), b(-0.16, -0.06, -0.44, -0.14, 0.02, -0.36, c(0x111111)),
                                               b(0.14, -0.06, -0.44, 0.16, 0.02, -0.36, c(0x111111))])
            for (x, z, phase) in [(-0.36, -0.6, Float(0)), (0.36, -0.6, .pi), (-0.36, 0.7, .pi), (0.36, 0.7, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.78, z), [b(-0.15, -0.78, -0.15, 0.15, 0, 0.15, dark)])
            }
            m.add(.tail, SIMD3(0, 1.2, 1.0), [b(-0.18, -0.16, 0, 0.18, 0.12, 1.2, body), b(-0.4, -0.02, 0.9, -0.18, 0.05, 0.97, c(0xF2EBD6)),
                                              b(0.18, -0.02, 0.9, 0.4, 0.05, 0.97, c(0xF2EBD6)), b(-0.36, -0.02, 1.08, -0.18, 0.05, 1.15, c(0xF2EBD6)),
                                              b(0.18, -0.02, 1.08, 0.36, 0.05, 1.15, c(0xF2EBD6))])

        case .ankylo:
            let body = c(0x6A6A58), armor = c(0x8A8068), spike = c(0xE6DCC0), dark = c(0x4A4A3C)
            var boxes = [b(-0.7, 0.45, -0.8, 0.7, 1.1, 0.9, armor), b(-0.65, 0.4, -0.75, 0.65, 0.5, 0.85, body)]
            for i in 0..<4 {
                let z = -0.6 + Float(i) * 0.45
                boxes += [b(-0.84, 0.72, z - 0.07, -0.7, 0.84, z + 0.07, spike), b(0.7, 0.72, z - 0.07, 0.84, 0.84, z + 0.07, spike),
                          b(-0.32, 1.1, z - 0.1, -0.16, 1.22, z + 0.1, spike), b(0.16, 1.1, z - 0.1, 0.32, 1.22, z + 0.1, spike)]
            }
            m.add(.body, .zero, boxes)
            m.add(.head, SIMD3(0, 0.75, -0.8), [b(-0.3, -0.22, -0.48, 0.3, 0.18, 0.02, body), b(-0.34, 0.08, -0.2, -0.22, 0.24, -0.08, spike),
                                                b(0.22, 0.08, -0.2, 0.34, 0.24, -0.08, spike), b(-0.31, -0.02, -0.38, -0.29, 0.05, -0.3, c(0x111111)),
                                                b(0.29, -0.02, -0.38, 0.31, 0.05, -0.3, c(0x111111))])
            for (x, z, phase) in [(-0.5, -0.5, Float(0)), (0.5, -0.5, .pi), (-0.5, 0.6, .pi), (0.5, 0.6, 0)] as [(Float, Float, Float)] {
                m.add(.leg(phase), SIMD3(x, 0.46, z), [b(-0.14, -0.46, -0.14, 0.14, 0, 0.14, dark)])
            }
            m.add(.tail, SIMD3(0, 0.8, 0.9), [b(-0.12, -0.1, 0, 0.12, 0.1, 1.2, body), b(-0.3, -0.18, 1.1, 0.3, 0.18, 1.45, spike)])

        case .crawler:
            for i in 0..<7 {
                let z = Float(i) * 0.34 - 1.0
                var boxes = [b(-0.42, 0.08, -0.17, 0.42, 0.42, 0.17, i % 2 == 0 ? c(0x3A2A22) : c(0x4A3628)),
                             b(-0.64, 0, -0.04, -0.42, 0.12, 0.04, c(0xD8782A)), b(0.42, 0, -0.04, 0.64, 0.12, 0.04, c(0xD8782A))]
                if i == 0 {
                    boxes += [b(-0.2, 0.3, -0.45, -0.16, 0.34, -0.17, c(0xD8782A)), b(0.16, 0.3, -0.45, 0.2, 0.34, -0.17, c(0xD8782A)),
                              b(-0.25, 0.25, -0.18, -0.15, 0.33, -0.16, c(0xFF3A2A), glow: true), b(0.15, 0.25, -0.18, 0.25, 0.33, -0.16, c(0xFF3A2A), glow: true)]
                }
                m.add(.segment(i), SIMD3(0, 0, z), boxes)
            }
        default:
            break   // drawn from CreatureShapes above
        }
        return m.parts
    }

    private static func raptor(_ m: inout Builder, body: SIMD4<Float>, stripe: SIMD4<Float>, belly: SIMD4<Float>,
                               glow: Bool, frill: SIMD4<Float>?, s: Float) {
        let eye = c(0xFFE24A)
        m.add(.body, .zero, [b(-0.22, 0.55, -0.35, 0.22, 0.95, 0.38, body, s: s), b(-0.2, 0.52, -0.3, 0.2, 0.58, 0.3, belly, s: s),
                             b(-0.23, 0.8, -0.2, 0.23, 0.85, -0.12, stripe, glow: glow, s: s), b(-0.23, 0.8, 0.05, 0.23, 0.85, 0.13, stripe, glow: glow, s: s),
                             b(-0.2, 0.6, -0.44, -0.14, 0.75, -0.32, body, s: s), b(0.14, 0.6, -0.44, 0.2, 0.75, -0.32, body, s: s)])
        var head: [Box] = [b(-0.12, -0.05, -0.28, 0.12, 0.25, 0.05, body, s: s), b(-0.16, 0.12, -0.64, 0.16, 0.38, -0.22, body, s: s),
                           b(-0.13, 0.02, -0.6, 0.13, 0.12, -0.25, belly, s: s),
                           b(-0.17, 0.28, -0.5, -0.15, 0.32, -0.44, eye, glow: true, s: s), b(0.15, 0.28, -0.5, 0.17, 0.32, -0.44, eye, glow: true, s: s)]
        if let frill {
            head.append(b(-0.38, -0.05, -0.03, 0.38, 0.38, 0.02, frill, s: s))
            head.append(b(-0.05, 0.38, -0.55, -0.02, 0.52, -0.25, c(0xD8402A), s: s))
            head.append(b(0.02, 0.38, -0.55, 0.05, 0.52, -0.25, c(0xD8402A), s: s))
        }
        m.add(.head, SIMD3(0, 0.9, -0.3) * s, head)
        for (x, phase) in [(Float(-0.14), Float(0)), (0.14, .pi)] {
            m.add(.leg(phase), SIMD3(x, 0.62, 0.05) * s, [b(-0.07, -0.62, -0.08, 0.07, 0, 0.1, body, s: s),
                                                          b(-0.07, -0.64, -0.24, 0.07, -0.56, 0.04, belly, s: s)])
        }
        m.add(.tail, SIMD3(0, 0.85, 0.36) * s, [b(-0.1, -0.1, 0, 0.1, 0.08, 0.95, body, s: s),
                                               b(-0.105, 0, 0.3, 0.105, 0.09, 0.4, stripe, glow: glow, s: s),
                                               b(-0.105, 0, 0.6, 0.105, 0.09, 0.7, stripe, glow: glow, s: s)])
    }

    // MARK: - Drawing

    private static var cache: [String: [CreaturePart]] = [:]

    /// The model for a creature; villagers dress by profession (`variant`).
    static func parts(_ kind: CreatureKind, variant: Int = 0) -> [CreaturePart] {
        let looks = MobKind(rawValue: kind.rawValue).map { CreatureShapes.variantCount($0) } ?? 1
        let look = max(0, variant) % max(1, looks)
        let key = "\(kind.rawValue)#\(look)"
        if let parts = cache[key] { return parts }
        let parts = build(kind, variant: look)
        cache[key] = parts
        return parts
    }

    /// Appends a transformed box as shaded triangles: x, y, z, r, g, b, glow per vertex.
    static func appendBox(_ v: inout [Float], _ m: Mat4, _ lo: SIMD3<Float>, _ hi: SIMD3<Float>, _ color: SIMD4<Float>, glow: Bool, tint: SIMD4<Float>) {
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> {
            let q = m * SIMD4<Float>(x, y, z, 1)
            return SIMD3(q.x, q.y, q.z)
        }
        let c000 = p(lo.x, lo.y, lo.z), c100 = p(hi.x, lo.y, lo.z), c110 = p(hi.x, hi.y, lo.z), c010 = p(lo.x, hi.y, lo.z)
        let c001 = p(lo.x, lo.y, hi.z), c101 = p(hi.x, lo.y, hi.z), c111 = p(hi.x, hi.y, hi.z), c011 = p(lo.x, hi.y, hi.z)
        var base = SIMD3<Float>(color.x, color.y, color.z)
        if tint.w > 0 { base += (SIMD3(tint.x, tint.y, tint.z) - base) * tint.w }
        let g: Float = glow ? 1 : 0
        func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, _ shade: Float) {
            let col = base * shade
            for q in [a, b, c, a, c, d] { v += [q.x, q.y, q.z, col.x, col.y, col.z, g] }
        }
        face(c010, c110, c111, c011, 1.0)
        face(c000, c100, c101, c001, 0.5)
        face(c000, c100, c110, c010, 0.85)
        face(c001, c101, c111, c011, 0.85)
        face(c000, c001, c011, c010, 0.7)
        face(c100, c101, c111, c110, 0.7)
    }

    /// A creature at camera-relative position `rel`, animated like the Mac renderer.
    static func appendCreature(_ v: inout [Float], kind name: String, at rel: SIMD3<Float>, yaw: Float, walk: Float, amount: Float,
                               lunge: Float, hurt: Float, dying: Float, variant: Int, seed: Double, time: Double, scale: Float = 1) {
        guard let kind = CreatureKind(rawValue: name) else { return }
        let tint: SIMD4<Float> = hurt > 0 ? SIMD4(0.9, 0.1, 0.1, min(1, hurt / 0.35) * 0.6)
            : (dying > 0 ? SIMD4(0.9, 0.1, 0.1, 0.45) : (kind == .sheep && variant == 1 ? SIMD4(0.08, 0.08, 0.1, 0.8) : SIMD4(0, 0, 0, 0)))
        let tip: Float = dying > 0 ? min(1, dying / 0.4) * (.pi / 2) : 0
        var base = MathUtil.translation(rel) * MathUtil.rotationY(yaw) * MathUtil.rotationZ(tip)
        if scale != 1 { base = base * MathUtil.scale(SIMD3(repeating: scale)) }
        for part in parts(kind, variant: variant) {
            let local: Mat4
            switch part.role {
            case .body:
                local = MathUtil.translation(part.pivot + SIMD3(0, abs(sin(walk)) * 0.03 * amount, -lunge * 0.12))
            case .head:
                local = MathUtil.translation(part.pivot + SIMD3(0, 0, -lunge * 0.2))
                    * MathUtil.rotationX(Float(sin(time * 1.3 + seed)) * 0.06 + lunge * 0.35 - amount * 0.05)
            case .leg(let phase):
                local = MathUtil.translation(part.pivot) * MathUtil.rotationX(sin(walk + phase) * 0.7 * amount)
            case .tail:
                local = MathUtil.translation(part.pivot) * MathUtil.rotationY(Float(sin(time * 2.2 + seed)) * 0.25 + sin(walk) * 0.15 * amount)
            case .segment(let i):
                let sway = Float(sin(time * 7 + Double(i) * 0.9 + seed)) * 0.05 * (0.3 + amount)
                local = MathUtil.translation(part.pivot + SIMD3(sway, 0, 0))
            case .wing(let side):
                let flap = Float(sin(time * 7 + seed)) * 0.55 + 0.1
                local = MathUtil.translation(part.pivot) * MathUtil.rotationZ(side * flap)
            }
            let model = base * local
            for box in part.boxes { appendBox(&v, model, box.0, box.1, box.2, glow: box.3, tint: tint) }
        }
    }

    /// A player with the shared explorer model (and their cosmetics), animated like on the Mac.
    static func appendPlayer(_ v: inout [Float], name: String, look: String?, at rel: SIMD3<Float>, yaw: Float, pitch: Float, walk: Float,
                             moving: Float, sneaking: Bool, swing: Float, hurt: Float) {
        let tint: SIMD4<Float> = hurt > 0 ? SIMD4(0.9, 0.1, 0.1, min(1, hurt / 0.35) * 0.6) : SIMD4(0, 0, 0, 0)
        let base = MathUtil.translation(rel - SIMD3(0, sneaking ? 0.25 : 0, 0)) * MathUtil.rotationY(yaw)
        for part in PlayerAvatar.parts(PlayerLook.resolve(look, name: name)) {
            let model = base * MathUtil.translation(part.pivot)
                * PlayerAvatar.pose(kind: part.kind, pitch: pitch, walk: walk, moving: moving, sneaking: sneaking, swing: swing)
            for box in part.boxes { appendBox(&v, model, box.0, box.1, box.2, glow: false, tint: tint) }
        }
    }
}
