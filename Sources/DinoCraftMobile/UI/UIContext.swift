import UIKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// DinoCraft's look: like working at a crafting table. Oak planks in a dark walnut frame,
/// honey-gold for the main actions and cream lettering.
enum Theme {
    static let deep = Color(hex: 0x1E120A)
    static let panelTop = Color(hex: 0x86592F, alpha: 0.98)
    static let panelBottom = Color(hex: 0x6A4424, alpha: 0.98)
    static let frame = Color(hex: 0x3A2212)
    static let plankSeam = Color(hex: 0x4A2C14)
    static let grain = Color(hex: 0x70461F)
    static let iron = Color(hex: 0x6E6E78)
    static let amber = Color(hex: 0xF4B44A)
    static let amberDeep = Color(hex: 0xC8742A)
    static let jungle = Color(hex: 0x6CC45E)
    static let teal = Color(hex: 0x3FC1B0)
    static let text = Color(hex: 0xFBF2DE)
    static let textMuted = Color(hex: 0xE2CDA6)
    static let textDark = Color(hex: 0x2A1608)
    static let danger = Color(hex: 0xE5484D)
    static let field = Color(hex: 0x24150A, alpha: 0.85)
}

enum UISound { case hover, click, back, toggle }

enum ButtonStyle { case primary, secondary, danger, ghost }

/// Immediate-mode widget toolkit. Screens call widget functions every frame;
/// the context tracks hover/active/focus state and eased animation values by id.
/// Layout uses a virtual canvas (~1280×800) scaled to the window.
final class UIContext {
    let draw: UIRenderer
    let input: Input
    var onSound: ((UISound) -> Void)?

    private(set) var size = SIMD2<Float>(1280, 800)
    private(set) var scale: Float = 1
    private(set) var dt: Float = 0
    private(set) var time: Double = 0

    private var hotThisFrame: String?
    private var hotLastFrame: String?
    private var activeID: String?
    var focusedID: String?
    var modalActive = false
    private var anims: [String: Float] = [:]
    private var scrollTargets: [String: Float] = [:]
    private var clipStack: [Rect] = []
    private var pointer = false
    private var textCursor = false

    var mouse: SIMD2<Float> { input.mouse / scale }
    var mouseDown: Bool { input.buttonsDown.contains(0) }
    var mousePressed: Bool { input.buttonsPressed.contains(0) }
    var mouseReleased: Bool { input.buttonsReleased.contains(0) }

    init(draw: UIRenderer, input: Input) {
        self.draw = draw
        self.input = input
    }

    func begin(viewSize: SIMD2<Float>, backingScale: Float, guiScale: Float, dt: Double, time: Double) {
        // Phones are short in landscape: lay menus out on a canvas about 600 tall (the Mac's is 800),
        // so the text stays big enough to read and tap.
        let fit = min(viewSize.x / 1100, viewSize.y / 600)
        scale = max(0.45, min(1.8, fit)) * Float(guiScale)
        size = viewSize / scale
        self.dt = Float(dt)
        self.time = time
        draw.begin(size: size, scale: backingScale * scale)
        hotLastFrame = hotThisFrame
        hotThisFrame = nil
        pointer = false
        textCursor = false
        clipStack.removeAll()
        modalActive = false
    }

    func end() {
        if !mouseDown { activeID = nil }
        _ = textCursor
        _ = pointer
    }

    // MARK: State helpers

    func anim(_ id: String, _ target: Float, speed: Float = 14) -> Float {
        let current = anims[id] ?? target
        let next = current + (target - current) * (1 - exp(-speed * dt))
        anims[id] = abs(next - target) < 0.0005 ? target : next
        return anims[id]!
    }

    func setAnim(_ id: String, _ value: Float) { anims[id] = value }

    private func canInteract(_ id: String) -> Bool { !modalActive || id.hasPrefix("modal.") }

    func hovered(_ id: String, _ r: Rect) -> Bool {
        guard canInteract(id), !input.mouseCaptured, r.contains(mouse) else { return false }
        if let clip = clipStack.last, !clip.contains(mouse) { return false }
        guard activeID == nil || activeID == id else { return false }
        hotThisFrame = id
        pointer = true
        if hotLastFrame != id { onSound?(.hover) }
        return true
    }

    /// Hover test without sound (inventory slots, list rows).
    func hoverSilent(_ id: String, _ r: Rect) -> Bool {
        guard canInteract(id), !input.mouseCaptured, r.contains(mouse) else { return false }
        if let clip = clipStack.last, !clip.contains(mouse) { return false }
        hotThisFrame = id
        pointer = true
        return true
    }

