import Foundation
import CSDL3
import CGPUPreference
import DinoCraftCore
@testable import DinoCraftGame
#if os(Windows)
import WinSDK
#endif

// DinoCraft for Windows: a title screen with your worlds, playing on your own, hosting friends,
// and joining games hosted on a Mac or another Windows PC.
//
// Options:
//   --join <code or address>  join a friend's game straight away (invite code like DINO-3M4KA-9QX2B, or an IP address)
//   --name <name>             player name when joining
//   --host <name>             open "Windows World" for friends straight away
//   --seed <text>             seed when "Windows World" is created by --host or an automated check
//   --render-distance <n>     chunks (default: the Settings value)
//   --console                 keep the console window open (for log output)
//   --screenshot <path.png>   automated check: save a screenshot and quit
//   --frames <n>              frames to draw after loading before the screenshot (default 30)
//   --demo-entities           automated check: place sample creatures in view
//   --demo-screen <name>      automated check: inventory, crafting, furnace, creative, pause, advancements,
//                             menu, worlds, create, toonland, toonland-boss or hardcore

struct Options {
    var seed = ""
    var renderDistance: Int?
    var screenshotPath: String?
    var frames = 30
    var join: String?
    var name: String?
    var demoEntities = false
    var demoScreen: String?
    var hostName: String?
    var console = false
    /// Automated check: hide the console like a double-click launch does.
    var hideConsole = false
    /// This is DinoCraft Launcher (DinoCraft Launcher.exe, or --launcher): Play starts DinoCraft.exe.
    var launcherOnly = false
    /// Started by DinoCraft Launcher: go straight to the title screen.
    var skipLauncher = false
    /// Automated check: still do the launcher's online work (updates, reviews, friends, stats) while taking a screenshot.
    var online = false

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        o.launcherOnly = URL(fileURLWithPath: args.first ?? "").lastPathComponent.lowercased().contains("launcher")
        var i = 1
        func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
        while i < args.count {
            switch args[i] {
            case "--seed": o.seed = next() ?? ""
            case "--render-distance": o.renderDistance = max(2, min(GameSettings.maxRenderDistance, Int(next() ?? "") ?? 8))
            case "--screenshot": o.screenshotPath = next()
            case "--frames": o.frames = max(1, Int(next() ?? "") ?? 30)
            case "--join": o.join = next()
            case "--name": o.name = next()
            case "--demo-entities": o.demoEntities = true
            case "--demo-screen": o.demoScreen = next()
            case "--host": o.hostName = next()
            case "--console": o.console = true
            case "--hide-console": o.hideConsole = true
            case "--launcher": o.launcherOnly = true
            case "--skip-launcher": o.skipLauncher = true
            case "--online": o.online = true
            default: break
            }
            i += 1
        }
        return o
    }
}

/// Registries and GPU resources shared by the menus and every game session.
struct GameContent {
    let blocks: BlockRegistry
    let items: ItemRegistry
    let recipes: RecipeRegistry
    let smelting: SmeltingRegistry
    let renderer: WinRenderer
}

private let SDL_WINDOW_OPENGL_FLAG: UInt64 = 0x0000_0002
private let SDL_WINDOW_RESIZABLE_FLAG: UInt64 = 0x0000_0020
private let SDL_WINDOW_HIGH_PIXEL_DENSITY_FLAG: UInt64 = 0x0000_2000
private let SDL_MESSAGEBOX_ERROR_FLAG: UInt32 = 0x0000_0010

func fail(_ message: String, window: OpaquePointer? = nil) -> Never {
    Log.fatal(message, category: "App")
    Log.shared.flush()
    _ = SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR_FLAG, "DinoCraft", message, window)
    exit(1)
}

