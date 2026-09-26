import UIKit
import MetalKit
import AVFoundation
import DinoCraftCore
@testable import DinoCraftGame

/// Switches for automated checks (passed with `simctl launch … --args`).
struct LaunchOptions {
    var screenshotPath: String?
    var screenshotAfter: Double = 6
    var exitAfter: Double?
    var autoWorld: String?
    var autoSeed: String = ""
    var autoCreative = false
    var bonusChest = false

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
            case "--bonus-chest": o.bonusChest = true
            default: break
            }
            i += 1
        }
        return o
    }
}

final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    private var engine: GameEngine?
    private let options = LaunchOptions.parse(CommandLine.arguments)

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do { try GamePaths.ensureDirectories() } catch {}
        Log.shared.start(directory: GamePaths.logs)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        Log.info("DinoCraft Mobile \(version) starting on \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion) · data: \(GamePaths.root.path)", category: "App")

        // Play alongside other audio, and follow the silent switch like other games.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)

        let window = UIWindow(frame: UIScreen.main.bounds)
        self.window = window
        guard let device = MTLCreateSystemDefaultDevice() else {
            Log.fatal("No Metal device available", category: "App")
            window.rootViewController = MessageViewController(title: "Metal is unavailable", message: "DinoCraft needs a device with Metal graphics.")
            window.makeKeyAndVisible()
            return true
        }
        Log.info("Metal device: \(device.name)", category: "App")

        let firstRun = !FileManager.default.fileExists(atPath: GamePaths.settingsFile.path)
        let settings = SettingsStore()
        if firstRun {
            // Phone-friendly defaults: a shorter view distance keeps the frame rate up and the phone cool.
            settings.update { s in
                s.renderDistance = 6
                s.graphicsQuality = .balanced
                s.showGuide = true
            }
        }
        PlayerLook.settle(settings)

        let view = GameView(frame: window.bounds, device: device)
        let controller = GameViewController(gameView: view)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        do {
            let engine = try GameEngine(view: view, device: device, settings: settings, options: options)
            self.engine = engine
            view.engine = engine
            engine.start()
        } catch {
            Log.fatal("Engine failed to start: \(error)", category: "App")
            Log.shared.flush()
            window.rootViewController = MessageViewController(title: "DinoCraft failed to start", message: String(describing: error))
        }
        return true
    }

    func applicationWillResignActive(_ application: UIApplication) { engine?.applicationLostFocus() }
    func applicationDidEnterBackground(_ application: UIApplication) {
        engine?.applicationLostFocus()
        Log.shared.flush()
    }
    func applicationWillTerminate(_ application: UIApplication) {
        engine?.shutdown()
        Log.shared.flush()
    }
}

/// Full screen, landscape, no status bar, and edge swipes go to the game first.
final class GameViewController: UIViewController {
    let gameView: GameView

    init(gameView: GameView) {
        self.gameView = gameView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func loadView() { view = gameView }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
}

/// The Metal view the game draws into. Touches go to the on-screen controls, and while a text box
/// has focus it brings up the keyboard and passes the typing to the game.
final class GameView: MTKView, UIKeyInput {
    weak var engine: GameEngine?
    var input: Input?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        isMultipleTouchEnabled = true
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func point(_ touch: UITouch) -> SIMD2<Float> {
        let p = touch.location(in: self)
        return SIMD2(Float(p.x), Float(p.y))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let input else { return }
        for t in touches { engine.touch.began(ObjectIdentifier(t), at: point(t), input: input, engine: engine) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let input else { return }
        for t in touches { engine.touch.moved(ObjectIdentifier(t), to: point(t), input: input) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let input else { return }
        for t in touches { engine.touch.ended(ObjectIdentifier(t), at: point(t), input: input, engine: engine) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchesEnded(touches, with: event)
    }

    // MARK: Keyboard

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var returnKeyType: UIReturnKeyType = .done

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { true }

    func insertText(_ text: String) {
        if text == "\n" { input?.tapKey(KeyCode.returnKey) } else { input?.type(text) }
    }

    func deleteBackward() { input?.tapKey(KeyCode.delete) }

    func setKeyboard(visible: Bool) {
        if visible && !isFirstResponder { becomeFirstResponder() } else if !visible && isFirstResponder { resignFirstResponder() }
    }
}

/// A plain message for when the game can't start at all.
final class MessageViewController: UIViewController {
    private let titleText: String
    private let message: String

    init(title: String, message: String) {
        titleText = title
        self.message = message
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.12, green: 0.07, blue: 0.04, alpha: 1)
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.textColor = .white
        label.text = "\(titleText)\n\n\(message)"
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.8),
        ])
    }
}
