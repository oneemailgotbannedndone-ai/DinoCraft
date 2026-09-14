import Foundation
import DinoCraftCore

/// Food from farm animals and the Pookpook.
enum FarmTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S

    static func item(_ name: String) -> Canvas? {
        let raw = name.hasPrefix("raw_")
        switch name {
        case "raw_pork", "cooked_pork":
            return chop(raw ? Palette([0xC8606A, 0xDA7A82, 0xEA949A, 0xF4B0B4]) : Palette([0x7A4020, 0x96542C, 0xB06A3A, 0xC8844A]),
                        fat: raw ? 0xF6E0E0 : 0xE0B880, seed: 1)
        case "raw_beef", "cooked_beef":
            return chop(raw ? Palette([0x9A2A2A, 0xB43A34, 0xC84A40, 0xDA6A5A]) : Palette([0x5A2E18, 0x74401E, 0x8E5228, 0xA86A36]),
                        fat: raw ? 0xF2D8D0 : 0xD8A878, seed: 2)
        case "raw_mutton", "cooked_mutton":
            return drumstick(raw ? Palette([0xB84A4A, 0xCC6060, 0xDC7A74]) : Palette([0x7A4222, 0x965830, 0xB0703E]), seed: 3)
        case "raw_poultry", "cooked_poultry":
            return drumstick(raw ? Palette([0xE8B8A8, 0xF2CABC, 0xFADCD0]) : Palette([0xB8702A, 0xD08A3A, 0xE4A450]), seed: 4)
        default:
            return nil
        }
    }

    static func chop(_ p: Palette, fat: UInt32, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        for y in 7..<26 {
            for x in 5..<28 {
                let dx = Double(x) - 16, dy = Double(y) - 16
                guard dx * dx / 120 + dy * dy / 80 < 1 else { continue }
                let edge = dx * dx / 120 + dy * dy / 80 > 0.72
                c.plot(x, y, edge ? RGBA(hex: fat) : p.step(0.2 + T.hash01(seed, x / 2, y / 2) * 0.6 + (dy < -3 ? 0.2 : 0)))
            }
        }
        c.disc(12, 18, 2.2, RGBA(hex: 0xF2EBD6))
        c.outline()
        return c
    }

    static func drumstick(_ p: Palette, seed: UInt64) -> Canvas {
        let c = Canvas(S)
        let bone = RGBA(hex: 0xF2EBD6)
        c.line(20, 20, 27, 27, width: 3) { _ in bone }
        c.disc(27, 26, 2.2, bone); c.disc(26, 28, 2.2, bone)
        for y in 4..<24 {
            for x in 4..<24 {
                let dx = Double(x) - 12, dy = Double(y) - 12
                guard dx * dx + dy * dy < 70 - Double(x + y - 24) * 1.5 else { continue }
                c.plot(x, y, p.step(0.15 + T.hash01(seed, x / 2, y / 2) * 0.5 + (x + y < 20 ? 0.3 : 0)))
            }
        }
        c.outline()
        return c
    }
}
