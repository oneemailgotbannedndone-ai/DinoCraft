import Foundation
import simd
import DinoCraftCore
@testable import DinoCraftGame

// MARK: - Pause

final class PauseScreen: Screen {
    override var scene: GameActivityState.Scene { .playing }

    override func back(_ engine: GameEngine) { engine.resumeGame() }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        let a = appear(0, duration: 0.3)
        ui.dim(0.6 * a)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        d.opacity = a
        d.outlinedText("Paused", x: W / 2, y: H * 0.2 - (1 - a) * 12, size: 64, fill: Color(hex: 0xFFE69A), fillBottom: Color(hex: 0xF08A2E),
                       outline: Color(hex: 0x3A2414), outlineWidth: 5)
        if let s = e.session {
            d.text("\(s.meta.name)  ·  \(s.modeName)  ·  \(s.dimension == .overworld ? SkyModel.periodName(worldTime: s.worldTime) : s.dimension.displayName)",
                   x: W / 2, y: H * 0.2 + 84, size: 16, color: Theme.text.alpha(0.85), align: .center, shadow: Color(linear: 0, 0, 0, 0.6))
        }
        let bw: Float = 380, bh: Float = 56
        var y = H * 0.2 + 140
        var entries: [(String, String, ButtonStyle)] = [
            ("pause.resume", "Resume", .primary),
            ("pause.settings", "Settings", .secondary),
            ("pause.advancements", "Advancements", .secondary),
        ]
        if let s = e.session, !s.meta.isHardcore {
            entries.append(("pause.commands", "Commands: \(s.meta.commandsAllowed ? "On" : "Off")", .secondary))
        }
        entries.append(("pause.quit", "Save & Quit to Title", .secondary))
        for (i, entry) in entries.enumerated() {
            let t = appear(0.05 + Double(i) * 0.05, duration: 0.3)
            d.opacity = t
            if ui.button(entry.0, entry.1, Rect(W / 2 - bw / 2, y + (1 - t) * 16, bw, bh), style: entry.2) {
                switch entry.0 {
                case "pause.resume": e.resumeGame()
                case "pause.settings": e.pushScreen(SettingsScreen())
                case "pause.advancements": e.pushScreen(AdvancementsScreen())
                case "pause.commands":
                    if let s = e.session {
                        s.setCommandsAllowed(!s.meta.commandsAllowed)
                        e.showToast(s.meta.commandsAllowed ? "Commands turned on" : "Commands turned off")
                    }
                default: e.saveAndQuitToTitle()
                }
            }
            y += bh + 14
        }
        d.opacity = 1
    }
}

// MARK: - Death

final class DeathScreen: Screen {
    override var scene: GameActivityState.Scene { .playing }
    override func back(_ engine: GameEngine) {}

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        let a = appear(0.2, duration: 1.0)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        d.fill(Rect(0, 0, W, H), Color(hex: 0x5A0A12, alpha: 0.55 * a), bottom: Color(hex: 0x1A0206, alpha: 0.8 * a))
        d.opacity = a
        let hardcore = e.session?.meta.isHardcore ?? false
        d.outlinedText(hardcore ? "Game Over" : "You Perished", x: W / 2, y: H * 0.26, size: 72, fill: Color(hex: 0xFF8A80), fillBottom: Color(hex: 0xC62828),
                       outline: Color(hex: 0x1A0206), outlineWidth: 6)
        if hardcore {
            d.text("HARDCORE — THIS WORLD IS LOST", x: W / 2, y: H * 0.26 - 34, size: 14, color: Theme.danger, face: .display, align: .center, tracking: 0.18)
        }
        if let s = e.session {
            d.text(s.deathMessage, x: W / 2, y: H * 0.26 + 96, size: 18, color: Theme.text, align: .center, shadow: Color(linear: 0, 0, 0, 0.7))
        }
        let t = appear(1.0, duration: 0.4)
        d.opacity = t
        if ui.button("death.respawn", hardcore ? "Spectate World" : "Respawn", Rect(W / 2 - 190, H * 0.26 + 160, 380, 56)) { e.respawnPlayer() }
        if ui.button("death.title", "Save & Quit to Title", Rect(W / 2 - 190, H * 0.26 + 230, 380, 56), style: .secondary) {
            e.saveAndQuitToTitle()
        }
        d.opacity = 1
    }
}

// MARK: - Credits

final class CreditsScreen: Screen {
    override var scene: GameActivityState.Scene { .credits }

