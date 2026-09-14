import AppKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// All advancements, grouped by category, with progress.
final class AdvancementsScreen: Screen {
    private var tab = 0

    override var scene: GameActivityState.Scene { .playing }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else {
            back(e)
            return
        }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.6)
        let a = appear(0, duration: 0.22)
        let pw = min(920, W - 60), ph = min(700, H - 40)
        let p = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 12, pw, ph)
        d.opacity = a
        ui.panel(p, title: "Advancements")

        let tracker = s.advancements
        let all = AdvancementTracker.definitions
        d.text("\(tracker.unlockedCount) of \(all.count) unlocked", x: p.midX, y: p.y + 66, size: 14, color: Theme.textMuted, align: .center)
        let categories = AdvancementTracker.categories
        guard !categories.isEmpty else { return }
        let options = categories.map { cat -> String in
            let defs = all.filter { $0.category == cat }
            return "\(cat) \(defs.filter { tracker.isUnlocked($0.id) }.count)/\(defs.count)"
        }
        ui.segmented("adv.tab", Rect(p.x + 40, p.y + 94, p.w - 80, 44), options: options, selected: &tab)
        let category = categories[min(tab, categories.count - 1)]
        let defs = all.filter { $0.category == category }

        let area = Rect(p.x + 40, p.y + 154, p.w - 80, p.h - 154 - 92)
        let gap: Float = 12, rowH: Float = 80
        let colW = (area.w - 14 - gap) / 2
        let content = Float((defs.count + 1) / 2) * (rowH + gap)
        let offset = ui.beginScroll("adv.scroll.\(tab)", area, contentHeight: content)
        for (i, def) in defs.enumerated() {
            let r = Rect(area.x + Float(i % 2) * (colW + gap), area.y + Float(i / 2) * (rowH + gap) - offset, colW, rowH)
            guard r.maxY > area.y, r.y < area.maxY else { continue }
            let done = tracker.isUnlocked(def.id)
            d.fill(r, done ? Theme.amber.alpha(0.13) : Color(linear: 1, 1, 1, 0.035), radius: 14)
            if done { d.stroke(r, Theme.amber.alpha(0.7), radius: 14, width: 1.4) }
            let iconRect = Rect(r.x + 14, r.y + 18, 44, 44)
            d.fill(iconRect.inset(-4), Color(hex: 0x0D0818, alpha: 0.6), radius: 10)
            if let info = e.items.info(named: def.icon) { d.itemIcon(info, iconRect, alpha: done ? 1 : 0.35) }
            d.text(def.title, x: r.x + 72, y: r.y + 12, size: 16, color: done ? Theme.text : Theme.text.alpha(0.75), face: .display, maxWidth: r.w - 170)
            d.text(def.description, x: r.x + 72, y: r.y + 37, size: 13, color: Theme.textMuted, maxWidth: r.w - 84)
            if done {
                d.text("Unlocked", x: r.maxX - 14, y: r.y + 13, size: 12.5, color: Theme.jungle, face: .display, align: .right)
            } else if def.required > 1 {
                let prog = tracker.progress(of: def)
                let bar = Rect(r.x + 72, r.maxY - 17, r.w - 150, 6)
                d.fill(bar, Color(linear: 1, 1, 1, 0.08), radius: 3)
                d.fill(Rect(bar.x, bar.y, bar.w * Float(prog) / Float(def.required), bar.h), Theme.amber, radius: 3)
                d.text("\(prog)/\(def.required)", x: r.maxX - 14, y: r.maxY - 24, size: 12, color: Theme.textMuted, align: .right)
            }
        }
        ui.endScroll("adv.scroll.\(tab)", area, contentHeight: content)
        d.opacity = 1

        if ui.button("adv.done", "Done", Rect(p.midX - 130, p.maxY - 74, 260, 50)) {
            back(e)
            return
        }
        if ui.input.wasPressed(e.settings.binding(for: .advancements)) && age > 0.1 { back(e) }
    }
}

/// "Advancement Made!" cards that slide in at the top right.
enum AdvancementToast {
    static func draw(_ ui: UIContext, engine e: GameEngine) {
        let d = ui.draw
        let W = ui.size.x
        var y: Float = 84
        for toast in e.advancementToasts.suffix(3) {
            let age = e.time - toast.time
            guard age >= 0, age < 5 else { continue }
            let slide = Float(max(0, min(1, min(age / 0.35, (5 - age) / 0.35))))
            let r = Rect(W - 16 - 330 * slide + 16 * (1 - slide) - (1 - slide) * 0, y, 330, 66)
            let card = Rect(r.x + (1 - slide) * 350, r.y, r.w, r.h)
            d.shadow(card, radius: 14, blur: 12, color: Color(linear: 0, 0, 0, 0.45), offset: 4)
            d.fill(card, Color(hex: 0x1A1230, alpha: 0.94), radius: 14)
            d.stroke(card, Theme.amber.alpha(0.65), radius: 14, width: 1.5)
            if let info = e.items.info(named: toast.def.icon) { d.itemIcon(info, Rect(card.x + 12, card.y + 13, 40, 40)) }
            d.text("Advancement Made!", x: card.x + 64, y: card.y + 12, size: 12.5, color: Theme.amber, face: .display, tracking: 0.04)
            d.text(toast.def.title, x: card.x + 64, y: card.y + 33, size: 16.5, color: Theme.text, face: .display, maxWidth: card.w - 76)
            y += 76
        }
    }
}
