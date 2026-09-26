import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Amber circuits: levers, buttons and pressure plates power amber dust, which carries the signal up to 15
/// blocks to lamps, pistons and doors. Only the world's owner (or host) runs them; everyone sees the blocks change.
final class CircuitManager {
    struct IDs {
        let dustOff, dustOn, leverOff, leverOn, buttonOff, buttonOn, plateOff, plateOn, lampOff, lampOn: BlockID
        /// Pistons by facing: north, east, south, west, up, down.
        let pistons: [BlockID], extended: [BlockID], heads: [BlockID]

        init?(_ blocks: BlockRegistry) {
            func id(_ n: String) -> BlockID? { blocks.id(named: n) }
            let facings = ["north", "east", "south", "west", "up", "down"]
            guard let a = id("amber_dust"), let b = id("amber_dust_on"), let c = id("lever"), let d = id("lever_on"),
                  let e = id("amber_button"), let f = id("amber_button_on"), let g = id("pressure_plate"), let h = id("pressure_plate_on"),
                  let i = id("amber_lamp"), let j = id("amber_lamp_on") else { return nil }
            let p = facings.compactMap { id("piston_\($0)") }, x = facings.compactMap { id("piston_extended_\($0)") }
            let hd = facings.compactMap { id("piston_head_\($0)") }
            guard p.count == 6, x.count == 6, hd.count == 6 else { return nil }
            dustOff = a; dustOn = b; leverOff = c; leverOn = d; buttonOff = e; buttonOn = f; plateOff = g; plateOn = h
            lampOff = i; lampOn = j; pistons = p; extended = x; heads = hd
        }
    }

    static let faces: [BlockFace] = [.north, .east, .south, .west, .up, .down]
    static let maxStrength = 15
    /// Most blocks a piston can shove at once.
    static let pushLimit = 12

    let ids: IDs?
    private var tracked: Set<BlockID> = []
    /// Every circuit block in this dimension.
    private(set) var positions: Set<BlockPos> = []
    private var buttonTimers: [BlockPos: Double] = [:]
    /// Doors the circuits opened (closed again when the power goes).
    private var poweredDoors: Set<BlockPos> = []
    private(set) var dirty = true
    private var plateTimer = 0.0
    /// Changes we make ourselves come back through the block hook; don't recount them as the player's.
    private var applying = false

    init(blocks: BlockRegistry) {
        ids = IDs(blocks)
        if let ids {
            tracked = [ids.dustOff, ids.dustOn, ids.leverOff, ids.leverOn, ids.buttonOff, ids.buttonOn, ids.plateOff, ids.plateOn,
                       ids.lampOff, ids.lampOn]
            tracked.formUnion(ids.pistons)
            tracked.formUnion(ids.extended)
        }
    }

    func isCircuit(_ id: BlockID) -> Bool { tracked.contains(id) }

    /// Called for every block change in the world.
    func noteChange(_ pos: BlockPos, _ id: BlockID) {
        if tracked.contains(id) {
            positions.insert(pos)
            // A button pressed by anyone (a friend who joined, too) pops back up after a second.
            if id == ids?.buttonOn && buttonTimers[pos] == nil { buttonTimers[pos] = 1.0 }
            dirty = true
        } else if positions.remove(pos) != nil {
            buttonTimers[pos] = nil
            dirty = true
        } else if !applying {
            // Something next to a circuit changed (a block in front of a piston, a door placed by a plate).
            for f in CircuitManager.faces where positions.contains(pos.offset(f)) { dirty = true; break }
        }
    }

    func pressButton(_ pos: BlockPos) { buttonTimers[pos] = 1.0 }

    func clear() {
        positions.removeAll()
        buttonTimers.removeAll()
        poweredDoors.removeAll()
        dirty = true
    }

    // MARK: Saving

    private struct Saved: Codable { var p: [[Int32]]; var doors: [[Int32]]? }

    func save(to url: URL) {
        let saved = Saved(p: positions.map { [$0.x, $0.y, $0.z] }, doors: poweredDoors.isEmpty ? nil : poweredDoors.map { [$0.x, $0.y, $0.z] })
        do { try AtomicFile.write(JSONEncoder().encode(saved), to: url) } catch { Log.error("Failed to save circuits: \(error)", category: "Save") }
    }

    func load(from url: URL) {
        clear()
        guard let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        for p in saved.p where p.count == 3 { positions.insert(BlockPos(p[0], p[1], p[2])) }
        for p in saved.doors ?? [] where p.count == 3 { poweredDoors.insert(BlockPos(p[0], p[1], p[2])) }
    }

    // MARK: Simulation

