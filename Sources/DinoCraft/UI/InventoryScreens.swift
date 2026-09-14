import AppKit
import simd
import DinoCraftCore

/// Shared drawing for item slots, tooltips and the carried ("cursor") stack.
enum SlotView {
    static let size: Float = 52
    static let gap: Float = 6

    @discardableResult
    static func draw(_ ui: UIContext, _ e: GameEngine, id: String, _ r: Rect, stack: ItemStack?,
                     accent: Bool = false, dim: Bool = false, showCount: Bool = true) -> Bool {
        let d = ui.draw
        let hover = ui.hoverSilent(id, r)
        let h = ui.anim(id + ".h", hover ? 1 : 0, speed: 22)
        d.fill(r, Color(hex: 0x0D0818, alpha: 0.62).mix(Color(hex: 0x3E2F66, alpha: 0.88), h * 0.7), radius: 9)
        d.stroke(r, accent ? Theme.amber.alpha(0.8) : Color(linear: 1, 1, 1, 0.07 + 0.3 * h), radius: 9, width: accent ? 1.8 : 1.1)
        if let stack, let info = e.items[stack.item] {
            let lift = h * 1.5
            d.itemIcon(info, r.inset(7).offset(0, -lift), alpha: dim ? 0.4 : 1)
            if showCount { countLabel(d, stack, r) }
            if let durability = info.maxDurability, stack.damage > 0 {
                let frac = 1 - Float(stack.damage) / Float(durability)
                let bar = Rect(r.x + 7, r.maxY - 7, r.w - 14, 3)
                d.fill(bar, Color(linear: 0, 0, 0, 0.7), radius: 1.5)
                d.fill(Rect(bar.x, bar.y, bar.w * frac, 3), Theme.danger.mix(Theme.jungle, frac), radius: 1.5)
            }
        }
        return hover
    }

    static func countLabel(_ d: UIRenderer, _ stack: ItemStack, _ r: Rect) {
        guard stack.count > 1 else { return }
        d.text("\(stack.count)", x: r.maxX - 5, y: r.maxY - 21, size: 14, color: .white, face: .display, align: .right,
               shadow: Color(linear: 0, 0, 0, 0.95))
    }

    static func tooltip(_ ui: UIContext, _ e: GameEngine, stack: ItemStack) {
        guard let info = e.items[stack.item] else { return }
        let d = ui.draw
        var lines: [(String, Color, Float, FontFace)] = [(info.displayName, Theme.text, 16, .display)]
        if let tool = info.tool {
            let tier = ["", "Wood", "Stone", "Iron", "Diamond"][max(0, min(4, tool.level))]
            lines.append(("\(tier) \(tool.kind.rawValue.capitalized)", Theme.textMuted, 13, .body))
            lines.append(("Durability \(tool.durability - stack.damage) / \(tool.durability)", Theme.textMuted, 13, .body))
        }
        if let armor = info.armor {
            lines.append(("+\(armor.protection) Armor · \(armor.slot.rawValue.capitalized)", Theme.teal, 13, .body))
            lines.append(("Durability \(armor.durability - stack.damage) / \(armor.durability)", Theme.textMuted, 13, .body))
        }
        if let food = info.food { lines.append(("Restores \(food.hunger) hunger", Theme.jungle, 13, .body)) }
        if let b = info.block, let bi = e.blocks[b] {
            if bi.emission > 0 { lines.append(("Emits light", Theme.amber, 13, .body)) }
            if bi.toolLevel > 0 { lines.append(("Needs a \(bi.tool.rawValue) to harvest", Theme.textMuted, 13, .body)) }
        }
        var w: Float = 0, h: Float = 14
        for l in lines {
            w = max(w, d.font.measure(l.0, size: l.2, face: l.3))
            h += l.2 * 1.45
        }
        w += 28
        var x = ui.mouse.x + 18, y = ui.mouse.y + 12
        if x + w > ui.size.x - 8 { x = ui.mouse.x - w - 12 }
        if y + h > ui.size.y - 8 { y = ui.size.y - h - 8 }
        let r = Rect(x, y, w, h)
        d.shadow(r, radius: 10, blur: 10, color: Color(linear: 0, 0, 0, 0.5), offset: 4)
        d.fill(r, Color(hex: 0x120B22, alpha: 0.96), radius: 10)
        d.stroke(r, Theme.amber.alpha(0.45), radius: 10, width: 1.2)
        var ly = y + 9
        for l in lines {
            d.text(l.0, x: x + 14, y: ly, size: l.2, color: l.1, face: l.3)
            ly += l.2 * 1.45
        }
    }

