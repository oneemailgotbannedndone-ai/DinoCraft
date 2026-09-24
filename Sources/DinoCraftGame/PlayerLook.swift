import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// How an explorer looks: the cosmetics chosen in the launcher. Sent to friends with every player
/// update as a short text (`encoded`), so Mac and Windows players see each other's outfits.
struct PlayerLook: Equatable {
    enum Hat: String, CaseIterable {
        case explorer, none, cap, crown, tophat, dinohood, flowers

        var displayName: String {
            switch self {
            case .explorer: return "Explorer Hat"
            case .none: return "No Hat"
            case .cap: return "Cap"
            case .crown: return "Crown"
            case .tophat: return "Top Hat"
            case .dinohood: return "Dino Hood"
            case .flowers: return "Flower Crown"
            }
        }
    }

    enum Back: String, CaseIterable {
        case none, cape, tail, backpack

        var displayName: String {
            switch self {
            case .none: return "Nothing"
            case .cape: return "Cape"
            case .tail: return "Dino Tail"
            case .backpack: return "Backpack"
            }
        }
    }

    /// The first eight are the colours players had before cosmetics, picked from their name.
    static let shirtColors: [UInt32] = [0x3A7BD5, 0xD5563A, 0x3AA66A, 0x9A4AD5, 0xD5A33A, 0x2FB5B0, 0xD54A8A, 0x6A7A3A,
                                        0xE8E4DA, 0x2A2A30, 0xE07A2A, 0x8FD0E8]
    static let shirtNames = ["Blue", "Red", "Green", "Purple", "Gold", "Teal", "Pink", "Olive", "White", "Black", "Orange", "Sky"]
    static let pantsColors: [UInt32] = [0x5A4632, 0x2E3A5A, 0x3A3A3A, 0x4E5A34, 0x8A6A44, 0x6A2E2E]
    static let pantsNames = ["Brown", "Navy", "Charcoal", "Moss", "Sand", "Maroon"]
    static let skinTones: [UInt32] = [0xD9A77E, 0xF1C9A5, 0xC08A5C, 0x8D5A3A, 0x5E3A24]
    static let skinNames = ["Tan", "Light", "Warm", "Brown", "Deep"]
    static let accentColors: [UInt32] = [0xC8323C, 0x3A6ED8, 0x3AA65A, 0xE8B83A, 0x8A4AD5, 0x2A2A30, 0xF08AC0, 0xF2F0EA]
    static let accentNames = ["Red", "Blue", "Green", "Gold", "Purple", "Black", "Pink", "White"]

    var hat = Hat.explorer
    var shirt = 0
    var pants = 0
    var skin = 0
    var back = Back.none
    var accent = 0

    // MARK: Custom skin (painted in the skin creator)

    /// Paint colours; 0 means "not painted" (the model's own colour shows through).
    static let paintColors: [UInt32] = [0x000000, 0x1A1A1E, 0xF2F0EA, 0xC8323C, 0xE07A2A, 0xF2E24A, 0x3AA65A, 0x2E6E2E,
                                        0x3A6ED8, 0x8FD0E8, 0x8A4AD5, 0xF08AC0, 0x7A5230, 0xD9A77E, 0x8A8A92, 0x7A1E24]
    static let faceWidth = 8, faceHeight = 8
    static let chestWidth = 8, chestHeight = 10
    /// Face pixels, row by row from the top-left as you look at the explorer (empty = the default face).
    var face: [UInt8] = []
    /// Shirt-front pixels, the same way (empty = a plain shirt).
    var chest: [UInt8] = []

    var hasFace: Bool { face.contains { $0 != 0 } }
    var hasChest: Bool { chest.contains { $0 != 0 } }

    private static func hex(_ pixels: [UInt8]) -> String {
        String(pixels.map { Character(String($0 & 15, radix: 16)) })
    }

    private static func pixels(_ text: String, count: Int) -> [UInt8] {
        let values = text.compactMap { $0.hexDigitValue }.map { UInt8($0) }
        return values.count == count ? values : []
    }

    /// The look someone has before choosing cosmetics (and on older versions of the game).
    static func defaultLook(for name: String) -> PlayerLook {
        var look = PlayerLook()
        look.shirt = Int(Hashing.seed(from: name.lowercased()) % 8)
        return look
    }