    // MARK: Containers

    /// A crafting-table panel: oak planks with grain and joints in a dark walnut frame, iron nails
    /// in the corners and the title carved into a board across the top.
    func panel(_ r: Rect, title: String? = nil, radius: Float = 22) {
        let corner: Float = 8
        draw.shadow(r, radius: corner, blur: 26, color: Color(linear: 0, 0, 0, 0.55), offset: 12)
        draw.fill(r, Theme.frame, radius: corner)
        let inner = r.inset(min(9, max(0, min(r.w, r.h) / 2 - 1)))
        draw.fill(inner, Theme.panelTop, radius: 3, bottom: Theme.panelBottom)
        // Boards, with seams, grain streaks and staggered joints (placed the same way every frame)
        let plank: Float = 46
        var y = inner.y + plank
        while y < inner.maxY - 4 {
            draw.fill(Rect(inner.x, y - 1, inner.w, 2), Theme.plankSeam)
            draw.fill(Rect(inner.x, y + 1, inner.w, 1), Color(linear: 1, 0.8, 0.5, 0.08))
            y += plank
        }
        for board in 0..<max(0, Int(inner.h / plank) + 1) {
            let top = inner.y + Float(board) * plank
            var x = inner.x + Float((board * 37) % 60)
            var k = 0
            while x < inner.maxX - 40 {
                let len = Float(22 + (board * 13 + k * 7) % 34)
                let gy = top + plank * (0.3 + Float((board + k) % 3) * 0.18)
                if gy < inner.maxY - 3 { draw.fill(Rect(x, gy, len, 1.5), Theme.grain.alpha(0.55)) }
                x += Float(70 + (board * 11 + k * 17) % 60)
                k += 1
            }
            if board % 2 == 1 && top + plank <= inner.maxY {
                let jx = inner.x + inner.w * (board % 4 == 1 ? 0.37 : 0.66)
                draw.fill(Rect(jx, top + 1, 2, plank - 2), Theme.plankSeam)
            }
        }
        draw.stroke(inner, Color(linear: 0, 0, 0, 0.45), radius: 3, width: 2)
        draw.stroke(r, Color(linear: 1, 0.75, 0.45, 0.16), radius: corner, width: 1.5)
        for p in [SIMD2(r.x + 5, r.y + 5), SIMD2(r.maxX - 5, r.y + 5), SIMD2(r.x + 5, r.maxY - 5), SIMD2(r.maxX - 5, r.maxY - 5)] {
            draw.circle(center: p, radius: 3, Theme.iron)
            draw.circle(center: p - SIMD2(0.8, 0.8), radius: 1.2, Color(hex: 0xB8B8C2))
        }
        if let title {
            // The title on a darker board, like a carved sign
            let sign = Rect(inner.x, inner.y, inner.w, 62)
            draw.fill(sign, Color(hex: 0x5A361A, alpha: 0.9), radius: 3)
            draw.fill(Rect(sign.x, sign.maxY - 2, sign.w, 2), Theme.frame)
            draw.text(title, in: Rect(r.x, r.y + 18, r.w, 44), size: 30, color: Theme.text, face: .display,
                      shadow: Color(linear: 0, 0, 0, 0.7))
        }
    }

    func dim(_ alpha: Float = 0.55) {
        draw.fill(Rect(0, 0, size.x, size.y), Color(hex: 0x140A04, alpha: alpha * 0.8), bottom: Color(hex: 0x140A04, alpha: alpha))
    }

    // MARK: Widgets

