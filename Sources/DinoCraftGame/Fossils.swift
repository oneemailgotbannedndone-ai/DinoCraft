import Foundation

/// Fossils dug out of fossil deposits (at dig sites) and shown off in display cases.
enum Fossils {
    static let deposit = "fossil_deposit"
    /// In the same order as `Blocks.displayCases`.
    static let all = ["fossil_skull", "fossil_claw", "fossil_rib", "fossil_tooth", "fossil_fern"]
    /// How often each turns up when you dig: teeth are common, skulls rare.
    private static let weights: [Double] = [0.1, 0.22, 0.2, 0.3, 0.18]

    static func roll() -> String {
        var r = Double.random(in: 0..<weights.reduce(0, +))
        for (i, w) in weights.enumerated() {
            if r < w { return all[i] }
            r -= w
        }
        return all[3]
    }
}
