import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

/// Playing your own world on Windows. The game itself is the shared `GameSession` the Mac runs:
/// Survival, Hardcore and Creative, creatures, dropped items, crafting, furnaces, chests, farming,
/// bows, armor, beds, villagers, portals, weather, advancements and chat commands. This class feeds
/// it SDL input, draws it with OpenGL, and can open the world to friends on Mac and Windows.
final class WinSolo: CommandHost {
    enum Screen {
        case closed, pause, settings, inventory, crafting, creative, advancements
        case container(BlockPos, ContainerKind)
        case trade(Mob)
        case sleep(started: Double)
    }

    enum SlotRef: Equatable {
        case inventory(Int), craft(Int), output, armor(Int), container(Int), palette(Int)
    }

    let gl: GL
    let window: OpaquePointer
    let options: Options
    let blocks: BlockRegistry
    let items: ItemRegistry
    let recipes: RecipeRegistry
    let renderer: WinRenderer
    let audio: WinAudio?
    let store: SettingsStore
    let storage = WorldStorage()
    let jobs: JobSystem
    let input = SDLGameInput()
    let particles = ParticleSystem()
    private(set) var session: GameSession?
    /// The session, which exists from `init` until the game ends.
    var game: GameSession { session! }

    /// True when the player closed the window (rather than returning to the title screen).
    private(set) var quitRequested = false
    var running = true
    var mouseCaptured = false
    let startTime = Date.timeIntervalSinceReferenceDate
    var lastFrame = Date.timeIntervalSinceReferenceDate
    var clock: Double { Date.timeIntervalSinceReferenceDate - startTime }

    // Screens and menus
    var screen = Screen.closed
    var mouse = SIMD2<Float>(0, 0)
    var clicked = false
    var rightClicked = false
    var shiftHeld = false
    var menuTyped = ""
    var menuBackspace = false
    var cursorStack: ItemStack?
    var craftGrid: [ItemStack?] = Array(repeating: nil, count: 4)
    var hoveredSlot: SlotRef?
    var paletteScroll = 0
    /// The recipe book beside the inventory and crafting bench.
    var bookOpen = true
    var bookScroll = 0
    var bookCraftableOnly = false
    /// Where the book was drawn last frame (x, y, w, h), for the mouse wheel.
    var bookArea: SIMD4<Float>?
    var paletteSearch = ""
    var paletteSearchFocused = false
    var hudHidden = false
    /// F5: first person, behind you, or facing you.
    var cameraView = CameraView.firstPerson
    var showDebug = false

    // Chat and messages
    var chatLines: [(text: String, time: Double)] = []
    var chatOpen = false
    var chatInput = ""
    var swallowText: String?
    var toast: (text: String, time: Double)?
    var advancementToasts: [(def: AdvancementDef, time: Double)] = []

    // Sound
    var ambienceTimer = 6.0
    var musicTimer = 50.0

    // Frame counter and automated checks
    var titleTimer = 0.0
    var framesThisSecond = 0
    var fps = 0
    var framesSinceReady = 0
    var demoPlaced = false
    /// Automated check "reef"/"kelp": already moved under the sea.
    var seaDemoMoved = false
    var screenshotQueued = false

    // Hosting: friends on Mac and Windows join through the wire protocol
    var host: WireHost?
    let hostName: String
    var hostEntities: [Int: RemoteEntity] = [:]
    var applyingRemoteEdit = false
    var lanCode: String?
    var internetCode: String?
    let mappingLock = NSLock()
    var mappingResult: Result<PortMapping.Mapping, PortMapping.Failure>?
    var mapping: PortMapping.Mapping?
    var mappingClosed = false

    init(gl: GL, window: OpaquePointer, content: GameContent, audio: WinAudio?, settings: SettingsStore, options: Options,
         world meta: WorldMetadata, isNew: Bool, hostName requestedHost: String?) {
        self.gl = gl
        self.window = window
        self.options = options
        blocks = content.blocks
        items = content.items
        recipes = content.recipes
        renderer = content.renderer
        self.audio = audio
        store = settings
        jobs = JobSystem.forWindows(blocks: blocks, fancyLeaves: settings.settings.graphicsQuality != .fast)
        let savedName = settings.settings.username
        hostName = cleanName(requestedHost ?? (savedName.isEmpty ? "Host" : savedName))

        let s = GameSession(meta: meta, isNew: isNew, storage: storage, blocks: blocks, items: items,
                            meshFactory: GLChunkMeshFactory(renderer: renderer), jobs: jobs,
                            renderDistance: WinSolo.gameSettings(settings.settings, options).renderDistance)
        s.smelting = content.smelting
        session = s
        s.onSound = { [weak self] name, volume, pitch in self?.audio?.play(name, volume: volume, pitch: pitch) }
        s.onToast = { [weak self] text in self?.showToast(text) }
        s.onOpenCrafting = { [weak self] in self?.openScreen(.crafting) }
        s.onOpenContainer = { [weak self] pos, kind in self?.openScreen(.container(pos, kind)) }
        s.onOpenTrade = { [weak self] mob in self?.openScreen(.trade(mob)) }
        s.onSleep = { [weak self] in
            guard let self else { return }
            self.openScreen(.sleep(started: self.clock))
        }
        s.weather.onThunder = { [weak self, weak s] closeness in
            guard let self, let s, s.dimension == .overworld else { return }
            self.audio?.play("thunder", volume: 0.25 + 0.75 * closeness, pitch: 1.15 - 0.3 * closeness)
        }
        s.advancements.onUnlock = { [weak self] def in self?.announceAdvancement(def) }
        s.onBlockBroken = { [weak self] pos, id in
            guard let self else { return }
            self.particles.blockBroken(pos, id: id, blocks: self.blocks)
        }
        s.onBlockHit = { [weak self, weak s] pos, id in
            guard let self, let s else { return }
            self.particles.blockHit(pos, id: id, blocks: self.blocks, eye: s.player.eyePosition)
        }
        s.blockObserver = { [weak self] pos, id in
            guard let self, let host = self.host, !self.applyingRemoteEdit, self.session?.dimension == .overworld else { return }
            host.broadcastBlock(pos, id)
        }
        audio?.apply(settings.settings)
        if requestedHost != nil { startHosting() }
    }

