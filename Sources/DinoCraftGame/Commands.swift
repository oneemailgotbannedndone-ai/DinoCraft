import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

struct CommandSuggestion {
    let label: String
    let detail: String?
    let completion: String
}

/// Minecraft-style chat commands (`/give`, `/tp`, `/time set night`, …) with
/// tab suggestions and autocorrect for mistyped commands and names.
///
/// Commands work in single-player and for the host of a multiplayer game.
/// Friends who joined can use the read-only ones. Hardcore worlds keep
/// commands off (except the read-only ones) so the challenge stays fair.
enum Commands {
    enum Arg {
        case items, blocks, creatures, biomes, command, coordinate, number, text
        case itemsOrPlayers, countOrItem, coordinateOrPlayer, players
        case choices([String])
    }

    struct Spec {
        let name: String
        let aliases: [String]
        let usage: String
        let help: String
        let args: [Arg]
        let readOnly: Bool

        init(_ name: String, _ usage: String, _ help: String, args: [Arg] = [], aliases: [String] = [], readOnly: Bool = false) {
            self.name = name; self.usage = usage; self.help = help; self.args = args; self.aliases = aliases; self.readOnly = readOnly
        }
    }

    static let gameRules = ["keepInventory", "doDaylightCycle", "doMobSpawning", "doWeatherCycle"]
    private static let coord3: [Arg] = [.coordinate, .coordinate, .coordinate]

    static let specs: [Spec] = [
        Spec("help", "/help [command]", "List commands, or explain one", args: [.command], aliases: ["?"], readOnly: true),
        Spec("give", "/give [player] <item> [count]", "Give items, e.g. /give diamond 5", args: [.itemsOrPlayers, .countOrItem, .number]),
        Spec("summon", "/summon <creature> [count | x y z]", "Spawn creatures, e.g. /summon rex 3", args: [.creatures] + coord3, aliases: ["spawn"]),
        Spec("tp", "/tp <x> <y> <z> | /tp <player>", "Teleport; ~ means your position, e.g. /tp ~ ~10 ~", args: [.coordinateOrPlayer, .coordinate, .coordinate], aliases: ["teleport"]),
        Spec("back", "/back", "Return to where you were before your last teleport or death"),
        Spec("home", "/home", "Teleport to your home (or spawn if you haven't set one)"),
        Spec("sethome", "/sethome", "Make this spot your home"),
        Spec("spawnpoint", "/spawnpoint", "Respawn here from now on"),
        Spec("time", "/time set <day|noon|sunset|night|midnight|number>", "Change the time of day",
             args: [.choices(["set", "add"]), .choices(["day", "noon", "sunset", "night", "midnight"])]),
        Spec("day", "/day", "Jump to morning"),
        Spec("night", "/night", "Jump to nightfall"),
        Spec("weather", "/weather <clear|rain|thunder|storm> [seconds]", "Change the weather", args: [.choices(["clear", "rain", "thunder", "storm"]), .number]),
        Spec("event", "/event <eruption|meteors>", "Start a volcano eruption or a meteor shower", args: [.choices(["eruption", "meteors"])]),
        Spec("gamemode", "/gamemode <survival|creative>", "Switch game mode", args: [.choices(["survival", "creative"])], aliases: ["gm"]),
        Spec("difficulty", "/difficulty <peaceful|easy|normal|hard>", "Change difficulty", args: [.choices(Difficulty.allCases.map { $0.rawValue })]),
        Spec("gamerule", "/gamerule <rule> [true|false]", "Show or change a world rule", args: [.choices(gameRules), .choices(["true", "false"])]),
        Spec("heal", "/heal", "Refill health and hunger", aliases: ["feed"]),
        Spec("clear", "/clear", "Empty your inventory"),
        Spec("repair", "/repair [all]", "Fix the tool in your hand (or every tool)", args: [.choices(["all"])]),
        Spec("fly", "/fly [on|off]", "Let yourself fly in Survival (double-tap jump)", args: [.choices(["on", "off"])]),
        Spec("god", "/god [on|off]", "Take no damage", args: [.choices(["on", "off"])]),
        Spec("kill", "/kill [me|creatures|hostile|items]", "Defeat yourself, or clear creatures or dropped items",
             args: [.choices(["me", "creatures", "hostile", "items"])]),
        Spec("setblock", "/setblock <x> <y> <z> <block>", "Place a block", args: coord3 + [.blocks]),
        Spec("fill", "/fill <x1> <y1> <z1> <x2> <y2> <z2> <block> [replace <block>]", "Fill a box (air clears)",
             args: coord3 + coord3 + [.blocks, .choices(["replace"]), .blocks]),
        Spec("locate", "/locate <village|dungeon|ruin|desert_ruin|dig_site|volcano|biome> [biome]", "Find the nearest structure or biome",
             args: [.choices(["village", "dungeon", "ruin", "desert_ruin", "dig_site", "volcano", "biome"]), .biomes], readOnly: true),
        Spec("biome", "/biome", "Show which biome you're in", readOnly: true),
        Spec("coords", "/coords", "Show your position and facing", aliases: ["pos"], readOnly: true),
        Spec("list", "/list", "Show who's playing", readOnly: true),
        Spec("dimension", "/dimension <overworld|underworld|skylands|toonland>", "Travel to a dimension", args: [.choices(["overworld", "underworld", "skylands", "toonland"])]),
        Spec("seed", "/seed", "Show the world seed", readOnly: true),
        Spec("say", "/say <message>", "Announce a message", args: [.text]),
        Spec("msg", "/msg <player> <message>", "Send a private message to one player", args: [.players, .text],
             aliases: ["tell", "w", "whisper"], readOnly: true),
        Spec("name", "/name <name>", "Name the tamed creature you're looking at", args: [.text], aliases: ["rename"], readOnly: true),
    ]