    @discardableResult
    func button(_ id: String, _ label: String, _ r: Rect, style: ButtonStyle = .primary, enabled: Bool = true,
                badge: String? = nil, fontSize: Float = 20) -> Bool {
        let hover = enabled && hovered(id, r)
        if !enabled && r.contains(mouse) && canInteract(id) { hotThisFrame = id }
        if hover && mousePressed { activeID = id }
        let pressed = activeID == id && mouseDown && hover
        let clicked = enabled && hover && activeID == id && mouseReleased
        let h = anim(id + ".h", hover ? 1 : 0, speed: 16)
        let p = anim(id + ".p", pressed ? 1 : 0, speed: 30)
        let lift = h * 2 - p * 2.5
        let rr = r.offset(0, -lift)
        let radius = min(6, r.h * 0.15)

        var top: Color, bottom: Color, textColor: Color, border: Color?
        switch style {
        case .primary:
            top = Theme.amber.mix(.white, 0.14 * h); bottom = Theme.amberDeep.mix(Theme.amber, 0.15 * h)
            textColor = Theme.textDark; border = nil
        case .secondary:
            // An oak plank
            top = Color(hex: 0x8E6036).mix(Color(hex: 0xA8743F), h)
            bottom = Color(hex: 0x6A4424).mix(Color(hex: 0x7E5430), h)
            textColor = Theme.text; border = Theme.frame.mix(Theme.amber, 0.6 * h)
        case .danger:
            top = Color(hex: 0xD9474C).mix(.white, 0.1 * h); bottom = Color(hex: 0xA62F38)
            textColor = .white; border = nil
        case .ghost:
            top = Color(linear: 1, 1, 1, 0.06 * h); bottom = top
            textColor = Theme.text.mix(Theme.amber, h); border = nil
        }
        if !enabled {
            top = Color(hex: 0x4A3322, alpha: 0.85); bottom = Color(hex: 0x3A281A, alpha: 0.85)
            textColor = Theme.textMuted.alpha(0.6); border = Color(linear: 1, 1, 1, 0.06)
        }
        if style != .ghost {
            draw.shadow(rr, radius: radius, blur: 8 + 8 * h, color: Color(linear: 0, 0, 0, 0.32 + 0.15 * h), offset: 5 - lift * 0.5)
            if h > 0.01 && enabled {
                let glow = (style == .danger ? Theme.danger : Theme.amber).alpha(0.28 * h)
                draw.fill(rr.inset(-3), glow, radius: radius + 3, blur: 10)
            }
        }
        draw.fill(rr, top, radius: radius, bottom: bottom)
        if style != .ghost {
            draw.stroke(rr.inset(1), Color(linear: 1, 1, 1, enabled ? 0.16 + 0.1 * h : 0.05), radius: radius - 1, width: 1,
                        bottom: Color(linear: 1, 1, 1, 0))
        }
        if style != .ghost {
            // Dark outline and a shadowed lower lip, like a board's edge
            draw.stroke(rr, border ?? Theme.frame, radius: radius, width: 2)
            draw.fill(Rect(rr.x + 2, rr.maxY - 4, rr.w - 4, 2), Color(linear: 0, 0, 0, 0.25), radius: 1)
        }
        draw.text(label, in: rr, size: fontSize, color: textColor, face: .display,
                  shadow: style == .primary || !enabled ? nil : Color(linear: 0, 0, 0, 0.55))
        if let badge {
            let bw = draw.font.measure(badge, size: 11, face: .display, tracking: 0.12) + 18
            let br = Rect(rr.maxX - bw - 12, rr.midY - 11, bw, 22)
            let pulse = Float(0.75 + 0.25 * sin(time * 2.4))
            draw.fill(br, Theme.amber.alpha(0.2 * pulse + 0.1), radius: 11)
            draw.stroke(br, Theme.amber.alpha(0.7), radius: 11, width: 1)
            draw.text(badge, in: br, size: 11, color: Theme.amber, face: .display, tracking: 0.12)
        }
        if clicked { onSound?(style == .ghost ? .back : .click) }
        return clicked
    }

    /// Selectable list row. Returns (clicked, doubleClicked).
    func row(_ id: String, _ r: Rect, selected: Bool) -> (Bool, Bool) {
        let hover = hovered(id, r)
        if hover && mousePressed { activeID = id }
        let clicked = hover && activeID == id && mouseReleased
        let h = anim(id + ".h", hover ? 1 : 0)
        let s = anim(id + ".s", selected ? 1 : 0)
        draw.fill(r, Color(linear: 1, 1, 1, 0.03 + 0.05 * h).mix(Theme.amber.alpha(0.16), s), radius: 14)
        if s > 0.01 { draw.stroke(r, Theme.amber.alpha(0.8 * s), radius: 14, width: 1.6) }
        if clicked { onSound?(.click) }
        return (clicked, hover && input.doubleClicked)
    }

