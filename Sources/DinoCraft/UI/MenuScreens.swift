import Foundation
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Base class for full-screen menus and overlays managed by the engine's screen stack.
class Screen {
    var age: Double = 0
    /// What Discord (and other observers) should consider the player to be doing.
    var scene: GameActivityState.Scene { .mainMenu }
    /// Overlays draw on top of the screen beneath them (e.g. confirmation dialogs).
    var isOverlay: Bool { false }
    func draw(_ ui: UIContext, _ engine: GameEngine) {}
    func back(_ engine: GameEngine) {
        engine.audio.play("ui_back", volume: 0.6)
        engine.popScreen()
    }

    /// Eased 0→1 entrance progress after `delay` seconds.
    func appear(_ delay: Double, duration: Double = 0.45) -> Float {
        let t = Float(max(0, min(1, (age - delay) / duration)))
        return 1 - pow(1 - t, 3)
    }
}

/// Cinematic overlay for menus drawn over the live panorama world.
enum MenuBackdrop {
    static func draw(_ ui: UIContext, strength: Float = 1) {
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        d.fill(Rect(0, 0, W, H * 0.45), Color(hex: 0x1E1208, alpha: 0.55 * strength), bottom: Color(hex: 0x1E1208, alpha: 0.05 * strength))
        d.fill(Rect(0, H * 0.45, W, H * 0.55), Color(hex: 0x1E1208, alpha: 0.1 * strength), bottom: Color(hex: 0x140A04, alpha: 0.8 * strength))
        // Floating spores and embers
        for i in 0..<46 {
            let h1 = Float(Hashing.unit(99, Int32(i), 1, 0)), h2 = Float(Hashing.unit(99, Int32(i), 2, 0))
            let h3 = Float(Hashing.unit(99, Int32(i), 3, 0))
            let t = Float(ui.time)
            let x = (h1 + t * (0.004 + h3 * 0.01)).truncatingRemainder(dividingBy: 1) * W + sin(t * 0.7 + h2 * 20) * 18
            let y = H - (h2 + t * (0.01 + h3 * 0.025)).truncatingRemainder(dividingBy: 1) * H * 1.1
            let flicker = 0.4 + 0.6 * (0.5 + 0.5 * sin(t * (1.5 + h3 * 3) + h1 * 30))
            let color = (i % 3 == 0 ? Theme.teal : Theme.amber).alpha(0.55 * flicker * strength)
            let r = 1.2 + h3 * 2.6
            d.circle(center: SIMD2(x, y), radius: r * 2.6, color.alpha(color.a * 0.18))
            d.circle(center: SIMD2(x, y), radius: r, color)
        }
    }
}

// MARK: - Main menu

final class MainMenuScreen: Screen {
    override var scene: GameActivityState.Scene { .mainMenu }
    override func back(_ engine: GameEngine) {}

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let intro = appear(0, duration: 0.8)
        let bob = Float(sin(ui.time * 1.1)) * 3
        let top = max(40, H * 0.1)

        d.opacity = intro
        if let icon = e.iconTexture {
            let s: Float = 118
            let r = Rect(W / 2 - s / 2, top - (1 - intro) * 20 + bob * 0.5, s, s)
            d.fill(r.inset(10), Theme.amber.alpha(0.25), radius: 30, blur: 24)
            d.image(icon, r)
        }
        let titleY = top + 110 + bob
        d.outlinedText(Brand.title, x: W / 2, y: titleY, size: Brand.title.count > 9 ? 84 : 96, fill: Color(hex: Brand.top), fillBottom: Color(hex: Brand.bottom),
                       outline: Color(hex: 0x3A2414), outlineWidth: 7, tracking: 0.005)
        d.text("A  PREHISTORIC  VOXEL  ADVENTURE", x: W / 2, y: titleY + 112, size: 14, color: Theme.text.alpha(0.88), face: .display,
               align: .center, tracking: 0.18, shadow: Color(linear: 0, 0, 0, 0.7))
        d.opacity = 1