    static func cursor(_ ui: UIContext, _ e: GameEngine, _ stack: ItemStack?) {
        guard let stack, let info = e.items[stack.item] else { return }
        let r = Rect(ui.mouse.x - 27, ui.mouse.y - 27, 54, 54)
        ui.draw.fill(r.inset(6).offset(0, 6), Color(linear: 0, 0, 0, 0.3), radius: 10, blur: 6)
        ui.draw.itemIcon(info, r.inset(4))
        countLabel(ui.draw, stack, r)
    }
}

// MARK: - Survival inventory & crafting bench

final class InventoryScreen: Screen {
    let gridSize: Int
    let title: String
    private var grid: [ItemStack?]
    private var cursor: ItemStack?
    private var craftableOnly = false
    private var closed = false
    /// Rects of interactive elements from the last frame (used by automation scripts).
    private(set) var slotRects: [String: Rect] = [:]

    var isCraftingBench: Bool { gridSize == 3 }

    init(gridSize: Int, title: String) {
        self.gridSize = gridSize
        self.title = title
        grid = Array(repeating: nil, count: gridSize * gridSize)
    }

    override var scene: GameActivityState.Scene { .playing }
    override func back(_ engine: GameEngine) { close(engine) }

    /// Returns the grid contents and carried stack to the inventory (dropping any overflow).
    func close(_ e: GameEngine) {
        guard !closed else { return }
        closed = true
        if let s = e.session {
            for i in grid.indices {
                if let st = grid[i] { stash(st, s) }
                grid[i] = nil
            }
            if let c = cursor { stash(c, s) }
            cursor = nil
        }
        e.audio.play("ui_close", volume: 0.45)
        e.popScreen()
    }

    private func stash(_ stack: ItemStack, _ s: GameSession) {
        let left = s.inventory.add(stack)
        if left > 0 {
            var rest = stack
            rest.count = left
            s.dropStack(rest, thrown: false)
        }
    }

    private enum Ref { case inv(Int), grid(Int), armor(Int) }

    private func get(_ r: Ref, _ s: GameSession) -> ItemStack? {
        switch r {
        case .inv(let i): return s.inventory.slots[i]
        case .grid(let i): return grid[i]
        case .armor(let i): return s.armor[i]
        }
    }

    private func set(_ r: Ref, _ v: ItemStack?, _ s: GameSession) {
        switch r {
        case .inv(let i):
            s.inventory.slots[i] = v
            s.inventory.markChanged()
        case .grid(let i):
            grid[i] = v
        case .armor(let i):
            s.armor[i] = v
        }
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { return }
        slotRects.removeAll(keepingCapacity: true)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)

        let slot = SlotView.size, gap = SlotView.gap, step = slot + gap
        let rowW = 9 * slot + 8 * gap
        let pad: Float = 30
        let craftH = 3 * step - gap
        let panelW = rowW + pad * 2
        let panelH: Float = 78 + craftH + 36 + craftH + 18 + slot + pad
        let bookW: Float = 320, spacing: Float = 16
        let a = appear(0, duration: 0.22)
        let px = W / 2 - (panelW + spacing + bookW) / 2
        let py = H / 2 - panelH / 2 + (1 - a) * 12
        let panel = Rect(px, py, panelW, panelH)
        let book = Rect(panel.maxX + spacing, py, bookW, panelH)
        d.opacity = a
        ui.panel(panel, title: title)