    static func spec(_ name: String) -> Spec? {
        let key = name.lowercased()
        return specs.first { $0.name == key || $0.aliases.contains(key) }
    }

    private static var allNames: [String] { specs.flatMap { [$0.name] + $0.aliases } }

    // MARK: Running

    static func run(_ input: String, engine e: CommandHost) {
        let text = input.trimmingCharacters(in: .whitespaces)
        let args = text.dropFirst().split(separator: " ").map(String.init)
        guard var name = args.first?.lowercased(), let s = e.session else { return }
        func reply(_ message: String) { e.addChat(from: "", text: message) }
        Log.info("Command: \(text)", category: "Command")
        e.addChat(from: "", text: "> \(text)")

        if spec(name) == nil {
            guard let fixed = closest(name, in: allNames) else {
                return reply("Unknown command /\(name). Type /help for the list.")
            }
            reply("Autocorrected /\(name) → /\(fixed)")
            name = fixed
        }
        guard let command = spec(name) else { return }
        name = command.name

        if !command.readOnly {
            if e.isClient { return reply("Only the host can use /\(name).") }
            if s.meta.isHardcore { return reply("Commands are turned off in Hardcore worlds.") }
            if !s.meta.commandsAllowed { return reply("Commands are turned off in this world. Turn them on from the pause menu.") }
        }

        let rest = Array(args.dropFirst())
        func teleport(_ p: DVec3) {
            s.lastPosition = s.player.position
            s.player.teleport(to: DVec3(p.x, max(1, min(Double(WorldConst.height - 2), p.y)), p.z))
        }
        func choice(_ index: Int, _ options: [String]) -> String? {
            guard index < rest.count else { return nil }
            let token = rest[index].lowercased()
            if let exact = options.first(where: { $0.lowercased() == token }) { return exact }
            guard let fixed = closest(token, in: options) else { return nil }
            reply("Autocorrected \"\(rest[index])\" → \(fixed)")
            return fixed
        }

        switch name {
        case "help":
            if let topic = rest.first {
                guard let target = spec(topic) ?? closest(topic, in: allNames).flatMap({ spec($0) }) else { return reply("No command called /\(topic).") }
                reply("\(target.usage) — \(target.help)")
            } else {
                for entry in specs { reply("\(entry.usage) — \(entry.help)") }
                reply("Tip: press Tab while typing to complete commands and names.")
            }

        case "give":
            var params = rest
            var targetPlayer: String?
            let isPlayer = { (word: String) in
                e.remotePlayers.contains { $0.name.lowercased() == word.lowercased() } || word.lowercased() == e.settings.username.lowercased()
            }
            if params.count >= 2, item(named: params[0], e) == nil, isPlayer(params[0]) { targetPlayer = params.removeFirst() }
            guard let (id, words) = resolveItem(params, e, note: reply), let info = e.items[id] else {
                return reply("Unknown item. Try /give diamond 5 or /give iron pickaxe.")
            }
            let count = max(1, min(64 * 36, Int(params.dropFirst(words).first ?? "") ?? 1))
            if let targetPlayer, targetPlayer.lowercased() != e.settings.username.lowercased() {
                guard e.give(playerNamed: targetPlayer, item: info.name, count: count) else {
                    return reply("Couldn't find a player named \(targetPlayer).")
                }
                return reply("Gave \(count) × \(info.displayName) to \(targetPlayer).")
            }
            var left = count
            while left > 0 {
                let batch = min(left, info.maxStack)
                let overflow = s.inventory.add(ItemStack(item: id, count: batch))
                if overflow > 0 { s.dropStack(ItemStack(item: id, count: overflow), thrown: false) }
                left -= batch
            }
            reply("Gave \(count) × \(info.displayName).")

        case "summon":
            guard let creature = rest.first, let kind = resolveCreature(creature, note: reply) else {
                return reply("Unknown creature. Choose from: \(creatureNames.joined(separator: ", "))")
            }
            var spot = s.player.position + horizontalLook(s) * 3
            var count = 1
            if rest.count >= 4 {
                guard let p = coordinates(Array(rest[1...3]), base: s.player.position, yOffset: s.world.generator.depthOffset) else { return reply("Couldn't read those coordinates.") }
                spot = p
            } else {
                if rest.count == 2, let n = Int(rest[1]) { count = max(1, min(25, n)) }
                if let y = s.world.findStandingY(Int(floor(spot.x)), Int(floor(spot.z)), near: Int(floor(s.player.position.y))) { spot.y = Double(y) }
            }
            let species = MobSpecies.of(kind)
            for i in 0..<count {
                let offset = i == 0 ? DVec3.zero : DVec3(Double.random(in: -2...2), 0, Double.random(in: -2...2))
                let mob = s.mobs.spawn(kind, at: DVec3(floor(spot.x) + 0.5, spot.y + (species.flying ? 1 : 0), floor(spot.z) + 0.5) + offset)
                if kind == .villager { mob.home = mob.position }
            }
            reply(count == 1 ? "Summoned a \(species.displayName)." : "Summoned \(count) × \(species.displayName).")

        case "tp":
            if rest.count == 1 {
                guard let friend = e.remotePlayers.first(where: { $0.name.lowercased() == rest[0].lowercased() })
                        ?? closest(rest[0], in: e.remotePlayers.map { $0.name }).flatMap({ n in e.remotePlayers.first { $0.name == n } }) else {
                    return reply("No player named \(rest[0]) is here.")
                }
                teleport(friend.position + DVec3(1, 0, 0))
                return reply("Teleported to \(friend.name).")
            }
            guard rest.count == 3, let p = coordinates(rest, base: s.player.position, yOffset: s.world.generator.depthOffset) else { return reply("Usage: \(command.usage)") }
            teleport(p)
            reply(String(format: "Teleported to %.0f, %.0f, %.0f.", p.x, p.y - Double(s.world.generator.depthOffset), p.z))

        case "back":
            guard let previous = s.lastPosition else { return reply("There's nowhere to go back to yet.") }
            teleport(previous)
            reply("Back where you were.")

        case "home":
            let home = s.meta.home.flatMap { $0.count == 3 ? DVec3($0[0], $0[1], $0[2]) : nil }
            teleport(home ?? s.spawnLocation)
            reply(home == nil ? "No home set, so you're at spawn. Use /sethome to set one." : "Welcome home.")

        case "sethome":
            s.setHome(s.player.position)
            reply(String(format: "Home set to %.0f, %.0f, %.0f.", s.player.position.x, s.player.position.y - Double(s.world.generator.depthOffset), s.player.position.z))

        case "spawnpoint":
            s.setSpawnPoint(s.player.position)
            reply(String(format: "Spawn point set to %.0f, %.0f, %.0f.", s.player.position.x, s.player.position.y - Double(s.world.generator.depthOffset), s.player.position.z))

        case "time", "day", "night":
            let presets: [String: Double] = ["day": 100, "noon": 300, "sunset": 580, "night": 700, "midnight": 900]
            let length = SkyModel.dayLength
            let dayStart = floor(s.worldTime / length) * length
            if name != "time" {
                s.debugSetTime(dayStart + presets[name]!)
                return reply(name == "day" ? "Good morning!" : "Night falls…")
            }
            guard let mode = choice(0, ["set", "add"]), rest.count == 2 else { return reply("Usage: \(command.usage)") }
            if mode == "add", let t = Double(rest[1]) {
                s.debugSetTime(s.worldTime + t)
                return reply("Added \(Int(t)) to the time.")
            }
            let everyday = ["nite": "night", "evening": "sunset", "dusk": "sunset", "dawn": "day", "morning": "day", "midday": "noon", "afternoon": "noon"]
            let value = Double(rest[1]) ?? presets[everyday[rest[1].lowercased()] ?? ""] ?? choice(1, Array(presets.keys)).flatMap { presets[$0] }
            guard let t = value else { return reply("Usage: \(command.usage)") }
            s.debugSetTime(dayStart + t.truncatingRemainder(dividingBy: length))
            reply("Time set to \(rest[1]).")

        case "weather":
            guard let w = choice(0, WeatherKind.allCases.map { $0.rawValue }), let kind = WeatherKind(rawValue: w) else {
                return reply("Usage: \(command.usage)")
            }
            s.weather.set(kind, duration: rest.count > 1 ? Double(rest[1]) : nil)
            switch kind {
            case .clear: reply("The skies clear.")
            case .rain: reply("It starts to rain.")
            case .thunder: reply("A thunderstorm rolls in!")
            case .storm: reply("A howling storm blows in! Hold on to your hat.")
            }

        case "event":
            guard let what = choice(0, ["eruption", "meteors"]) else { return reply("Usage: \(command.usage)") }
            if what == "meteors" {
                s.startMeteorShower()
                reply("Meteors incoming!")
            } else {
                reply(s.startEruption() ? "The nearest volcano rumbles to life!" : "There's no volcano within \(Int(Hazards.volcanoRange)) blocks. Try /locate volcano.")
            }

        case "gamemode":
            let aliases = ["s": "survival", "0": "survival", "c": "creative", "1": "creative"]
            let arg = rest.first.flatMap { aliases[$0.lowercased()] } ?? choice(0, ["survival", "creative"])
            guard let arg, let mode = GameMode(rawValue: arg) else { return reply("Usage: \(command.usage)") }
            s.setGameMode(mode)
            reply("Game mode set to \(mode.displayName).")

        case "difficulty":
            guard let arg = choice(0, Difficulty.allCases.map { $0.rawValue }), let d = Difficulty(rawValue: arg) else {
                return reply("Usage: \(command.usage)")
            }
            s.setDifficulty(d)
            reply("Difficulty set to \(d.displayName).")

        case "gamerule":
            guard !rest.isEmpty else {
                return reply("Rules: " + gameRules.map { "\($0) = \(s.meta.rule($0))" }.joined(separator: ", "))
            }
            guard let rule = choice(0, gameRules) else { return reply("Unknown rule. Rules: \(gameRules.joined(separator: ", "))") }
            guard rest.count >= 2 else { return reply("\(rule) = \(s.meta.rule(rule))") }
            guard let value = choice(1, ["true", "false"]) else { return reply("Use true or false.") }
            s.setRule(rule, value == "true")
            reply("Game rule \(rule) is now \(value).")

        case "heal":
            s.restoreVitals()
            reply("Health and hunger restored.")

        case "clear":
            s.inventory.clear()
            reply("Inventory cleared.")

        case "repair":
            let inv = s.inventory
            let targets = rest.first?.lowercased() == "all" ? Array(inv.slots.indices) : [inv.selected]
            var fixed = 0
            for i in targets {
                guard var stack = inv.slots[i], stack.damage > 0 else { continue }
                stack.damage = 0
                inv.slots[i] = stack
                fixed += 1
            }
            inv.markChanged()
            reply(fixed == 0 ? "Nothing needed repairing." : "Repaired \(fixed) tool\(fixed == 1 ? "" : "s").")

        case "fly":
            let on = rest.isEmpty ? !s.player.allowFlight : choice(0, ["on", "off"]) == "on"
            s.player.allowFlight = on
            if !on { s.player.setFlying(false) }
            reply(on ? "Flight on — double-tap jump to fly." : "Flight off.")

        case "god":
            let on = rest.isEmpty ? !s.godMode : choice(0, ["on", "off"]) == "on"
            s.godMode = on
            reply(on ? "You can't be hurt now." : "You can be hurt again.")

        case "kill":
            switch choice(0, ["me", "creatures", "hostile", "items"]) ?? (rest.isEmpty ? "me" : "?") {
            case "me":
                s.takeDamage(10_000, cause: "Defeated by a command", knockback: nil)
                reply("Ouch.")
            case "creatures":
                let n = s.mobs.mobs.filter { !$0.removed }.count
                for m in s.mobs.mobs { m.removed = true }
                reply("Removed \(n) creatures.")
            case "hostile":
                let hostile = s.mobs.mobs.filter { $0.species.hostile && !$0.removed }
                for m in hostile { m.removed = true }
                reply("Removed \(hostile.count) hostile creatures.")
            case "items":
                let n = s.entities.items.count
                s.entities.clear()
                reply("Removed \(n) dropped items.")
            default:
                reply("Usage: \(command.usage)")
            }

        case "setblock":
            guard rest.count == 4, let p = coordinates(Array(rest[0...2]), base: s.player.position, yOffset: s.world.generator.depthOffset),
                  let id = resolveBlock(rest[3], e, note: reply) else { return reply("Usage: \(command.usage)") }
            let pos = BlockPos(Int(floor(p.x)), Int(floor(p.y)), Int(floor(p.z)))
            if s.world.setBlock(pos, id) || s.world.block(pos) == id {
                reply("Placed \(e.blocks[id]?.displayName ?? rest[3]) at \(pos.x), \(pos.y), \(pos.z).")
            } else {
                reply("That spot isn't loaded or is outside the world.")
            }

        case "fill":
            guard rest.count == 7 || rest.count == 9, let a = coordinates(Array(rest[0...2]), base: s.player.position, yOffset: s.world.generator.depthOffset),
                  let b = coordinates(Array(rest[3...5]), base: s.player.position, yOffset: s.world.generator.depthOffset), let id = resolveBlock(rest[6], e, note: reply) else {
                return reply("Usage: \(command.usage)")
            }
            var only: BlockID?
            if rest.count == 9 {
                guard choice(7, ["replace"]) != nil, let old = resolveBlock(rest[8], e, note: reply) else { return reply("Usage: \(command.usage)") }
                only = old
            }
            let lo = BlockPos(Int(floor(min(a.x, b.x))), Int(floor(min(a.y, b.y))), Int(floor(min(a.z, b.z))))
            let hi = BlockPos(Int(floor(max(a.x, b.x))), Int(floor(max(a.y, b.y))), Int(floor(max(a.z, b.z))))
            let volume = Int(hi.x - lo.x + 1) * Int(hi.y - lo.y + 1) * Int(hi.z - lo.z + 1)
            guard volume <= 32_768 else { return reply("That's \(volume) blocks — the limit is 32768.") }
            var changed = 0
            for y in lo.y...hi.y {
                for z in lo.z...hi.z {
                    for x in lo.x...hi.x {
                        let pos = BlockPos(x, y, z)
                        if let only, s.world.block(pos) != only { continue }
                        if s.world.setBlock(pos, id) { changed += 1 }
                    }
                }
            }
            reply("Filled \(changed) blocks with \(e.blocks[id]?.displayName ?? rest[6]).")

        case "locate":
            guard s.dimension == .overworld, let generator = s.world.generator as? TerrainGenerator else {
                return reply("Only the Overworld can be searched.")
            }
            let px = Int(floor(s.player.position.x)), pz = Int(floor(s.player.position.z))
            guard let what = choice(0, ["village", "dungeon", "ruin", "desert_ruin", "dig_site", "volcano", "biome"]) else { return reply("Usage: \(command.usage)") }
            if what == "biome" {
                guard rest.count >= 2, let biome = resolveBiome(rest.dropFirst().joined(separator: "_"), note: reply) else {
                    return reply("Which biome? \(biomeNames.joined(separator: ", "))")
                }
                reply("Searching for \(biome.displayName)…")
                DispatchQueue.global(qos: .userInitiated).async {
                    let found = locateBiome(biome, x: px, z: pz, generator: generator)
                    DispatchQueue.main.async {
                        guard let f = found else { return reply("No \(biome.displayName) within 5000 blocks.") }
                        let distance = Int(hypot(Double(f.x - px), Double(f.z - pz)))
                        reply("Nearest \(biome.displayName): \(f.x), \(f.y), \(f.z) (\(distance) blocks away). Try /tp \(f.x) \(f.y + 2) \(f.z)")
                    }
                }
                return
            }
            var found: (x: Int, y: Int, z: Int, label: String)?
            if what == "village" {
                found = generator.villages(near: px, z: pz, radius: 4000).first.map { ($0.x, $0.y, $0.z, "village") }
            } else {
                let kind: StructureKind
                switch what {
                case "dungeon": kind = .dungeon
                case "ruin": kind = .ruin
                case "dig_site", "digsite", "fossils": kind = .digSite
                case "volcano": kind = .volcano
                default: kind = .desertRuin
                }
                found = generator.structures(near: px, z: pz, radius: 3000).first(where: { $0.kind == kind })
                    .map { ($0.x, $0.y, $0.z, kind.displayName.lowercased()) }
            }
            guard let f = found else { return reply("No \(what.replacingOccurrences(of: "_", with: " ")) found nearby.") }
            let distance = Int(hypot(Double(f.x - px), Double(f.z - pz)))
            let shownY = f.y - generator.depthOffset
            reply("Nearest \(f.label): \(f.x), \(shownY), \(f.z) (\(distance) blocks away). Try /tp \(f.x) \(shownY + 2) \(f.z)")

        case "biome":
            reply("You're in: \(s.biome.displayName)")

        case "coords":
            let p = s.player.position
            let facing = BlockRegistry.name(of: BlockVariants.horizontalFacing(s.player.lookDirection))
            reply(String(format: "Position %.1f, %.1f, %.1f · facing %@ · %@", p.x, p.y - Double(s.world.generator.depthOffset), p.z, facing, s.biome.displayName))

        case "list":
            let names = [e.settings.username.isEmpty ? "You" : e.settings.username] + e.remotePlayers.map { $0.name }
            reply("\(names.count) playing: \(names.joined(separator: ", "))")

        case "dimension":
            guard let arg = choice(0, ["overworld", "underworld", "skylands", "toonland"]),
                  let dim = WorldDimension.allCases.first(where: { $0.rawValue.lowercased() == arg || $0.displayName.lowercased().contains(arg) }) else {
                return reply("Usage: \(command.usage)")
            }
            guard dim != s.dimension else { return reply("You're already there.") }
            s.changeDimension(to: dim, portal: dim == .overworld ? nil : dim.portalBlock, arrival: nil)
            reply("Travelling to \(dim.displayName)…")

        case "seed":
            reply("Seed: \(s.meta.seedText.isEmpty ? s.meta.seed : s.meta.seedText)")

        case "say":
            let message = rest.joined(separator: " ")
            guard !message.isEmpty else { return reply("Usage: \(command.usage)") }
            if e.isMultiplayer { e.sendChat("[\(e.settings.username)] \(message)") } else { reply("[\(e.settings.username)] \(message)") }

        case "msg":
            guard e.isMultiplayer else { return reply("Private messages need other players in the game.") }
            guard rest.count >= 2 else { return reply("Usage: \(command.usage)") }
            let names = e.remotePlayers.map { $0.name }
            guard let target = names.first(where: { $0.lowercased() == rest[0].lowercased() }) ?? closest(rest[0], in: names) else {
                return reply("No player called \(rest[0]) is here. Type /list to see who's playing.")
            }
            if let problem = e.whisper(to: target, text: rest.dropFirst().joined(separator: " ")) { reply(problem) }

        case "name":
            guard !rest.isEmpty else { return reply("Usage: \(command.usage)") }
            // The tamed creature you're looking at, or else your nearest one.
            let pet = s.targetMob.flatMap { $0.isTamed ? $0 : nil }
                ?? s.mobs.mobs.filter { $0.isTamed && !$0.isDying }.min { simd_distance($0.position, s.player.position) < simd_distance($1.position, s.player.position) }
            guard let pet, simd_distance(pet.position, s.player.position) < 12 else {
                return reply("Look at one of your tamed creatures to name it (feed a dino its favourite food to tame it).")
            }
            let newName = String(rest.joined(separator: " ").prefix(20))
            pet.petName = newName
            reply("Your \(pet.species.displayName) is now called \(newName).")

        default:
            reply("Unknown command /\(name). Type /help for the list.")
        }
    }

