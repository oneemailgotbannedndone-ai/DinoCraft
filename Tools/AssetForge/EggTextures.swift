import Foundation
import DinoCraftCore

/// Spawn egg icons: a speckled egg in each creature's colors.
enum EggTextures {
    static let S = TexturePainter.S

    static let colors: [String: (UInt32, UInt32)] = [
        "trikey": (0x7FA35A, 0xD9824A), "dodo": (0x8A9BA8, 0xE8B84A), "longneck": (0x6E8F7A, 0x3E5A4A),
        "raptor": (0x8A5A3A, 0x3A2214), "spitter": (0x4F8A3A, 0xE0C23A), "crawler": (0x3A2A22, 0xD8782A),
        "magma_raptor": (0x2A2228, 0xFF7A1A), "villager": (0x6A4E8A, 0xE0B24A), "stego": (0x8A7A4A, 0xC8602A),
        "ankylo": (0x6A6A58, 0xE6DCC0), "rex": (0x5E4A36, 0xB89A70), "compy": (0x6A9A3A, 0xD8E0A0),
        "ptero": (0x7A5A8A, 0xE0703A), "parasaur": (0x5E8A7A, 0xD8603A), "sailback": (0x8A5A3A, 0xF2B24A),
        "bone_walker": (0xD9CEB2, 0x3A3228), "scorpion": (0xC89A4A, 0xFF5A3A), "pig": (0xE8A0A0, 0xA85A5A),
        "cow": (0x4A3A2A, 0xE8E0D0), "sheep": (0xE8E8E0, 0xB89878), "chicken": (0xF0F0E8, 0xD83A2A),
        "pookpook": (0xE0C060, 0x6A4A2A), "carnotaurus": (0xA84A3A, 0x2E2018), "allosaurus": (0x9A7A4A, 0x5A3A22),
        "baryonyx": (0x5A7A6A, 0xC8B888), "troodon": (0x6A6A8A, 0xF0E060), "spinosaurus": (0x6A5A4A, 0xD86A3A),
        "grumblesaurus": (0x2A2A2A, 0xF4F4F0),
    ]

    static func item(_ name: String) -> Canvas? {
        guard name.hasPrefix("spawn_egg_") else { return nil }
        let kind = String(name.dropFirst("spawn_egg_".count))
        let (baseHex, spotHex) = colors[kind] ?? (0x9A9A9A, 0x505050)
        let base = RGBA(hex: baseHex), spot = RGBA(hex: spotHex)
        let c = Canvas(S)
        var rng = SplitMix64(seed: kind.unicodeScalars.reduce(UInt64(17)) { $0 &* 31 &+ UInt64($1.value) })
        // Egg outline: wider at the bottom
        func inside(_ x: Double, _ y: Double) -> Bool {
            let dy = (y - 17) / 12.5
            let halfWidth = 9.5 * sqrt(max(0, 1 - dy * dy)) * (y < 17 ? 0.86 : 1.0)
            return abs(x - 15.5) <= halfWidth
        }
        for y in 4..<31 {
            for x in 4..<28 where inside(Double(x), Double(y)) {
                let light = 1.12 - Double(x - 6) / 40 - Double(y - 4) / 90
                c.plot(x, y, base.shade(light))
            }
        }
        // Spots in the second color (deterministic per creature)
        for _ in 0..<7 {
            let sx = 8 + Double(rng.nextInt(16)), sy = 8 + Double(rng.nextInt(20))
            let r = 1.2 + Double(rng.nextInt(3)) * 0.6
            for y in Int(sy - r)...Int(sy + r) {
                for x in Int(sx - r)...Int(sx + r) where inside(Double(x), Double(y)) {
                    let dx = Double(x) + 0.5 - sx, dy = Double(y) + 0.5 - sy
                    if dx * dx + dy * dy <= r * r { c.plot(x, y, spot) }
                }
            }
        }
        // Shine
        c.plot(11, 9, RGBA(hex: 0xFFFFFF, alpha: 0.9)); c.plot(12, 9, RGBA(hex: 0xFFFFFF, alpha: 0.7)); c.plot(11, 10, RGBA(hex: 0xFFFFFF, alpha: 0.7))
        c.outline()
        return c
    }
}
