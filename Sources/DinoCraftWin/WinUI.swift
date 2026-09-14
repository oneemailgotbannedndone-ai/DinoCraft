import Foundation
import DinoCraftCore

/// A tiny 5×7 pixel font with upper and lower case, digits, punctuation, a heart and a dot, drawn as solid quads.
enum PixelFont {
    static func rows(for character: Character) -> [UInt8] {
        if let rows = glyphs[character] { return rows }
        let upper = String(character).uppercased().first ?? character
        return glyphs[upper] ?? glyphs["?"]!
    }

    private static let glyphs: [Character: [UInt8]] = [
        " ": [0, 0, 0, 0, 0, 0, 0],
        "A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30], "C": [14, 17, 16, 16, 16, 17, 14],
        "D": [30, 17, 17, 17, 17, 17, 30], "E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
        "G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17], "I": [14, 4, 4, 4, 4, 4, 14],
        "J": [7, 2, 2, 2, 2, 18, 12], "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
        "M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 17, 25, 21, 19, 17, 17], "O": [14, 17, 17, 17, 17, 17, 14],
        "P": [30, 17, 17, 30, 16, 16, 16], "Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
        "S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4], "U": [17, 17, 17, 17, 17, 17, 14],
        "V": [17, 17, 17, 17, 17, 10, 4], "W": [17, 17, 17, 21, 21, 21, 10], "X": [17, 17, 10, 4, 10, 17, 17],
        "Y": [17, 17, 17, 10, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
        "0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14], "2": [14, 17, 1, 2, 4, 8, 31],
        "3": [31, 2, 4, 2, 1, 17, 14], "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 30, 1, 1, 17, 14],
        "6": [6, 8, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8], "8": [14, 17, 17, 14, 17, 17, 14],
        "9": [14, 17, 17, 15, 1, 2, 12],
        ".": [0, 0, 0, 0, 0, 12, 12], ",": [0, 0, 0, 0, 12, 4, 8], ":": [0, 12, 12, 0, 12, 12, 0],
        ";": [0, 12, 12, 0, 12, 4, 8], "!": [4, 4, 4, 4, 4, 0, 4], "?": [14, 17, 1, 2, 4, 0, 4],
        "'": [4, 4, 8, 0, 0, 0, 0], "\"": [10, 10, 0, 0, 0, 0, 0], "-": [0, 0, 0, 31, 0, 0, 0],
        "_": [0, 0, 0, 0, 0, 0, 31], "+": [0, 4, 4, 31, 4, 4, 0], "=": [0, 0, 31, 0, 31, 0, 0],
        "/": [1, 1, 2, 4, 8, 16, 16], "\\": [16, 16, 8, 4, 2, 1, 1], "(": [2, 4, 8, 8, 8, 4, 2],
        ")": [8, 4, 2, 2, 2, 4, 8], "<": [2, 4, 8, 16, 8, 4, 2], ">": [8, 4, 2, 1, 2, 4, 8],
        "#": [10, 10, 31, 10, 31, 10, 10], "*": [0, 4, 21, 14, 21, 4, 0], "%": [24, 25, 2, 4, 8, 19, 3],
        "&": [12, 18, 20, 8, 21, 18, 13], "@": [14, 17, 23, 21, 23, 16, 14], "[": [14, 8, 8, 8, 8, 8, 14],
        "]": [14, 2, 2, 2, 2, 2, 14], "$": [4, 15, 20, 14, 5, 30, 4], "^": [4, 10, 17, 0, 0, 0, 0],
        "~": [0, 0, 8, 21, 2, 0, 0], "|": [4, 4, 4, 4, 4, 4, 4],
        "\u{2665}": [0, 10, 31, 31, 14, 4, 0],
        "\u{25CF}": [0, 14, 31, 31, 31, 14, 0],
        "a": [0, 0, 14, 1, 15, 17, 15], "b": [16, 16, 22, 25, 17, 17, 30], "c": [0, 0, 14, 16, 16, 17, 14],
        "d": [1, 1, 13, 19, 17, 17, 15], "e": [0, 0, 14, 17, 31, 16, 14], "f": [6, 9, 8, 28, 8, 8, 8],
        "g": [0, 15, 17, 17, 15, 1, 14], "h": [16, 16, 22, 25, 17, 17, 17], "i": [4, 0, 12, 4, 4, 4, 14],
        "j": [2, 0, 6, 2, 2, 18, 12], "k": [16, 16, 18, 20, 24, 20, 18], "l": [12, 4, 4, 4, 4, 4, 14],
        "m": [0, 0, 26, 21, 21, 17, 17], "n": [0, 0, 22, 25, 17, 17, 17], "o": [0, 0, 14, 17, 17, 17, 14],
        "p": [0, 30, 17, 17, 30, 16, 16], "q": [0, 13, 19, 17, 15, 1, 1], "r": [0, 0, 22, 25, 16, 16, 16],
        "s": [0, 0, 14, 16, 14, 1, 30], "t": [8, 8, 28, 8, 8, 9, 6], "u": [0, 0, 17, 17, 17, 19, 13],
        "v": [0, 0, 17, 17, 17, 10, 4], "w": [0, 0, 17, 17, 21, 21, 10], "x": [0, 0, 17, 10, 4, 10, 17],
        "y": [0, 17, 17, 17, 15, 1, 14], "z": [0, 0, 31, 2, 4, 8, 31],
    ]
}

/// Builds 2D overlay geometry: `x, y, u, v, layer, r, g, b, a` per vertex, in pixels from the top-left.
/// A layer of -1 is a solid colour, 0… a block texture, and `itemLayerOffset`… an item texture.
struct UIBuilder {
    static let itemLayerOffset: Float = 10_000
    private(set) var vertices: [Float] = []

