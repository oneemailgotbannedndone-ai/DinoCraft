import Foundation
import CSDL3
import DinoCraftCore

/// The Windows game loop: input, player movement, block building, day/night, saving,
/// multiplayer (joining a Mac host) and rendering.
final class WinGame {
    private let gl: GL
    private let window: OpaquePointer
    private let options: Options
    private let blocks: BlockRegistry
    private let renderer: WinRenderer
    private let storage: WorldStorage?
    private var meta: WorldMetadata?
    private let jobs: WinJobSystem
    private let world: WinWorld
    private let player: PlayerController
    private let network: WinNetwork?

    private var running = true
    private var mouseCaptured = false
    private var needsSpawnResolve: Bool
    private var worldTime: Double
    private let hotbar: [BlockID]
    private var selected = 0
    private var jumpPressed = false
    private var breakQueued = false
    private var placeQueued = false
    private var screenshotQueued = false
    private var swingTimer = 0.0
    private var stateTimer = 0.0
    private var notice: (text: String, until: Double)?
    private var disconnectReason: String?
    private var demoEntities: [RemoteEntity] = []

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
        let renderer = try WinRenderer(gl: gl, blocks: blocks)
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let jobs = WinJobSystem(workerCount: workers, registry: blocks)

        let storage: WorldStorage?
        let meta: WorldMetadata?
        let world: WinWorld
        let player: PlayerController
        var selectedSlot = 0
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
                selectedSlot = max(0, min(8, saved.selectedSlot))
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
        player.gameMode = .creative
        world.uploadMesh = { renderer.makeMesh($0) }
        world.releaseMesh = { renderer.deleteMesh($0) }
        let names = ["grass", "dirt", "stone", "cobblestone", "planks", "log", "glass", "torch", "amber_lantern"]