        var hoveredStack: ItemStack?
        var hoveredRef: Ref?
        let top = py + 78

        // Crafting grid → output
        let gridW = Float(gridSize) * step - gap
        let outX = panel.maxX - pad - slot
        let gx = outX - 70 - gridW
        let gy = top + (craftH - gridW) / 2
        for row in 0..<gridSize {
            for col in 0..<gridSize {
                let i = row * gridSize + col
                let rect = Rect(gx + Float(col) * step, gy + Float(row) * step, slot, slot)
                slotRects["grid\(i)"] = rect
                if SlotView.draw(ui, e, id: "inv.grid\(i)", rect, stack: grid[i]) {
                    hoveredStack = grid[i]
                    hoveredRef = .grid(i)
                }
            }
        }
        let recipe = e.recipes.match(grid: grid, size: gridSize)
        let pulse: Float = recipe != nil ? Float(0.7 + 0.3 * sin(ui.time * 4)) : 0.3
        d.text("→", in: Rect(gx + gridW, top + craftH / 2 - 22, 70, 44), size: 36, color: Theme.amber.alpha(pulse), face: .display)
        let outRect = Rect(outX, top + craftH / 2 - slot / 2, slot, slot)
        slotRects["out"] = outRect
        if recipe != nil { d.fill(outRect.inset(-6), Theme.amber.alpha(0.3 * pulse), radius: 15, blur: 10) }
        let outHover = SlotView.draw(ui, e, id: "inv.out", outRect, stack: recipe?.result, accent: true)
        if outHover, let r = recipe { hoveredStack = r.result }

        // Explorer card
        let card = Rect(panel.x + pad, top, gx - panel.x - pad - 26, craftH)
        if card.w > 150 {
            d.fill(card, Color(linear: 1, 1, 1, 0.035), radius: 14)
            if let icon = e.iconTexture { d.image(icon, Rect(card.x + 14, card.y + 14, 60, 60)) }
            d.text(isCraftingBench ? "Workbench" : "Explorer", x: card.x + 88, y: card.y + 18, size: 19, color: Theme.text, face: .display, maxWidth: card.w - 96)
            if isCraftingBench {
                d.text(s.player.gameMode.displayName, x: card.x + 88, y: card.y + 46, size: 13.5, color: Theme.amber)
                let lines = ["Tools, lanterns and bone", "gear need the 3×3 grid.", "Pick a recipe from the book →"]
                for (i, line) in lines.enumerated() {
                    d.text(line, x: card.x + 16, y: card.y + 92 + Float(i) * 22, size: 13.5, color: Theme.textMuted, maxWidth: card.w - 28)
                }
            } else {
                d.text("\(s.player.gameMode.displayName) · Armor \(s.armorPoints)", x: card.x + 88, y: card.y + 46, size: 13.5, color: Theme.amber, maxWidth: card.w - 96)
                d.text("♥ \(Int(s.health))  ● \(Int(s.hunger))", x: card.x + 88, y: card.y + 66, size: 12.5, color: Theme.textMuted, maxWidth: card.w - 96)
                // Armor slots
                let aSlot = min(slot, (card.w - 32 - 3 * gap) / 4)
                let ay = min(card.y + 88, card.maxY - aSlot - 12)
                for i in 0..<4 {
                    let rect = Rect(card.x + 16 + Float(i) * (aSlot + gap), ay, aSlot, aSlot)
                    slotRects["armor\(i)"] = rect
                    if SlotView.draw(ui, e, id: "inv.armor\(i)", rect, stack: s.armor[i]) {
                        hoveredStack = s.armor[i]
                        hoveredRef = .armor(i)
                    }
                    if s.armor[i] == nil {
                        d.text(["Head", "Chest", "Legs", "Feet"][i], in: rect, size: 10.5, color: Theme.textMuted.alpha(0.55))
                    }
                }
            }
        }