    /// The look a player sent, or their default one.
    static func resolve(_ encoded: String?, name: String) -> PlayerLook {
        encoded.flatMap(PlayerLook.init(encoded:)) ?? defaultLook(for: name)
    }

    /// For example `hat=cap;shirt=3;pants=0;skin=1;back=cape;accent=2`.
    var encoded: String {
        var text = "hat=\(hat.rawValue);shirt=\(shirt);pants=\(pants);skin=\(skin);back=\(back.rawValue);accent=\(accent)"
        if hasFace { text += ";face=" + PlayerLook.hex(face) }
        if hasChest { text += ";chest=" + PlayerLook.hex(chest) }
        return text
    }

    /// A code friends can paste into their skin creator.
    var shareCode: String { "DINOSKIN:" + encoded }

    /// Reads a share code (or a bare encoded look).
    init?(shareCode: String) {
        var text = shareCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.uppercased().hasPrefix("DINOSKIN:") { text = String(text.dropFirst(9)) }
        guard text.contains("hat=") || text.contains("face=") else { return nil }
        self.init(encoded: text)
    }

    init() {}

    init?(encoded: String) {
        guard !encoded.isEmpty else { return nil }
        for pair in encoded.split(separator: ";") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2 else { continue }
            func index(_ count: Int) -> Int { max(0, min(count - 1, Int(kv[1]) ?? 0)) }
            switch kv[0] {
            case "hat": hat = Hat(rawValue: kv[1]) ?? .explorer
            case "shirt": shirt = index(PlayerLook.shirtColors.count)
            case "pants": pants = index(PlayerLook.pantsColors.count)
            case "skin": skin = index(PlayerLook.skinTones.count)
            case "back": back = Back(rawValue: kv[1]) ?? .none
            case "accent": accent = index(PlayerLook.accentColors.count)
            case "face": face = PlayerLook.pixels(kv[1], count: PlayerLook.faceWidth * PlayerLook.faceHeight)
            case "chest": chest = PlayerLook.pixels(kv[1], count: PlayerLook.chestWidth * PlayerLook.chestHeight)
            default: break
            }
        }
    }
}

/// The blocky explorer model, shared by the Mac and Windows renderers.
/// Part kinds: 0 body, 1 head, 2 left arm, 3 right arm, 4 left leg, 5 right leg, 6 cape, 7 tail.
enum PlayerAvatar {
    typealias Box = (SIMD3<Float>, SIMD3<Float>, SIMD4<Float>)
    struct Part {
        let kind: Int
        let pivot: SIMD3<Float>
        let boxes: [Box]
    }

