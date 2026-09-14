import Foundation
import CSDL3
import DinoCraftCore
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
//   --demo-entities           automated check: place sample players and creatures in view
//   --demo-screen <name>      automated check: inventory, menu or worlds

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

    static func parse(_ args: [String]) -> Options {
        var o = Options()
        var i = 1
        func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
        while i < args.count {
            switch args[i] {
            case "--seed": o.seed = next() ?? ""
            case "--render-distance": o.renderDistance = max(2, min(16, Int(next() ?? "") ?? 8))
            case "--screenshot": o.screenshotPath = next()
            case "--frames": o.frames = max(1, Int(next() ?? "") ?? 30)
            case "--join": o.join = next()
            case "--name": o.name = next()
            case "--demo-entities": o.demoEntities = true
            case "--demo-screen": o.demoScreen = next()
            case "--host": o.hostName = next()
            case "--console": o.console = true
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
func cleanName(_ raw: String) -> String {
    let name = String(raw.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(16))
    return name.isEmpty ? "Explorer" : name
}

let options = Options.parse(CommandLine.arguments)
try? GamePaths.ensureDirectories()
Log.shared.start(directory: GamePaths.logs)
Log.info("DinoCraft for Windows starting · data: \(GamePaths.root.path)", category: "App")

#if os(Windows)
if options.screenshotPath == nil && !options.console {
    // Started by double-clicking: hide the empty console window (keep it when run from a terminal).
    var processes = [UInt32](repeating: 0, count: 4)
    if GetConsoleProcessList(&processes, 4) <= 1 { _ = FreeConsole() }
}
#endif

guard SDL_Init(SDL_INIT_VIDEO) else { fail("Could not start SDL: \(String(cString: SDL_GetError()))") }
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, 1)   // core profile
_ = SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)
_ = SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
_ = SDL_GL_SetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1)

guard let window = SDL_CreateWindow("DinoCraft", 1280, 720,
                                    SDL_WINDOW_OPENGL_FLAG | SDL_WINDOW_RESIZABLE_FLAG | SDL_WINDOW_HIGH_PIXEL_DENSITY_FLAG) else {
    fail("Could not create the game window: \(String(cString: SDL_GetError()))")
}
guard let context = SDL_GL_CreateContext(window) else {
    fail("DinoCraft needs OpenGL 3.3, which your graphics driver doesn't provide. Updating your graphics driver usually fixes this.\n\n\(String(cString: SDL_GetError()))", window: window)
}
_ = SDL_GL_MakeCurrent(window, context)
_ = SDL_GL_SetSwapInterval(options.screenshotPath == nil ? 1 : 0)

let settingsStore = SettingsStore()

do {
    let gl = try GL()
    Log.info("OpenGL \(gl.string(GLC.VERSION)) · \(gl.string(GLC.RENDERER)) · \(gl.string(GLC.VENDOR))", category: "Renderer")
    let blocks = try BlockRegistry.loadDefault()
    let items = try ItemRegistry.loadDefault(blocks: blocks)
    let recipes = try RecipeRegistry.loadDefault(items: items)
    let renderer = try WinRenderer(gl: gl, blocks: blocks, items: items)
    let content = GameContent(blocks: blocks, items: items, recipes: recipes, renderer: renderer)
    let audio = WinAudio()
    audio.apply(settingsStore.settings)

    /// Runs one game session. Returns whether the player closed the window, and why the game ended if it wasn't their choice.
    func play(network: WinNetwork?, world: WorldMetadata?, hostName: String?) throws -> (quit: Bool, message: String?) {
        var sessionOptions = options
        if sessionOptions.renderDistance == nil { sessionOptions.renderDistance = max(2, min(16, settingsStore.settings.renderDistance)) }
        SDL_SetWindowTitle(window, "DinoCraft · \(network?.welcome.worldName ?? world?.name ?? "")")
        let game = try WinGame(gl: gl, window: window, content: content, audio: audio, settings: settingsStore, options: sessionOptions,
                               network: network, world: world, hostName: hostName)
        let reason = game.run()
        SDL_SetWindowTitle(window, "DinoCraft")
        return (game.quitRequested, reason.map { "You left the game: \($0)" })
    }

    if let address = options.join {
        let username = cleanName(options.name ?? settingsStore.settings.username)
        let joined: WinNetwork
        do {
            joined = try WinNetwork.join(address: address, username: username)
        } catch {
            fail("Couldn't join the game:\n\n\(error)", window: window)
        }
        if let message = try play(network: joined, world: nil, hostName: nil).message {
            Log.info(message, category: "Net")
        }
    } else if options.hostName != nil || (options.screenshotPath != nil && options.demoScreen != "menu" && options.demoScreen != "worlds") {
        let storage = WorldStorage()
        let meta = try storage.listWorlds().first { $0.name == "Windows World" }
            ?? storage.createWorld(name: "Windows World", seedText: options.seed, gameMode: .creative, difficulty: .normal)
        _ = try play(network: nil, world: meta, hostName: options.hostName.map(cleanName))
    } else {
        let menus = WinMenus(window: window, renderer: renderer, store: settingsStore, audio: audio, options: options)
        var message: String?
        menuLoop: while true {
            let result: (quit: Bool, message: String?)
            switch menus.run(message: message) {
            case .quit:
                break menuLoop
            case .play(let meta, let hostName):
                do {
                    result = try play(network: nil, world: meta, hostName: hostName)
                } catch {
                    Log.error("Could not open world: \(error)", category: "Game")
                    result = (false, "Couldn't open the world: \(error)")
                }
            case .join(let network):
                result = try play(network: network, world: nil, hostName: nil)
            }
            if result.quit || options.screenshotPath != nil { break }
            message = result.message
        }
    }
    audio.shutdown()
} catch {
    fail(String(describing: error), window: window)
}

SDL_GL_DestroyContext(context)
SDL_DestroyWindow(window)
SDL_Quit()
Log.info("DinoCraft closed", category: "App")
Log.shared.flush()
