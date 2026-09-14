import Foundation
import CSDL3
import DinoCraftCore

/// The Windows game loop: input, movement, building and mining, survival (when joining a
/// Survival world), chat, name tags, day/night, saving, multiplayer and rendering.
final class WinGame {
    private enum EntityTarget {
        case mob(Int)
        case player(Int)
    }

    private let gl: GL
    private let window: OpaquePointer
    private let options: Options
    private let blocks: BlockRegistry
    private let items: ItemRegistry
    private let renderer: WinRenderer
    private let storage: WorldStorage?
    private var meta: WorldMetadata?
    private let jobs: WinJobSystem
    private let world: WinWorld
    private let player: PlayerController
    private let network: WinNetwork?
    private let inventory: Inventory
    private let creative: Bool
    private let spawnPoint: DVec3

    private var running = true
    private var mouseCaptured = false
    private var needsSpawnResolve: Bool
    private var worldTime: Double
    private var jumpPressed = false
    private var leftHeld = false
    private var attackQueued = false
    private var placeQueued = false
    private var screenshotQueued = false
    private var swingTimer = 0.0
    private var stateTimer = 0.0
    private var disconnectReason: String?
    private var demoEntities: [RemoteEntity] = []

    // Survival
    private var health = 20.0
    private var dead = false
    private var deathMessage = ""
    private var hurtCooldown = 0.0
    private var damageFlash = 0.0
    private var regenTimer = 0.0
    private var attackCooldown = 0.0
    private var breakingPos: BlockPos?
    private var breakProgress = 0.0

    // Chat
    private var chatLines: [(text: String, time: Double)] = []
    private var chatOpen = false
    private var chatInput = ""
    private var swallowText: String?

    private let startTime = Date.timeIntervalSinceReferenceDate
    private var lastFrame = Date.timeIntervalSinceReferenceDate
    private var autosaveTimer = 0.0
    private var titleTimer = 0.0
    private var framesThisSecond = 0
    private var fps = 0
    private var framesSinceReady = 0

    init(gl: GL, window: OpaquePointer, options: Options, network: WinNetwork?) throws {
        // Build everything in locals first: stored properties can't be read until all are set.
        let blocks = try BlockRegistry.loadDefault()
        let items = try ItemRegistry.loadDefault(blocks: blocks)
        let renderer = try WinRenderer(gl: gl, blocks: blocks, items: items)
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let jobs = WinJobSystem(workerCount: workers, registry: blocks)
        let inventory = Inventory(registry: items)
        let creative = network.map { $0.welcome.gameMode == "creative" } ?? true

        let storage: WorldStorage?
        let meta: WorldMetadata?
        let world: WinWorld
        let player: PlayerController
        var resolveSpawn = false
        let time: Double

        if let network {
            let welcome = network.welcome
            storage = nil
            meta = nil
            let generator = WorldDimension.overworld.makeGenerator(seed: UInt64(welcome.seed) ?? 0)
            world = WinWorld(registry: blocks, generator: generator, storage: nil, worldID: nil, jobs: jobs,
                             renderDistance: options.renderDistance)
            world.remoteRequest = { network.requestChunks($0) }
            player = PlayerController(position: DVec3(welcome.x, welcome.y, welcome.z))
            time = welcome.worldTime
        } else {
            let localStorage = WorldStorage()
            let worldName = "Windows World"
            let localMeta: WorldMetadata
            if let existing = localStorage.listWorlds().first(where: { $0.name == worldName }) {
                localMeta = existing
            } else {
                localMeta = try localStorage.createWorld(name: worldName, seedText: options.seed, gameMode: .creative, difficulty: .normal)
                Log.info("Created world '\(worldName)' with seed \(localMeta.seedText)", category: "Game")
            }
            let generator = WorldDimension.overworld.makeGenerator(seed: localMeta.numericSeed)
            world = WinWorld(registry: blocks, generator: generator, storage: localStorage, worldID: localMeta.id, jobs: jobs,
                             renderDistance: options.renderDistance)
            if let saved = localStorage.loadPlayer(id: localMeta.id) {
                player = PlayerController(position: DVec3(saved.x, saved.y, saved.z))
                player.yaw = saved.yaw
                player.pitch = saved.pitch
                inventory.selected = max(0, min(8, saved.selectedSlot))
            } else {
                let column = generator.findSpawnColumn()
                let y = generator.estimatedSurface(x: column.x, z: column.z)
                player = PlayerController(position: DVec3(Double(column.x) + 0.5, Double(y) + 1, Double(column.z) + 0.5))
                player.pitch = -0.2
                resolveSpawn = true
            }
            storage = localStorage
            meta = localMeta
            time = localMeta.worldTime
        }
        player.gameMode = creative ? .creative : .survival
        if creative {
            let names = ["grass", "dirt", "stone", "cobblestone", "planks", "log", "glass", "torch", "amber_lantern"]
            for (i, name) in names.enumerated() {
                if let id = items.id(named: name) { inventory.slots[i] = ItemStack(item: id, count: 64) }
            }
        }
        world.uploadMesh = { renderer.makeMesh($0) }
        world.releaseMesh = { renderer.deleteMesh($0) }

        self.gl = gl
        self.window = window
        self.options = options
        self.blocks = blocks
        self.items = items
        self.renderer = renderer
        self.storage = storage
        self.meta = meta
        self.jobs = jobs
        self.world = world
        self.player = player
        self.network = network
        self.inventory = inventory
        self.creative = creative
        spawnPoint = player.position
        needsSpawnResolve = resolveSpawn
        worldTime = time
        if let network {
            Log.info("Playing on '\(network.welcome.worldName)' in \(creative ? "Creative" : "Survival") at \(player.position)", category: "Game")
        } else {
            Log.info("World '\(meta?.name ?? "?")' opened at \(player.position)", category: "Game")
        }
    }