    /// sRGB hex to the linear colour the model shaders use.
    static func color(_ hex: UInt32) -> SIMD4<Float> {
        func lin(_ v: UInt32) -> Float {
            let x = Float(v & 0xFF) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return SIMD4(lin(hex >> 16), lin(hex >> 8), lin(hex), 1)
    }

    static func parts(_ look: PlayerLook) -> [Part] {
        let skin = color(PlayerLook.skinTones[look.skin]), shirt = color(PlayerLook.shirtColors[look.shirt])
        let pants = color(PlayerLook.pantsColors[look.pants]), accent = color(PlayerLook.accentColors[look.accent])
        let boots = color(0x3A2A1E), belt = color(0x2A2016), eye = color(0x2A1E14)
        func b(_ x0: Float, _ y0: Float, _ z0: Float, _ x1: Float, _ y1: Float, _ z1: Float, _ c: SIMD4<Float>) -> Box {
            (SIMD3(x0, y0, z0), SIMD3(x1, y1, z1), c)
        }

        var body: [Box] = [b(-0.25, 0, -0.13, 0.25, 0.72, 0.13, shirt), b(-0.26, 0, -0.14, 0.26, 0.07, 0.14, belt)]
        if look.hasChest {
            body += painted(look.chest, width: PlayerLook.chestWidth, height: PlayerLook.chestHeight, left: 0.25, right: -0.25,
                            top: 0.72, bottom: 0.07, z: -0.13)
        }
        if look.back == .backpack {
            let leather = color(0x7A5230)
            body += [b(-0.19, 0.12, 0.13, 0.19, 0.62, 0.32, leather), b(-0.2, 0.44, 0.13, 0.2, 0.64, 0.34, accent),
                     b(-0.23, 0.14, -0.14, -0.17, 0.72, 0.14, leather), b(0.17, 0.14, -0.14, 0.23, 0.72, 0.14, leather)]
        }

        var head: [Box] = [b(-0.22, 0, -0.22, 0.22, 0.42, 0.22, skin)]
        if look.hasFace {
            head += painted(look.face, width: PlayerLook.faceWidth, height: PlayerLook.faceHeight, left: 0.22, right: -0.22,
                            top: 0.42, bottom: 0, z: -0.22)
        } else {
            head += [b(-0.13, 0.22, -0.23, -0.06, 0.28, -0.22, eye), b(0.06, 0.22, -0.23, 0.13, 0.28, -0.22, eye)]
        }
        switch look.hat {
        case .explorer:
            let hat = color(0xC8A46A), band = color(0x6A4A2A)
            head += [b(-0.34, 0.38, -0.34, 0.34, 0.43, 0.34, hat), b(-0.24, 0.43, -0.24, 0.24, 0.62, 0.24, hat),
                     b(-0.245, 0.43, -0.245, 0.245, 0.49, 0.245, band)]
        case .none:
            head += [b(-0.225, 0.3, -0.18, 0.225, 0.45, 0.225, color(0x4A3322))]   // hair
        case .cap:
            head += [b(-0.23, 0.34, -0.23, 0.23, 0.5, 0.23, accent), b(-0.21, 0.34, -0.42, 0.21, 0.38, -0.22, accent),
                     b(-0.04, 0.5, -0.04, 0.04, 0.53, 0.04, color(0xF2F0EA))]
        case .crown:
            let gold = color(0xE8B83A)
            head += [b(-0.23, 0.4, -0.23, 0.23, 0.5, 0.23, gold), b(-0.03, 0.43, -0.24, 0.03, 0.47, -0.23, accent)]
            for (x, z) in [(-0.19, -0.19), (0.19, -0.19), (-0.19, 0.19), (0.19, 0.19), (0.0, -0.19), (0.0, 0.19), (-0.19, 0.0), (0.19, 0.0)] {
                head.append(b(Float(x) - 0.03, 0.5, Float(z) - 0.03, Float(x) + 0.03, 0.6, Float(z) + 0.03, gold))
            }
        case .tophat:
            let black = color(0x1E1E24)
            head += [b(-0.3, 0.41, -0.3, 0.3, 0.45, 0.3, black), b(-0.2, 0.45, -0.2, 0.2, 0.82, 0.2, black),
                     b(-0.205, 0.48, -0.205, 0.205, 0.54, 0.205, accent)]
        case .dinohood:
            let green = color(0x4E9A3A), spike = color(0xE0782A), tooth = color(0xF2F0EA)
            head += [b(-0.25, 0.42, -0.25, 0.25, 0.52, 0.26, green), b(-0.26, 0.04, -0.2, -0.22, 0.46, 0.26, green),
                     b(0.22, 0.04, -0.2, 0.26, 0.46, 0.26, green), b(-0.25, 0.04, 0.22, 0.25, 0.46, 0.27, green),
                     b(-0.25, 0.42, -0.38, 0.25, 0.5, -0.25, green),
                     b(-0.2, 0.39, -0.37, -0.15, 0.42, -0.33, tooth), b(0.15, 0.39, -0.37, 0.2, 0.42, -0.33, tooth),
                     b(-0.18, 0.5, -0.33, -0.1, 0.55, -0.27, color(0xF2E24A)), b(0.1, 0.5, -0.33, 0.18, 0.55, -0.27, color(0xF2E24A))]
            for z in [Float(-0.14), 0.02, 0.18] { head.append(b(-0.03, 0.52, z - 0.04, 0.03, 0.62, z + 0.04, spike)) }
        case .flowers:
            head += [b(-0.23, 0.4, -0.23, 0.23, 0.44, 0.23, color(0x4E9A3A))]
            let petals: [(Float, Float, UInt32)] = [(-0.2, -0.2, 0xF08AC0), (0.2, -0.2, 0xF2E24A), (0, -0.23, 0xF2F0EA),
                                                   (-0.23, 0.05, 0xC8323C), (0.23, 0.05, 0x8FD0E8), (0, 0.23, 0xF08AC0)]
            for (x, z, hex) in petals { head.append(b(x - 0.045, 0.42, z - 0.045, x + 0.045, 0.5, z + 0.045, color(hex))) }
        }

        let arm: [Box] = [b(-0.12, -0.66, -0.12, 0.12, 0.04, 0.12, shirt), b(-0.115, -0.72, -0.115, 0.115, -0.5, 0.115, skin)]
        let leg: [Box] = [b(-0.12, -0.75, -0.12, 0.12, 0, 0.12, pants), b(-0.125, -0.75, -0.14, 0.125, -0.58, 0.13, boots)]
        var parts = [
            Part(kind: 0, pivot: SIMD3(0, 0.75, 0), boxes: body),
            Part(kind: 1, pivot: SIMD3(0, 1.47, 0), boxes: head),
            Part(kind: 2, pivot: SIMD3(-0.37, 1.4, 0), boxes: arm),
            Part(kind: 3, pivot: SIMD3(0.37, 1.4, 0), boxes: arm),
            Part(kind: 4, pivot: SIMD3(-0.13, 0.75, 0), boxes: leg),
            Part(kind: 5, pivot: SIMD3(0.13, 0.75, 0), boxes: leg),
        ]
        switch look.back {
        case .cape:
            parts.append(Part(kind: 6, pivot: SIMD3(0, 1.45, 0.14),
                              boxes: [b(-0.24, -1.0, 0, 0.24, 0, 0.04, accent), b(-0.25, -0.06, -0.01, 0.25, 0, 0.05, color(0xE8B83A))]))
        case .tail:
            let green = color(0x4E9A3A), spike = color(0xE0782A)
            parts.append(Part(kind: 7, pivot: SIMD3(0, 0.82, 0.13),
                              boxes: [b(-0.1, -0.1, 0, 0.1, 0.1, 0.25, green), b(-0.07, -0.09, 0.25, 0.07, 0.05, 0.5, green),
                                      b(-0.04, -0.08, 0.5, 0.04, 0.0, 0.72, green),
                                      b(-0.02, 0.1, 0.06, 0.02, 0.16, 0.16, spike), b(-0.02, 0.05, 0.3, 0.02, 0.1, 0.4, spike)]))
        case .none, .backpack:
            break
        }
        return parts
    }

    /// Thin boxes for painted pixels on a front face (at depth `z`, facing -Z), merging runs in each row.
    /// `left` is the x of the first column as you look at the explorer.
    private static func painted(_ pixels: [UInt8], width: Int, height: Int, left: Float, right: Float,
                                top: Float, bottom: Float, z: Float) -> [Box] {
        var boxes: [Box] = []
        let cw = (right - left) / Float(width), ch = (top - bottom) / Float(height)
        for row in 0..<height {
            var col = 0
            while col < width {
                let value = pixels[row * width + col]
                guard value != 0 else { col += 1; continue }
                var run = 1
                while col + run < width && pixels[row * width + col + run] == value { run += 1 }
                let x0 = left + Float(col) * cw, x1 = left + Float(col + run) * cw
                let y1 = top - Float(row) * ch, y0 = y1 - ch
                boxes.append((SIMD3(min(x0, x1), y0, z - 0.008), SIMD3(max(x0, x1), y1, z + 0.001),
                              color(PlayerLook.paintColors[Int(value) & 15])))
                col += run
            }
        }
        return boxes
    }

    /// The joint rotation for a part (the same animation on Mac and Windows).
    static func pose(kind: Int, pitch: Float, walk: Float, moving: Float, sneaking: Bool, swing: Float) -> Mat4 {
        let swingLeg = sin(walk) * 0.8 * min(1, moving)
        let armSwing = sin(swing * .pi)
        switch kind {
        case 0: return sneaking ? MathUtil.rotationX(-0.4) : matrix_identity_float4x4
        case 1: return MathUtil.rotationX(pitch * 0.8)
        case 2: return MathUtil.rotationX(swingLeg)
        case 3: return MathUtil.rotationX(-swingLeg - armSwing * 1.6)
        case 4: return MathUtil.rotationX(-swingLeg)
        case 5: return MathUtil.rotationX(swingLeg)
        case 6: return MathUtil.rotationX(-(0.08 + min(1, moving) * 0.55 + abs(sin(walk)) * 0.08 * moving + (sneaking ? 0.4 : 0)))
        default: return MathUtil.rotationY(sin(walk * 0.5) * 0.35 * max(0.3, moving)) * MathUtil.rotationX(-0.15)
        }
    }
}