    @discardableResult
    func toggle(_ id: String, _ label: String, _ r: Rect, _ value: inout Bool, detail: String? = nil) -> Bool {
        let hover = hovered(id, r)
        if hover && mousePressed { activeID = id }
        let clicked = hover && activeID == id && mouseReleased
        if clicked { value.toggle(); onSound?(.toggle) }
        let h = anim(id + ".h", hover ? 1 : 0)
        let on = anim(id + ".on", value ? 1 : 0, speed: 18)
        draw.fill(r, Color(linear: 1, 1, 1, 0.025 + 0.035 * h), radius: 12)
        draw.text(label, in: Rect(r.x + 16, r.y, r.w - 100, detail == nil ? r.h : r.h * 0.62), size: 16, color: Theme.text, align: .left)
        if let detail {
            draw.text(detail, in: Rect(r.x + 16, r.y + r.h * 0.45, r.w - 100, r.h * 0.5), size: 12.5, color: Theme.textMuted, align: .left)
        }
        let sw = Rect(r.maxX - 66, r.midY - 13, 50, 26)
        draw.fill(sw, Color(hex: 0x24150A, alpha: 0.8).mix(Theme.jungle, on), radius: 13)
        draw.stroke(sw, Color(linear: 1, 1, 1, 0.12), radius: 13, width: 1)
        let kx = sw.x + 13 + on * 24
        draw.circle(center: SIMD2(kx, sw.midY + 1), radius: 10.5, Color(linear: 0, 0, 0, 0.3))
        draw.circle(center: SIMD2(kx, sw.midY), radius: 10, Theme.text)
        return clicked
    }

    @discardableResult
    func slider(_ id: String, _ label: String, _ r: Rect, _ value: inout Double, range: ClosedRange<Double>, step: Double = 0,
                format: (Double) -> String) -> Bool {
        let track = Rect(r.x + 16, r.maxY - 20, r.w - 32, 6)
        let hover = hovered(id, r)
        if hover && mousePressed { activeID = id }
        var changed = false
        if activeID == id && mouseDown {
            let t = Double(max(0, min(1, (mouse.x - track.x) / track.w)))
            var v = range.lowerBound + t * (range.upperBound - range.lowerBound)
            if step > 0 { v = (v / step).rounded() * step }
            v = min(range.upperBound, max(range.lowerBound, v))
            if v != value { value = v; changed = true }
        }
        if activeID == id && mouseReleased { onSound?(.toggle) }
        let h = anim(id + ".h", hover || activeID == id ? 1 : 0)
        draw.fill(r, Color(linear: 1, 1, 1, 0.025 + 0.035 * h), radius: 12)
        draw.text(label, x: r.x + 16, y: r.y + 10, size: 16, color: Theme.text)
        draw.text(format(value), x: r.maxX - 16, y: r.y + 10, size: 16, color: Theme.amber, face: .display, align: .right)
        let t = Float((value - range.lowerBound) / (range.upperBound - range.lowerBound))
        draw.fill(track, Color(linear: 1, 1, 1, 0.12), radius: 3)
        draw.fill(Rect(track.x, track.y, track.w * t, track.h), Theme.amberDeep, radius: 3, bottom: Theme.amber)
        let knob = SIMD2(track.x + track.w * t, track.midY)
        draw.circle(center: knob + SIMD2(0, 1.5), radius: 10 + 2 * h, Color(linear: 0, 0, 0, 0.35))
        draw.circle(center: knob, radius: 9 + 2 * h, Theme.text)
        draw.circle(center: knob, radius: 9 + 2 * h, Theme.amber, ring: 2.5)
        return changed
    }

    /// Returns true when Return is pressed while focused.
    @discardableResult
    func textField(_ id: String, _ r: Rect, _ text: inout String, placeholder: String, maxLength: Int = 32) -> Bool {
        let hover = hovered(id, r)
        if hover { textCursor = true }
        if mousePressed && canInteract(id) {
            if hover { focusedID = id } else if focusedID == id { focusedID = nil }
        }
        let focused = focusedID == id
        var submitted = false
        if focused {
            if input.modifiers.contains(.command) && input.keyPressed(KeyCode.v),
               let paste = UIPasteboard.general.string {
                text += paste.filter { !$0.isNewline }
            }
            for ch in input.typedText { text.append(ch) }
            if text.count > maxLength { text = String(text.prefix(maxLength)) }
            if input.keyRepeated(KeyCode.delete) && !text.isEmpty {
                if input.modifiers.contains(.command) || input.modifiers.contains(.option) { text = "" } else { text.removeLast() }
            }
            if input.keyPressed(KeyCode.returnKey) || input.keyPressed(KeyCode.enter) { submitted = true }
        }
        let f = anim(id + ".f", focused ? 1 : 0)
        let h = anim(id + ".h", hover ? 1 : 0)
        draw.fill(r, Theme.field, radius: 12)
        draw.stroke(r, Theme.amber.alpha(0.18 + 0.2 * h + 0.6 * f), radius: 12, width: 1.5 + f)
        let inner = Rect(r.x + 16, r.y, r.w - 32, r.h)
        if text.isEmpty {
            draw.text(placeholder, in: inner, size: 17, color: Theme.textMuted.alpha(0.7), align: .left)
        }
        var width: Float = 0
        if !text.isEmpty {
            width = draw.text(text, in: inner, size: 17, color: Theme.text, align: .left)
        }
        if focused && Int(time * 2) % 2 == 0 {
            let cx = inner.x + min(width, inner.w) + 2
            draw.fill(Rect(cx, r.midY - 11, 2, 22), Theme.amber, radius: 1)
        }
        return submitted
    }

