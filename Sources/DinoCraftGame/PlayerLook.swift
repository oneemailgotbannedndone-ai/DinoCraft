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
        case wizard, viking, headphones, halo, pirate, beanie, bunny, party

        var displayName: String {
            switch self {
            case .explorer: return "Explorer Hat"
            case .none: return "No Hat"
            case .cap: return "Cap"
            case .crown: return "Crown"
            case .tophat: return "Top Hat"
            case .dinohood: return "Dino Hood"
            case .flowers: return "Flower Crown"
            case .wizard: return "Wizard Hat"
            case .viking: return "Viking Helmet"
            case .headphones: return "Headphones"
            case .halo: return "Halo"
            case .pirate: return "Pirate Hat"
            case .beanie: return "Beanie"
            case .bunny: return "Bunny Ears"
            case .party: return "Party Hat"
            }
        }
    }

    enum Back: String, CaseIterable {
        case none, cape, tail, backpack, wings, dragonwings, jetpack, sword

        var displayName: String {
            switch self {
            case .none: return "Nothing"
            case .cape: return "Cape"
            case .tail: return "Dino Tail"
            case .backpack: return "Backpack"
            case .wings: return "Angel Wings"
            case .dragonwings: return "Dragon Wings"
            case .jetpack: return "Jetpack"
            case .sword: return "Sword"
            }
        }
    }

    /// The first eight are the colours players had before cosmetics, picked from their name.
    static let shirtColors: [UInt32] = [0x3A7BD5, 0xD5563A, 0x3AA66A, 0x9A4AD5, 0xD5A33A, 0x2FB5B0, 0xD54A8A, 0x6A7A3A,
                                        0xE8E4DA, 0x2A2A30, 0xE07A2A, 0x8FD0E8, 0x9AE05A, 0xF2E24A, 0x7A1E24, 0xC8A0F0]
    static let shirtNames = ["Blue", "Red", "Green", "Purple", "Gold", "Teal", "Pink", "Olive", "White", "Black", "Orange", "Sky",
                             "Lime", "Yellow", "Wine", "Lavender"]
    static let pantsColors: [UInt32] = [0x5A4632, 0x2E3A5A, 0x3A3A3A, 0x4E5A34, 0x8A6A44, 0x6A2E2E, 0x3A6ED8, 0xE8E4DA, 0x1A1A1E, 0x7A4AA0]
    static let pantsNames = ["Brown", "Navy", "Charcoal", "Moss", "Sand", "Maroon", "Denim", "White", "Black", "Purple"]
    static let skinTones: [UInt32] = [0xD9A77E, 0xF1C9A5, 0xC08A5C, 0x8D5A3A, 0x5E3A24, 0x7AB84E, 0x6A8AD0, 0xB0B0B8]
    static let skinNames = ["Tan", "Light", "Warm", "Brown", "Deep", "Dino Green", "Alien Blue", "Robot Grey"]
    static let accentColors: [UInt32] = [0xC8323C, 0x3A6ED8, 0x3AA65A, 0xE8B83A, 0x8A4AD5, 0x2A2A30, 0xF08AC0, 0xF2F0EA,
                                         0xE07A2A, 0x2FB5B0, 0x8FD0E8, 0x7A5230]
    static let accentNames = ["Red", "Blue", "Green", "Gold", "Purple", "Black", "Pink", "White", "Orange", "Teal", "Sky", "Leather"]

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

    /// Every other painted side of the explorer (see `SkinRegion`), keyed by region id.
    var paint: [String: [UInt8]] = [:]

    var hasFace: Bool { face.contains { $0 != 0 } }
    var hasChest: Bool { chest.contains { $0 != 0 } }

    /// The pixels of any paintable side (all zeros when it hasn't been painted).
    func pixels(_ region: SkinRegion) -> [UInt8] {
        let stored: [UInt8]
        switch region.id {
        case "hf": stored = face
        case "bf": stored = chest
        default: stored = paint[region.id] ?? []
        }
        return stored.count == region.count ? stored : Array(repeating: 0, count: region.count)
    }

    mutating func setPixels(_ pixels: [UInt8], for region: SkinRegion) {
        let clean = pixels.count == region.count && pixels.contains { $0 != 0 } ? pixels : []
        switch region.id {
        case "hf": face = clean
        case "bf": chest = clean
        default: paint[region.id] = clean.isEmpty ? nil : clean
        }
    }

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

    /// A one-of-a-kind starting look made from a player's ID: hat, colours and back item all come
    /// from it, so no two players start out the same.
    static func oneOfOne(id: String) -> PlayerLook {
        var rng = SplitMix64(seed: Hashing.seed(from: "look-" + id))
        var look = PlayerLook()
        look.hat = Hat.allCases[rng.nextInt(Hat.allCases.count)]
        look.shirt = rng.nextInt(shirtColors.count)
        look.pants = rng.nextInt(pantsColors.count)
        look.skin = rng.nextInt(skinTones.count)
        look.back = Back.allCases[rng.nextInt(Back.allCases.count)]
        look.accent = rng.nextInt(accentColors.count)
        return look
    }

    /// Gives a player who hasn't picked a look yet their one-of-a-kind one (call at startup).
    static func settle(_ store: SettingsStore) {
        guard PlayerLook(encoded: store.settings.cosmetics) == nil else { return }
        store.update { $0.cosmetics = PlayerLook.oneOfOne(id: $0.playerID).encoded }
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
        for region in SkinRegion.all where region.id != "hf" && region.id != "bf" {
            if let pixels = paint[region.id], pixels.contains(where: { $0 != 0 }) { text += ";p.\(region.id)=" + PlayerLook.hex(pixels) }
        }
        return text
    }

    /// Ready-made faces for the skin creator (hex pixels as for `face`).
    static let facePresets: [(name: String, pixels: String)] = [
        ("Smile", "0000000000000000000000000210012000000000010000100011110000000000"),
        ("Sunglasses", "0000000000000000111111111110011100000000000000000011110000000000"),
        ("Dino", "6666666666666666666666666166661666666666111111112121212166666666"),
        ("Beard", "000000000000000000000000011001100000000000cccc00cccccccc0cccccc0"),
        ("Surprised", "0000000000000000021001200210012000000000000110000001100000000000"),
    ]
    /// Ready-made shirt fronts (hex pixels as for `chest`).
    static let chestPresets: [(name: String, pixels: String)] = [
        ("Stripes", "22222222000000002222222200000000222222220000000022222222000000002222222200000000"),
        ("Heart", "00000000000000000330033033333333333333330333333000333300000330000000000000000000"),
        ("Star", "00000000000550000005500055555555055555500055550005500550550000550000000000000000"),
        ("Dino", "00000000000066600000666600006600600666006666660006666000006600000060600000000000"),
        ("Tuxedo", "21100112221001222210012222133122221001222213312222100122221001222210012222100122"),
    ]

    static func presetPixels(_ hex: String, count: Int) -> [UInt8] { pixels(hex, count: count) }

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
            default:
                if kv[0].hasPrefix("p."), let region = SkinRegion.byID[String(kv[0].dropFirst(2))] {
                    let pixels = PlayerLook.pixels(kv[1], count: region.count)
                    if !pixels.isEmpty { paint[region.id] = pixels }
                }
            }
        }
    }
}

