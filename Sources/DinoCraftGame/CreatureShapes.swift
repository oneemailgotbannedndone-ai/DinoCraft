import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif

/// Box models defined once for both renderers: the villagers (one outfit per profession) and the newer
/// dinosaurs. Sizes are in blocks, the creature faces -Z, and colours are sRGB hex; each renderer turns
/// these into its own meshes and animates the parts by role (legs walk, heads bob, tails sway, wings flap).
enum ShapeRole: Equatable {
    case body, head, tail
    case leg(Float)
    case segment(Int)
    case wing(Float)
}

struct ShapeBox {
    var min: SIMD3<Float>
    var max: SIMD3<Float>
    var color: UInt32
    var glow = false
}

struct ShapePart {
    var role: ShapeRole
    var pivot: SIMD3<Float>
    var boxes: [ShapeBox]
}

enum CreatureShapes {
    /// The shared model for `kind` (villagers by profession `variant`), or nil if the renderer draws it itself.
    static func parts(_ kind: MobKind, variant: Int) -> [ShapePart]? {
        switch kind {
        case .villager: return villager(profession: variant)
        case .pachy: return pachy()
        case .iguanodon: return iguanodon()
        case .therizino: return therizino()
        case .gallimimus: return gallimimus()
        case .oviraptor: return oviraptor()
        case .microraptor: return microraptor()
        case .boat: return boat()
        case .egg: return egg(Breeding.kind(ofEgg: variant))
        case .armorStand: return armorStand(Decorations.armor(variant))
        case .mosasaurus: return mosasaurus()
        case .crab: return crab()
        default: return nil
        }
    }

    /// How many looks a kind has (villagers: one per profession).
    static func variantCount(_ kind: MobKind) -> Int {
        switch kind {
        case .villager: return VillagerProfession.all.count
        case .egg: return Breeding.kinds.count
        case .armorStand: return 256
        default: return 1
        }
    }

    // MARK: Building blocks

    private struct Model {
        var parts: [ShapePart] = []
        mutating func add(_ role: ShapeRole, _ pivot: SIMD3<Float>, _ boxes: [ShapeBox]) {
            parts.append(ShapePart(role: role, pivot: pivot, boxes: boxes))
        }
    }

