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
        var color: SIMD4<Float> = !enabled ? SIMD4(0.12, 0.1, 0.16, 0.8) : (primary ? SIMD4(0.78, 0.38, 0.08, 1) : SIMD4(0.2, 0.15, 0.32, 0.95))
        if hovered { color = SIMD4(min(1, color.x + 0.12), min(1, color.y + 0.1), min(1, color.z + 0.1), 1) }
        rect(x, y, w, h, color)
        let small = max(1, (2 * s).rounded())
        centeredText(label, centerX: x + w / 2, y: y + h / 2 - 3.5 * small, scale: small,
                     color: enabled ? SIMD4(1, 1, 1, 1) : SIMD4(0.6, 0.6, 0.65, 1))
        return hovered && input.clicked
    }

    /// Draws a text field; returns true if it was clicked (so the caller can focus it).
    mutating func field(_ value: String, placeholder: String, x: Float, y: Float, w: Float, h: Float, scale s: Float,
                        focused: Bool, input: MenuInput, time: Double) -> Bool {
        let hovered = input.mouse.x >= x && input.mouse.x < x + w && input.mouse.y >= y && input.mouse.y < y + h
        rect(x, y, w, h, focused ? SIMD4(0.03, 0.02, 0.06, 1) : SIMD4(0.07, 0.05, 0.11, 0.95))
        rect(x, y + h - 2 * s, w, 2 * s, focused ? SIMD4(0.95, 0.6, 0.15, 1) : SIMD4(0.3, 0.25, 0.42, 1))
        let small = max(1, (2 * s).rounded())
        let textY = y + h / 2 - 3.5 * small
        if value.isEmpty && !focused {
            text(placeholder, x: x + 10 * s, y: textY, scale: small, color: SIMD4(0.55, 0.52, 0.62, 1), shadow: false)
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
    }

    private enum Page { case launcher, cosmetics, title, worlds, create, multiplayer, settings, connecting }

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
            page = .launcher
            if store.settings.checkForUpdates && options.screenshotPath == nil { updater.check() }
        }
        focus = ""
        address = store.settings.lastServerAddress
        playerName = defaultName
        refreshWorlds()
        if options.demoScreen == "worlds" { page = .worlds }
        if options.demoScreen == "create" { page = .create; focus = "name" }
        if options.demoScreen == "cosmetics" { page = .cosmetics }
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
        ui.rect(0, 0, W, H, SIMD4(0.02, 0.01, 0.05, 0.35))

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
                ui.rect(listX, y, listW, rowH, SIMD4(0.1, 0.07, 0.16, 0.9))
                let bwSmall = 92 * s, bhSmall = 36 * s, by = y + (rowH - bhSmall) / 2
                let textChars = max(8, Int((listW - 3 * bwSmall - 52 * s) / (6 * small)))
                func fit(_ text: String) -> String { text.count > textChars ? String(text.prefix(textChars - 1)) + "\u{2026}" : text }
                ui.text(fit(world.name), x: listX + 14 * s, y: y + 10 * s, scale: small, color: SIMD4(1, 1, 1, 1))
                let mode = world.isHardcore ? ((world.hardcoreDead ?? false) ? "Hardcore - Game Over" : "Hardcore") : world.gameMode.displayName
                let detail = "\(mode) - \(world.difficulty.displayName) - \(formatter.string(from: world.lastPlayed))"
                ui.text(fit(detail), x: listX + 14 * s, y: y + 10 * s + 11 * small, scale: small, color: SIMD4(0.7, 0.66, 0.8, 1))
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
            ui.centeredText(modeInfo, centerX: cx, y: y - 6 * s, scale: small, color: SIMD4(0.8, 0.76, 0.9, 0.9))
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
                            centerX: cx, y: y, scale: small, color: SIMD4(0.8, 0.76, 0.9, 0.9))
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
        Thread { [weak self] in
            let result: Result<WinNetwork, Error>
            do {
                result = .success(try WinNetwork.join(address: target, username: name))
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
    private var muted: SIMD4<Float> { SIMD4(0.8, 0.76, 0.9, 0.9) }

    /// The pre-launcher: news about the newest build, the update button, cosmetics, settings and Play.
    fileprivate func buildLauncher(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) -> Choice? {
        let small = max(1, (2 * s).rounded())
        let cx = W / 2
        ui.rect(0, 0, W, H, SIMD4(0.02, 0.01, 0.05, 0.45))

        // Title in the texture pack's colours
        let big = max(1, (8 * s).rounded())
        let pack = renderer.texturePack
        func color(_ hex: UInt32) -> SIMD4<Float> {
            SIMD4(Float((hex >> 16) & 0xFF) / 255, Float((hex >> 8) & 0xFF) / 255, Float(hex & 0xFF) / 255, 1)
        }
        let titleY = H * 0.07
        ui.centeredText(pack.title, centerX: cx + big * 0.5, y: titleY + big, scale: big, color: color(pack.titleBottom))
        ui.centeredText(pack.title, centerX: cx, y: titleY, scale: big, color: color(pack.titleTop))
        ui.centeredText("LAUNCHER", centerX: cx, y: titleY + 10 * big, scale: small, color: muted)

        // News panel
        let panelX = max(20 * s, cx - 600 * s), panelY = H * 0.27
        let panelW = min(640 * s, cx - panelX - 30 * s), panelH = H * 0.6
        ui.rect(panelX, panelY, panelW, panelH, SIMD4(0.06, 0.04, 0.1, 0.88))
        ui.rect(panelX, panelY, 5 * s, panelH, SIMD4(0.95, 0.6, 0.12, 1))
        let maxChars = max(10, Int((panelW - 40 * s) / (6 * small)))
        var ny = panelY + 18 * s
        func line(_ text: String, _ c: SIMD4<Float>) {
            guard ny < panelY + panelH - 20 * s else { return }
            ui.text(text, x: panelX + 22 * s, y: ny, scale: small, color: c, shadow: false)
            ny += 11 * small
        }
        let state = updater.state
        if let release = updater.latestRelease {
            ui.text("What's new", x: panelX + 22 * s, y: ny, scale: max(1, (3 * s).rounded()), color: amber)
            ny += 16 * max(1, (3 * s).rounded()) / 2 + 12 * s
            line("\(release.title)\(release.published.isEmpty ? "" : " - \(release.published)")", SIMD4(1, 1, 1, 1))
            ny += 4 * s
            for raw in release.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = raw.trimmingCharacters(in: .whitespaces)
                if text.isEmpty { ny += 5 * s; continue }
                if text.hasPrefix("Co-Authored-By") || text.hasPrefix("Claude-Session") { continue }
                for part in WinMenus.wrap(text.replacingOccurrences(of: "**", with: ""), width: maxChars) { line(part, muted) }
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
            click(); message = nil; page = .title
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
        if ui.button("Settings", x: bx, y: y, w: bw, h: bh, scale: s, input: input) { click(); settingsReturn = .launcher; page = .settings }
        y += bh + gap
        if ui.button("Quit", x: bx, y: y, w: bw, h: bh, scale: s, input: input) || input.escape { return .quit }

        ui.text("DinoCraft for Windows - \(BuildInfo.current.displayName)", x: 16 * s, y: H - 14 * s - 7 * small, scale: small, color: muted)
        if quitForUpdate { return .quit }
        return nil
    }

    /// Choose a hat, outfit colours and something to wear on your back, with a spinning preview.
    fileprivate func buildCosmetics(_ ui: inout UIBuilder, input: MenuInput, width W: Float, height H: Float, scale s: Float, now: Double) {
        let small = max(1, (2 * s).rounded())
        ui.rect(0, 0, W, H, SIMD4(0.02, 0.01, 0.05, 0.35))
        let head = max(1, (4 * s).rounded())
        ui.centeredText("Cosmetics", centerX: W / 2, y: H * 0.06, scale: head, color: amber)
        ui.centeredText("Friends see your look in multiplayer, on Mac and Windows.", centerX: W / 2, y: H * 0.06 + 10 * head,
                        scale: small, color: muted)

        var look = PlayerLook(encoded: store.settings.cosmetics) ?? PlayerLook.defaultLook(for: store.settings.username)
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
            ui.rect(x, y, colW, rowH, SIMD4(0.08, 0.06, 0.12, 0.88))
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
            look = PlayerLook.defaultLook(for: store.settings.username)
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