    /// The saved settings with any command-line override. The world needs at least 4 chunks around
    /// the player to finish loading, so the view distance never goes below that.
    static func gameSettings(_ saved: GameSettings, _ options: Options) -> GameSettings {
        var s = saved
        s.renderDistance = max(4, options.renderDistance ?? s.renderDistance)
        return s
    }

    // MARK: CommandHost

    var settings: GameSettings { store.settings }
    /// The players connected to your hosted world (for /list, /msg and /tp).
    var remotePlayers: [RemotePlayer] {
        (host?.players ?? []).map { p in
            RemotePlayer(id: p.id, name: p.name, position: p.state.map { DVec3($0.x, $0.y, $0.z) } ?? game.player.position)
        }
    }
    var isMultiplayer: Bool { host != nil }
    var isClient: Bool { false }

    func addChat(from: String, text: String) {
        let line = from.isEmpty ? text : "<\(from)> \(text)"
        for part in WinSolo.wrap(line, width: 80) {
            chatLines.append((part, clock))
        }
        if chatLines.count > 80 { chatLines.removeFirst(chatLines.count - 80) }
        Log.info("Chat: \(line)", category: "Net")
    }

    func whisper(to name: String, text: String) -> String? {
        guard !text.isEmpty else { return "Type a message after the name." }
        guard let host else { return "Private messages need other players in the game." }
        guard host.whisper(from: hostName, to: name, text: text) else { return "No player called \(name) is here." }
        addChat(from: "", text: "You whisper to \(name): \(text)")
        return nil
    }

    func sendChat(_ text: String) {
        if let host {
            host.broadcastChat(from: hostName, text: text)
            addChat(from: hostName, text: text)
        } else {
            addChat(from: settings.username.isEmpty ? "You" : settings.username, text: text)
        }
    }

    func give(playerNamed name: String, item: String, count: Int) -> Bool { false }

