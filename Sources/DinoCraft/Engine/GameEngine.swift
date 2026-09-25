import AppKit
import MetalKit
import Network
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Top-level coordinator: owns the renderer, input, audio, Discord presence,
/// job system, registries, the screen stack and the active game session, and
/// drives the per-frame update → render loop.
final class GameEngine: NSObject, MTKViewDelegate {
    let window: GameWindow
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
    let presence: PresenceManager
    let storage = WorldStorage()
    let versionString: String
    /// Checks the public releases page for a newer DinoCraft (the launcher shows the result).
    let updater = GameUpdater(assetName: "DinoCraft-Mac.zip")
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
    private var script: ScriptRunner?

    // Multiplayer
    private(set) var server: GameServer?
    let portMapper = PortMapper()
    private(set) var internetAddress: String?
    private(set) var internetStatus: String?
    private(set) var inviteCode: String?
    private var internetRenewTimer = 0.0
    private(set) var client: GameClient?
    let discovery = LANDiscovery()
    private(set) var chatLog: [(text: String, time: Double)] = []
    private(set) var lastViewProj = matrix_identity_float4x4
    private(set) var showPlayerList = false
    var isMultiplayer: Bool { server != nil || client != nil }
    var remotePlayers: [RemotePlayer] { server?.remotePlayers ?? client?.remotePlayers ?? [] }

    func requestScreenshot(_ url: URL) { pendingScreenshot = url }

    var settings: GameSettings { settingsStore.settings }
    var activeWorld: World? { session?.world ?? menuWorld }

    enum EngineError: Error, CustomStringConvertible {
        case data(Error)
        var description: String {
            switch self { case .data(let e): return "Game data could not be loaded: \(e)" }
        }
    }