    @discardableResult
    func segmented(_ id: String, _ r: Rect, options: [String], selected: inout Int) -> Bool {
        draw.fill(r, Theme.field, radius: 12)
        draw.stroke(r, Color(linear: 1, 1, 1, 0.08), radius: 12, width: 1)
        let w = r.w / Float(options.count)
        let pos = anim(id + ".sel", Float(selected), speed: 16)
        let pill = Rect(r.x + 3 + pos * w, r.y + 3, w - 6, r.h - 6)
        draw.shadow(pill, radius: 10, blur: 6, color: Color(linear: 0, 0, 0, 0.3), offset: 2)
        draw.fill(pill, Theme.amber, radius: 10, bottom: Theme.amberDeep)
        var changed = false
        for (i, option) in options.enumerated() {
            let cell = Rect(r.x + Float(i) * w, r.y, w, r.h)
            let sid = "\(id).\(i)"
            let hover = hovered(sid, cell)
            if hover && mousePressed { activeID = sid }
            if hover && activeID == sid && mouseReleased && selected != i {
                selected = i; changed = true; onSound?(.toggle)
            }
            let isSel = Float(abs(pos - Float(i)) < 0.5 ? 1 : 0)
            draw.text(option, in: cell, size: 15, color: Theme.text.mix(Theme.textDark, isSel), face: .display)
        }
        return changed
    }

    /// A row showing an action and its binding; clicking starts listening.
    func keyBinding(_ id: String, _ label: String, _ r: Rect, binding: InputBinding, listening: Bool) -> Bool {
        let hover = hovered(id, r)
        if hover && mousePressed { activeID = id }
        let clicked = hover && activeID == id && mouseReleased
        let h = anim(id + ".h", hover ? 1 : 0)
        draw.fill(r, Color(linear: 1, 1, 1, 0.025 + 0.035 * h), radius: 12)
        draw.text(label, in: Rect(r.x + 16, r.y, r.w * 0.5, r.h), size: 16, color: Theme.text, align: .left)
        let chip = Rect(r.maxX - 196, r.y + 8, 180, r.h - 16)
        let pulse = listening ? Float(0.6 + 0.4 * sin(time * 6)) : 0
        draw.fill(chip, listening ? Theme.amber.alpha(0.25 + 0.2 * pulse) : Theme.field, radius: 10)
        draw.stroke(chip, Theme.amber.alpha(listening ? 0.9 : 0.25 + 0.4 * h), radius: 10, width: 1.4)
        draw.text(listening ? "Press a key…" : binding.displayName, in: chip, size: 15,
                  color: listening ? Theme.amber : Theme.text, face: .display)
        if clicked { onSound?(.click) }
        return clicked
    }

    // MARK: Scrolling

    func beginScroll(_ id: String, _ r: Rect, contentHeight: Float) -> Float {
        let maxOffset = max(0, contentHeight - r.h)
        var target = scrollTargets[id] ?? 0
        if r.contains(mouse) && canInteract(id) { target -= Float(input.scroll) * 38 }
        target = max(0, min(maxOffset, target))
        scrollTargets[id] = target
        let offset = anim(id + ".scroll", target, speed: 18)
        draw.pushClip(r)
        clipStack.append(r)
        return offset
    }

    func endScroll(_ id: String, _ r: Rect, contentHeight: Float) {
        draw.popClip()
        _ = clipStack.popLast()
        guard contentHeight > r.h else { return }
        let offset = anims[id + ".scroll"] ?? 0
        let ratio = r.h / contentHeight
        let thumbH = max(30, r.h * ratio)
        let t = offset / max(1, contentHeight - r.h)
        draw.fill(Rect(r.maxX - 5, r.y, 4, r.h), Color(linear: 1, 1, 1, 0.06), radius: 2)
        draw.fill(Rect(r.maxX - 5, r.y + (r.h - thumbH) * t, 4, thumbH), Theme.amber.alpha(0.7), radius: 2)
    }

    func resetScroll(_ id: String) {
        scrollTargets[id] = 0
        anims[id + ".scroll"] = 0
    }
}