/// Player names follow the host's rules: letters, numbers and underscores, up to 16 characters.
/// DinoCraft Launcher's Play: starts DinoCraft.exe from the same folder, straight to the title screen.
func launchGame(join address: String? = nil) {
    let here = URL(fileURLWithPath: CommandLine.arguments.first ?? "").deletingLastPathComponent()
    let game = here.appendingPathComponent("DinoCraft.exe")
    let process = Process()
    process.executableURL = game
    process.arguments = ["--skip-launcher"] + (address.map { ["--join", $0] } ?? [])
    process.currentDirectoryURL = here
    do {
        try process.run()
        Log.info("Launcher started \(game.path)", category: "App")
    } catch {
        Log.error("Couldn't start DinoCraft: \(error)", category: "App")
    }
}

func cleanName(_ raw: String) -> String {
    let name = String(raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(16))
    return name.isEmpty ? "Explorer" : name
}

let options = Options.parse(CommandLine.arguments)
try? GamePaths.ensureDirectories()
Log.shared.start(directory: GamePaths.logs)
Log.info("DinoCraft for Windows starting · data: \(GamePaths.root.path)", category: "App")

#if os(Windows)
if options.hideConsole || (options.screenshotPath == nil && !options.console) {
    // Started by double-clicking: hide the empty console window (keep it when run from a terminal).
    // Nothing may write to the console afterwards, so logging goes to the log file only.
    var processes = [UInt32](repeating: 0, count: 4)
    if options.hideConsole || GetConsoleProcessList(&processes, 4) <= 1 {
        Log.shared.echoToConsole = false
        _ = FreeConsole()
    }
}
#endif
// Keep crash details (in a file next to the log when there's no console to show them).
WinCrash.install(redirectErrors: !Log.shared.echoToConsole)

guard SDL_Init(SDL_INIT_VIDEO) else { fail("Could not start SDL: \(String(cString: SDL_GetError()))") }
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, 1)   // core profile
_ = SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)
_ = SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
_ = SDL_GL_SetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1)

guard let window = SDL_CreateWindow(options.launcherOnly ? "DinoCraft Launcher" : "DinoCraft", options.launcherOnly ? 1180 : 1280, options.launcherOnly ? 700 : 720,
                                    SDL_WINDOW_OPENGL_FLAG | SDL_WINDOW_RESIZABLE_FLAG | SDL_WINDOW_HIGH_PIXEL_DENSITY_FLAG) else {
    fail("Could not create the game window: \(String(cString: SDL_GetError()))")
}
guard let context = SDL_GL_CreateContext(window) else {
    fail("DinoCraft needs OpenGL 3.3, which your graphics driver doesn't provide. Updating your graphics driver usually fixes this.\n\n\(String(cString: SDL_GetError()))", window: window)
}
_ = SDL_GL_MakeCurrent(window, context)
let settingsStore = SettingsStore()
PlayerLook.settle(settingsStore)
GameLinks.setUpStats(settingsStore)
let wantsVSync = options.screenshotPath == nil && settingsStore.settings.vsync
if !SDL_GL_SetSwapInterval(wantsVSync ? 1 : 0) { Log.warning("The driver refused to set VSync \(wantsVSync ? "on" : "off")", category: "Renderer") }

