import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

/// Mouse and keyboard input for one frame of a menu.
struct MenuInput {
    var mouse = SIMD2<Float>(0, 0)
    var clicked = false
    var typed = ""
    var backspace = false
    var enter = false
    var escape = false
    var tab = false
    var wheel: Float = 0
    var quit = false
    /// Buttons held this frame (for painting in the skin creator).
    var leftDown = false
    var rightDown = false
}

extension UIBuilder {
    /// Draws a button and returns true when it was clicked this frame.
    mutating func button(_ label: String, x: Float, y: Float, w: Float, h: Float, scale s: Float, input: MenuInput,
                         enabled: Bool = true, primary: Bool = false) -> Bool {
        let hovered = enabled && input.mouse.x >= x && input.mouse.x < x + w && input.mouse.y >= y && input.mouse.y < y + h
        // A wooden plank (golden honey-wood for the main action) with a bevel and a dark outline.
        var base: SIMD4<Float> = !enabled ? SIMD4(0.07, 0.04, 0.02, 0.9) : (primary ? SIMD4(0.6, 0.3, 0.05, 1) : SIMD4(0.2, 0.1, 0.04, 1))
        if hovered { base = SIMD4(min(1, base.x * 1.45 + 0.02), min(1, base.y * 1.45 + 0.01), min(1, base.z * 1.4), 1) }
        let px = max(1, s.rounded())
        rect(x, y, w, h, SIMD4(0.02, 0.01, 0.004, 1))
        rect(x + px, y + px, w - 2 * px, h - 2 * px, base)
        rect(x + px, y + px, w - 2 * px, 2 * px, SIMD4(min(1, base.x * 1.7 + 0.03), min(1, base.y * 1.7 + 0.02), min(1, base.z * 1.6 + 0.01), 1))
        rect(x + px, y + h - 3 * px, w - 2 * px, 2 * px, SIMD4(base.x * 0.45, base.y * 0.45, base.z * 0.45, 1))
        let small = max(1, (2 * s).rounded())
        centeredText(label, centerX: x + w / 2, y: y + h / 2 - 3.5 * small, scale: small,
                     color: enabled ? SIMD4(1, 0.96, 0.86, 1) : SIMD4(0.45, 0.38, 0.3, 1))
        return hovered && input.clicked
    }

    /// Draws a text field; returns true if it was clicked (so the caller can focus it).
    mutating func field(_ value: String, placeholder: String, x: Float, y: Float, w: Float, h: Float, scale s: Float,
                        focused: Bool, input: MenuInput, time: Double) -> Bool {
        let hovered = input.mouse.x >= x && input.mouse.x < x + w && input.mouse.y >= y && input.mouse.y < y + h
        rect(x, y, w, h, focused ? SIMD4(0.03, 0.015, 0.006, 1) : SIMD4(0.06, 0.03, 0.012, 0.95))
        rect(x, y, w, max(1, s.rounded()) * 2, SIMD4(0.01, 0.005, 0.002, 1))
        rect(x, y + h - 2 * s, w, 2 * s, focused ? SIMD4(0.95, 0.6, 0.15, 1) : SIMD4(0.3, 0.17, 0.07, 1))
        let small = max(1, (2 * s).rounded())
        let textY = y + h / 2 - 3.5 * small
        if value.isEmpty && !focused {
            text(placeholder, x: x + 10 * s, y: textY, scale: small, color: SIMD4(0.594, 0.529, 0.432, 1), shadow: false)
        } else {
            let cursor = focused && Int(time * 2) % 2 == 0 ? "_" : ""
            text(value + cursor, x: x + 10 * s, y: textY, scale: small, color: SIMD4(1, 1, 1, 1), shadow: false)
        }
        return hovered && input.clicked
    }
}

/// Title screen, world list, world creation, joining and settings.
final class WinMenus {
    enum Choice {
        case play(WorldMetadata, isNew: Bool, hostName: String?)
        case join(WinNetwork)
        case quit
        /// DinoCraft Launcher: start DinoCraft.exe and close the launcher.
        /// Launcher only: start DinoCraft.exe, joining a friend's game if an address is given.
        case launchGame(join: String?)
    }

    private enum Page { case launcher, cosmetics, skin, title, worlds, create, multiplayer, settings, connecting, reviews, friends, leaderboard }

    private let window: OpaquePointer
    private let renderer: WinRenderer
    private let store: SettingsStore
    private let audio: WinAudio?
    private let options: Options
    private let storage = WorldStorage()
    private var page = Page.title
    private var worlds: [WorldMetadata] = []
    private var message: String?
    private var focus = ""
    private var newName = "New World"
    private var newSeed = ""
    /// Checks the public releases page for a newer DinoCraft.
    private let updater = GameUpdater(assetName: "DinoCraft-Windows.zip")
    /// The launcher shows first, once per start.
    private var launched = false
    private var settingsReturn = Page.title
    private var updateError: String?
    /// Set when the update is unpacked and DinoCraft should close so the updater can finish.
    private var quitForUpdate = false
    /// The cosmetics preview (camera-relative model triangles), rebuilt every frame.
    private var previewModels: [Float] = []
    // Skin creator
    private var skinDraft: PlayerLook?
    /// The launcher's news panel shows the guide to beating DinoCraft instead.
    private var showingGuide = false
    /// Stars picked on the Reviews page before writing a review.
    private var reviewStars = 5
    private var reviewWords = ""
    private var friendMessage: String?
    private var leaderCategory = Leaderboard.Category.playtime
    private var leaderScroll = 0
    private var launchJoin: String?
    private var friendScroll = 0
    /// The side being painted (a `SkinRegion` id); "hf" is the face.
    private var skinRegionID = "hf"
    private var skinColor: UInt8 = 1
    private var skinMirror = true
    private var skinFill = false
    private var skinFacePreset = 0
    private var skinChestPreset = 0
    private var skinMessage: String?
    /// 0 Survival, 1 Hardcore, 2 Creative (the same order as on the Mac).
    private var newMode = 0
    private var newDifficulty = 2
    private var newBonusChest = false
    private var newCommands = true
    private var address = ""
    private var playerName = ""
    private var deleteArmed: String?
    private var scroll = 0
    private let joinLock = NSLock()
    private var joinResult: Result<WinNetwork, Error>?
    private var joinToken = UUID()
    private let startTime = Date.timeIntervalSinceReferenceDate

    init(window: OpaquePointer, renderer: WinRenderer, store: SettingsStore, audio: WinAudio?, options: Options) {
        self.window = window
        self.renderer = renderer
        self.store = store
        self.audio = audio
        self.options = options
    }

    private var defaultName: String {
        let saved = store.settings.username
        return cleanName(saved.isEmpty ? (ProcessInfo.processInfo.environment["USERNAME"] ?? "Explorer") : saved)
    }

    func run(message: String?) -> Choice {
        self.message = message
        page = .title
        if !launched {
            launched = true
            page = options.skipLauncher ? .title : .launcher
            if store.settings.checkForUpdates && options.screenshotPath == nil { updater.check() }
            if options.screenshotPath == nil && !options.skipLauncher {
                GameLinks.reviews.load()
                FriendList.shared.refreshStatuses()
                PlayerStats.shared.submitNow()
            }
        }
        focus = ""
        address = store.settings.lastServerAddress
        playerName = defaultName
        refreshWorlds()
        if options.demoScreen == "worlds" { page = .worlds }
        if options.demoScreen == "create" { page = .create; focus = "name" }
        if options.demoScreen == "cosmetics" { page = .cosmetics }
        if options.demoScreen == "reviews" { GameLinks.reviews.load(); page = .reviews }
        if options.demoScreen == "leaderboard" { GameLinks.leaderboard.load(); page = .leaderboard }
        if options.demoScreen == "friends" {
            // Automated check: a friend, a recent player and a friend code to paste.
            let list = FriendList.shared
            if list.friends.isEmpty {
                list.add(code: FriendCode.encode(name: "Tuneful", id: "1d2c3b4a59687706", address: "127.0.0.1:1"), myID: store.settings.playerID)
                list.met(id: "a1b2c3d4e5f60718", name: "Rexy", look: PlayerLook.oneOfOne(id: "a1b2c3d4e5f60718").encoded, address: nil,
                         myID: store.settings.playerID)
            }
            list.refreshStatuses()
            page = .friends
        }
        if options.demoScreen == "skin" {
            page = .skin
            var demo = PlayerLook(encoded: store.settings.cosmetics) ?? PlayerLook()
            demo.face = PlayerLook.presetPixels(PlayerLook.facePresets[0].pixels, count: 64)
            demo.chest = PlayerLook.presetPixels(PlayerLook.chestPresets[3].pixels, count: 80)
            skinDraft = demo
        }
        if options.demoScreen == "skin-arm" {
            // Automated check: a painted left arm (a stripe down its outer side) and a star on the back
            page = .skin
            var demo = PlayerLook()
            demo.hat = .wizard
            demo.back = .dragonwings
            if let arm = SkinRegion.byID["lal"] {
                demo.setPixels((0..<arm.count).map { ($0 % 4 == 1 || $0 % 4 == 2) ? 5 : 0 }, for: arm)
            }
            if let back = SkinRegion.byID["bb"] {
                demo.setPixels(PlayerLook.presetPixels(PlayerLook.chestPresets[2].pixels, count: back.count), for: back)
            }
            skinDraft = demo
            skinRegionID = "lal"
        }
        _ = SDL_SetWindowRelativeMouseMode(window, false)
        _ = SDL_StartTextInput(window)
        defer { _ = SDL_StopTextInput(window) }
        audio?.stopLoops()
        audio?.playMusic("menu_theme")

        var frames = 0
        var last = Date.timeIntervalSinceReferenceDate
        while true {
            let now = Date.timeIntervalSinceReferenceDate
            audio?.update(dt: min(0.1, now - last))
            last = now
            let input = pollInput()
            if input.quit { return .quit }
            var w: Int32 = 0, h: Int32 = 0
            _ = SDL_GetWindowSizeInPixels(window, &w, &h)
            var ui = UIBuilder()
            previewModels = []
            if let choice = build(&ui, input: input, width: Float(w), height: Float(h), now: now - startTime) {
                if case .quit = choice {} else { audio?.stopMusic() }
                return choice
            }
            renderer.renderMenu(width: w, height: h, time: now - startTime, ui: ui.vertices, models: previewModels)
            frames += 1
            if let path = options.screenshotPath, frames >= 40 {
                let image = renderer.capture(width: w, height: h)
                try? PNG.encode(width: image.width, height: image.height, rgba: image.rgba).write(to: URL(fileURLWithPath: path))
                Log.info("Saved menu screenshot \(path)", category: "Game")
                return .quit
            }
            SDL_GL_SwapWindow(window)
        }
    }