        // Backpack and hotbar
        let storageY = top + craftH + 36
        d.text("BACKPACK", x: panel.x + pad, y: storageY - 22, size: 11.5, color: Theme.amber.alpha(0.8), face: .display, tracking: 0.14)
        for row in 0..<3 {
            for col in 0..<9 {
                let i = 9 + row * 9 + col
                let rect = Rect(panel.x + pad + Float(col) * step, storageY + Float(row) * step, slot, slot)
                slotRects["inv\(i)"] = rect
                if SlotView.draw(ui, e, id: "inv.slot\(i)", rect, stack: s.inventory.slots[i]) {
                    hoveredStack = s.inventory.slots[i]
                    hoveredRef = .inv(i)
                }
            }
        }
        let hotY = storageY + craftH + 18
        for col in 0..<9 {
            let rect = Rect(panel.x + pad + Float(col) * step, hotY, slot, slot)
            slotRects["inv\(col)"] = rect
            if SlotView.draw(ui, e, id: "inv.slot\(col)", rect, stack: s.inventory.slots[col], accent: col == s.inventory.selected) {
                hoveredStack = s.inventory.slots[col]
                hoveredRef = .inv(col)
            }
        }

        drawBook(ui, e, s, book)
        d.opacity = 1

        // Interaction
        let input = ui.input
        let shift = input.modifiers.contains(.shift)
        let left = input.buttonsPressed.contains(0), right = input.buttonsPressed.contains(1)
        if left || right {
            let button: SlotButton = left ? .left : .right
            if outHover {
                craftOutput(button: button, shift: shift, s, e)
            } else if let ref = hoveredRef {
                click(ref, button: button, shift: shift, s, e)
            } else if !panel.contains(ui.mouse) && !book.contains(ui.mouse), var c = cursor {
                var dropped = c
                dropped.count = button == .left ? c.count : 1
                c.count -= dropped.count
                cursor = c.count > 0 ? c : nil
                s.dropStack(dropped, thrown: true)
            }
        }
        if input.wasPressed(e.settings.binding(for: .drop)), let ref = hoveredRef, var st = get(ref, s) {
            let whole = input.modifiers.contains(.command) || input.modifiers.contains(.option)
            var dropped = st
            dropped.count = whole ? st.count : 1
            st.count -= dropped.count
            set(ref, st.count > 0 ? st : nil, s)
            s.dropStack(dropped, thrown: true)
        }
        if let ref = hoveredRef {
            for (i, code) in KeyCode.digits.enumerated() where input.keyPressed(code) {
                let other = get(.inv(i), s), mine = get(ref, s)
                set(.inv(i), mine, s)
                set(ref, other, s)
            }
        }
        if input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 {
            close(e)
            return
        }