do {
    let gl = try GL()
    Log.info("OpenGL \(gl.string(GLC.VERSION)) · \(gl.string(GLC.RENDERER)) · \(gl.string(GLC.VENDOR))", category: "Renderer")
    Log.info("Asks for the discrete GPU on dual-GPU laptops: \(dinocraft_prefers_discrete_gpu() == 1 ? "yes" : "no")", category: "Renderer")
    if let vram = gl.videoMemoryMB() { Log.info("Video memory: \(vram.total) MB, \(vram.free) MB free", category: "Renderer") }
    let blocks = try BlockRegistry.loadDefault()
    let items = try ItemRegistry.loadDefault(blocks: blocks)
    let recipes = try RecipeRegistry.loadDefault(items: items)
    let smelting = try SmeltingRegistry.loadDefault(items: items)
    let pack = TexturePackLibrary.all().first { $0.id == settingsStore.settings.texturePack } ?? TexturePackLibrary.defaultPack
    let renderer = try WinRenderer(gl: gl, blocks: blocks, items: items, pack: pack)
    SettingsPanel.applyLooks(settingsStore.settings, to: renderer)
    if settingsStore.settings.fullscreen { _ = SDL_SetWindowFullscreen(window, true) }
    let content = GameContent(blocks: blocks, items: items, recipes: recipes, smelting: smelting, renderer: renderer)
    let audio = WinAudio()
    audio.apply(settingsStore.settings)

    /// Plays on a friend's game. Returns whether the player closed the window, and why the game ended if it wasn't their choice.
    func join(_ network: WinNetwork) -> (quit: Bool, message: String?) {
        var sessionOptions = options
        if sessionOptions.renderDistance == nil { sessionOptions.renderDistance = max(2, min(GameSettings.maxRenderDistance, settingsStore.settings.renderDistance)) }
        SDL_SetWindowTitle(window, "DinoCraft · \(network.welcome.worldName)")
        // The full game, playing the friend's world (the same as on the Mac).
        guard let client = WinSessionClient(joined: network) else {
            network.connection.close()
            return (false, "The host's world couldn't be read. Make sure you both have the latest DinoCraft.")
        }
        let game = WinSolo(gl: gl, window: window, content: content, audio: audio, settings: settingsStore, options: sessionOptions,
                           world: client.meta, isNew: false, hostName: nil, join: client)
        game.run()
        SDL_SetWindowTitle(window, "DinoCraft")
        return (game.quitRequested, game.disconnectReason.map { "You left the game: \($0)" })
    }

    /// Plays one of your own worlds (optionally opened to friends). Returns whether the player closed the window.
    func play(_ world: WorldMetadata, isNew: Bool, hostName: String?) -> Bool {
        SDL_SetWindowTitle(window, "DinoCraft · \(world.name)")
        let game = WinSolo(gl: gl, window: window, content: content, audio: audio, settings: settingsStore, options: options,
                           world: world, isNew: isNew, hostName: hostName)
        game.run()
        SDL_SetWindowTitle(window, "DinoCraft")
        return game.quitRequested
    }

    if let address = options.join {
        let username = cleanName(options.name ?? settingsStore.settings.username)
        let joined: WinNetwork
        do {
            joined = try WinNetwork.join(address: address, username: username, playerID: settingsStore.settings.playerID,
                                         look: settingsStore.settings.cosmetics)
        } catch {
            fail("Couldn't join the game:\n\n\(error)", window: window)
        }
        if let message = join(joined).message {
            Log.info(message, category: "Net")
        }
    } else if options.hostName != nil || (options.screenshotPath != nil && !["menu", "worlds", "create", "cosmetics", "skin", "skin-arm", "reviews", "friends", "leaderboard", "crash"].contains(options.demoScreen ?? "")) {
        let storage = WorldStorage()
        if let existing = storage.listWorlds().first(where: { $0.name == "Windows World" }) {
            _ = play(existing, isNew: false, hostName: options.hostName.map(cleanName))
        } else {
            let meta = try storage.createWorld(name: "Windows World", seedText: options.seed, gameMode: .survival, difficulty: .normal,
                                               hardcore: options.demoScreen == "hardcore")
            _ = play(meta, isNew: true, hostName: options.hostName.map(cleanName))
        }
    } else {
        let menus = WinMenus(window: window, renderer: renderer, store: settingsStore, audio: audio, options: options)
        var message: String?
        menuLoop: while true {
            let result: (quit: Bool, message: String?)
            switch menus.run(message: message) {
            case .quit:
                break menuLoop
            case .play(let meta, let isNew, let hostName):
                result = (play(meta, isNew: isNew, hostName: hostName), nil)
            case .join(let network):
                result = join(network)
            case .launchGame(let address):
                launchGame(join: address)
                break menuLoop
            }
            if result.quit || options.screenshotPath != nil { break }
            message = result.message
        }
    }
    audio.shutdown()
    WinPresence.shared.shutdown()
} catch {
    fail(String(describing: error), window: window)
}

SDL_GL_DestroyContext(context)
SDL_DestroyWindow(window)
SDL_Quit()
PlayerStats.shared.save()
Log.info("DinoCraft closed", category: "App")
Log.shared.flush()
