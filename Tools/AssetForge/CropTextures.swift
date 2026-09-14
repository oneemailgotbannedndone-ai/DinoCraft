import Foundation
import DinoCraftCore

/// Farmland, wheat and carrot growth stages, seeds, bread and bone meal.
enum CropTextures {
    typealias T = TexturePainter
    static let S = TexturePainter.S
    static let stem = Palette([0x3F7A24, 0x4E8A2A, 0x62A534, 0x7CC044, 0x9AD65A])
    static let ripe = Palette([0x9A7024, 0xB8892E, 0xD0A53C, 0xE2BE52, 0xF0D478])

    static func add(to t: inout [String: Canvas]) {
        for s in 0..<4 {
            t["wheat_stage\(s)"] = wheat(s)
            t["carrots_stage\(s)"] = carrots(s)
        }
        t["farmland_top"] = farmland()
    }

    static func wheat(_ stage: Int) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: UInt64(600 + stage))
        let height = [8.0, 14, 21, 27][stage]
        for k in 0..<7 {
            let x0 = 3 + Double(k) * 4.2 + rng.nextDouble() * 2
            let h = height * (0.8 + rng.nextDouble() * 0.25)
            let lean = (rng.nextDouble() - 0.5) * 4
            c.line(x0, 32, x0 + lean, 32 - h, width: 1.5) { t in
                stage == 3 ? ripe.ramp(0.1 + t * 0.6) : stem.ramp(0.15 + t * 0.55 + Double(stage) * 0.06)
            }
            guard stage >= 2 else { continue }
            for g in 0..<5 {
                let y = 32 - h + Double(g) * 1.7 + 1
                let side: Double = g % 2 == 0 ? -0.9 : 0.9
                c.disc(x0 + lean + side, y, 1.1, stage == 3 ? ripe.step(0.5 + Double(g % 2) * 0.3) : stem.step(0.75))
            }
        }
        return c
    }

    static func carrots(_ stage: Int) -> Canvas {
        let c = Canvas(S)
        var rng = SplitMix64(seed: UInt64(620 + stage))
        let height = [7.0, 12, 17, 22][stage]
        for k in 0..<4 {
            let bx = 5 + Double(k) * 7.3
            if stage == 3 {
                c.disc(bx, 30, 2.4, RGBA(hex: 0xE8782A))
                c.disc(bx - 0.6, 29.4, 1, RGBA(hex: 0xF7A04A))
            }
            for f in 0..<4 {
                let lean = (Double(f) - 1.5) * 2.6 + (rng.nextDouble() - 0.5)
                let top = 30 - height * (0.75 + rng.nextDouble() * 0.3)
                c.line(bx, 30, bx + lean, top, width: 1.3) { t in stem.ramp(0.2 + t * 0.75) }
            }
        }
        return c
    }

    static func farmland() -> Canvas {
        let c = T.paintDirt(630)
        for y in 0..<S {
            for x in 0..<S {
                let furrow = y % 8 < 2
                c[x, y] = furrow ? c[x, y].shade(0.5) : c[x, y].shade(0.8).mix(RGBA(hex: 0x3A2414), 0.25)
            }
        }
        return c
    }

    static func item(_ name: String) -> Canvas? {
        let c = Canvas(S)
        switch name {
        case "wheat_seeds":
            var rng = SplitMix64(seed: 640)
            for _ in 0..<9 {
                let x = 8 + rng.nextDouble() * 16, y = 9 + rng.nextDouble() * 15
                c.disc(x, y, 2, RGBA(hex: 0x8CA83E))
                c.plot(Int(x) - 1, Int(y) - 1, RGBA(hex: 0xD6E48A))
            }
        case "wheat":
            for k in 0..<5 {
                let dx = (Double(k) - 2) * 3.5
                c.line(16 + dx * 0.25, 29, 16 + dx, 9, width: 1.6) { t in ripe.ramp(0.15 + t * 0.4) }
                for g in 0..<4 {
                    c.disc(16 + dx + (g % 2 == 0 ? -1 : 1), 5 + Double(g) * 2.2, 1.4, ripe.step(0.55 + Double(g % 2) * 0.3))
                }
            }
            c.rect(12, 20, 9, 2, RGBA(hex: 0x7A4E22))
        case "carrot":
            for i in 0...24 {
                let t = Double(i) / 24
                c.disc(7 + 14 * t, 27 - 15 * t, 0.7 + 2.7 * t, RGBA(hex: 0xD8601E).mix(RGBA(hex: 0xF49A44), t))
            }
            for (x, y) in [(12, 21), (15, 18), (18, 15)] { c.plot(x, y, RGBA(hex: 0xA8461A)) }
            for (ex, ey) in [(28.0, 3.0), (24.0, 2.0), (29.0, 8.0)] {
                c.line(22, 11, ex, ey, width: 1.8) { t in stem.ramp(0.3 + t * 0.6) }
            }
        case "bread":
            for y in 9..<25 {
                for x in 4..<29 {
                    let dx = (Double(x) - 16) / 12.5, dy = (Double(y) - 17) / 8
                    guard dx * dx + dy * dy < 1 else { continue }
                    let top = dy < -0.1
                    c.plot(x, y, top ? RGBA(hex: 0xC8843A).lighten(0.1 * (-dy)) : RGBA(hex: 0x9A5A26))
                }
            }
            for k in 0..<3 {
                let x = 10 + k * 5
                c.line(Double(x), 12, Double(x + 3), 16, width: 1.2) { _ in RGBA(hex: 0xF0C47A) }
            }
        case "bone_meal":
            var rng = SplitMix64(seed: 650)
            for _ in 0..<26 {
                let a = rng.nextDouble() * 2 * .pi, r = rng.nextDouble() * 8
                let x = 16 + cos(a) * r * 1.3, y = 20 + sin(a) * r * 0.6 - (8 - r) * 0.5
                c.disc(x, y, 1.6, RGBA(hex: 0xEDEAE0).shade(0.85 + rng.nextDouble() * 0.15))
            }
        default:
            return nil
        }
        c.outline()
        return c
    }
}
