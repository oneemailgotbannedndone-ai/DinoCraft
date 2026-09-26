import UIKit
import MetalKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Top-level coordinator for the offline phone edition: owns the renderer, touch input, audio,
/// job system, registries, the screen stack and the active game session, and drives the
/// per-frame update → render loop. (The Mac engine, minus multiplayer, the launcher and Discord.)
final class GameEngine: NSObject, MTKViewDelegate {
    let view: GameView
    let device: MTLDevice
    /// Creates Metal buffers for chunk meshes built by the shared world.
    lazy var meshFactory = MetalChunkMeshFactory(device: device)
    let settingsStore: SettingsStore
    let options: LaunchOptions

    let blocks: BlockRegistry
    let items: ItemRegistry
    let recipes: RecipeRegistry
    let smelting: SmeltingRegistry
    let renderer: Renderer
    let worldRenderer: WorldRenderer
    let overlayRenderer: OverlayRenderer
    let modelRenderer: ModelRenderer
    let mobModels: MobModelLibrary
    let postProcessor: PostProcessor
    let particleRenderer: ParticleRenderer
    let particles = ParticleSystem()
    private(set) var activeTexturePack = "dino"
    private(set) var texturePacks: [TexturePack] = TexturePackLibrary.all()
    let playerModels: PlayerModelLibrary
    let uiRenderer: UIRenderer
    let ui: UIContext
    let jobs: JobSystem
    let input = Input()
    let profiler = Profiler()
    let audio: AudioSystem
    let storage = WorldStorage()
    let versionString: String
    /// The on-screen joystick and buttons.
    let touch = TouchControls()
    /// F5: first person, behind you, or facing you.
    private(set) var cameraView = CameraView.firstPerson
    private var lastTrack: String?
    /// You, drawn as a player model in third person.
    private let selfModel = RemotePlayer(id: -1, name: "", position: .zero)

    private(set) var session: GameSession?
    private var menuWorld: World?
    private var menuAnchor = DVec3(0, 100, 0)
    private var menuTime: Double = 0
    private var screens: [Screen] = []
    private(set) var iconTexture: MTLTexture?

    var camera = Camera()
    private var uniforms = FrameUniforms()
    private var lastFrameTime = CACurrentMediaTime()
    private(set) var time: Double = 0
    private var pendingScreenshot: URL?
    private var pendingScreenshotAt: (URL, Double)?
    private var started = false
    private(set) var showDebug = false
    private var hudHidden = false
    private(set) var toast: (String, Double)?
    private var fovCurrent: Double = 75
    private var musicTimer: Double = 45
    private var ambienceTimer: Double = 5
    private var curtain: Float = 1

    // Offline only: no other players.
    var isMultiplayer: Bool { false }
    var remotePlayers: [RemotePlayer] { [] }
    private(set) var chatLog: [(text: String, time: Double)] = []
    private(set) var lastViewProj = matrix_identity_float4x4

    func requestScreenshot(_ url: URL) { pendingScreenshot = url }

    var settings: GameSettings { settingsStore.settings }
    var activeWorld: World? { session?.world ?? menuWorld }

    enum EngineError: Error, CustomStringConvertible {
        case data(Error)
        var description: String {
            switch self { case .data(let e): return "Game data could not be loaded: \(e)" }
        }
    }

