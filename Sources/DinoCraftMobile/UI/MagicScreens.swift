import UIKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// The enchanting table: three offers for the item in your hand, paid for with levels and amber.
final class EnchantScreen: Screen {
    let pos: BlockPos

    init(pos: BlockPos) { self.pos = pos }

    override var scene: GameActivityState.Scene { .playing }

    override func back(_ engine: GameEngine) {
        engine.audio.play("ui_close", volume: 0.45)
        engine.popScreen()
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        let center = DVec3(Double(pos.x) + 0.5, Double(pos.y), Double(pos.z) + 0.5)
        guard let s = e.session, e.blocks[s.world.block(pos)]?.name == Enchanting.table,
              simd_distance(center, s.player.position) < 8 else {
            back(e)
            return
        }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)
        let rowH: Float = 64, gap: Float = 10
        let pw: Float = 600, ph: Float = 190 + 3 * (rowH + gap) + 50
        let a = appear(0, duration: 0.22)
        let panel = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 12, pw, ph)
        d.opacity = a
        ui.panel(panel, title: "Enchanting Table")
        d.text("Spend levels and amber on the item in your hand.", x: panel.midX, y: panel.y + 70, size: 14,
               color: Theme.textMuted, align: .center)

        // The held item
        let card = Rect(panel.x + 30, panel.y + 100, pw - 60, 66)
        d.fill(card, Color(linear: 1, 1, 1, 0.05), radius: 12)
        let held = s.inventory.selectedStack
        if let held, let info = e.items[held.item] {
            d.itemIcon(info, Rect(card.x + 12, card.y + 11, 44, 44))
            if held.enchant != 0 { HUD.enchantGlint(d, Rect(card.x + 12, card.y + 11, 44, 44), time: ui.time) }
            d.text(info.displayName, x: card.x + 70, y: card.y + 12, size: 17, color: Theme.text, face: .display)
            let current = Enchantments.describe(held.enchant)
            d.text(current.isEmpty ? "Not enchanted yet" : current, x: card.x + 70, y: card.y + 38, size: 13,
                   color: current.isEmpty ? Theme.textMuted : Color(hex: 0xC8A0FF), maxWidth: card.w - 90)
        } else {
            d.text("Hold a tool, weapon or piece of armour", in: card, size: 15, color: Theme.textMuted)
        }

        let offers = s.enchantOffers
        if held != nil && offers.isEmpty {
            d.text("This can't be enchanted (or it's already as strong as it gets).", x: panel.midX, y: card.maxY + 30, size: 14,
                   color: Theme.textMuted, align: .center)
        }
        for (i, offer) in offers.enumerated() {
            let row = Rect(panel.x + 30, card.maxY + 16 + Float(i) * (rowH + gap), pw - 60, rowH)
            let problem = s.enchantProblem(offer)
            d.fill(row, Color(hex: 0x3A1E5A, alpha: 0.55), radius: 12)
            d.text("\(offer.enchantment.displayName) \(Enchantments.roman(offer.level))", x: row.x + 16, y: row.y + 10, size: 19,
                   color: problem == nil ? Color(hex: 0xE0C8FF) : Theme.textMuted, face: .display)
            d.text(problem ?? "\(offer.cost) level\(offer.cost == 1 ? "" : "s") + \(offer.cost) amber", x: row.x + 16, y: row.y + 38, size: 13,
                   color: problem == nil ? Theme.text : Theme.danger)
            if ui.button("enchant.\(i)", "Enchant", Rect(row.maxX - 134, row.y + 10, 122, rowH - 20), enabled: problem == nil) {
                if s.enchantHeld(offer) { e.audio.play("craft", volume: 0.6) }
            }
        }
        d.text("Level \(s.xpLevel)  ·  \(s.amberCount) amber", x: panel.midX, y: panel.maxY - 38, size: 14,
               color: Color(hex: 0x8CFF4A), face: .display, align: .center)
        d.opacity = 1
        if ui.input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 { back(e) }
    }
}

/// The Quest Book: what you've promised the villagers, and how far along you are.
final class QuestBookScreen: Screen {
    override var scene: GameActivityState.Scene { .playing }