    // MARK: Loop

    /// Runs until the window closes. Returns the reason if the host disconnected us.
    func run() -> String? {
        if options.screenshotPath == nil { setMouseCaptured(true) }
        if let network {
            addChat("Joined \(network.welcome.worldName). Press T to chat.", now: Date.timeIntervalSinceReferenceDate)
        }
        while running {
            let now = Date.timeIntervalSinceReferenceDate
            let dt = min(0.1, now - lastFrame)
            lastFrame = now
            pollEvents(now: now)
            update(dt: dt, now: now)
            draw(now: now)
        }
        shutdown()
        return disconnectReason
    }

    private func setMouseCaptured(_ captured: Bool) {
        mouseCaptured = captured
        _ = SDL_SetWindowRelativeMouseMode(window, captured)
    }

    private func addChat(_ text: String, now: Double) {
        chatLines.append((text, now))
        if chatLines.count > 60 { chatLines.removeFirst(chatLines.count - 60) }
        Log.info("Chat: \(text)", category: "Net")
        print("  \(text)")
    }

    private func openChat() {
        guard network != nil, !chatOpen else { return }
        chatOpen = true
        chatInput = ""
        swallowText = "t"
        leftHeld = false
        _ = SDL_StartTextInput(window)
    }

    private func closeChat() {
        chatOpen = false
        chatInput = ""
        _ = SDL_StopTextInput(window)
    }