    func update(dt: Double, session s: GameSession) {
        guard let ids, !positions.isEmpty || !poweredDoors.isEmpty else { return }
        // Buttons pop back up after a second.
        for (pos, t) in buttonTimers {
            let left = t - dt
            if left <= 0 {
                buttonTimers[pos] = nil
                if s.world.block(pos) == ids.buttonOn { set(pos, ids.buttonOff, s) ; s.onSound?("ui_click", 0.4, 0.8) }
            } else {
                buttonTimers[pos] = left
            }
        }
        // Pressure plates notice anyone standing on them.
        plateTimer -= dt
        if plateTimer <= 0 {
            plateTimer = 0.1
            for pos in positions {
                let id = s.world.block(pos)
                guard id == ids.plateOff || id == ids.plateOn else { continue }
                let pressed = CircuitManager.somethingOn(pos, s)
                if pressed != (id == ids.plateOn) {
                    set(pos, pressed ? ids.plateOn : ids.plateOff, s)
                    s.onSound?("ui_click", 0.35, pressed ? 0.7 : 0.6)
                }
            }
        }
        guard dirty else { return }
        dirty = false
        simulate(ids, s)
    }

    private static func somethingOn(_ pos: BlockPos, _ s: GameSession) -> Bool {
        let box = DBox(min: DVec3(Double(pos.x) + 0.06, Double(pos.y), Double(pos.z) + 0.06),
                       max: DVec3(Double(pos.x) + 0.94, Double(pos.y) + 0.25, Double(pos.z) + 0.94))
        if !s.spectator && s.player.box.intersects(box) { return true }
        if s.mobs.mobs.contains(where: { !$0.removed && !$0.isDying && $0.box.intersects(box) }) { return true }
        for p in s.network?.remotePlayers ?? [] where !p.dead {
            let hw = 0.3
            let pb = DBox(min: p.position - DVec3(hw, 0, hw), max: p.position + DVec3(hw, 1.8, hw))
            if pb.intersects(box) { return true }
        }
        return false
    }

    private func set(_ pos: BlockPos, _ id: BlockID, _ s: GameSession) {
        applying = true
        s.naturalPlace(pos, id)
        applying = false
    }

    /// Works out which dust is lit (and how strongly), then switches lamps, pistons and doors to match.
    private func simulate(_ ids: IDs, _ s: GameSession) {
        let world = s.world
        var sources: [BlockPos] = []
        var dust: Set<BlockPos> = []
        for pos in positions {
            let id = world.block(pos)
            switch id {
            case ids.leverOn, ids.buttonOn, ids.plateOn: sources.append(pos)
            case ids.dustOff, ids.dustOn: dust.insert(pos)
            default: break
            }
        }
        // Spread the signal through the dust, one weaker per block, climbing up or down a block where it has to.
        var strength: [BlockPos: Int] = [:]
        var queue: [(BlockPos, Int)] = []
        func dustNeighbours(_ p: BlockPos) -> [BlockPos] {
            var out: [BlockPos] = []
            for f in [BlockFace.north, .east, .south, .west] {
                let n = p.offset(f)
                out.append(n)
                out.append(n.offset(.up))
                out.append(n.offset(.down))
            }
            out.append(p.offset(.up))
            out.append(p.offset(.down))
            return out
        }
        for src in sources {
            for f in CircuitManager.faces {
                let n = src.offset(f)
                // Also the dust on the block a source sits on (a lever on top of a block with dust around it).
                for c in [n, n.offset(.down)] where dust.contains(c) && (strength[c] ?? 0) < CircuitManager.maxStrength {
                    strength[c] = CircuitManager.maxStrength
                    queue.append((c, CircuitManager.maxStrength))
                }
            }
        }
        var head = 0
        while head < queue.count {
            let (p, st) = queue[head]
            head += 1
            guard st > 1 else { continue }
            for n in dustNeighbours(p) where dust.contains(n) && (strength[n] ?? 0) < st - 1 {
                strength[n] = st - 1
                queue.append((n, st - 1))
            }
        }
        // Everything next to a source or lit dust is powered.
        var powered: Set<BlockPos> = []
        for p in sources { powered.insert(p) }
        for (p, st) in strength where st > 0 { powered.insert(p) }
        func isPowered(_ p: BlockPos) -> Bool {
            if powered.contains(p) { return true }
            return CircuitManager.faces.contains { powered.contains(p.offset($0)) }
        }

        for p in dust {
            let lit = (strength[p] ?? 0) > 0
            let id = world.block(p)
            if lit && id == ids.dustOff { set(p, ids.dustOn, s) }
            if !lit && id == ids.dustOn { set(p, ids.dustOff, s) }
        }
        for p in positions {
            let id = world.block(p)
            if id == ids.lampOff || id == ids.lampOn {
                let on = isPowered(p)
                if on != (id == ids.lampOn) { set(p, on ? ids.lampOn : ids.lampOff, s) }
            } else if let facing = ids.pistons.firstIndex(of: id) {
                if isPowered(p) { extend(p, facing: facing, ids, s) }
            } else if let facing = ids.extended.firstIndex(of: id) {
                // Retract when the power goes, or when the head was broken off.
                let head = p.offset(CircuitManager.faces[facing])
                if !isPowered(p) || world.block(head) != ids.heads[facing] { retract(p, facing: facing, ids, s) }
            }
        }
        // Doors: open next to power, close again when it goes.
        var doors: Set<BlockPos> = []
        for p in powered {
            for f in CircuitManager.faces {
                let n = p.offset(f)
                if let st = s.variants.doorState(world.block(n)) { doors.insert(st.upper ? n.offset(.down) : n) }
            }
        }
        for d in doors.subtracting(poweredDoors) { s.setDoor(at: d, open: true) }
        for d in poweredDoors.subtracting(doors) { s.setDoor(at: d, open: false) }
        poweredDoors = doors
    }