    private func refreshWorlds() {
        worlds = storage.listWorlds().sorted { $0.lastPlayed > $1.lastPlayed }
    }

    private func pixelScale() -> Float {
        var lw: Int32 = 0, lh: Int32 = 0, pw: Int32 = 0, ph: Int32 = 0
        _ = SDL_GetWindowSize(window, &lw, &lh)
        _ = SDL_GetWindowSizeInPixels(window, &pw, &ph)
        return lw > 0 ? Float(pw) / Float(lw) : 1
    }

    private var lastMouse = SIMD2<Float>(0, 0)

    private func pollInput() -> MenuInput {
        var input = MenuInput()
        input.mouse = lastMouse
        var event = SDL_Event()
        while SDL_PollEvent(&event) {
            let type = UInt32(event.type)
            if type == UInt32(SDL_EVENT_QUIT.rawValue) {
                input.quit = true
            } else if type == UInt32(SDL_EVENT_MOUSE_MOTION.rawValue) {
                lastMouse = SIMD2<Float>(event.motion.x, event.motion.y) * pixelScale()
                input.mouse = lastMouse
            } else if type == UInt32(SDL_EVENT_MOUSE_BUTTON_DOWN.rawValue), event.button.button == 1 {
                lastMouse = SIMD2<Float>(event.button.x, event.button.y) * pixelScale()
                input.mouse = lastMouse
                input.clicked = true
            } else if type == UInt32(SDL_EVENT_MOUSE_WHEEL.rawValue) {
                input.wheel += event.wheel.y
            } else if type == UInt32(SDL_EVENT_TEXT_INPUT.rawValue), let raw = event.text.text {
                input.typed += String(cString: raw)
            } else if type == UInt32(SDL_EVENT_KEY_DOWN.rawValue) {
                let code = Int(event.key.scancode.rawValue)
                if code == Int(SDL_SCANCODE_BACKSPACE.rawValue) { input.backspace = true }
                if code == Int(SDL_SCANCODE_RETURN.rawValue) || code == Int(SDL_SCANCODE_KP_ENTER.rawValue) { input.enter = true }
                if code == Int(SDL_SCANCODE_ESCAPE.rawValue) { input.escape = true }
                if code == Int(SDL_SCANCODE_TAB.rawValue) { input.tab = true }
            }
        }
        var mx: Float = 0, my: Float = 0
        let buttons = SDL_GetMouseState(&mx, &my)
        input.leftDown = buttons & 1 != 0
        input.rightDown = buttons & 4 != 0
        return input
    }

    /// Applies typing to the focused field.
    private func edit(_ text: inout String, id: String, input: MenuInput, limit: Int) {
        guard focus == id else { return }
        if input.backspace, !text.isEmpty { text.removeLast() }
        if !input.typed.isEmpty { text = String((text + input.typed).prefix(limit)) }
    }

    private func click() { audio?.play("ui_click", volume: 0.5) }

    // MARK: Pages