    init(view: GameView, device: MTLDevice, settings: SettingsStore, options: LaunchOptions) throws {
        self.view = view
        self.device = device
        self.settingsStore = settings
        self.options = options
        versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.9 (dev)"
        do {
            blocks = try BlockRegistry.loadDefault()
            items = try ItemRegistry.loadDefault(blocks: blocks)
            recipes = try RecipeRegistry.loadDefault(items: items)
            smelting = try SmeltingRegistry.loadDefault(items: items)
        } catch {
            throw EngineError.data(error)
        }
        Log.info("Registries: \(blocks.all.count) blocks, \(items.all.count) items, \(recipes.recipes.count) recipes", category: "Engine")

        renderer = try Renderer(device: device, blocks: blocks, items: items)
        worldRenderer = WorldRenderer(renderer: renderer)
        overlayRenderer = try OverlayRenderer(renderer: renderer)
        modelRenderer = try ModelRenderer(renderer: renderer)
        postProcessor = try PostProcessor(renderer: renderer)
        particleRenderer = try ParticleRenderer(renderer: renderer)
        mobModels = MobModelLibrary(device: device)
        playerModels = PlayerModelLibrary(device: device)
        uiRenderer = try UIRenderer(renderer: renderer)
        ui = UIContext(draw: uiRenderer, input: input)

        let workers = max(2, ProcessInfo.processInfo.activeProcessorCount - 2)
        let registry = blocks
        let fancy = settings.settings.graphicsQuality != .fast
        jobs = JobSystem(workerCount: workers) { index in
            let mesher = ChunkMesher(registry: registry)
            mesher.fancyLeaves = fancy
            return WorkerContext(index: index, mesher: mesher)
        }
        audio = AudioSystem()
        super.init()

        if let url = try? ResourceLocator.url("Art/icon_1024.png") {
            iconTexture = ImageLoader.texture(url: url, device: device, maxSize: 320)
        }
        ui.onSound = { [weak self] sound in
            switch sound {
            case .hover: break   // every tap would "hover" on a touch screen
            case .click: self?.audio.play("ui_click", volume: 0.55)
            case .back: self?.audio.play("ui_back", volume: 0.5)
            case .toggle: self?.audio.play("ui_toggle", volume: 0.4)
            }
        }
        renderer.configure(view: view)
        view.delegate = self
        view.input = input
        input.view = view
        applyDisplaySettings()
    }

    func applyDisplaySettings() {
        // Phones always sync to the screen (60 Hz, or 120 on ProMotion iPhones).
        view.preferredFramesPerSecond = UIScreen.main.maximumFramesPerSecond
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        createMenuWorld()
        screens = [MainMenuScreen()]
        audio.applyVolumes(settings)
        audio.playMusic("menu_theme", loop: true, fade: 3)
        if let shot = options.screenshotPath { pendingScreenshotAt = (URL(fileURLWithPath: shot), options.screenshotAfter) }
        if let name = options.autoWorld { autoStart(world: name) }
        Log.info("Engine started", category: "Engine")
    }

    private func autoStart(world name: String) {
        if let existing = storage.listWorlds().first(where: { $0.name == name }) {
            loadWorld(existing)
        } else {
            do {
                var meta = try storage.createWorld(name: name, seedText: options.autoSeed,
                                                   gameMode: options.autoCreative ? .creative : .survival, difficulty: .normal)
                if options.bonusChest {
                    meta.bonusChest = true
                    try storage.saveMetadata(meta)
                }
                startSession(meta: meta, isNew: true)
            } catch {
                Log.error("Auto-start world failed: \(error)", category: "Engine")
            }
        }
    }

    private func createMenuWorld() {
        let generator = TerrainGenerator(seed: Hashing.seed(from: "DinoCraft Panorama"))
        let spawn = generator.findSpawnColumn()
        let info = generator.columnInfo(x: spawn.x, z: spawn.z)
        menuAnchor = DVec3(Double(spawn.x) + 0.5, Double(max(info.height, WorldConst.seaLevel)) + 30, Double(spawn.z) + 0.5)
        menuWorld = World(registry: blocks, generator: generator, storage: nil, worldID: nil, meshFactory: meshFactory, jobs: jobs,
                          renderDistance: min(settings.renderDistance, 6))
    }

    func shutdown() {
        PlayerStats.shared.save()
        input.setMouseCaptured(false)
        session?.shutdown()
        session = nil
        menuWorld?.shutdown()
        jobs.shutdown()
        audio.shutdown()
        settingsStore.save()
    }

    // MARK: Screens & sessions

    func pushScreen(_ screen: Screen) {
        ui.focusedID = nil
        screens.append(screen)
    }

    var topScreen: Screen? { screens.last }