    init(window: GameWindow, device: MTLDevice, settings: SettingsStore, options: LaunchOptions) throws {
        self.window = window
        self.view = window.gameView
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
        presence = PresenceManager { DiscordIPCClient(clientID: $0) }
        super.init()

        if let url = try? ResourceLocator.url("Art/icon_1024.png") {
            iconTexture = ImageLoader.texture(url: url, device: device, maxSize: 320)
        }
        ui.onSound = { [weak self] sound in
            switch sound {
            case .hover: self?.audio.play("ui_hover", volume: 0.25)
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
        if let layer = view.layer as? CAMetalLayer {
            layer.displaySyncEnabled = settings.vsync
        }
        let screenMax = window.screen?.maximumFramesPerSecond ?? 120
        view.preferredFramesPerSecond = settings.vsync ? screenMax : (settings.maxFPS == 0 ? 1000 : settings.maxFPS)
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true
        createMenuWorld()
        screens = [MainMenuScreen()]
        if options.script == nil && options.autoWorld == nil && options.joinAddress == nil && !options.skipLauncher {
            // The launcher comes first; Play reveals the main menu underneath.
            screens.append(LauncherScreen())
            if settings.checkForUpdates { updater.check() }
        }
        if let name = options.username, Username.validate(name) == nil { settingsStore.update { $0.username = name } }
        if Username.validate(settings.username) != nil && options.script == nil && options.autoWorld == nil && options.joinAddress == nil {
            screens.append(UsernameScreen(current: "", firstRun: true))
        }
        audio.applyVolumes(settings)
        audio.playMusic("menu_theme", loop: true, fade: 3)
        presence.setEnabled(settings.discordRichPresence)
        if let shot = options.screenshotPath { pendingScreenshotAt = (URL(fileURLWithPath: shot), options.screenshotAfter) }
        if let path = options.script {
            script = ScriptRunner(path: path)
            input.headless = script != nil
        }
        if let name = options.autoWorld { autoStart(world: name) }
        if let address = options.joinAddress { joinGame(address: address) }
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
                          renderDistance: min(settings.renderDistance, 12))
    }

    func shutdown() {
        PlayerStats.shared.save()
        input.setMouseCaptured(false)
        portMapper.unmap()
        server?.stop()
        client?.connection.close()
        session?.shutdown()
        session = nil
        menuWorld?.shutdown()
        jobs.shutdown()
        presence.shutdown()
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
        portMapper.unmap()
        internetAddress = nil
        internetStatus = nil
        inviteCode = nil
        server?.stop()
        server = nil
        client?.connection.close()
        client = nil
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

    func quitGame() { NSApp.terminate(nil) }

    /// DinoCraft Launcher's Play: opens DinoCraft.app (next to the launcher) and closes the launcher.
    /// Opens DinoCraft.app from the launcher (joining `address` straight away if given) and quits the launcher.
    func launchGameApp(join address: String? = nil) {
        let here = Bundle.main.bundleURL
        let sibling = here.deletingLastPathComponent().appendingPathComponent("DinoCraft.app")
        // Next to the launcher, or wherever macOS knows DinoCraft is installed.
        let found = FileManager.default.fileExists(atPath: sibling.path) ? sibling
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.dinocraft.game")
        guard let game = found, game.standardizedFileURL != here.standardizedFileURL else {
            // No separate game app to open: play right here instead.
            Log.info("DinoCraft.app not found; playing in the launcher window", category: "App")
            if let address { joinGame(address: address) } else { popScreen() }
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = ["--skip-launcher"] + (address.map { ["--join", $0] } ?? [])
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: game, configuration: config) { _, error in
            DispatchQueue.main.async {
                if let error {
                    // Couldn't open the game app: play right here instead.
                    Log.warning("Couldn't open DinoCraft.app (\(error.localizedDescription)); playing in the launcher window", category: "App")
                    if let address { self.joinGame(address: address) } else { self.popScreen() }
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Advancements

    private(set) var advancementToasts: [(def: AdvancementDef, time: Double)] = []
    /// Where the minimap ends on screen (0 when hidden), so cards in the corner go below it.
    var minimapBottom: Float = 0

    func announceAdvancement(_ def: AdvancementDef) {
        advancementToasts.removeAll { time - $0.time > 10 }
        advancementToasts.append((def, time))
        audio.play("discover", volume: 0.7)
        if isMultiplayer { sendChat("made the advancement [\(def.title)]") }
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

    func openTexturePacksFolder() {
        TexturePackLibrary.prepareUserFolder()
        refreshTexturePacks()
        NSWorkspace.shared.open(TexturePackLibrary.userFolder)
    }

    // MARK: Multiplayer

    func hostGame() {
        guard let s = session, server == nil, client == nil, !s.isLoading else { return }
        let host = Username.validate(settings.username) == nil ? settings.username : "Host"
        let srv = GameServer(session: s, hostName: host)
        srv.onEvent = { [weak self] text in self?.showToast(text) }
        srv.onChat = { [weak self] from, text in self?.addChat(from: from, text: text) }
        srv.onWhisper = { [weak self] from, text in self?.addChat(from: "", text: "\(from) whispers to you: \(text)") }
        srv.hostID = settings.playerID
        srv.hostLook = settings.cosmetics
        srv.onMet = { [weak self] id, name, look in
            guard let self else { return }
            if FriendList.shared.met(id: id, name: name, look: look, address: nil, myID: self.settings.playerID) {
                self.addChat(from: "", text: "Your friend \(name) is here!")
            }
        }
        do {
            try srv.start()
            server = srv
            s.network = srv
            let ip = NetworkInfo.localIPv4() ?? "this Mac's IP address"
            if let local = NetworkInfo.localIPv4(), let code = InviteCode.encode(ip: local, port: NetConfig.port) { FriendList.shared.myAddress = code }
            showToast("Open to LAN on \(ip):\(NetConfig.port)")
            addChat(from: "", text: "Your world is open! Friends can join at \(ip):\(NetConfig.port)")
        } catch {
            Log.error("Could not host: \(error)", category: "Net")
            showToast("Could not open to LAN: \(error.localizedDescription)")
        }
    }

    /// Asks the home router to forward the game port so friends on other networks can join.
    func openToInternet() {
        if server == nil { hostGame() }
        guard server != nil, internetStatus != "Opening…", internetAddress == nil else { return }
        internetStatus = "Opening…"
        addChat(from: "", text: "Asking your router to open port \(NetConfig.port)…")
        portMapper.map(port: NetConfig.port) { [weak self] result in
            guard let self, self.server != nil else { return }
            switch result {
            case .success(let mapping):
                if let ip = mapping.externalIP, !PortMapper.isPrivate(ip) {
                    self.internetAddress = "\(ip):\(mapping.port)"
                    self.internetStatus = "Open"
                    self.internetRenewTimer = 45 * 60
                    let code = InviteCode.encode(ip: ip, port: mapping.port)
                    self.inviteCode = code
                    if let code { FriendList.shared.myAddress = code }
                    self.addChat(from: "", text: "Open to the internet! Invite code \(code ?? "?") (address \(ip):\(mapping.port)). Press Esc to copy it.")
                    self.showToast("Invite code \(code ?? "\(ip):\(mapping.port)")")
                } else {
                    self.internetStatus = "Blocked"
                    self.addChat(from: "", text: "Your router opened the port, but your internet provider hides your public address (\(mapping.externalIP ?? "unknown")). Use Tailscale instead (see the README).")
                    self.showToast("Your internet provider blocks direct joining")
                }
            case .failure(let failure):
                self.internetStatus = "Failed"
                self.addChat(from: "", text: "\(failure.description) Forward TCP port \(NetConfig.port) on your router, or use Tailscale.")
                self.showToast("Couldn't open to the internet")
            }
        }
    }

    func copyInviteCode() {
        guard let address = internetAddress else { return }
        let text = "Join my DinoCraft world! Invite code: \(inviteCode ?? address)  (or address \(address))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showToast("Invite code copied — paste it to your friends")
    }

    func stopHosting() {
        portMapper.unmap()
        internetAddress = nil
        internetStatus = nil
        inviteCode = nil
        server?.stop()
        server = nil
        session?.network = nil
        showToast("Your world is no longer shared")
    }

    func joinGame(address: String) {
        let (host, port) = Wire.parseAddress(address)
        let label = InviteCode.decode(address) != nil ? "invite code \(address.uppercased())" : "\(host):\(port)"
        connect(NetConnection(host: host, port: port), label: label, address: address.trimmingCharacters(in: .whitespaces))
    }

    func joinGame(lanHost: LANDiscovery.Host) {
        connect(NetConnection(connection: NWConnection(to: lanHost.endpoint, using: .tcp), label: lanHost.name), label: lanHost.name)
    }

    private func connect(_ connection: NetConnection, label: String, address: String? = nil) {
        guard session == nil, client == nil else { return }
        guard Username.validate(settings.username) == nil else {
            pushScreen(UsernameScreen(current: settings.username, firstRun: false))
            return
        }
        let c = GameClient(connection: connection, username: settings.username, label: label)
        c.playerIdentity = (settings.playerID, settings.cosmetics)
        c.address = address
        c.onWelcome = { [weak self, weak c] welcome in
            guard let self, let c else { return }
            self.startRemoteSession(welcome, client: c)
        }
        c.onDisconnect = { [weak self] reason in self?.clientDisconnected(reason) }
        c.onChat = { [weak self] from, text in self?.addChat(from: from, text: text) }
        client = c
        pushScreen(ConnectingScreen(label: label))
        Log.info("Joining \(label) as \(settings.username)", category: "Net")
        c.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self, weak c] in
            guard let self, let c, self.client === c, self.session == nil else { return }
            let waiting = c.connection.lastWaitingReason
            c.connection.close()
            var message = "Couldn't reach \(label). Check the code or address, make sure the host pressed Open to LAN or Open to Internet, and that you both have the latest DinoCraft."
            if let waiting {
                message += "\n\nmacOS said: \(waiting)\nIf your friend is on the same Wi-Fi, open System Settings → Privacy & Security → Local Network and turn on DinoCraft, then try again."
            }
            self.clientDisconnected(message)
        }
    }

    func cancelJoin() {
        let c = client
        client = nil
        c?.connection.close()
        if topScreen is ConnectingScreen { popScreen() }
    }

    private func clientDisconnected(_ reason: String) {
        guard client != nil else { return }
        Log.info("Disconnected from host: \(reason)", category: "Net")
        client = nil
        if session != nil {
            session?.network = nil
            saveAndQuitToTitle()
        }
        discovery.stop()
        screens = [MainMenuScreen(), MultiplayerScreen(), MessageScreen(title: "Disconnected", message: reason)]
    }

    private func startRemoteSession(_ w: WelcomeMessage, client c: GameClient) {
        guard session == nil else { return }
        discovery.stop()
        screens.removeAll()
        menuWorld?.shutdown()
        menuWorld = nil
        let now = Date()
        let meta = WorldMetadata(formatVersion: w.deep == true ? WorldMetadata.currentFormat : 1, id: "remote", name: w.worldName, seedText: w.seed, seed: w.seed,
                                 gameMode: GameMode(rawValue: w.gameMode) ?? .survival, difficulty: Difficulty(rawValue: w.difficulty) ?? .normal,
                                 createdAt: now, lastPlayed: now, playTimeSeconds: 0, worldTime: w.worldTime,
                                 spawnX: Int(floor(w.x)), spawnY: Int(floor(w.y)), spawnZ: Int(floor(w.z)),
                                 hardcore: w.hardcore ? true : nil, hardcoreDead: w.spectator == true ? true : nil)
        let s = GameSession(meta: meta, isNew: false, storage: storage, blocks: blocks, items: items, meshFactory: meshFactory, jobs: jobs,
                            renderDistance: settings.renderDistance, remote: true)
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
        s.network = c
        c.session = s
        s.remoteChunkRequester = { [weak c] list in c?.requestChunks(list) }
        if let dim = WorldDimension(rawValue: w.dimension), dim != .overworld {
            s.followDimension(dim, position: DVec3(w.x, w.y, w.z))
        }
        session = s
        audio.stopMusic(fade: 2.5)
        musicTimer = 50
        curtain = 1
        addChat(from: "", text: "Joined \(w.worldName)")
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
        if let server {
            server.broadcastChat(from: settings.username, text: text)
            addChat(from: settings.username, text: text)
        } else {
            client?.sendChat(text)
        }
    }

    func whisper(to name: String, text: String) -> String? {
        guard !text.isEmpty else { return "Type a message after the name." }
        if let server {
            guard server.whisper(from: settings.username, to: name, text: text) else { return "No player called \(name) is here." }
            addChat(from: "", text: "You whisper to \(name): \(text)")
            return nil
        }
        guard let client else { return "Private messages need other players in the game." }
        client.sendChat(text, to: name)
        return nil
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
        if s.vsync != old.vsync || s.maxFPS != old.maxFPS { applyDisplaySettings() }
        if s.fullscreen != window.styleMask.contains(.fullScreen) { window.toggleFullScreen(nil) }
        if (s.windowWidth != old.windowWidth || s.windowHeight != old.windowHeight) && !window.styleMask.contains(.fullScreen) {
            window.setContentSize(NSSize(width: s.windowWidth, height: s.windowHeight))
            window.center()
        }
        if s.graphicsQuality != old.graphicsQuality {
            let fancy = s.graphicsQuality != .fast
            jobs.forEachContext { $0.mesher.fancyLeaves = fancy }
            activeWorld?.invalidateAllMeshes()
        }
        audio.applyVolumes(s)
        if s.discordRichPresence != old.discordRichPresence { presence.setEnabled(s.discordRichPresence) }
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
            Log.info("Exiting after \(exitAfter)s (--exit-after)", category: "Engine")
            NSApp.terminate(nil)
        }
    }

    private func update(dt: Double) {
        let viewSize = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
        ui.begin(viewSize: viewSize, backingScale: Float(window.backingScaleFactor), guiScale: Float(settings.guiScale), dt: dt, time: time)
        for s in screens { s.age += dt }
        if let t = toast { toast = t.1 - dt > 0 ? (t.0, t.1 - dt) : nil }
        script?.update(dt: dt, engine: self)

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
            let focused = (NSApp.isActive && window.isKeyWindow) || script != nil
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
            showPlayerList = isMultiplayer && input.keysDown.contains(KeyCode.tab)
            let controls = screens.isEmpty && !s.isLoading && !s.isDead && focused
            input.setMouseCaptured(controls)
            let paused = !isMultiplayer && screens.contains { $0 is PauseScreen || $0 is SettingsScreen }
            s.update(dt: dt, input: controls ? input : nil, settings: settings, paused: paused)
            particles.update(dt: paused ? 0 : dt, session: s, blocks: blocks)
            server?.tick(dt: dt)
            if internetAddress != nil {
                // NAT-PMP / UPnP leases expire; renew well before they do.
                internetRenewTimer -= dt
                if internetRenewTimer <= 0 {
                    internetRenewTimer = 45 * 60
                    portMapper.map(port: NetConfig.port) { result in
                        if case .failure(let failure) = result { Log.warning("Router port renewal failed: \(failure)", category: "Net") }
                    }
                }
            }
            client?.tick(dt: dt)
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
                w.renderDistance = min(settings.renderDistance, 12)
                w.update(focus: camera.position)
            }
        }
        camera.far = Float(max(600, (settings.renderDistance + 2) * 16 * 2))
        audio.update(dt: dt)
        presence.update(activityState(), showWorldName: settings.showWorldNameInDiscord)
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
        if showDebug { DebugOverlay.draw(ui, engine: self) }
        if curtain > 0 { ui.draw.fill(Rect(0, 0, ui.size.x, ui.size.y), Color(hex: 0x0A0614, alpha: curtain)) }
        ui.end()

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
        let raining = s.dimension == .overworld && WeatherSystem.precipitation(for: s.biome) == .rain
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

    func applicationLostFocus() {
        input.setMouseCaptured(false)
        guard script == nil else { return }
        input.releaseAll()
        if let s = session, !s.isLoading, !s.isDead, screens.isEmpty { pushScreen(PauseScreen()) }
    }

    func applicationGainedFocus() {}

    func fullscreenChanged(_ isFullscreen: Bool) {
        settingsStore.update { $0.fullscreen = isFullscreen }
    }

    func windowResized() {
        guard !window.styleMask.contains(.fullScreen) else { return }
        let size = window.contentView?.bounds.size ?? .zero
        settingsStore.update { s in
            s.windowWidth = Int(size.width)
            s.windowHeight = Int(size.height)
        }
    }
}

extension GameEngine: CommandHost {
    var isClient: Bool { client != nil }

    func give(playerNamed name: String, item: String, count: Int) -> Bool {
        server?.give(playerNamed: name, item: item, count: count) ?? false
    }
}