    // MARK: Suggestions

    /// The usage line for the command being typed, if it's recognizable.
    static func usage(for text: String) -> String? {
        guard text.hasPrefix("/"), let first = text.dropFirst().split(separator: " ").first.map(String.init),
              text.contains(" ") else { return nil }
        return (spec(first) ?? closest(first, in: allNames).flatMap { spec($0) })?.usage
    }

    static func suggestions(for text: String, engine e: CommandHost) -> [CommandSuggestion] {
        guard text.hasPrefix("/") else { return [] }
        var tokens = String(text.dropFirst()).split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let current = tokens.popLast() ?? ""
        let head = "/" + tokens.map { $0 + " " }.joined()

        if tokens.isEmpty {
            return rank(current, specs.map { $0.name }).prefix(8).map {
                CommandSuggestion(label: "/\($0)", detail: spec($0)?.help, completion: "/\($0) ")
            }
        }
        guard let command = spec(tokens[0]) ?? closest(tokens[0], in: allNames).flatMap({ spec($0) }) else { return [] }
        let index = tokens.count - 1
        guard index < command.args.count else { return [] }
        let pool = candidates(command.args[index], previous: Array(tokens.dropFirst()), engine: e)
        let more = index + 1 < command.args.count
        return rank(current, pool).prefix(8).map { CommandSuggestion(label: $0, detail: nil, completion: head + $0 + (more ? " " : "")) }
    }

