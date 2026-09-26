import AppKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Chest and furnace UI: the container's slots above the player's backpack and hotbar. Two chests
/// side by side open together as one 54-slot Large Chest.
final class ContainerScreen: Screen {
    let pos: BlockPos
    let kind: ContainerKind
    /// The chests shown (both halves of a double chest) and, for a double chest, the combined
    /// 54-slot view the screen edits. Refreshed every frame.
    private var halves: [BlockPos] = []
    private var parts: [Container] = []
    private var combined: Container?

    /// Copies a double chest's combined slots back into its two halves.
    private func syncHalves() {
        guard let combined, parts.count > 1 else { return }
        for (n, part) in parts.enumerated() {
            part.slots = Array(combined.slots[(n * ChestHalves.size)..<((n + 1) * ChestHalves.size)])
        }
    }
    private var cursor: ItemStack?
    private var closed = false
    private(set) var slotRects: [String: Rect] = [:]

    init(pos: BlockPos, kind: ContainerKind) {
        self.pos = pos
        self.kind = kind
    }

    override var scene: GameActivityState.Scene { .playing }
    override func back(_ engine: GameEngine) { close(engine) }

    func close(_ e: GameEngine) {
        guard !closed else { return }
        closed = true
        if let c = cursor, let s = e.session {
            let left = s.inventory.add(c)
            if left > 0 { s.dropStack(ItemStack(item: c.item, count: left, damage: c.damage), thrown: false) }
        }
        cursor = nil
        e.audio.play("ui_close", volume: 0.45)
        e.popScreen()
    }