    private func pollEvents(now: Double) {
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            let type = UInt32(event.type)
            if type == UInt32(SDL_EVENT_QUIT.rawValue) {
                running = false
            } else if type == UInt32(SDL_EVENT_TEXT_INPUT.rawValue) {
                guard chatOpen, let raw = event.text.text else { continue }
                let typed = String(cString: raw)
                if let swallow = swallowText {
                    swallowText = nil
                    if typed.lowercased() == swallow { continue }
                }
                chatInput = String((chatInput + typed).prefix(100))
            } else if type == UInt32(SDL_EVENT_KEY_DOWN.rawValue) {
                let code = Int(event.key.scancode.rawValue)
                if chatOpen {
                    if code == Int(SDL_SCANCODE_ESCAPE.rawValue) {
                        closeChat()
                    } else if code == Int(SDL_SCANCODE_RETURN.rawValue) || code == Int(SDL_SCANCODE_KP_ENTER.rawValue) {
                        let text = chatInput.trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty { network?.sendChat(text) }
                        closeChat()
                    } else if code == Int(SDL_SCANCODE_BACKSPACE.rawValue), !chatInput.isEmpty {
                        chatInput.removeLast()
                    }
                    continue
                }
                guard !event.key.`repeat` else { continue }
                if code == Int(SDL_SCANCODE_ESCAPE.rawValue) {
                    setMouseCaptured(!mouseCaptured)
                } else if code == Int(SDL_SCANCODE_SPACE.rawValue) {
                    if dead { respawn() } else { jumpPressed = true }
                } else if code == Int(SDL_SCANCODE_T.rawValue) {
                    openChat()
                } else if code == Int(SDL_SCANCODE_F2.rawValue) {
                    screenshotQueued = true
                } else if code >= Int(SDL_SCANCODE_1.rawValue) && code <= Int(SDL_SCANCODE_9.rawValue) {
                    inventory.selected = code - Int(SDL_SCANCODE_1.rawValue)
                }
            } else if type == UInt32(SDL_EVENT_MOUSE_MOTION.rawValue) {
                guard mouseCaptured else { continue }
                let sensitivity = 0.0022
                player.yaw -= Double(event.motion.xrel) * sensitivity
                player.pitch = max(-1.55, min(1.55, player.pitch - Double(event.motion.yrel) * sensitivity))
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue) {
                if !mouseCaptured {
                    setMouseCaptured(true)
                } else if event.button.button == 1 {
                    leftHeld = true
                    attackQueued = true
                } else if event.button.button == 3 {
                    placeQueued = true
                }
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_UP.rawValue) {
                if event.button.button == 1 { leftHeld = false }
            } else if type == UInt32(SDL_EVENT_MOUSE_WHEEL.rawValue) {
                if event.wheel.y < 0 { inventory.selected += 1 }
                if event.wheel.y > 0 { inventory.selected -= 1 }
            } else if type == UInt32(SDL_EVENT_WINDOW_FOCUS_LOST.rawValue) {
                setMouseCaptured(false)
                leftHeld = false
            }
        }
        swallowText = nil
    }

    private func update(dt: Double, now: Double) {
        worldTime += dt
        swingTimer = max(0, swingTimer - dt)
        hurtCooldown = max(0, hurtCooldown - dt)
        damageFlash = max(0, damageFlash - dt * 1.6)
        attackCooldown = max(0, attackCooldown - dt)
        if let network { handleNetwork(network, dt: dt, now: now) }
        world.update(focus: player.position, now: now)

        let px = Int(floor(player.position.x)), pz = Int(floor(player.position.z))
        if needsSpawnResolve, world.isLoaded(px, pz), let y = world.findStandingY(px, pz, near: Int(player.position.y)) {
            player.teleport(to: DVec3(player.position.x, Double(y), player.position.z))
            needsSpawnResolve = false
            Log.info("Spawn resolved at \(player.position)", category: "Game")
        }

        let controllable = mouseCaptured && !chatOpen && !dead
        var input = MovementInput()
        if controllable, let keys = SDL_GetKeyboardState(nil) {
            func down(_ scancode: SDL_Scancode) -> Bool { keys[Int(scancode.rawValue)] }
            input.forward = (down(SDL_SCANCODE_W) ? 1 : 0) - (down(SDL_SCANCODE_S) ? 1 : 0)
            input.strafe = (down(SDL_SCANCODE_D) ? 1 : 0) - (down(SDL_SCANCODE_A) ? 1 : 0)
            input.jump = down(SDL_SCANCODE_SPACE)
            input.sprint = down(SDL_SCANCODE_LCTRL)
            input.sneak = down(SDL_SCANCODE_LSHIFT)
        }
        input.jumpPressed = jumpPressed && controllable
        jumpPressed = false
        if !needsSpawnResolve && !dead && world.isLoaded(px, pz) {
            player.update(dt: dt, input: input, world: world)
        }
        for event in player.events {
            if case .landed(let fall, _) = event, fall > 3.5 { hurt(fall - 3, cause: "Fell from a high place", knockback: nil, now: now) }
        }
        player.events.removeAll()

        if !creative && !dead && health < 20 {
            regenTimer += dt
            if regenTimer > 4 {
                regenTimer = 0
                health = min(20, health + 1)
            }
        }

        if controllable {
            interact(dt: dt)
        } else {
            breakingPos = nil
            breakProgress = 0
        }
        attackQueued = false
        placeQueued = false

        autosaveTimer += dt
        if autosaveTimer > 60 {
            autosaveTimer = 0
            save()
        }
        titleTimer += dt
        framesThisSecond += 1
        if titleTimer >= 1 {
            fps = framesThisSecond
            framesThisSecond = 0
            titleTimer = 0
            SDL_SetWindowTitle(window, "DinoCraft · \(fps) FPS\(network.map { " · \($0.welcome.worldName)" } ?? "")")
        }
    }

    // MARK: Building, mining and combat

    private var heldTool: ToolSpec? { inventory.selectedStack.flatMap { items[$0.item]?.tool } }

    private func canHarvest(_ info: BlockInfo) -> Bool {
        guard info.toolLevel > 0 else { return true }
        guard let tool = heldTool else { return false }
        return tool.kind == info.tool && tool.level >= info.toolLevel
    }

    private func breakTime(_ info: BlockInfo) -> Double {
        guard info.hardness > 0 else { return 0 }
        let tool = heldTool
        let correct = info.tool != .none && tool?.kind == info.tool
        let speed = correct ? Double(tool?.speed ?? 1) : 1
        var t = Double(info.hardness) * (canHarvest(info) ? 1.5 : 5.0) / speed
        if player.headInWater { t *= 3 }
        if !player.onGround && !player.flying && !player.inWater { t *= 2 }
        return t
    }

    private func interact(dt: Double) {
        let target = VoxelPhysics.raycast(world, origin: player.eyePosition, direction: player.lookDirection, maxDistance: creative ? 6.5 : 5)
        let entity = entityUnderCrosshair(maxDistance: 4.5)
        let entityCloser = entity.map { e in target.map { e.distance < $0.distance } ?? true } ?? false

        if attackQueued, entityCloser, let entity, attackCooldown <= 0, let network {
            let look = player.lookDirection
            let flat = sqrt(look.x * look.x + look.z * look.z)
            let knockback = flat > 0.01 ? DVec3(look.x / flat, 0, look.z / flat) : DVec3(0, 0, -1)
            let damage = Double(heldTool?.damage ?? 1) * (creative ? 6 : 1)
            switch entity.target {
            case .mob(let id): network.sendAttackMob(id: id, damage: damage, knockback: knockback)
            case .player(let id): network.sendAttackPlayer(id: id, damage: damage, knockback: knockback)
            }
            attackCooldown = 0.35
            swingTimer = 0.25
            if !creative && heldTool != nil { inventory.damageSelectedTool() }
            return
        }

        if !entityCloser, let hit = target, let info = blocks[hit.id], info.isBreakable {
            if creative {
                if attackQueued { breakBlock(hit, info: info) }
            } else if leftHeld {
                if breakingPos != hit.block {
                    breakingPos = hit.block
                    breakProgress = 0
                }
                let time = breakTime(info)
                breakProgress += time <= 0.001 ? 1 : dt / time
                swingTimer = 0.25
                if breakProgress >= 1 {
                    breakBlock(hit, info: info)
                    breakingPos = nil
                    breakProgress = 0
                }
            }
        } else {
            breakingPos = nil
            breakProgress = 0
        }
        if !leftHeld {
            breakingPos = nil
            breakProgress = 0
        }

        if placeQueued, let hit = target { place(hit) }
    }

    private func breakBlock(_ hit: RaycastHit, info: BlockInfo) {
        guard world.setBlock(hit.block, Blocks.air) else { return }
        network?.sendBlock(hit.block, Blocks.air, harvest: !creative && canHarvest(info))
        swingTimer = 0.25
        if !creative && info.hardness > 0 && heldTool != nil { inventory.damageSelectedTool() }
    }

    private func place(_ hit: RaycastHit) {
        guard let stack = inventory.selectedStack, let info = items[stack.item], let blockID = info.block else { return }
        var cell = hit.adjacent
        if blocks[hit.id]?.replaceable == true { cell = hit.block }
        guard cell.y >= 0, cell.y < Int32(WorldConst.height) else { return }
        let current = world.block(cell)
        guard current == Blocks.air || blocks[current]?.replaceable == true else { return }
        let origin = DVec3(Double(cell.x), Double(cell.y), Double(cell.z))
        if blocks.isSolid[Int(blockID)] && DBox(min: origin, max: origin + DVec3(1, 1, 1)).intersects(player.box) { return }
        guard world.setBlock(cell, blockID) else { return }
        network?.sendBlock(cell, blockID, harvest: false)
        swingTimer = 0.25
        if !creative { inventory.consumeSelected() }
    }

    private func entityUnderCrosshair(maxDistance: Double) -> (target: EntityTarget, distance: Double)? {
        guard let network else { return nil }
        let origin = player.eyePosition, direction = player.lookDirection
        var best: (target: EntityTarget, distance: Double)?
        func test(_ e: RemoteEntity, _ halfWidth: Double, _ height: Double, _ target: EntityTarget) {
            let lo = e.position - DVec3(halfWidth, 0, halfWidth), hi = e.position + DVec3(halfWidth, height, halfWidth)
            guard let t = WinGame.rayBox(origin, direction, lo, hi), t <= maxDistance, t < (best?.distance ?? .infinity) else { return }
            best = (target, t)
        }
        for p in network.players.values where p.dying == 0 { test(p, 0.35, 1.9, .player(p.id)) }
        for m in network.mobs.values where m.dying == 0 {
            let size = EntityShapes.size(of: m.kind)
            test(m, size.width * 0.9, size.height, .mob(m.id))
        }
        return best
    }

    private static func rayBox(_ o: DVec3, _ d: DVec3, _ lo: DVec3, _ hi: DVec3) -> Double? {
        var tmin = 0.0, tmax = Double.infinity
        for axis in 0..<3 {
            if abs(d[axis]) < 1e-9 {
                if o[axis] < lo[axis] || o[axis] > hi[axis] { return nil }
            } else {
                let inv = 1 / d[axis]
                var t1 = (lo[axis] - o[axis]) * inv, t2 = (hi[axis] - o[axis]) * inv
                if t1 > t2 { swap(&t1, &t2) }
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return tmin
    }

    // MARK: Health

    private func hurt(_ amount: Double, cause: String, knockback: DVec3?, now: Double) {
        guard !creative, !dead, amount > 0, hurtCooldown <= 0 else { return }
        health = max(0, health - amount)
        hurtCooldown = 0.5
        damageFlash = 1
        if let k = knockback { player.velocity += DVec3(k.x * 7, 4.5, k.z * 7) }
        if health <= 0 {
            dead = true
            deathMessage = cause
            leftHeld = false
            addChat("You died: \(cause)", now: now)
        }
    }

    private func respawn() {
        dead = false
        health = 20
        damageFlash = 0
        player.teleport(to: spawnPoint)
    }

    // MARK: Network

    private func handleNetwork(_ network: WinNetwork, dt: Double, now: Double) {
        for event in network.poll() {
            switch event {
            case .chunk(let chunk):
                world.receiveRemoteChunk(chunk)
            case .blockChange(let pos, let id):
                world.setBlock(pos, id)
            case .worldTime(let time):
                worldTime = time
            case .dimensionChange(let position):
                world.resetRemote()
                player.teleport(to: position)
                addChat("Following the host to another dimension", now: now)
            case .notice(let text):
                addChat(text, now: now)
            case .giveItem(let name, let count, let damage):
                if let id = items.id(named: name) {
                    let left = inventory.add(ItemStack(item: id, count: count, damage: damage))
                    if left > 0 { addChat("Your inventory is full", now: now) }
                }
            case .damage(let amount, let cause, let knockback):
                let scale: Double
                switch network.welcome.difficulty {
                case "peaceful": scale = 0
                case "easy": scale = 0.4
                case "hard": scale = 1.0
                default: scale = 0.6
                }
                hurt(amount * scale, cause: cause, knockback: knockback, now: now)
            case .disconnected(let reason):
                disconnectReason = reason
                running = false
            }
        }
        network.updateEntities(dt: dt)
        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            network.sendState(player: player, swinging: swingTimer > 0, held: inventory.selectedStack.flatMap { items[$0.item]?.name },
                              health: Float(creative ? 20 : health), dead: dead)
        }
    }

    // MARK: Drawing

    private func entityBoxes() -> [WinRenderer.Box] {
        var boxes: [WinRenderer.Box] = []
        if let network {
            for p in network.players.values { boxes += EntityShapes.player(p) }
            for m in network.mobs.values { boxes += EntityShapes.mob(m) }
        }
        for e in demoEntities { boxes += e.kind == "player" ? EntityShapes.player(e) : EntityShapes.mob(e) }
        return boxes
    }

    private func iconLayer(_ item: ItemID) -> Float {
        guard let info = items[item] else { return -1 }
        if let texture = info.texture {
            if let layer = renderer.itemLayers[texture] { return UIBuilder.itemLayerOffset + Float(layer) }
            if let layer = renderer.blockLayers[texture] { return Float(layer) }
        }
        if let block = info.block { return Float(blocks.faceLayers[Int(block) * 6 + BlockFace.south.rawValue]) }
        return -1
    }

    private func buildUI(width W: Float, height H: Float, camera: WinCamera, now: Double) -> [Float] {
        var ui = UIBuilder()
        let s = max(1, min(W / 1280, H / 720))
        let small = max(1, (2 * s).rounded())
        let white = SIMD4<Float>(1, 1, 1, 1)

        // Name tags over other players
        let viewProj = camera.viewProjection(aspect: W / max(1, H))
        var tagged = demoEntities.filter { $0.kind == "player" }
        if let network { tagged += network.players.values.filter { $0.dying == 0 } }
        for p in tagged {
            let rel = p.position + DVec3(0, 2.25, 0) - camera.position
            guard simd_length(rel) < 48 else { continue }
            let clip = viewProj * SIMD4<Float>(Float(rel.x), Float(rel.y), Float(rel.z), 1)
            guard clip.w > 0.1 else { continue }
            let sx = (clip.x / clip.w * 0.5 + 0.5) * W, sy = (0.5 - clip.y / clip.w * 0.5) * H
            let width = UIBuilder.textWidth(p.name, scale: small)
            ui.rect(sx - width / 2 - 3 * small, sy - 9 * small, width + 6 * small, 11 * small, SIMD4(0, 0, 0, 0.45))
            ui.text(p.name, x: sx - width / 2, y: sy - 7 * small, scale: small, color: white, shadow: false)
        }

        // Crosshair and mining progress
        ui.rect(W / 2 - 1.5 * s, H / 2 - 11 * s, 3 * s, 22 * s, SIMD4(0.9, 0.9, 0.9, 0.85))
        ui.rect(W / 2 - 11 * s, H / 2 - 1.5 * s, 22 * s, 3 * s, SIMD4(0.9, 0.9, 0.9, 0.85))
        if breakProgress > 0 {
            ui.rect(W / 2 - 22 * s, H / 2 + 18 * s, 44 * s, 5 * s, SIMD4(0, 0, 0, 0.5))
            ui.rect(W / 2 - 22 * s, H / 2 + 18 * s, 44 * s * Float(min(1, breakProgress)), 5 * s, SIMD4(0.95, 0.6, 0.12, 1))
        }

        // Hotbar
        let slot = 54 * s, gap = 6 * s
        let total = Float(Inventory.hotbarCount) * slot + Float(Inventory.hotbarCount - 1) * gap
        let x0 = W / 2 - total / 2, y0 = H - slot - 18 * s
        ui.rect(x0 - 8 * s, y0 - 8 * s, total + 16 * s, slot + 16 * s, SIMD4(0.005, 0.003, 0.012, 0.55))
        for i in 0..<Inventory.hotbarCount {
            let x = x0 + Float(i) * (slot + gap)
            if i == inventory.selected { ui.rect(x - 3 * s, y0 - 3 * s, slot + 6 * s, slot + 6 * s, SIMD4(0.9, 0.45, 0.08, 1)) }
            ui.rect(x, y0, slot, slot, SIMD4(0.02, 0.012, 0.04, 0.85))
            guard let stack = inventory.slots[i] else { continue }
            ui.icon(x + 9 * s, y0 + 9 * s, slot - 18 * s, layer: iconLayer(stack.item))
            if stack.count > 1 {
                let count = "\(stack.count)"
                ui.text(count, x: x + slot - 4 * s - UIBuilder.textWidth(count, scale: small), y: y0 + slot - 4 * s - 7 * small, scale: small, color: white)
            }
            if let tool = items[stack.item]?.tool, stack.damage > 0 {
                let fraction = max(0, 1 - Float(stack.damage) / Float(max(1, tool.durability)))
                ui.rect(x + 7 * s, y0 + slot - 7 * s, slot - 14 * s, 3 * s, SIMD4(0, 0, 0, 0.7))
                ui.rect(x + 7 * s, y0 + slot - 7 * s, (slot - 14 * s) * fraction, 3 * s, SIMD4(1 - fraction, fraction, 0.1, 1))
            }
        }

        // Hearts (Survival)
        if !creative || options.demoEntities {
            let shown = creative ? 13.0 : health
            for i in 0..<10 {
                let hx = x0 + Float(i) * 8 * small, hy = y0 - 12 * s - 7 * small
                let value = shown / 2 - Double(i)
                ui.text("\u{2665}", x: hx, y: hy, scale: small, color: SIMD4(0.1, 0.02, 0.03, 0.85), shadow: false)
                if value >= 1 {
                    ui.text("\u{2665}", x: hx, y: hy, scale: small, color: SIMD4(0.95, 0.1, 0.16, 1), shadow: false)
                } else if value > 0 {
                    ui.text("\u{2665}", x: hx, y: hy, scale: small, color: SIMD4(0.85, 0.42, 0.48, 1), shadow: false)
                }
            }
        }

        // Chat
        let lineHeight = 10 * small
        let recent = chatOpen ? Array(chatLines.suffix(12)) : Array(chatLines.filter { now - $0.time < 10 }.suffix(8))
        let inputY = y0 - 40 * s
        var y = inputY - (chatOpen ? lineHeight + 4 * s : 0)
        for line in recent.reversed() {
            y -= lineHeight
            let alpha: Float = chatOpen ? 1 : Float(max(0, min(1, (10 - (now - line.time)) / 1.5)))
            let text = String(line.text.prefix(90))
            ui.rect(12 * s, y - 2 * small, UIBuilder.textWidth(text, scale: small) + 8 * small, lineHeight, SIMD4(0, 0, 0, 0.4 * alpha))
            ui.text(text, x: 12 * s + 4 * small, y: y, scale: small, color: SIMD4(1, 1, 1, alpha))
        }
        if chatOpen {
            let text = "> " + chatInput + (Int(now * 2) % 2 == 0 ? "_" : "")
            ui.rect(12 * s, inputY - 2 * small, max(360 * s, UIBuilder.textWidth(text, scale: small) + 8 * small), lineHeight, SIMD4(0, 0, 0, 0.6))
            ui.text(text, x: 12 * s + 4 * small, y: inputY, scale: small, color: SIMD4(1, 1, 0.85, 1))
        }

        // Status line
        if let network {
            let status = "\(network.welcome.worldName) - \(network.players.count + 1) playing - T to chat"
            ui.text(status, x: 12 * s, y: 12 * s, scale: small, color: SIMD4(1, 1, 1, 0.8))
        }

        // Damage flash, death screen, paused hint
        if damageFlash > 0 { ui.rect(0, 0, W, H, SIMD4(0.6, 0, 0, Float(damageFlash) * 0.3)) }
        if dead {
            ui.rect(0, 0, W, H, SIMD4(0.25, 0, 0, 0.6))
            let big = max(1, (7 * s).rounded())
            ui.centeredText("YOU DIED", centerX: W / 2, y: H * 0.35, scale: big, color: SIMD4(1, 0.35, 0.35, 1))
            ui.centeredText(deathMessage, centerX: W / 2, y: H * 0.35 + 12 * big, scale: small, color: white)
            ui.centeredText("Press Space to respawn", centerX: W / 2, y: H * 0.35 + 12 * big + 18 * small, scale: small, color: white)
        } else if !mouseCaptured && options.screenshotPath == nil {
            ui.centeredText("Click to play", centerX: W / 2, y: H / 2 - 40 * s, scale: max(1, (3 * s).rounded()), color: white)
        }
        return ui.vertices
    }

    /// Automated check: sample players, creatures and chat so the screenshot shows the multiplayer view.
    private func placeDemoEntities(now: Double) {
        let look = player.lookDirection
        let forward = simd_normalize(DVec3(look.x, 0, look.z))
        let right = DVec3(-forward.z, 0, forward.x)
        let samples: [(String, String, Double, Double)] = [("player", "Friend", 5, -1.5), ("raptor", "raptor", 7, 2), ("trikey", "trikey", 9, -4),
                                                           ("rex", "rex", 16, 3), ("sheep", "sheep", 6, 4)]
        for (i, sample) in samples.enumerated() {
            let spot = player.position + forward * sample.2 + right * sample.3
            let y = world.findStandingY(Int(floor(spot.x)), Int(floor(spot.z)), near: Int(player.position.y)) ?? Int(player.position.y)
            demoEntities.append(RemoteEntity(id: i + 1, kind: sample.0, name: sample.1, position: DVec3(spot.x, Double(y), spot.z),
                                             yaw: atan2(forward.x, forward.z)))
        }
        addChat("Friend joined the game", now: now)
        addChat("<Friend> hi from the Mac!", now: now)
    }

    private func draw(now: Double) {
        var w: Int32 = 0, h: Int32 = 0
        _ = SDL_GetWindowSizeInPixels(window, &w, &h)
        var camera = WinCamera()
        camera.position = player.eyePosition
        camera.yaw = player.yaw
        camera.pitch = player.pitch
        let ui = buildUI(width: Float(w), height: Float(h), camera: camera, now: now)
        renderer.render(world: world, camera: camera, sky: SkyState.at(worldTime: worldTime), time: now - startTime, now: now,
                        width: w, height: h, ui: ui, boxes: entityBoxes())

        if let path = options.screenshotPath {
            let center = ChunkPos(Int32(floor(player.position.x / 16)), Int32(floor(player.position.z / 16)))
            let ready = world.readiness(around: center, radius: 3)
            if !needsSpawnResolve && ready.meshed == ready.total {
                if options.demoEntities && demoEntities.isEmpty { placeDemoEntities(now: now) }
                framesSinceReady += 1
            }
            let timedOut = now - startTime > 150
            if framesSinceReady >= options.frames || timedOut {
                if timedOut { Log.warning("Screenshot taken before the world finished loading (\(ready.meshed)/\(ready.total) chunks)", category: "Game") }
                saveScreenshot(to: URL(fileURLWithPath: path), width: w, height: h)
                Log.info("Automated check: \(renderer.visibleChunks) chunks visible, \(world.slots.count) loaded, \(demoEntities.count) sample entities", category: "Game")
                running = false
            }
        } else if screenshotQueued {
            screenshotQueued = false
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
            saveScreenshot(to: GamePaths.screenshots.appendingPathComponent("DinoCraft_\(formatter.string(from: Date())).png"), width: w, height: h)
        }
        SDL_GL_SwapWindow(window)
    }

    private func saveScreenshot(to url: URL, width: Int32, height: Int32) {
        let image = renderer.capture(width: width, height: height)
        do {
            try PNG.encode(width: image.width, height: image.height, rgba: image.rgba).write(to: url)
            Log.info("Saved screenshot \(url.path) (\(image.width)×\(image.height))", category: "Game")
        } catch {
            Log.error("Could not save screenshot: \(error)", category: "Game")
        }
    }

    // MARK: Saving

    private func save() {
        guard let storage, var meta else { return }
        meta.worldTime = worldTime
        meta.lastPlayed = Date()
        self.meta = meta
        do {
            try storage.saveMetadata(meta)
            let p = player.position
            try storage.savePlayer(PlayerSave(x: p.x, y: p.y, z: p.z, yaw: player.yaw, pitch: player.pitch, health: 20, hunger: 20,
                                              saturation: 5, air: 10, flying: player.flying, selectedSlot: inventory.selected, inventory: []),
                                   id: meta.id)
        } catch {
            Log.error("Could not save world: \(error)", category: "Save")
        }
        let queued = world.saveModifiedChunks()
        Log.info("Saved '\(meta.name)' (\(queued) chunks queued)", category: "Save")
    }

    private func shutdown() {
        setMouseCaptured(false)
        save()
        network?.disconnect()
        world.shutdown()
        jobs.shutdown()
    }
}
