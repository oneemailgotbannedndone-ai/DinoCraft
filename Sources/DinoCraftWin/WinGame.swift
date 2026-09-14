import Foundation
import CSDL3
import DinoCraftCore

/// The Windows game loop: input, player movement, block building, day/night, saving and rendering.
final class WinGame {
    private let gl: GL
    private let window: OpaquePointer
    private let options: Options
    private let blocks: BlockRegistry
    private let renderer: WinRenderer
    private let storage: WorldStorage
    private var meta: WorldMetadata
    private let jobs: WinJobSystem
    private let world: WinWorld
    private let player: PlayerController

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

    private let startTime = Date.timeIntervalSinceReferenceDate
    private var lastFrame = Date.timeIntervalSinceReferenceDate
    private var autosaveTimer = 0.0
    private var titleTimer = 0.0
    private var framesThisSecond = 0
    private var fps = 0
    private var framesSinceReady = 0

    init(gl: GL, window: OpaquePointer, options: Options) throws {
        // Build everything in locals first: stored properties can't be read until all are set.
        let blocks = try BlockRegistry.loadDefault()
        let renderer = try WinRenderer(gl: gl, blocks: blocks)
        let storage = WorldStorage()

        let worldName = "Windows World"
        let meta: WorldMetadata
        if let existing = storage.listWorlds().first(where: { $0.name == worldName }) {
            meta = existing
        } else {
            meta = try storage.createWorld(name: worldName, seedText: options.seed, gameMode: .creative, difficulty: .normal)
            Log.info("Created world '\(worldName)' with seed \(meta.seedText)", category: "Game")
        }

        let generator = WorldDimension.overworld.makeGenerator(seed: meta.numericSeed)
        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 1)
        let jobs = WinJobSystem(workerCount: workers, registry: blocks)
        let world = WinWorld(registry: blocks, generator: generator, storage: storage, worldID: meta.id, jobs: jobs,
                             renderDistance: options.renderDistance)

        let player: PlayerController
        var selectedSlot = 0
        var resolveSpawn: Bool
        if let saved = storage.loadPlayer(id: meta.id) {
            player = PlayerController(position: DVec3(saved.x, saved.y, saved.z))
            player.yaw = saved.yaw
            player.pitch = saved.pitch
            selectedSlot = max(0, min(8, saved.selectedSlot))
            resolveSpawn = false
        } else {
            let column = generator.findSpawnColumn()
            let y = generator.estimatedSurface(x: column.x, z: column.z)
            player = PlayerController(position: DVec3(Double(column.x) + 0.5, Double(y) + 1, Double(column.z) + 0.5))
            player.pitch = -0.2
            resolveSpawn = true
        }
        player.gameMode = .creative

        let names = ["grass", "dirt", "stone", "cobblestone", "planks", "log", "glass", "torch", "amber_lantern"]
        world.uploadMesh = { renderer.makeMesh($0) }
        world.releaseMesh = { renderer.deleteMesh($0) }

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
        hotbar = names.map { blocks.id(named: $0) ?? Blocks.stone }
        selected = selectedSlot
        needsSpawnResolve = resolveSpawn
        worldTime = meta.worldTime
        Log.info("World '\(meta.name)' opened at \(player.position)", category: "Game")
    }

    // MARK: Loop

    func run() {
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
    }

    private func setMouseCaptured(_ captured: Bool) {
        mouseCaptured = captured
        _ = SDL_SetWindowRelativeMouseMode(window, captured)
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
            world.setBlock(hit.block, Blocks.air)
        }
        if placeQueued, let hit = target {
            var cell = hit.adjacent
            if blocks[hit.id]?.replaceable == true { cell = hit.block }
            let id = hotbar[selected]
            let current = world.block(cell)
            let free = current == Blocks.air || blocks[current]?.replaceable == true
            let origin = DVec3(Double(cell.x), Double(cell.y), Double(cell.z))
            let blocksPlayer = blocks.isSolid[Int(id)] && DBox(min: origin, max: origin + DVec3(1, 1, 1)).intersects(player.box)
            if free && !blocksPlayer { world.setBlock(cell, id) }
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
            fps = framesThisSecond
            framesThisSecond = 0
            titleTimer = 0
            let p = player.position
            SDL_SetWindowTitle(window, "DinoCraft · \(fps) FPS · \(Int(floor(p.x))), \(Int(floor(p.y))), \(Int(floor(p.z)))\(mouseCaptured ? "" : " · click to play")")
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
                        width: w, height: h, overlay: overlay)

        if let path = options.screenshotPath {
            let center = ChunkPos(Int32(floor(player.position.x / 16)), Int32(floor(player.position.z / 16)))
            let ready = world.readiness(around: center, radius: 3)
            if !needsSpawnResolve && ready.meshed == ready.total { framesSinceReady += 1 }
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

    // MARK: Saving

    private func save() {
        meta.worldTime = worldTime
        meta.lastPlayed = Date()
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
        world.shutdown()
        jobs.shutdown()
    }
}