    private func build(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, now: Double) -> Choice? {
        let s = max(1, min(W / 1280, H / 720))
        let small = max(1, (2 * s).rounded())
        let bw = 360 * s, bh = 46 * s, gap = 12 * s
        let cx = W / 2
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.35))

        func header(_ title: String) {
            let scale = max(1, (4 * s).rounded())
            ui.centeredText(title, centerX: cx, y: H * 0.1, scale: scale, color: SIMD4(1, 0.85, 0.55, 1))
        }
        func label(_ text: String, _ y: Float) {
            ui.text(text, x: cx - bw / 2, y: y, scale: small, color: SIMD4(0.9, 0.85, 1, 0.9))
        }

        switch page {
        case .title:
            let big = max(1, (9 * s).rounded())
            let pack = renderer.texturePack
            let top = pack.titleTop, bottom = pack.titleBottom
            func color(_ hex: UInt32) -> SIMD4<Float> {
                SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
            }
            // The title is the top colour over the bottom colour, one pixel lower, like a two-tone logo.
            ui.centeredText(pack.title, centerX: cx + big * 0.5, y: H * 0.16 + big, scale: big, color: color(bottom))
            ui.centeredText(pack.title, centerX: cx, y: H * 0.16, scale: big, color: color(top))
            ui.centeredText("for Windows", centerX: cx, y: H * 0.16 + 10 * big, scale: small, color: SIMD4(0.9, 0.85, 1, 0.8))
            if let message {
                ui.centeredText(String(message.prefix(110)), centerX: cx, y: H * 0.16 + 10 * big + 16 * small, scale: small, color: SIMD4(1, 0.6, 0.5, 1))
            }
            var y = H * 0.46
            if ui.button("Singleplayer", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, input: input, primary: true) {
                click(); message = nil; refreshWorlds(); scroll = 0; page = .worlds
            }
            y += bh + gap
            if ui.button("Multiplayer", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, input: input) {
                click(); message = nil; focus = "address"; page = .multiplayer
            }
            y += bh + gap
            if ui.button("Settings", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, input: input) {
                click(); message = nil; focus = ""; settingsReturn = .title; page = .settings
            }
            y += bh + gap
            if ui.button("Back to Launcher", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, input: input) || input.escape {
                click(); message = nil; page = .launcher
            }

        case .launcher:
            if let choice = buildLauncher(&ui, input: input, width: W, height: H, scale: s, now: now) { return choice }

        case .cosmetics:
            buildCosmetics(&ui, input: input, width: W, height: H, scale: s, now: now)

        case .reviews:
            buildReviews(&ui, input: input, width: W, height: H, scale: s)

        case .leaderboard:
            buildLeaderboard(&ui, input: input, width: W, height: H, scale: s)

        case .friends:
            buildFriends(&ui, input: input, width: W, height: H, scale: s, now: now)
            if let target = launchJoin {
                launchJoin = nil
                return .launchGame(join: target)
            }

        case .skin:
            buildSkinCreator(&ui, input: input, width: W, height: H, scale: s, now: now)
            if options.launcherOnly && page == .title { return .launchGame(join: nil) }

        case .worlds:
            header("Your Worlds")
            let rowH = 58 * s, listW = min(W - 80 * s, 760 * s), listX = cx - listW / 2
            var y = H * 0.24
            if worlds.isEmpty {
                ui.centeredText("No worlds yet - create one!", centerX: cx, y: y + 20 * s, scale: small, color: SIMD4(0.9, 0.85, 1, 0.8))
            }
            let visible = max(1, Int((H * 0.5) / (rowH + 8 * s)))
            if input.wheel != 0 { scroll = max(0, min(max(0, worlds.count - visible), scroll - Int(input.wheel))) }
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            for world in worlds.dropFirst(scroll).prefix(visible) {
                ui.rect(listX, y, listW, rowH, SIMD4(0.151, 0.084, 0.037, 0.9))
                let bwSmall = 92 * s, bhSmall = 36 * s, by = y + (rowH - bhSmall) / 2
                let textChars = max(8, Int((listW - 3 * bwSmall - 52 * s) / (6 * small)))
                func fit(_ text: String) -> String { text.count > textChars ? String(text.prefix(textChars - 1)) + "\u{2026}" : text }
                ui.text(fit(world.name), x: listX + 14 * s, y: y + 10 * s, scale: small, color: SIMD4(1, 1, 1, 1))
                let mode = world.isHardcore ? ((world.hardcoreDead ?? false) ? "Hardcore - Game Over" : "Hardcore") : world.gameMode.displayName
                let detail = "\(mode) - \(world.difficulty.displayName) - \(formatter.string(from: world.lastPlayed))"
                ui.text(fit(detail), x: listX + 14 * s, y: y + 10 * s + 11 * small, scale: small, color: SIMD4(0.756, 0.674, 0.55, 1))
                var bx = listX + listW - 3 * bwSmall - 3 * 8 * s
                if ui.button("Play", x: bx, y: by, w: bwSmall, h: bhSmall, scale: s, input: input, primary: true) {
                    click()
                    return .play(world, isNew: false, hostName: nil)
                }
                bx += bwSmall + 8 * s
                if ui.button("Host", x: bx, y: by, w: bwSmall, h: bhSmall, scale: s, input: input) {
                    click()
                    store.update { $0.username = self.playerName }
                    return .play(world, isNew: false, hostName: defaultName)
                }
                bx += bwSmall + 8 * s
                let armed = deleteArmed == world.id
                if ui.button(armed ? "Sure?" : "Delete", x: bx, y: by, w: bwSmall, h: bhSmall, scale: s, input: input) {
                    click()
                    if armed {
                        try? storage.deleteWorld(id: world.id)
                        deleteArmed = nil
                        refreshWorlds()
                    } else {
                        deleteArmed = world.id
                    }
                }
                y += rowH + 8 * s
            }
            let footerY = H * 0.8
            if ui.button("Create New World", x: cx - bw - gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input, primary: true) {
                click(); newName = "New World"; newSeed = ""; newMode = 0; newDifficulty = 2; newBonusChest = false; newCommands = true
                focus = "name"; page = .create
            }
            if ui.button("Back", x: cx + gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input) || input.escape {
                click(); page = .title
            }

        case .create:
            header("Create New World")
            if input.tab { focus = focus == "name" ? "seed" : "name" }
            edit(&newName, id: "name", input: input, limit: 32)
            edit(&newSeed, id: "seed", input: input, limit: 40)
            var y = H * 0.2
            let fw = min(W - 60 * s, 620 * s), fx = cx - fw / 2
            func caption(_ text: String) {
                ui.text(text, x: fx, y: y, scale: small, color: SIMD4(0.9, 0.85, 1, 0.9))
                y += 12 * small
            }
            /// A row of buttons where one is chosen.
            func choices(_ labels: [String], selected: Int, enabled: Bool = true) -> Int? {
                let gapX = 8 * s, w = (fw - gapX * Float(labels.count - 1)) / Float(labels.count)
                var picked: Int?
                for (i, text) in labels.enumerated() {
                    if ui.button(text, x: fx + Float(i) * (w + gapX), y: y, w: w, h: 40 * s, scale: s, input: input,
                                 enabled: enabled || i == selected, primary: i == selected) { picked = i }
                }
                y += 40 * s + 14 * s
                return picked
            }
            caption("World name")
            if ui.field(newName, placeholder: "Name your world", x: fx, y: y, w: fw, h: bh, scale: s, focused: focus == "name", input: input, time: now) { focus = "name" }
            y += bh + 14 * s
            caption("Seed (optional)")
            if ui.field(newSeed, placeholder: "Leave blank for a random world", x: fx, y: y, w: fw, h: bh, scale: s, focused: focus == "seed", input: input, time: now) { focus = "seed" }
            y += bh + 14 * s
            caption("Game mode")
            if let pick = choices(["Survival", "Hardcore", "Creative"], selected: newMode) { click(); newMode = pick }
            let modeInfo = [
                "Gather resources, craft tools, manage health and hunger.",
                "One life on Hard. If you fall, the world is lost forever.",
                "Unlimited blocks, instant breaking and flight (double-tap jump).",
            ][newMode]
            ui.centeredText(modeInfo, centerX: cx, y: y - 6 * s, scale: small, color: SIMD4(0.866, 0.772, 0.63, 0.9))
            y += 12 * small + 6 * s
            caption("Difficulty")
            if let pick = choices(Difficulty.allCases.map { $0.displayName }, selected: newMode == 1 ? 3 : newDifficulty, enabled: newMode != 1) {
                click(); newDifficulty = pick
            }
            let half = (fw - 8 * s) / 2
            if newMode != 2, ui.button("Bonus Chest: \(newBonusChest ? "On" : "Off")", x: fx, y: y, w: half, h: 40 * s, scale: s, input: input,
                                       primary: newBonusChest) {
                click(); newBonusChest.toggle()
            }
            if newMode != 1, ui.button("Commands: \(newCommands ? "On" : "Off")", x: fx + half + 8 * s, y: y, w: half, h: 40 * s, scale: s,
                                       input: input, primary: newCommands) {
                click(); newCommands.toggle()
            }
            let valid = !newName.trimmingCharacters(in: .whitespaces).isEmpty
            let footerY = H - bh - 30 * s
            if ui.button("Create", x: cx - bw - gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input, enabled: valid, primary: true) || (input.enter && valid) {
                click()
                do {
                    var meta = try storage.createWorld(name: newName.trimmingCharacters(in: .whitespaces), seedText: newSeed,
                                                       gameMode: newMode == 2 ? .creative : .survival,
                                                       difficulty: Difficulty.allCases[newDifficulty], hardcore: newMode == 1)
                    if (newBonusChest && newMode != 2) || (!newCommands && newMode != 1) {
                        if newBonusChest && newMode != 2 { meta.bonusChest = true }
                        if !newCommands && newMode != 1 { meta.allowCommands = false }
                        try storage.saveMetadata(meta)
                    }
                    return .play(meta, isNew: true, hostName: nil)
                } catch {
                    message = "Couldn't create the world: \(error)"
                    page = .title
                }
            }
            if ui.button("Back", x: cx + gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input) || input.escape {
                click(); page = .worlds
            }

        case .multiplayer:
            header("Join a Friend")
            if input.tab { focus = focus == "address" ? "player" : "address" }
            edit(&address, id: "address", input: input, limit: 60)
            edit(&playerName, id: "player", input: input, limit: 16)
            var y = H * 0.26
            label("Invite code or IP address", y)
            y += 12 * small
            if ui.field(address, placeholder: "DINO-3M4KA-9QX2B", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, focused: focus == "address", input: input, time: now) { focus = "address" }
            y += bh + 18 * s
            label("Your player name", y)
            y += 12 * small
            if ui.field(playerName, placeholder: "Explorer", x: cx - bw / 2, y: y, w: bw, h: bh, scale: s, focused: focus == "player", input: input, time: now) { focus = "player" }
            y += bh + 18 * s
            if let message {
                ui.centeredText(String(message.prefix(110)), centerX: cx, y: y, scale: small, color: SIMD4(1, 0.6, 0.5, 1))
                y += 14 * small
            }
            ui.centeredText("Your friend opens their world first (on Mac: Esc > Open to Internet, on Windows: Host).",
                            centerX: cx, y: y, scale: small, color: SIMD4(0.866, 0.772, 0.63, 0.9))
            let canJoin = !address.trimmingCharacters(in: .whitespaces).isEmpty
            let footerY = H * 0.74
            if ui.button("Join", x: cx - bw - gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input, enabled: canJoin, primary: true) || (input.enter && canJoin) {
                click()
                startJoin()
            }
            if ui.button("Back", x: cx + gap / 2, y: footerY, w: bw, h: bh, scale: s, input: input) || input.escape {
                click(); message = nil; page = .title
            }

        case .connecting:
            header("Connecting")
            ui.centeredText("Joining \(address)...", centerX: cx, y: H * 0.4, scale: small, color: SIMD4(1, 1, 1, 1))
            joinLock.lock()
            let result = joinResult
            joinLock.unlock()
            if let result {
                switch result {
                case .success(let network):
                    return .join(network)
                case .failure(let error):
                    message = "Couldn't join: \(error)"
                    page = .multiplayer
                }
            }
            if ui.button("Cancel", x: cx - bw / 2, y: H * 0.6, w: bw, h: bh, scale: s, input: input) || input.escape {
                click()
                joinLock.lock()
                joinToken = UUID()
                joinLock.unlock()
                page = .multiplayer
            }

        case .settings:
            header("Settings")
            edit(&playerName, id: "player", input: input, limit: 16)
            let rowW = min(W - 80 * s, 620 * s), rowX = cx - rowW / 2
            var y = H * 0.2
            ui.text("Player name", x: rowX, y: y + bh / 2 - 3.5 * small, scale: small, color: SIMD4(1, 1, 1, 1))
            if ui.field(playerName, placeholder: "Explorer", x: rowX + rowW - 260 * s, y: y, w: 260 * s, h: bh, scale: s, focused: focus == "player", input: input, time: now) { focus = "player" }
            y += bh + gap
            let panel = SettingsPanel(store: store, renderer: renderer, audio: audio, window: window, click: { [weak self] in self?.click() })
            _ = panel.build(&ui, input: input, width: W, top: y, scale: s)
            if ui.button("Done", x: cx - bw / 2, y: H - bh - 24 * s, w: bw, h: bh, scale: s, input: input, primary: true) || input.escape || input.enter {
                click()
                let name = cleanName(playerName)
                store.update { $0.username = name }
                playerName = name
                focus = ""
                page = settingsReturn
            }
        }
        return nil
    }

    private func startJoin() {
        let target = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = cleanName(playerName)
        store.update {
            $0.lastServerAddress = target
            $0.username = name
        }
        message = nil
        page = .connecting
        let token = UUID()
        joinLock.lock()
        joinToken = token
        joinResult = nil
        joinLock.unlock()
        let identity = (id: store.settings.playerID, look: store.settings.cosmetics)
        Thread { [weak self] in
            let result: Result<WinNetwork, Error>
            do {
                result = .success(try WinNetwork.join(address: target, username: name, playerID: identity.id, look: identity.look))
            } catch {
                result = .failure(error)
            }
            guard let self else { return }
            self.joinLock.lock()
            if self.joinToken == token {
                self.joinResult = result
            } else if case .success(let network) = result {
                network.disconnect()
            }
            self.joinLock.unlock()
        }.start()
    }
}

