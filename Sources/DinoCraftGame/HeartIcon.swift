import Foundation

/// The health heart, drawn pixel by pixel on both platforms. Hardcore worlds get their own heart:
/// deeper crimson with a gold crest and dark cracks, so you always know you only have one life.
enum HeartIcon {
    static let width = 9, height = 8

    private static let normal = [
        ".KKK.KKK.",
        "KRWRKRRRK",
        "KWRRRRRRK",
        "KRRRRRRDK",
        ".KRRRRDK.",
        "..KRRDK..",
        "...KDK...",
        "....K....",
    ]
    private static let hardcore = [
        ".KKK.KKK.",
        "KGWGKGYGK",
        "KWHHDHHHK",
        "KHDHHHDHK",
        ".KHHHHDK.",
        "..KHDHK..",
        "...KHK...",
        "....K....",
    ]
    private static let empty = [
        ".KKK.KKK.",
        "KEEEKEEEK",
        "KEEEEEEEK",
        "KEEEEEEEK",
        ".KEEEEEK.",
        "..KEEEK..",
        "...KEK...",
        "....K....",
    ]

    private static let colors: [Character: UInt32] = [
        "K": 0x1A0508, "R": 0xE8283C, "W": 0xFFD6DA, "D": 0x9A1024,
        "H": 0xA80E24, "G": 0xF2C14E, "Y": 0xFFF1B0, "E": 0x3A1418,
    ]

    /// Every pixel to draw: (column, row, colour). `fill` is 1 for a full heart, 0.5 for half, 0 for empty.
    static func pixels(fill: Double, hardcore isHardcore: Bool) -> [(Int, Int, UInt32)] {
        let full = isHardcore ? hardcore : normal
        var out: [(Int, Int, UInt32)] = []
        for row in 0..<height {
            let emptyRow = Array(empty[row]), fullRow = Array(full[row])
            for col in 0..<width {
                // A half heart shows the full heart's left half.
                let useFull = fill >= 1 || (fill > 0 && col < 5)
                let ch = useFull ? fullRow[col] : emptyRow[col]
                if let color = colors[ch] { out.append((col, row, color)) }
            }
        }
        return out
    }
}
