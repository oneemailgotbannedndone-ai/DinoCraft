import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

// The heads-up display and the in-game screens for single-player on Windows.

private let white = SIMD4<Float>(1, 1, 1, 1)
private let amber = SIMD4<Float>(1, 0.85, 0.55, 1)
private let dim = SIMD4<Float>(0.75, 0.7, 0.85, 1)
private let panelColor = SIMD4<Float>(0.09, 0.06, 0.14, 0.96)

extension WinSolo {
    func buildUI(width W: Float, height H: Float, camera: WinCamera) -> [Float] {
        var ui = UIBuilder()
        guard let s = session else { return [] }
        let sc = max(1, min(W / 1280, H / 720))
        let now = clock

        if s.isLoading {
            buildLoadingScreen(&ui, session: s, width: W, height: H, scale: sc, now: now)
            return ui.vertices
        }

        if s.player.headInWater { ui.rect(0, 0, W, H, SIMD4(0.02, 0.1, 0.3, 0.35)) }
        if s.portalProgress > 0 {
            let tint: SIMD3<Float> = s.portalKind == Blocks.toonlandPortal ? SIMD3(0.95, 0.95, 0.95) : SIMD3(0.45, 0.1, 0.7)
            ui.rect(0, 0, W, H, SIMD4(tint, Float(min(1, s.portalProgress)) * 0.55))
        }
        var fullScreenMenu = false
        switch screen {
        case .settings, .advancements: fullScreenMenu = true
        default: break
        }
        if !hudHidden && !fullScreenMenu { buildHUD(&ui, width: W, height: H, scale: sc, camera: camera, now: now) }
        if s.damageFlash > 0 { ui.rect(0, 0, W, H, SIMD4(0.6, 0, 0, Float(s.damageFlash) * 0.3)) }

        if s.isDead {
            buildDeathScreen(&ui, width: W, height: H, scale: sc)
        } else {
            switch screen {
            case .closed:
                if !mouseCaptured && !chatOpen && options.screenshotPath == nil { buildResumeHint(&ui, width: W, height: H, scale: sc) }
            case .pause:
                buildPauseMenu(&ui, width: W, height: H, scale: sc)
            case .settings:
                ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.6))
                ui.centeredText("Settings", centerX: W / 2, y: 30 * sc, scale: max(1, (4 * sc).rounded()), color: amber)
                let panel = SettingsPanel(store: store, renderer: renderer, audio: audio, window: window,
                                          click: { [weak self] in self?.audio?.play("ui_click", volume: 0.5) })
                let bottom = panel.build(&ui, input: menuInput(), width: W, top: 30 * sc + 40 * max(1, (4 * sc).rounded()) / 2 + 30 * sc, scale: sc)
                if ui.button("Done", x: W / 2 - 200 * sc, y: max(bottom + 16 * sc, H - 70 * sc), w: 400 * sc, h: 46 * sc, scale: sc,
                             input: menuInput(), primary: true) {
                    audio?.play("ui_click", volume: 0.5)
                    screen = .pause
                }
            case .sleep(let started):
                let elapsed = Float(now - started)
                let darkness = min(1, elapsed / 1.2) * (1 - max(0, (elapsed - 2.4) / 0.8))
                ui.rect(0, 0, W, H, SIMD4(0.02, 0.01, 0.05, darkness * 0.96))
                ui.centeredText("Sleeping...", centerX: W / 2, y: H / 2 - 10 * sc, scale: max(1, (4 * sc).rounded()),
                                color: SIMD4(1, 1, 1, darkness))
            case .advancements:
                buildAdvancements(&ui, width: W, height: H, scale: sc)
            case .trade(let mob):
                buildTrade(&ui, mob: mob, width: W, height: H, scale: sc)
            case .inventory, .crafting, .container, .creative:
                buildSlotScreen(&ui, width: W, height: H, scale: sc)
            }
        }
        return ui.vertices
    }

    /// Loading screen: a backdrop for the dimension you're entering, drifting blocks, the title,
    /// a progress bar, your next goal and a rotating tip.
    private func buildLoadingScreen(_ ui: inout UIBuilder, session s: GameSession, width W: Float, height H: Float, scale sc: Float, now: Double) {
        let (top, bottom): (SIMD3<Float>, SIMD3<Float>)
        switch s.dimension {
        case .underworld: (top, bottom) = (SIMD3(0.23, 0.06, 0.04), SIMD3(0.07, 0.02, 0.02))
        case .skylands: (top, bottom) = (SIMD3(0.42, 0.35, 0.6), SIMD3(0.9, 0.63, 0.29))
        case .toonland: (top, bottom) = (SIMD3(0.23, 0.23, 0.23), SIMD3(0.06, 0.06, 0.06))
        default: (top, bottom) = (SIMD3(0.11, 0.07, 0.21), SIMD3(0.04, 0.02, 0.08))
        }
        let bands = 24
        for i in 0..<bands {
            let t = Float(i) / Float(bands - 1)
            ui.rect(0, H * Float(i) / Float(bands), W, H / Float(bands) + 1, SIMD4(top + (bottom - top) * t, 1))
        }
        // Drifting voxel silhouettes
        for i in 0..<18 {
            let h1 = Hashing.unit(7, Int32(i), 0, 0), h2 = Hashing.unit(7, Int32(i), 1, 0)
            let size = (20 + h2 * 60) * sc
            let x = (h1 * W + Float(now) * (8 + h2 * 20) * sc).truncatingRemainder(dividingBy: W + 120 * sc) - 60 * sc
            ui.rect(x, H * (0.55 + h2 * 0.4), size, size, SIMD4(1, 0.8, 0.4, 0.03 + h1 * 0.05))
        }
        if s.dimension == .toonland {
            let cell = 40 * sc
            let shift = Float(now * 30).truncatingRemainder(dividingBy: cell * 2)
            for row in 0..<2 {
                let y = row == 0 ? 0 : H - cell
                for k in -2..<Int(W / cell) + 3 where (k + row) % 2 == 0 {
                    ui.rect(Float(k) * cell + (row == 0 ? shift : -shift), y, cell, cell, SIMD4(0.95, 0.95, 0.95, 1))
                }
            }
        }
        let small = max(1, (2 * sc).rounded())
        let huge = max(2, (9 * sc).rounded())
        let bob = Float(sin(now * 1.5)) * 4 * sc
        let titleY = H * 0.2 + bob
        ui.centeredText("DinoCraft", centerX: W / 2 + 4 * sc, y: titleY + 4 * sc, scale: huge, color: SIMD4(0.16, 0.09, 0.25, 1))
        ui.centeredText("DinoCraft", centerX: W / 2, y: titleY, scale: huge, color: SIMD4(1, 0.8, 0.35, 1))
        let big = max(1, (3 * sc).rounded())
        let infoY = titleY + 7 * huge + 30 * sc
        ui.centeredText(s.loadingTitle, centerX: W / 2, y: infoY, scale: big, color: white)
        ui.centeredText(s.meta.name, centerX: W / 2, y: infoY + 7 * big + 12 * sc, scale: small, color: dim)
        let bw = 480 * sc, bh = 14 * sc, bx = W / 2 - bw / 2, by = infoY + 7 * big + 40 * sc
        let progress = Float(max(0, min(1, s.loadingProgress)))
        ui.rect(bx - 2 * sc, by - 2 * sc, bw + 4 * sc, bh + 4 * sc, SIMD4(1, 0.8, 0.4, 0.3))
        ui.rect(bx, by, bw, bh, SIMD4(0.06, 0.04, 0.11, 0.95))
        ui.rect(bx, by, max(8 * sc, bw * progress), bh, SIMD4(0.95, 0.6, 0.12, 1))
        let shimmer = bx + Float(now * 0.6).truncatingRemainder(dividingBy: 1) * bw * progress
        ui.rect(shimmer - 16 * sc, by, 32 * sc, bh, SIMD4(1, 1, 1, 0.22))
        ui.centeredText("\(Int(progress * 100))%  -  \(s.loadingDetail)", centerX: W / 2, y: by + bh + 12 * sc, scale: small, color: dim)
        if let goal = GameGuide.current(s.advancements), !s.isRemote {
            ui.centeredText("NEXT GOAL: \(goal.step.title.uppercased())", centerX: W / 2, y: H - 150 * sc, scale: small, color: SIMD4(0.55, 0.95, 0.5, 1))
        }
        let tip = GameGuide.tips[Int(now / 5) % GameGuide.tips.count]
        ui.centeredText("TIP", centerX: W / 2, y: H - 112 * sc, scale: small, color: amber)
        ui.centeredText(tip, centerX: W / 2, y: H - 90 * sc, scale: small, color: white)
    }

    // MARK: HUD

    private func buildHUD(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float, camera: WinCamera, now: Double) {
        let s = game
        let small = max(1, (2 * sc).rounded())
        let survival = s.player.gameMode == .survival && !s.spectator

        // Name tags over friends
        let viewProj = camera.viewProjection(aspect: W / max(1, H))
        for p in hostEntities.values where p.dying == 0 {
            let rel = p.position + DVec3(0, 2.25, 0) - camera.position
            guard simd_length(rel) < 48 else { continue }
            let clip = viewProj * SIMD4<Float>(Float(rel.x), Float(rel.y), Float(rel.z), 1)
            guard clip.w > 0.1 else { continue }
            let sx = (clip.x / clip.w * 0.5 + 0.5) * W, sy = (0.5 - clip.y / clip.w * 0.5) * H
            let width = UIBuilder.textWidth(p.name, scale: small)
            ui.rect(sx - width / 2 - 3 * small, sy - 9 * small, width + 6 * small, 11 * small, SIMD4(0, 0, 0, 0.45))
            ui.text(p.name, x: sx - width / 2, y: sy - 7 * small, scale: small, color: white, shadow: false)
        }

        // Crosshair, mining progress and bow draw
        if !screenIsOpen && cameraView != .front {
            let color: SIMD4<Float> = s.targetMob != nil ? SIMD4(1, 0.55, 0.45, 0.95) : SIMD4(0.9, 0.9, 0.9, 0.85)
            ui.rect(W / 2 - 1.5 * sc, H / 2 - 11 * sc, 3 * sc, 22 * sc, color)
            ui.rect(W / 2 - 11 * sc, H / 2 - 1.5 * sc, 22 * sc, 3 * sc, color)
        }
        if let boss = s.mobs.boss(near: s.player.position) {
            // Boss health bar across the top of the screen
            let frac = Float(max(0, boss.health) / boss.species.maxHealth)
            let bw = 520 * sc, bh = 14 * sc, bx = W / 2 - bw / 2, by = 38 * sc
            ui.centeredText(boss.species.displayName, centerX: W / 2, y: 14 * sc, scale: max(1, (2.5 * sc).rounded()), color: white)
            ui.rect(bx - 3 * sc, by - 3 * sc, bw + 6 * sc, bh + 6 * sc, SIMD4(0, 0, 0, 0.7))
            ui.rect(bx, by, bw, bh, SIMD4(0.25, 0.25, 0.25, 1))
            ui.rect(bx, by, bw * frac, bh, boss.enraged ? SIMD4(0.95, 0.3, 0.3, 1) : SIMD4(0.95, 0.95, 0.95, 1))
        }
        if settings.showGuide, !showDebug, !s.isRemote, let goal = GameGuide.current(s.advancements) {
            // The guide to beating the game, in the top-left corner
            let small = max(1, (2 * sc).rounded())
            let x = 14 * sc, y = 118 * sc
            let w = max(UIBuilder.textWidth(goal.step.hint, scale: small), UIBuilder.textWidth(goal.step.title, scale: small)) + 20 * sc
            ui.rect(x, y, w, 7 * small * 3 + 30 * sc, SIMD4(0.05, 0.03, 0.1, 0.6))
            ui.rect(x, y, 3 * sc, 7 * small * 3 + 30 * sc, amber)
            ui.text("GUIDE \(goal.number)/\(GameGuide.steps.count)  (G)", x: x + 10 * sc, y: y + 6 * sc, scale: small, color: amber)
            ui.text(goal.step.title, x: x + 10 * sc, y: y + 6 * sc + 7 * small + 6 * sc, scale: small, color: white)
            ui.text(goal.step.hint, x: x + 10 * sc, y: y + 6 * sc + 14 * small + 12 * sc, scale: small, color: dim)
        }
        if s.dimension == .toonland, let line = SongLyrics.line(track: audio?.currentTrack, time: audio?.musicTime) {
            // Sing-along lyrics
            let text = "\u{266A} \(line) \u{266A}"
            let scale = max(1, (2 * sc).rounded())
            let tw = UIBuilder.textWidth(text, scale: scale)
            let y = H - 150 * sc
            ui.rect(W / 2 - tw / 2 - 10 * sc, y - 6 * sc, tw + 20 * sc, 7 * scale + 12 * sc, SIMD4(0, 0, 0, 0.55))
            ui.centeredText(text, centerX: W / 2, y: y, scale: scale, color: white)
        }
        if s.breakProgress > 0 {
            ui.rect(W / 2 - 22 * sc, H / 2 + 18 * sc, 44 * sc, 5 * sc, SIMD4(0, 0, 0, 0.5))
            ui.rect(W / 2 - 22 * sc, H / 2 + 18 * sc, 44 * sc * Float(min(1, s.breakProgress)), 5 * sc, SIMD4(0.95, 0.6, 0.12, 1))
        }
        if s.bowCharge > 0 {
            let charge = Float(min(1, s.bowCharge))
            ui.rect(W / 2 - 22 * sc, H / 2 + 26 * sc, 44 * sc, 5 * sc, SIMD4(0, 0, 0, 0.5))
            ui.rect(W / 2 - 22 * sc, H / 2 + 26 * sc, 44 * sc * charge, 5 * sc, charge >= 1 ? SIMD4(1, 0.95, 0.4, 1) : SIMD4(0.85, 0.85, 0.9, 1))
        }

        // Hotbar
        let slot = 54 * sc, gap = 6 * sc
        let total = Float(Inventory.hotbarCount) * slot + Float(Inventory.hotbarCount - 1) * gap
        let x0 = W / 2 - total / 2, y0 = H - slot - 18 * sc
        ui.rect(x0 - 8 * sc, y0 - 8 * sc, total + 16 * sc, slot + 16 * sc, SIMD4(0.005, 0.003, 0.012, 0.55))
        for i in 0..<Inventory.hotbarCount {
            let x = x0 + Float(i) * (slot + gap)
            if i == s.inventory.selected { ui.rect(x - 3 * sc, y0 - 3 * sc, slot + 6 * sc, slot + 6 * sc, SIMD4(0.9, 0.45, 0.08, 1)) }
            ui.rect(x, y0, slot, slot, SIMD4(0.02, 0.012, 0.04, 0.85))
            if let stack = s.inventory.slots[i] { drawStack(&ui, stack, x: x, y: y0, size: slot, scale: sc) }
        }
        if s.zooming {
            ui.centeredText(String(format: "Zoom %.1fx - scroll to adjust", s.zoomFactor), centerX: W / 2, y: y0 - (survival ? 64 : 44) * sc - 7 * small,
                            scale: small, color: SIMD4(1, 1, 1, 0.9))
        }
        if s.hotbarNameTimer > 0, let stack = s.inventory.selectedStack, let info = items[stack.item] {
            let alpha = Float(min(1, s.hotbarNameTimer / 0.5))
            ui.centeredText(info.displayName, centerX: W / 2, y: y0 - (survival ? 44 : 24) * sc - 7 * small, scale: small,
                            color: SIMD4(1, 1, 1, alpha))
        }

        if survival {
            let rowY = y0 - 12 * sc - 7 * small
            // Hearts
            let pulse: Float = s.health <= 4 ? Float(0.75 + 0.25 * sin(Date.timeIntervalSinceReferenceDate * 10)) : 1
            for i in 0..<10 {
                let hx = x0 + Float(i) * 8 * small
                let value = s.health / 2 - Double(i)
                ui.heart(x: hx, y: rowY - small * 0.4, unit: small * 7.6 / 9, fill: value >= 1 ? 1 : (value > 0 ? 0.5 : 0),
                         hardcore: s.meta.isHardcore, brightness: pulse)
            }
            // Hunger
            for i in 0..<10 {
                let fx = x0 + total - Float(i + 1) * 8 * small
                let value = s.hunger / 2 - Double(i)
                ui.text("\u{25CF}", x: fx, y: rowY, scale: small, color: SIMD4(0.12, 0.06, 0.02, 0.85), shadow: false)
                if value >= 1 {
                    ui.text("\u{25CF}", x: fx, y: rowY, scale: small, color: SIMD4(0.95, 0.55, 0.15, 1), shadow: false)
                } else if value > 0 {
                    ui.text("\u{25CF}", x: fx, y: rowY, scale: small, color: SIMD4(0.7, 0.42, 0.2, 1), shadow: false)
                }
            }
            // Armor above the hearts, air above the hunger
            let upperY = rowY - 10 * small
            let armor = s.armorPoints
            if armor > 0 {
                for i in 0..<10 {
                    let value = armor - i * 2
                    let color: SIMD4<Float> = value >= 2 ? SIMD4(0.8, 0.85, 0.95, 1) : (value == 1 ? SIMD4(0.55, 0.58, 0.66, 1) : SIMD4(0.15, 0.15, 0.2, 0.8))
                    ui.rect(x0 + Float(i) * 8 * small + small, upperY + small, 5 * small, 6 * small, color)
                }
            }
            if s.air < 10 {
                for i in 0..<max(0, Int(ceil(s.air))) {
                    ui.text("\u{25CB}", x: x0 + total - Float(i + 1) * 8 * small, y: upperY, scale: small,
                            color: SIMD4(0.55, 0.8, 1, 1), shadow: false)
                }
            }
        } else if s.spectator {
            ui.centeredText("Spectator - your Hardcore adventure is over", centerX: W / 2, y: y0 - 16 * sc - 7 * small, scale: small, color: dim)
        }

        // Chat
        let lineHeight = 10 * small
        let recent = chatOpen ? Array(chatLines.suffix(14)) : Array(chatLines.filter { now - $0.time < 10 }.suffix(8))
        let inputY = y0 - 60 * sc
        var y = inputY - (chatOpen ? lineHeight + 4 * sc : 0)
        for line in recent.reversed() {
            y -= lineHeight
            let alpha: Float = chatOpen ? 1 : Float(max(0, min(1, (10 - (now - line.time)) / 1.5)))
            let text = String(line.text.prefix(90))
            ui.rect(12 * sc, y - 2 * small, UIBuilder.textWidth(text, scale: small) + 8 * small, lineHeight, SIMD4(0, 0, 0, 0.4 * alpha))
            ui.text(text, x: 12 * sc + 4 * small, y: y, scale: small, color: SIMD4(1, 1, 1, alpha))
        }
        if chatOpen {
            let text = "> " + chatInput + (Int(now * 2) % 2 == 0 ? "_" : "")
            ui.rect(12 * sc, inputY - 2 * small, max(420 * sc, UIBuilder.textWidth(text, scale: small) + 8 * small), lineHeight, SIMD4(0, 0, 0, 0.6))
            ui.text(text, x: 12 * sc + 4 * small, y: inputY, scale: small, color: SIMD4(1, 1, 0.85, 1))
        }

        // Status, messages and debug
        if let host {
            ui.text("Hosting \(s.meta.name) - \(host.playerCount + 1) playing - T to chat", x: 12 * sc, y: 12 * sc, scale: small, color: SIMD4(1, 1, 1, 0.8))
        }
        if let toast, now - toast.time < 2.6 {
            let alpha = Float(min(1, (2.6 - (now - toast.time)) / 0.4))
            let width = UIBuilder.textWidth(toast.text, scale: small)
            ui.rect(W / 2 - width / 2 - 10 * sc, H * 0.14 - 6 * sc, width + 20 * sc, 7 * small + 12 * sc, SIMD4(0.05, 0.03, 0.1, 0.8 * alpha))
            ui.text(toast.text, x: W / 2 - width / 2, y: H * 0.14, scale: small, color: SIMD4(1, 1, 1, alpha))
        }
        var ty = 16 * sc
        for entry in advancementToasts where now - entry.time < 6 {
            let alpha = Float(min(1, (6 - (now - entry.time)) / 0.6))
            let w = max(UIBuilder.textWidth(entry.def.title, scale: small), UIBuilder.textWidth("Advancement made!", scale: small)) + 24 * sc
            ui.rect(W - w - 16 * sc, ty, w, 20 * small + 8 * sc, SIMD4(0.12, 0.08, 0.2, 0.92 * alpha))
            ui.rect(W - w - 16 * sc, ty, 4 * sc, 20 * small + 8 * sc, SIMD4(0.95, 0.6, 0.12, alpha))
            ui.text("Advancement made!", x: W - w - 4 * sc, y: ty + 4 * sc, scale: small, color: SIMD4(1, 0.85, 0.4, alpha))
            ui.text(entry.def.title, x: W - w - 4 * sc, y: ty + 4 * sc + 10 * small, scale: small, color: SIMD4(1, 1, 1, alpha))
            ty += 20 * small + 16 * sc
        }
        if settings.showFPS && !showDebug {
            let text = "\(fps) FPS"
            ui.text(text, x: W - 12 * sc - UIBuilder.textWidth(text, scale: small), y: H - 12 * sc - 7 * small, scale: small, color: SIMD4(1, 1, 1, 0.8))
        }
        if showDebug {
            let p = s.player.position
            var lines = [
                "DinoCraft for Windows - \(fps) FPS",
                String(format: "XYZ %.1f / %.1f / %.1f", p.x, p.y - Double(s.world.generator.depthOffset), p.z),
                "\(s.dimension.displayName) - \(s.biome.rawValue) - \(s.modeName)",
                "Chunks \(renderer.visibleChunks) drawn, \(s.world.slots.count) loaded",
                "Creatures \(s.mobs.mobs.count) - items \(s.entities.items.count)",
                "Time \(SkyModel.periodName(worldTime: s.worldTime)) - weather \(s.weather.kind.rawValue)",
            ]
            if let t = s.target, let name = blocks[t.id]?.displayName { lines.append("Looking at \(name)") }
            var dy = (host != nil ? 28 : 12) * sc
            for line in lines {
                ui.rect(12 * sc - 2 * small, dy - 2 * small, UIBuilder.textWidth(line, scale: small) + 4 * small, 11 * small, SIMD4(0, 0, 0, 0.45))
                ui.text(line, x: 12 * sc, y: dy, scale: small, color: white, shadow: false)
                dy += 12 * small
            }
        }
    }

    func drawStack(_ ui: inout UIBuilder, _ stack: ItemStack, x: Float, y: Float, size: Float, scale sc: Float) {
        let small = max(1, (2 * sc).rounded())
        let inset = size * 0.17
        ui.icon(x + inset, y + inset, size - 2 * inset, layer: renderer.iconLayer(stack.item, items: items, blocks: blocks))
        if stack.count > 1 {
            let count = "\(stack.count)"
            ui.text(count, x: x + size - 3 * sc - UIBuilder.textWidth(count, scale: small), y: y + size - 3 * sc - 7 * small, scale: small, color: white)
        }
        if let info = items[stack.item], stack.damage > 0 {
            let durability = info.tool?.durability ?? info.armor?.durability ?? 0
            if durability > 0 {
                let fraction = max(0, 1 - Float(stack.damage) / Float(durability))
                ui.rect(x + inset, y + size - 6 * sc, size - 2 * inset, 3 * sc, SIMD4(0, 0, 0, 0.7))
                ui.rect(x + inset, y + size - 6 * sc, (size - 2 * inset) * fraction, 3 * sc, SIMD4(1 - fraction, fraction, 0.1, 1))
            }
        }
    }

    private func menuInput() -> MenuInput {
        var input = MenuInput()
        input.mouse = mouse
        input.clicked = clicked
        return input
    }

    private func buildResumeHint(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float) {
        let small = max(1, (2 * sc).rounded())
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.25))
        ui.centeredText("Click to keep playing", centerX: W / 2, y: H * 0.45, scale: small, color: white)
        if clicked { setMouseCaptured(true) }
    }

    private func buildPauseMenu(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float) {
        let input = menuInput()
        let small = max(1, (2 * sc).rounded())
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.5))
        ui.centeredText("Game Paused", centerX: W / 2, y: H * 0.14, scale: max(1, (5 * sc).rounded()), color: amber)
        let bw = 400 * sc, bh = 46 * sc, gap = 12 * sc
        var y = H * 0.3
        if ui.button("Back to Game", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input, primary: true) {
            audio?.play("ui_click", volume: 0.5)
            screen = .closed
            setMouseCaptured(true)
            return
        }
        y += bh + gap
        if ui.button("Advancements - \(game.advancements.unlockedCount) of \(AdvancementTracker.definitions.count)",
                     x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input) {
            audio?.play("ui_click", volume: 0.5)
            screen = .advancements
            return
        }
        y += bh + gap
        if ui.button("Settings", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input) {
            audio?.play("ui_click", volume: 0.5)
            screen = .settings
            return
        }
        y += bh + gap
        let label = host.map { "Open to Friends - \($0.playerCount) joined" } ?? "Open to Friends"
        if ui.button(label, x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input, enabled: host == nil) {
            audio?.play("ui_click", volume: 0.5)
            startHosting()
        }
        y += bh + gap
        if ui.button("Save & Quit to Title", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input) {
            audio?.play("ui_click", volume: 0.5)
            quitToTitle()
        }
        y += bh + 24 * sc
        var lines: [String] = ["\(game.meta.name) - \(game.modeName) - \(game.meta.difficulty.rawValue.capitalized)"]
        if let lanCode { lines.append("Same Wi-Fi invite code: \(lanCode)") }
        if let internetCode { lines.append("Internet invite code: \(internetCode)") }
        if host == nil { lines.append("Open to Friends lets Mac and Windows players join this world.") }
        for line in lines {
            ui.centeredText(line, centerX: W / 2, y: y, scale: small, color: SIMD4(1, 1, 1, 0.9))
            y += 12 * small
        }
    }

    private func buildDeathScreen(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float) {
        let input = menuInput()
        let small = max(1, (2 * sc).rounded())
        let big = max(1, (7 * sc).rounded())
        ui.rect(0, 0, W, H, SIMD4(0.25, 0, 0, 0.6))
        ui.centeredText("You Died!", centerX: W / 2, y: H * 0.26, scale: big, color: SIMD4(1, 0.35, 0.35, 1))
        ui.centeredText(game.deathMessage, centerX: W / 2, y: H * 0.26 + 12 * big, scale: small, color: white)
        let bw = 400 * sc, bh = 46 * sc
        var y = H * 0.5
        let hardcore = game.meta.isHardcore
        if ui.button(hardcore ? "Spectate World" : "Respawn", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input, primary: true) {
            audio?.play("ui_click", volume: 0.5)
            game.respawn()
            setMouseCaptured(true)
            return
        }
        y += bh + 12 * sc
        if ui.button("Title Screen", x: W / 2 - bw / 2, y: y, w: bw, h: bh, scale: sc, input: input) {
            audio?.play("ui_click", volume: 0.5)
            quitToTitle()
        }
    }

    private func buildAdvancements(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float) {
        let small = max(1, (2 * sc).rounded())
        let tracker = game.advancements
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.6))
        let defs = AdvancementTracker.definitions
        ui.centeredText("Advancements - \(tracker.unlockedCount) of \(defs.count)", centerX: W / 2, y: 20 * sc,
                        scale: max(1, (3 * sc).rounded()), color: amber)
        let columns = 3
        let colW = min(400 * sc, (W - 40 * sc) / Float(columns))
        let rowH = 21 * small
        let startX = W / 2 - colW * Float(columns) / 2
        let startY = 20 * sc + 14 * max(1, (3 * sc).rounded())
        let perColumn = max(1, Int((H - startY - 40 * sc) / rowH))
        for (i, def) in defs.enumerated() {
            let column = i / perColumn, row = i % perColumn
            guard column < columns else { break }
            let x = startX + Float(column) * colW, y = startY + Float(row) * rowH
            let done = tracker.isUnlocked(def.id)
            ui.rect(x + 4 * sc, y, colW - 8 * sc, rowH - 3 * sc, done ? SIMD4(0.22, 0.16, 0.06, 0.95) : SIMD4(0.08, 0.06, 0.12, 0.9))
            ui.text((done ? "\u{2713} " : "") + def.title, x: x + 10 * sc, y: y + 3 * sc, scale: small, color: done ? SIMD4(1, 0.8, 0.35, 1) : white)
            let maxChars = max(8, Int((colW - 20 * sc) / (6 * small)))
            let detail = def.description.count > maxChars ? String(def.description.prefix(maxChars - 1)) + "\u{2026}" : def.description
            ui.text(detail, x: x + 10 * sc, y: y + 3 * sc + 9 * small, scale: small, color: dim, shadow: false)
        }
        ui.centeredText("Esc to close", centerX: W / 2, y: H - 20 * sc - 7 * small, scale: small, color: dim)
    }

    private func buildTrade(_ ui: inout UIBuilder, mob: Mob, width W: Float, height H: Float, scale sc: Float) {
        let input = menuInput()
        let small = max(1, (2 * sc).rounded())
        let profession = VillagerProfession.of(mob)
        let inv = game.inventory
        let rowH = 52 * sc, gap = 8 * sc
        let pw = 620 * sc
        let ph = 90 * sc + Float(profession.trades.count) * (rowH + gap) + 40 * sc
        let px = W / 2 - pw / 2, py = H / 2 - ph / 2
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.45))
        ui.rect(px, py, pw, ph, panelColor)
        ui.text("\(profession.name) Villager", x: px + 20 * sc, y: py + 18 * sc, scale: max(1, (3 * sc).rounded()), color: amber)
        ui.text(profession.blurb, x: px + 20 * sc, y: py + 18 * sc + 24 * sc, scale: small, color: dim)
        var y = py + 80 * sc
        for t in profession.trades {
            guard let cost = items.info(named: t.cost), let result = items.info(named: t.result) else { continue }
            let affordable = inv.count(of: cost.id) >= t.costCount
            ui.rect(px + 20 * sc, y, pw - 40 * sc, rowH, SIMD4(0.05, 0.03, 0.09, 0.9))
            drawStack(&ui, ItemStack(item: cost.id, count: t.costCount), x: px + 28 * sc, y: y + 4 * sc, size: rowH - 8 * sc, scale: sc)
            ui.text("\u{2192}", x: px + 36 * sc + rowH, y: y + rowH / 2 - 3.5 * small, scale: small, color: amber)
            drawStack(&ui, ItemStack(item: result.id, count: t.resultCount), x: px + 60 * sc + rowH, y: y + 4 * sc, size: rowH - 8 * sc, scale: sc)
            ui.text("\(t.costCount) \(cost.displayName) for \(t.resultCount) \(result.displayName)", x: px + 76 * sc + 2 * rowH,
                    y: y + rowH / 2 - 3.5 * small, scale: small, color: affordable ? white : dim)
            if ui.button("Trade", x: px + pw - 130 * sc, y: y + 8 * sc, w: 100 * sc, h: rowH - 16 * sc, scale: sc, input: input,
                         enabled: affordable, primary: true) {
                performTrade(t)
            }
            y += rowH + gap
        }
        let emeralds = items.id(named: "emerald").map { inv.count(of: $0) } ?? 0
        ui.text("You have \(emeralds) emeralds - Esc to close", x: px + 20 * sc, y: py + ph - 28 * sc, scale: small, color: dim)
    }

    private func performTrade(_ t: Trade) {
        let s = game
        guard let cost = items.id(named: t.cost), let result = items.id(named: t.result) else { return }
        let inv = s.inventory
        guard inv.count(of: cost) >= t.costCount else { return }
        var left = t.costCount
        for i in inv.slots.indices where left > 0 {
            guard var st = inv.slots[i], st.item == cost else { continue }
            let take = min(left, st.count)
            st.count -= take
            left -= take
            inv.slots[i] = st.count > 0 ? st : nil
        }
        inv.markChanged()
        let overflow = inv.add(ItemStack(item: result, count: t.resultCount))
        if overflow > 0 { s.dropStack(ItemStack(item: result, count: overflow), thrown: false) }
        audio?.play("craft", volume: 0.6)
        s.advancements.record("trade", t.result)
    }

    // MARK: Inventory, crafting, containers and the creative palette

    private var gridSize: Int { craftGrid.count == 9 ? 3 : 2 }

    private var openContainer: (pos: BlockPos, container: Container)? {
        guard case .container(let pos, let kind) = screen else { return nil }
        return (pos, game.containers.ensure(pos, kind: kind))
    }

    func paletteItems() -> [ItemInfo] {
        let q = paletteSearch.lowercased().trimmingCharacters(in: .whitespaces)
        let all = items.all
        return q.isEmpty ? all : all.filter { $0.displayName.lowercased().contains(q) || $0.name.contains(q) }
    }

    private func stack(at ref: SlotRef) -> ItemStack? {
        let s = game
        switch ref {
        case .inventory(let i): return s.inventory.slots[i]
        case .craft(let i): return i < craftGrid.count ? craftGrid[i] : nil
        case .output: return recipes.match(grid: craftGrid, size: gridSize)?.result
        case .armor(let i): return s.armor[i]
        case .container(let i):
            guard let open = openContainer, i < open.container.slots.count else { return nil }
            return open.container.slots[i]
        case .palette(let i):
            let list = paletteItems()
            guard i < list.count else { return nil }
            return ItemStack(item: list[i].id, count: 1)
        }
    }

    private func setStack(_ ref: SlotRef, _ value: ItemStack?) {
        let s = game
        switch ref {
        case .inventory(let i): s.inventory.slots[i] = value
        case .craft(let i): if i < craftGrid.count { craftGrid[i] = value }
        case .armor(let i): s.armor[i] = value
        case .container(let i):
            if let open = openContainer, i < open.container.slots.count { open.container.slots[i] = value }
        case .output, .palette: break
        }
    }

    private func slotsChanged() {
        game.inventory.markChanged()
        if let open = openContainer { game.containerChanged(open.pos) }
    }

    private func clickSlot(_ ref: SlotRef, button: SlotButton, shift: Bool) {
        let s = game
        let inv = s.inventory
        switch ref {
        case .output:
            takeCraftResult(shift: shift)
            return
        case .palette(let i):
            let list = paletteItems()
            if cursorStack != nil {
                cursorStack = nil
            } else if i < list.count {
                let full = ItemStack(item: list[i].id, count: button == .right ? 1 : list[i].maxStack)
                if shift { inv.add(full) } else { cursorStack = full }
            }
            return
        case .container(Container.furnaceOutput) where openContainer?.container.kind == .furnace:
            takeFurnaceOutput(shift: shift)
            return
        default:
            break
        }
        if shift, let moving = stack(at: ref) {
            if let open = openContainer {
                switch ref {
                case .container:
                    var slots = inv.slots
                    setStack(ref, SlotInteraction.quickMove(moving, into: &slots, indices: Array(9..<36) + Array(0..<9), maxStack: inv.maxStack))
                    inv.slots = slots
                case .inventory(let i):
                    var targets = Array(0..<open.container.slots.count)
                    if open.container.kind == .furnace {
                        if s.smelting?.recipe(for: moving.item) != nil { targets = [Container.furnaceInput] }
                        else if s.smelting?.burnTime(moving.item) != nil { targets = [Container.furnaceFuel] }
                        else { return }
                    }
                    inv.slots[i] = SlotInteraction.quickMove(moving, into: &open.container.slots, indices: targets, maxStack: inv.maxStack)
                default:
                    break
                }
            } else {
                if case .inventory = ref, case .inventory = screen, let spec = items[moving.item]?.armor, s.armor[spec.slot.index] == nil {
                    s.armor[spec.slot.index] = moving
                    setStack(ref, nil)
                    audio?.play("place_metal", volume: 0.5)
                    slotsChanged()
                    return
                }
                let targets: [Int]
                switch ref {
                case .inventory(let i): targets = i < 9 ? Array(9..<36) : Array(0..<9)
                default: targets = Array(9..<36) + Array(0..<9)
                }
                var slots = inv.slots
                let left = SlotInteraction.quickMove(moving, into: &slots, indices: targets, maxStack: inv.maxStack)
                inv.slots = slots
                setStack(ref, left)
            }
            audio?.play("ui_toggle", volume: 0.3)
            slotsChanged()
            return
        }
        // Armor slots only take the matching kind of armor.
        if case .armor(let i) = ref, let c = cursorStack, items[c.item]?.armor?.slot.index != i { return }
        var value = stack(at: ref)
        SlotInteraction.click(&value, cursor: &cursorStack, button: button, maxStack: inv.maxStack)
        setStack(ref, value)
        slotsChanged()
    }

    private func takeCraftResult(shift: Bool) {
        let s = game
        guard let recipe = recipes.match(grid: craftGrid, size: gridSize) else { return }
        let result = recipe.result
        let inv = s.inventory
        if shift {
            var crafted = 0
            while crafted < 64, let r = recipes.match(grid: craftGrid, size: gridSize), r.result.item == result.item {
                var slots = inv.slots
                guard SlotInteraction.quickMove(r.result, into: &slots, indices: Array(0..<36), maxStack: inv.maxStack) == nil else { break }
                inv.slots = slots
                RecipeRegistry.consumeIngredients(grid: &craftGrid)
                crafted += 1
            }
            if crafted > 0 {
                inv.markChanged()
                audio?.play("craft", volume: 0.6)
                s.noteCrafted(result.item, count: result.count * crafted)
            }
            return
        }
        if let c = cursorStack {
            guard c.canStack(with: result), c.count + result.count <= inv.maxStack(c.item) else { return }
            cursorStack?.count += result.count
        } else {
            cursorStack = result
        }
        RecipeRegistry.consumeIngredients(grid: &craftGrid)
        audio?.play("craft", volume: 0.6)
        s.noteCrafted(result.item, count: result.count)
    }

    private func takeFurnaceOutput(shift: Bool) {
        guard let open = openContainer, let out = open.container.slots[Container.furnaceOutput] else { return }
        let c = open.container
        let inv = game.inventory
        if shift {
            var slots = inv.slots
            c.slots[Container.furnaceOutput] = SlotInteraction.quickMove(out, into: &slots, indices: Array(0..<36), maxStack: inv.maxStack)
            inv.slots = slots
        } else if let held = cursorStack {
            guard held.canStack(with: out), held.count + out.count <= inv.maxStack(held.item) else { return }
            cursorStack?.count += out.count
            c.slots[Container.furnaceOutput] = nil
        } else {
            cursorStack = out
            c.slots[Container.furnaceOutput] = nil
        }
        if let name = items[out.item]?.name { game.advancements.record("smelt", name, amount: out.count) }
        audio?.play("pickup", volume: 0.35)
        slotsChanged()
    }

    private func buildSlotScreen(_ ui: inout UIBuilder, width W: Float, height H: Float, scale sc: Float) {
        let s = game
        let small = max(1, (2 * sc).rounded())
        let slot = 40 * sc, gap = 4 * sc, step = slot + gap, pad = 16 * sc
        let gridWidth = 9 * step - gap
        let panelW = gridWidth + 2 * pad
        let title: String
        let topHeight: Float
        var creative = false
        switch screen {
        case .inventory:
            title = "Inventory - \(s.modeName)"
            topHeight = 4 * step
        case .crafting:
            title = "Crafting Bench"
            topHeight = 3 * step
        case .container(_, let kind):
            title = kind.displayName
            topHeight = kind == .furnace ? 2 * step : 3 * step
        case .creative:
            title = "Creative Items"
            topHeight = 6 * step + 14 * small
            creative = true
        default:
            return
        }
        let titleHeight = 12 * small
        let lowerHeight = creative ? slot : 3 * step + 8 * sc + slot
        let panelH = pad + titleHeight + topHeight + 14 * sc + lowerHeight + pad
        let px = W / 2 - panelW / 2, py = H / 2 - panelH / 2
        ui.rect(0, 0, W, H, SIMD4(0, 0, 0, 0.45))
        ui.rect(px, py, panelW, panelH, panelColor)
        ui.text(title, x: px + pad, y: py + pad, scale: small, color: amber)

        hoveredSlot = nil
        var hoveredStack: ItemStack?
        func slotView(_ ref: SlotRef, _ x: Float, _ y: Float, accent: Bool = false, placeholder: String? = nil) {
            let hovered = mouse.x >= x && mouse.x < x + slot && mouse.y >= y && mouse.y < y + slot
            let background: SIMD4<Float> = accent ? SIMD4(0.4, 0.24, 0.05, 1) : (hovered ? SIMD4(0.28, 0.22, 0.42, 1) : SIMD4(0.03, 0.02, 0.06, 0.95))
            ui.rect(x, y, slot, slot, background)
            if hovered {
                hoveredSlot = ref
                hoveredStack = stack(at: ref)
            }
            if let st = stack(at: ref) {
                if case .palette = ref {
                    ui.icon(x + 5 * sc, y + 5 * sc, slot - 10 * sc, layer: renderer.iconLayer(st.item, items: items, blocks: blocks))
                } else {
                    drawStack(&ui, st, x: x, y: y, size: slot, scale: sc)
                }
            } else if let placeholder {
                ui.centeredText(placeholder, centerX: x + slot / 2, y: y + slot / 2 - 3.5 * small, scale: small, color: SIMD4(0.35, 0.32, 0.45, 1))
            }
        }

        let top = py + pad + titleHeight + 4 * sc
        let left = px + pad
        switch screen {
        case .inventory, .crafting:
            let size = gridSize
            if case .inventory = screen {
                for i in 0..<4 { slotView(.armor(i), left, top + Float(i) * step, placeholder: ["H", "C", "L", "B"][i]) }
                ui.text("Armor \(s.armorPoints)", x: left + step + 4 * sc, y: top + 4 * sc, scale: small, color: dim)
            }
            let gx = left + gridWidth / 2 - Float(size) * step + (size == 2 ? 20 * sc : -20 * sc)
            let gy = top + (topHeight - Float(size) * step) / 2
            for r in 0..<size {
                for c in 0..<size { slotView(.craft(r * size + c), gx + Float(c) * step, gy + Float(r) * step) }
            }
            let arrowX = gx + Float(size) * step + 8 * sc
            ui.text("\u{2192}", x: arrowX, y: top + topHeight / 2 - 3.5 * small, scale: small, color: SIMD4(1, 0.8, 0.4, 1))
            slotView(.output, arrowX + 8 * small + 8 * sc, top + topHeight / 2 - slot / 2,
                     accent: recipes.match(grid: craftGrid, size: size) != nil)
        case .container(_, let kind):
            if let open = openContainer {
                if kind == .furnace {
                    let c = open.container
                    let fx = left + gridWidth / 2 - 70 * sc
                    slotView(.container(Container.furnaceInput), fx, top)
                    slotView(.container(Container.furnaceFuel), fx, top + step)
                    let cook = c.cookTotal > 0 ? Float(min(1, c.cook / c.cookTotal)) : 0
                    let burn = c.burnTotal > 0 ? Float(min(1, c.burnLeft / c.burnTotal)) : 0
                    ui.rect(fx + step + 8 * sc, top + slot / 2 - 3 * sc, 48 * sc, 6 * sc, SIMD4(0, 0, 0, 0.6))
                    ui.rect(fx + step + 8 * sc, top + slot / 2 - 3 * sc, 48 * sc * cook, 6 * sc, SIMD4(1, 0.6, 0.15, 1))
                    ui.rect(fx + step + 8 * sc, top + step + slot / 2 - 3 * sc, 48 * sc, 6 * sc, SIMD4(0, 0, 0, 0.6))
                    ui.rect(fx + step + 8 * sc, top + step + slot / 2 - 3 * sc, 48 * sc * burn, 6 * sc, SIMD4(1, 0.35, 0.1, 1))
                    slotView(.container(Container.furnaceOutput), fx + step + 64 * sc, top + step / 2)
                } else {
                    for i in 0..<min(27, open.container.slots.count) { slotView(.container(i), left + Float(i % 9) * step, top + Float(i / 9) * step) }
                }
            }
        case .creative:
            let list = paletteItems()
            let rows = 6
            let maxScroll = max(0, (list.count + 8) / 9 - rows)
            paletteScroll = min(paletteScroll, maxScroll)
            // Search box: click to type
            let searchH = 12 * small
            let focused = paletteSearchFocused
            let searchHovered = mouse.x >= left && mouse.x < left + gridWidth && mouse.y >= top && mouse.y < top + searchH
            if clicked { paletteSearchFocused = searchHovered }
            if focused {
                if !menuTyped.isEmpty { paletteSearch = String((paletteSearch + menuTyped).prefix(24)); paletteScroll = 0 }
                if menuBackspace && !paletteSearch.isEmpty { paletteSearch.removeLast(); paletteScroll = 0 }
            }
            ui.rect(left, top, gridWidth, searchH, focused ? SIMD4(0.03, 0.02, 0.06, 1) : SIMD4(0.07, 0.05, 0.11, 0.95))
            let shown = paletteSearch.isEmpty && !focused ? "Click to search \(list.count) items"
                : paletteSearch + (focused && Int(clock * 2) % 2 == 0 ? "_" : "")
            ui.text(shown, x: left + 4 * sc, y: top + (searchH - 7 * small) / 2, scale: small,
                    color: paletteSearch.isEmpty && !focused ? dim : white, shadow: false)
            let gridTop = top + searchH + 6 * sc
            for row in 0..<rows {
                for col in 0..<9 {
                    let index = (paletteScroll + row) * 9 + col
                    guard index < list.count else { continue }
                    slotView(.palette(index), left + Float(col) * step, gridTop + Float(row) * step)
                }
            }
            if maxScroll > 0 {
                let barH = Float(rows) * step - gap
                ui.rect(left + gridWidth + 4 * sc, gridTop, 4 * sc, barH, SIMD4(0, 0, 0, 0.5))
                let thumb = barH * Float(rows) / Float(rows + maxScroll)
                ui.rect(left + gridWidth + 4 * sc, gridTop + (barH - thumb) * Float(paletteScroll) / Float(maxScroll), 4 * sc, thumb, amber)
            }
        default:
            break
        }

        let inventoryY = top + topHeight + 14 * sc
        if !creative {
            for i in 9..<Inventory.size {
                let index = i - 9
                slotView(.inventory(i), left + Float(index % 9) * step, inventoryY + Float(index / 9) * step)
            }
        }
        let hotbarY = creative ? inventoryY : inventoryY + 3 * step + 8 * sc
        for i in 0..<Inventory.hotbarCount { slotView(.inventory(i), left + Float(i) * step, hotbarY, accent: i == s.inventory.selected && creative) }

        if clicked || rightClicked {
            let button: SlotButton = rightClicked ? .right : .left
            if let ref = hoveredSlot {
                clickSlot(ref, button: button, shift: shiftHeld)
            } else if let cursor = cursorStack {
                let inside = mouse.x >= px && mouse.x < px + panelW && mouse.y >= py && mouse.y < py + panelH
                if !inside {
                    // Clicking outside the panel throws the carried stack (or deletes it in the creative palette).
                    if !creative { s.dropStack(cursor, thrown: true) }
                    cursorStack = nil
                }
            }
        }
        if let cursor = cursorStack {
            drawStack(&ui, cursor, x: mouse.x - slot / 2, y: mouse.y - slot / 2, size: slot, scale: sc)
        } else if let st = hoveredStack, let info = items[st.item] {
            var lines = [info.displayName]
            if let armor = info.armor { lines.append("+\(armor.protection) armor") }
            if let damage = info.tool?.damage, damage > 1 { lines.append("\(Int(damage)) attack damage") }
            if let food = info.food { lines.append("Restores \(food.hunger) hunger") }
            let width = lines.map { UIBuilder.textWidth($0, scale: small) }.max() ?? 0
            let boxH = Float(lines.count) * 10 * small + 4 * small
            ui.rect(mouse.x + 14 * sc, mouse.y - 6 * sc, width + 8 * small, boxH, SIMD4(0.05, 0.03, 0.1, 0.96))
            for (i, line) in lines.enumerated() {
                ui.text(line, x: mouse.x + 14 * sc + 4 * small, y: mouse.y - 6 * sc + 2 * small + Float(i) * 10 * small, scale: small,
                        color: i == 0 ? white : dim)
            }
        }
    }
}
