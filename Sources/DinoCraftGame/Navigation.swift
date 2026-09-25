import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Where you last died, shown as a red X on the minimap until you get back there.
struct DeathSpot {
    var position: DVec3
    var dimension: WorldDimension
}

extension GameSession {
    /// Clears the death marker once you've made it back.
    func updateNavigation(_ dt: Double) {
        guard !isDead, let spot = deathSpot, spot.dimension == dimension else { return }
        if simd_distance(spot.position, player.position) < 3 {
            deathSpot = nil
            onToast?("You made it back to where you fell.")
        }
    }
}

// MARK: - Minimap

/// A top-down map of the blocks around you, north up, one cell per block. Each renderer draws
/// `cells` as coloured squares and the markers from `markers(for:)` on top.
final class Minimap {
    /// Blocks from the centre to the edge of the map.
    static let radius = 48
    static let size = radius * 2 + 1

    /// sRGB hex per cell, row by row from the north-west corner; 0 means not loaded yet.
    private(set) var cells = [UInt32](repeating: 0, count: Minimap.size * Minimap.size)
    private(set) var centerX = 0, centerZ = 0
    private(set) var caveMode = false
    private var builtAt = -100.0
    private var lastCenter = (Int.min, Int.min)
    private var blockColors: [UInt32]?

    enum MarkerKind { case you, death, player, pet }

    struct Marker {
        /// Offset from the map centre in blocks (east, south), clamped to the edge when far away.
        var dx: Float, dz: Float
        var color: UInt32
        var kind: MarkerKind
        var label: String
        var clamped: Bool
    }

    /// Redraws the map when you've moved a block, and every half second for changes around you.
    func refresh(_ s: GameSession) {
        let cx = Int(floor(s.player.position.x)), cz = Int(floor(s.player.position.z))
        guard abs(s.clock - builtAt) > 0.5 || cx != lastCenter.0 || cz != lastCenter.1 else { return }
        builtAt = s.clock
        lastCenter = (cx, cz)
        rebuild(s, cx: cx, cz: cz)
    }

    private func rebuild(_ s: GameSession, cx: Int, cz: Int) {
        let world = s.world
        let reg = world.registry
        if blockColors == nil { blockColors = Minimap.loadColors(reg) }
        let colors = blockColors!
        centerX = cx; centerZ = cz
        let r = Minimap.radius, n = Minimap.size
        let py = Int(floor(s.player.position.y))
        // Underground (or in the Underworld, under its roof), map the cave floor around you instead.
        let surface = columnTop(world, cx, cz) ?? py
        caveMode = s.dimension == .underworld || surface > py + 6
        var heights = [Int](repeating: Int.min, count: n * n)
        for j in 0..<n {
            let z = cz - r + j
            for i in 0..<n {
                let x = cx - r + i
                let k = j * n + i
                guard world.isLoaded(x, z) else { cells[k] = 0; continue }
                var y: Int?
                if caveMode {
                    // The first floor under air, searching down from just above your head.
                    var yy = py + 2
                    var sawAir = false
                    while yy > py - 24 {
                        let id = world.block(x, yy, z)
                        if reg.isSolid[Int(id)] || reg.isWet[Int(id)] {
                            if sawAir { y = yy; break }
                        } else {
                            sawAir = true
                        }
                        yy -= 1
                    }
                } else {
                    y = columnTop(world, x, z)
                }
                guard let top = y else { cells[k] = 0x101010; continue }
                heights[k] = top
                let id = world.block(x, top, z)
                var color: UInt32
                if reg.isWet[Int(id)] && !reg.isSolid[Int(id)] {
                    // Water: deeper is darker.
                    var depth = 0
                    while depth < 12 && reg.isWet[Int(world.block(x, top - depth - 1, z))] { depth += 1 }
                    color = Minimap.shade(0x3A74D0, 1.15 - Double(depth) * 0.05)
                } else {
                    color = colors[Int(id)]
                }
                cells[k] = color
            }
        }
        // Relief: slopes facing north-west catch the light.
        for j in 1..<n {
            for i in 1..<n {
                let k = j * n + i
                let h = heights[k], north = heights[k - n], west = heights[k - 1]
                guard h != Int.min, north != Int.min, west != Int.min, cells[k] != 0 else { continue }
                let slope = (h - north) + (h - west)
                if slope != 0 { cells[k] = Minimap.shade(cells[k], 1 + Double(max(-3, min(3, slope))) * 0.07) }
            }
        }
    }