    private let lines: [(String, Float, Bool)] = GameCredits.lines(technology: [
        "Native AppKit · Metal · AVAudioEngine", "Tuned for Apple Silicon",
    ]).map { line -> (String, Float, Bool) in
        switch line.style {
        case .title: return (line.text, 44, true)
        case .heading: return (line.text, 14, true)
        case .line: return (line.text, 18, false)
        case .spacer: return ("", 16, false)
        case .thanks: return (line.text, 22, true)
        }
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        ui.dim(0.35)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let a = appear(0)
        d.opacity = a
        var total: Float = 0
        for l in lines { total += l.1 * 1.9 }
        let scroll = Float(age) * 34
        let startY = H * 0.85 - scroll.truncatingRemainder(dividingBy: total + H * 0.9)
        var y = startY
        d.pushClip(Rect(0, 60, W, H - 150))
        for (text, size, strong) in lines {
            if !text.isEmpty {
                if size > 40 {
                    d.outlinedText(text, x: W / 2, y: y, size: size, fill: Color(hex: 0xFFE69A), fillBottom: Color(hex: 0xF08A2E),
                                   outline: Color(hex: 0x3A2414), outlineWidth: 4)
                } else {
                    d.text(text, x: W / 2, y: y, size: size, color: strong ? Theme.amber : Theme.text, face: strong ? .display : .body,
                           align: .center, tracking: strong ? 0.12 : 0, shadow: Color(linear: 0, 0, 0, 0.7))
                }
            }
            y += size * 1.9
        }
        d.popClip()
        if ui.button("credits.back", "Back", Rect(W / 2 - 120, H - 80, 240, 52), style: .secondary) { back(e) }
        d.opacity = 1
    }
}

// MARK: - Settings

final class SettingsScreen: Screen {
    private var tab = 0
    private var listening: GameAction?

    override var scene: GameActivityState.Scene { .settings }

    override func back(_ engine: GameEngine) {
        if listening != nil {
            listening = nil
            engine.input.captureNextBinding = nil
            return
        }
        super.back(engine)
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        if e.session != nil { ui.dim(0.65) } else { MenuBackdrop.draw(ui) }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let a = appear(0)
        let pw = min(860, W - 60), ph = min(700, H - 50)
        let p = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 24, pw, ph)
        d.opacity = a
        ui.panel(p, title: "Settings")

        let previousTab = tab
        ui.segmented("settings.tab", Rect(p.x + 40, p.y + 80, p.w - 80, 46), options: ["Graphics", "Audio", "Touch", "Packs"], selected: &tab)
        if tab != previousTab && tab == 3 { e.refreshTexturePacks() }
        let area = Rect(p.x + 40, p.y + 144, p.w - 80, p.h - 144 - 96)
        var s = e.settings
        let rowH: Float = 58, gap: Float = 10
        var rows: Float = 0
        let contentHeight: Float
        switch tab {
        case 0: contentHeight = 9 * (rowH + gap)
        case 1: contentHeight = 4 * (rowH + gap)
        case 2: contentHeight = 4 * (rowH + gap)
        default: contentHeight = Float(e.texturePacks.count + 6) * (rowH + gap)
        }
        let offset = ui.beginScroll("settings.scroll.\(tab)", area, contentHeight: contentHeight)
        func next() -> Rect {
            let r = Rect(area.x, area.y + rows * (rowH + gap) - offset, area.w - 14, rowH)
            rows += 1
            return r
        }