    /// Splits a long message at spaces so each line fits the chat box.
    static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false) {
            if !line.isEmpty && line.count + word.count + 1 > width {
                lines.append(line)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word
        }
        if !line.isEmpty || lines.isEmpty { lines.append(line) }
        return lines
    }

    func showToast(_ text: String) { toast = (text, clock) }

    func announceAdvancement(_ def: AdvancementDef) {
        advancementToasts.removeAll { clock - $0.time > 6 }
        advancementToasts.append((def, clock))
        audio?.play("discover", volume: 0.7)
        addChat(from: "", text: "Advancement made: \(def.title)")
        if let host { host.broadcastChat(from: hostName, text: "made the advancement [\(def.title)]") }
    }

    // MARK: Loop

    /// Runs until the player leaves or closes the window.
    func run() {
        if options.screenshotPath == nil { setMouseCaptured(true) }
        audio?.stopMusic()
        addChat(from: "", text: "Welcome to \(game.meta.name)! Press E for your inventory, T to chat, and / for commands.")
        while running {
            let now = Date.timeIntervalSinceReferenceDate
            let dt = min(0.1, now - lastFrame)
            lastFrame = now
            pollEvents()
            update(dt: dt)
            draw()
            // With VSync off, an optional frame cap (0 = unlimited)
            if !settings.vsync && settings.maxFPS > 0 && options.screenshotPath == nil {
                let spare = 1 / Double(settings.maxFPS) - (Date.timeIntervalSinceReferenceDate - now)
                if spare > 0.001 { SDL_Delay(UInt32(spare * 1000)) }
            }
        }
        shutdown()
    }

    func setMouseCaptured(_ captured: Bool) {
        mouseCaptured = captured
        _ = SDL_SetWindowRelativeMouseMode(window, captured)
        if !captured { input.releaseAll() }
    }

    func pixelScale() -> Float {
        var lw: Int32 = 0, lh: Int32 = 0, pw: Int32 = 0, ph: Int32 = 0
        _ = SDL_GetWindowSize(window, &lw, &lh)
        _ = SDL_GetWindowSizeInPixels(window, &pw, &ph)
        return lw > 0 ? Float(pw) / Float(lw) : 1
    }

    var isPlaying: Bool {
        if case .closed = screen { return mouseCaptured && !chatOpen && !game.isDead }
        return false
    }

    var screenIsOpen: Bool {
        if case .closed = screen { return false }
        return true
    }

    private func openChat(prefix: String) {
        guard !chatOpen, !screenIsOpen else { return }
        chatOpen = true
        chatInput = prefix
        swallowText = prefix.isEmpty ? "t" : prefix
        input.releaseAll()
        _ = SDL_StartTextInput(window)
    }

    private func closeChat() {
        chatOpen = false
        chatInput = ""
        _ = SDL_StopTextInput(window)
    }

    private func submitChat() {
        let text = chatInput.trimmingCharacters(in: .whitespaces)
        closeChat()
        guard !text.isEmpty else { return }
        if text.hasPrefix("/") {
            Commands.run(text, engine: self)
        } else {
            sendChat(text)
        }
    }

    private func pollEvents() {
        clicked = false
        rightClicked = false
        menuTyped = ""
        menuBackspace = false
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            let type = UInt32(event.type)
            if type == UInt32(SDL_EVENT_QUIT.rawValue) {
                running = false
                quitRequested = true
            } else if type == UInt32(SDL_EVENT_TEXT_INPUT.rawValue) {
                guard let raw = event.text.text else { continue }
                let typed = String(cString: raw)
                if chatOpen {
                    if let swallow = swallowText {
                        swallowText = nil
                        if typed.lowercased() == swallow { continue }
                    }
                    chatInput = String((chatInput + typed).prefix(120))
                } else {
                    menuTyped += typed
                }
            } else if type == UInt32(SDL_EVENT_KEY_DOWN.rawValue) {
                keyDown(event.key)
            } else if type == UInt32(SDL_EVENT_KEY_UP.rawValue) {
                input.keyUp(event.key.scancode)
            } else if type == UInt32(SDL_EVENT_MOUSE_MOTION.rawValue) {
                mouse = SIMD2<Float>(event.motion.x, event.motion.y) * pixelScale()
                if isPlaying { input.mouseMoved(dx: event.motion.xrel, dy: event.motion.yrel) }
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue) {
                mouse = SIMD2<Float>(event.button.x, event.button.y) * pixelScale()
                let keys = SDL_GetKeyboardState(nil)
                shiftHeld = keys.map { $0[Int(SDL_SCANCODE_LSHIFT.rawValue)] || $0[Int(SDL_SCANCODE_RSHIFT.rawValue)] } ?? false
                if isPlaying {
                    input.buttonDown(event.button.button)
                } else if screenIsOpen || game.isDead || game.isLoading {
                    if event.button.button == 1 { clicked = true }
                    if event.button.button == 3 { rightClicked = true }
                } else if !mouseCaptured && !chatOpen {
                    if options.screenshotPath != nil { setMouseCaptured(true) } else if event.button.button == 1 { clicked = true }
                }
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_UP.rawValue) {
                input.buttonUp(event.button.button)
            } else if type == UInt32(SDL_EVENT_MOUSE_WHEEL.rawValue) {
                if isPlaying {
                    input.wheel(event.wheel.y)
                } else if let r = bookArea, mouse.x >= r.x, mouse.x < r.x + r.z, mouse.y >= r.y, mouse.y < r.y + r.w {
                    bookScroll = max(0, bookScroll - Int(event.wheel.y.rounded()))
                } else if case .creative = screen {
                    paletteScroll = max(0, paletteScroll - Int(event.wheel.y.rounded()))
                }
            } else if type == UInt32(SDL_EVENT_WINDOW_FOCUS_LOST.rawValue) {
                if isPlaying { openPause() } else { input.releaseAll() }
            }
        }
        swallowText = nil
    }

    private func keyDown(_ key: SDL_KeyboardEvent) {
        let code = key.scancode
        func `is`(_ c: SDL_Scancode) -> Bool { code == c }
        func bound(_ action: GameAction) -> Bool {
            let b = settings.binding(for: action)
            return b.kind == .key && SDLGameInput.scancode(forMacKey: b.code) == Int(code.rawValue)
        }
        if chatOpen {
            if `is`(SDL_SCANCODE_ESCAPE) { closeChat() }
            else if `is`(SDL_SCANCODE_RETURN) || `is`(SDL_SCANCODE_KP_ENTER) { submitChat() }
            else if `is`(SDL_SCANCODE_BACKSPACE), !chatInput.isEmpty { chatInput.removeLast() }
            return
        }
        if `is`(SDL_SCANCODE_BACKSPACE) { menuBackspace = true }
        if key.`repeat` { if isPlaying { input.keyDown(code, isRepeat: true) }; return }
        if bound(.screenshot) { screenshotQueued = true; return }

        if game.isDead || game.isLoading { return }
        if screenIsOpen {
            if case .sleep = screen { return }
            let typing: Bool
            if case .creative = screen { typing = paletteSearchFocused } else { typing = false }
            if case .settings = screen, `is`(SDL_SCANCODE_ESCAPE) {
                screen = .pause
                return
            }
            if `is`(SDL_SCANCODE_ESCAPE) || (bound(.inventory) && !typing) || (bound(.advancements) && isAdvancements) { closeScreen() }
            return
        }
        if bound(.pause) || `is`(SDL_SCANCODE_ESCAPE) {
            if mouseCaptured { openPause() } else { setMouseCaptured(true) }
            return
        }
        if !mouseCaptured { return }
        if bound(.inventory) {
            openScreen(game.player.gameMode == .creative && !game.spectator ? .creative : .inventory)
        } else if `is`(SDL_SCANCODE_T) {
            openChat(prefix: "")
        } else if `is`(SDL_SCANCODE_SLASH) {
            openChat(prefix: "/")
        } else if bound(.toggleDebug) {
            showDebug.toggle()
        } else if `is`(SDL_SCANCODE_F5) {
            cameraView = cameraView.next
        } else if `is`(SDL_SCANCODE_G) {
            store.update { $0.showGuide.toggle() }
            showToast(settings.showGuide ? "Guide shown (G to hide)" : "Guide hidden (G to show)")
        } else if bound(.toggleHUD) {
            hudHidden.toggle()
        } else if bound(.advancements) {
            openScreen(.advancements)
        } else {
            input.keyDown(code, isRepeat: false)
        }
    }

    private var isAdvancements: Bool {
        if case .advancements = screen { return true }
        return false
    }

    func openPause() {
        screen = .pause
        setMouseCaptured(false)
        audio?.play("ui_open", volume: 0.45)
        centerMouse()
    }

    func centerMouse() {
        var w: Int32 = 0, h: Int32 = 0
        _ = SDL_GetWindowSizeInPixels(window, &w, &h)
        mouse = SIMD2(Float(w) / 2, Float(h) / 2)
    }

    func openScreen(_ next: Screen) {
        if case .sleep = next {} else { audio?.play("ui_open", volume: 0.45) }
        let size: Int
        if case .crafting = next { size = 3 } else { size = 2 }
        craftGrid = Array(repeating: nil, count: size * size)
        paletteSearch = ""
        paletteSearchFocused = false
        paletteScroll = 0
        screen = next
        setMouseCaptured(false)
        if case .creative = next { _ = SDL_StartTextInput(window) }
        centerMouse()
    }

    func closeScreen() {
        guard let s = session else { return }
        for stack in craftGrid.compactMap({ $0 }) { stash(stack, s) }
        craftGrid = Array(repeating: nil, count: craftGrid.count)
        if let cursor = cursorStack {
            if case .creative = screen {} else { stash(cursor, s) }
            cursorStack = nil
        }
        if case .creative = screen { _ = SDL_StopTextInput(window) }
        screen = .closed
        audio?.play("ui_close", volume: 0.45)
        hoveredSlot = nil
        if options.screenshotPath == nil { setMouseCaptured(true) }
    }

    /// Puts a stack back in the inventory, dropping whatever doesn't fit.
    func stash(_ stack: ItemStack, _ s: GameSession) {
        let left = s.inventory.add(stack)
        if left > 0 {
            var rest = stack
            rest.count = left
            s.dropStack(rest, thrown: false)
        }
    }

    private func update(dt: Double) {
        guard let s = session else { return }
        audio?.update(dt: dt)
        if let host {
            pollMapping()
            host.poll()
            host.tick(dt: dt, hostState: hostPlayerState())
            syncHostPlayers(dt: dt)
        }
        let gameSettings = WinSolo.gameSettings(settings, options)
        let paused: Bool
        switch screen {
        case .pause, .settings: paused = host == nil
        default: paused = false
        }
        s.update(dt: dt, input: isPlaying ? input : nil, settings: gameSettings, paused: paused)
        input.endFrame()
        if !s.isLoading { particles.update(dt: paused ? 0 : dt, session: s, blocks: blocks) }

        if case .sleep(let started) = screen {
            let elapsed = clock - started
            if elapsed > 2.0 && !sleepWoke {
                sleepWoke = true
                s.wakeUp()
            }
            if elapsed > 3.2 {
                sleepWoke = false
                screen = .closed
                showToast("Good morning!")
                if options.screenshotPath == nil { setMouseCaptured(true) }
            }
        }
        if case .trade(let mob) = screen, mob.isDying || mob.removed || simd_distance(mob.position, s.player.position) > 8 {
            closeScreen()
        }
        if s.isDead && mouseCaptured { setMouseCaptured(false) }

        updateAmbience(dt: dt)
        titleTimer += dt
        framesThisSecond += 1
        if titleTimer >= 1 {
            fps = framesThisSecond
            framesThisSecond = 0
            titleTimer = 0
            SDL_SetWindowTitle(window, "DinoCraft · \(fps) FPS · \(s.meta.name)")
        }
    }

    var sleepWoke = false
    private var lastTrack: String?

    /// Ambience loops, occasional birds and dinosaur calls, and music, following the Mac rules.
    private func updateAmbience(dt: Double) {
        guard let audio, let s = session, options.screenshotPath == nil else { return }
        let p = s.player
        let night = s.isNight
        let underground = s.dimension == .overworld && p.position.y < Double(s.world.generator.seaLevel - 14)
        let surface = s.dimension == .overworld && !underground && !p.headInWater
        let raining = s.weather.kind != .clear && s.dimension == .overworld
        audio.setLoop("amb_underwater", volume: p.headInWater ? 0.8 : 0)
        audio.setLoop("amb_cave", volume: (underground || s.dimension == .underworld) && !p.headInWater ? 0.7 : 0)
        audio.setLoop("amb_wind", volume: surface ? Float(min(0.8, 0.22 + max(0, p.position.y - 85) / 90)) : (s.dimension == .skylands ? 0.5 : 0))
        audio.setLoop("amb_crickets", volume: surface && night && !raining ? 0.45 : 0)
        audio.setLoop("amb_rain", volume: surface && raining ? 0.7 * s.weather.intensity : 0)
        ambienceTimer -= dt
        if ambienceTimer <= 0 {
            ambienceTimer = Double.random(in: 4...11)
            if underground {
                audio.play("amb_drip", volume: 0.5, pitch: Float.random(in: 0.85...1.1))
            } else if surface && !night && !raining {
                audio.play("amb_bird", volume: 0.35)
            }
            if surface && Double.random(in: 0..<1) < 0.06 {
                audio.play(Bool.random() ? "amb_dino_low" : "amb_dino_high", volume: 0.4, pitch: Float.random(in: 0.9...1.05))
            }
        }
        if s.dimension == .toonland {
            // Toonland always has its song on (the boss has his own theme).
            let track = SongLyrics.toonlandTrack(s)
            if audio.currentTrack != track || !audio.isMusicPlaying { audio.playMusic(track) }
            return
        } else if audio.currentTrack == "sunny_side_up" || audio.currentTrack == "grumble_stomp" {
            audio.stopMusic()
            musicTimer = 20
        }
        musicTimer -= dt
        if !audio.isMusicPlaying && musicTimer <= 0 {
            let pool = underground || s.dimension == .underworld ? ["deep_strata", "amber_dusk"]
                : (night ? ["amber_dusk", "deep_strata", "menu_theme"] : ["fernlight", "titan_valley", "amber_dusk", "menu_theme"])
            // Never the same song twice in a row
            let track = pool.filter { $0 != lastTrack }.randomElement() ?? pool[0]
            lastTrack = track
            audio.playMusic(track)
            musicTimer = Double.random(in: 60...150)
        }
    }

    // MARK: Drawing

    private func draw() {
        guard let s = session else { return }
        var w: Int32 = 0, h: Int32 = 0
        _ = SDL_GetWindowSizeInPixels(window, &w, &h)
        var camera = WinCamera()
        let placement = s.cameraPlacement(cameraView)
        camera.position = placement.eye
        camera.yaw = placement.yaw
        camera.pitch = placement.pitch
        camera.fovY = max(50, min(110, settings.fov)) * .pi / 180
        if s.player.isSprinting && !s.zooming { camera.fovY *= 1.08 }
        camera.fovY /= s.zoomAmount
        if settings.viewBobbing && !s.player.flying && cameraView == .firstPerson {
            // Gentle head bob while walking, like on the Mac.
            let phase = s.bobPhase * .pi, amount = s.bobAmount
            camera.position.y += abs(cos(phase)) * 0.045 * amount
            camera.yaw += sin(phase) * 0.004 * amount
        }
        let ui = buildUI(width: Float(w), height: Float(h), camera: camera)
        let sky = SkyState.at(worldTime: s.worldTime, dimension: s.dimension, weather: s.weather.intensity)
        renderer.mono = 0
        let eye = camera.position
        renderer.underwater = cameraView == .firstPerson && s.player.headInWater
            && Blocks.holdsWater(s.world.block(Int(floor(eye.x)), Int(floor(eye.y)), Int(floor(eye.z))), s.world.registry)
        renderer.render(world: s.world, camera: camera, sky: sky, time: clock, now: Date.timeIntervalSinceReferenceDate,
                        width: w, height: h, ui: ui, models: models(camera: camera), effects: worldEffects(camera: camera))

        if let path = options.screenshotPath {
            if !s.isLoading {
                if !demoPlaced { placeDemo() }
                framesSinceReady += 1
            }
            let timedOut = clock > 150
            let loadingShot = options.demoScreen == "loading" && s.isLoading && clock > 1.5
            if framesSinceReady >= options.frames || timedOut || loadingShot {
                if timedOut { Log.warning("Screenshot taken before the world finished loading", category: "Game") }
                saveScreenshot(to: URL(fileURLWithPath: path), width: w, height: h)
                Log.info("Automated check: \(renderer.visibleChunks) chunks visible, \(s.world.slots.count) loaded, \(s.mobs.mobs.count) creatures", category: "Game")
                running = false
            }
        } else if screenshotQueued {
            screenshotQueued = false
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd_HH.mm.ss"
            let url = GamePaths.screenshots.appendingPathComponent("DinoCraft_\(formatter.string(from: Date())).png")
            saveScreenshot(to: url, width: w, height: h)
            showToast("Saved screenshot \(url.lastPathComponent)")
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

    /// Creatures, arrows and friends as camera-relative triangles.
    private func models(camera: WinCamera) -> [Float] {
        guard let s = session, !s.isLoading else { return [] }
        var v: [Float] = []
        let maxDistance = Double(s.world.renderDistance * 16)
        func rel(_ p: DVec3) -> SIMD3<Float>? {
            let d = p - camera.position
            guard d.x * d.x + d.z * d.z < maxDistance * maxDistance else { return nil }
            return SIMD3(Float(d.x), Float(d.y), Float(d.z))
        }
        let time = clock
        for m in s.mobs.mobs where !m.removed {
            guard let r = rel(m.position) else { continue }
            CreatureModels.appendCreature(&v, kind: m.species.kind.rawValue, at: r, yaw: Float(m.yaw), walk: Float(m.walkPhase),
                                          amount: Float(m.moveAmount), lunge: Float(m.lunge), hurt: Float(m.hurtTimer),
                                          dying: m.isDying ? Float(max(0.001, m.deathTimer)) : 0, variant: m.variant,
                                          seed: Double(m.id % 997) * 0.61, time: time)
        }
        let none = SIMD4<Float>(0, 0, 0, 0)
        for p in s.mobs.projectiles where !p.removed {
            guard let r = rel(p.position) else { continue }
            let m = MathUtil.translation(r) * MathUtil.rotationY(Float(p.age * 9))
            CreatureModels.appendBox(&v, m, SIMD3(repeating: -0.12), SIMD3(repeating: 0.12), CreatureModels.c(0x9BD23A), glow: true, tint: none)
        }
        for a in s.arrows.arrows where !a.done {
            guard let r = rel(a.position) else { continue }
            let d = simd_length(a.velocity) > 0.01 ? simd_normalize(a.velocity) : DVec3(0, 0, -1)
            let yaw = Float(atan2(-d.x, -d.z)), pitch = Float(asin(max(-1, min(1, d.y))))
            let m = MathUtil.translation(r) * MathUtil.rotationY(yaw) * MathUtil.rotationX(pitch)
            CreatureModels.appendBox(&v, m, SIMD3(-0.025, -0.025, -0.3), SIMD3(0.025, 0.025, 0.3), CreatureModels.c(0x8A6A44), glow: false, tint: none)
            CreatureModels.appendBox(&v, m, SIMD3(-0.05, -0.05, 0.22), SIMD3(0.05, 0.05, 0.3), CreatureModels.c(0xE8E2D6), glow: false, tint: none)
        }
        if cameraView != .firstPerson && !s.isDead, let r = rel(s.player.position) {
            // You, wearing your cosmetics and skin.
            let p = s.player
            CreatureModels.appendPlayer(&v, name: settings.username, look: settings.cosmetics.isEmpty ? nil : settings.cosmetics, at: r,
                                        yaw: Float(p.yaw), pitch: Float(p.pitch), walk: Float(s.bobPhase * .pi),
                                        moving: Float(p.onGround ? min(1, p.horizontalSpeed / 4.3) : 0), sneaking: p.isSneaking,
                                        swing: Float(s.swingProgress), hurt: Float(s.damageFlash > 0.7 ? 0.3 : 0))
        }
        for p in hostEntities.values where p.dying == 0 {
            guard let r = rel(p.position) else { continue }
            CreatureModels.appendPlayer(&v, name: p.name, look: p.look, at: r, yaw: Float(p.yaw), pitch: p.pitch, walk: p.walk, moving: p.moving,
                                        sneaking: p.sneaking, swing: p.swing, hurt: p.hurt)
        }
        return v
    }

    /// Automated check: dive into the nearest coral reef (or cold kelp forest), then let the chunks there load.
    private func moveToSeaDemo(_ s: GameSession) {
        seaDemoMoved = true
        framesSinceReady = 0
        guard let generator = s.world.generator as? TerrainGenerator else { return }
        let sea = generator.seaLevel
        let reef = options.demoScreen == "reef"
        let start = s.player.position
        search: for ring in 0..<80 {
            let r = ring * 12
            for step in 0..<max(1, ring * 8) {
                let a = Double(step) / Double(max(1, ring * 8)) * 2 * .pi
                let x = Int(start.x + cos(a) * Double(r)), z = Int(start.z + sin(a) * Double(r))
                let info = generator.columnInfo(x: x, z: z)
                guard info.biome == .ocean else { continue }
                let ok = reef ? sea - info.height >= 6 && [(0, 0), (8, 0), (-8, 0), (0, 8), (0, -8)].allSatisfy { generator.isReef(x: x + $0.0, z: z + $0.1) }
                              : info.temperature < 0.3 && sea - info.height >= 9
                guard ok else { continue }
                s.player.gameMode = .creative
                s.player.setFlying(true)
                s.player.teleport(to: DVec3(Double(x) + 0.5, Double(sea - 3), Double(z) + 0.5))
                s.player.pitch = -0.45
                Log.info("Automated check: diving at \(x), \(z), \(sea - info.height) deep", category: "Game")
                break search
            }
        }
    }

    /// Automated check: a few creatures and a chat line in view, and optionally the inventory screen.
    private func placeDemo() {
        guard let s = session else { return }
        if (options.demoScreen ?? "").hasPrefix("toonland") && s.dimension != .toonland {
            // Automated check: travel to Toonland first, then take the picture there.
            s.changeDimension(to: .toonland, portal: nil, arrival: DVec3(24.5, 70, 0.5))
            framesSinceReady = 0
            return
        }
        if options.demoScreen == "reef" || options.demoScreen == "kelp" {
            guard seaDemoMoved else { moveToSeaDemo(s); return }
            demoPlaced = true
            // A school of fish in front of you.
            let look = s.player.lookDirection
            let forward = simd_normalize(DVec3(look.x, 0, look.z)), right = DVec3(-forward.z, 0, forward.x)
            let kinds: [MobKind] = options.demoScreen == "reef" ? [.clownfish, .blueTang] : [.cod, .salmon]
            for i in 0..<7 {
                let spot = s.player.position + forward * (2.4 + Double(i % 3) * 1.1) + right * (Double(i) - 3) * 0.6 + DVec3(0, 0.6 - Double(i % 3) * 0.45, 0)
                let fish = s.mobs.spawn(kinds[i % 2], at: spot)
                fish.yaw = atan2(-right.x, -right.z)
            }
            addChat(from: "", text: "Automated check: under the sea")
            return
        }
        demoPlaced = true
        if s.dimension == .toonland { s.player.yaw = .pi / 2 }   // look toward the stage
        if options.demoScreen == "toonland-boss" {
            let boss = s.mobs.spawn(.grumblesaurus, at: DVec3(10.5, Double(ToonlandGenerator.stageFloor + 1), 0.5))
            boss.yaw = -.pi / 2
            boss.health = 130
            boss.enraged = true
            Log.info("Automated check: King Grumblesaurus placed on the stage", category: "Game")
        }
        guard options.demoEntities else { return }
        let look = s.player.lookDirection
        let forward = simd_normalize(DVec3(look.x, 0, look.z))
        let right = DVec3(-forward.z, 0, forward.x)
        let samples: [(MobKind, Double, Double)] = [(.raptor, 7, 2), (.trikey, 9, -4), (.rex, 16, 3), (.sheep, 6, 4), (.pookpook, 5, -1.5)]
        for sample in samples {
            let spot = s.player.position + forward * sample.1 + right * sample.2
            let y = s.world.findStandingY(Int(floor(spot.x)), Int(floor(spot.z)), near: Int(s.player.position.y)) ?? Int(s.player.position.y)
            let mob = s.mobs.spawn(sample.0, at: DVec3(spot.x, Double(y), spot.z))
            mob.yaw = atan2(forward.x, forward.z)
        }
        if let bread = items.id(named: "bread") {
            s.entities.spawnItem(ItemStack(item: bread, count: 3), at: s.player.position + forward * 3 + DVec3(0, 1, 0), velocity: .zero, pickupDelay: 60)
        }
        addChat(from: "", text: "Automated check: creatures placed nearby")
        func give(_ name: String, _ count: Int, slot: Int) {
            if let id = items.id(named: name) { s.inventory.slots[slot] = ItemStack(item: id, count: count) }
        }
        switch options.demoScreen {
        case "inventory":
            give("planks", 23, slot: 12)
            give("stick", 7, slot: 20)
            give("iron_pickaxe", 1, slot: 1)
            if let helmet = items.id(named: "iron_helmet") { s.armor[0] = ItemStack(item: helmet, count: 1) }
            openScreen(.inventory)
            if let planks = items.id(named: "planks") {
                craftGrid[0] = ItemStack(item: planks, count: 2)
                craftGrid[2] = ItemStack(item: planks, count: 2)
            }
            mouse += SIMD2(60, 40)
        case "crafting":
            give("planks", 30, slot: 10)
            give("cobblestone", 20, slot: 11)
            openScreen(.crafting)
        case "furnace":
            let pos = BlockPos(Int32(floor(s.player.position.x)), 0, Int32(floor(s.player.position.z)))
            let furnace = s.containers.ensure(pos, kind: .furnace)
            if let ore = items.id(named: "iron_ore"), let coal = items.id(named: "coal") {
                furnace.slots[Container.furnaceInput] = ItemStack(item: ore, count: 5)
                furnace.slots[Container.furnaceFuel] = ItemStack(item: coal, count: 3)
                furnace.cook = 4
                furnace.burnLeft = 30
                furnace.burnTotal = 80
            }
            openScreen(.container(pos, .furnace))
        case "chests", "double-chest":
            // Automated check: a double chest (and a single one) in front of the player.
            let face = BlockVariants.horizontalFacing(-look)
            let base = s.player.position + forward * 3.5
            let y = Int32(s.world.findStandingY(Int(floor(base.x)), Int(floor(base.z)), near: Int(s.player.position.y)) ?? Int(s.player.position.y))
            var placed: [BlockPos] = []
            for offset in [-1.0, 0.0, 2.0] {
                let spot = base + right * offset
                let pos = BlockPos(Int32(floor(spot.x)), y, Int32(floor(spot.z)))
                if let id = s.variants.chest(facing: face) { s.world.setBlock(pos, id); placed.append(pos) }
            }
            if options.demoScreen == "double-chest", let first = placed.first {
                s.prepareContainer(at: first, kind: .chest)
                for (i, name) in ["diamond", "iron_ingot", "planks", "bread", "torch"].enumerated() {
                    if let id = items.id(named: name) {
                        s.containers.ensure(s.chestHalves(first).last ?? first, kind: .chest).slots[i * 4] = ItemStack(item: id, count: 10 + i * 9)
                    }
                }
                openScreen(.container(first, .chest))
            }
        case "creative":
            openScreen(.creative)
        case "pause":
            openPause()
        case "settings":
            openPause()
            screen = .settings
        case "advancements":
            openScreen(.advancements)
        case "deep":
            // Down in the deep layers: a room carved out of the Deep Slate at shown Y -45
            let p = s.player.position
            let x = Int(floor(p.x)), z = Int(floor(p.z)), y = 25
            for dy in 0..<5 { for dz in -6...6 { for dx in -6...6 { s.world.setBlock(BlockPos(x + dx, y + dy, z + dz), Blocks.air) } } }
            s.world.setBlock(BlockPos(x + 3, y + 1, z - 5), Blocks.torch)
            s.player.teleport(to: DVec3(Double(x) + 0.5, Double(y), Double(z) + 0.5))
            if let pick = items.id(named: "diamond_pickaxe") { s.inventory.slots[0] = ItemStack(item: pick, count: 1) }
            showDebug = true
        case "thirdperson":
            cameraView = .behind
        case "front":
            cameraView = .front
        default:
            break
        }
    }

    // MARK: Hosting

    /// Opens this world so friends can join: on the same Wi-Fi straight away, and over the internet
    /// if the router accepts an automatic port mapping.
    func startHosting() {
        guard host == nil, let s = session else { return }
        let meta = s.meta
        let generator = WorldDimension.overworld.makeGenerator(seed: meta.numericSeed, deep: meta.isDeep)
        let server: WireHost
        do {
            server = try WireHost(settings: .init(worldName: meta.name, seed: meta.seed, gameMode: meta.gameMode.rawValue,
                                                  difficulty: meta.difficulty.rawValue, hostName: hostName, deep: meta.isDeep,
                                                  hostID: settings.playerID, hostLook: settings.cosmetics, hardcore: meta.isHardcore),
                                  makeChunk: { [storage, generator, id = meta.id] pos in
                                      storage.loadChunk(worldID: id, pos: pos) ?? generator.generate(pos)
                                  })
        } catch {
            Log.error("Could not host: \(error)", category: "Net")
            addChat(from: "", text: "Couldn't open your world for friends: \(error)")
            return
        }
        server.loadedChunk = { [weak self] pos in
            guard let s = self?.session, s.dimension == .overworld, let slot = s.world.slot(at: pos) else { return nil }
            let copy = Chunk(pos: pos)
            copy.blocks.update(from: slot.chunk.blocks, count: WorldConst.blocksPerChunk)
            return copy
        }
        server.onBlockChange = { [weak self] pos, id in
            guard let self, let s = self.session else { return false }
            guard s.dimension == .overworld else { return false }
            self.applyingRemoteEdit = true
            s.world.setBlock(pos, id)
            self.applyingRemoteEdit = false
            return true
        }
        server.spawnPoint = { [weak self] in self?.session?.spawnLocation ?? .zero }
        server.worldTime = { [weak self] in self?.session?.worldTime ?? 0 }
        server.onChat = { [weak self] from, text in self?.addChat(from: from, text: text) }
        server.onEvent = { [weak self] text in self?.addChat(from: "", text: text) }
        server.onWhisper = { [weak self] from, text in self?.addChat(from: "", text: "\(from) whispers to you: \(text)") }
        server.hardcoreDead = Set(meta.hardcoreDeadPlayers ?? [])
        server.onHardcoreDeath = { [weak self] key, name in
            guard let self, let s = self.session, s.recordHardcoreDeath(key) else { return }
            self.addChat(from: "", text: "\(name) is out of lives and can only spectate now.")
        }
        server.onMet = { [weak self] id, name, look in
            guard let self else { return }
            if FriendList.shared.met(id: id, name: name, look: look, address: nil, myID: self.settings.playerID) {
                self.addChat(from: "", text: "Your friend \(name) is here!")
            }
        }
        host = server

        let port = server.port
        if let ip = NetSocket.localIPv4(), let code = InviteCode.encode(ip: ip, port: port) {
            lanCode = code
            FriendList.shared.myAddress = code
            addChat(from: "", text: "Your world is open! Friends on the same Wi-Fi can join with \(code)")
        } else {
            addChat(from: "", text: "Your world is open on port \(port).")
        }
        addChat(from: "", text: "Asking your router to let friends on other internet join...")
        Thread { [weak self] in
            let result = PortMapping.map(port: port)
            guard let self else {
                if case .success(let m) = result { PortMapping.unmap(m) }
                return
            }
            self.mappingLock.lock()
            let closed = self.mappingClosed
            if !closed { self.mappingResult = result }
            self.mappingLock.unlock()
            if closed, case .success(let m) = result { PortMapping.unmap(m) }
        }.start()
    }

    private func pollMapping() {
        mappingLock.lock()
        let result = mappingResult
        mappingResult = nil
        mappingLock.unlock()
        guard let result else { return }
        switch result {
        case .success(let m):
            mapping = m
            if let ip = m.externalIP, !PortMapping.isPrivate(ip), let code = InviteCode.encode(ip: ip, port: m.port) {
                internetCode = code
                FriendList.shared.myAddress = code
                addChat(from: "", text: "Friends anywhere can join with \(code)")
            } else {
                addChat(from: "", text: "Your router opened the port, but your internet provider shares one address between homes, so only same-Wi-Fi friends can join (or use Tailscale).")
            }
        case .failure(let failure):
            addChat(from: "", text: "Internet play isn't available: \(failure.description)")
            addChat(from: "", text: "Friends on the same Wi-Fi can still join (or use Tailscale).")
        }
    }

    /// This player's movement as the host (player id 0).
    private func hostPlayerState() -> Wire.PlayerState {
        let s = game
        let p = s.player
        return Wire.PlayerState(id: 0, x: p.position.x, y: p.position.y, z: p.position.z, yaw: Float(p.yaw), pitch: Float(p.pitch),
                                moving: Float(p.onGround ? min(1, p.horizontalSpeed / 4.3) : 0), sneaking: p.isSneaking,
                                swinging: s.swingProgress > 0, held: s.inventory.selectedStack.flatMap { items[$0.item]?.name },
                                health: Float(s.health), dead: s.isDead,
                                look: settings.cosmetics.isEmpty ? nil : settings.cosmetics)
    }

    /// Keeps a smoothed model for every friend connected to this host.
    private func syncHostPlayers(dt: Double) {
        guard let host else { return }
        var next: [Int: RemoteEntity] = [:]
        for p in host.players {
            guard let state = p.state else { continue }
            let entity = hostEntities[p.id] ?? RemoteEntity(id: p.id, kind: "player", name: p.name,
                                                             position: DVec3(state.x, state.y, state.z), yaw: Double(state.yaw))
            entity.apply(state)
            entity.update(dt: dt)
            next[p.id] = entity
        }
        hostEntities = next
    }

    // MARK: Leaving

    func quitToTitle() {
        running = false
    }

    private func shutdown() {
        PlayerStats.shared.submitNow()
        setMouseCaptured(false)
        audio?.stopLoops()
        if !chatOpen { _ = SDL_StopTextInput(window) }
        if let s = session {
            if let cursor = cursorStack { stash(cursor, s) }
            for stack in craftGrid.compactMap({ $0 }) { stash(stack, s) }
            s.shutdown()
        }
        session = nil
        mappingLock.lock()
        mappingClosed = true
        let late = mappingResult
        mappingLock.unlock()
        if case .success(let m)? = late { PortMapping.unmap(m) }
        if let mapping { PortMapping.unmap(mapping) }
        host?.stop()
        jobs.shutdown()
    }
}