    mutating func rect(_ x: Float, _ y: Float, _ w: Float, _ h: Float, _ color: SIMD4<Float>) {
        quad(x, y, w, h, layer: -1, color: color)
    }

    mutating func icon(_ x: Float, _ y: Float, _ size: Float, layer: Float) {
        guard layer >= 0 else { return }
        quad(x, y, size, size, layer: layer, color: SIMD4(1, 1, 1, 1))
    }

    private mutating func quad(_ x: Float, _ y: Float, _ w: Float, _ h: Float, layer: Float, color: SIMD4<Float>) {
        let corners: [(Float, Float, Float, Float)] = [(x, y, 0, 0), (x + w, y, 1, 0), (x + w, y + h, 1, 1),
                                                      (x, y, 0, 0), (x + w, y + h, 1, 1), (x, y + h, 0, 1)]
        for c in corners { vertices += [c.0, c.1, c.2, c.3, layer, color.x, color.y, color.z, color.w] }
    }

    static func textWidth(_ text: String, scale: Float) -> Float {
        text.isEmpty ? 0 : Float(text.count) * 6 * scale - scale
    }

    mutating func text(_ string: String, x: Float, y: Float, scale: Float, color: SIMD4<Float>, shadow: Bool = true) {
        if shadow { glyphs(string, x + scale, y + scale, scale, SIMD4(0, 0, 0, color.w * 0.75)) }
        glyphs(string, x, y, scale, color)
    }

    mutating func centeredText(_ string: String, centerX: Float, y: Float, scale: Float, color: SIMD4<Float>) {
        text(string, x: centerX - UIBuilder.textWidth(string, scale: scale) / 2, y: y, scale: scale, color: color)
    }

    private mutating func glyphs(_ string: String, _ x: Float, _ y: Float, _ scale: Float, _ color: SIMD4<Float>) {
        var cx = x
        for character in string {
            for (row, bits) in PixelFont.rows(for: character).enumerated() where bits != 0 {
                var column = 0
                while column < 5 {
                    guard bits & (UInt8(16) >> UInt8(column)) != 0 else { column += 1; continue }
                    var run = 1
                    while column + run < 5 && bits & (UInt8(16) >> UInt8(column + run)) != 0 { run += 1 }
                    rect(cx + Float(column) * scale, y + Float(row) * scale, Float(run) * scale, scale, color)
                    column += run
                }
            }
            cx += 6 * scale
        }
    }
}