    func openScreen(_ screen: Screen) {
        input.setMouseCaptured(false)
        audio.play("ui_open", volume: 0.45)
        pushScreen(screen)
    }

    func popScreen() {
        _ = screens.popLast()
        ui.focusedID = nil
        input.captureNextBinding = nil
    }

    func loadWorld(_ meta: WorldMetadata) { startSession(meta: meta, isNew: false) }

    func startSession(meta: WorldMetadata, isNew: Bool) {
        guard session == nil else { return }
        screens.removeAll()
        menuWorld?.shutdown()
        menuWorld = nil
        let s = GameSession(meta: meta, isNew: isNew, storage: storage, blocks: blocks, items: items, meshFactory: meshFactory, jobs: jobs,
                            renderDistance: settings.renderDistance)
        s.onSound = { [weak self] name, volume, pitch in self?.audio.play(name, volume: volume, pitch: pitch) }
        s.onToast = { [weak self] text in self?.showToast(text) }
        s.onOpenCrafting = { [weak self] in self?.openScreen(InventoryScreen(gridSize: 3, title: "Crafting Bench")) }
        s.onSleep = { [weak self] in self?.openScreen(SleepScreen()) }
        s.smelting = smelting
        s.onOpenContainer = { [weak self] pos, kind in self?.openScreen(ContainerScreen(pos: pos, kind: kind)) }
        s.onOpenTrade = { [weak self] mob in self?.openScreen(TradeScreen(mob: mob)) }
        s.onOpenEnchanting = { [weak self] pos in self?.openScreen(EnchantScreen(pos: pos)) }
        s.onOpenQuestBook = { [weak self] in self?.openScreen(QuestBookScreen()) }
        s.onOpenMap = { [weak self] in self?.openScreen(MapScreen()) }
        s.onBlockBroken = { [weak self] pos, id in
            guard let self else { return }
            self.particles.blockBroken(pos, id: id, blocks: self.blocks)
        }
        s.onBlockHit = { [weak self, weak s] pos, id in
            guard let self, let s else { return }
            self.particles.blockHit(pos, id: id, blocks: self.blocks, eye: s.player.eyePosition)
        }
        s.weather.onThunder = { [weak self, weak s] closeness in
            guard let self, let s, s.dimension == .overworld else { return }
            self.audio.play("thunder", volume: 0.25 + 0.75 * closeness, pitch: 1.15 - 0.3 * closeness)
        }
        s.advancements.onUnlock = { [weak self] def in self?.announceAdvancement(def) }
        session = s
        audio.stopMusic(fade: 2.5)
        musicTimer = 50
        curtain = 1
    }

    func resumeGame() {
        screens.removeAll()
        input.captureNextBinding = nil
    }

    func saveAndQuitToTitle() {
        guard let s = session else { return }
        PlayerStats.shared.submitNow()
        input.setMouseCaptured(false)
        s.shutdown()
        session = nil
        audio.stopAllLoops()
        createMenuWorld()
        screens = [MainMenuScreen()]
        audio.playMusic("menu_theme", loop: true, fade: 3)
        curtain = 1
    }

    func respawnPlayer() {
        session?.respawn()
        screens.removeAll()
    }

    /// iPhone apps don't quit themselves (swipe the app away instead).
    func quitGame() {}

    // MARK: Advancements

    private(set) var advancementToasts: [(def: AdvancementDef, time: Double)] = []
    /// Where the minimap ends on screen (0 when hidden), so cards in the corner go below it.
    var minimapBottom: Float = 0

    func announceAdvancement(_ def: AdvancementDef) {
        advancementToasts.removeAll { time - $0.time > 10 }
        advancementToasts.append((def, time))
        audio.play("discover", volume: 0.7)
    }

    // MARK: Texture packs

    func refreshTexturePacks() { texturePacks = TexturePackLibrary.all() }