    override func back(_ engine: GameEngine) {
        engine.audio.play("ui_close", volume: 0.45)
        engine.popScreen()
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { back(e); return }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)
        let rowH: Float = 76, gap: Float = 10
        let rows = max(1, s.quests.count)
        let pw: Float = 600, ph: Float = 130 + Float(rows) * (rowH + gap) + 30
        let a = appear(0, duration: 0.22)
        let panel = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 12, pw, ph)
        d.opacity = a
        ui.panel(panel, title: "Quest Book")
        d.text("Villagers ask for help. Hand finished quests in to any villager.", x: panel.midX, y: panel.y + 70, size: 14,
               color: Theme.textMuted, align: .center)
        if s.quests.isEmpty {
            d.text("No quests yet: right-click a villager to see what they need.", x: panel.midX, y: panel.y + 124, size: 15,
                   color: Theme.text, align: .center)
        }
        for (i, q) in s.quests.enumerated() {
            let row = Rect(panel.x + 30, panel.y + 100 + Float(i) * (rowH + gap), pw - 60, rowH)
            let progress = s.questProgress(q)
            d.fill(row, Color(linear: 1, 1, 1, 0.05), radius: 12)
            d.text(s.questTitle(q), x: row.x + 16, y: row.y + 10, size: 17, color: s.questComplete(q) ? Theme.jungle : Theme.text, face: .display)
            d.text("\(q.giver): \(q.emeralds) emeralds, \(q.xp) XP", x: row.x + 16, y: row.y + 34, size: 13, color: Theme.textMuted)
            let bar = Rect(row.x + 16, row.maxY - 16, row.w - 210, 6)
            d.fill(bar, Color(linear: 0, 0, 0, 0.5), radius: 3)
            d.fill(Rect(bar.x, bar.y, bar.w * Float(progress) / Float(max(1, q.count)), bar.h), Theme.jungle, radius: 3)
            d.text("\(progress)/\(q.count)", x: bar.maxX + 10, y: bar.y - 6, size: 13, color: Theme.text, face: .display)
            if ui.button("quest.abandon.\(i)", "Abandon", Rect(row.maxX - 124, row.y + rowH / 2 - 20, 112, 40)) {
                s.abandonQuest(q)
            }
        }
        d.opacity = 1
        if ui.input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 { back(e) }
    }
}

/// The paper map: the land around you, with villages, dig sites, ruins and volcanoes marked.
final class MapScreen: Screen {
    override var scene: GameActivityState.Scene { .playing }

    override func back(_ engine: GameEngine) {
        engine.audio.play("ui_close", volume: 0.45)
        engine.popScreen()
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { back(e); return }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)
        let map = s.paperMap
        map.refresh(s)
        let n = map.width
        let size = (min(W, H) - 150).rounded()
        let cell = size / Float(n)
        let a = appear(0, duration: 0.22)
        let box = Rect(W / 2 - size / 2, H / 2 - size / 2 + 18 + (1 - a) * 12, size, size)
        d.opacity = a
        ui.panel(Rect(box.x - 24, box.y - 70, box.w + 48, box.h + 112), title: "Map")
        let parchment: UInt32 = 0xE6D8B0
        d.fill(box, Color(hex: parchment))
        for j in 0..<n {
            let row = j * n
            var i = 0
            while i < n {
                let color = map.cells[row + i]
                var run = 1
                while i + run < n && map.cells[row + i + run] == color { run += 1 }
                if color != 0 {
                    d.fill(Rect(box.x + Float(i) * cell, box.y + Float(j) * cell, Float(run) * cell + 0.4, cell + 0.4),
                           Color(hex: Minimap.mix(color, parchment, 0.18)))
                }
                i += run
            }
        }
        let cx = box.x + size / 2, cy = box.y + size / 2
        for l in s.landmarks(radius: map.reach) {
            let mx = cx + l.dx * cell, my = cy + l.dz * cell
            d.fill(Rect(mx - 5, my - 5, 10, 10), Color(linear: 0, 0, 0, 0.85), radius: 3)
            d.fill(Rect(mx - 4, my - 4, 8, 8), Color(hex: l.color), radius: 2)
            d.text(l.label, x: mx, y: my + 7, size: 12, color: .white, face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.95))
        }
        for m in map.markers(for: s, radius: map.reach) {
            let mx = cx + m.dx * cell, my = cy + m.dz * cell
            switch m.kind {
            case .you:
                let look = s.player.lookDirection
                let flat = SIMD2<Float>(Float(look.x), Float(look.z))
                let dir = simd_length(flat) > 0.01 ? simd_normalize(flat) : SIMD2(0, -1)
                for k in 0..<3 {
                    let px = mx + dir.x * Float(k) * 4, py = my + dir.y * Float(k) * 4
                    let half: Float = k == 0 ? 4 : 3
                    d.fill(Rect(px - half - 1, py - half - 1, half * 2 + 2, half * 2 + 2), Color(linear: 0, 0, 0, 0.8), radius: half + 1)
                    d.fill(Rect(px - half, py - half, half * 2, half * 2), k == 2 ? Color(hex: 0xFF5A3C) : .white, radius: half)
                }
            case .death:
                d.text("X", x: mx, y: my - 9, size: 16, color: Color(hex: m.color), face: .display, align: .center,
                       shadow: Color(linear: 0, 0, 0, 0.9))
            case .player, .pet:
                let half: Float = m.kind == .pet ? 3 : 4
                d.fill(Rect(mx - half - 1, my - half - 1, half * 2 + 2, half * 2 + 2), Color(linear: 0, 0, 0, 0.85))
                d.fill(Rect(mx - half, my - half, half * 2, half * 2), Color(hex: m.color))
            }
        }
        d.text("N", x: cx, y: box.y + 4, size: 13, color: Color(hex: 0x3A2410), face: .display, align: .center)
        let p = s.player.position
        d.text("\(Int(floor(p.x))), \(Int(floor(p.z)))", x: cx, y: box.maxY + 12, size: 14, color: Theme.text, face: .display, align: .center)
        d.opacity = 1
        if ui.input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 { back(e) }
    }
}
