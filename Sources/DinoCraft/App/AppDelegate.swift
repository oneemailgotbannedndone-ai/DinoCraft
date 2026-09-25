import AppKit
import Metal
import DinoCraftCore
@testable import DinoCraftGame

/// Global descriptor used by the signal handler (must be async-signal-safe).
nonisolated(unsafe) var crashLogFD: Int32 = -1

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: GameWindow?
    private var engine: GameEngine?
    let launchOptions = LaunchOptions.parse(CommandLine.arguments)

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try GamePaths.ensureDirectories()
        } catch {
            FatalError.present(title: "DinoCraft can't create its data folder",
                               message: "\(GamePaths.root.path)\n\n\(error.localizedDescription)")
            return
        }
        Log.shared.start(directory: GamePaths.logs)
        crashLogFD = Log.shared.fileDescriptor
        CrashHandler.install()
        logSystemInfo()

        buildMenu()

        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.fatal("No Metal device available", category: "App")
            FatalError.present(title: "Metal is unavailable",
                               message: "DinoCraft requires a Mac with Metal support (Apple Silicon recommended).")
            return
        }
        Log.info("Metal device: \(device.name) · unified memory: \(device.hasUnifiedMemory) · recommended working set: \(device.recommendedMaxWorkingSetSize / 1_048_576) MB", category: "App")

        let settings = SettingsStore()
        PlayerLook.settle(settings)
        let s = settings.settings
        let window = GameWindow(size: NSSize(width: s.windowWidth, height: s.windowHeight))
        window.delegate = self
        self.window = window

        do {
            let engine = try GameEngine(window: window, device: device, settings: settings, options: launchOptions)
            self.engine = engine
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if s.fullscreen && !launchOptions.windowed { window.toggleFullScreen(nil) }
            engine.start()
        } catch {
            Log.fatal("Engine failed to start: \(error)", category: "App")
            FatalError.present(title: "DinoCraft failed to start", message: String(describing: error))
        }
    }

    private func logSystemInfo() {
        let info = ProcessInfo.processInfo
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brand = [CChar](repeating: 0, count: max(1, size))
        sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
        var arch = "unknown"
        #if arch(arm64)
        arch = "arm64"
        #elseif arch(x86_64)
        arch = "x86_64"
        #endif
        let translated = Self.isTranslated ? " (Rosetta!)" : ""
        Log.info("DinoCraft \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev") starting", category: "App")
        Log.info("CPU: \(String(cString: brand)) · \(info.activeProcessorCount) cores · \(info.physicalMemory / 1_073_741_824) GB · arch \(arch)\(translated)", category: "App")
        Log.info("macOS \(info.operatingSystemVersionString) · data: \(GamePaths.root.path)", category: "App")
    }

    static var isTranslated: Bool {
        var ret: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("sysctl.proc_translated", &ret, &size, nil, 0) == 0 && ret == 1
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About DinoCraft", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Open Logs Folder", action: #selector(openLogs), keyEquivalent: "")
        appMenu.addItem(withTitle: "Open Worlds Folder", action: #selector(openWorlds), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide DinoCraft", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit DinoCraft", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let fs = NSMenuItem(title: "Toggle Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(fs)
        viewItem.submenu = viewMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = main
    }

    @objc private func showAbout() { engine?.showCredits() }
    @objc private func openLogs() { NSWorkspace.shared.open(GamePaths.logs) }
    @objc private func openWorlds() { NSWorkspace.shared.open(GamePaths.worlds) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        engine?.shutdown()
        Log.info("DinoCraft exited cleanly", category: "App")
        Log.shared.flush()
        return .terminateNow
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationDidResignActive(_ notification: Notification) { engine?.applicationLostFocus() }
    func applicationDidBecomeActive(_ notification: Notification) { engine?.applicationGainedFocus() }

    func windowDidEnterFullScreen(_ notification: Notification) { engine?.fullscreenChanged(true) }
    func windowDidExitFullScreen(_ notification: Notification) { engine?.fullscreenChanged(false) }
    func windowDidResize(_ notification: Notification) { engine?.windowResized() }
    func windowDidChangeBackingProperties(_ notification: Notification) { engine?.windowResized() }
}

/// Command-line switches used for development and automated testing.
struct LaunchOptions {
    var screenshotPath: String?
    var screenshotAfter: Double = 6
    var exitAfter: Double?
    var autoWorld: String?          // create/load this world immediately
    var autoSeed: String = ""
    var autoCreative = false
    var windowed = false
    var benchmark = false
    var script: String?             // path to an automation script
    var joinAddress: String?        // join a multiplayer host on launch
    var username: String?
    var bonusChest = false
    /// Started from DinoCraft Launcher: go straight to the main menu.
    var skipLauncher = false
    /// This copy is DinoCraft Launcher: Play opens the game app.
    var launcherOnly = Bundle.main.bundleURL.lastPathComponent.contains("Launcher")

    static func parse(_ args: [String]) -> LaunchOptions {
        var o = LaunchOptions()
        var i = 1
        func next() -> String? { i += 1; return i < args.count ? args[i] : nil }
        while i < args.count {
            switch args[i] {
            case "--screenshot": o.screenshotPath = next()
            case "--screenshot-after": o.screenshotAfter = Double(next() ?? "") ?? 6
            case "--exit-after": o.exitAfter = Double(next() ?? "")
            case "--world": o.autoWorld = next()
            case "--seed": o.autoSeed = next() ?? ""
            case "--creative": o.autoCreative = true
            case "--windowed": o.windowed = true
            case "--benchmark": o.benchmark = true
            case "--script": o.script = next()
            case "--join": o.joinAddress = next()
            case "--username": o.username = next()
            case "--bonus-chest": o.bonusChest = true
            case "--skip-launcher": o.skipLauncher = true
            case "--launcher": o.launcherOnly = true
            default: break
            }
            i += 1
        }
        return o
    }
}

enum FatalError {
    static func present(title: String, message: String) {
        Log.shared.flush()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = title
        alert.informativeText = message + "\n\nDetails were written to the log folder."
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Open Logs Folder")
        if alert.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.open(GamePaths.logs)
        }
        NSApp.terminate(nil)
    }
}

enum CrashHandler {
    static func install() {
        NSSetUncaughtExceptionHandler { exception in
            Log.fatal("Uncaught exception \(exception.name.rawValue): \(exception.reason ?? "no reason")\n\(exception.callStackSymbols.joined(separator: "\n"))", category: "Crash")
            Log.shared.flush()
        }
        for sig in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGFPE, SIGTRAP] {
            signal(sig) { s in
                let message = "\n*** DinoCraft crashed: fatal signal \(s) — backtrace follows ***\n"
                message.withCString { ptr in _ = write(crashLogFD >= 0 ? crashLogFD : 2, ptr, strlen(ptr)) }
                message.withCString { ptr in _ = write(2, ptr, strlen(ptr)) }
                var frames = [UnsafeMutableRawPointer?](repeating: nil, count: 64)
                let count = backtrace(&frames, 64)
                if crashLogFD >= 0 { backtrace_symbols_fd(&frames, count, crashLogFD) }
                backtrace_symbols_fd(&frames, count, 2)
                signal(s, SIG_DFL)
                raise(s)
            }
        }
    }
}
