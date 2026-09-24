import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

/// Playing on a friend's game (hosted on a Mac or another Windows PC): input, movement, building and
/// mining, survival, chat, name tags, day/night and rendering. Your own worlds run in `WinSolo`.
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
    private let audio: WinAudio?
    private let settings: SettingsStore
    private let jobs: JobSystem
    private let world: World
    private let player: PlayerController
    private let network: WinNetwork
    private let inventory: Inventory
    private let creative: Bool
    private let spawnPoint: DVec3
    /// True when the player closed the window (rather than returning to the title screen).
    private(set) var quitRequested = false
    private var pauseClick = false

    // Sound
    private var ambienceTimer = 6.0
    private var musicTimer = 20.0
    private var hitSoundTimer = 0.0

    private var running = true
    private var mouseCaptured = false
    private var worldTime: Double
    private var jumpPressed = false
    private var leftHeld = false
    private var attackQueued = false
    private var placeQueued = false
    private var screenshotQueued = false
    private var swingTimer = 0.0
    private var stateTimer = 0.0
    private var disconnectReason: String?

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

    // Hunger and air (Survival)
    private var hunger = 20.0
    private var saturation = 5.0
    private var exhaustion = 0.0
    private var starveTimer = 0.0
    private var air = 10.0
    private var drownTimer = 0.0

    // Inventory, crafting and containers
    private enum Screen: Equatable {
        case closed, inventory, crafting, container(BlockPos)
    }
    private enum SlotRef: Equatable {
        case inventory(Int), craft(Int), output, container(Int)
    }
    private struct ContainerView {
        var kind: String
        var slots: [ItemStack?]
        var cook: Double, cookTotal: Double, burnLeft: Double, burnTotal: Double
    }
    private let recipes: RecipeRegistry
    private var screen = Screen.closed
    private var cursorStack: ItemStack?
    private var craftGrid: [ItemStack?] = Array(repeating: nil, count: 4)
    private var containers: [BlockPos: ContainerView] = [:]
    private var mouse = SIMD2<Float>(0, 0)
    private var pendingClick: (button: SlotButton, shift: Bool)?
    private var hoveredSlot: SlotRef?

    private let startTime = Date.timeIntervalSinceReferenceDate
    private var lastFrame = Date.timeIntervalSinceReferenceDate
    private var titleTimer = 0.0
    private var framesThisSecond = 0
    private var fps = 0
    private var framesSinceReady = 0

    init(gl: GL, window: OpaquePointer, content: GameContent, audio: WinAudio?, settings: SettingsStore, options: Options,
         network: WinNetwork) {
        // Build everything in locals first: stored properties can't be read until all are set.
        let blocks = content.blocks, items = content.items, renderer = content.renderer
        let jobs = JobSystem.forWindows(blocks: blocks, fancyLeaves: settings.settings.graphicsQuality != .fast)
        let inventory = Inventory(registry: items)
        let welcome = network.welcome
        let creative = welcome.gameMode == "creative"
        let generator = WorldDimension.overworld.makeGenerator(seed: UInt64(welcome.seed) ?? 0)
        let world = World(registry: blocks, generator: generator, storage: nil, worldID: nil,
                          meshFactory: GLChunkMeshFactory(renderer: renderer), jobs: jobs, renderDistance: options.renderDistance ?? 8)
        world.remoteRequest = { network.requestChunks($0) }
        let player = PlayerController(position: DVec3(welcome.x, welcome.y, welcome.z))
        player.gameMode = creative ? .creative : .survival
        if creative {
            let names = ["grass", "dirt", "stone", "cobblestone", "planks", "log", "glass", "torch", "amber_lantern"]
            for (i, name) in names.enumerated() {
                if let id = items.id(named: name) { inventory.slots[i] = ItemStack(item: id, count: 64) }
            }
        }

        self.gl = gl
        self.window = window
        self.options = options
        self.blocks = blocks
        self.items = items
        self.recipes = content.recipes
        self.renderer = renderer
        self.audio = audio
        self.settings = settings
        self.jobs = jobs
        self.world = world
        self.player = player
        self.network = network
        self.inventory = inventory
        self.creative = creative
        spawnPoint = player.position
        worldTime = welcome.worldTime
        Log.info("Playing on '\(welcome.worldName)' in \(creative ? "Creative" : "Survival") at \(player.position)", category: "Game")
        audio?.apply(settings.settings)
    }

    // MARK: Loop

    /// Runs until the window closes. Returns the reason if the host disconnected us.
    func run() -> String? {
        if options.screenshotPath == nil { setMouseCaptured(true) }
        audio?.stopMusic()
        addChat("Joined \(network.welcome.worldName). Press T to chat.", now: Date.timeIntervalSinceReferenceDate)
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

    private func soundGroup(_ id: BlockID) -> String? {
        guard let group = blocks[id]?.sound, group != .none else { return nil }
        return group.rawValue
    }

    private func addChat(_ text: String, now: Double) {
        chatLines.append((text, now))
        if chatLines.count > 60 { chatLines.removeFirst(chatLines.count - 60) }
        Log.info("Chat: \(text)", category: "Net")
    }

    private func openChat() {
        guard !chatOpen else { return }
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
                quitRequested = true
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
                        if !text.isEmpty { network.sendChat(text) }
                        closeChat()
                    } else if code == Int(SDL_SCANCODE_BACKSPACE.rawValue), !chatInput.isEmpty {
                        chatInput.removeLast()
                    }
                    continue
                }
                guard !event.key.`repeat` else { continue }
                if screen != .closed {
                    if code == Int(SDL_SCANCODE_ESCAPE.rawValue) || code == Int(SDL_SCANCODE_E.rawValue) { closeScreen() }
                    continue
                }
                if code == Int(SDL_SCANCODE_ESCAPE.rawValue) {
                    setMouseCaptured(!mouseCaptured || dead)
                    audio?.play(mouseCaptured ? "ui_close" : "ui_open", volume: 0.45)
                } else if code == Int(SDL_SCANCODE_E.rawValue) {
                    if !dead { openScreen(.inventory) }
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
                mouse = SIMD2<Float>(event.motion.x, event.motion.y) * pixelScale()
                guard mouseCaptured else { continue }
                let sensitivity = 0.0022 * (0.25 + settings.settings.mouseSensitivity * 1.5)
                player.yaw -= Double(event.motion.xrel) * sensitivity
                player.pitch = max(-1.55, min(1.55, player.pitch - Double(event.motion.yrel) * sensitivity))
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue) {
                if screen != .closed {
                    let keys = SDL_GetKeyboardState(nil)
                    let shift = keys.map { $0[Int(SDL_SCANCODE_LSHIFT.rawValue)] || $0[Int(SDL_SCANCODE_RSHIFT.rawValue)] } ?? false
                    mouse = SIMD2<Float>(event.button.x, event.button.y) * pixelScale()
                    if event.button.button == 1 { pendingClick = (.left, shift) }
                    if event.button.button == 3 { pendingClick = (.right, shift) }
                } else if !mouseCaptured {
                    mouse = SIMD2<Float>(event.button.x, event.button.y) * pixelScale()
                    if dead || options.screenshotPath != nil {
                        setMouseCaptured(true)
                    } else if event.button.button == 1 {
                        pauseClick = true
                    }
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
        hitSoundTimer = max(0, hitSoundTimer - dt)
        audio?.update(dt: dt)
        handleNetwork(network, dt: dt, now: now)
        world.update(focus: player.position)
        let px = Int(floor(player.position.x)), pz = Int(floor(player.position.z))

        let controllable = mouseCaptured && !chatOpen && !dead && screen == .closed
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
        if !dead && world.isLoaded(px, pz) {
            player.update(dt: dt, input: input, world: world)
        }
        for event in player.events {
            switch event {
            case .footstep(let id):
                if let g = soundGroup(id) { audio?.play("step_\(g)", volume: player.isSneaking ? 0.12 : 0.28) }
            case .landed(let fall, let id):
                if fall > 3.5 && !creative && !player.inWater {
                    hurt(fall - 3, cause: "Fell from a high place", knockback: nil, now: now)
                    audio?.play("land", volume: 0.8)
                } else if fall > 1, let g = soundGroup(id) {
                    audio?.play("step_\(g)", volume: 0.45, pitch: 0.9)
                }
            case .jumped:
                exhaustion += player.isSprinting ? 0.2 : 0.05
            case .enteredWater:
                if player.velocity.y < -5 { audio?.play("splash", volume: 0.6) }
            default:
                break
            }
        }
        player.events.removeAll()

        if !creative && !dead { survivalTick(dt: dt, now: now) }
        updateAmbience(dt: dt)

        if controllable {
            interact(dt: dt)
        } else {
            breakingPos = nil
            breakProgress = 0
        }
        attackQueued = false
        placeQueued = false

        titleTimer += dt
        framesThisSecond += 1
        if titleTimer >= 1 {
            fps = framesThisSecond
            framesThisSecond = 0
            titleTimer = 0
            SDL_SetWindowTitle(window, "DinoCraft · \(fps) FPS · \(network.welcome.worldName)")
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

        if attackQueued, entityCloser, let entity, attackCooldown <= 0 {
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
            audio?.play("hurt", volume: 0.6, pitch: 1.1)
            exhaustion += 0.1
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
                if hitSoundTimer <= 0, let g = soundGroup(hit.id) {
                    audio?.play("hit_\(g)", volume: 0.3, pitch: 0.8)
                    hitSoundTimer = 0.22
                }
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

        if placeQueued { useItem(target) }
    }

    private func breakBlock(_ hit: RaycastHit, info: BlockInfo) {
        guard world.setBlock(hit.block, Blocks.air) else { return }
        if let g = soundGroup(hit.id) { audio?.play("break_\(g)", volume: 0.8) }
        network.sendBlock(hit.block, Blocks.air, harvest: !creative && canHarvest(info))
        exhaustion += 0.005
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
        if let g = soundGroup(blockID) { audio?.play("place_\(g)", volume: 0.8) }
        network.sendBlock(cell, blockID, harvest: false)
        swingTimer = 0.25
        if !creative { inventory.consumeSelected() }
    }

    private func entityUnderCrosshair(maxDistance: Double) -> (target: EntityTarget, distance: Double)? {
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
        audio?.play(health <= 0 ? "death" : "hurt", volume: 0.8)
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
        hunger = 20
        saturation = 5
        air = 10
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
                    audio?.play("pickup", volume: 0.35, pitch: Float.random(in: 1.0...1.4))
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
            case .containerData(let m):
                let slots: [ItemStack?] = m.slots.map { entry in
                    entry.flatMap { s in items.id(named: s.item).map { ItemStack(item: $0, count: s.count, damage: s.damage ?? 0) } }
                }
                containers[BlockPos(m.x, m.y, m.z)] = ContainerView(kind: m.kind, slots: slots, cook: m.cook, cookTotal: m.cookTotal,
                                                                    burnLeft: m.burnLeft, burnTotal: m.burnTotal)
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

    /// Animated players and creatures as camera-relative triangles.
    private func entityModels(camera: WinCamera, time: Double) -> [Float] {
        var v: [Float] = []
        func rel(_ p: DVec3) -> SIMD3<Float>? {
            let d = p - camera.position
            guard d.x * d.x + d.z * d.z < 110 * 110 else { return nil }
            return SIMD3(Float(d.x), Float(d.y), Float(d.z))
        }
        func player(_ e: RemoteEntity) {
            guard e.dying == 0, let r = rel(e.position) else { return }
            CreatureModels.appendPlayer(&v, name: e.name, at: r, yaw: Float(e.yaw), pitch: e.pitch, walk: e.walk, moving: e.moving,
                                        sneaking: e.sneaking, swing: e.swing, hurt: e.hurt)
        }
        func creature(_ e: RemoteEntity) {
            guard let r = rel(e.position) else { return }
            CreatureModels.appendCreature(&v, kind: e.kind, at: r, yaw: Float(e.yaw), walk: e.walk, amount: e.moving, lunge: e.lunge,
                                          hurt: e.hurt, dying: e.dying, variant: e.variant, seed: Double(e.id % 997) * 0.61, time: time)
        }
        for p in network.players.values { player(p) }
        for m in network.mobs.values { creature(m) }
        return v
    }

    private func iconLayer(_ item: ItemID) -> Float { renderer.iconLayer(item, items: items, blocks: blocks) }

    private func buildUI(width W: Float, height H: Float, camera: WinCamera, now: Double) -> [Float] {
        var ui = UIBuilder()
        let s = max(1, min(W / 1280, H / 720))
        let small = max(1, (2 * s).rounded())
        let white = SIMD4<Float>(1, 1, 1, 1)

        // Name tags over other players
        let viewProj = camera.viewProjection(aspect: W / max(1, H))
        for p in network.players.values where p.dying == 0 {
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
        if !creative {
            let shown = health
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

        // Hunger and air (Survival)
        if !creative {
            let shown = hunger
            for i in 0..<10 {
                let fx = x0 + total - Float(i + 1) * 8 * small, fy = y0 - 12 * s - 7 * small
                let value = shown / 2 - Double(i)
                ui.text("\u{25CF}", x: fx, y: fy, scale: small, color: SIMD4(0.12, 0.06, 0.02, 0.85), shadow: false)
                if value >= 1 {
                    ui.text("\u{25CF}", x: fx, y: fy, scale: small, color: SIMD4(0.95, 0.55, 0.15, 1), shadow: false)
                } else if value > 0 {
                    ui.text("\u{25CF}", x: fx, y: fy, scale: small, color: SIMD4(0.7, 0.42, 0.2, 1), shadow: false)
                }
            }
            if !creative && air < 10 {
                for i in 0..<max(0, Int(ceil(air))) {
                    ui.text("o", x: x0 + total - Float(i + 1) * 8 * small, y: y0 - 12 * s - 17 * small, scale: small,
                            color: SIMD4(0.55, 0.8, 1, 1), shadow: false)
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
        let status = "\(network.welcome.worldName) - \(network.players.count + 1) playing - T to chat"
        ui.text(status, x: 12 * s, y: 12 * s, scale: small, color: SIMD4(1, 1, 1, 0.8))

        // Damage flash, death screen, paused hint
        if damageFlash > 0 { ui.rect(0, 0, W, H, SIMD4(0.6, 0, 0, Float(damageFlash) * 0.3)) }
        if dead {
            ui.rect(0, 0, W, H, SIMD4(0.25, 0, 0, 0.6))
            let big = max(1, (7 * s).rounded())
            ui.centeredText("YOU DIED", centerX: W / 2, y: H * 0.35, scale: big, color: SIMD4(1, 0.35, 0.35, 1))
            ui.centeredText(deathMessage, centerX: W / 2, y: H * 0.35 + 12 * big, scale: small, color: white)
            ui.centeredText("Press Space to respawn", centerX: W / 2, y: H * 0.35 + 12 * big + 18 * small, scale: small, color: white)
        }
        if screen != .closed {
            buildScreenUI(&ui, width: W, height: H, scale: s)
        } else if !mouseCaptured && !dead && !chatOpen && options.screenshotPath == nil {
            buildPauseMenu(&ui, width: W, height: H, scale: s)
        }
        return ui.vertices
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
                        width: w, height: h, ui: ui, models: entityModels(camera: camera, time: now - startTime))

        if let path = options.screenshotPath {
            let center = ChunkPos(Int32(floor(player.position.x / 16)), Int32(floor(player.position.z / 16)))
            let ready = world.readiness(around: center, radius: 3)
            if ready.meshed == ready.total { framesSinceReady += 1 }
            let timedOut = now - startTime > 150
            if framesSinceReady >= options.frames || timedOut {
                if timedOut { Log.warning("Screenshot taken before the world finished loading (\(ready.meshed)/\(ready.total) chunks)", category: "Game") }
                saveScreenshot(to: URL(fileURLWithPath: path), width: w, height: h)
                Log.info("Automated check: \(renderer.visibleChunks) chunks visible, \(world.slots.count) loaded", category: "Game")
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

    private func shutdown() {
        setMouseCaptured(false)
        audio?.stopLoops()
        network.disconnect()
        world.shutdown()
        jobs.shutdown()
    }
}

// MARK: - Hunger, item use, inventory, crafting and containers

extension WinGame {
    /// Hunger, healing, starvation and drowning, following the Mac rules.
    private func survivalTick(dt: Double, now: Double) {
        let difficulty = network.welcome.difficulty
        let peaceful = difficulty == "peaceful"
        if player.isSprinting && player.onGround { exhaustion += player.horizontalSpeed * dt * 0.1 }
        if peaceful {
            exhaustion = 0
            hunger = 20
        }
        while exhaustion >= 4 {
            exhaustion -= 4
            if saturation > 0 { saturation = max(0, saturation - 1) } else { hunger = max(0, hunger - 1) }
        }
        if hunger >= 18 && health < 20 {
            regenTimer += dt
            if regenTimer >= (peaceful ? 1 : 3.5) {
                regenTimer = 0
                health = min(20, health + 1)
                exhaustion += 1.5
            }
        } else {
            regenTimer = 0
        }
        if hunger <= 0 {
            starveTimer += dt
            if starveTimer >= 4 {
                starveTimer = 0
                let floorHealth = difficulty == "hard" ? 0.0 : (difficulty == "normal" ? 1.0 : 10.0)
                if health > floorHealth {
                    hurtCooldown = 0
                    hurt(1, cause: "Starved in the wilderness", knockback: nil, now: now)
                }
            }
        }
        let eye = player.eyePosition
        if player.headInWater && world.block(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))) == Blocks.water {
            air -= dt
            if air < 0 {
                drownTimer += dt
                if drownTimer >= 1 {
                    drownTimer = 0
                    hurtCooldown = 0
                    hurt(2, cause: "Drowned", knockback: nil, now: now)
                }
            }
        } else {
            air = min(10, air + dt * 5)
            drownTimer = 0
        }
    }

    /// Right-click: open benches and containers, eat food, or place the held block.
    private func useItem(_ target: RaycastHit?) {
        if let hit = target, !player.isSneaking {
            if hit.id == Blocks.craftingBench {
                openScreen(.crafting)
                return
            }
            if let name = blocks[hit.id]?.name, name.hasPrefix("chest") || name.hasPrefix("furnace") {
                network.openContainer(hit.block)
                openScreen(.container(hit.block))
                return
            }
        }
        if !creative, let stack = inventory.selectedStack, let food = items[stack.item]?.food {
            guard hunger < 20 else { return }
            hunger = min(20, hunger + Double(food.hunger))
            saturation = min(hunger, saturation + Double(food.saturation))
            inventory.consumeSelected()
            swingTimer = 0.25
            audio?.play("eat", volume: 0.7)
            return
        }
        if let hit = target { place(hit) }
    }

    /// Ambience loops, occasional birds and dinosaur calls, and music, following the Mac rules.
    private func updateAmbience(dt: Double) {
        guard let audio, options.screenshotPath == nil else { return }
        let night = SkyState.at(worldTime: worldTime).daylight < 0.45
        let underground = player.position.y < 48
        let surface = !underground && !player.headInWater
        audio.setLoop("amb_underwater", volume: player.headInWater ? 0.8 : 0)
        audio.setLoop("amb_cave", volume: underground && !player.headInWater ? 0.7 : 0)
        audio.setLoop("amb_wind", volume: surface ? Float(min(0.8, 0.22 + max(0, player.position.y - 85) / 90)) : 0)
        audio.setLoop("amb_crickets", volume: surface && night ? 0.45 : 0)
        ambienceTimer -= dt
        if ambienceTimer <= 0 {
            ambienceTimer = Double.random(in: 4...11)
            if underground {
                audio.play("amb_drip", volume: 0.5, pitch: Float.random(in: 0.85...1.1))
            } else if surface && !night {
                audio.play("amb_bird", volume: 0.35)
            }
            if surface && Double.random(in: 0..<1) < 0.06 {
                audio.play(Bool.random() ? "amb_dino_low" : "amb_dino_high", volume: 0.4, pitch: Float.random(in: 0.9...1.05))
            }
        }
        musicTimer -= dt
        if !audio.isMusicPlaying && musicTimer <= 0 {
            let pool = underground ? ["deep_strata"] : (night ? ["amber_dusk", "deep_strata"] : ["fernlight", "titan_valley", "amber_dusk"])
            audio.playMusic(pool.randomElement()!)
            musicTimer = Double.random(in: 120...260)
        }
    }

    private func buildPauseMenu(_ ui: inout UIBuilder, width W: Float, height H: Float, scale s: Float) {
        var input = MenuInput()
        input.mouse = mouse
        input.clicked = pauseClick
        pauseClick = false
        let small = max(1, (2 * s).rounded())
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.5))
        ui.centeredText("Game Paused", centerX: W / 2, y: H * 0.16, scale: max(1, (5 * s).rounded()), color: SIMD4(1, 0.85, 0.55, 1))
        let bw = 400 * s, bh = 46 * s, gap = 12 * s
        var y = H * 0.34
        if ui.button("Back to Game", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: s, input: input, primary: true) {
            audio?.play("ui_click", volume: 0.5)
            setMouseCaptured(true)
        }
        y += bh + gap
        if ui.button("Leave Game", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: s, input: input) {
            audio?.play("ui_click", volume: 0.5)
            running = false
        }
        y += bh + 24 * s
        ui.centeredText("Playing on \(network.welcome.worldName)", centerX: W / 2, y: y, scale: small, color: SIMD4(1, 1, 1, 0.9))
    }

    private func pixelScale() -> Float {
        var lw: Int32 = 0, lh: Int32 = 0, pw: Int32 = 0, ph: Int32 = 0
        _ = SDL_GetWindowSize(window, &lw, &lh)
        _ = SDL_GetWindowSizeInPixels(window, &pw, &ph)
        return lw > 0 ? Float(pw) / Float(lw) : 1
    }

    private var gridSize: Int { craftGrid.count == 9 ? 3 : 2 }

    private func openScreen(_ next: Screen) {
        screen = next
        audio?.play("ui_open", volume: 0.45)
        let size = next == .crafting ? 3 : 2
        craftGrid = Array(repeating: nil, count: size * size)
        leftHeld = false
        breakingPos = nil
        breakProgress = 0
        setMouseCaptured(false)
        var w: Int32 = 0, h: Int32 = 0
        _ = SDL_GetWindowSizeInPixels(window, &w, &h)
        mouse = SIMD2(Float(w) / 2, Float(h) / 2)
    }

    private func closeScreen() {
        for stack in craftGrid.compactMap({ $0 }) { inventory.add(stack) }
        craftGrid = Array(repeating: nil, count: craftGrid.count)
        if let cursor = cursorStack {
            inventory.add(cursor)
            cursorStack = nil
        }
        screen = .closed
        audio?.play("ui_close", volume: 0.45)
        hoveredSlot = nil
        pendingClick = nil
        if options.screenshotPath == nil { setMouseCaptured(true) }
    }

    private func netStack(_ stack: ItemStack?) -> Wire.NetStack? {
        guard let stack, let info = items[stack.item] else { return nil }
        return Wire.NetStack(item: info.name, count: stack.count, damage: stack.damage > 0 ? stack.damage : nil)
    }

    private func stack(at ref: SlotRef) -> ItemStack? {
        switch ref {
        case .inventory(let i): return inventory.slots[i]
        case .craft(let i): return i < craftGrid.count ? craftGrid[i] : nil
        case .output: return recipes.match(grid: craftGrid, size: gridSize)?.result
        case .container(let i):
            guard case .container(let pos) = screen, let view = containers[pos], i < view.slots.count else { return nil }
            return view.slots[i]
        }
    }

    private func setStack(_ ref: SlotRef, _ value: ItemStack?) {
        switch ref {
        case .inventory(let i):
            inventory.slots[i] = value
            inventory.markChanged()
        case .craft(let i):
            if i < craftGrid.count { craftGrid[i] = value }
        case .output:
            break
        case .container(let i):
            guard case .container(let pos) = screen, var view = containers[pos], i < view.slots.count else { return }
            view.slots[i] = value
            containers[pos] = view
            network.setContainer(pos, slots: view.slots.map { netStack($0) })
        }
    }

    private func clickSlot(_ ref: SlotRef, button: SlotButton, shift: Bool) {
        if ref == .output {
            takeCraftResult(shift: shift)
            return
        }
        if shift, let moving = stack(at: ref) {
            switch ref {
            case .inventory(let i):
                if case .container(let pos) = screen, let view = containers[pos] {
                    var slots = view.slots
                    let indices = view.kind == "furnace" ? [0] : Array(0..<slots.count)
                    let left = SlotInteraction.quickMove(moving, into: &slots, indices: indices, maxStack: inventory.maxStack)
                    containers[pos]?.slots = slots
                    network.setContainer(pos, slots: slots.map { netStack($0) })
                    setStack(ref, left)
                } else {
                    var slots = inventory.slots
                    let left = SlotInteraction.quickMove(moving, into: &slots, indices: i < 9 ? Array(9..<36) : Array(0..<9), maxStack: inventory.maxStack)
                    slots[i] = left
                    inventory.slots = slots
                    inventory.markChanged()
                }
            default:
                var slots = inventory.slots
                let left = SlotInteraction.quickMove(moving, into: &slots, indices: Array(9..<36) + Array(0..<9), maxStack: inventory.maxStack)
                inventory.slots = slots
                inventory.markChanged()
                setStack(ref, left)
            }
            return
        }
        var value = stack(at: ref)
        SlotInteraction.click(&value, cursor: &cursorStack, button: button, maxStack: inventory.maxStack)
        setStack(ref, value)
    }

    private func takeCraftResult(shift: Bool) {
        guard let recipe = recipes.match(grid: craftGrid, size: gridSize) else { return }
        let result = recipe.result
        if shift {
            var crafted = 0
            while crafted < 64, let r = recipes.match(grid: craftGrid, size: gridSize), r.result.item == result.item {
                var slots = inventory.slots
                guard SlotInteraction.quickMove(r.result, into: &slots, indices: Array(0..<36), maxStack: inventory.maxStack) == nil else { break }
                inventory.slots = slots
                RecipeRegistry.consumeIngredients(grid: &craftGrid)
                crafted += 1
            }
            inventory.markChanged()
            return
        }
        if let cursor = cursorStack {
            guard cursor.canStack(with: result), cursor.count + result.count <= inventory.maxStack(cursor.item) else { return }
            cursorStack?.count += result.count
        } else {
            cursorStack = result
        }
        RecipeRegistry.consumeIngredients(grid: &craftGrid)
        audio?.play("craft", volume: 0.6)
    }

    private func buildScreenUI(_ ui: inout UIBuilder, width W: Float, height H: Float, scale s: Float) {
        let small = max(1, (2 * s).rounded())
        let slot = 40 * s, gap = 4 * s, step = slot + gap, pad = 16 * s
        let gridWidth = 9 * step - gap
        let panelW = gridWidth + 2 * pad
        let title: String
        let topHeight: Float
        switch screen {
        case .inventory:
            title = "Inventory"
            topHeight = 2 * step
        case .crafting:
            title = "Crafting Bench"
            topHeight = 3 * step
        case .container(let pos):
            let furnace = containers[pos]?.kind == "furnace"
            title = furnace ? "Furnace" : "Chest"
            topHeight = furnace ? 2 * step : 3 * step
        case .closed:
            return
        }
        let titleHeight = 12 * small
        let panelH = pad + titleHeight + topHeight + 14 * s + 3 * step + 8 * s + slot + pad
        let px = W / 2 - panelW / 2, py = H / 2 - panelH / 2
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.45))
        ui.rect(px, py, panelW, panelH, SIMD4(0.09, 0.06, 0.14, 0.96))
        ui.text(title, x: px + pad, y: py + pad, scale: small, color: SIMD4(1, 0.85, 0.55, 1))

        hoveredSlot = nil
        var hoveredStack: ItemStack?
        let white = SIMD4<Float>(1, 1, 1, 1)
        func slotView(_ ref: SlotRef, _ x: Float, _ y: Float, accent: Bool = false) {
            let hovered = mouse.x >= x && mouse.x < x + slot && mouse.y >= y && mouse.y < y + slot
            let background: SIMD4<Float> = accent ? SIMD4(0.4, 0.24, 0.05, 1) : (hovered ? SIMD4(0.28, 0.22, 0.42, 1) : SIMD4(0.03, 0.02, 0.06, 0.95))
            ui.rect(x, y, slot, slot, background)
            if hovered {
                hoveredSlot = ref
                hoveredStack = stack(at: ref)
            }
            guard let st = stack(at: ref) else { return }
            ui.icon(x + 5 * s, y + 5 * s, slot - 10 * s, layer: iconLayer(st.item))
            if st.count > 1 {
                let count = "\(st.count)"
                ui.text(count, x: x + slot - 2 * s - UIBuilder.textWidth(count, scale: small), y: y + slot - 2 * s - 7 * small, scale: small, color: white)
            }
            if let tool = items[st.item]?.tool, st.damage > 0 {
                let fraction = max(0, 1 - Float(st.damage) / Float(max(1, tool.durability)))
                ui.rect(x + 5 * s, y + slot - 5 * s, (slot - 10 * s) * fraction, 2 * s, SIMD4(1 - fraction, fraction, 0.1, 1))
            }
        }

        let top = py + pad + titleHeight + 4 * s
        let left = px + pad
        switch screen {
        case .inventory, .crafting:
            let size = gridSize
            let gx = left + gridWidth / 2 - Float(size) * step - 20 * s
            let gy = top + (topHeight - Float(size) * step) / 2
            for r in 0..<size {
                for c in 0..<size { slotView(.craft(r * size + c), gx + Float(c) * step, gy + Float(r) * step) }
            }
            let arrowX = gx + Float(size) * step + 8 * s
            ui.text("->", x: arrowX, y: top + topHeight / 2 - 3.5 * small, scale: small, color: SIMD4(1, 0.8, 0.4, 1))
            slotView(.output, arrowX + 12 * small + 8 * s, top + topHeight / 2 - slot / 2,
                     accent: recipes.match(grid: craftGrid, size: size) != nil)
        case .container(let pos):
            if let view = containers[pos] {
                if view.kind == "furnace" {
                    let fx = left + gridWidth / 2 - 70 * s
                    slotView(.container(0), fx, top)
                    slotView(.container(1), fx, top + step)
                    let cook = view.cookTotal > 0 ? Float(min(1, view.cook / view.cookTotal)) : 0
                    let burn = view.burnTotal > 0 ? Float(min(1, view.burnLeft / view.burnTotal)) : 0
                    ui.rect(fx + step + 8 * s, top + slot / 2 - 3 * s, 48 * s, 6 * s, SIMD4(0, 0, 0, 0.6))
                    ui.rect(fx + step + 8 * s, top + slot / 2 - 3 * s, 48 * s * cook, 6 * s, SIMD4(1, 0.6, 0.15, 1))
                    ui.rect(fx + step + 8 * s, top + step + slot / 2 - 3 * s, 48 * s, 6 * s, SIMD4(0, 0, 0, 0.6))
                    ui.rect(fx + step + 8 * s, top + step + slot / 2 - 3 * s, 48 * s * burn, 6 * s, SIMD4(1, 0.35, 0.1, 1))
                    slotView(.container(2), fx + step + 64 * s, top + step / 2)
                } else {
                    for i in 0..<min(27, view.slots.count) { slotView(.container(i), left + Float(i % 9) * step, top + Float(i / 9) * step) }
                }
            } else {
                ui.text("Opening...", x: left, y: top + 10 * s, scale: small, color: SIMD4(1, 1, 1, 0.8))
            }
        case .closed:
            break
        }

        let inventoryY = top + topHeight + 14 * s
        for i in 9..<Inventory.size {
            let index = i - 9
            slotView(.inventory(i), left + Float(index % 9) * step, inventoryY + Float(index / 9) * step)
        }
        let hotbarY = inventoryY + 3 * step + 8 * s
        for i in 0..<Inventory.hotbarCount { slotView(.inventory(i), left + Float(i) * step, hotbarY) }

        if let click = pendingClick {
            pendingClick = nil
            if let ref = hoveredSlot { clickSlot(ref, button: click.button, shift: click.shift) }
        }
        if let cursor = cursorStack {
            ui.icon(mouse.x - slot / 2 + 5 * s, mouse.y - slot / 2 + 5 * s, slot - 10 * s, layer: iconLayer(cursor.item))
            if cursor.count > 1 {
                let count = "\(cursor.count)"
                ui.text(count, x: mouse.x + slot / 2 - 2 * s - UIBuilder.textWidth(count, scale: small), y: mouse.y + slot / 2 - 2 * s - 7 * small,
                        scale: small, color: white)
            }
        } else if let st = hoveredStack, let info = items[st.item] {
            let name = info.displayName
            let width = UIBuilder.textWidth(name, scale: small)
            ui.rect(mouse.x + 14 * s, mouse.y - 6 * s, width + 8 * small, 11 * small, SIMD4(0.05, 0.03, 0.1, 0.96))
            ui.text(name, x: mouse.x + 14 * s + 4 * small, y: mouse.y - 6 * s + 2 * small, scale: small, color: white)
        }
    }
}
