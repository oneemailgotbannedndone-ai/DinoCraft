import Foundation
import DinoCraftCore
@testable import DinoCraftGame

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

    /// One health heart, `unit` pixels per heart pixel (9×8 heart pixels).
    mutating func heart(x: Float, y: Float, unit: Float, fill: Double, hardcore: Bool, brightness: Float = 1) {
        for (col, row, hex) in HeartIcon.pixels(fill: fill, hardcore: hardcore) {
            // The overlay works in linear colour, so the heart's sRGB palette is linearised first.
            func channel(_ shift: UInt32) -> Float { pow(Float((hex >> shift) & 255) / 255, 2.2) * brightness }
            let c = SIMD4<Float>(channel(16), channel(8), channel(0), 1)
            rect(x + Float(col) * unit, y + Float(row) * unit, unit, unit, c)
        }
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