    private enum Ref { case inv(Int), box(Int) }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { return }
        guard s.variants.containerKind(s.world.block(pos)) == kind else {
            close(e)
            return
        }
        // A double chest is shown (and edited) as one container, then split back into its halves.
        halves = kind == .chest ? s.chestHalves(pos) : [pos]
        parts = halves.map { s.containers.ensure($0, kind: kind) }
        let container: Container
        if parts.count > 1 {
            container = combined ?? Container(kind: .chest)
            container.slots = parts.flatMap { $0.slots }
            combined = container
        } else {
            container = parts[0]
            combined = nil
        }
        defer { syncHalves() }
        slotRects.removeAll(keepingCapacity: true)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)

        let slot = SlotView.size, gap = SlotView.gap, step = slot + gap
        let rowW = 9 * slot + 8 * gap
        let pad: Float = 30
        let rows = kind == .chest ? container.slots.count / 9 : 3
        let topH: Float = Float(rows) * step - gap
        let panelW = rowW + pad * 2
        let panelH: Float = 78 + topH + 36 + (3 * step - gap) + 18 + slot + pad
        let a = appear(0, duration: 0.22)
        let panel = Rect(W / 2 - panelW / 2, H / 2 - panelH / 2 + (1 - a) * 12, panelW, panelH)
        d.opacity = a
        ui.panel(panel, title: kind == .chest ? ChestHalves.title(halves) : kind.displayName)

        var hoveredStack: ItemStack?
        var hoveredRef: Ref?
        var outputHover = false
        let top = panel.y + 78

        if kind == .chest {
            for row in 0..<rows {
                for col in 0..<9 {
                    let i = row * 9 + col
                    let rect = Rect(panel.x + pad + Float(col) * step, top + Float(row) * step, slot, slot)
                    slotRects["c\(i)"] = rect
                    if SlotView.draw(ui, e, id: "box.\(i)", rect, stack: container.slots[i]) {
                        hoveredStack = container.slots[i]
                        hoveredRef = .box(i)
                    }
                }
            }
        } else {
            let cx = panel.midX
            let inRect = Rect(cx - 150, top, slot, slot)
            let fuelRect = Rect(cx - 150, top + 2 * step, slot, slot)
            let outRect = Rect(cx + 70, top + step - 8, slot + 16, slot + 16)
            slotRects["c0"] = inRect; slotRects["c1"] = fuelRect; slotRects["c2"] = outRect
            if SlotView.draw(ui, e, id: "box.0", inRect, stack: container.slots[0]) { hoveredStack = container.slots[0]; hoveredRef = .box(0) }
            if SlotView.draw(ui, e, id: "box.1", fuelRect, stack: container.slots[1]) { hoveredStack = container.slots[1]; hoveredRef = .box(1) }
            outputHover = SlotView.draw(ui, e, id: "box.2", outRect, stack: container.slots[2], accent: true)
            if outputHover { hoveredStack = container.slots[2] }

            // Flame (fuel remaining)
            let flame = Rect(inRect.x + 10, inRect.maxY + 12, slot - 20, step - 24 + gap)
            let burn = container.burnTotal > 0 ? Float(container.burnLeft / container.burnTotal) : 0
            d.fill(flame, Color(linear: 1, 1, 1, 0.06), radius: 6)
            if burn > 0 {
                let h = flame.h * burn
                d.fill(Rect(flame.x, flame.maxY - h, flame.w, h), Theme.amber.mix(Theme.danger, 1 - burn), radius: 6)
            }
            // Progress arrow
            let bar = Rect(cx - 70, top + step + slot / 2 - 8, 120, 16)
            let progress = container.cookTotal > 0 ? Float(min(1, container.cook / container.cookTotal)) : 0
            d.fill(bar, Color(linear: 1, 1, 1, 0.07), radius: 8)
            if progress > 0 { d.fill(Rect(bar.x, bar.y, bar.w * progress, bar.h), Theme.amber, radius: 8) }
            d.text("→", x: bar.maxX + 4, y: bar.y - 12, size: 28, color: Theme.amber.alpha(progress > 0 ? 1 : 0.4), face: .display)
            let status = container.isBurning ? "Smelting…" : (container.slots[0] == nil ? "Add something to smelt" : "Add fuel below")
            d.text(status, x: cx - 70, y: top + 2 * step + 14, size: 13.5, color: Theme.textMuted)
        }

        let storageY = top + topH + 36
        d.text("BACKPACK", x: panel.x + pad, y: storageY - 22, size: 11.5, color: Theme.amber.alpha(0.8), face: .display, tracking: 0.14)
        for row in 0..<3 {
            for col in 0..<9 {
                let i = 9 + row * 9 + col
                let rect = Rect(panel.x + pad + Float(col) * step, storageY + Float(row) * step, slot, slot)
                slotRects["inv\(i)"] = rect
                if SlotView.draw(ui, e, id: "cinv.slot\(i)", rect, stack: s.inventory.slots[i]) {
                    hoveredStack = s.inventory.slots[i]
                    hoveredRef = .inv(i)
                }
            }
        }
        let hotY = storageY + 3 * step - gap + 18
        for col in 0..<9 {
            let rect = Rect(panel.x + pad + Float(col) * step, hotY, slot, slot)
            slotRects["inv\(col)"] = rect
            if SlotView.draw(ui, e, id: "cinv.slot\(col)", rect, stack: s.inventory.slots[col], accent: col == s.inventory.selected) {
                hoveredStack = s.inventory.slots[col]
                hoveredRef = .inv(col)
            }
        }
        d.opacity = 1

        let input = ui.input
        let shift = input.modifiers.contains(.shift)
        let left = input.buttonsPressed.contains(0), right = input.buttonsPressed.contains(1)
        if left || right {
            if outputHover {
                takeOutput(container, shift: shift, s, e)
            } else if let ref = hoveredRef {
                click(ref, button: left ? .left : .right, shift: shift, container, s, e)
            } else if !panel.contains(ui.mouse), var c = cursor {
                var dropped = c
                dropped.count = left ? c.count : 1
                c.count -= dropped.count
                cursor = c.count > 0 ? c : nil
                s.dropStack(dropped, thrown: true)
            }
        }
        if input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 {
            close(e)
            return
        }
        if cursor == nil, let st = hoveredStack { SlotView.tooltip(ui, e, stack: st) }
        SlotView.cursor(ui, e, cursor)
    }

    private func changed(_ s: GameSession, _ e: GameEngine) {
        s.inventory.markChanged()
        syncHalves()
        for half in halves { s.containerChanged(half) }
    }

    private func click(_ ref: Ref, button: SlotButton, shift: Bool, _ c: Container, _ s: GameSession, _ e: GameEngine) {
        let inv = s.inventory
        if shift {
            switch ref {
            case .box(let i):
                guard let st = c.slots[i] else { return }
                var slots = inv.slots
                c.slots[i] = SlotInteraction.quickMove(st, into: &slots, indices: Array(9..<36) + Array(0..<9), maxStack: inv.maxStack)
                inv.slots = slots
            case .inv(let i):
                guard let st = inv.slots[i] else { return }
                var targets = Array(0..<c.slots.count)
                if kind == .furnace {
                    if e.smelting.recipe(for: st.item) != nil { targets = [Container.furnaceInput] }
                    else if e.smelting.burnTime(st.item) != nil { targets = [Container.furnaceFuel] }
                    else { return }
                }
                inv.slots[i] = SlotInteraction.quickMove(st, into: &c.slots, indices: targets, maxStack: inv.maxStack)
            }
            e.audio.play("ui_toggle", volume: 0.3)
            changed(s, e)
            return
        }
        switch ref {
        case .box(let i):
            var value = c.slots[i]
            SlotInteraction.click(&value, cursor: &cursor, button: button, maxStack: inv.maxStack)
            c.slots[i] = value
        case .inv(let i):
            var value = inv.slots[i]
            SlotInteraction.click(&value, cursor: &cursor, button: button, maxStack: inv.maxStack)
            inv.slots[i] = value
        }
        changed(s, e)
    }

    private func takeOutput(_ c: Container, shift: Bool, _ s: GameSession, _ e: GameEngine) {
        guard let out = c.slots[Container.furnaceOutput] else { return }
        let inv = s.inventory
        if shift {
            var slots = inv.slots
            c.slots[Container.furnaceOutput] = SlotInteraction.quickMove(out, into: &slots, indices: Array(0..<36), maxStack: inv.maxStack)
            inv.slots = slots
        } else if let held = cursor {
            guard held.canStack(with: out), held.count + out.count <= inv.maxStack(held.item) else { return }
            cursor?.count += out.count
            c.slots[Container.furnaceOutput] = nil
        } else {
            cursor = out
            c.slots[Container.furnaceOutput] = nil
        }
        if let name = e.items[out.item]?.name { s.advancements.record("smelt", name, amount: out.count) }
        e.audio.play("pickup", volume: 0.35)
        changed(s, e)
    }
}
