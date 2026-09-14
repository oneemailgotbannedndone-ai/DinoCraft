import AppKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Trading with a villager: each offer swaps items from the inventory for goods.
final class TradeScreen: Screen {
    let mob: Mob

    init(mob: Mob) { self.mob = mob }

    override var scene: GameActivityState.Scene { .playing }

    override func back(_ engine: GameEngine) {
        engine.audio.play("ui_close", volume: 0.45)
        engine.popScreen()
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session, !mob.isDying, !mob.removed, simd_distance(mob.position, s.player.position) < 8 else {
            back(e)
            return
        }
        let profession = VillagerProfession.of(mob)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)
        let rowH: Float = 64, gap: Float = 10
        let pw: Float = 600
        let ph: Float = 150 + Float(profession.trades.count) * (rowH + gap) + 30
        let a = appear(0, duration: 0.22)
        let panel = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 12, pw, ph)
        d.opacity = a
        ui.panel(panel, title: profession.name)
        d.text(profession.blurb, x: panel.midX, y: panel.y + 70, size: 14, color: Theme.textMuted, align: .center)

        for (i, t) in profession.trades.enumerated() {
            guard let cost = e.items.info(named: t.cost), let result = e.items.info(named: t.result) else { continue }
            let row = Rect(panel.x + 30, panel.y + 104 + Float(i) * (rowH + gap), pw - 60, rowH)
            let ok = s.inventory.count(of: cost.id) >= t.costCount
            d.fill(row, Color(linear: 1, 1, 1, 0.04), radius: 12)
            d.itemIcon(cost, Rect(row.x + 14, row.y + 12, 40, 40), alpha: ok ? 1 : 0.45)
            d.text("×\(t.costCount)", x: row.x + 60, y: row.y + 21, size: 16, color: ok ? Theme.text : Theme.danger, face: .display)
            d.text("→", x: row.x + 112, y: row.y + 12, size: 28, color: Theme.amber, face: .display)
            d.itemIcon(result, Rect(row.x + 156, row.y + 12, 40, 40))
            d.text("×\(t.resultCount)  \(result.displayName)", x: row.x + 204, y: row.y + 21, size: 15, color: Theme.text, maxWidth: row.w - 340)
            if ui.button("trade.\(i)", "Trade", Rect(row.maxX - 124, row.y + 10, 112, rowH - 20), enabled: ok) {
                perform(i, e)
            }
        }
        let emeralds = e.items.id(named: "emerald").map { s.inventory.count(of: $0) } ?? 0
        d.text("You have \(emeralds) emerald\(emeralds == 1 ? "" : "s")", x: panel.midX, y: panel.maxY - 38, size: 14,
               color: Theme.jungle, face: .display, align: .center)
        d.opacity = 1
        if ui.input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 { back(e) }
    }

    @discardableResult
    func perform(_ index: Int, _ e: GameEngine) -> Bool {
        guard let s = e.session else { return false }
        let trades = VillagerProfession.of(mob).trades
        guard trades.indices.contains(index) else { return false }
        let t = trades[index]
        guard let cost = e.items.id(named: t.cost), let result = e.items.id(named: t.result) else { return false }
        let inv = s.inventory
        guard inv.count(of: cost) >= t.costCount else {
            e.showToast("You need \(t.costCount) \(e.items[cost]?.displayName ?? t.cost)")
            e.audio.play("ui_back", volume: 0.4)
            return false
        }
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
        e.audio.play("craft", volume: 0.6)
        s.advancements.record("trade", t.result)
        Log.info("Traded \(t.costCount)× \(t.cost) for \(t.resultCount)× \(t.result) with a \(VillagerProfession.of(mob).name)", category: "Game")
        return true
    }
}