        if cursor == nil, let st = hoveredStack { SlotView.tooltip(ui, e, stack: st) }
        SlotView.cursor(ui, e, cursor)
    }

    private func click(_ ref: Ref, button: SlotButton, shift: Bool, _ s: GameSession, _ e: GameEngine) {
        let inv = s.inventory
        if shift, let st = get(ref, s) {
            if case .inv = ref, let spec = e.items[st.item]?.armor, s.armor[spec.slot.index] == nil {
                s.armor[spec.slot.index] = st
                set(ref, nil, s)
                e.audio.play("place_metal", volume: 0.5)
                return
            }
            let targets: [Int]
            switch ref {
            case .inv(let i): targets = i < 9 ? Array(9..<36) : Array(0..<9)
            case .grid, .armor: targets = Array(9..<36) + Array(0..<9)
            }
            var slots = inv.slots
            let left = SlotInteraction.quickMove(st, into: &slots, indices: targets, maxStack: inv.maxStack)
            inv.slots = slots
            set(ref, left, s)
            inv.markChanged()
            e.audio.play("ui_toggle", volume: 0.3)
            return
        }
        // Armor slots only take the matching kind of armor.
        if case .armor(let i) = ref, let c = cursor, e.items[c.item]?.armor?.slot.index != i { return }
        var value = get(ref, s)
        SlotInteraction.click(&value, cursor: &cursor, button: button, maxStack: inv.maxStack)
        set(ref, value, s)
    }

    private func craftOutput(button: SlotButton, shift: Bool, _ s: GameSession, _ e: GameEngine) {
        guard let recipe = e.recipes.match(grid: grid, size: gridSize) else { return }
        let result = recipe.result
        let inv = s.inventory
        if shift {
            var crafted = 0
            while crafted < 64, let r = e.recipes.match(grid: grid, size: gridSize), r.result.item == result.item {
                var slots = inv.slots
                guard SlotInteraction.quickMove(r.result, into: &slots, indices: Array(0..<36), maxStack: inv.maxStack) == nil else { break }
                inv.slots = slots
                RecipeRegistry.consumeIngredients(grid: &grid)
                crafted += 1
            }
            if crafted > 0 {
                inv.markChanged()
                e.audio.play("craft", volume: 0.6)
                s.noteCrafted(result.item, count: result.count)
                Log.info("Crafted \(crafted * result.count)× \(e.items[result.item]?.name ?? "?") (shift)", category: "Game")
            }
            return
        }
        if let c = cursor {
            guard c.canStack(with: result), c.count + result.count <= inv.maxStack(c.item) else { return }
            cursor?.count += result.count
        } else {
            cursor = result
        }
        RecipeRegistry.consumeIngredients(grid: &grid)
        e.audio.play("craft", volume: 0.6)
        s.noteCrafted(result.item, count: result.count)
        Log.info("Crafted \(result.count)× \(e.items[result.item]?.name ?? "?")", category: "Game")
    }

    // MARK: Recipe book

    private func ingredients(_ r: Recipe) -> [Ingredient] {
        switch r.kind {
        case .shaped(_, _, let cells): return cells.compactMap { $0 }
        case .shapeless(let list): return list
        }
    }

    private func summary(_ r: Recipe) -> [(ItemID, Int)] {
        var order: [ItemID] = [], counts: [ItemID: Int] = [:]
        for ing in ingredients(r) {
            let id = ing.displayItem
            if counts[id] == nil { order.append(id) }
            counts[id, default: 0] += 1
        }
        return order.map { ($0, counts[$0]!) }
    }

    private func pool(_ s: GameSession) -> [ItemID: Int] {
        var p: [ItemID: Int] = [:]
        for st in s.inventory.slots + grid {
            if let st, st.damage == 0 { p[st.item, default: 0] += st.count }
        }
        return p
    }

    private func canCraft(_ r: Recipe, pool: [ItemID: Int]) -> Bool {
        var p = pool
        let list = ingredients(r)
        let ordered = list.filter { if case .item = $0 { return true } else { return false } }
            + list.filter { if case .tag = $0 { return true } else { return false } }
        for ing in ordered {
            guard let id = p.first(where: { $0.value > 0 && ing.matches($0.key) })?.key else { return false }
            p[id]! -= 1
        }
        return true
    }

    private func drawBook(_ ui: UIContext, _ e: GameEngine, _ s: GameSession, _ r: Rect) {
        let d = ui.draw
        ui.panel(r)
        d.text("Recipe Book", x: r.x + 22, y: r.y + 22, size: 22, color: Theme.text, face: .display)
        var only = craftableOnly
        if ui.toggle("book.only", "Craftable only", Rect(r.x + 14, r.y + 62, r.w - 28, 44), &only) { craftableOnly = only }

        let available = pool(s)
        var entries = e.recipes.recipes.filter { $0.requiredGridSize <= gridSize }.map { ($0, canCraft($0, pool: available)) }
        if craftableOnly { entries = entries.filter { $0.1 } }
        entries.sort { a, b in
            if a.1 != b.1 { return a.1 }
            return (e.items[a.0.result.item]?.displayName ?? "") < (e.items[b.0.result.item]?.displayName ?? "")
        }

        let list = Rect(r.x + 14, r.y + 118, r.w - 28, r.h - 132)
        let rowH: Float = 58, rowGap: Float = 6
        let content = Float(entries.count) * (rowH + rowGap)
        let offset = ui.beginScroll("book.\(gridSize)", list, contentHeight: content)
        if entries.isEmpty {
            d.text("Gather materials to unlock recipes.", in: Rect(list.x, list.y + 10, list.w, 40), size: 14, color: Theme.textMuted)
        }
        for (i, (recipe, ok)) in entries.enumerated() {
            let row = Rect(list.x, list.y + Float(i) * (rowH + rowGap) - offset, list.w - 10, rowH)
            guard row.maxY > list.y, row.y < list.maxY, let info = e.items[recipe.result.item] else { continue }
            slotRects["recipe:\(recipe.id)"] = row
            let id = "book.row.\(recipe.id)"
            let hover = ui.hoverSilent(id, row)
            let h = ui.anim(id, hover ? 1 : 0, speed: 20)
            d.fill(row, Color(linear: 1, 1, 1, 0.03 + 0.06 * h), radius: 12)
            if hover { d.stroke(row, Theme.amber.alpha(ok ? 0.6 : 0.25), radius: 12, width: 1.2) }
            let alpha: Float = ok ? 1 : 0.38
            d.itemIcon(info, Rect(row.x + 8, row.y + 9, 40, 40), alpha: alpha)
            let name = info.displayName + (recipe.result.count > 1 ? "  ×\(recipe.result.count)" : "")
            d.text(name, x: row.x + 58, y: row.y + 8, size: 15, color: Theme.text.alpha(alpha), face: .display, maxWidth: row.w - 64)
            var x = row.x + 58
            for (item, count) in summary(recipe) {
                guard let ii = e.items[item], x < row.maxX - 40 else { break }
                d.itemIcon(ii, Rect(x, row.y + 32, 20, 20), alpha: alpha)
                d.text("\(count)", x: x + 22, y: row.y + 35, size: 12, color: Theme.textMuted.alpha(alpha))
                x += 44
            }
            if hover && ui.input.buttonsPressed.contains(0) {
                if ok {
                    autofill(recipe, s, e)
                } else {
                    e.showToast("Missing ingredients for \(info.displayName)")
                    e.audio.play("ui_back", volume: 0.4)
                }
            }
        }
        ui.endScroll("book.\(gridSize)", list, contentHeight: content)
    }

    /// Moves one set of a recipe's ingredients from the inventory into the grid.
    /// Clicking again adds another set on top.
    private func autofill(_ recipe: Recipe, _ s: GameSession, _ e: GameEngine) {
        let inv = s.inventory
        let same = e.recipes.match(grid: grid, size: gridSize)?.id == recipe.id
        if !same {
            for i in grid.indices {
                guard let st = grid[i] else { continue }
                let left = inv.add(st)
                if left > 0 {
                    var rest = st
                    rest.count = left
                    grid[i] = rest
                    e.showToast("Inventory full")
                    return
                }
                grid[i] = nil
            }
        }
        var cells: [(Int, Ingredient)] = []
        switch recipe.kind {
        case .shaped(let w, let h, let ings):
            for row in 0..<h { for col in 0..<w { if let ing = ings[row * w + col] { cells.append((row * gridSize + col, ing)) } } }
        case .shapeless(let list):
            for (i, ing) in list.enumerated() { cells.append((i, ing)) }
        }
        var taken: [(Int, ItemID)] = []
        func rollback() {
            for (cell, item) in taken {
                if var st = grid[cell] {
                    st.count -= 1
                    grid[cell] = st.count > 0 ? st : nil
                }
                inv.add(ItemStack(item: item, count: 1))
            }
        }
        for (cell, ing) in cells {
            let existing = grid[cell]
            let index = inv.slots.indices.first { i in
                guard let st = inv.slots[i], st.damage == 0 else { return false }
                if let existing { return st.item == existing.item && existing.count < inv.maxStack(existing.item) }
                return ing.matches(st.item)
            }
            guard let index, var st = inv.slots[index] else {
                rollback()
                e.showToast("Not enough ingredients")
                return
            }
            let item = st.item
            st.count -= 1
            inv.slots[index] = st.count > 0 ? st : nil
            if var g = grid[cell] { g.count += 1; grid[cell] = g } else { grid[cell] = ItemStack(item: item, count: 1) }
            taken.append((cell, item))
        }
        inv.markChanged()
        e.audio.play("ui_click", volume: 0.4)
    }
}