    private func applyTexturePack(_ id: String) {
        activeTexturePack = id
        refreshTexturePacks()
        let pack = texturePacks.first { $0.id == id } ?? TexturePackLibrary.defaultPack
        do {
            try renderer.loadTextures(blocks: blocks, items: items, pack: pack)
            modelRenderer.clearCache()
            Brand.apply(pack)
            Log.info("Texture pack '\(pack.name)' active", category: "Renderer")
        } catch {
            Log.error("Could not load texture pack '\(pack.name)': \(error)", category: "Renderer")
            showToast("Could not load texture pack \(pack.name)")
        }
    }

    /// What the chat box does on Enter: commands start with "/", anything else is a message.
    func submitChat(_ text: String) {
        if text.hasPrefix("/") {
            Commands.run(text, engine: self)
        } else if isMultiplayer {
            sendChat(text)
        } else {
            addChat(from: settings.username.isEmpty ? "You" : settings.username, text: text)
        }
    }

    func sendChat(_ text: String) {
        addChat(from: settings.username.isEmpty ? "You" : settings.username, text: text)
    }

    func whisper(to name: String, text: String) -> String? {
        "Private messages need other players, and this edition is offline."
    }

    func addChat(from: String, text: String) {
        chatLog.append((from.isEmpty ? text : "<\(from)> \(text)", time))
        if chatLog.count > 60 { chatLog.removeFirst(chatLog.count - 60) }
        Log.info("Chat: \(from.isEmpty ? "" : "<\(from)> ")\(text)", category: "Net")
    }

    func showToast(_ text: String) { toast = (text, 2.6) }

    func showCredits() {
        if session == nil && !(screens.last is CreditsScreen) { pushScreen(CreditsScreen()) }
    }

    func updateSettings(_ new: GameSettings) {
        let old = settings
        settingsStore.update { $0 = new }
        let s = settings
        if s.graphicsQuality != old.graphicsQuality {
            let fancy = s.graphicsQuality != .fast
            jobs.forEachContext { $0.mesher.fancyLeaves = fancy }
            activeWorld?.invalidateAllMeshes()
        }
        audio.applyVolumes(s)
    }

    // MARK: Frame

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime()
        let dt = min(0.1, max(0, now - lastFrameTime))
        lastFrameTime = now
        time += dt
        profiler.frame(dt: dt)
        profiler.begin()
        update(dt: dt)
        profiler.endUpdate()
        render(in: view)
        profiler.endEncode()
        input.endFrame()