    // MARK: Pistons

    private func extend(_ p: BlockPos, facing: Int, _ ids: IDs, _ s: GameSession) {
        let world = s.world
        let dir = CircuitManager.faces[facing]
        // Find the line of blocks to push, up to the first gap.
        var line: [BlockPos] = []
        var cursor = p.offset(dir)
        while true {
            let id = world.block(cursor)
            if id == Blocks.air || s.blocks[id]?.replaceable == true || s.blocks.isWet[Int(id)] && !s.blocks.isSolid[Int(id)] { break }
            guard line.count < CircuitManager.pushLimit, movable(id, ids, s), cursor.y > 0, cursor.y < Int32(WorldConst.height - 1) else { return }
            line.append(cursor)
            cursor = cursor.offset(dir)
        }
        applying = true
        // Move from the far end back, so nothing is overwritten.
        for b in line.reversed() {
            let id = world.block(b)
            s.naturalPlace(b.offset(dir), id)
        }
        s.naturalPlace(p.offset(dir), ids.heads[facing])
        s.naturalPlace(p, ids.extended[facing])
        applying = false
        positions.remove(p)
        positions.insert(p)
        s.onSound?("place_wood", 0.6, 0.7)
        Log.info("Piston at \(p) pushed \(line.count) block\(line.count == 1 ? "" : "s")", category: "Game")
        dirty = true
    }

    private func retract(_ p: BlockPos, facing: Int, _ ids: IDs, _ s: GameSession) {
        let head = p.offset(CircuitManager.faces[facing])
        applying = true
        if s.world.block(head) == ids.heads[facing] { s.naturalPlace(head, Blocks.air) }
        s.naturalPlace(p, ids.pistons[facing])
        applying = false
        s.onSound?("place_wood", 0.5, 0.55)
        dirty = true
    }

    /// Pistons won't move bedrock, obsidian, containers, portals, other pistons' parts or anything with
    /// no hardness limit.
    private func movable(_ id: BlockID, _ ids: IDs, _ s: GameSession) -> Bool {
        guard let info = s.blocks[id], info.isBreakable else { return false }
        if id == Blocks.bedrock || id == Blocks.obsidian || s.variants.containerKind(id) != nil { return false }
        if s.variants.doorState(id) != nil { return false }
        if ids.extended.contains(id) || ids.heads.contains(id) { return false }
        if WorldDimension.forPortal(id) != nil { return false }
        return true
    }
}

extension GameSession {
    /// Opens or closes both halves of a door (for circuits).
    func setDoor(at lower: BlockPos, open: Bool) {
        guard let st = variants.doorState(world.block(lower)), st.open != open else { return }
        let top = lower.offset(.up)
        if let l = variants.door(upper: false, open: open, facing: st.facing) { naturalPlace(lower, l) }
        if variants.doorState(world.block(top)) != nil, let u = variants.door(upper: true, open: open, facing: st.facing) { naturalPlace(top, u) }
        onSound?(open ? "ui_open" : "ui_close", 0.6, 0.75)
    }

    /// Right-clicking a lever or button. Returns true when the click was used.
    func useCircuitBlock(_ pos: BlockPos, id: BlockID) -> Bool {
        guard let ids = circuits.ids else { return false }
        switch id {
        case ids.leverOff, ids.leverOn:
            naturalPlace(pos, id == ids.leverOff ? ids.leverOn : ids.leverOff)
            onSound?("ui_click", 0.6, id == ids.leverOff ? 0.9 : 0.7)
            swing()
            advancements.record("circuit", "lever")
            return true
        case ids.buttonOff:
            naturalPlace(pos, ids.buttonOn)
            circuits.pressButton(pos)
            onSound?("ui_click", 0.6, 1.1)
            swing()
            return true
        case ids.buttonOn:
            return true
        default:
            return false
        }
    }

    /// Which piston to place for where you're looking: pistons face you, like the furnace, or up/down when
    /// you look steeply.
    func pistonVariant(_ family: [BlockFace: BlockID], towardPlayer: BlockFace) -> BlockID? {
        guard let ids = circuits.ids else { return family[towardPlayer] }
        if player.pitch < -0.9 { return ids.pistons[4] }     // looking down at it from above: it faces up at you
        if player.pitch > 0.9 { return ids.pistons[5] }
        return family[towardPlayer]
    }
}