        self.gl = gl
        self.window = window
        self.options = options
        self.blocks = blocks
        self.renderer = renderer
        self.storage = storage
        self.meta = meta
        self.jobs = jobs
        self.world = world
        self.player = player
        self.network = network
        hotbar = names.map { blocks.id(named: $0) ?? Blocks.stone }
        selected = selectedSlot
        needsSpawnResolve = resolveSpawn
        worldTime = time
        if let network {
            Log.info("Playing on '\(network.welcome.worldName)' at \(player.position)", category: "Game")
        } else {
            Log.info("World '\(meta?.name ?? "?")' opened at \(player.position)", category: "Game")
        }
    }

    // MARK: Loop

    /// Runs until the window closes. Returns the reason if the host disconnected us.
    func run() -> String? {
        if options.screenshotPath == nil { setMouseCaptured(true) }
        while running {
            let now = Date.timeIntervalSinceReferenceDate
            let dt = min(0.1, now - lastFrame)
            lastFrame = now
            pollEvents()
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

    private func showNotice(_ text: String, now: Double) {
        notice = (text, now + 8)
        titleTimer = 1
        Log.info("Notice: \(text)", category: "Game")
        print("  \(text)")
    }

    private func pollEvents() {
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            let type = UInt32(event.type)
            if type == UInt32(SDL_EVENT_QUIT.rawValue) {
                running = false
            } else if type == UInt32(SDL_EVENT_KEY_DOWN.rawValue) {
                guard !event.key.`repeat` else { continue }
                let code = Int(event.key.scancode.rawValue)
                if code == Int(SDL_SCANCODE_ESCAPE.rawValue) {
                    setMouseCaptured(!mouseCaptured)
                } else if code == Int(SDL_SCANCODE_SPACE.rawValue) {
                    jumpPressed = true
                } else if code == Int(SDL_SCANCODE_F2.rawValue) {
                    screenshotQueued = true
                } else if code >= Int(SDL_SCANCODE_1.rawValue) && code <= Int(SDL_SCANCODE_9.rawValue) {
                    selected = code - Int(SDL_SCANCODE_1.rawValue)
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
                    breakQueued = true
                } else if event.button.button == 3 {
                    placeQueued = true
                }
            } else if type == UInt32(SDL_EVENT_MOUSE_WHEEL.rawValue) {
                if event.wheel.y < 0 { selected = (selected + 1) % hotbar.count }
                if event.wheel.y > 0 { selected = (selected + hotbar.count - 1) % hotbar.count }
            } else if type == UInt32(SDL_EVENT_WINDOW_FOCUS_LOST.rawValue) {
                setMouseCaptured(false)
            }
        }
    }

    private func update(dt: Double, now: Double) {
        worldTime += dt
        swingTimer = max(0, swingTimer - dt)
        if let network { handleNetwork(network, dt: dt, now: now) }
        world.update(focus: player.position, now: now)

        let px = Int(floor(player.position.x)), pz = Int(floor(player.position.z))
        if needsSpawnResolve, world.isLoaded(px, pz), let y = world.findStandingY(px, pz, near: Int(player.position.y)) {
            player.teleport(to: DVec3(player.position.x, Double(y), player.position.z))
            needsSpawnResolve = false
            Log.info("Spawn resolved at \(player.position)", category: "Game")
        }

        var input = MovementInput()
        if mouseCaptured, let keys = SDL_GetKeyboardState(nil) {
            func down(_ scancode: SDL_Scancode) -> Bool { keys[Int(scancode.rawValue)] }
            input.forward = (down(SDL_SCANCODE_W) ? 1 : 0) - (down(SDL_SCANCODE_S) ? 1 : 0)
            input.strafe = (down(SDL_SCANCODE_D) ? 1 : 0) - (down(SDL_SCANCODE_A) ? 1 : 0)
            input.jump = down(SDL_SCANCODE_SPACE)
            input.sprint = down(SDL_SCANCODE_LCTRL)
            input.sneak = down(SDL_SCANCODE_LSHIFT)
        }
        input.jumpPressed = jumpPressed
        jumpPressed = false
        if !needsSpawnResolve && world.isLoaded(px, pz) {
            player.update(dt: dt, input: input, world: world)
        }
        player.events.removeAll()

        let target = VoxelPhysics.raycast(world, origin: player.eyePosition, direction: player.lookDirection, maxDistance: 6.5)
        if breakQueued, let hit = target, blocks[hit.id]?.isBreakable == true {
            if world.setBlock(hit.block, Blocks.air) {
                network?.sendBlock(hit.block, Blocks.air)
                swingTimer = 0.25
            }
        }
        if placeQueued, let hit = target {
            var cell = hit.adjacent
            if blocks[hit.id]?.replaceable == true { cell = hit.block }
            let id = hotbar[selected]
            let current = world.block(cell)
            let free = current == Blocks.air || blocks[current]?.replaceable == true
            let origin = DVec3(Double(cell.x), Double(cell.y), Double(cell.z))
            let blocksPlayer = blocks.isSolid[Int(id)] && DBox(min: origin, max: origin + DVec3(1, 1, 1)).intersects(player.box)
            if free && !blocksPlayer && world.setBlock(cell, id) {
                network?.sendBlock(cell, id)
                swingTimer = 0.25
            }
        }
        breakQueued = false
        placeQueued = false

        autosaveTimer += dt
        if autosaveTimer > 60 {
            autosaveTimer = 0
            save()
        }
        titleTimer += dt
        framesThisSecond += 1
        if titleTimer >= 1 {
            if titleTimer >= 1 && framesThisSecond > 1 { fps = framesThisSecond }
            framesThisSecond = 0
            titleTimer = 0
            let p = player.position
            var title = "DinoCraft · \(fps) FPS · \(Int(floor(p.x))), \(Int(floor(p.y))), \(Int(floor(p.z)))"
            if let network { title += " · \(network.welcome.worldName) (\(network.players.count + 1) playing)" }
            if let notice, now < notice.until { title += " · \(notice.text)" }
            if !mouseCaptured { title += " · click to play" }
            SDL_SetWindowTitle(window, title)
        }
    }

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
                showNotice("Following the host to another dimension", now: now)
            case .notice(let text):
                showNotice(text, now: now)
            case .disconnected(let reason):
                disconnectReason = reason
                running = false
            }
        }
        network.updateEntities(dt: dt)
        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            network.sendState(player: player, swinging: swingTimer > 0, held: blocks[hotbar[selected]]?.itemName)
        }
    }

    private func entityBoxes() -> [WinRenderer.Box] {
        var boxes: [WinRenderer.Box] = []
        if let network {
            for p in network.players.values { boxes += EntityShapes.player(p) }
            for m in network.mobs.values { boxes += EntityShapes.mob(m) }
        }
        for e in demoEntities { boxes += e.kind == "player" ? EntityShapes.player(e) : EntityShapes.mob(e) }
        return boxes
    }

    /// Automated check: sample players and creatures a few blocks in front of the camera.
    private func placeDemoEntities() {
        let look = player.lookDirection
        let forward = simd_normalize(DVec3(look.x, 0, look.z))
        let right = DVec3(-forward.z, 0, forward.x)
        let samples: [(String, Double, Double)] = [("player", 5, -1.5), ("raptor", 7, 2), ("trikey", 9, -4), ("rex", 16, 3), ("sheep", 6, 4)]
        for (i, sample) in samples.enumerated() {
            let spot = player.position + forward * sample.1 + right * sample.2
            let x = Int(floor(spot.x)), z = Int(floor(spot.z))
            let y = world.findStandingY(x, z, near: Int(player.position.y)) ?? Int(player.position.y)
            let yaw = atan2(forward.x, forward.z)
            demoEntities.append(RemoteEntity(id: i + 1, kind: sample.0, name: sample.0, position: DVec3(spot.x, Double(y), spot.z), yaw: yaw))
        }
    }

    private func draw(now: Double) {
        var w: Int32 = 0, h: Int32 = 0
        _ = SDL_GetWindowSizeInPixels(window, &w, &h)
        var camera = WinCamera()
        camera.position = player.eyePosition
        camera.yaw = player.yaw
        camera.pitch = player.pitch
        let overlay = WinRenderer.Overlay(hotbarLayers: hotbar.map { blocks.faceLayers[Int($0) * 6 + BlockFace.south.rawValue] },
                                          selected: selected, showCrosshair: true)
        renderer.render(world: world, camera: camera, sky: SkyState.at(worldTime: worldTime), time: now - startTime, now: now,
                        width: w, height: h, overlay: overlay, boxes: entityBoxes())

        if let path = options.screenshotPath {
            let center = ChunkPos(Int32(floor(player.position.x / 16)), Int32(floor(player.position.z / 16)))
            let ready = world.readiness(around: center, radius: 3)
            if !needsSpawnResolve && ready.meshed == ready.total {
                if options.demoEntities && demoEntities.isEmpty { placeDemoEntities() }
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
                                              saturation: 5, air: 10, flying: player.flying, selectedSlot: selected, inventory: []),
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
