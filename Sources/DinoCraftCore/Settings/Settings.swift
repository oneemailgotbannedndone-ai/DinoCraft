import Foundation

/// A physical input a game action can be bound to.
public struct InputBinding: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case key, mouse }
    public var kind: Kind
    /// macOS virtual key code for `.key`; button number for `.mouse` (0 left, 1 right, 2 middle, 3+ extra).
    public var code: Int

    public static func key(_ code: Int) -> InputBinding { InputBinding(kind: .key, code: code) }
    public static func mouse(_ button: Int) -> InputBinding { InputBinding(kind: .mouse, code: button) }

    public var displayName: String {
        switch kind {
        case .mouse:
            switch code {
            case 0: return "Left Click"
            case 1: return "Right Click"
            case 2: return "Middle Click"
            default: return "Mouse \(code + 1)"
            }
        case .key:
            return KeyNames.name(for: code)
        }
    }
}

public enum GameAction: String, Codable, CaseIterable, Sendable {
    case forward, backward, left, right, jump, sprint, crouch, inventory, attack, use, pause
    case drop, pickBlock, toggleDebug, screenshot, toggleHUD, advancements

    public var displayName: String {
        switch self {
        case .forward: return "Forward"
        case .backward: return "Backward"
        case .left: return "Strafe Left"
        case .right: return "Strafe Right"
        case .jump: return "Jump / Swim Up"
        case .sprint: return "Sprint"
        case .crouch: return "Crouch"
        case .inventory: return "Inventory"
        case .attack: return "Attack / Break"
        case .use: return "Use / Place"
        case .pause: return "Pause"
        case .drop: return "Drop Item"
        case .pickBlock: return "Pick Block"
        case .toggleDebug: return "Debug Overlay"
        case .screenshot: return "Screenshot"
        case .toggleHUD: return "Hide HUD"
        case .advancements: return "Advancements"
        }
    }

    public static var defaults: [GameAction: InputBinding] {
        [
            .forward: .key(13),       // W
            .backward: .key(1),       // S
            .left: .key(0),           // A
            .right: .key(2),          // D
            .jump: .key(49),          // Space
            .sprint: .key(59),        // Left Control
            .crouch: .key(56),        // Left Shift
            .inventory: .key(14),     // E
            .attack: .mouse(0),
            .use: .mouse(1),
            .pause: .key(53),         // Escape
            .drop: .key(12),          // Q
            .pickBlock: .mouse(2),
            .toggleDebug: .key(122),  // F1? (F3 on many keyboards is Mission Control) → F1
            .screenshot: .key(120),   // F2
            .toggleHUD: .key(99),     // F3
            .advancements: .key(37),  // L
        ]
    }
}

public enum GraphicsQuality: String, Codable, CaseIterable, Sendable {
    case fast, balanced, fancy
    public var displayName: String { rawValue.capitalized }
}

public struct GameSettings: Codable, Equatable, Sendable {
    // Graphics
    public var windowWidth = 1600
    public var windowHeight = 900
    public var fullscreen = false
    public var vsync = true
    public var maxFPS = 120          // used when VSync is off (0 = unlimited)
    public var renderDistance = 12   // chunks
    public var graphicsQuality: GraphicsQuality = .fancy
    public var fov: Double = 75
    public var brightness: Double = 0.5
    public var viewBobbing = true
    public var renderScale: Double = 1.0
    public var guiScale: Double = 1.0
    public var clouds = true
    public var showFPS = false

    // Profile & multiplayer
    public var username = ""
    public var lastServerAddress = ""
    public var texturePack = "dino"
    public var shaderPack = "off"
    public var shaderStrength: Double = 1.0

    // Audio (0...1)
    public var masterVolume: Double = 0.8
    public var musicVolume: Double = 0.5
    public var soundVolume: Double = 0.9
    public var ambientVolume: Double = 0.7

    // Controls
    public var mouseSensitivity: Double = 0.5
    public var invertY = false
    public var bindings: [String: InputBinding] = Dictionary(uniqueKeysWithValues:
        GameAction.defaults.map { ($0.key.rawValue, $0.value) })

    // Integrations
    public var discordRichPresence = true
    public var showWorldNameInDiscord = true

    public init() {}

    public func binding(for action: GameAction) -> InputBinding {
        bindings[action.rawValue] ?? GameAction.defaults[action]!
    }

    public mutating func setBinding(_ binding: InputBinding, for action: GameAction) {
        bindings[action.rawValue] = binding
    }