// MARK: - Launcher and cosmetics

extension WinMenus {
    private var amber: SIMD4<Float> { SIMD4(1, 0.85, 0.55, 1) }
    private var muted: SIMD4<Float> { SIMD4(0.866, 0.772, 0.63, 0.9) }

    /// The pre-launcher: news about the newest build, the update button, cosmetics, settings and Play.
    fileprivate func buildLauncher(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) -> Choice? {
        let small = max(1, (2 * s).rounded())
        let cx = W / 2
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.45))

        // Title in the texture pack's colours
        let big = max(1, (8 * s).rounded())
        let pack = renderer.texturePack
        func color(_ hex: UInt32) -> SIMD4<Float> {
            SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
        }
        let titleY = H * 0.07
        ui.centeredText(pack.title, centerX: cx + big * 0.5, y: titleY + big, scale: big, color: color(pack.titleBottom))
        ui.centeredText(pack.title, centerX: cx, y: titleY, scale: big, color: color(pack.titleTop))
        ui.centeredText(options.launcherOnly ? "DINOCRAFT LAUNCHER" : "LAUNCHER", centerX: cx, y: titleY + 10 * big, scale: small, color: muted)

        // News panel
        let panelX = max(20 * s, cx - 600 * s), panelY = H * 0.27
        let panelW = min(640 * s, cx - panelX - 30 * s), panelH = H * 0.6
        ui.woodPanel(panelX, panelY, panelW, panelH, scale: s)
        ui.rect(panelX, panelY, 5 * s, panelH, SIMD4(0.95, 0.6, 0.12, 1))
        let maxChars = max(10, Int((panelW - 40 * s) / (6 * small)))
        var ny = panelY + 18 * s
        func line(_ text: String, _ c: SIMD4<Float>) {
            guard ny < panelY + panelH - 20 * s else { return }
            ui.text(text, x: panelX + 22 * s, y: ny, scale: small, color: c, shadow: false)
            ny += 11 * small
        }
        let state = updater.state
        if showingGuide {
            ui.text("How to beat DinoCraft", x: panelX + 22 * s, y: ny, scale: max(1, (3 * s).rounded()), color: amber)
            ny += 16 * max(1, (3 * s).rounded()) / 2 + 12 * s
            for (i, step) in GameGuide.steps.enumerated() {
                line("\(i + 1). \(step.title)", SIMD4(1, 1, 1, 1))
                for part in WinMenus.wrap(step.hint, width: maxChars - 3) { line("   " + part, muted) }
                ny += 3 * s
            }
            line("In game, press G to show or hide your next goal.", SIMD4(0.55, 0.95, 0.5, 1))
        } else if let release = updater.latestRelease, release.build > BuildInfo.current.build {
            ui.text("New in the update", x: panelX + 22 * s, y: ny, scale: max(1, (3 * s).rounded()), color: amber)
            ny += 16 * max(1, (3 * s).rounded()) / 2 + 12 * s
            line("\(release.title)\(release.published.isEmpty ? "" : " - \(release.published)")", SIMD4(1, 1, 1, 1))
            ny += 4 * s
            for raw in release.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = raw.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { ny += 5 * s; continue }
                for part in WinMenus.wrap(text.replacingOccurrences(of: "**", with: ""), width: maxChars) { line(part, muted) }
            }
        } else if !BuildInfo.whatsNew.isEmpty {
            ui.text("What's new", x: panelX + 22 * s, y: ny, scale: max(1, (3 * s).rounded()), color: amber)
            ny += 16 * max(1, (3 * s).rounded()) / 2 + 12 * s
            for (i, raw) in BuildInfo.whatsNew.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let text = raw.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { ny += 5 * s; continue }
                let heading = i == 0 || !text.hasPrefix("-")
                for part in WinMenus.wrap(text, width: maxChars) { line(part, heading ? SIMD4(1, 1, 1, 1) : muted) }
            }
        } else {
            ui.text("Welcome, explorer!", x: panelX + 22 * s, y: ny, scale: max(1, (3 * s).rounded()), color: amber)
            ny += 16 * max(1, (3 * s).rounded()) / 2 + 12 * s
            let tips = [
                "Press Play to pick a world or join a friend.",
                "Cosmetics: choose a hat, outfit, cape or dino tail. Friends see it in multiplayer.",
                "Settings: texture packs, shader packs, view distance and more.",
                "The launcher checks for new versions each time it opens.",
                "",
                "In game: E inventory, T chat, / commands, F1 info, F2 screenshot.",
            ]
            for tip in tips { if tip.isEmpty { ny += 6 * s } else { for part in WinMenus.wrap(tip, width: maxChars) { line(part, muted) } } }
        }

        // Buttons
        let bx = panelX + panelW + 30 * s, bw = min(420 * s, W - bx - 20 * s), bh = 50 * s, gap = 12 * s
        var y = panelY
        if ui.button("Play", x: bx, y: y, w: bw, h: bh + 10 * s, scale: s, input: input, primary: true) || input.enter {
            click(); message = nil
            if options.launcherOnly { return .launchGame(join: nil) }
            page = .title
        }
        y += bh + 10 * s + gap

        // Update button: what it says and does follows the updater.
        var label = "Check for Updates", enabled = true, primary = false
        var status = BuildInfo.current.displayName
        var action: (() -> Void)? = { [updater] in updater.check() }
        switch state {
        case .idle:
            break
        case .checking:
            label = "Checking for Updates..."; enabled = false; action = nil
        case .upToDate(let release):
            label = "Up to Date"
            status = release.map { BuildInfo.current.isDevelopment ? "Newest release is build \($0.build)" : "You have the newest build (\($0.build))" }
                ?? "No releases published yet"
        case .available(let release, let canInstall):
            if canInstall {
                label = "Update to Build \(release.build)"; primary = true
                action = { [updater] in updater.download() }
                status = "A new version is ready to download"
            } else {
                label = "Build \(release.build) Available"; enabled = false; action = nil
                status = BuildInfo.current.isDevelopment ? "This copy was built by hand, so it can't update itself"
                    : "This release has no Windows download yet"
            }
        case .downloading(let release, let fraction):
            label = "Downloading... \(Int(fraction * 100))%"; enabled = false; action = nil
            status = "Build \(release.build)"
            ui.rect(bx, y + bh + 2 * s, bw, 4 * s, SIMD4(0, 0, 0, 0.5))
            ui.rect(bx, y + bh + 2 * s, bw * Float(fraction), 4 * s, SIMD4(0.95, 0.6, 0.12, 1))
        case .downloaded(let release, let file):
            label = "Restart to Update"; primary = true
            status = "Build \(release.build) downloaded"
            action = { [weak self] in
                if let error = WinUpdater.install(zip: file) {
                    self?.updateError = error
                } else {
                    self?.updateError = nil
                    self?.quitForUpdate = true
                }
            }
        case .failed(let reason):
            label = "Try Again"
            status = reason
        }
        if ui.button(label, x: bx, y: y, w: bw, h: bh, scale: s, input: input, enabled: enabled, primary: primary), let action {
            click()
            action()
        }
        y += bh + 8 * s
        let statusText = updateError ?? status
        for part in WinMenus.wrap(statusText, width: max(10, Int(bw / (6 * small)))).prefix(2) {
            ui.text(part, x: bx, y: y, scale: small, color: updateError != nil ? SIMD4(1, 0.6, 0.5, 1) : muted, shadow: false)
            y += 10 * small
        }
        y += gap
        if ui.button("Cosmetics", x: bx, y: y, w: bw, h: bh, scale: s, input: input) { click(); page = .cosmetics }
        y += bh + gap
        if ui.button("Skin Creator", x: bx, y: y, w: bw, h: bh, scale: s, input: input) { click(); skinDraft = nil; page = .skin }
        y += bh + gap
        if ui.button("Settings", x: bx, y: y, w: bw, h: bh, scale: s, input: input) { click(); settingsReturn = .launcher; page = .settings }
        y += bh + gap
        let guideW = (bw - gap) / 2
        if ui.button(showingGuide ? "What's New" : "Guide", x: bx, y: y, w: guideW, h: bh, scale: s, input: input) {
            click(); showingGuide.toggle()
        }
        if ui.button("Leaderboard", x: bx + guideW + gap, y: y, w: guideW, h: bh, scale: s, input: input) {
            click(); leaderScroll = 0; GameLinks.leaderboard.load(); page = .leaderboard
        }
        y += bh + gap
        let halfW = (bw - gap) / 2
        if ui.button(FriendList.shared.buttonLabel, x: bx, y: y, w: halfW, h: bh, scale: s, input: input) {
            click(); friendMessage = nil; FriendList.shared.refreshStatuses(); page = .friends
        }
        if ui.button(GameLinks.reviews.buttonLabel, x: bx + halfW + gap, y: y, w: halfW, h: bh, scale: s, input: input) {
            click(); GameLinks.reviews.load(); page = .reviews
        }
        y += bh + gap
        if ui.button("Quit", x: bx, y: y, w: bw, h: bh, scale: s, input: input) || input.escape { return .quit }

        ui.text("DinoCraft for Windows - \(BuildInfo.current.displayName)", x: 16 * s, y: H - 14 * s - 7 * small, scale: small, color: muted)
        let folderW = 230 * s
        if ui.button("Open Game Folder", x: W - folderW - 16 * s, y: H - 44 * s, w: folderW, h: 32 * s, scale: s, input: input) {
            click()
            openGameFolder()
        }
        if let donate = GameLinks.donate,
           ui.button(GameLinks.donateLabel, x: W - folderW * 2 - 28 * s, y: H - 44 * s, w: folderW, h: 32 * s, scale: s, input: input, primary: true) {
            click()
            _ = SDL_OpenURL(donate.absoluteString)
        }
        // Your stats, under the news panel
        let played = worlds.reduce(0) { $0 + $1.playTimeSeconds }
        let hours = Int(played / 3600), minutes = Int(played / 60) % 60
        ui.text("\(worlds.count) world\(worlds.count == 1 ? "" : "s") - \(hours)h \(minutes)m played - \(store.settings.username.isEmpty ? "no name yet" : store.settings.username)",
                x: panelX, y: panelY + panelH + 10 * s, scale: small, color: muted)
        if quitForUpdate { return .quit }
        return nil
    }

    /// Everyone's lifetime stats, sortable by category, with your own stats beside them.
    fileprivate func buildLeaderboard(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float) {
        let small = max(1, (2 * s).rounded())
        let head = max(1, (4 * s).rounded())
        ui.rect(0, 0, W, H, SIMD4(0.02, 0.01, 0.005, 0.45))
        ui.centeredText("Leaderboard", centerX: W / 2, y: H * 0.04, scale: head, color: amber)
        ui.centeredText("Everyone who plays DinoCraft. Your stats are shared every few minutes while you play.",
                        centerX: W / 2, y: H * 0.04 + 10 * head, scale: small, color: muted)
        // Categories
        let categories = Leaderboard.Category.allCases
        let tabW = min(140 * s, (W - 80 * s) / Float(categories.count) - 6 * s), tabY = H * 0.04 + 10 * head + 18 * s
        let tabsX = W / 2 - (Float(categories.count) * (tabW + 6 * s) - 6 * s) / 2
        for (i, category) in categories.enumerated() {
            if ui.button(category.tab, x: tabsX + Float(i) * (tabW + 6 * s), y: tabY, w: tabW, h: 32 * s, scale: s, input: input,
                         primary: category == leaderCategory) {
                click(); leaderCategory = category; leaderScroll = 0
            }
        }
        let me = Leaderboard.entryName(name: store.settings.username, playerID: store.settings.playerID)
        let mine = PlayerStats.shared.values
        // The table
        let top = tabY + 44 * s, bottom = H - 80 * s
        let sideW = min(300 * s, W * 0.26)
        let tableX = 40 * s, tableW = W - 80 * s - sideW - 20 * s
        ui.woodPanel(tableX, top, tableW, bottom - top, scale: s)
        let rowH = 12 * small
        var y = top + 16 * s
        switch GameLinks.leaderboard.state {
        case .idle, .loading:
            ui.centeredText("Loading the leaderboard...", centerX: tableX + tableW / 2, y: y + 30 * s, scale: small, color: muted)
        case .failed(let reason):
            ui.centeredText(reason, centerX: tableX + tableW / 2, y: y + 30 * s, scale: small, color: SIMD4(1, 0.7, 0.6, 1))
        case .loaded(let entries):
            let ranked = Leaderboard.ranked(entries, by: leaderCategory)
            if ranked.isEmpty {
                ui.centeredText("Nobody's on the board yet. Play for a minute and you'll be first!", centerX: tableX + tableW / 2, y: y + 30 * s,
                                scale: small, color: muted)
            }
            let visible = max(1, Int((bottom - top - 50 * s) / rowH))
            if input.wheel != 0 { leaderScroll = max(0, min(max(0, ranked.count - visible), leaderScroll - Int(input.wheel))) }
            ui.text("#", x: tableX + 20 * s, y: y, scale: small, color: amber)
            ui.text("Player", x: tableX + 70 * s, y: y, scale: small, color: amber)
            let valueX = tableX + tableW - 20 * s
            ui.text(leaderCategory.title, x: valueX - UIBuilder.textWidth(leaderCategory.title, scale: small), y: y, scale: small, color: amber)
            y += rowH + 4 * s
            for (index, entry) in ranked.enumerated().dropFirst(leaderScroll).prefix(visible) {
                let isMe = entry.name + "_" + entry.tag == me
                if isMe { ui.rect(tableX + 10 * s, y - 3 * s, tableW - 20 * s, rowH, SIMD4(0.5, 0.26, 0.05, 0.6)) }
                let medal: SIMD4<Float> = index == 0 ? SIMD4(1, 0.78, 0.2, 1) : index == 1 ? SIMD4(0.8, 0.82, 0.86, 1) : index == 2 ? SIMD4(0.8, 0.45, 0.2, 1) : SIMD4(1, 0.95, 0.85, 1)
                ui.text("\(index + 1)", x: tableX + 20 * s, y: y, scale: small, color: medal)
                ui.text(entry.display + (isMe ? "  (you)" : ""), x: tableX + 70 * s, y: y, scale: small, color: SIMD4(1, 0.96, 0.88, 1))
                let value = leaderCategory.format(entry.stats)
                ui.text(value, x: valueX - UIBuilder.textWidth(value, scale: small), y: y, scale: small, color: SIMD4(1, 0.96, 0.88, 1))
                y += rowH
            }
        }
        // Your stats
        let sideX = tableX + tableW + 20 * s
        ui.woodPanel(sideX, top, sideW, bottom - top, scale: s)
        var sy = top + 16 * s
        ui.text("Your Stats", x: sideX + 16 * s, y: sy, scale: small, color: amber)
        sy += 12 * small
        ui.text(PlayerIdentity.display(name: store.settings.username, id: store.settings.playerID), x: sideX + 16 * s, y: sy, scale: small,
                color: SIMD4(1, 0.96, 0.88, 1))
        sy += 16 * small
        for category in categories {
            ui.text(category.title, x: sideX + 16 * s, y: sy, scale: small, color: muted)
            let value = category.format(mine)
            ui.text(value, x: sideX + sideW - 16 * s - UIBuilder.textWidth(value, scale: small), y: sy, scale: small, color: SIMD4(1, 0.96, 0.88, 1))
            sy += 12 * small
        }
        if ui.button("Refresh", x: W / 2 - 250 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) {
            click(); PlayerStats.shared.submitNow(); GameLinks.leaderboard.load()
        }
        if ui.button("Back", x: W / 2 + 10 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) || input.escape {
            click(); page = .launcher
        }
    }

    /// Your one-of-a-kind player card, your friends (and whether they're hosting right now) and the
    /// players you've recently been in a game with.
    fileprivate func buildFriends(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) {
        let small = max(1, (2 * s).rounded())
        let head = max(1, (4 * s).rounded())
        let friends = FriendList.shared
        let me = store.settings
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.45))
        ui.centeredText("Friends", centerX: W / 2, y: H * 0.05, scale: head, color: amber)
        ui.centeredText("Add friends with their friend code. Play together once and they show up here too.",
                        centerX: W / 2, y: H * 0.05 + 10 * head, scale: small, color: muted)

        // Your card: a spinning preview, your one-of-a-kind name tag and your friend code.
        let cardX = 40 * s, cardW = min(W * 0.3, 380 * s), cardY = H * 0.17, cardH = H * 0.66
        let infoY = cardY + cardH * 0.46
        ui.woodPanel(cardX, infoY, cardW, cardY + cardH - infoY, scale: s)
        // Stand the preview on top of the card: turn the card's screen position into the preview camera's space.
        let depth: Float = 5.6, tanHalf: Float = 0.766
        let ndcX = (cardX + cardW / 2) / W * 2 - 1, ndcFeet = 1 - 2 * (infoY - 6 * s) / H
        CreatureModels.appendPlayer(&previewModels, name: me.username, look: me.cosmetics,
                                    at: SIMD3(ndcX * depth * tanHalf * W / H, ndcFeet * depth * tanHalf + 0.05, -depth),
                                    yaw: Float(now * 0.8), pitch: 0, walk: 0, moving: 0, sneaking: false, swing: 0, hurt: 0)
        var y = infoY + 14 * s
        let big = max(1, (3 * s).rounded())
        ui.centeredText(PlayerIdentity.display(name: me.username, id: me.playerID), centerX: cardX + cardW / 2, y: y, scale: big, color: amber)
        y += 10 * big + 2 * s
        ui.centeredText("1 of 1", centerX: cardX + cardW / 2, y: y, scale: big, color: SIMD4(0.6, 1, 0.7, 1))
        y += 10 * big
        ui.centeredText("Nobody else has your tag", centerX: cardX + cardW / 2, y: y, scale: small, color: muted)
        y += 14 * small
        let bx = cardX + 16 * s, bw = cardW - 32 * s, bh = 40 * s
        if ui.button("Copy My Friend Code", x: bx, y: y, w: bw, h: bh, scale: s, input: input, primary: true) {
            click()
            let code = friends.myCode(name: me.username, id: me.playerID)
            friendMessage = SDL_SetClipboardText(code) ? "Friend code copied! Send it to a friend." : "Couldn't copy your friend code."
        }
        y += bh + 8 * s
        if ui.button("Add Friend (Paste Code)", x: bx, y: y, w: bw, h: bh, scale: s, input: input) {
            click()
            if let raw = SDL_GetClipboardText() {
                let text = String(cString: raw)
                SDL_free(raw)
                friendMessage = friends.add(code: text, myID: me.playerID)
                friends.refreshStatuses()
            } else {
                friendMessage = "Copy your friend's code first, then press this."
            }
        }
        y += bh + 10 * s
        if let friendMessage {
            for part in WinMenus.wrap(friendMessage, width: max(10, Int(bw / (6 * small)))).prefix(3) {
                ui.text(part, x: bx, y: y, scale: small, color: SIMD4(1, 0.9, 0.6, 1), shadow: false)
                y += 10 * small
            }
        }

        // Friends and recent players
        let listX = cardX + cardW + 24 * s, listW = W - listX - 40 * s, listY = cardY
        ui.woodPanel(listX, listY, listW, cardH, scale: s)
        let rowH = 52 * s
        struct Row { let person: FriendList.Person; let isFriend: Bool }
        let rows = friends.friends.map { Row(person: $0, isFriend: true) } + friends.recent.map { Row(person: $0, isFriend: false) }
        let visible = max(1, Int((cardH - 70 * s) / rowH))
        if input.wheel != 0 { friendScroll = max(0, min(max(0, rows.count - visible), friendScroll - Int(input.wheel))) }
        friendScroll = min(friendScroll, max(0, rows.count - visible))
        y = listY + 14 * s
        if rows.isEmpty {
            ui.centeredText("No friends yet.", centerX: listX + listW / 2, y: y + 40 * s, scale: big, color: SIMD4(1, 1, 1, 0.9))
            ui.centeredText("Copy your friend code and send it to someone, or join a friend's game.", centerX: listX + listW / 2, y: y + 40 * s + 12 * big,
                            scale: small, color: muted)
        }
        var shownRecentHeader = false
        ui.text("Friends (\(friends.friends.count))", x: listX + 16 * s, y: y, scale: small, color: amber)
        y += 12 * small
        for (index, row) in rows.enumerated().dropFirst(friendScroll).prefix(visible) {
            if !row.isFriend && !shownRecentHeader {
                shownRecentHeader = true
                ui.text("Played with recently", x: listX + 16 * s, y: y, scale: small, color: amber)
                y += 12 * small
            }
            guard y + rowH < listY + cardH else { break }
            let p = row.person
            WinMenus.portrait(&ui, look: PlayerLook.resolve(p.look, name: p.name), x: listX + 16 * s, y: y + 4 * s, size: rowH - 14 * s)
            let textX = listX + 16 * s + rowH
            ui.text(p.display, x: textX, y: y + 6 * s, scale: small, color: SIMD4(1, 1, 1, 1))
            let status = friends.status(p.id)
            var line: String
            var lineColor = muted
            switch status {
            case .hosting(let world, let players):
                line = "Playing \(world) - \(players) player\(players == 1 ? "" : "s") - you can join!"
                lineColor = SIMD4(0.55, 1, 0.6, 1)
            case .checking: line = "Checking..."
            case .offline: line = "Not hosting right now"
            case .unknown: line = p.address == nil ? "Hasn't shared where they host yet" : "Press Refresh to check"
            }
            if !row.isFriend { line = p.lastPlayed.map { "Played together " + WinMenus.relative($0) } ?? "Played together" }
            ui.text(line, x: textX, y: y + 6 * s + 11 * small, scale: small, color: lineColor, shadow: false)
            let btnW = 130 * s, btnH = 34 * s, btnY = y + (rowH - 8 * s - btnH) / 2
            if row.isFriend {
                let canJoin: Bool
                if case .hosting = status { canJoin = true } else { canJoin = false }
                if ui.button("Join", x: listX + listW - 2 * btnW - 24 * s, y: btnY, w: btnW, h: btnH, scale: s, input: input,
                             enabled: canJoin && p.address != nil, primary: true), let target = p.address {
                    click()
                    if options.launcherOnly {
                        launchJoin = target
                    } else {
                        address = target
                        playerName = me.username
                        startJoin()
                    }
                }
                if ui.button("Remove", x: listX + listW - btnW - 16 * s, y: btnY, w: btnW, h: btnH, scale: s, input: input) {
                    click(); friends.remove(p.id); friendMessage = "Removed \(p.display)."
                }
            } else if ui.button("Add Friend", x: listX + listW - btnW - 16 * s, y: btnY, w: btnW, h: btnH, scale: s, input: input, primary: true) {
                click(); friends.befriend(p.id); friendMessage = "\(p.display) is now your friend!"; friends.refreshStatuses()
            }
            _ = index
            y += rowH
        }

        if ui.button("Refresh", x: W / 2 - 250 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) {
            click(); friends.refreshStatuses()
        }
        if ui.button("Back", x: W / 2 + 10 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) || input.escape {
            click(); page = .launcher
        }
    }

    /// A tiny flat portrait of an explorer: hat, face and shirt.
    static func portrait(_ ui: inout UIBuilder, look: PlayerLook, x: Float, y: Float, size: Float) {
        func color(_ hex: UInt32) -> SIMD4<Float> {
            SIMD4(Float((hex >> 16) & 255) / 255, Float((hex >> 8) & 255) / 255, Float(hex & 255) / 255, 1)
        }
        let u = size / 8
        ui.rect(x, y, size, size, SIMD4(0.195, 0.109, 0.048, 1))
        ui.rect(x + 2 * u, y + 1 * u, 4 * u, 4 * u, color(PlayerLook.skinTones[look.skin]))                       // face
        ui.rect(x + 3 * u, y + 2.5 * u, 0.7 * u, 0.7 * u, SIMD4(0.1, 0.08, 0.1, 1))                              // eyes
        ui.rect(x + 4.3 * u, y + 2.5 * u, 0.7 * u, 0.7 * u, SIMD4(0.1, 0.08, 0.1, 1))
        if look.hat != .none { ui.rect(x + 1.6 * u, y + 0.4 * u, 4.8 * u, 1.3 * u, color(PlayerLook.accentColors[look.accent])) }  // hat
        ui.rect(x + 1.5 * u, y + 5.2 * u, 5 * u, 2.8 * u, color(PlayerLook.shirtColors[look.shirt]))            // shirt
    }

    /// "today", "yesterday" or "3 days ago".
    static func relative(_ date: Date) -> String {
        let days = Int(Date().timeIntervalSince(date) / 86_400)
        return days <= 0 ? "today" : days == 1 ? "yesterday" : "\(days) days ago"
    }

    /// Everyone's reviews (read from GitHub), the average rating, and a star picker that opens
    /// a pre-filled page for writing your own.
    fileprivate func buildReviews(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float) {
        let small = max(1, (2 * s).rounded())
        let head = max(1, (4 * s).rounded())
        let gold = SIMD4<Float>(1, 0.8, 0.25, 1), dimStar = SIMD4<Float>(0.659, 0.368, 0.163, 1)
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.55))
        ui.centeredText("Player Reviews", centerX: W / 2, y: H * 0.05, scale: head, color: amber)
        let board = GameLinks.reviews
        func stars(_ n: Int, x: Float, y: Float, scale: Float) {
            for k in 0..<5 { ui.text("\u{2605}", x: x + Float(k) * 8 * scale, y: y, scale: scale, color: k < n ? gold : dimStar) }
        }
        let panelW = min(W - 60 * s, 900 * s), panelX = W / 2 - panelW / 2, panelY = H * 0.05 + 10 * head + 16 * s
        let panelH = H - panelY - 205 * s
        ui.woodPanel(panelX, panelY, panelW, panelH, scale: s)
        var y = panelY + 16 * s
        let maxChars = max(10, Int((panelW - 40 * s) / (6 * small)))
        switch board.state {
        case .idle, .loading:
            ui.centeredText("Loading reviews...", centerX: W / 2, y: y + 20 * s, scale: small, color: muted)
        case .failed(let reason):
            for part in WinMenus.wrap(reason, width: maxChars) {
                ui.centeredText(part, centerX: W / 2, y: y + 20 * s, scale: small, color: SIMD4(1, 0.7, 0.6, 1))
                y += 10 * small
            }
        case .loaded(let list):
            if list.isEmpty {
                ui.centeredText("No reviews yet. Be the first!", centerX: W / 2, y: y + 20 * s, scale: small, color: muted)
            } else {
                let big = max(1, (3 * s).rounded())
                stars(Int(board.average.rounded()), x: panelX + 20 * s, y: y, scale: big)
                ui.text(String(format: "%.1f out of 5 from %d review%@", board.average, list.count, list.count == 1 ? "" : "s"),
                        x: panelX + 20 * s + 44 * big, y: y + 2 * s, scale: small, color: SIMD4(1, 1, 1, 1))
                y += 10 * big + 10 * s
                for review in list {
                    guard y < panelY + panelH - 30 * s else { break }
                    stars(review.stars, x: panelX + 20 * s, y: y, scale: small)
                    ui.text("\(review.author) - \(review.date)", x: panelX + 20 * s + 46 * small, y: y, scale: small, color: amber)
                    y += 10 * small
                    for part in WinMenus.wrap(review.text, width: maxChars).prefix(3) {
                        ui.text(part, x: panelX + 20 * s, y: y, scale: small, color: muted, shadow: false)
                        y += 10 * small
                    }
                    y += 8 * s
                }
            }
        }
        // Your review: stars and a few words, then post it on GitHub (anyone with a free account can post)
        edit(&reviewWords, id: "review", input: input, limit: 240)
        let rowY = panelY + panelH + 16 * s
        ui.text("Your rating:", x: panelX, y: rowY + 12 * s, scale: small, color: SIMD4(1, 1, 1, 1))
        let starW = 40 * s
        for k in 1...5 {
            let sx = panelX + 160 * s + Float(k - 1) * (starW + 6 * s)
            if ui.button("\u{2605}", x: sx, y: rowY, w: starW, h: 38 * s, scale: s, input: input, primary: k <= reviewStars) {
                click(); reviewStars = k
            }
        }
        let bw = 260 * s
        if ui.field(reviewWords, placeholder: "Type your review here...", x: panelX, y: rowY + 46 * s, w: panelW - bw - 12 * s, h: 38 * s,
                    scale: s, focused: focus == "review", input: input, time: Date.timeIntervalSinceReferenceDate) { focus = "review" }
        if ui.button("Post Review", x: panelX + panelW - bw, y: rowY + 46 * s, w: bw, h: 38 * s, scale: s, input: input, primary: true)
            || (focus == "review" && input.enter),
           let url = board.writeURL(stars: reviewStars, username: store.settings.username, words: reviewWords) {
            click()
            if SDL_OpenURL(url.absoluteString) {
                reviewWords = ""
                updateError = nil
            } else {
                updateError = "Couldn't open your browser. Go to github.com/\(board.repository)/issues/new to post."
            }
        }
        ui.text(updateError ?? "Opens GitHub with your review filled in: sign in (free) and press Create to post it.", x: panelX, y: rowY + 92 * s,
                scale: small, color: muted)
        if ui.button("Refresh", x: W / 2 - 250 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) { click(); board.load() }
        if ui.button("Back", x: W / 2 + 10 * s, y: H - 60 * s, w: 240 * s, h: 44 * s, scale: s, input: input) || input.escape {
            click(); page = .launcher
        }
    }

    /// Choose a hat, outfit colours and something to wear on your back, with a spinning preview.
    fileprivate func buildCosmetics(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) {
        let small = max(1, (2 * s).rounded())
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.35))
        let head = max(1, (4 * s).rounded())
        ui.centeredText("Cosmetics", centerX: W / 2, y: H * 0.06, scale: head, color: amber)
        ui.centeredText("Friends see your look in multiplayer, on Mac and Windows.", centerX: W / 2, y: H * 0.06 + 10 * head,
                        scale: small, color: muted)

        var look = PlayerLook(encoded: store.settings.cosmetics) ?? PlayerLook.oneOfOne(id: store.settings.playerID)
        let before = look

        // Spinning preview on the left half of the screen
        let spin = Float(now * 0.8)
        CreatureModels.appendPlayer(&previewModels, name: store.settings.username, look: look.encoded,
                                    at: SIMD3(-1.45, -1.0, -4.0), yaw: spin, pitch: 0, walk: Float(now * 4),
                                    moving: 0.35, sneaking: false, swing: 0, hurt: 0)

        // Options on the right
        let colW = min(560 * s, W * 0.5), x = W - colW - 40 * s
        let rowH = 42 * s, rowGap = 10 * s
        var y = H * 0.22
        func row(_ title: String, _ value: String, minus: () -> Void, plus: () -> Void) {
            ui.rect(x, y, colW, rowH, SIMD4(0.123, 0.069, 0.03, 0.88))
            ui.text(title, x: x + 12 * s, y: y + rowH / 2 - 3.5 * small, scale: small, color: SIMD4(1, 1, 1, 1))
            let bw = 40 * s, valueW = min(230 * s, colW * 0.5)
            let bx = x + colW - bw * 2 - valueW - 8 * s
            if ui.button("<", x: bx, y: y + 4 * s, w: bw, h: rowH - 8 * s, scale: s, input: input) { click(); minus() }
            ui.centeredText(value, centerX: bx + bw + valueW / 2, y: y + rowH / 2 - 3.5 * small, scale: small, color: amber)
            if ui.button(">", x: bx + bw + valueW, y: y + 4 * s, w: bw, h: rowH - 8 * s, scale: s, input: input) { click(); plus() }
            y += rowH + rowGap
        }
        func cycle(_ i: inout Int, _ count: Int, _ step: Int) { i = (i + step + count) % count }
        let hats = PlayerLook.Hat.allCases, backs = PlayerLook.Back.allCases
        var hat = hats.firstIndex(of: look.hat) ?? 0, back = backs.firstIndex(of: look.back) ?? 0
        row("Hat", look.hat.displayName, minus: { cycle(&hat, hats.count, -1) }, plus: { cycle(&hat, hats.count, 1) })
        row("Shirt", PlayerLook.shirtNames[look.shirt], minus: { cycle(&look.shirt, PlayerLook.shirtColors.count, -1) },
            plus: { cycle(&look.shirt, PlayerLook.shirtColors.count, 1) })
        row("Trousers", PlayerLook.pantsNames[look.pants], minus: { cycle(&look.pants, PlayerLook.pantsColors.count, -1) },
            plus: { cycle(&look.pants, PlayerLook.pantsColors.count, 1) })
        row("Skin", PlayerLook.skinNames[look.skin], minus: { cycle(&look.skin, PlayerLook.skinTones.count, -1) },
            plus: { cycle(&look.skin, PlayerLook.skinTones.count, 1) })
        row("On your back", look.back.displayName, minus: { cycle(&back, backs.count, -1) }, plus: { cycle(&back, backs.count, 1) })
        row("Accent colour", PlayerLook.accentNames[look.accent], minus: { cycle(&look.accent, PlayerLook.accentColors.count, -1) },
            plus: { cycle(&look.accent, PlayerLook.accentColors.count, 1) })
        look.hat = hats[hat]
        look.back = backs[back]

        y += 8 * s
        let half = (colW - 12 * s) / 2
        if ui.button("Surprise Me", x: x, y: y, w: half, h: 46 * s, scale: s, input: input) {
            click()
            look.hat = hats.randomElement()!
            look.back = backs.randomElement()!
            look.shirt = Int.random(in: 0..<PlayerLook.shirtColors.count)
            look.pants = Int.random(in: 0..<PlayerLook.pantsColors.count)
            look.skin = Int.random(in: 0..<PlayerLook.skinTones.count)
            look.accent = Int.random(in: 0..<PlayerLook.accentColors.count)
        }
        if ui.button("Reset", x: x + half + 12 * s, y: y, w: half, h: 46 * s, scale: s, input: input) {
            click()
            look = PlayerLook.oneOfOne(id: store.settings.playerID)
        }
        if look != before { store.update { $0.cosmetics = look.encoded } }
        if ui.button("Done", x: W / 2 - 200 * s, y: H - 46 * s - 24 * s, w: 400 * s, h: 46 * s, scale: s, input: input, primary: true) || input.escape {
            click()
            page = .launcher
        }
    }

    /// Splits text at spaces into lines of at most `width` characters.
    static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = [], line = ""
        for word in text.split(separator: " ") {
            if !line.isEmpty && line.count + word.count + 1 > width {
                lines.append(line)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + String(word.prefix(width))
        }
        if !line.isEmpty { lines.append(line) }
        return lines
    }
}