        switch tab {
        case 0:
            var rd = Double(s.renderDistance)
            if ui.slider("set.rd", "Render Distance", next(), &rd, range: 3...16, step: 1,
                         format: { "\(Int($0)) chunks\($0 > 10 ? " · may get warm" : "")" }) { s.renderDistance = Int(rd) }
            ui.slider("set.fov", "Field of View", next(), &s.fov, range: 50...110, step: 1, format: { "\(Int($0))°" })
            ui.slider("set.brightness", "Brightness", next(), &s.brightness, range: 0...1, step: 0.01, format: { $0 < 0.05 ? "Moody" : ($0 > 0.95 ? "Bright" : "\(Int($0 * 100))%") })
            var q = GraphicsQuality.allCases.firstIndex(of: s.graphicsQuality) ?? 2
            let qr = next()
            d.text("Graphics Quality", in: Rect(qr.x + 16, qr.y, 200, qr.h), size: 16, color: Theme.text, align: .left)
            if ui.segmented("set.quality", Rect(qr.maxX - 360, qr.y + 7, 344, qr.h - 14), options: GraphicsQuality.allCases.map { $0.displayName }, selected: &q) {
                s.graphicsQuality = GraphicsQuality.allCases[q]
            }
            ui.toggle("set.bob", "View Bobbing", next(), &s.viewBobbing)
            ui.toggle("set.clouds", "Clouds", next(), &s.clouds)
            ui.toggle("set.fps", "Show FPS Counter", next(), &s.showFPS)
            let mr = next()
            d.text("Map", in: Rect(mr.x + 16, mr.y, 200, mr.h), size: 16, color: Theme.text, align: .left)
            var mapMode = max(0, min(2, s.minimapMode))
            if ui.segmented("set.map", Rect(mr.maxX - 360, mr.y + 7, 344, mr.h - 14), options: ["Hidden", "Corner", "Big"], selected: &mapMode) {
                s.minimapMode = mapMode
            }
            ui.slider("set.gui", "Interface Scale", next(), &s.guiScale, range: 0.75...1.5, step: 0.05, format: { "\(Int($0 * 100))%" })
        case 1:
            ui.slider("set.master", "Master Volume", next(), &s.masterVolume, range: 0...1, step: 0.01, format: { "\(Int($0 * 100))%" })
            ui.slider("set.music", "Music", next(), &s.musicVolume, range: 0...1, step: 0.01, format: { "\(Int($0 * 100))%" })
            ui.slider("set.sound", "Sound Effects", next(), &s.soundVolume, range: 0...1, step: 0.01, format: { "\(Int($0 * 100))%" })
            ui.slider("set.ambient", "Ambience", next(), &s.ambientVolume, range: 0...1, step: 0.01, format: { "\(Int($0 * 100))%" })
        case 2:
            ui.slider("set.sens", "Look Sensitivity", next(), &s.mouseSensitivity, range: 0...1, step: 0.01, format: { "\(Int($0 * 200))%" })
            ui.toggle("set.invert", "Invert Look", next(), &s.invertY)
            let hr = next()
            d.text("Left thumb: move (push all the way to sprint). Right thumb: drag to look, tap to use or hit, hold to break.",
                   in: Rect(hr.x + 16, hr.y, hr.w - 32, hr.h), size: 13.5, color: Theme.textMuted, align: .left)
            let hr2 = next()
            d.text("In menus: tap to click, hold for a right-click, and use Shift for quick moves.",
                   in: Rect(hr2.x + 16, hr2.y, hr2.w - 32, hr2.h), size: 13.5, color: Theme.textMuted, align: .left)
        default:
            let th = next()
            d.text("TEXTURE PACKS", x: th.x + 4, y: th.y + 32, size: 12.5, color: Theme.amber, face: .display, tracking: 0.12)
            for pack in e.texturePacks {
                let r = next()
                let active = s.texturePack == pack.id
                let hover = ui.hoverSilent("pack.\(pack.id)", r)
                d.fill(r, Color(linear: 1, 1, 1, active ? 0.09 : (hover ? 0.06 : 0.025)), radius: 12)
                if active { d.stroke(r, Theme.amber.alpha(0.75), radius: 12, width: 1.5) }
                d.text(pack.name, x: r.x + 16, y: r.y + 8, size: 16, color: Theme.text, face: .display)
                d.text(pack.description, x: r.x + 16, y: r.y + 32, size: 13, color: Theme.textMuted, maxWidth: r.w - 150)
                d.text(active ? "Active" : (pack.isUser ? "Your pack" : "Built-in"), in: Rect(r.maxX - 130, r.y, 114, r.h), size: 13.5,
                       color: active ? Theme.jungle : Theme.textMuted, face: .display, align: .right)
                if hover && ui.input.buttonsPressed.contains(0) && !active {
                    s.texturePack = pack.id
                    e.audio.play("ui_click", volume: 0.5)
                }
            }
            let sh = next()
            d.text("SHADER PACKS", x: sh.x + 4, y: sh.y + 32, size: 12.5, color: Theme.amber, face: .display, tracking: 0.12)
            let sr = next()
            let current = ShaderPack(rawValue: s.shaderPack) ?? .off
            var shaderIndex = ShaderPack.allCases.firstIndex(of: current) ?? 0
            if ui.segmented("set.shader", Rect(sr.x, sr.y + 6, sr.w, sr.h - 12), options: ShaderPack.allCases.map { $0.displayName }, selected: &shaderIndex) {
                s.shaderPack = ShaderPack.allCases[shaderIndex].rawValue
            }
            let dr = next()
            d.text(current.detail, in: Rect(dr.x + 16, dr.y, dr.w - 32, dr.h), size: 14, color: Theme.textMuted, align: .left)
            ui.slider("set.shaderStrength", "Shader Strength", next(), &s.shaderStrength, range: 0...1, step: 0.05, format: { "\(Int($0 * 100))%" })
        }
        ui.endScroll("settings.scroll.\(tab)", area, contentHeight: contentHeight)

        if s != e.settings { e.updateSettings(s) }
        if ui.button("settings.done", "Done", Rect(p.midX - 130, p.maxY - 78, 260, 52)) { back(e) }
        d.opacity = 1
    }
}

// MARK: - Loading

enum LoadingView {
    static let tips = [
        "Sneak to stay safely on ledges.",
        "Fossil Stone hides Dino Bones deep in the mountains.",
        "Amber glows faintly — look for it in caves.",
        "Ginkgo leaves sometimes drop Cycad Berries.",
        "Double-tap jump to fly in Creative mode.",
        "Torches keep the deep strata bright.",
        "Iron ore can be field-smelted with coal on a crafting grid.",
        "Rivers carve valleys through even the tallest peaks.",
    ]