    private static func candidates(_ arg: Arg, previous: [String], engine e: CommandHost) -> [String] {
        let players = e.remotePlayers.map { $0.name }
        switch arg {
        case .items: return e.items.all.map { $0.name }
        case .blocks: return e.blocks.all.filter { $0.hasItem || $0.name == "air" || $0.name == "water" }.map { $0.name }
        case .creatures: return creatureNames
        case .biomes: return biomeNames
        case .command: return specs.map { $0.name }
        case .coordinate: return ["~"]
        case .number: return ["1", "16", "32", "64"]
        case .text: return []
        case .itemsOrPlayers: return players + e.items.all.map { $0.name }
        case .countOrItem:
            if let first = previous.first, players.contains(where: { $0.lowercased() == first.lowercased() }) { return e.items.all.map { $0.name } }
            return ["1", "16", "32", "64"]
        case .coordinateOrPlayer: return ["~"] + players
        case .players: return players
        case .choices(let options): return options
        }
    }

    /// Prefix matches first, then substring matches, then close misspellings.
    static func rank(_ token: String, _ pool: [String]) -> [String] {
        let t = token.lowercased()
        guard !t.isEmpty else { return Array(pool.prefix(8)) }
        var result = pool.filter { $0.lowercased().hasPrefix(t) }
        result += pool.filter { !$0.lowercased().hasPrefix(t) && $0.lowercased().contains(t) }
        if result.count < 4 {
            let limit = t.count <= 3 ? 1 : 2
            let fuzzy = pool.compactMap { name -> (String, Int)? in
                guard !result.contains(name) else { return nil }
                let d = distance(t, String(name.lowercased().prefix(t.count)))
                return d <= limit ? (name, d) : nil
            }.sorted { $0.1 < $1.1 }.map { $0.0 }
            result += fuzzy
        }
        return result
    }