// MARK: - Creative inventory

final class CreativeInventoryScreen: Screen {
    private var tab = 0
    private var search = ""
    private var cursor: ItemStack?
    private(set) var slotRects: [String: Rect] = [:]

    static let natureNames: Set<String> = [
        "grass", "dirt", "sand", "gravel", "log", "leaves", "tall_grass", "fern", "emberbloom", "sunpetal", "snowy_grass",
        "snow", "clay", "ice", "dead_bush", "redwood_log", "redwood_needles", "mud", "coal_ore", "iron_ore", "gold_ore",
        "diamond_ore", "amber_ore", "fossil_stone", "bedrock", "stone",
        "blue_bloom", "white_daisy", "pink_petal", "red_mushroom", "brown_mushroom", "glow_mushroom", "cattail", "horsetail",
        "stalagmite", "cactus", "lily_pad", "pebbles", "moss_block", "dry_grass", "marble", "slate", "red_rock", "palm_log",
        "palm_fronds", "packed_ice", "berry_bush", "emerald_ore", "basalt", "ash", "magma_rock", "obsidian", "sky_grass", "sky_soil", "cloud",
    ]

    override var scene: GameActivityState.Scene { .playing }
    override func back(_ engine: GameEngine) { close(engine) }

    private func close(_ e: GameEngine) {
        if let c = cursor, let s = e.session { s.inventory.add(c) }
        cursor = nil
        e.audio.play("ui_close", volume: 0.45)
        e.popScreen()
    }

