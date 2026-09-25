import Foundation

/// The hunger bar's drumstick, drawn pixel by pixel on both platforms like `HeartIcon`.
/// Better than a plain bar: the gold rim shows how much "fullness" (saturation) you have left before
/// the drumsticks start to empty, the bar shakes when you're starving and ripples when you eat.
enum HungerIcon {
    static let width = 9, height = 9

    private static let shape = [
        "...KKKK..",
        "..KLLMMK.",
        ".KLLMMMDK",
        ".KLMMMMDK",
        ".KMMMMDDK",
        "..KMDDDK.",
        ".KWKKKK..",
        "KWWK.....",
        ".KK......",
    ]

    private static let colors: [Character: UInt32] = [
        "K": 0x2A1408, "L": 0xF2A866, "M": 0xC8682A, "D": 0x8A3E16, "W": 0xF4ECD8,
    ]
    private static let emptyInside: UInt32 = 0x3A2414
    private static let gold: UInt32 = 0xF2C14E

    /// Every pixel to draw: (column, row, colour). `fill` is 1 full, 0.5 half, 0 empty; a half drumstick
    /// keeps its meaty right side. `saturated` draws the rim in gold.
    static func pixels(fill: Double, saturated: Bool) -> [(Int, Int, UInt32)] {
        var out: [(Int, Int, UInt32)] = []
        for (row, line) in shape.enumerated() {
            for (col, ch) in line.enumerated() where ch != "." {
                if ch == "K" {
                    out.append((col, row, saturated ? gold : colors["K"]!))
                    continue
                }
                let filled = fill >= 1 || (fill > 0 && col >= 4)
                out.append((col, row, filled ? colors[ch]! : emptyInside))
            }
        }
        return out
    }

    /// Fill of drumstick `index` (0 is the rightmost) for a hunger value 0...20.
    static func fill(index: Int, hunger: Double) -> Double {
        let value = hunger / 2 - Double(index)
        return value >= 1 ? 1 : (value > 0 ? 0.5 : 0)
    }

    /// Is drumstick `index` covered by saturation (0...20, same scale as hunger)?
    static func saturated(index: Int, saturation: Double) -> Bool {
        saturation / 2 > Double(index) + 0.25
    }

    /// Vertical offset in icon pixels: a nervous shake when starving, a ripple from right to left after eating.
    static func offset(index: Int, hunger: Double, eatFlash: Double, time: Double) -> Double {
        var y = 0.0
        if hunger <= 6 {
            // Jitter, a different pattern per drumstick, changing about 12 times a second.
            var h = UInt64(Int(time * 12)) &* 0x9E3779B97F4A7C15 &+ UInt64(index) &* 0xBF58476D1CE4E5B9
            h ^= h >> 31
            y += Double(Int(h % 3) - 1)
        }
        if eatFlash > 0 {
            let wave = (1 - eatFlash) * 14 - Double(index)
            if wave > 0 && wave < 3 { y -= sin(wave / 3 * .pi) * 1.5 }
        }
        return y
    }
}