    // MARK: Autocorrect

    /// Edit distance counting insertions, deletions, substitutions and swapped neighbors.
    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }

    /// The single best close match for a typo, or nil if nothing is close or it's ambiguous.
    static func closest(_ token: String, in pool: [String]) -> String? {
        let t = token.lowercased()
        guard !t.isEmpty else { return nil }
        let limit = t.count <= 3 ? 1 : (t.count <= 6 ? 2 : 3)
        var best: (name: String, d: Int)?
        var tie = false
        for name in pool {
            let d = distance(t, name.lowercased())
            guard d <= limit else { continue }
            if best == nil || d < best!.d {
                best = (name, d); tie = false
            } else if d == best!.d && name.lowercased() != best!.name.lowercased() {
                tie = true
            }
        }
        return tie ? nil : best?.name
    }

    private static func item(named raw: String, _ e: CommandHost) -> ItemID? {
        let key = raw.lowercased().replacingOccurrences(of: "minecraft:", with: "")
        if let id = e.items.id(named: key) { return id }
        return e.items.all.first { $0.displayName.lowercased().replacingOccurrences(of: " ", with: "_") == key }?.id
    }

    /// Longest run of words naming an item (so "iron pickaxe 2" works), with typo correction as a fallback.
    private static func resolveItem(_ words: [String], _ e: CommandHost, note: (String) -> Void) -> (ItemID, Int)? {
        for n in stride(from: words.count, through: 1, by: -1) where Int(words[n - 1]) == nil {
            if let id = item(named: words.prefix(n).joined(separator: "_"), e) { return (id, n) }
        }
        let names = e.items.all.map { $0.name }
        for n in stride(from: min(words.count, 3), through: 1, by: -1) where Int(words[n - 1]) == nil {
            let phrase = words.prefix(n).joined(separator: "_").lowercased()
            if let fixed = closest(phrase, in: names), let id = e.items.id(named: fixed) {
                note("Autocorrected \"\(words.prefix(n).joined(separator: " "))\" → \(fixed)")
                return (id, n)
            }
        }
        return nil
    }

    private static func resolveBlock(_ raw: String, _ e: CommandHost, note: (String) -> Void) -> BlockID? {
        let key = raw.lowercased()
        if let id = e.blocks.id(named: key) { return id }
        if let id = item(named: key, e), let b = e.items[id]?.block { return b }
        let pool = e.blocks.all.filter { $0.hasItem || $0.name == "air" || $0.name == "water" }.map { $0.itemName }
        guard let fixed = closest(key, in: pool) else { return nil }
        note("Autocorrected \"\(raw)\" → \(fixed)")
        return e.blocks.id(named: fixed) ?? e.items.id(named: fixed).flatMap { e.items[$0]?.block }
    }

    static var creatureNames: [String] { MobKind.allCases.map { String($0.eggItemName.dropFirst("spawn_egg_".count)) } }

    private static let creatureAliases: [String: MobKind] = [
        "trex": .rex, "tyrannosaurus": .rex, "triceratops": .trikey, "stegosaurus": .stego, "ankylosaurus": .ankylo,
        "pteranodon": .ptero, "parasaurolophus": .parasaur, "dimetrodon": .sailback, "skeleton": .boneWalker,
    ]

    private static func resolveCreature(_ raw: String, note: (String) -> Void) -> MobKind? {
        let key = raw.lowercased().replacingOccurrences(of: "-", with: "_")
        let compact = key.replacingOccurrences(of: "_", with: "")
        if let kind = creatureAliases[compact] { return kind }
        if let kind = MobKind.allCases.first(where: {
            $0.rawValue.lowercased() == compact || MobSpecies.of($0).displayName.lowercased().replacingOccurrences(of: " ", with: "") == compact
                || String($0.eggItemName.dropFirst("spawn_egg_".count)) == key
        }) { return kind }
        let pool = creatureNames + Array(creatureAliases.keys)
        guard let fixed = closest(key, in: pool) else { return nil }
        note("Autocorrected \"\(raw)\" → \(fixed)")
        return creatureAliases[fixed] ?? MobKind.allCases.first { String($0.eggItemName.dropFirst("spawn_egg_".count)) == fixed }
    }

    // MARK: Biomes

    static func commandName(_ biome: Biome) -> String {
        var out = ""
        for ch in String(describing: biome) {
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    static var overworldBiomes: [Biome] { Biome.allCases.filter { ![.underworld, .skylands, .toonland].contains($0) } }
    static var biomeNames: [String] { overworldBiomes.map(commandName) }

    private static func resolveBiome(_ raw: String, note: (String) -> Void) -> Biome? {
        let key = raw.lowercased()
        if let b = overworldBiomes.first(where: { commandName($0) == key || $0.displayName.lowercased().replacingOccurrences(of: " ", with: "_") == key }) {
            return b
        }
        let pool = biomeNames + overworldBiomes.map { $0.displayName.lowercased().replacingOccurrences(of: " ", with: "_") }
        guard let fixed = closest(key, in: pool) else { return nil }
        note("Autocorrected \"\(raw)\" → \(fixed)")
        return overworldBiomes.first { commandName($0) == fixed || $0.displayName.lowercased().replacingOccurrences(of: " ", with: "_") == fixed }
    }

    /// Spiral search outward in 32-block rings (up to about 5000 blocks). Safe to call off the main thread.
    static func locateBiome(_ biome: Biome, x: Int, z: Int, generator: TerrainGenerator) -> (x: Int, y: Int, z: Int)? {
        if generator.columnInfo(x: x, z: z).biome == biome { return (x, generator.columnInfo(x: x, z: z).height, z) }
        for ring in 1...160 {
            let r = Double(ring * 32)
            let steps = max(8, Int(2 * .pi * r / 32))
            for i in 0..<steps {
                let a = Double(i) / Double(steps) * 2 * .pi
                let px = x + Int(cos(a) * r), pz = z + Int(sin(a) * r)
                let info = generator.columnInfo(x: px, z: pz)
                if info.biome == biome { return (px, info.height, pz) }
            }
        }
        return nil
    }

    // MARK: Helpers

    private static func horizontalLook(_ s: GameSession) -> DVec3 {
        let look = s.player.lookDirection
        let flat = DVec3(look.x, 0, look.z)
        return simd_length(flat) > 0.01 ? simd_normalize(flat) : DVec3(0, 0, -1)
    }

    /// Parses three coordinates, where `~` or `~n` is relative to `base`.
    /// Absolute Y values are as shown on screen (`yOffset` below the stored height in deep worlds).
    static func coordinates(_ parts: [String], base: DVec3, yOffset: Int = 0) -> DVec3? {
        guard parts.count == 3 else { return nil }
        var out = [Double]()
        for (i, part) in parts.enumerated() {
            let origin = [base.x, base.y, base.z][i]
            if part.hasPrefix("~") {
                let offset = part.count > 1 ? Double(part.dropFirst()) : 0
                guard let offset else { return nil }
                out.append(origin + offset)
            } else if let v = Double(part) {
                out.append(i == 1 ? v + Double(yOffset) : v + (v == v.rounded() ? 0.5 : 0))
            } else {
                return nil
            }
        }
        return DVec3(out[0], out[1], out[2])
    }
}