    private func palette(_ e: GameEngine) -> [ItemInfo] {
        let all = e.items.all
        switch tab {
        case 0: return all.filter { $0.block != nil && !Self.natureNames.contains($0.name) }
        case 1: return all.filter { Self.natureNames.contains($0.name) }
        case 2: return all.filter { $0.block == nil && !$0.name.hasPrefix("spawn_egg_") }
        case 3: return all.filter { $0.name.hasPrefix("spawn_egg_") }
        default:
            let q = search.lowercased().trimmingCharacters(in: .whitespaces)
            return q.isEmpty ? all : all.filter { $0.displayName.lowercased().contains(q) || $0.name.contains(q) }
        }
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { return }
        slotRects.removeAll(keepingCapacity: true)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        ui.dim(0.5)
        let slot = SlotView.size, step = SlotView.size + SlotView.gap
        let rowW = 9 * slot + 8 * SlotView.gap
        let pad: Float = 30
        let panelW = rowW + step + pad * 2
        let panelH = min(H - 40, 680)
        let a = appear(0, duration: 0.22)
        let panel = Rect(W / 2 - panelW / 2, H / 2 - panelH / 2 + (1 - a) * 12, panelW, panelH)
        d.opacity = a
        ui.panel(panel, title: "Creative Inventory")

        let previousTab = tab
        ui.segmented("creative.tab", Rect(panel.x + pad, panel.y + 76, panel.w - pad * 2, 44),
                     options: ["Building", "Nature", "Items & Tools", "Spawn Eggs", "Search"], selected: &tab)
        if tab != previousTab {
            ui.resetScroll("creative.palette")
            ui.focusedID = tab == 4 ? "creative.search" : nil
        }
        var paletteTop = panel.y + 134
        if tab == 4 {
            ui.textField("creative.search", Rect(panel.x + pad, paletteTop, panel.w - pad * 2, 46), &search, placeholder: "Search items…", maxLength: 24)
            paletteTop += 58
        }

        let hotY = panel.maxY - pad - slot
        let area = Rect(panel.x + pad, paletteTop, panel.w - pad * 2, hotY - 24 - paletteTop)
        let items = palette(e)
        let columns = 10
        let rows = (items.count + columns - 1) / columns
        let content = Float(rows) * step
        let offset = ui.beginScroll("creative.palette", area, contentHeight: content)
        var hoveredStack: ItemStack?
        var paletteHover: ItemInfo?
        for (i, info) in items.enumerated() {
            let rect = Rect(area.x + Float(i % columns) * step, area.y + Float(i / columns) * step - offset, slot, slot)
            guard rect.maxY > area.y, rect.y < area.maxY else { continue }
            slotRects["palette:\(info.name)"] = rect
            if SlotView.draw(ui, e, id: "creative.item.\(info.name)", rect, stack: ItemStack(item: info.id, count: 1), showCount: false) {
                paletteHover = info
                hoveredStack = ItemStack(item: info.id, count: 1)
            }
        }
        ui.endScroll("creative.palette", area, contentHeight: content)
        if items.isEmpty {
            d.text("No items match “\(search)”", in: Rect(area.x, area.y + 20, area.w, 40), size: 15, color: Theme.textMuted)
        }

        var hotHover: Int?
        for col in 0..<9 {
            let rect = Rect(panel.x + pad + Float(col) * step, hotY, slot, slot)
            slotRects["inv\(col)"] = rect
            if SlotView.draw(ui, e, id: "creative.hot\(col)", rect, stack: s.inventory.slots[col], accent: col == s.inventory.selected) {
                hotHover = col
                hoveredStack = s.inventory.slots[col]
            }
        }
        let trash = Rect(panel.x + pad + 9 * step, hotY, slot, slot)
        slotRects["trash"] = trash
        let trashHover = SlotView.draw(ui, e, id: "creative.trash", trash, stack: nil)
        d.text("×", in: trash, size: 22, color: Theme.danger.alpha(trashHover ? 1 : 0.6), face: .display)
        d.opacity = 1

        let input = ui.input
        let shift = input.modifiers.contains(.shift)
        let leftClick = input.buttonsPressed.contains(0), rightClick = input.buttonsPressed.contains(1)
        if leftClick || rightClick {
            if let info = paletteHover {
                if cursor != nil {
                    cursor = nil
                } else if shift {
                    s.inventory.add(ItemStack(item: info.id, count: info.maxStack))
                } else {
                    cursor = ItemStack(item: info.id, count: leftClick ? info.maxStack : 1)
                }
                e.audio.play("ui_toggle", volume: 0.25)
            } else if let col = hotHover {
                if shift {
                    s.inventory.slots[col] = nil
                } else {
                    var value = s.inventory.slots[col]
                    SlotInteraction.click(&value, cursor: &cursor, button: leftClick ? .left : .right, maxStack: s.inventory.maxStack)
                    s.inventory.slots[col] = value
                }
                s.inventory.markChanged()
            } else if trashHover {
                cursor = nil
                e.audio.play("ui_back", volume: 0.4)
            } else if !panel.contains(ui.mouse), let c = cursor {
                s.dropStack(c, thrown: true)
                cursor = nil
            }
        }
        if ui.focusedID != "creative.search" && input.wasPressed(e.settings.binding(for: .inventory)) && age > 0.1 {
            close(e)
            return
        }
        if cursor == nil, let st = hoveredStack { SlotView.tooltip(ui, e, stack: st) }
        SlotView.cursor(ui, e, cursor)
    }
}
