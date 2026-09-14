import Foundation
import CSDL3
import DinoCraftCore

// DinoCraft for Windows: explore and build on your own, or join a friend's game hosted on a Mac.
//
// Options:
//   --join <code or address>  join a friend's game (invite code like DINO-3M4KA-9QX2B, or an IP address)
//   --name <name>             player name when joining
//   --seed <text>             seed for a new single-player world
//   --render-distance <n>     chunks (default 8)
//   --screenshot <path.png>   automated check: wait for the world to load, save a screenshot, quit
//   --frames <n>              frames to draw after loading before the screenshot (default 30)
//   --demo-entities           automated check: place sample players and creatures in view

struct Options {
    var seed = ""
    var renderDistance = 8
    var screenshotPath: String?
    var frames = 30
    var join: String?
    var name: String?
    var demoEntities = false

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
            default: break
            }
            i += 1
        }
        return o
    }
}

private let SDL_WINDOW_OPENGL_FLAG: UInt64 = 0x0000_0002
private let SDL_WINDOW_RESIZABLE_FLAG: UInt64 = 0x0000_0020
private let SDL_WINDOW_HIGH_PIXEL_DENSITY_FLAG: UInt64 = 0x0000_2000
private let SDL_MESSAGEBOX_ERROR_FLAG: UInt32 = 0x0000_0010
private let SDL_MESSAGEBOX_INFORMATION_FLAG: UInt32 = 0x0000_0040

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

var options = Options.parse(CommandLine.arguments)
try? GamePaths.ensureDirectories()
Log.shared.start(directory: GamePaths.logs)
Log.info("DinoCraft for Windows starting · data: \(GamePaths.root.path)", category: "App")

if options.screenshotPath == nil && options.join == nil {
    print("")
    print("  DinoCraft for Windows")
    print("")
    print("  Press Enter to play on your own.")
    print("  To join a friend, paste their invite code (like DINO-3M4KA-9QX2B) or IP address, then press Enter.")
    print("  (Your friend hosts on a Mac: Esc > Open to LAN, or Open to Internet > Copy Invite Code.)")
    print("")
    if let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty { options.join = line }
}

var network: WinNetwork?
if let address = options.join {
    var name = options.name
    if name == nil && options.screenshotPath == nil {
        let fallback = cleanName(ProcessInfo.processInfo.environment["USERNAME"] ?? "Explorer")
        print("  Your player name (press Enter to use \(fallback)):")
        let typed = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = typed.isEmpty ? fallback : typed
    }
    let username = cleanName(name ?? "Explorer")
    print("  Connecting to \(address) as \(username)…")
    do {
        let joined = try WinNetwork.join(address: address, username: username)
        network = joined
        print("  Joined \(joined.welcome.worldName)! Opening the game window…")
    } catch {
        print("  Couldn't join: \(error)")
        fail("Couldn't join the game:\n\n\(error)")
    }
}

guard SDL_Init(SDL_INIT_VIDEO) else { fail("Could not start SDL: \(String(cString: SDL_GetError()))") }
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 3)
_ = SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, 1)   // core profile
_ = SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)
_ = SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
_ = SDL_GL_SetAttribute(SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1)

let title = network.map { "DinoCraft · \($0.welcome.worldName)" } ?? "DinoCraft"
guard let window = SDL_CreateWindow(title, 1280, 720,
                                    SDL_WINDOW_OPENGL_FLAG | SDL_WINDOW_RESIZABLE_FLAG | SDL_WINDOW_HIGH_PIXEL_DENSITY_FLAG) else {
    fail("Could not create the game window: \(String(cString: SDL_GetError()))")
}
guard let context = SDL_GL_CreateContext(window) else {
    fail("DinoCraft needs OpenGL 3.3, which your graphics driver doesn't provide. Updating your graphics driver usually fixes this.\n\n\(String(cString: SDL_GetError()))", window: window)
}
_ = SDL_GL_MakeCurrent(window, context)
_ = SDL_GL_SetSwapInterval(options.screenshotPath == nil ? 1 : 0)

do {
    let gl = try GL()
    Log.info("OpenGL \(gl.string(GLC.VERSION)) · \(gl.string(GLC.RENDERER)) · \(gl.string(GLC.VENDOR))", category: "Renderer")
    let game = try WinGame(gl: gl, window: window, options: options, network: network)
    if let reason = game.run() {
        print("  Disconnected: \(reason)")
        _ = SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_INFORMATION_FLAG, "DinoCraft", "You left the game:\n\n\(reason)", window)
    }
} catch {
    fail(String(describing: error), window: window)
}

SDL_GL_DestroyContext(context)
SDL_DestroyWindow(window)
SDL_Quit()
Log.info("DinoCraft closed", category: "App")
Log.shared.flush()