/// One paintable side of the explorer in the skin creator: a grid of pixels laid over a face of a
/// body part. Columns run left to right as you look straight at that side.
struct SkinRegion {
    enum Side: String { case front, back, left, right, top }

    let id: String
    let part: String
    let side: Side
    /// `PlayerAvatar.Part.kind` of the body part it's on.
    let kind: Int
    let width: Int, height: Int
    /// The box it covers, in the part's own space.
    let lo: SIMD3<Float>, hi: SIMD3<Float>

    var count: Int { width * height }
    var name: String { "\(part) - \(side.rawValue.capitalized)" }

    /// Parts in the order the skin creator lists them.
    static let parts = ["Head", "Body", "Left Arm", "Right Arm", "Left Leg", "Right Leg"]

    static let all: [SkinRegion] = {
        var list: [SkinRegion] = []
        func add(_ prefix: String, _ part: String, kind: Int, _ sides: [(Side, Int, Int)], lo: SIMD3<Float>, hi: SIMD3<Float>) {
            for (side, w, h) in sides {
                let key = prefix + String(side.rawValue.first!)
                list.append(SkinRegion(id: key, part: part, side: side, kind: kind, width: w, height: h, lo: lo, hi: hi))
            }
        }
        add("h", "Head", kind: 1, [(.front, 8, 8), (.back, 8, 8), (.left, 8, 8), (.right, 8, 8), (.top, 8, 8)],
            lo: SIMD3(-0.22, 0, -0.22), hi: SIMD3(0.22, 0.42, 0.22))
        add("b", "Body", kind: 0, [(.front, 8, 10), (.back, 8, 10), (.left, 4, 10), (.right, 4, 10)],
            lo: SIMD3(-0.25, 0.07, -0.13), hi: SIMD3(0.25, 0.72, 0.13))
        let limbSides: [(Side, Int, Int)] = [(.front, 4, 12), (.back, 4, 12), (.left, 4, 12), (.right, 4, 12)]
        add("la", "Left Arm", kind: 2, limbSides, lo: SIMD3(-0.12, -0.72, -0.12), hi: SIMD3(0.12, 0.04, 0.12))
        add("ra", "Right Arm", kind: 3, limbSides, lo: SIMD3(-0.12, -0.72, -0.12), hi: SIMD3(0.12, 0.04, 0.12))
        add("ll", "Left Leg", kind: 4, limbSides, lo: SIMD3(-0.125, -0.75, -0.14), hi: SIMD3(0.125, 0, 0.13))
        add("rl", "Right Leg", kind: 5, limbSides, lo: SIMD3(-0.125, -0.75, -0.14), hi: SIMD3(0.125, 0, 0.13))
        return list
    }()

