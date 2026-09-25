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

    /// A crafting-table style panel: oak planks with grain, set in a dark walnut frame with iron nails.
    /// (Colours are linear, like everything the overlay draws.)
    mutating func woodPanel(_ x: Float, _ y: Float, _ w: Float, _ h: Float, scale s: Float) {
        let px = max(1, s.rounded())
        rect(x - 2 * px, y + 3 * px, w + 4 * px, h, SIMD4(0, 0, 0, 0.35))                      // drop shadow
        rect(x, y, w, h, SIMD4(0.045, 0.022, 0.008, 0.99))                                      // frame
        let border = 6 * px
        rect(x + px, y + px, w - 2 * px, px, SIMD4(0.14, 0.07, 0.03, 1))                        // frame highlight
        let ix = x + border, iy = y + border, iw = w - 2 * border, ih = h - 2 * border
        let plank = 28 * px
        var top = iy, row = 0
        while top < iy + ih {
            let ph = min(plank, iy + ih - top)
            let tone: SIMD4<Float> = row % 2 == 0 ? SIMD4(0.2, 0.1, 0.04, 0.98) : SIMD4(0.18, 0.088, 0.034, 0.98)
            rect(ix, top, iw, ph, tone)
            rect(ix, top, iw, px, SIMD4(0.3, 0.16, 0.07, 0.98))                                // lit edge
            if top + ph < iy + ih { rect(ix, top + ph - px, iw, px, SIMD4(0.05, 0.024, 0.01, 1)) }   // seam
            // Grain streaks, placed the same way every frame
            var gx = ix + Float((row * 37) % 50) * px
            var k = 0
            while gx < ix + iw - 24 * px {
                let len = Float(10 + (row * 13 + k * 7) % 16) * px
                rect(gx, top + ph * (0.35 + Float((k + row) % 3) * 0.15), len, px, SIMD4(0.13, 0.062, 0.024, 0.9))
                gx += Float(46 + (row * 11 + k * 17) % 30) * px
                k += 1
            }
            // A butt joint between two boards on alternating rows
            if row % 2 == 1 && iw > 120 * px {
                let jx = ix + iw * (row % 4 == 1 ? 0.38 : 0.64)
                rect(jx, top, px, ph, SIMD4(0.05, 0.024, 0.01, 1))
            }
            top += plank
            row += 1
        }
        rect(ix, iy, iw, px, SIMD4(0.02, 0.01, 0.004, 0.7))                                     // inner shadow
        rect(ix, iy, px, ih, SIMD4(0.02, 0.01, 0.004, 0.5))
        for (nx, ny) in [(x + 1.5 * px, y + 1.5 * px), (x + w - 4.5 * px, y + 1.5 * px), (x + 1.5 * px, y + h - 4.5 * px), (x + w - 4.5 * px, y + h - 4.5 * px)] {
            rect(nx, ny, 3 * px, 3 * px, SIMD4(0.22, 0.22, 0.25, 1))                           // iron nails
            rect(nx, ny, 1.5 * px, 1.5 * px, SIMD4(0.55, 0.55, 0.6, 1))
        }
    }

    /// An item slot sunk into the wood: dark inside, shadowed top-left and lit bottom-right.
    mutating func woodSlot(_ x: Float, _ y: Float, _ size: Float, scale s: Float, hovered: Bool = false, accent: Bool = false) {
        let px = max(1, s.rounded())
        rect(x, y, size, size, accent ? SIMD4(0.42, 0.22, 0.04, 1) : (hovered ? SIMD4(0.16, 0.085, 0.035, 1) : SIMD4(0.05, 0.026, 0.011, 0.97)))
        rect(x, y, size, 2 * px, SIMD4(0.012, 0.006, 0.002, 1))
        rect(x, y, 2 * px, size, SIMD4(0.012, 0.006, 0.002, 1))
        rect(x, y + size - px, size, px, SIMD4(0.32, 0.18, 0.08, 1))
        rect(x + size - px, y, px, size, SIMD4(0.32, 0.18, 0.08, 1))
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

    /// The hunger bar: ten drumsticks filling from the right, a gold rim while you still have saturation,
    /// shaking when you're starving and rippling after you eat.
    mutating func hungerBar(right: Float, y: Float, small: Float, hunger: Double, saturation: Double, eatFlash: Double, time: Double) {
        let unit = small * 7.6 / 9
        for i in 0..<10 {
            let x = right - Float(i + 1) * 8 * small
            let dy = Float(HungerIcon.offset(index: i, hunger: hunger, eatFlash: eatFlash, time: time)) * unit
            let glow = Float(max(0, eatFlash - Double(i) * 0.05)) * 0.35
            for (col, row, hex) in HungerIcon.pixels(fill: HungerIcon.fill(index: i, hunger: hunger),
                                                    saturated: HungerIcon.saturated(index: i, saturation: saturation)) {
                func channel(_ shift: UInt32) -> Float { min(1, pow(Float((hex >> shift) & 255) / 255, 2.2) * (1 + glow)) }
                rect(x + Float(col) * unit, y - small * 0.6 + Float(row) * unit + dy, unit, unit, SIMD4(channel(16), channel(8), channel(0), 1))
            }
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