        let bw: Float = 380, bh: Float = 56, gap: Float = 14
        var y = min(titleY + 164, H - (bh + gap) * 5 - 50)
        let items: [(String, String, ButtonStyle, Bool, String?)] = [
            ("menu.sp", "Singleplayer", .primary, true, nil),
            ("menu.mp", "Multiplayer", .secondary, true, nil),
            ("menu.settings", "Settings", .secondary, true, nil),
            ("menu.credits", "Credits", .secondary, true, nil),
            ("menu.quit", "Quit Game", .secondary, true, nil),
        ]
        for (i, item) in items.enumerated() {
            let a = appear(0.25 + Double(i) * 0.07)
            d.opacity = a
            let r = Rect(W / 2 - bw / 2, y + (1 - a) * 26, bw, bh)
            if ui.button(item.0, item.1, r, style: item.2, enabled: item.3, badge: item.4) {
                switch item.0 {
                case "menu.sp": e.pushScreen(WorldSelectScreen())
                case "menu.mp": e.pushScreen(MultiplayerScreen())
                case "menu.settings": e.pushScreen(SettingsScreen())
                case "menu.credits": e.pushScreen(CreditsScreen())
                case "menu.quit": e.quitGame()
                default: break
                }
            }
            y += bh + gap
        }
        d.opacity = appear(0.8)
        d.text("DinoCraft \(e.versionString)", x: 22, y: H - 34, size: 13, color: Theme.textMuted, shadow: Color(linear: 0, 0, 0, 0.6))
        d.text("Native Apple Silicon · Metal", x: W - 22, y: H - 34, size: 13, color: Theme.textMuted, align: .right,
               shadow: Color(linear: 0, 0, 0, 0.6))
        let profile = e.settings.username.isEmpty ? "Choose a name" : e.settings.username
        let chipW = d.font.measure(profile, size: 15, face: .display) + 56
        if ui.button("menu.profile", profile, Rect(W - chipW - 22, 22, chipW, 42), style: .secondary, fontSize: 15) {
            e.pushScreen(UsernameScreen(current: e.settings.username, firstRun: false))
        }
        d.opacity = 1
    }
}

// MARK: - World selection

final class WorldSelectScreen: Screen {
    private var worlds: [WorldMetadata] = []
    private var selected: String?
    private var needsReload = true
    private let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    override var scene: GameActivityState.Scene { .worldSelection }

    func reload(_ e: GameEngine) {
        worlds = e.storage.listWorlds()
        if selected == nil || !worlds.contains(where: { $0.id == selected }) { selected = worlds.first?.id }
        needsReload = false
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        if needsReload { reload(e) }
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let a = appear(0)
        let pw = min(820, W - 80), ph = min(640, H - 70)
        let panel = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 30, pw, ph)
        d.opacity = a
        ui.panel(panel, title: "Singleplayer")

        let list = Rect(panel.x + 30, panel.y + 84, panel.w - 60, panel.h - 84 - 100)
        if worlds.isEmpty {
            let cy = list.midY - 40
            let bob = Float(sin(ui.time * 2)) * 4
            d.fill(Rect(W / 2 - 60, cy - 60 + bob, 120, 120), Theme.jungle.alpha(0.18), radius: 60, blur: 30)
            d.blockIcon(Blocks.grass, Rect(W / 2 - 46, cy - 46 + bob, 92, 92))
            d.text("No worlds yet", x: W / 2, y: cy + 62, size: 26, color: Theme.text, face: .display, align: .center)
            d.text("Every great adventure starts with a single block.", x: W / 2, y: cy + 98, size: 16, color: Theme.textMuted, align: .center)
            if ui.button("worlds.createEmpty", "Create Your First World", Rect(W / 2 - 150, cy + 136, 300, 52)) {
                e.pushScreen(CreateWorldScreen())
            }
        } else {
            let rowH: Float = 84, gap: Float = 10
            let content = Float(worlds.count) * (rowH + gap)
            let offset = ui.beginScroll("worlds.list", list, contentHeight: content)
            for (i, w) in worlds.enumerated() {
                let r = Rect(list.x, list.y + Float(i) * (rowH + gap) - offset, list.w - 12, rowH)
                guard r.maxY > list.y - rowH, r.y < list.maxY + rowH else { continue }
                let (clicked, double) = ui.row("world.\(w.id)", r, selected: selected == w.id)
                if clicked { selected = w.id }
                if double { e.loadWorld(w) }
                d.fill(Rect(r.x + 14, r.y + 14, 56, 56), Color(hex: 0x24150A, alpha: 0.6), radius: 12)
                d.blockIcon(w.gameMode == .creative ? Blocks.amberLantern : Blocks.grass, Rect(r.x + 18, r.y + 18, 48, 48))
                d.text(w.name, x: r.x + 86, y: r.y + 16, size: 21, color: Theme.text, face: .display, maxWidth: r.w - 280)
                let when = relative.localizedString(for: w.lastPlayed, relativeTo: Date())
                let modeLabel = w.isHardcore ? ((w.hardcoreDead ?? false) ? "Hardcore · Game Over" : "Hardcore") : w.gameMode.displayName
                let sub = "\(modeLabel) · \(w.difficulty.displayName) · Played \(when)"
                d.text(sub, x: r.x + 86, y: r.y + 48, size: 14, color: Theme.textMuted, maxWidth: r.w - 280)
                let hours = Int(w.playTimeSeconds) / 3600, mins = (Int(w.playTimeSeconds) % 3600) / 60
                d.text(hours > 0 ? "\(hours)h \(mins)m" : "\(max(mins, 0))m", x: r.maxX - 20, y: r.y + 18, size: 15,
                       color: Theme.amber, face: .display, align: .right)
                d.text("Seed \(w.seedText)", x: r.maxX - 20, y: r.y + 48, size: 12.5, color: Theme.textMuted.alpha(0.7),
                       align: .right, maxWidth: 190)
            }
            ui.endScroll("worlds.list", list, contentHeight: content)
        }

