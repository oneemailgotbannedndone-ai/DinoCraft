import Foundation
import DinoCraftCore

/// Items for tamed creatures.
enum PetTextures {
    static let S = TexturePainter.S

    static func item(_ name: String) -> Canvas? {
        guard name == "saddle" else { return nil }
        // A leather saddle seen from the side: seat, raised front and back, flap, girth strap and a stirrup.
        let c = Canvas(S)
        let leather = Palette([0x4A2A16, 0x6A3E22, 0x86522E, 0xA0683C, 0xBA804E])
        for y in 9..<20 {
            for x in 4..<28 {
                let dx = (Double(x) - 16) / 12, dy = (Double(y) - 16) / 6
                let seat = dx * dx + dy * dy < 1 && !(y < 13 && abs(Double(x) - 16) < 7)
                if seat { c.plot(x, y, leather.step(0.35 + (y < 14 ? 0.35 : 0) - Double(x - 4) / 60)) }
            }
        }
        c.rect(5, 8, 4, 4, leather.colors[3]); c.rect(23, 7, 4, 5, leather.colors[3])      // pommel and cantle
        c.rect(10, 17, 12, 6, leather.colors[1])                                          // flap
        c.line(15, 22, 15, 27, width: 1.5) { _ in leather.colors[0] }                       // stirrup leather
        c.rect(12, 27, 7, 2, RGBA(hex: 0x9A9AA4)); c.plot(12, 26, RGBA(hex: 0x9A9AA4)); c.plot(18, 26, RGBA(hex: 0x9A9AA4))
        c.plot(8, 10, RGBA(hex: 0xD8B040)); c.plot(24, 9, RGBA(hex: 0xD8B040))              // brass studs
        c.outline()
        return c
    }
}