    private static func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ color: UInt32, glow: Bool = false) -> ShapeBox {
        ShapeBox(min: SIMD3(x0, y0, z0), max: SIMD3(x1, y1, z1), color: color, glow: glow)
    }

    /// Two eyes on the sides of a head, looking forward (-Z): white with a dark pupil at the front.
    private static func eyes(x: Float, y: Float, z: Float, size s: Float = 0.05) -> [ShapeBox] {
        [b(-x - 0.01, y, z, -x + 0.005, y + s, z + s, 0xF4F0E4), b(-x - 0.012, y, z, -x + 0.004, y + s, z + s * 0.45, 0x141414),
         b(x - 0.005, y, z, x + 0.01, y + s, z + s, 0xF4F0E4), b(x - 0.004, y, z, x + 0.012, y + s, z + s * 0.45, 0x141414)]
    }

    // MARK: Villagers

    private struct Outfit {
        var robe: UInt32, trim: UInt32, sleeve: UInt32, trousers: UInt32, apron: UInt32?
    }

    /// A villager: robe with a belt and folded arms, a friendly face with a big nose and bushy brows,
    /// and each profession's own outfit and hat.
    static func villager(profession: Int) -> [ShapePart] {
        var m = Model()
        let skin: UInt32 = 0xD8A47A, skinDark: UInt32 = 0xB8845E, hair: UInt32 = 0x4A3222
        let outfits = [
            Outfit(robe: 0x5E8A3A, trim: 0x3E6224, sleeve: 0x6E9A48, trousers: 0x4A3A28, apron: 0x9A7A52),   // Farmer
            Outfit(robe: 0x4A4C56, trim: 0x2E3038, sleeve: 0x5A5C66, trousers: 0x2E2E34, apron: 0x6A4028),   // Toolsmith
            Outfit(robe: 0x8A7A68, trim: 0x5E5244, sleeve: 0x9A8A76, trousers: 0x4E463C, apron: 0xE8E2D6),   // Mason
            Outfit(robe: 0xB09A6A, trim: 0x7A6A44, sleeve: 0xC0AA7A, trousers: 0x5E4E32, apron: nil),        // Fossil Hunter
        ]
        let o = outfits[max(0, profession) % outfits.count]

        var body = [
            b(-0.25, 0.7, -0.16, 0.25, 1.42, 0.16, o.robe),                     // robe
            b(-0.27, 0.7, -0.18, 0.27, 0.8, 0.18, o.trim),                      // hem
            b(-0.26, 1.0, -0.17, 0.26, 1.05, 0.17, 0x3A2A1A),                   // belt
            b(-0.04, 1.005, -0.18, 0.04, 1.045, -0.17, 0xD8B040),               // buckle
            // Folded arms: sleeves from the shoulders meeting in front, hands peeking out
            b(-0.34, 1.12, -0.12, -0.24, 1.4, 0.1, o.sleeve), b(0.24, 1.12, -0.12, 0.34, 1.4, 0.1, o.sleeve),
            b(-0.32, 1.1, -0.32, 0.32, 1.24, -0.14, o.sleeve),
            b(-0.08, 1.11, -0.33, 0.08, 1.23, -0.3, skin),
        ]
        if let apron = o.apron { body.append(b(-0.2, 0.74, -0.175, 0.2, 1.1, -0.16, apron)) }
        if profession % 4 == 3 {
            // Fossil Hunter: satchel strap and bag, and a red neckerchief
            body += [b(-0.22, 1.02, -0.17, -0.16, 1.4, 0.17, 0x6A4A2A), b(0.18, 0.86, -0.1, 0.34, 1.06, 0.12, 0x7A5A34),
                     b(-0.16, 1.36, -0.17, 0.16, 1.42, -0.15, 0xB83A2A)]
        }
        m.add(.body, .zero, body)

        var head = [
            b(-0.2, 0, -0.2, 0.2, 0.44, 0.2, skin),                              // head
            b(-0.05, 0.08, -0.3, 0.05, 0.26, -0.2, skinDark),                   // big nose
            b(-0.21, 0.36, -0.21, 0.21, 0.46, 0.21, hair),                      // hair
            b(-0.16, 0.29, -0.215, -0.05, 0.32, -0.2, hair), b(0.05, 0.29, -0.215, 0.16, 0.32, -0.2, hair),   // brows
            b(-0.08, 0.04, -0.205, 0.08, 0.06, -0.2, 0x7A4A3A),                 // mouth
        ]
        head += [b(-0.15, 0.22, -0.205, -0.07, 0.28, -0.2, 0xF4F0E4), b(-0.12, 0.22, -0.21, -0.07, 0.27, -0.205, 0x2A4A6A),
                 b(0.07, 0.22, -0.205, 0.15, 0.28, -0.2, 0xF4F0E4), b(0.07, 0.22, -0.21, 0.12, 0.27, -0.205, 0x2A4A6A)]
        switch profession % 4 {
        case 0:   // Farmer: a wide straw hat
            head += [b(-0.36, 0.44, -0.36, 0.36, 0.48, 0.36, 0xE0C060), b(-0.2, 0.48, -0.2, 0.2, 0.62, 0.2, 0xE8CC70),
                     b(-0.205, 0.48, -0.205, 0.205, 0.52, 0.205, 0xA83A2A)]
        case 1:   // Toolsmith: goggles pushed up on the forehead
            head += [b(-0.21, 0.36, -0.21, 0.21, 0.4, 0.21, 0x2A2A2A), b(-0.15, 0.34, -0.23, -0.03, 0.42, -0.2, 0x8AC8E0, glow: false),
                     b(0.03, 0.34, -0.23, 0.15, 0.42, -0.2, 0x8AC8E0)]
        case 2:   // Mason: a flat cap
            head += [b(-0.22, 0.44, -0.22, 0.22, 0.52, 0.22, 0x5A5A62), b(-0.22, 0.44, -0.34, 0.22, 0.47, -0.2, 0x4A4A52)]
        default:  // Fossil Hunter: an explorer's pith helmet
            head += [b(-0.3, 0.42, -0.3, 0.3, 0.46, 0.3, 0xCCB88A), b(-0.22, 0.46, -0.22, 0.22, 0.62, 0.22, 0xD8C89A),
                     b(-0.223, 0.46, -0.223, 0.223, 0.5, 0.223, 0x7A5A34)]
        }
        m.add(.head, SIMD3(0, 1.42, 0), head)
        for (x, phase) in [(Float(-0.12), Float(0)), (0.12, .pi)] {
            m.add(.leg(phase), SIMD3(x, 0.72, 0), [b(-0.09, -0.72, -0.09, 0.09, 0, 0.09, o.trousers),
                                                   b(-0.1, -0.72, -0.13, 0.1, -0.62, 0.1, 0x3A2A1C)])
        }
        return m.parts
    }

    // MARK: Dinosaurs

    /// Pachycephalosaurus: a stocky two-legged dino with a thick, knobbly bone dome for headbutting.
    static func pachy() -> [ShapePart] {
        var m = Model()
        let body: UInt32 = 0x6E7A4A, belly: UInt32 = 0xC8C090, dome: UInt32 = 0xE6D8B0, stripe: UInt32 = 0x4A5630, knob: UInt32 = 0x8A7A5A
        m.add(.body, .zero, [b(-0.3, 0.8, -0.5, 0.3, 1.3, 0.45, body), b(-0.27, 0.76, -0.42, 0.27, 0.84, 0.4, belly),
                             b(-0.31, 1.1, -0.2, 0.31, 1.18, -0.1, stripe), b(-0.31, 1.1, 0.1, 0.31, 1.18, 0.2, stripe),
                             b(-0.3, 0.95, -0.56, -0.24, 1.05, -0.4, body), b(0.24, 0.95, -0.56, 0.3, 1.05, -0.4, body)])
        var head = [b(-0.2, -0.1, -0.42, 0.2, 0.24, 0.02, body), b(-0.13, -0.1, -0.58, 0.13, 0.08, -0.4, body),
                    b(-0.23, 0.18, -0.4, 0.23, 0.44, 0.0, dome), b(-0.18, 0.44, -0.34, 0.18, 0.5, -0.06, dome)]
        for (x, z) in [(-0.24, -0.1), (0.2, -0.1), (-0.24, -0.34), (0.2, -0.34), (-0.1, 0.0), (0.06, 0.0)] as [(Float, Float)] {
            head.append(b(x, 0.12, z, x + 0.04, 0.2, z + 0.04, knob))
        }
        head += eyes(x: 0.2, y: 0.05, z: -0.34)
        m.add(.head, SIMD3(0, 1.22, -0.5), head)
        for (x, phase) in [(Float(-0.18), Float(0)), (0.18, .pi)] {
            m.add(.leg(phase), SIMD3(x, 0.82, 0.05), [b(-0.11, -0.82, -0.12, 0.11, 0, 0.14, body), b(-0.12, -0.82, -0.3, 0.12, -0.74, 0.1, stripe)])
        }
        m.add(.tail, SIMD3(0, 1.08, 0.45), [b(-0.15, -0.13, 0, 0.15, 0.1, 0.6, body), b(-0.09, -0.08, 0.6, 0.09, 0.05, 1.1, body)])
        return m.parts
    }

    /// Iguanodon: a big, gentle plant-eater that walks on all fours, with a beak and spiked thumbs.
    static func iguanodon() -> [ShapePart] {
        var m = Model()
        let body: UInt32 = 0x4E7A5A, belly: UInt32 = 0xB8C898, dark: UInt32 = 0x3A5A42, spike: UInt32 = 0xEDE4CC, beak: UInt32 = 0x6A5A3A
        m.add(.body, .zero, [b(-0.4, 1.0, -0.8, 0.4, 1.7, 0.7, body), b(-0.36, 0.95, -0.7, 0.36, 1.04, 0.6, belly),
                             b(-0.41, 1.4, -0.5, 0.41, 1.48, -0.38, dark), b(-0.41, 1.4, -0.1, 0.41, 1.48, 0.02, dark),
                             b(-0.41, 1.4, 0.3, 0.41, 1.48, 0.42, dark)])
        var head = [b(-0.18, -0.12, -0.48, 0.18, 0.28, 0.05, body), b(-0.13, -0.12, -0.68, 0.13, 0.12, -0.46, beak)]
        head += eyes(x: 0.18, y: 0.1, z: -0.38)
        m.add(.head, SIMD3(0, 1.65, -0.8), head)
        for (x, phase) in [(Float(-0.32), Float(0)), (0.32, .pi)] {
            m.add(.leg(phase), SIMD3(x, 1.0, -0.6), [b(-0.1, -1.0, -0.1, 0.1, 0, 0.1, body), b(-0.03, -0.42, -0.24, 0.03, -0.32, -0.08, spike)])
        }
        for (x, phase) in [(Float(-0.3), Float.pi), (0.3, 0)] {
            m.add(.leg(phase), SIMD3(x, 1.1, 0.4), [b(-0.17, -1.1, -0.18, 0.17, 0, 0.2, body), b(-0.18, -1.1, -0.3, 0.18, -1.0, 0.2, dark)])
        }
        m.add(.tail, SIMD3(0, 1.4, 0.7), [b(-0.22, -0.2, 0, 0.22, 0.18, 0.8, body), b(-0.13, -0.12, 0.8, 0.13, 0.1, 1.5, body)])
        return m.parts
    }

    /// Therizinosaurus: tall and feathery with a round belly, a tiny beaked head and enormous claws.
    static func therizino() -> [ShapePart] {
        var m = Model()
        let feather: UInt32 = 0x8A6A4A, belly: UInt32 = 0xD8C8A8, dark: UInt32 = 0x5A4430, claw: UInt32 = 0x2A2622, beak: UInt32 = 0xC8A860
        m.add(.body, .zero, [b(-0.42, 1.3, -0.45, 0.42, 2.2, 0.6, feather), b(-0.38, 1.25, -0.52, 0.38, 1.9, -0.3, belly),
                             b(-0.44, 2.0, -0.3, 0.44, 2.3, 0.5, feather), b(-0.1, 2.2, 0.2, 0.1, 2.5, 0.5, dark)])
        var head = [b(-0.1, 0, -0.1, 0.1, 0.62, 0.1, feather), b(-0.13, 0.55, -0.36, 0.13, 0.78, 0.06, feather),
                    b(-0.07, 0.56, -0.52, 0.07, 0.66, -0.34, beak)]
        head += eyes(x: 0.13, y: 0.68, z: -0.28, size: 0.04)
        m.add(.head, SIMD3(0, 2.3, -0.35), head)
        for (x, phase) in [(Float(-0.46), Float(0)), (0.46, .pi)] {
            var arm = [b(-0.08, -0.7, -0.08, 0.08, 0, 0.08, feather), b(-0.1, -0.45, -0.1, 0.1, -0.2, 0.12, dark)]
            for (i, dz) in [Float(-0.06), 0.0, 0.06].enumerated() {
                arm.append(b(-0.02 + dz, -1.2 + Float(i) * 0.04, -0.3, 0.02 + dz, -0.68, -0.06, claw))
            }
            m.add(.leg(phase), SIMD3(x, 2.05, -0.35), arm)
        }
        for (x, phase) in [(Float(-0.22), Float.pi), (0.22, 0)] {
            m.add(.leg(phase), SIMD3(x, 1.3, 0.15), [b(-0.14, -1.3, -0.14, 0.14, 0, 0.16, feather), b(-0.16, -1.3, -0.36, 0.16, -1.2, 0.14, dark)])
        }
        m.add(.tail, SIMD3(0, 1.6, 0.6), [b(-0.18, -0.15, 0, 0.18, 0.15, 0.6, feather), b(-0.24, -0.05, 0.5, 0.24, 0.2, 0.8, dark)])
        return m.parts
    }

    /// Gallimimus: an ostrich-like sprinter on long legs, striped and quick to run off.
    static func gallimimus() -> [ShapePart] {
        var m = Model()
        let body: UInt32 = 0xB08A5A, stripe: UInt32 = 0x6A4A2A, belly: UInt32 = 0xE8D8B8, beak: UInt32 = 0x4A3A2A
        m.add(.body, .zero, [b(-0.22, 1.0, -0.42, 0.22, 1.36, 0.4, body), b(-0.2, 0.96, -0.36, 0.2, 1.04, 0.34, belly),
                             b(-0.23, 1.2, -0.25, 0.23, 1.26, -0.17, stripe), b(-0.23, 1.2, 0.0, 0.23, 1.26, 0.08, stripe),
                             b(-0.23, 1.2, 0.24, 0.23, 1.26, 0.32, stripe)])
        var head = [b(-0.07, 0, -0.07, 0.07, 0.56, 0.07, body), b(-0.09, 0.5, -0.3, 0.09, 0.66, 0.05, body),
                    b(-0.045, 0.52, -0.44, 0.045, 0.6, -0.3, beak)]
        head += eyes(x: 0.09, y: 0.58, z: -0.22, size: 0.04)
        m.add(.head, SIMD3(0, 1.3, -0.4), head)
        for (x, phase) in [(Float(-0.12), Float(0)), (0.12, .pi)] {
            m.add(.leg(phase), SIMD3(x, 1.02, 0.05), [b(-0.07, -0.5, -0.08, 0.07, 0, 0.1, body), b(-0.05, -1.02, -0.05, 0.05, -0.5, 0.05, stripe),
                                                       b(-0.07, -1.02, -0.22, 0.07, -0.96, 0.06, stripe)])
        }
        m.add(.tail, SIMD3(0, 1.2, 0.4), [b(-0.09, -0.09, 0, 0.09, 0.08, 0.95, body), b(-0.095, 0, 0.5, 0.095, 0.085, 0.6, stripe)])
        return m.parts
    }

    /// Oviraptor: a small, bright feathered dino with a tall crest, a parrot beak and a fan of tail feathers.
    static func oviraptor() -> [ShapePart] {
        var m = Model()
        let body: UInt32 = 0x5A4A7A, crest: UInt32 = 0xE06A3A, beak: UInt32 = 0xE8C060, wing: UInt32 = 0x3A8A9A, belly: UInt32 = 0xD8D0E0
        m.add(.body, .zero, [b(-0.18, 0.5, -0.3, 0.18, 0.86, 0.3, body), b(-0.16, 0.47, -0.26, 0.16, 0.54, 0.24, belly)])
        var head = [b(-0.1, 0, -0.22, 0.1, 0.19, 0.02, body), b(-0.025, 0.18, -0.22, 0.025, 0.36, -0.02, crest),
                    b(-0.065, 0, -0.33, 0.065, 0.11, -0.21, beak)]
        head += eyes(x: 0.1, y: 0.1, z: -0.16, size: 0.04)
        m.add(.head, SIMD3(0, 0.84, -0.28), head)
        m.add(.wing(-1), SIMD3(-0.18, 0.78, -0.1), [b(-0.3, -0.02, -0.14, 0, 0.03, 0.18, wing)])
        m.add(.wing(1), SIMD3(0.18, 0.78, -0.1), [b(0, -0.02, -0.14, 0.3, 0.03, 0.18, wing)])
        for (x, phase) in [(Float(-0.09), Float(0)), (0.09, .pi)] {
            m.add(.leg(phase), SIMD3(x, 0.5, 0.05), [b(-0.045, -0.5, -0.045, 0.045, 0, 0.06, beak), b(-0.06, -0.5, -0.16, 0.06, -0.46, 0.04, beak)])
        }
        m.add(.tail, SIMD3(0, 0.72, 0.3), [b(-0.06, -0.06, 0, 0.06, 0.06, 0.4, body), b(-0.14, -0.02, 0.32, 0.14, 0.04, 0.55, wing),
                                           b(-0.08, -0.01, 0.5, 0.08, 0.03, 0.6, crest)])
        return m.parts
    }

    /// Microraptor: a crow-sized glider with four feathered wings in shimmering black and blue.
    static func microraptor() -> [ShapePart] {
        var m = Model()
        let body: UInt32 = 0x1E2A3A, shine: UInt32 = 0x3A6ABA, tip: UInt32 = 0x121820, beak: UInt32 = 0x2A2A2A
        m.add(.body, .zero, [b(-0.1, 0.15, -0.26, 0.1, 0.35, 0.2, body), b(-0.09, 0.34, -0.2, 0.09, 0.37, 0.12, shine)])
        var head = [b(-0.07, -0.04, -0.16, 0.07, 0.1, 0.02, body), b(-0.03, -0.02, -0.24, 0.03, 0.04, -0.15, beak)]
        head += eyes(x: 0.07, y: 0.03, z: -0.12, size: 0.035)
        m.add(.head, SIMD3(0, 0.3, -0.26), head)
        m.add(.wing(-1), SIMD3(-0.1, 0.3, -0.06), [b(-0.7, -0.02, -0.15, 0, 0.02, 0.14, shine), b(-0.7, -0.021, -0.16, -0.5, 0.021, 0.16, tip)])
        m.add(.wing(1), SIMD3(0.1, 0.3, -0.06), [b(0, -0.02, -0.15, 0.7, 0.02, 0.14, shine), b(0.5, -0.021, -0.16, 0.7, 0.021, 0.16, tip)])
        m.add(.tail, SIMD3(0, 0.25, 0.2), [b(-0.03, -0.02, 0, 0.03, 0.02, 0.4, body), b(-0.13, -0.01, 0.32, 0.13, 0.02, 0.5, shine)])
        return m.parts
    }

    // MARK: Boats

    /// A wooden rowing boat: plank hull with a pointed bow, a bench, and oars that row as it moves.
    /// A dino egg, speckled in its kind's colours; it rocks on its base (the "leg" role) before hatching.
    static func egg(_ kind: MobKind) -> [ShapePart] {
        var m = Model()
        let (shell, spot) = Breeding.eggColors(kind)
        // Stacked slabs make the rounded egg: widest a third of the way up.
        let rings: [(Float, Float, Float)] = [(0, 0.06, 0.14), (0.06, 0.16, 0.2), (0.16, 0.3, 0.23), (0.3, 0.42, 0.2), (0.42, 0.5, 0.15), (0.5, 0.56, 0.08)]
        var boxes = rings.map { b(-$0.2, $0.0, -$0.2, $0.2, $0.1, $0.2, shell) }
        let spots: [(Float, Float, Float)] = [(0.1, 0.2, 1), (-0.12, 0.34, 1), (0.04, 0.44, -1), (-0.08, 0.12, -1), (0.14, 0.32, -1)]
        for (x, y, side) in spots {
            let z = side * 0.23
            boxes.append(b(x - 0.035, y, min(z, z + side * 0.012), x + 0.035, y + 0.05, max(z, z + side * 0.012), spot))
        }
        for (x, y) in [(Float(-0.235), Float(0.22)), (0.235, 0.26)] {
            boxes.append(b(min(x, x * 1.05), y, -0.03, max(x, x * 1.05), y + 0.05, 0.04, spot))
        }
        m.add(.leg(0), .zero, boxes)
        return m.parts
    }

    /// A wooden armour stand, wearing hide, iron or diamond armour in each slot (materials 0-3: none, hide, iron, diamond).
    static func armorStand(_ armor: [Int]) -> [ShapePart] {
        var m = Model()
        let wood: UInt32 = 0xB08050, dark: UInt32 = 0x7A5230, stone: UInt32 = 0x8A8C94
        let colours: [(UInt32, UInt32)] = [(0, 0), (0x8A5A34, 0x6A4224), (0xC8CED6, 0x98A0AA), (0x4ADCD0, 0x24A8A0)]
        var body = [
            b(-0.4, 0, -0.4, 0.4, 0.08, 0.4, stone),          // base plate
            b(-0.05, 0.08, -0.05, 0.05, 1.45, 0.05, wood),     // pole
            b(-0.3, 0.72, -0.06, 0.3, 0.8, 0.06, dark),        // hips
            b(-0.38, 1.36, -0.06, 0.38, 1.44, 0.06, dark),     // shoulders
            b(-0.12, 1.46, -0.12, 0.12, 1.72, 0.12, wood),     // head
            b(-0.2, 0.08, -0.04, -0.12, 0.72, 0.04, wood),     // legs
            b(0.12, 0.08, -0.04, 0.2, 0.72, 0.04, wood),
            b(-0.38, 0.9, -0.04, -0.3, 1.36, 0.04, wood),      // arms
            b(0.3, 0.9, -0.04, 0.38, 1.36, 0.04, wood),
        ]
        func piece(_ slot: Int) -> (UInt32, UInt32)? { armor.indices.contains(slot) && armor[slot] > 0 ? colours[armor[slot]] : nil }
        if let (c, d) = piece(0) {                                            // helmet
            body.append(b(-0.16, 1.44, -0.16, 0.16, 1.78, 0.16, c))
            body.append(b(-0.16, 1.54, -0.17, 0.16, 1.58, -0.16, d))
        }
        if let (c, d) = piece(1) {                                            // chestplate
            body.append(b(-0.34, 0.86, -0.14, 0.34, 1.42, 0.14, c))
            body.append(b(-0.42, 1.2, -0.12, -0.3, 1.42, 0.12, d))
            body.append(b(0.3, 1.2, -0.12, 0.42, 1.42, 0.12, d))
        }
        if let (c, d) = piece(2) {                                            // leggings
            body.append(b(-0.3, 0.66, -0.12, 0.3, 0.86, 0.12, d))
            body.append(b(-0.26, 0.26, -0.1, -0.06, 0.7, 0.1, c))
            body.append(b(0.06, 0.26, -0.1, 0.26, 0.7, 0.1, c))
        }
        if let (c, _) = piece(3) {                                            // boots
            body.append(b(-0.26, 0.08, -0.14, -0.06, 0.28, 0.1, c))
            body.append(b(0.06, 0.08, -0.14, 0.26, 0.28, 0.1, c))
        }
        m.add(.body, .zero, body)
        return m.parts
    }

    /// A Mosasaurus: a huge sea lizard with a long toothy snout, four flippers and a shark-like tail fluke.
    static func mosasaurus() -> [ShapePart] {
        var m = Model()
        let top: UInt32 = 0x2E4A5A, stripe: UInt32 = 0x3E6272, belly: UInt32 = 0xC8CEC0, tooth: UInt32 = 0xF2EEDC, mouth: UInt32 = 0x6A2A2A
        m.add(.body, .zero, [
            b(-0.45, 0.2, -1.1, 0.45, 1.0, 1.05, top),
            b(-0.4, 0.14, -1.0, 0.4, 0.34, 0.95, belly),
            b(-0.08, 1.0, -0.8, 0.08, 1.12, 0.8, stripe),          // ridge along the back
            b(-0.46, 0.55, -1.0, -0.44, 0.7, 0.9, stripe), b(0.44, 0.55, -1.0, 0.46, 0.7, 0.9, stripe),
        ])
        var head = [
            b(-0.36, -0.2, -1.4, 0.36, 0.34, 0, top),              // skull and upper jaw
            b(-0.3, -0.42, -1.3, 0.3, -0.22, -0.05, belly),        // lower jaw
            b(-0.28, -0.22, -1.28, 0.28, -0.18, -0.1, mouth),      // inside of the mouth
        ]
        for k in 0..<6 {
            let z = -1.25 + Float(k) * 0.2
            head.append(b(-0.3, -0.26, z, -0.24, -0.16, z + 0.06, tooth))
            head.append(b(0.24, -0.26, z, 0.3, -0.16, z + 0.06, tooth))
        }
        head += eyes(x: 0.36, y: 0.1, z: -0.55, size: 0.09)
        m.add(.head, SIMD3(0, 0.6, -1.1), head)
        m.add(.segment(0), SIMD3(0, 0.6, 1.0), [b(-0.36, -0.32, 0, 0.36, 0.32, 0.95, top), b(-0.3, -0.34, 0.05, 0.3, -0.2, 0.9, belly)])
        m.add(.segment(1), SIMD3(0, 0.6, 1.9), [b(-0.26, -0.24, 0, 0.26, 0.24, 0.95, top)])
        m.add(.tail, SIMD3(0, 0.6, 2.8), [
            b(-0.14, -0.14, 0, 0.14, 0.14, 0.6, top),
            b(-0.05, -0.05, 0.35, 0.05, 0.95, 0.85, stripe),        // upper fluke
            b(-0.05, -0.55, 0.45, 0.05, -0.05, 0.8, stripe),        // lower fluke
        ])
        m.add(.wing(-1), SIMD3(-0.45, 0.35, -0.55), [b(-0.95, -0.04, -0.22, 0, 0.04, 0.26, stripe)])
        m.add(.wing(1), SIMD3(0.45, 0.35, -0.55), [b(0, -0.04, -0.22, 0.95, 0.04, 0.26, stripe)])
        m.add(.wing(-1), SIMD3(-0.45, 0.35, 0.7), [b(-0.7, -0.04, -0.18, 0, 0.04, 0.2, stripe)])
        m.add(.wing(1), SIMD3(0.45, 0.35, 0.7), [b(0, -0.04, -0.18, 0.7, 0.04, 0.2, stripe)])
        return m.parts
    }

    /// A beach crab: a wide red shell, eyes on stalks, snapping claws and three legs a side.
    static func crab() -> [ShapePart] {
        var m = Model()
        let shell: UInt32 = 0xB8342A, dark: UInt32 = 0x7E2018, light: UInt32 = 0xE0604A, belly: UInt32 = 0xE8C8A0
        m.add(.body, .zero, [
            b(-0.32, 0.14, -0.22, 0.32, 0.3, 0.2, shell),
            b(-0.26, 0.3, -0.18, 0.26, 0.34, 0.16, light),
            b(-0.3, 0.12, -0.2, 0.3, 0.14, 0.18, belly),
            b(-0.1, 0.3, -0.26, -0.07, 0.42, -0.23, dark), b(0.07, 0.3, -0.26, 0.1, 0.42, -0.23, dark),   // eye stalks
            b(-0.12, 0.42, -0.28, -0.05, 0.47, -0.21, 0x141414), b(0.05, 0.42, -0.28, 0.12, 0.47, -0.21, 0x141414),
        ])
        m.add(.wing(-1), SIMD3(-0.28, 0.22, -0.2), [b(-0.22, -0.04, -0.14, 0, 0.04, 0.02, shell), b(-0.3, -0.06, -0.26, -0.16, 0.08, -0.08, dark)])
        m.add(.wing(1), SIMD3(0.28, 0.22, -0.2), [b(0, -0.04, -0.14, 0.22, 0.04, 0.02, shell), b(0.16, -0.06, -0.26, 0.3, 0.08, -0.08, dark)])
        for (i, z) in [Float(-0.1), 0.02, 0.14].enumerated() {
            let phase = Float(i) * 2.1
            m.add(.leg(phase), SIMD3(-0.3, 0.16, z), [b(-0.2, -0.16, -0.02, 0, 0.02, 0.02, dark)])
            m.add(.leg(phase + .pi), SIMD3(0.3, 0.16, z), [b(0, -0.16, -0.02, 0.2, 0.02, 0.02, dark)])
        }
        return m.parts
    }

    static func boat() -> [ShapePart] {
        var m = Model()
        let plank: UInt32 = 0xA8783E, dark: UInt32 = 0x7E5528, rim: UInt32 = 0x5E3C1C, seat: UInt32 = 0x8E6232
        var hull = [
            b(-0.5, 0, -0.8, 0.5, 0.1, 0.9, dark),                  // bottom
            b(-0.58, 0.02, -0.72, -0.48, 0.46, 0.92, plank),        // port side
            b(0.48, 0.02, -0.72, 0.58, 0.46, 0.92, plank),          // starboard side
            b(-0.58, 0.02, 0.86, 0.58, 0.46, 0.96, plank),          // stern
            b(-0.4, 0.02, -0.9, 0.4, 0.44, -0.78, plank),           // bow, narrowing
            b(-0.22, 0.04, -1.02, 0.22, 0.42, -0.88, plank),
            b(-0.08, 0.08, -1.1, 0.08, 0.5, -1.0, rim),             // stem post
            b(-0.6, 0.44, -0.72, -0.46, 0.5, 0.96, rim),            // gunwales
            b(0.46, 0.44, -0.72, 0.6, 0.5, 0.96, rim),
            b(-0.6, 0.44, 0.88, 0.6, 0.5, 0.98, rim),
            b(-0.44, 0.4, -0.92, 0.44, 0.47, -0.78, rim),
            b(-0.48, 0.3, -0.06, 0.48, 0.36, 0.18, seat),           // bench
            b(-0.48, 0.3, 0.62, 0.48, 0.36, 0.86, seat),            // stern seat
        ]
        // Plank seams along the sides.
        for y: Float in [0.17, 0.31] {
            hull.append(b(-0.585, y, -0.72, -0.575, y + 0.02, 0.92, dark))
            hull.append(b(0.575, y, -0.72, 0.585, y + 0.02, 0.92, dark))
        }
        m.add(.body, .zero, hull)
        // Oars: shafts out over the sides from the oarlocks, blades down in the water.
        for (side, phase) in [(Float(-1), Float(0)), (Float(1), Float(0))] {
            let shaft = side < 0 ? b(-0.9, -0.03, -0.03, 0.2, 0.03, 0.03, seat) : b(-0.2, -0.03, -0.03, 0.9, 0.03, 0.03, seat)
            let blade = side < 0 ? b(-1.12, -0.28, -0.1, -0.86, -0.02, 0.1, plank) : b(0.86, -0.28, -0.1, 1.12, -0.02, 0.1, plank)
            let lock = b(-0.04, -0.04, -0.04, 0.04, 0.06, 0.04, rim)
            m.add(.leg(phase), SIMD3(side * 0.56, 0.5, 0.05), [shaft, blade, lock])
        }
        return m.parts
    }
}