    static func draw(_ ui: UIContext, session: GameSession) {
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        // Each dimension has its own loading backdrop
        switch session.dimension {
        case .underworld: d.fill(Rect(0, 0, W, H), Color(hex: 0x3A0E0A), bottom: Color(hex: 0x120404))
        case .skylands: d.fill(Rect(0, 0, W, H), Color(hex: 0x6A5A9A), bottom: Color(hex: 0xE8A04A))
        case .toonland: d.fill(Rect(0, 0, W, H), Color(hex: 0x6A8AC8), bottom: Color(hex: 0xE8B25A))
        default: d.fill(Rect(0, 0, W, H), Color(hex: 0x2A1A0C), bottom: Color(hex: 0x140A04))
        }
        // Drifting voxel silhouettes
        for i in 0..<18 {
            let h1 = Float(Hashing.unit(7, Int32(i), 0, 0)), h2 = Float(Hashing.unit(7, Int32(i), 1, 0))
            let size = 20 + h2 * 60
            let x = (h1 * W + Float(ui.time) * (8 + h2 * 20)).truncatingRemainder(dividingBy: W + 120) - 60
            let y = H * (0.55 + h2 * 0.4)
            d.fill(Rect(x, y, size, size), Theme.amber.alpha(0.03 + h1 * 0.04), radius: 4)
        }
        MenuBackdrop.draw(ui, strength: 0.6)
        let bob = Float(sin(ui.time * 1.5)) * 4
        d.outlinedText(Brand.title, x: W / 2, y: H * 0.26 + bob, size: 80, fill: Color(hex: Brand.top), fillBottom: Color(hex: Brand.bottom),
                       outline: Color(hex: 0x3A2414), outlineWidth: 6)
        let title = session.loadingTitle
        d.text(title, x: W / 2, y: H * 0.26 + 110, size: 24, color: Theme.text, face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.6))
        d.text(session.meta.name, x: W / 2, y: H * 0.26 + 146, size: 16, color: Theme.textMuted, align: .center)

        let bar = Rect(W / 2 - 240, H * 0.26 + 196, 480, 14)
        let progress = ui.anim("loading.progress", session.loadingProgress, speed: 6)
        d.fill(bar, Color(hex: 0x24150A, alpha: 0.9), radius: 7)
        d.stroke(bar, Theme.amber.alpha(0.3), radius: 7, width: 1)
        let fill = Rect(bar.x + 2, bar.y + 2, max(10, (bar.w - 4) * progress), bar.h - 4)
        d.fill(fill, Theme.amberDeep, radius: 5, bottom: Theme.amber)
        let shimmerX = fill.x + (Float(ui.time * 0.6).truncatingRemainder(dividingBy: 1)) * fill.w
        d.fill(Rect(shimmerX - 20, fill.y, 40, fill.h), Color(linear: 1, 1, 1, 0.25), radius: 5, blur: 6)
        d.text("\(Int(progress * 100))%  ·  \(session.loadingDetail)", x: W / 2, y: bar.maxY + 14, size: 14, color: Theme.textMuted, align: .center)

        if let goal = GameGuide.current(session.advancements), !session.isRemote {
            d.text("NEXT GOAL: \(goal.step.title.uppercased())", x: W / 2, y: H - 150, size: 13, color: Theme.jungle, face: .display, align: .center, tracking: 0.1)
        }
        let allTips = tips + GameGuide.tips
        let tip = allTips[Int(ui.time / 5) % allTips.count]
        d.text("TIP", x: W / 2, y: H - 110, size: 12, color: Theme.amber, face: .display, align: .center, tracking: 0.2)
        d.text(tip, x: W / 2, y: H - 88, size: 16, color: Theme.text.alpha(0.85), align: .center)
    }
}

// MARK: - HUD