        let by = panel.maxY - 78
        let bw = (panel.w - 60 - 36) / 4
        let current = worlds.first { $0.id == selected }
        if ui.button("worlds.create", "Create New World", Rect(panel.x + 30, by, bw + 20, 52), style: .secondary, fontSize: 17) {
            e.pushScreen(CreateWorldScreen())
        }
        if ui.button("worlds.play", "Play", Rect(panel.x + 30 + (bw + 12) + 20, by, bw - 8, 52), enabled: current != nil), let w = current {
            e.loadWorld(w)
        }
        if ui.button("worlds.delete", "Delete", Rect(panel.x + 30 + (bw + 12) * 2 + 12, by, bw - 12, 52), style: .danger,
                     enabled: current != nil, fontSize: 17), let w = current {
            e.pushScreen(ConfirmScreen(title: "Delete “\(w.name)”?",
                                       message: "This world will be moved to the Trash.",
                                       confirmLabel: "Delete World") { [weak self] engine in
                do {
                    try engine.storage.deleteWorld(id: w.id)
                    self?.needsReload = true
                } catch {
                    Log.error("Delete failed: \(error)", category: "UI")
                    engine.showToast("Could not delete the world")
                }
            })
        }
        if ui.button("worlds.back", "Back", Rect(panel.maxX - 30 - bw, by, bw, 52), style: .ghost, fontSize: 17) {
            back(e)
        }
        d.opacity = 1

        if ui.input.keyPressed(KeyCode.returnKey), let w = current { e.loadWorld(w) }
    }

    override func back(_ engine: GameEngine) {
        super.back(engine)
    }

    func markNeedsReload() { needsReload = true }
}

// MARK: - World creation

final class CreateWorldScreen: Screen {
    private var name = "Dino World"
    private var seed = ""
    private var mode = 0
    private var difficulty = 2
    private var bonusChest = false
    private var commands = true
    private var error: String?