    /// The highest block worth drawing in a column (skipping flowers, grass and torches).
    private func columnTop(_ world: World, _ x: Int, _ z: Int) -> Int? {
        guard let slot = world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4))) else { return nil }
        let reg = world.registry
        var y = Int(slot.chunk.heightMap[(z & 15) * 16 + (x & 15)]) - 1
        var steps = 0
        while y > 0 && steps < 8 {
            let id = world.block(x, y, z)
            if reg.isSolid[Int(id)] || reg.isWet[Int(id)] { return y }
            y -= 1
            steps += 1
        }
        return y > 0 ? y : nil
    }

    /// Markers for you, where you died, friends and your tamed creatures, for a map
    /// showing `radius` blocks around you.
    func markers(for s: GameSession, radius: Int = Minimap.radius) -> [Marker] {
        let r = Float(radius)
        let origin = s.player.position
        func place(_ p: DVec3, _ color: UInt32, _ kind: MarkerKind, _ label: String) -> Marker {
            var dx = Float(p.x - origin.x), dz = Float(p.z - origin.z)
            let far = max(abs(dx), abs(dz))
            let clamped = far > r - 1
            if clamped { dx *= (r - 1) / far; dz *= (r - 1) / far }
            return Marker(dx: dx, dz: dz, color: color, kind: kind, label: label, clamped: clamped)
        }
        var out: [Marker] = []
        for m in s.mobs.mobs where m.isTamed && !m.isDying && simd_distance(m.position, origin) < Double(r) {
            out.append(place(m.position, 0x8BE07A, .pet, m.petName ?? m.species.displayName))
        }
        for p in s.network?.remotePlayers ?? [] where !p.dead {
            out.append(place(p.position, 0xFFFFFF, .player, p.name))
        }
        if let spot = s.deathSpot, spot.dimension == s.dimension {
            out.append(place(spot.position, 0xE53935, .death, "Where you fell"))
        }
        out.append(Marker(dx: 0, dz: 0, color: 0xFFFFFF, kind: .you, label: "", clamped: false))
        return out
    }

    // MARK: Colours

    static func shade(_ hex: UInt32, _ k: Double) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 { UInt32(max(0, min(255, Double((hex >> shift) & 255) * k))) }
        return max(1, ch(16) << 16 | ch(8) << 8 | ch(0))
    }

    /// Each block's colour: the average of its top texture.
    private static func loadColors(_ reg: BlockRegistry) -> [UInt32] {
        var out = [UInt32](repeating: 0x808080, count: 256)
        var cache: [String: UInt32] = [:]
        for b in reg.all {
            let name = b.faceTextureNames[BlockFace.up.rawValue]
            if let c = cache[name] { out[Int(b.id)] = c; continue }
            var color: UInt32 = 0x808080
            if let data = try? ResourceLocator.data("Textures/blocks/\(name).png"), let image = try? PNG.decode(data) {
                var r = 0.0, g = 0.0, bl = 0.0, count = 0.0
                for p in 0..<(image.width * image.height) where image.rgba[p * 4 + 3] > 127 {
                    r += Double(image.rgba[p * 4]); g += Double(image.rgba[p * 4 + 1]); bl += Double(image.rgba[p * 4 + 2])
                    count += 1
                }
                if count > 0 { color = UInt32(r / count) << 16 | UInt32(g / count) << 8 | UInt32(bl / count) }
            }
            cache[name] = max(1, color)
            out[Int(b.id)] = max(1, color)
        }
        return out
    }
}