        if let exitAfter = options.exitAfter, time > exitAfter {
            // Automated checks only.
            Log.info("Exiting after \(exitAfter)s (--exit-after)", category: "Engine")
            session?.shutdown()
            Log.shared.flush()
            exit(0)
        }
    }

    private func update(dt: Double) {
        let viewSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        ui.begin(viewSize: viewSize, backingScale: Float(view.contentScaleFactor), guiScale: Float(settings.guiScale), dt: dt, time: time)
        for s in screens { s.age += dt }
        if let t = toast { toast = t.1 - dt > 0 ? (t.0, t.1 - dt) : nil }
        touch.apply(engine: self, dt: dt)

        if input.keyPressed(settings.binding(for: .toggleDebug).code) { showDebug.toggle() }
        if input.keyPressed(settings.binding(for: .toggleHUD).code) { hudHidden.toggle() }
        if session != nil && screens.isEmpty && input.keyPressed(96) { cameraView = cameraView.next }   // F5
        if session != nil && screens.isEmpty && input.wasPressed(settings.binding(for: .minimap)) {
            settingsStore.update { $0.minimapMode = ($0.minimapMode + 1) % 3 }
            showToast(["Map hidden (M to show)", "Map in the corner", "Big map (M to hide)"][settings.minimapMode])
        }
        if session != nil && screens.isEmpty && input.keyPressed(5) {   // G: show or hide the guide
            settingsStore.update { $0.showGuide.toggle() }
            showToast(settings.showGuide ? "Guide shown (G to hide)" : "Guide hidden (G to show)")
        }
        if input.keyPressed(settings.binding(for: .screenshot).code) {
            pendingScreenshot = Screenshot.nextURL()
            showToast("Screenshot saved")
        }
        let escape = input.wasPressed(settings.binding(for: .pause))

        if let s = session {
            let focused = true
            if escape {
                if let top = screens.last { top.back(self) }
                else if !s.isLoading && !s.isDead { pushScreen(PauseScreen()) }
            }
            if s.isDead && !(screens.last is DeathScreen) { screens = [DeathScreen()] }
            if screens.isEmpty && !s.isLoading && !s.isDead && focused && input.wasPressed(settings.binding(for: .inventory)) {
                openScreen(s.player.gameMode == .creative ? CreativeInventoryScreen() : InventoryScreen(gridSize: 2, title: "Inventory"))
            }
            if screens.isEmpty && !s.isLoading && focused && input.keyPressed(17) {
                pushScreen(ChatScreen())
            } else if screens.isEmpty && !s.isLoading && focused && input.keyPressed(44) {
                pushScreen(ChatScreen(prefill: "/"))
            }
            if screens.isEmpty && !s.isLoading && focused && input.wasPressed(settings.binding(for: .advancements)) {
                pushScreen(AdvancementsScreen())
            }
            let controls = screens.isEmpty && !s.isLoading && !s.isDead && focused
            input.setMouseCaptured(controls)
            let paused = !isMultiplayer && screens.contains { $0 is PauseScreen || $0 is SettingsScreen }
            s.update(dt: dt, input: controls ? input : nil, settings: settings, paused: paused)
            particles.update(dt: paused ? 0 : dt, session: s, blocks: blocks)
            if !s.isLoading {
                updateGameCamera(s, dt: dt)
                updateGameAudio(s, dt: dt)
            }
        } else {
            input.setMouseCaptured(false)
            if escape { screens.last?.back(self) }
            menuTime += dt
            camera.position = menuAnchor
            camera.yaw = menuTime * 0.028
            camera.pitch = -0.2 + sin(menuTime * 0.07) * 0.04
            camera.roll = 0
            camera.fovY = 70 * .pi / 180
            if let w = menuWorld {
                w.renderDistance = min(settings.renderDistance, 6)
                w.update(focus: camera.position)
            }
        }
        camera.far = Float(max(600, (settings.renderDistance + 2) * 16 * 2))
        audio.update(dt: dt)
        curtain = max(0, curtain - Float(dt) * 1.4)

        // Interface
        if let s = session {
            if s.isLoading {
                LoadingView.draw(ui, session: s)
            } else if !hudHidden && !(screens.last is DeathScreen) && !(screens.last is InventoryScreen) && !(screens.last is CreativeInventoryScreen) {
                HUD.draw(ui, session: s, engine: self)
            }
        }
        if !screens.isEmpty {
            let first = screens.lastIndex(where: { !$0.isOverlay }) ?? 0
            let visible = Array(screens[first...])
            for (i, screen) in visible.enumerated() {
                ui.modalActive = i < visible.count - 1
                screen.draw(ui, self)
            }
            ui.modalActive = false
        } else if session == nil {
            MenuBackdrop.draw(ui)
        }
        touch.draw(ui, engine: self)
        if showDebug { DebugOverlay.draw(ui, engine: self) }
        if curtain > 0 { ui.draw.fill(Rect(0, 0, ui.size.x, ui.size.y), Color(hex: 0x0A0614, alpha: curtain)) }
        ui.end()
        view.setKeyboard(visible: ui.focusedID != nil)

        if let (url, after) = pendingScreenshotAt, time >= after {
            pendingScreenshot = url
            pendingScreenshotAt = nil
        }
    }

    private func updateGameCamera(_ s: GameSession, dt: Double) {
        let p = s.player
        var eye = p.eyePosition
        var roll = 0.0
        if settings.viewBobbing && !p.flying {
            let amount = s.bobAmount, phase = s.bobPhase * .pi
            let right = DVec3(cos(p.yaw), 0, -sin(p.yaw))
            eye += right * sin(phase) * 0.04 * amount
            eye.y += (0.5 - abs(cos(phase))) * 0.08 * amount
            roll = sin(phase) * 0.008 * amount
        }
        camera.position = eye
        camera.yaw = p.yaw
        camera.pitch = p.pitch
        camera.roll = roll
        if cameraView != .firstPerson {
            let placement = s.cameraPlacement(cameraView)
            camera.position = placement.eye
            camera.yaw = placement.yaw
            camera.pitch = placement.pitch
            camera.roll = 0
        }
        var target = settings.fov
        if p.isSprinting && !s.zooming { target *= p.flying ? 1.18 : 1.12 }
        fovCurrent += (target - fovCurrent) * (1 - exp(-10 * dt))
        camera.fovY = fovCurrent / s.zoomAmount * .pi / 180
    }

    private func updateGameAudio(_ s: GameSession, dt: Double) {
        let p = s.player
        let sky = SkyModel.state(worldTime: s.worldTime, dimension: s.dimension)
        let surface = !s.isUnderground && !p.headInWater && s.dimension != .underworld
        audio.setLoop("amb_underwater", volume: p.headInWater ? 0.8 : 0)
        audio.setLoop("amb_cave", volume: (s.isUnderground || s.dimension == .underworld) && !p.headInWater ? 0.7 : 0)
        audio.setLoop("amb_wind", volume: surface ? Float(min(0.8, 0.22 + max(0, p.position.y - 85) / 90)) : 0)
        audio.setLoop("amb_crickets", volume: surface && sky.isNight ? 0.45 : 0)
        audio.setLoop("amb_jungle", volume: surface && s.biome == .fernJungle && !sky.isNight ? 0.5 : 0)
        audio.setLoop("amb_surf", volume: surface && [.beach, .ocean].contains(s.biome) ? 0.55 : 0)
        let raining = s.dimension == .overworld && s.precipitation == .rain
        audio.setLoop("amb_rain", volume: raining ? s.weather.intensity * (surface ? 0.75 : 0.2) : 0)

        ambienceTimer -= dt
        if ambienceTimer <= 0 {
            ambienceTimer = Double.random(in: 4...11)
            if s.isUnderground {
                audio.play("amb_drip", volume: 0.5, pitch: Float.random(in: 0.85...1.1))
            } else if surface && !sky.isNight && [.forest, .plains, .fernJungle, .redwoodTaiga, .swamp, .savanna, .flowerMeadow, .blossomGrove, .silverForest, .fungalMarsh].contains(s.biome) {
                audio.play("amb_bird", volume: 0.35)
            }
            if surface && Double.random(in: 0..<1) < 0.06 {
                audio.play(Bool.random() ? "amb_dino_low" : "amb_dino_high", volume: 0.4, pitch: Float.random(in: 0.9...1.05))
            }
        }

        if s.dimension == .toonland {
            // Toonland always has its song on (the boss has his own theme).
            let track = SongLyrics.toonlandTrack(s)
            if audio.currentTrack != track || !audio.isMusicPlaying { audio.playMusic(track, loop: true, fade: 1.5) }
            return
        } else if audio.currentTrack == "sunny_side_up" || audio.currentTrack == "grumble_stomp" {
            audio.stopMusic(fade: 2)
            musicTimer = 20
        }
        musicTimer -= dt
        if !audio.isMusicPlaying && musicTimer <= 0 {
            let pool = (s.isUnderground || s.dimension == .underworld) ? ["deep_strata", "amber_dusk"]
                : (s.dimension == .skylands ? ["fernlight", "menu_theme", "titan_valley"]
                   : (sky.isNight ? ["amber_dusk", "deep_strata", "menu_theme"] : ["fernlight", "titan_valley", "amber_dusk", "menu_theme"]))
            // Never the same song twice in a row
            let track = pool.filter { $0 != lastTrack }.randomElement() ?? pool[0]
            lastTrack = track
            audio.playMusic(track, loop: false, fade: 4)
            musicTimer = Double.random(in: 60...150)
        }
    }

    func activityState() -> GameActivityState {
        var st = GameActivityState()
        let top = screens.last
        guard let s = session else {
            st.scene = top?.scene ?? .mainMenu
            return st
        }
        st.worldName = s.meta.name
        st.gameMode = s.player.gameMode
        st.dimension = s.dimension
        st.hardcore = s.meta.isHardcore
        if s.isLoading {
            st.scene = .loading(newWorld: s.isNewWorld)
            return st
        }
        st.scene = top is SettingsScreen ? .settings : .playing
        st.paused = top is PauseScreen
        st.inventoryOpen = top is InventoryScreen || top is CreativeInventoryScreen
        st.crafting = (top as? InventoryScreen)?.isCraftingBench == true || s.clock - s.lastCraftTime < 6
        st.dead = s.isDead
        st.swimming = s.player.inWater && !s.player.onGround
        st.flying = s.player.flying
        st.underground = s.isUnderground
        st.mining = s.clock - s.lastMiningTime < 8
        st.building = s.clock - s.lastBuildingTime < 8
        st.biome = s.biome.displayName
        st.spectating = s.spectator
        st.fighting = s.clock - s.lastCombatTime < 6 ? s.lastCombatMob : nil
        if isMultiplayer { st.multiplayer = "Playing with friends (\(remotePlayers.count + 1) players)" }
        return st
    }

    // MARK: Rendering

    private func render(in view: MTKView) {
        if settings.texturePack != activeTexturePack { applyTexturePack(settings.texturePack) }
        if let s = session, s.playerLook != settings.cosmetics { s.playerLook = settings.cosmetics }
        renderer.inflight.wait()
        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cmd = renderer.queue.makeCommandBuffer() else {
            renderer.inflight.signal()
            return
        }
        cmd.label = "Frame"
        let sema = renderer.inflight
        let profiler = self.profiler
        cmd.addCompletedHandler { buffer in
            let gpu = buffer.gpuEndTime - buffer.gpuStartTime
            DispatchQueue.main.async { profiler.recordGPU(gpu) }
            if let error = buffer.error { Log.error("GPU command buffer failed: \(error)", category: "Renderer") }
            sema.signal()
        }

        let size = SIMD2<Float>(Float(view.drawableSize.width), Float(view.drawableSize.height))
        let worldTime = session?.worldTime ?? (220 + menuTime * 0.5)
        var sky = SkyModel.state(worldTime: worldTime, dimension: session?.dimension ?? .overworld)
        if let s = session, s.dimension == .overworld { s.weather.apply(to: &sky) }
        let loading = session?.isLoading ?? false
        let underwater = !loading && (session?.player.headInWater ?? false)
        worldRenderer.prepareUniforms(&uniforms, camera: camera, aspect: size.x / max(1, size.y), sky: sky, time: time,
                                      renderDistance: activeWorld?.renderDistance ?? settings.renderDistance,
                                      brightness: settings.brightness, underwater: underwater, clouds: settings.clouds,
                                      drawableSize: size, dimension: session?.dimension ?? .overworld)
        lastViewProj = uniforms.viewProj
        if let s = session {
            let look = Season.look(worldTime: s.worldTime, dimension: s.dimension)
            uniforms.season = look.tint
            uniforms.dimension.w = look.snow
        }
        if let s = session, s.dimension == .overworld, s.weather.intensity > 0 {
            let rain = s.weather.intensity
            uniforms.fogParams.w = 0.42 + 0.5 * rain
            uniforms.fogColorStart.w *= 1 - 0.45 * rain
        }

        func encodeScene(_ enc: MTLRenderCommandEncoder) {
            if let world = activeWorld, !loading {
                worldRenderer.encode(enc, world: world, camera: camera, uniforms: &uniforms)
                if let s = session {
                    modelRenderer.encodeItems(enc, session: s, camera: camera, frame: &uniforms, time: time)
                    modelRenderer.encodeMobs(enc, session: s, camera: camera, frame: &uniforms, time: time, library: mobModels)
                    var shown = remotePlayers
                    if cameraView != .firstPerson && !s.isDead {
                        // You, wearing your cosmetics and skin.
                        let p = s.player
                        selfModel.name = settings.username
                        selfModel.look = settings.cosmetics.isEmpty ? nil : settings.cosmetics
                        selfModel.position = p.position
                        selfModel.targetPosition = p.position
                        selfModel.yaw = p.yaw
                        selfModel.pitch = p.pitch
                        selfModel.moving = p.onGround ? min(1, p.horizontalSpeed / 4.3) : 0
                        selfModel.walkPhase = s.bobPhase * .pi
                        selfModel.sneaking = p.isSneaking
                        selfModel.swing = s.swingProgress
                        selfModel.held = s.inventory.selectedStack.flatMap { items[$0.item]?.name }
                        selfModel.motion = s.selfMotion
                        shown.append(selfModel)
                    }
                    playerModels.encode(enc, players: shown, world: world, camera: camera, frame: &uniforms, renderer: modelRenderer, items: items)
                    particleRenderer.encode(enc, particles: particles, session: s, world: world, camera: camera, frame: &uniforms, time: time)
                    if !s.isDead && !hudHidden {
                        if screens.isEmpty { overlayRenderer.encode(enc, session: s, camera: camera, uniforms: &uniforms) }
                        if cameraView == .firstPerson {
                            modelRenderer.encodeHand(enc, session: s, camera: camera, frame: &uniforms, aspect: size.x / max(1, size.y),
                                                     drawableSize: size, bobbing: settings.viewBobbing)
                        }
                    }
                }
            } else {
                worldRenderer.encodeSky(enc, uniforms: &uniforms)
            }
        }

        let shader = ShaderPack(rawValue: settings.shaderPack) ?? .off
        let mono: Float = 0
        if (shader != .off && settings.shaderStrength > 0.01) || mono > 0, let depth = rpd.depthAttachment.texture,
           let target = postProcessor.sceneTarget(width: Int(size.x), height: Int(size.y)) {
            // Shader pack: scene → offscreen target → graded into the drawable, interface on top.
            let scenePass = MTLRenderPassDescriptor()
            scenePass.colorAttachments[0].texture = target
            scenePass.colorAttachments[0].loadAction = .clear
            scenePass.colorAttachments[0].clearColor = rpd.colorAttachments[0].clearColor
            scenePass.colorAttachments[0].storeAction = .store
            scenePass.depthAttachment.texture = depth
            scenePass.depthAttachment.loadAction = .clear
            scenePass.depthAttachment.clearDepth = 0
            scenePass.depthAttachment.storeAction = .dontCare
            if let enc = cmd.makeRenderCommandEncoder(descriptor: scenePass) {
                enc.label = "Scene Pass"
                encodeScene(enc)
                enc.endEncoding()
            }
            if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
                enc.label = "Post + Interface"
                postProcessor.encode(enc, source: target, pack: shader, strength: Float(settings.shaderStrength), mono: mono, time: Float(time), size: size)
                uiRenderer.encode(enc, drawableSize: size)
                enc.endEncoding()
            }
        } else if let enc = cmd.makeRenderCommandEncoder(descriptor: rpd) {
            enc.label = "Main Pass"
            encodeScene(enc)
            uiRenderer.encode(enc, drawableSize: size)
            enc.endEncoding()
        }

        if let url = pendingScreenshot {
            pendingScreenshot = nil
            Screenshot.capture(drawable.texture, commandBuffer: cmd, device: device, to: url)
        }
        cmd.present(drawable)
        cmd.commit()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        Log.debug("Drawable size \(Int(size.width))×\(Int(size.height))", category: "Renderer")
    }

    // MARK: App hooks

    /// The app went to the background: let go of every control, pause, and save (iOS may close the
    /// app while it's in the background).
    func applicationLostFocus() {
        input.releaseAll()
        touch.reset()
        if let s = session, !s.isLoading, !s.isDead, screens.isEmpty { pushScreen(PauseScreen()) }
        session?.save()
        settingsStore.save()
        PlayerStats.shared.save()
    }

    func applicationGainedFocus() {}
}

extension GameEngine: CommandHost {
    var isClient: Bool { false }

    func give(playerNamed name: String, item: String, count: Int) -> Bool { false }
}