    override var scene: GameActivityState.Scene { .worldCreation }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        if age == 0 { ui.focusedID = "create.name" }
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let a = appear(0)
        let pw = min(700, W - 80), ph = min(710, H - 40)
        let p = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 30, pw, ph)
        d.opacity = a
        ui.panel(p, title: "Create New World")

        let x = p.x + 44, w = p.w - 88
        var y = p.y + 88
        func label(_ s: String) {
            d.text(s.uppercased(), x: x, y: y, size: 12.5, color: Theme.amber, face: .display, tracking: 0.12)
            y += 24
        }
        label("World Name")
        if ui.textField("create.name", Rect(x, y, w, 50), &name, placeholder: "Name your world", maxLength: 32) { create(e) }
        y += 68
        label("Seed")
        ui.textField("create.seed", Rect(x, y, w, 50), &seed, placeholder: "Leave blank for a random world", maxLength: 40)
        y += 58
        d.text("The same seed always generates the same world.", x: x, y: y, size: 13, color: Theme.textMuted)
        y += 34
        label("Game Mode")
        ui.segmented("create.mode", Rect(x, y, w, 46), options: ["Survival", "Hardcore", "Creative"], selected: &mode)
        y += 56
        let modeInfo = [
            "Gather resources, craft tools, manage health and hunger.",
            "One life on Hard. If you fall, the world is lost forever.",
            "Unlimited blocks, instant breaking and flight (double-tap jump).",
        ][mode]
        d.text(modeInfo, x: x, y: y, size: 13.5, color: Theme.textMuted)
        y += 36
        label("Difficulty")
        if mode == 1 {
            var locked = 3
            ui.segmented("create.difficulty.locked", Rect(x, y, w, 46), options: Difficulty.allCases.map { $0.displayName }, selected: &locked)
        } else {
            ui.segmented("create.difficulty", Rect(x, y, w, 46), options: Difficulty.allCases.map { $0.displayName }, selected: &difficulty)
        }
        y += 60
        if mode != 2 {
            _ = ui.toggle("create.bonus", "Bonus Chest (starter supplies next to spawn)", Rect(x, y, w, 44), &bonusChest)
            y += 50
        }
        if mode != 1 {
            _ = ui.toggle("create.commands", "Allow Commands (/give, /time, /tp and more)", Rect(x, y, w, 44), &commands)
        }

        if let error {
            d.text(error, x: p.midX, y: p.maxY - 118, size: 14, color: Theme.danger, align: .center)
        }
        let valid = !name.trimmingCharacters(in: .whitespaces).isEmpty
        let bw = (w - 16) / 2
        if ui.button("create.go", "Create World", Rect(x, p.maxY - 84, bw, 54), enabled: valid) { create(e) }
        if ui.button("create.cancel", "Cancel", Rect(x + bw + 16, p.maxY - 84, bw, 54), style: .secondary) { back(e) }
        d.opacity = 1
    }

    private func create(_ e: GameEngine) {
        do {
            var meta = try e.storage.createWorld(name: name, seedText: seed, gameMode: mode == 2 ? .creative : .survival,
                                                 difficulty: Difficulty.allCases[difficulty], hardcore: mode == 1)
            if (bonusChest && mode != 2) || (!commands && mode != 1) {
                if bonusChest && mode != 2 { meta.bonusChest = true }
                if !commands && mode != 1 { meta.allowCommands = false }
                try e.storage.saveMetadata(meta)
            }
            e.startSession(meta: meta, isNew: true)
        } catch {
            self.error = String(describing: error)
            Log.error("World creation failed: \(error)", category: "UI")
        }
    }
}

// MARK: - Confirmation dialog

final class ConfirmScreen: Screen {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: (GameEngine) -> Void

    init(title: String, message: String, confirmLabel: String, onConfirm: @escaping (GameEngine) -> Void) {
        self.title = title; self.message = message; self.confirmLabel = confirmLabel; self.onConfirm = onConfirm
    }

    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .worldSelection }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        let a = appear(0, duration: 0.25)
        ui.dim(0.6 * a)
        let d = ui.draw
        d.opacity = a
        let W = ui.size.x, H = ui.size.y
        let p = Rect(W / 2 - 230, H / 2 - 120 + (1 - a) * 16, 460, 240)
        ui.panel(p)
        d.text(title, in: Rect(p.x + 20, p.y + 26, p.w - 40, 40), size: 24, color: Theme.text, face: .display)
        d.text(message, in: Rect(p.x + 20, p.y + 76, p.w - 40, 30), size: 15, color: Theme.textMuted)
        let bw = (p.w - 72) / 2
        if ui.button("modal.confirm", confirmLabel, Rect(p.x + 28, p.maxY - 80, bw, 52), style: .danger, fontSize: 17) {
            e.popScreen()
            onConfirm(e)
        }
        if ui.button("modal.cancel", "Cancel", Rect(p.x + 44 + bw, p.maxY - 80, bw, 52), style: .secondary, fontSize: 17) {
            back(e)
        }
        d.opacity = 1
    }
}