enum HUD {
    /// The minimap in the top-right corner (M makes it big or hides it). Returns the y just below it.
    static func minimap(_ ui: UIContext, session s: GameSession, engine e: GameEngine) -> Float {
        let mode = e.settings.minimapMode
        guard mode > 0, !e.showDebug else { return 0 }
        let d = ui.draw
        let W = ui.size.x
        let map = s.minimap
        map.refresh(s)
        let view = mode == 1 ? 32 : Minimap.radius
        let cells = 2 * view + 1
        let size: Float = mode == 1 ? 176 : 300
        let cell = size / Float(cells)
        let box = Rect(W - size - 18, 18, size, size)
        d.shadow(box.inset(-6), radius: 10, blur: 10, color: Color(linear: 0, 0, 0, 0.45), offset: 3)
        d.fill(box.inset(-6), Color(hex: 0x5A3A1C), radius: 8)
        d.fill(box.inset(-2), Color(hex: 0x2A1A0C), radius: 3)
        d.fill(box, Color(hex: 0x050505))
        let n = Minimap.size, offset = Minimap.radius - view
        // Terrain, merging runs of the same colour along each row.
        for j in 0..<cells {
            let row = (offset + j) * n + offset
            var i = 0
            while i < cells {
                let color = map.cells[row + i]
                var run = 1
                while i + run < cells && map.cells[row + i + run] == color { run += 1 }
                if color != 0 {
                    d.fill(Rect(box.x + Float(i) * cell, box.y + Float(j) * cell, Float(run) * cell + 0.4, cell + 0.4), Color(hex: color))
                }
                i += run
            }
        }
        let cx = box.x + size / 2, cy = box.y + size / 2
        for m in map.markers(for: s, radius: view) {
            let mx = cx + m.dx * cell, my = cy + m.dz * cell
            switch m.kind {
            case .you:
                // An arrow of three dots pointing the way you face.
                let look = s.player.lookDirection
                let flat = SIMD2<Float>(Float(look.x), Float(look.z))
                let dir = simd_length(flat) > 0.01 ? simd_normalize(flat) : SIMD2(0, -1)
                for k in 0..<3 {
                    let px = mx + dir.x * Float(k) * 3, py = my + dir.y * Float(k) * 3
                    let half: Float = k == 0 ? 3 : 2.2
                    d.fill(Rect(px - half - 1, py - half - 1, half * 2 + 2, half * 2 + 2), Color(linear: 0, 0, 0, 0.8), radius: half + 1)
                    d.fill(Rect(px - half, py - half, half * 2, half * 2), k == 2 ? Color(hex: 0xFF5A3C) : .white, radius: half)
                }
            case .death:
                d.text("X", x: mx, y: my - 8, size: 14, color: Color(hex: m.color), face: .display, align: .center,
                       shadow: Color(linear: 0, 0, 0, 0.9))
            case .player, .pet:
                let half: Float = m.kind == .pet ? 2.5 : 3.5
                d.fill(Rect(mx - half - 1, my - half - 1, half * 2 + 2, half * 2 + 2), Color(linear: 0, 0, 0, 0.85))
                d.fill(Rect(mx - half, my - half, half * 2, half * 2), Color(hex: m.color))
                if mode == 2 && m.kind == .player {
                    d.text(m.label, x: mx, y: m.dz > 0 ? my - 20 : my + 6, size: 11, color: .white, face: .display, align: .center,
                           shadow: Color(linear: 0, 0, 0, 0.9))
                }
            }
        }
        // North marker and your position under the map.
        d.text("N", x: cx, y: box.y + 3, size: 12, color: .white, face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.9))
        let p = s.player.position
        let coords = "\(Int(floor(p.x))), \(Int(floor(p.y)) - s.world.generator.depthOffset), \(Int(floor(p.z)))" + (map.caveMode ? "  (cave)" : "")
        d.text(coords, x: cx, y: box.maxY + 10, size: 13, color: Theme.text, face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.85))
        return box.maxY + 32
    }

    static func draw(_ ui: UIContext, session s: GameSession, engine e: GameEngine) {
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y

        if s.damageFlash > 0 {
            let a = Float(s.damageFlash) * 0.45
            d.fill(Rect(0, 0, W, H), Color(hex: 0x8A0010, alpha: a * 0.3), bottom: Color(hex: 0x8A0010, alpha: a))
        }
        if s.player.headInWater {
            d.fill(Rect(0, 0, W, H), Color(hex: 0x0A3A6A, alpha: 0.18), bottom: Color(hex: 0x05203A, alpha: 0.35))
        }

        // Crosshair
        let c = SIMD2(W / 2, H / 2)
        d.fill(Rect(c.x - 1.5, c.y - 10, 3, 20), Color(linear: 0, 0, 0, 0.45), radius: 1.5, blur: 1)
        d.fill(Rect(c.x - 10, c.y - 1.5, 20, 3), Color(linear: 0, 0, 0, 0.45), radius: 1.5, blur: 1)
        d.fill(Rect(c.x - 1, c.y - 9, 2, 18), Color(linear: 1, 1, 1, 0.92), radius: 1)
        d.fill(Rect(c.x - 9, c.y - 1, 18, 2), Color(linear: 1, 1, 1, 0.92), radius: 1)
        if s.breakProgress > 0 {
            let br = Rect(c.x - 22, c.y + 18, 44, 5)
            d.fill(br, Color(linear: 0, 0, 0, 0.5), radius: 2.5)
            d.fill(Rect(br.x, br.y, br.w * Float(min(1, s.breakProgress)), br.h), Theme.amber, radius: 2.5)
        }
        if s.bowCharge > 0 {
            let br = Rect(c.x - 22, c.y + 18, 44, 5)
            d.fill(br, Color(linear: 0, 0, 0, 0.5), radius: 2.5)
            d.fill(Rect(br.x, br.y, br.w * Float(s.bowCharge), br.h), s.bowCharge >= 1 ? Theme.jungle : Color(hex: 0xE8E2D4), radius: 2.5)
        }

        if s.portalProgress > 0 {
            let a = Float(min(1, s.portalProgress))
            let tint = s.portalKind == Blocks.skylandsPortal ? Color(hex: 0xF2B04A)
                : (s.portalKind == Blocks.toonlandPortal ? Color(hex: 0xF2B84A) : Color(hex: 0x8A1A4A))
            d.fill(Rect(0, 0, W, H), tint.alpha(a * 0.5), bottom: tint.alpha(a * 0.8))
        }
        if let boss = s.mobs.boss(near: s.player.position) {
            // Boss health bar across the top of the screen
            let frac = Float(max(0, boss.health) / boss.species.maxHealth)
            let bar = Rect(W / 2 - 260, 44, 520, 14)
            d.text(boss.species.displayName, x: W / 2, y: 14, size: 20, color: Theme.text, face: .display, align: .center,
                   shadow: Color(linear: 0, 0, 0, 0.85))
            d.fill(bar.inset(-3), Color(linear: 0, 0, 0, 0.7), radius: 5)
            d.fill(bar, Color(hex: 0x3A3A3A), radius: 4)
            d.fill(Rect(bar.x, bar.y, bar.w * frac, bar.h), boss.enraged ? Theme.danger : Color(hex: 0xF2F2F2), radius: 4)
        } else if let mob = s.targetMob {
            let frac = Float(max(0, mob.health) / mob.species.maxHealth)
            let bar = Rect(W / 2 - 110, 74, 220, 8)
            d.text(mob.label, x: W / 2, y: 48, size: 15, color: mob.species.hostile && !mob.isTamed ? Color(hex: 0xFF8A80) : Theme.text,
                   face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.8))
            d.fill(bar, Color(linear: 0, 0, 0, 0.55), radius: 4)
            d.fill(Rect(bar.x, bar.y, bar.w * frac, bar.h), mob.species.hostile ? Theme.danger : Theme.jungle, radius: 4)
        }
        if e.settings.showGuide, !e.showDebug, !s.isRemote, let goal = GameGuide.current(s.advancements) {
            // The guide to beating the game, in the top-left corner
            let box = Rect(14, 118, 420, 84)
            d.fill(box, Color(hex: 0x120A20, alpha: 0.62), radius: 10)
            d.fill(Rect(box.x, box.y + 8, 3, box.h - 16), Theme.amber, radius: 1.5)
            d.text("GUIDE \(goal.number)/\(GameGuide.steps.count)  (G)", x: box.x + 14, y: box.y + 8, size: 12, color: Theme.amber, face: .display)
            d.text(goal.step.title, x: box.x + 14, y: box.y + 30, size: 16, color: Theme.text, face: .display)
            d.text(goal.step.hint, x: box.x + 14, y: box.y + 56, size: 13, color: Theme.text.alpha(0.7))
        }
        if s.dimension == .toonland, let line = SongLyrics.line(track: e.audio.currentTrack, time: e.audio.musicTime) {
            // Sing-along lyrics
            let text = "\u{266A} \(line) \u{266A}"
            let y = H - 150
            d.fill(Rect(W / 2 - 300, y - 8, 600, 34), Color(linear: 0, 0, 0, 0.5), radius: 10)
            d.text(text, x: W / 2, y: y, size: 18, color: Theme.text, face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.85))
        }
        if e.settings.showFPS && !e.showDebug {
            d.text(String(format: "%.0f FPS", e.profiler.fps), x: 14, y: 12, size: 14, color: Theme.jungle, face: .display,
                   shadow: Color(linear: 0, 0, 0, 0.85))
        }

        e.minimapBottom = minimap(ui, session: s, engine: e)
        MultiplayerHUD.draw(ui, engine: e)

        // Hotbar
        let slot: Float = 54, gap: Float = 5
        let total = slot * 9 + gap * 8
        let hx = W / 2 - total / 2, hy = H - slot - 18
        let backing = Rect(hx - 8, hy - 8, total + 16, slot + 16)
        d.shadow(backing, radius: 16, blur: 14, color: Color(linear: 0, 0, 0, 0.45), offset: 4)
        d.fill(backing, Color(hex: 0x2A1A0C, alpha: 0.72), radius: 16)
        d.stroke(backing, Theme.amber.alpha(0.18), radius: 16, width: 1)
        let selX = ui.anim("hud.sel", Float(s.inventory.selected), speed: 22)
        for i in 0..<9 {
            let r = Rect(hx + Float(i) * (slot + gap), hy, slot, slot)
            d.fill(r, Color(hex: 0x1A0E06, alpha: 0.55), radius: 10)
            if let stack = s.inventory.slots[i], let info = e.items[stack.item] {
                d.itemIcon(info, r.inset(8))
                if stack.enchant != 0 { HUD.enchantGlint(d, r.inset(8), time: ui.time) }
                if stack.count > 1 {
                    d.text("\(stack.count)", x: r.maxX - 6, y: r.maxY - 22, size: 14, color: .white, face: .display, align: .right,
                           shadow: Color(linear: 0, 0, 0, 0.9))
                }
                if let durability = info.maxDurability, stack.damage > 0 {
                    let frac = 1 - Float(stack.damage) / Float(durability)
                    let bar = Rect(r.x + 8, r.maxY - 8, r.w - 16, 3)
                    d.fill(bar, Color(linear: 0, 0, 0, 0.7), radius: 1.5)
                    d.fill(Rect(bar.x, bar.y, bar.w * frac, 3), Color(hex: 0xE5484D).mix(Theme.jungle, frac), radius: 1.5)
                }
            }
            d.text("\(i + 1)", x: r.x + 6, y: r.y + 3, size: 10, color: Theme.textMuted.alpha(0.6))
        }
        let sel = Rect(hx + selX * (slot + gap) - 3, hy - 3, slot + 6, slot + 6)
        d.fill(sel.inset(-2), Theme.amber.alpha(0.25), radius: 13, blur: 8)
        d.stroke(sel, Theme.amber, radius: 12, width: 2.5)

        // Zoom level while holding the zoom key
        if s.zooming {
            d.text(String(format: "Zoom %.1f×  ·  scroll to adjust", s.zoomFactor), x: W / 2, y: hy - 104, size: 15, color: Theme.text.alpha(0.9),
                   face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.8))
        }

        // Selected item name
        if s.hotbarNameTimer > 0, let stack = s.inventory.selectedStack, let info = e.items[stack.item] {
            let a = Float(min(1, s.hotbarNameTimer / 0.4))
            let lift: Float = s.player.gameMode == .survival && s.armorPoints > 0 ? 24 : 0
            d.text(info.displayName, x: W / 2, y: hy - 66 - lift, size: 17, color: Theme.text.alpha(a), face: .display, align: .center,
                   shadow: Color(linear: 0, 0, 0, 0.8 * a))
        }

        // Survival stats
        if s.player.gameMode == .survival && !s.spectator {
            // Experience: a green bar just above the hotbar with your level in the middle.
            let xpBar = Rect(hx, hy - 17, total, 5)
            d.fill(xpBar, Color(hex: 0x0E0A04, alpha: 0.75), radius: 2.5)
            d.fill(Rect(xpBar.x, xpBar.y, xpBar.w * Float(s.xpProgress), xpBar.h), Color(hex: 0x7CF03A), radius: 2.5)
            if s.xpLevel > 0 {
                d.text("\(s.xpLevel)", x: W / 2, y: hy - 38, size: 15, color: Color(hex: 0x8CFF4A), face: .display, align: .center,
                       shadow: Color(linear: 0, 0, 0, 0.9))
            }
            let rowY = hy - 42
            for i in 0..<10 {
                let x = hx + Float(i) * 22
                let value = s.health / 2 - Double(i)
                let lowPulse: Float = s.health <= 4 ? Float(0.75 + 0.25 * sin(ui.time * 10)) : 1
                for (col, row, hex) in HeartIcon.pixels(fill: value >= 1 ? 1 : (value > 0 ? 0.5 : 0), hardcore: s.meta.isHardcore) {
                    d.fill(Rect(x + Float(col) * 2.2, rowY + 4 + Float(row) * 2.2, 2.2, 2.2), Color(hex: hex).scaled(lowPulse))
                }
            }
            // Armor bar: one shield per 2 points
            let points = s.armorPoints
            if points > 0 {
                let armorY = rowY - 24
                func shield(_ x: Float, _ color: Color) {
                    d.fill(Rect(x + 3, armorY + 3, 14, 10), color, radius: 2.5)
                    d.circle(center: SIMD2(x + 10, armorY + 12), radius: 6.5, color)
                }
                for i in 0..<10 {
                    let x = hx + Float(i) * 22
                    let value = points - i * 2
                    shield(x, Color(hex: 0x14141C, alpha: 0.65))
                    if value > 0 {
                        if value == 1 { d.pushClip(Rect(x, armorY, 10, 24)) }
                        shield(x + 1, Color(hex: 0xCBD5E2))
                        if value == 1 { d.popClip() }
                    }
                }
            }
            // Hunger: pixel drumsticks with a gold rim while saturated, shaking when starving, rippling after eating.
            for i in 0..<10 {
                let x = hx + total - 20 - Float(i) * 22
                let dy = Float(HungerIcon.offset(index: i, hunger: s.hunger, eatFlash: s.eatFlash, time: ui.time)) * 2.2
                let glow = Float(max(0, s.eatFlash - Double(i) * 0.05)) * 0.35
                for (col, row, hex) in HungerIcon.pixels(fill: HungerIcon.fill(index: i, hunger: s.hunger),
                                                        saturated: HungerIcon.saturated(index: i, saturation: s.saturation)) {
                    d.fill(Rect(x + Float(col) * 2.2, rowY + 3 + Float(row) * 2.2 + dy, 2.2, 2.2), Color(hex: hex).scaled(1 + glow))
                }
            }
            if s.air < 10 {
                for i in 0..<10 where s.air / 1.0 > Double(i) {
                    let x = hx + total - 20 - Float(i) * 22
                    d.circle(center: SIMD2(x + 9, rowY - 12), radius: 7, Color(hex: 0x8FD3FF), ring: 2)
                }
            }
        } else {
            d.text(s.spectator ? "SPECTATING" : "CREATIVE", x: W / 2, y: hy - 32, size: 11, color: Theme.amber.alpha(0.7), face: .display, align: .center, tracking: 0.25)
        }

        if let (text, remaining) = e.toast {
            let a = Float(min(1, remaining / 0.3))
            let w = d.font.measure(text, size: 15, face: .display) + 40
            let r = Rect(W / 2 - w / 2, 28 - (1 - a) * 12, w, 40)
            d.opacity = a
            d.fill(r, Color(hex: 0x2A1A0C, alpha: 0.85), radius: 20)
            d.stroke(r, Theme.amber.alpha(0.4), radius: 20, width: 1)
            d.text(text, in: r, size: 15, color: Theme.text, face: .display)
            d.opacity = 1
        }
        AdvancementToast.draw(ui, engine: e)
    }
}