// MARK: - Skin creator

extension WinMenus {
    /// Opens DinoCraft's data folder (worlds, screenshots, texture packs) in Explorer.
    fileprivate func openGameFolder() {
        #if os(Windows)
        let explorer = Process()
        explorer.executableURL = URL(fileURLWithPath: "C:\\Windows\\explorer.exe")
        explorer.arguments = [GamePaths.root.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? GamePaths.root.path]
        try? explorer.run()
        #else
        Log.info("Game folder: \(GamePaths.root.path)", category: "App")
        #endif
    }

    /// Paint your own face and shirt, pixel by pixel, with a live preview. Friends see it in multiplayer.
    fileprivate func buildSkinCreator(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) {
        let small = max(1, (2 * s).rounded())
        let amber = SIMD4<Float>(1, 0.85, 0.55, 1), muted = SIMD4<Float>(0.866, 0.772, 0.63, 0.9)
        ui.rect(0, 0, W, H, SIMD4(0.03, 0.017, 0.007, 0.45))
        let head = max(1, (4 * s).rounded())
        ui.centeredText("Skin Creator", centerX: W / 2, y: H * 0.04, scale: head, color: amber)
        ui.centeredText("Left-click paints, right-click rubs out. Friends see your skin in multiplayer.", centerX: W / 2,
                        y: H * 0.04 + 10 * head, scale: small, color: muted)

        var look = skinDraft ?? PlayerLook(encoded: store.settings.cosmetics) ?? PlayerLook.oneOfOne(id: store.settings.playerID)
        let region = SkinRegion.byID[skinRegionID] ?? SkinRegion.all[0]
        let face = region.id == "hf", shirtFront = region.id == "bf"

        // Preview, turned to show the side you're painting (and swaying a little)
        let sideYaw: Float
        switch region.side {
        case .front, .top: sideYaw = .pi
        case .back: sideYaw = 0
        case .left: sideYaw = .pi / 2
        case .right: sideYaw = -.pi / 2
        }
        CreatureModels.appendPlayer(&previewModels, name: store.settings.username, look: look.encoded,
                                    at: SIMD3(-2.0, -1.05, -4.0), yaw: sideYaw + Float(sin(now * 0.7)) * 0.35, pitch: region.side == .top ? -0.6 : 0,
                                    walk: 0, moving: 0, sneaking: false, swing: 0, hurt: 0)

        // Which part and which side
        let cols = region.width, rows = region.height
        let canvasX = W * 0.36, canvasY = H * 0.3
        let partW = 110 * s, partH = 32 * s
        for (i, part) in SkinRegion.parts.enumerated() {
            let x = W * 0.36 - 20 * s + Float(i % 3) * (partW + 6 * s) - 0 * s, y = H * 0.115 + Float(i / 3) * (partH + 6 * s)
            if ui.button(part, x: x, y: y, w: partW, h: partH, scale: s, input: input, primary: region.part == part) {
                click()
                let sides = SkinRegion.regions(part: part)
                skinRegionID = (sides.first { $0.side == region.side } ?? sides[0]).id
            }
        }
        let sides = SkinRegion.regions(part: region.part)
        let sideW = 86 * s
        for (i, side) in sides.enumerated() {
            let x = W * 0.36 - 20 * s + Float(i) * (sideW + 6 * s), y = H * 0.115 + 2 * (partH + 6 * s) + 4 * s
            if ui.button(side.side.rawValue.capitalized, x: x, y: y, w: sideW, h: partH, scale: s, input: input, primary: side.id == region.id) {
                click(); skinRegionID = side.id
            }
        }
        let cell = min(30 * s, (H * 0.5) / Float(rows), (W * 0.26) / Float(cols))
        let canvasW = cell * Float(cols), canvasH = cell * Float(rows)

        // Canvas: unpainted cells show the model's own colour.
        let base = PlayerAvatar.color(region.baseColor(look))
        func srgb(_ c: SIMD4<Float>) -> SIMD4<Float> { SIMD4(pow(c.x, 1 / 2.2), pow(c.y, 1 / 2.2), pow(c.z, 1 / 2.2), 1) }
        func paintColor(_ i: UInt8) -> SIMD4<Float> { srgb(PlayerAvatar.color(PlayerLook.paintColors[Int(i)])) }
        ui.rect(canvasX - 4 * s, canvasY - 4 * s, canvasW + 8 * s, canvasH + 8 * s, SIMD4(0.071, 0.039, 0.017, 1))
        var pixels = look.pixels(region)
        for r in 0..<rows {
            for c in 0..<cols {
                let v = pixels[r * cols + c]
                let x = canvasX + Float(c) * cell, y = canvasY + Float(r) * cell
                ui.rect(x, y, cell, cell, v == 0 ? srgb(base) * SIMD4(0.8, 0.8, 0.8, 1) : paintColor(v))
                ui.rect(x, y, cell, 1, SIMD4(0, 0, 0, 0.18))
                ui.rect(x, y, 1, cell, SIMD4(0, 0, 0, 0.18))
            }
        }
        if skinMirror { ui.rect(canvasX + canvasW / 2 - 1 * s, canvasY, 2 * s, canvasH, SIMD4(1, 0.85, 0.55, 0.35)) }
        let inCanvas = input.mouse.x >= canvasX && input.mouse.x < canvasX + canvasW && input.mouse.y >= canvasY && input.mouse.y < canvasY + canvasH
        if inCanvas && (input.leftDown || input.rightDown || input.clicked) {
            let c = Int((input.mouse.x - canvasX) / cell), r = Int((input.mouse.y - canvasY) / cell)
            let value: UInt8 = input.rightDown ? 0 : skinColor
            if skinFill && input.clicked {
                WinMenus.floodFill(&pixels, cols: cols, rows: rows, from: r * cols + c, to: value)
                if skinMirror { WinMenus.floodFill(&pixels, cols: cols, rows: rows, from: r * cols + (cols - 1 - c), to: value) }
            } else if !skinFill {
                pixels[r * cols + c] = value
                if skinMirror { pixels[r * cols + (cols - 1 - c)] = value }
            }
        }

        // Palette
        // The palette stays put while the canvas changes shape between parts.
        let widest = 8 * min(30 * s, (H * 0.5) / 8, (W * 0.26) / 8)
        let swatch = 40 * s, px = canvasX + max(canvasW, widest) + 40 * s
        var py = canvasY
        ui.text("Colours", x: px, y: py - 22 * s, scale: small, color: muted)
        for i in 0..<16 {
            let x = px + Float(i % 4) * (swatch + 6 * s), y = py + Float(i / 4) * (swatch + 6 * s)
            if UInt8(i) == skinColor { ui.rect(x - 3 * s, y - 3 * s, swatch + 6 * s, swatch + 6 * s, SIMD4(1, 0.85, 0.55, 1)) }
            if i == 0 {
                ui.rect(x, y, swatch, swatch, srgb(base))
                ui.centeredText("x", centerX: x + swatch / 2, y: y + swatch / 2 - 3.5 * small, scale: small, color: SIMD4(0.2, 0.1, 0.1, 1))
            } else {
                ui.rect(x, y, swatch, swatch, paintColor(UInt8(i)))
            }
            if input.clicked && input.mouse.x >= x && input.mouse.x < x + swatch && input.mouse.y >= y && input.mouse.y < y + swatch {
                click()
                skinColor = UInt8(i)
            }
        }
        py += 4 * (swatch + 6 * s) + 14 * s

        // Tools
        let tw = 150 * s, th = 38 * s
        func tool(_ label: String, _ col: Int, primary: Bool = false) -> Bool {
            ui.button(label, x: px + Float(col) * (tw + 8 * s), y: py, w: tw, h: th, scale: s, input: input, primary: primary)
        }
        if tool(skinFill ? "Fill" : "Brush", 0, primary: skinFill) { click(); skinFill.toggle() }
        if tool(skinMirror ? "Mirror On" : "Mirror Off", 1, primary: skinMirror) { click(); skinMirror.toggle() }
        py += th + 8 * s
        if face || shirtFront {
            let presets = face ? PlayerLook.facePresets : PlayerLook.chestPresets
            let presetIndex = face ? skinFacePreset : skinChestPreset
            if tool("Idea: \(presets[presetIndex].name)", 0) {
                click()
                pixels = PlayerLook.presetPixels(presets[presetIndex].pixels, count: cols * rows)
                if face { skinFacePreset = (skinFacePreset + 1) % presets.count } else { skinChestPreset = (skinChestPreset + 1) % presets.count }
            }
        } else if let twin = region.twin, tool(region.copyTwinLabel, 0) {
            click(); pixels = look.pixels(twin)
        }
        if tool("Clear", 1) { click(); pixels = Array(repeating: 0, count: cols * rows) }
        py += th + 8 * s
        if tool("Copy Code", 0) {
            click()
            skinMessage = SDL_SetClipboardText(look.shareCode) ? "Skin code copied - paste it to a friend!" : "Couldn't copy the code."
        }
        if tool("Paste Code", 1) {
            click()
            if let raw = SDL_GetClipboardText() {
                let text = String(cString: raw)
                SDL_free(raw)
                if let pasted = PlayerLook(shareCode: text) {
                    look = pasted
                    pixels = look.pixels(region)
                    skinMessage = "Skin pasted!"
                } else {
                    skinMessage = "The clipboard doesn't hold a DinoCraft skin code."
                }
            }
        }
        py += th + 10 * s
        if let skinMessage {
            for line in WinMenus.wrap(skinMessage, width: max(10, Int((2 * tw + 8 * s) / (6 * small)))).prefix(2) {
                ui.text(line, x: px, y: py, scale: small, color: muted)
                py += 10 * small
            }
        }

        look.setPixels(pixels, for: region)
        skinDraft = look

        let bw = 250 * s, by = H - 46 * s - 22 * s
        if ui.button("Save & Play", x: W / 2 - bw * 1.5 - 12 * s, y: by, w: bw, h: 46 * s, scale: s, input: input, primary: true) || input.enter {
            click()
            store.update { $0.cosmetics = look.encoded }
            skinDraft = nil
            skinMessage = nil
            page = .title
        }
        if ui.button("Save & Back", x: W / 2 - bw / 2, y: by, w: bw, h: 46 * s, scale: s, input: input) || input.escape {
            click()
            store.update { $0.cosmetics = look.encoded }
            skinDraft = nil
            skinMessage = nil
            page = .launcher
        }
        if ui.button("Cancel", x: W / 2 + bw / 2 + 12 * s, y: by, w: bw, h: 46 * s, scale: s, input: input) {
            click()
            skinDraft = nil
            skinMessage = nil
            page = .launcher
        }
    }

    /// Fills the area of matching colour around `start`.
    static func floodFill(_ pixels: inout [UInt8], cols: Int, rows: Int, from start: Int, to value: UInt8) {
        let target = pixels[start]
        guard target != value else { return }
        var stack = [start]
        while let i = stack.popLast() {
            guard pixels[i] == target else { continue }
            pixels[i] = value
            let r = i / cols, c = i % cols
            if c > 0 { stack.append(i - 1) }
            if c < cols - 1 { stack.append(i + 1) }
            if r > 0 { stack.append(i - cols) }
            if r < rows - 1 { stack.append(i + cols) }
        }
    }
}