    /// Tolerant decoding: unknown or missing keys fall back to defaults so an
    /// older or hand-edited settings file never prevents the game from starting.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v<T: Decodable>(_ key: CodingKeys, _ current: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? current }
        windowWidth = v(.windowWidth, windowWidth)
        windowHeight = v(.windowHeight, windowHeight)
        fullscreen = v(.fullscreen, fullscreen)
        vsync = v(.vsync, vsync)
        maxFPS = v(.maxFPS, maxFPS)
        renderDistance = v(.renderDistance, renderDistance)
        graphicsQuality = v(.graphicsQuality, graphicsQuality)
        fov = v(.fov, fov)
        brightness = v(.brightness, brightness)
        viewBobbing = v(.viewBobbing, viewBobbing)
        renderScale = v(.renderScale, renderScale)
        guiScale = v(.guiScale, guiScale)
        clouds = v(.clouds, clouds)
        showFPS = v(.showFPS, showFPS)
        username = v(.username, username)
        lastServerAddress = v(.lastServerAddress, lastServerAddress)
        texturePack = v(.texturePack, texturePack)
        shaderPack = v(.shaderPack, shaderPack)
        shaderStrength = v(.shaderStrength, shaderStrength)
        masterVolume = v(.masterVolume, masterVolume)
        musicVolume = v(.musicVolume, musicVolume)
        soundVolume = v(.soundVolume, soundVolume)
        ambientVolume = v(.ambientVolume, ambientVolume)
        mouseSensitivity = v(.mouseSensitivity, mouseSensitivity)
        invertY = v(.invertY, invertY)
        let loaded: [String: InputBinding] = v(.bindings, [:])
        for (k, b) in loaded where GameAction(rawValue: k) != nil { bindings[k] = b }
        discordRichPresence = v(.discordRichPresence, discordRichPresence)
        showWorldNameInDiscord = v(.showWorldNameInDiscord, showWorldNameInDiscord)
        sanitize()
    }

    public mutating func sanitize() {
        windowWidth = max(960, min(7680, windowWidth))
        windowHeight = max(540, min(4320, windowHeight))
        renderDistance = max(2, min(32, renderDistance))
        maxFPS = max(0, min(500, maxFPS))
        fov = max(50, min(110, fov))
        brightness = max(0, min(1, brightness))
        renderScale = max(0.5, min(1, renderScale))
        guiScale = max(0.75, min(1.5, guiScale))
        shaderStrength = max(0, min(1, shaderStrength))
        for key in [\GameSettings.masterVolume, \.musicVolume, \.soundVolume, \.ambientVolume, \.mouseSensitivity] {
            self[keyPath: key] = max(0, min(1, self[keyPath: key]))
        }
    }
}

/// Loads and persists `settings.json` atomically.
public final class SettingsStore {
    public private(set) var settings: GameSettings
    private let url: URL

    public init(url: URL = GamePaths.settingsFile) {
        self.url = url
        if let data = try? Data(contentsOf: url) {
            do {
                settings = try JSONDecoder().decode(GameSettings.self, from: data)
                Log.info("Loaded settings from \(url.path)", category: "Settings")
            } catch {
                Log.error("Settings file is unreadable (\(error)); using defaults and backing up the old file", category: "Settings")
                try? FileManager.default.moveItem(at: url, to: url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))"))
                settings = GameSettings()
            }
        } else {
            settings = GameSettings()
            Log.info("No settings file yet; using defaults", category: "Settings")
        }
    }

    public func update(_ change: (inout GameSettings) -> Void) {
        var s = settings
        change(&s)
        s.sanitize()
        guard s != settings else { return }
        settings = s
        save()
    }

    public func save() {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try AtomicFile.write(enc.encode(settings), to: url)
        } catch {
            Log.error("Failed to save settings: \(error)", category: "Settings")
        }
    }
}

public enum AtomicFile {
    /// Writes to a temporary sibling and renames over the destination so a crash
    /// mid-write can never leave a truncated file.
    public static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}

/// Human-readable names for macOS virtual key codes (ANSI layout).
public enum KeyNames {
    private static let table: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",
        54: "Right Cmd", 55: "Cmd", 56: "Left Shift", 57: "Caps Lock", 58: "Left Option", 59: "Left Control",
        60: "Right Shift", 61: "Right Option", 62: "Right Control", 63: "Fn",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
        118: "F4", 120: "F2", 122: "F1", 123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3", 86: "Keypad 4", 87: "Keypad 5",
        88: "Keypad 6", 89: "Keypad 7", 91: "Keypad 8", 92: "Keypad 9",
    ]
    public static func name(for code: Int) -> String { table[code] ?? "Key \(code)" }
}