extension HUD {
    /// Enchanted items shimmer: a soft purple wash and a band of light sweeping across the icon.
    static func enchantGlint(_ d: UIRenderer, _ r: Rect, time: Double) {
        let t = Float((time.truncatingRemainder(dividingBy: 2.4)) / 2.4)
        let band = r.w * 0.3
        d.fill(r, Color(hex: 0x9A5CFF, alpha: 0.12), radius: 6)
        d.fill(Rect(r.x + (r.w - band) * t, r.y, band, r.h), Color(hex: 0xD8B8FF, alpha: 0.22), radius: 4)
    }
}

// MARK: - Debug overlay

enum DebugOverlay {
    static func draw(_ ui: UIContext, engine e: GameEngine) {
        let d = ui.draw
        let p = e.profiler
        var lines: [String] = [
            String(format: "%.0f FPS  (%.2f ms · worst %.1f ms)", p.fps, p.frameMs, p.worstFrameMs),
            String(format: "CPU update %.2f ms · encode %.2f ms · GPU %.2f ms", p.updateMs, p.encodeMs, p.gpuMs),
            String(format: "Memory %.0f MB", p.memoryMB),
        ]
        if let w = e.activeWorld {
            let s = w.stats, r = e.worldRenderer.stats
            lines += [
                "Chunks \(s.loadedChunks) loaded · \(r.visibleChunks) rendered",
                "Draw calls \(r.drawCalls) · quads \(r.quads)",
                String(format: "Chunk gen %.2f ms · mesh %.2f ms", s.avgGenerationMs, s.avgMeshMs),
                "Queued gen \(s.pendingGeneration) · meshing \(s.pendingMeshes) · workers \(e.jobs.workerCount)",
                String(format: "GPU mesh memory %.1f MB", Double(s.gpuMeshBytes) / 1_048_576),
            ]
        }
        if let s = e.session {
            let pos = s.player.position
            lines += [
                String(format: "XYZ %.2f / %.2f / %.2f", pos.x, pos.y - Double(s.world.generator.depthOffset), pos.z),
                "Biome \(s.biome.displayName) · \(SkyModel.periodName(worldTime: s.worldTime))",
                s.target.map { "Target \(e.blocks[$0.id]?.displayName ?? "?") at \($0.block)" } ?? "Target none",
            ]
        }
        let h = Float(lines.count) * 20 + 20
        let panel = Rect(12, 12, 430, h)
        d.fill(panel, Color(hex: 0x080402, alpha: 0.65), radius: 10)
        for (i, line) in lines.enumerated() {
            d.text(line, x: 24, y: 22 + Float(i) * 20, size: 13.5, color: i == 0 ? Theme.jungle : Theme.text)
        }
        // Frame-time graph
        let history = p.history
        let g = Rect(12, panel.maxY + 8, 430, 60)
        d.fill(g, Color(hex: 0x080402, alpha: 0.55), radius: 8)
        let bw = g.w / Float(history.count)
        for (i, t) in history.enumerated() {
            let ms = Float(t * 1000)
            let bh = min(g.h - 4, ms / 33.3 * (g.h - 4))
            let col = ms < 9 ? Theme.jungle : (ms < 17.5 ? Theme.amber : Theme.danger)
            d.fill(Rect(g.x + Float(i) * bw, g.maxY - 2 - bh, max(1, bw), bh), col.alpha(0.8))
        }
    }
}
