import AppKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Plays back a timed command script for automated end-to-end testing:
///
///     DinoCraft --world Test --script tests/break.txt
///
/// Commands (one per line, `#` starts a comment):
///   wait <seconds>            pause the script
///   wait-world                wait until the world has finished loading
///   look <yawDeg> <pitchDeg>  set the camera direction
///   press <action>            tap a bound action (attack, use, jump, …)
///   hold <action> <seconds>   hold an action down
///   select <1-9>              choose a hotbar slot
///   screenshot <path>         capture the next frame to a PNG
///   state                     log player position, target block and inventory
///   log <text>                write a line to the log
///   quit                      exit the game (saving the world)
final class ScriptRunner {
    private var commands: [[String]]
    private var index = 0
    private var wait = 0.0
    private var holds: [(InputBinding, Double)] = []

    init?(path: String) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            Log.error("Script not found: \(path)", category: "Script")
            return nil
        }
        commands = text.split(whereSeparator: \.isNewline).compactMap { line in
            let code = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let parts = code.split(separator: " ").map(String.init)
            return parts.isEmpty ? nil : parts
        }
        Log.info("Running script \(path) (\(commands.count) commands)", category: "Script")
    }

    var finished: Bool { index >= commands.count && holds.isEmpty }

    func update(dt: Double, engine e: GameEngine) {
        holds = holds.compactMap { binding, remaining in
            let left = remaining - dt
            if left <= 0 {
                e.input.inject(binding, down: false)
                return nil
            }
            return (binding, left)
        }
        if wait > 0 { wait -= dt; return }

        while index < commands.count {
            let cmd = commands[index]
            index += 1
            func arg(_ i: Int) -> String? { i < cmd.count ? cmd[i] : nil }
            func binding(_ name: String?) -> InputBinding? {
                guard let name, let action = GameAction(rawValue: name) else {
                    Log.warning("Script: unknown action '\(name ?? "")'", category: "Script")
                    return nil
                }
                return e.settings.binding(for: action)
            }

            switch cmd[0] {
            case "wait":
                wait = Double(arg(1) ?? "") ?? 1
                return
            case "wait-world":
                if e.session == nil || e.session!.isLoading {
                    index -= 1
                    return
                }
            case "look":
                guard let s = e.session else { break }
                s.player.yaw = (Double(arg(1) ?? "") ?? 0) * .pi / 180
                s.player.pitch = (Double(arg(2) ?? "") ?? 0) * .pi / 180
            case "press":
                if let b = binding(arg(1)) {
                    e.input.inject(b, down: true)
                    holds.append((b, 0.05))
                }
                return
            case "hold":
                if let b = binding(arg(1)) {
                    e.input.inject(b, down: true)
                    holds.append((b, Double(arg(2) ?? "") ?? 1))
                }
            case "give":
                if let s = e.session, let name = arg(1), let id = e.items.id(named: name) {
                    s.inventory.add(ItemStack(item: id, count: Int(arg(2) ?? "") ?? 1))
                } else {
                    Log.warning("Script: cannot give '\(arg(1) ?? "")'", category: "Script")
                }
            case "slot", "recipe":
                // Moves the mouse to a named rect of the open inventory screen (e.g. `slot inv9`, `slot grid0`, `slot out`, `recipe sticks`).
                let key = cmd[0] == "recipe" ? "recipe:\(arg(1) ?? "")" : (arg(1) ?? "")
                let rects = (e.topScreen as? InventoryScreen)?.slotRects ?? (e.topScreen as? CreativeInventoryScreen)?.slotRects ?? (e.topScreen as? ContainerScreen)?.slotRects ?? [:]
                if let r = rects[key] {
                    e.input.injectMouse(r.center * e.ui.scale)
                } else {
                    Log.warning("Script: no rect '\(key)' on \(String(describing: e.topScreen.map { type(of: $0) }))", category: "Script")
                }
            case "click":
                let button = arg(1) == "right" ? 1 : 0
                e.input.inject(.mouse(button), down: true)
                holds.append((.mouse(button), 0.05))
                return
            case "shift":
                e.input.injectModifiers(arg(1) == "off" ? [] : [.shift])
            case "screen":
                Log.info("Script: top screen = \(e.topScreen.map { String(describing: type(of: $0)) } ?? "none")", category: "Script")
            case "entities":
                if let s = e.session {
                    let summary = s.entities.items.map { "\(e.items[$0.stack.item]?.name ?? "?")x\($0.stack.count)" }.joined(separator: " ")
                    Log.info("Script: \(s.entities.items.count) item entities [\(summary)]", category: "Script")
                }
            case "spawn":
                if let s = e.session, let kind = arg(1).flatMap(MobKind.init(rawValue:)) {
                    let distance = Double(arg(2) ?? "") ?? 4
                    let look = s.player.lookDirection
                    let flat = simd_normalize(DVec3(look.x, 0, look.z))
                    let p = s.player.position + flat * distance
                    let y = s.world.findStandingY(Int(floor(p.x)), Int(floor(p.z)), near: Int(s.player.position.y)) ?? Int(s.player.position.y)
                    s.mobs.spawn(kind, at: DVec3(floor(p.x) + 0.5, Double(y), floor(p.z) + 0.5))
                    Log.info("Script: spawned \(kind.rawValue)", category: "Script")
                }
            case "dimension":
                if let s = e.session, let dim = arg(1).flatMap(WorldDimension.init(rawValue:)) {
                    s.changeDimension(to: dim, portal: dim == .overworld ? nil : dim.portalBlock, arrival: nil)
                }
            case "time":
                e.session?.debugSetTime(Double(arg(1) ?? "") ?? 0)
            case "kill":
                e.session?.takeDamage(1000, cause: "Script", knockback: nil)
            case "commands":
                e.session?.setCommandsAllowed(arg(1) != "off")
            case "mobs":
                if let s = e.session {
                    let list = s.mobs.mobs.map {
                        "\($0.species.kind.rawValue)(\(Int($0.health))hp @\(Int(simd_distance($0.position, s.player.position)))m" +
                            String(format: " y%.2f%@)", $0.position.y, $0.inLiquid ? " swimming" : "")
                    }
                    Log.info("Script: \(list.count) mobs [\(list.joined(separator: " "))]", category: "Script")
                }
            case "host":
                e.hostGame()
            case "chat":
                e.submitChat(cmd.dropFirst().joined(separator: " "))
            case "players":
                Log.info("Script: players [\(e.remotePlayers.map { "\($0.name)@\(Int($0.position.x)),\(Int($0.position.y)),\(Int($0.position.z)) hp\(Int($0.health))" }.joined(separator: " "))]", category: "Script")
            case "face-player":
                if let s = e.session, let target = e.remotePlayers.first {
                    let d = (target.position + DVec3(0, 1.2, 0)) - s.player.eyePosition
                    s.player.yaw = atan2(-d.x, -d.z)
                    s.player.pitch = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
                }
            case "set-block", "block", "look-at":
                // Block coordinates are relative to the cell the player stands in.
                guard let s = e.session, let dx = arg(1).flatMap({ Int($0) }), let dy = arg(2).flatMap({ Int($0) }), let dz = arg(3).flatMap({ Int($0) }) else { break }
                let p = BlockPos(Int(floor(s.player.position.x)) + dx, Int(floor(s.player.position.y)) + dy, Int(floor(s.player.position.z)) + dz)
                if cmd[0] == "set-block" {
                    if let id = arg(4).flatMap({ e.blocks.id(named: $0) }) { s.world.setBlock(p, id) }
                } else if cmd[0] == "block" {
                    Log.info("Script: block \(p) = \(e.blocks[s.world.block(p)]?.name ?? "?")", category: "Script")
                } else {
                    let d = DVec3(Double(p.x) + 0.5, Double(p.y) + 0.5, Double(p.z) + 0.5) - s.player.eyePosition
                    s.player.yaw = atan2(-d.x, -d.z)
                    s.player.pitch = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
                }
            case "containers":
                if let s = e.session {
                    for (pos, c) in s.containers.containers {
                        let list = c.slots.enumerated().compactMap { i, st in st.map { "\(i):\(e.items[$0.item]?.name ?? "?")x\($0.count)" } }
                        Log.info("Script: \(c.kind.rawValue)@\(pos) burn \(String(format: "%.1f", c.burnLeft)) cook \(String(format: "%.1f", c.cook)) [\(list.joined(separator: " "))]", category: "Script")
                    }
                }
            case "tp-player":
                if let s = e.session, let target = e.remotePlayers.first {
                    let p = target.position + DVec3(1.5, 0, 0)
                    let y = s.world.findStandingY(Int(floor(p.x)), Int(floor(p.z)), near: Int(target.position.y)) ?? Int(target.position.y)
                    s.player.teleport(to: DVec3(floor(p.x) + 0.5, Double(y), floor(p.z) + 0.5))
                }
            case "pack":
                let id = arg(1) ?? "dino"
                e.settingsStore.update { $0.texturePack = id }
            case "shader":
                let id = arg(1) ?? "off"
                let strength = Double(arg(2) ?? "") ?? 1
                e.settingsStore.update { $0.shaderPack = id; $0.shaderStrength = strength }
            case "aim-nearest":
                // aim-nearest <block name prefix> — looks at the closest matching block within 8 blocks
                guard let s = e.session, let prefix = arg(1) else { break }
                let bx = Int(floor(s.player.position.x)), by = Int(floor(s.player.position.y)), bz = Int(floor(s.player.position.z))
                var best: (BlockPos, Double)?
                for dy in -5...3 {
                    for dz in -8...8 {
                        for dx in -8...8 {
                            let p = BlockPos(bx + dx, by + dy, bz + dz)
                            guard let name = e.blocks[s.world.block(p)]?.name, name.hasPrefix(prefix) else { continue }
                            let c = DVec3(Double(p.x) + 0.5, Double(p.y) + 0.5, Double(p.z) + 0.5)
                            let dist = simd_distance(c, s.player.eyePosition)
                            if dist < (best?.1 ?? .infinity) { best = (p, dist) }
                        }
                    }
                }
                if let (p, _) = best {
                    let d = DVec3(Double(p.x) + 0.5, Double(p.y) + 0.5, Double(p.z) + 0.5) - s.player.eyePosition
                    s.player.yaw = atan2(-d.x, -d.z)
                    s.player.pitch = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
                    Log.info("Script: aiming at \(e.blocks[s.world.block(p)]?.name ?? "?") \(p)", category: "Script")
                } else {
                    Log.warning("Script: no '\(prefix)' block nearby", category: "Script")
                }
            case "villages":
                if let s = e.session, let generator = s.world.generator as? TerrainGenerator {
                    let list = generator.villages(near: Int(floor(s.player.position.x)), z: Int(floor(s.player.position.z)), radius: 1500)
                    Log.info("Script: villages \(list.prefix(5).map { "(\($0.x), \($0.y), \($0.z))" }.joined(separator: " "))", category: "Script")
                }
            case "tp-village":
                if let s = e.session, let generator = s.world.generator as? TerrainGenerator,
                   let v = generator.villages(near: Int(floor(s.player.position.x)), z: Int(floor(s.player.position.z)), radius: 3000).first {
                    s.player.teleport(to: DVec3(Double(v.x) + 6.5, Double(v.y + 1), Double(v.z) + 0.5))
                    Log.info("Script: teleported to village at \(v.x), \(v.y), \(v.z)", category: "Script")
                } else {
                    Log.warning("Script: no village found", category: "Script")
                }
            case "unstick":
                if let s = e.session {
                    let x = Int(floor(s.player.position.x)), z = Int(floor(s.player.position.z))
                    if let y = s.world.findStandingY(x, z, near: Int(floor(s.player.position.y)) + 4) {
                        s.player.teleport(to: DVec3(Double(x) + 0.5, Double(y), Double(z) + 0.5))
                    }
                }
            case "structures":
                if let s = e.session, let generator = s.world.generator as? TerrainGenerator {
                    let list = generator.structures(near: Int(floor(s.player.position.x)), z: Int(floor(s.player.position.z)), radius: 800)
                    Log.info("Script: structures \(list.prefix(8).map { "\($0.kind.rawValue)(\($0.x), \($0.y), \($0.z))" }.joined(separator: " "))", category: "Script")
                }
            case "tp-structure":
                if let s = e.session, let generator = s.world.generator as? TerrainGenerator, let kind = arg(1).flatMap({ StructureKind(rawValue: $0) }),
                   let target = generator.structures(near: Int(floor(s.player.position.x)), z: Int(floor(s.player.position.z)), radius: 3000).first(where: { $0.kind == kind }) {
                    let y = kind == .dungeon ? target.y : target.y + 1
                    s.player.teleport(to: DVec3(Double(target.x) + 0.5 + (kind == .dungeon ? 0 : 6), Double(y), Double(target.z) + 0.5))
                    Log.info("Script: teleported to \(kind.rawValue) at \(target.x), \(target.y), \(target.z)", category: "Script")
                } else {
                    Log.warning("Script: no \(arg(1) ?? "?") found", category: "Script")
                }
            case "clear-area":
                // clear-area <radius> <height> — flat grass floor with open air above, for screenshots
                if let s = e.session {
                    let r = Int(arg(1) ?? "") ?? 6, h = Int(arg(2) ?? "") ?? 6
                    let bx = Int(floor(s.player.position.x)), by = Int(floor(s.player.position.y)), bz = Int(floor(s.player.position.z))
                    for dz in -r...r {
                        for dx in -r...r {
                            s.world.setBlock(BlockPos(bx + dx, by - 1, bz + dz), Blocks.grass)
                            for dy in 0..<h { s.world.setBlock(BlockPos(bx + dx, by + dy, bz + dz), Blocks.air) }
                        }
                    }
                }
            case "advancements":
                if let s = e.session {
                    let list = AdvancementTracker.definitions.filter { s.advancements.isUnlocked($0.id) }.map { $0.title }
                    Log.info("Script: \(list.count) advancements [\(list.joined(separator: ", "))]", category: "Script")
                }
            case "net-probe":
                // Read-only: finds the router and asks for the public address; changes nothing.
                e.portMapper.probe { Log.info("Script: net-probe \($0)", category: "Script") }
            case "face-mob":
                if let s = e.session, let kind = arg(1).flatMap({ MobKind(rawValue: $0) }),
                   let m = s.mobs.mobs.filter({ $0.species.kind == kind }).min(by: { simd_distance($0.position, s.player.position) < simd_distance($1.position, s.player.position) }) {
                    let d = (m.position + DVec3(0, m.species.height * 0.6, 0)) - s.player.eyePosition
                    s.player.yaw = atan2(-d.x, -d.z)
                    s.player.pitch = atan2(d.y, sqrt(d.x * d.x + d.z * d.z))
                }
            case "trade":
                if let screen = e.topScreen as? TradeScreen {
                    let ok = screen.perform(Int(arg(1) ?? "") ?? 0, e)
                    Log.info("Script: trade \(arg(1) ?? "0") with \(VillagerProfession.of(screen.mob).name) \(ok ? "succeeded" : "failed")", category: "Script")
                } else {
                    Log.warning("Script: no trade screen open", category: "Script")
                }
            case "tp-biome":
                // tp-biome <command name> — jumps to the nearest biome of that kind (for screenshots)
                if let s = e.session, let generator = s.world.generator as? TerrainGenerator,
                   let biome = Commands.overworldBiomes.first(where: { Commands.commandName($0) == arg(1) }),
                   let spot = Commands.locateBiome(biome, x: Int(floor(s.player.position.x)), z: Int(floor(s.player.position.z)), generator: generator) {
                    s.player.teleport(to: DVec3(Double(spot.x) + 0.5, Double(spot.y + 12), Double(spot.z) + 0.5))
                    Log.info("Script: teleported to \(biome.displayName) at \(spot.x), \(spot.y), \(spot.z)", category: "Script")
                } else {
                    Log.warning("Script: couldn't find biome \(arg(1) ?? "?")", category: "Script")
                }
            case "suggest":
                // suggest <partial command> — logs what the chat box would offer (use _ for a trailing space)
                let typed = cmd.dropFirst().joined(separator: " ").replacingOccurrences(of: "_$", with: " ", options: .regularExpression)
                let list = Commands.suggestions(for: typed, engine: e).map { $0.label }
                Log.info("Script: suggestions for \"\(typed)\" → \(list.joined(separator: ", ")) · usage: \(Commands.usage(for: typed) ?? "-")", category: "Script")
            case "select":
                e.session?.inventory.selected = max(0, (Int(arg(1) ?? "") ?? 1) - 1)
            case "select-item":
                if let s = e.session, let id = arg(1).flatMap({ e.items.id(named: $0) }),
                   let index = (0..<Inventory.hotbarCount).first(where: { s.inventory.slots[$0]?.item == id }) {
                    s.inventory.selected = index
                } else {
                    Log.warning("Script: '\(arg(1) ?? "")' is not on the hotbar", category: "Script")
                }
            case "screenshot":
                if let path = arg(1) { e.requestScreenshot(URL(fileURLWithPath: path)) }
            case "state":
                guard let s = e.session else { Log.info("Script state: no session", category: "Script"); break }
                let p = s.player.position
                let target = s.target.map { "\(e.blocks[$0.id]?.name ?? "?")@\($0.block)" } ?? "none"
                let inv = s.inventory.slots.enumerated().compactMap { i, st in
                    st.map { "\(i + 1):\(e.items[$0.item]?.name ?? "?")x\($0.count)" }
                }.joined(separator: " ")
                let worn = s.armor.enumerated().compactMap { i, st in st.map { "\(i):\(e.items[$0.item]?.name ?? "?")/\($0.damage)" } }.joined(separator: " ")
                Log.info(String(format: "Script state: pos %.2f %.2f %.2f · onGround %@ · target %@ · health %.1f · armor %d [%@] · time %.0f %@ · weather %@ · inventory [%@]",
                                p.x, p.y, p.z, s.player.onGround ? "yes" : "no", target, s.health, s.armorPoints, worn,
                                s.worldTime, SkyModel.periodName(worldTime: s.worldTime), s.weather.kind.rawValue, inv), category: "Script")
            case "log":
                Log.info("Script: " + cmd.dropFirst().joined(separator: " "), category: "Script")
            case "quit":
                Log.info("Script finished; quitting", category: "Script")
                NSApp.terminate(nil)
                return
            default:
                Log.warning("Script: unknown command '\(cmd[0])'", category: "Script")
            }
        }
    }
}