    static let byID: [String: SkinRegion] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    static func regions(part: String) -> [SkinRegion] { all.filter { $0.part == part } }

    /// The matching side of the other arm or leg, for copying one to the other.
    var twin: SkinRegion? {
        let swap = ["la": "ra", "ra": "la", "ll": "rl", "rl": "ll"]
        guard let other = swap[String(id.prefix(2))] else { return nil }
        return SkinRegion.byID[other + String(id.dropFirst(2))]
    }

    /// "Copy Other Arm" or "Copy Other Leg" for a limb.
    var copyTwinLabel: String { id.dropFirst().hasPrefix("a") ? "Copy Other Arm" : "Copy Other Leg" }

    /// The colour a side shows where it isn't painted.
    func baseColor(_ look: PlayerLook) -> UInt32 {
        switch kind {
        case 1: return PlayerLook.skinTones[look.skin]
        case 4, 5: return PlayerLook.pantsColors[look.pants]
        default: return PlayerLook.shirtColors[look.shirt]
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
        body += paintedRegions(look, kind: 0)
        if look.back == .backpack {
            let leather = color(0x7A5230)
            body += [b(-0.19, 0.12, 0.13, 0.19, 0.62, 0.32, leather), b(-0.2, 0.44, 0.13, 0.2, 0.64, 0.34, accent),
                     b(-0.23, 0.14, -0.14, -0.17, 0.72, 0.14, leather), b(0.17, 0.14, -0.14, 0.23, 0.72, 0.14, leather)]
        }

        var head: [Box] = [b(-0.22, 0, -0.22, 0.22, 0.42, 0.22, skin)]
        head += paintedRegions(look, kind: 1)
        if !look.hasFace {
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
        case .wizard:
            let star = color(0xF2E24A)
            head += [b(-0.33, 0.4, -0.33, 0.33, 0.44, 0.33, accent), b(-0.22, 0.44, -0.22, 0.22, 0.58, 0.22, accent),
                     b(-0.15, 0.58, -0.15, 0.15, 0.72, 0.15, accent), b(-0.08, 0.72, -0.06, 0.08, 0.84, 0.1, accent),
                     b(-0.03, 0.84, 0.04, 0.03, 0.92, 0.12, accent),
                     b(-0.06, 0.5, -0.225, 0.02, 0.56, -0.215, star), b(0.08, 0.62, -0.155, 0.12, 0.66, -0.145, star)]
        case .viking:
            let steel = color(0x9A9AA6), horn = color(0xF2EBD6)
            head += [b(-0.24, 0.3, -0.24, 0.24, 0.52, 0.24, steel), b(-0.245, 0.3, -0.245, 0.245, 0.34, 0.245, color(0x7A5230)),
                     b(-0.03, 0.08, -0.26, 0.03, 0.34, -0.23, steel),
                     b(-0.34, 0.4, -0.05, -0.24, 0.48, 0.05, horn), b(-0.4, 0.46, -0.04, -0.32, 0.62, 0.04, horn),
                     b(0.24, 0.4, -0.05, 0.34, 0.48, 0.05, horn), b(0.32, 0.46, -0.04, 0.4, 0.62, 0.04, horn)]
        case .headphones:
            let dark = color(0x2A2A30)
            head += [b(-0.25, 0.14, -0.08, -0.21, 0.3, 0.08, accent), b(0.21, 0.14, -0.08, 0.25, 0.3, 0.08, accent),
                     b(-0.24, 0.3, -0.03, -0.2, 0.46, 0.03, dark), b(0.2, 0.3, -0.03, 0.24, 0.46, 0.03, dark),
                     b(-0.22, 0.44, -0.03, 0.22, 0.48, 0.03, dark)]
        case .halo:
            let gold = color(0xF2E24A)
            head += [b(-0.2, 0.58, -0.2, 0.2, 0.61, -0.14, gold), b(-0.2, 0.58, 0.14, 0.2, 0.61, 0.2, gold),
                     b(-0.2, 0.58, -0.14, -0.14, 0.61, 0.14, gold), b(0.14, 0.58, -0.14, 0.2, 0.61, 0.14, gold)]
        case .pirate:
            let black = color(0x1E1E24), skull = color(0xF2F0EA)
            head += [b(-0.3, 0.4, -0.2, 0.3, 0.48, 0.2, black), b(-0.24, 0.48, -0.16, 0.24, 0.58, 0.16, black),
                     b(-0.3, 0.44, -0.24, -0.18, 0.56, -0.18, black), b(0.18, 0.44, -0.24, 0.3, 0.56, -0.18, black),
                     b(-0.04, 0.5, -0.17, 0.04, 0.56, -0.16, skull)]
        case .beanie:
            head += [b(-0.23, 0.3, -0.23, 0.23, 0.52, 0.23, accent), b(-0.235, 0.3, -0.235, 0.235, 0.36, 0.235, color(0xF2F0EA)),
                     b(-0.06, 0.52, -0.06, 0.06, 0.6, 0.06, color(0xF2F0EA))]
        case .bunny:
            let fur = color(0xF2F0EA), pink = color(0xF08AC0)
            head += [b(-0.15, 0.42, -0.04, -0.07, 0.8, 0.04, fur), b(0.07, 0.42, -0.04, 0.15, 0.8, 0.04, fur),
                     b(-0.13, 0.48, -0.045, -0.09, 0.76, -0.04, pink), b(0.09, 0.48, -0.045, 0.13, 0.76, -0.04, pink)]
        case .party:
            let stripe = color(0xF2E24A)
            head += [b(-0.13, 0.42, -0.13, 0.13, 0.52, 0.13, accent), b(-0.09, 0.52, -0.09, 0.09, 0.62, 0.09, stripe),
                     b(-0.05, 0.62, -0.05, 0.05, 0.72, 0.05, accent), b(-0.04, 0.72, -0.04, 0.04, 0.78, 0.04, color(0xF2F0EA))]
        }

        switch look.back {
        case .wings, .dragonwings:
            let dragon = look.back == .dragonwings
            let main = dragon ? color(0x4E9A3A) : color(0xF2F0EA), tip = dragon ? accent : color(0xDADAE6)
            body += [b(-0.62, 0.3, 0.14, -0.06, 0.62, 0.18, main), b(-0.8, 0.46, 0.14, -0.6, 0.78, 0.18, main), b(-0.7, 0.18, 0.14, -0.3, 0.3, 0.18, tip),
                     b(0.06, 0.3, 0.14, 0.62, 0.62, 0.18, main), b(0.6, 0.46, 0.14, 0.8, 0.78, 0.18, main), b(0.3, 0.18, 0.14, 0.7, 0.3, 0.18, tip)]
        case .jetpack:
            let metal = color(0x9A9AA6), flame = color(0xF28A2A)
            body += [b(-0.2, 0.14, 0.13, -0.02, 0.62, 0.3, metal), b(0.02, 0.14, 0.13, 0.2, 0.62, 0.3, metal),
                     b(-0.22, 0.56, 0.13, 0.22, 0.64, 0.32, accent), b(-0.17, 0.02, 0.17, -0.05, 0.14, 0.27, flame),
                     b(0.05, 0.02, 0.17, 0.17, 0.14, 0.27, flame)]
        case .sword:
            let steel = color(0xC8CCD6), hilt = color(0x7A5230)
            body += [b(-0.3, 0.02, 0.14, -0.24, 0.9, 0.18, steel)]
            body += [b(-0.36, 0.64, 0.13, -0.18, 0.68, 0.19, accent), b(-0.3, 0.68, 0.14, -0.24, 0.86, 0.18, hilt)]
        default:
            break
        }
        let arm: [Box] = [b(-0.12, -0.66, -0.12, 0.12, 0.04, 0.12, shirt), b(-0.115, -0.72, -0.115, 0.115, -0.5, 0.115, skin)]
        let leg: [Box] = [b(-0.12, -0.75, -0.12, 0.12, 0, 0.12, pants), b(-0.125, -0.75, -0.14, 0.125, -0.58, 0.13, boots)]
        var parts = [
            Part(kind: 0, pivot: SIMD3(0, 0.75, 0), boxes: body),
            Part(kind: 1, pivot: SIMD3(0, 1.47, 0), boxes: head),
            Part(kind: 2, pivot: SIMD3(-0.37, 1.4, 0), boxes: arm + paintedRegions(look, kind: 2)),
            Part(kind: 3, pivot: SIMD3(0.37, 1.4, 0), boxes: arm + paintedRegions(look, kind: 3)),
            Part(kind: 4, pivot: SIMD3(-0.13, 0.75, 0), boxes: leg + paintedRegions(look, kind: 4)),
            Part(kind: 5, pivot: SIMD3(0.13, 0.75, 0), boxes: leg + paintedRegions(look, kind: 5)),
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
        case .none, .backpack, .wings, .dragonwings, .jetpack, .sword:
            break
        }
        return parts
    }

    /// Thin boxes for every painted pixel on a body part's sides, merging runs in each row.
    private static func paintedRegions(_ look: PlayerLook, kind: Int) -> [Box] {
        var boxes: [Box] = []
        for region in SkinRegion.all where region.kind == kind {
            let pixels = look.pixels(region)
            guard pixels.contains(where: { $0 != 0 }) else { continue }
            let lo = region.lo, hi = region.hi, t: Float = 0.008, w = region.width, h = region.height
            for row in 0..<h {
                var col = 0
                while col < w {
                    let value = pixels[row * w + col]
                    guard value != 0 else { col += 1; continue }
                    var run = 1
                    while col + run < w && pixels[row * w + col + run] == value { run += 1 }
                    // Fractions across the side: u runs left to right as you look at it, v top to bottom.
                    let u0 = Float(col) / Float(w), u1 = Float(col + run) / Float(w)
                    let v0 = Float(row) / Float(h), v1 = Float(row + 1) / Float(h)
                    func lerp(_ a: Float, _ b: Float, _ f: Float) -> Float { a + (b - a) * f }
                    let yTop = lerp(hi.y, lo.y, v0), yBottom = lerp(hi.y, lo.y, v1)
                    var a = SIMD3<Float>(0, 0, 0), c = SIMD3<Float>(0, 0, 0)
                    switch region.side {
                    case .front:
                        a = SIMD3(lerp(hi.x, lo.x, u1), yBottom, lo.z - t); c = SIMD3(lerp(hi.x, lo.x, u0), yTop, lo.z + 0.001)
                    case .back:
                        a = SIMD3(lerp(lo.x, hi.x, u0), yBottom, hi.z - 0.001); c = SIMD3(lerp(lo.x, hi.x, u1), yTop, hi.z + t)
                    case .left:
                        a = SIMD3(lo.x - t, yBottom, lerp(lo.z, hi.z, u0)); c = SIMD3(lo.x + 0.001, yTop, lerp(lo.z, hi.z, u1))
                    case .right:
                        a = SIMD3(hi.x - 0.001, yBottom, lerp(hi.z, lo.z, u1)); c = SIMD3(hi.x + t, yTop, lerp(hi.z, lo.z, u0))
                    case .top:
                        a = SIMD3(lerp(hi.x, lo.x, u1), hi.y - 0.001, lerp(hi.z, lo.z, v1)); c = SIMD3(lerp(hi.x, lo.x, u0), hi.y + t, lerp(hi.z, lo.z, v0))
                    }
                    boxes.append((simd_min(a, c), simd_max(a, c), color(PlayerLook.paintColors[Int(value) & 15])))
                    col += run
                }
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

/// The camera modes F5 cycles through.
enum CameraView: Int {
    case firstPerson, behind, front

    var next: CameraView { CameraView(rawValue: (rawValue + 1) % 3) ?? .firstPerson }
}

extension GameSession {
    /// Where the camera sits for a camera view: at the eyes, or pulled back (or forward) so you can see
    /// your own explorer, stopping short of walls. Also returns the direction the camera looks.
    func cameraPlacement(_ view: CameraView, distance: Double = 4) -> (eye: DVec3, yaw: Double, pitch: Double) {
        let eye = player.eyePosition
        guard view != .firstPerson else { return (eye, player.yaw, player.pitch) }
        let look = player.lookDirection
        let away = view == .behind ? -look : look
        var reach = distance
        if let hit = VoxelPhysics.raycast(world, origin: eye, direction: away, maxDistance: distance) {
            reach = max(0.4, hit.distance - 0.3)
        }
        let yaw = view == .behind ? player.yaw : player.yaw + .pi
        let pitch = view == .behind ? player.pitch : -player.pitch
        return (eye + away * reach, yaw, pitch)
    }
}
