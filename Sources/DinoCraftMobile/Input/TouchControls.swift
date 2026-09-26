import UIKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// The on-screen controls. While playing: a floating joystick under the left thumb, dragging
/// anywhere else to look (tap to use or hit, hold to break), buttons for jumping, breaking,
/// placing, sneaking and the inventory, and a tappable hotbar (hold a slot to drop an item).
/// In menus a finger is the mouse: tap to click, hold for a right-click, drag sliders and lists.
final class TouchControls {
    enum Button: CaseIterable { case jump, attack, use, sneak, inventory, pause, camera, chat, shift, close }

    private enum PointerMode { case pending, dragging, scrolling, done }

    private enum Role {
        case joystick(origin: SIMD2<Float>)
        case look(moved: Bool, breaking: Bool)
        case button(Button)
        case hotbar(slot: Int, dropped: Bool)
        case pointer(PointerMode)
        case ignored
    }

    private struct Tracked {
        var role: Role
        var start: SIMD2<Float>      // view points
        var position: SIMD2<Float>   // view points
        var startTime: Double
    }

    private var tracked: [ObjectIdentifier: Tracked] = [:]
    private var joystick = SIMD2<Float>(0, 0)
    private var sneakLatched = false
    private var shiftLatched = false
    private var lastTapTime = -1.0
    private var lastTapPoint = SIMD2<Float>(0, 0)
    private var clock = 0.0
    private var scale: Float = 1
    private var size = SIMD2<Float>(1100, 600)
    /// True while the player is in control (a world is open with no menu over it).
    private(set) var playing = false
    private var sessionScreenOpen = false
    private var inventoryScreenOpen = false

    private static let lookGain = 1.8
    private static let tapTime = 0.25
    private static let holdTime = 0.32
    private static let rightClickTime = 0.45
    private static let slop: Float = 11

    // MARK: Layout (interface units)

    private let joystickRadius: Float = 88
    private var joystickHome: SIMD2<Float> { SIMD2(150, size.y - 150) }

    private func place(_ b: Button) -> (center: SIMD2<Float>, radius: Float) {
        let W = size.x, H = size.y
        switch b {
        case .jump: return (SIMD2(W - 105, H - 115), 54)
        case .attack: return (SIMD2(W - 232, H - 185), 44)
        case .use: return (SIMD2(W - 105, H - 255), 44)
        case .sneak: return (SIMD2(W - 232, H - 62), 38)
        case .inventory: return (SIMD2(W / 2 - 305, H - 45), 28)
        case .pause: return (SIMD2(44, 40), 26)
        case .camera: return (SIMD2(108, 40), 26)
        case .chat: return (SIMD2(172, 40), 26)
        case .shift: return (SIMD2(W - 116, 40), 26)
        case .close: return (SIMD2(W - 44, 40), 26)
        }
    }

    private var visibleButtons: [Button] {
        if playing { return [.jump, .attack, .use, .sneak, .inventory, .pause, .camera, .chat] }
        if inventoryScreenOpen { return [.shift, .close] }
        if sessionScreenOpen { return [.close] }
        return []
    }

    private func hotbarSlot(at p: SIMD2<Float>) -> Int? {
        let slot: Float = 54, gap: Float = 5
        let total = slot * 9 + gap * 8
        let hx = size.x / 2 - total / 2, hy = size.y - slot - 18
        guard p.y >= hy - 10, p.y <= hy + slot + 10, p.x >= hx - 4, p.x <= hx + total + 4 else { return nil }
        return max(0, min(8, Int((p.x - hx) / (slot + gap))))
    }

    private func units(_ p: SIMD2<Float>) -> SIMD2<Float> { p / max(0.01, scale) }

    private func button(at p: SIMD2<Float>) -> Button? {
        let u = units(p)
        for b in visibleButtons {
            let (c, r) = place(b)
            if simd_distance(u, c) <= r + 10 { return b }
        }
        return nil
    }

    // MARK: Touches (view points, called by the game view)

    func began(_ id: ObjectIdentifier, at p: SIMD2<Float>, input: Input, engine: GameEngine) {
        var t = Tracked(role: .ignored, start: p, position: p, startTime: clock)
        let u = units(p)
        if let b = button(at: p) {
            t.role = .button(b)
            press(b, down: true, input: input, engine: engine)
        } else if playing {
            if let slot = hotbarSlot(at: u) {
                t.role = .hotbar(slot: slot, dropped: false)
                input.hotbarTap = slot
            } else if u.x < size.x * 0.45 && u.y > size.y * 0.3 && !tracked.values.contains(where: { if case .joystick = $0.role { return true } else { return false } }) {
                t.role = .joystick(origin: u)
            } else {
                t.role = .look(moved: false, breaking: false)
            }
        } else if !tracked.values.contains(where: { if case .pointer = $0.role { return true } else { return false } }) {
            t.role = .pointer(.pending)
            input.movePointer(to: p)
        }
        tracked[id] = t
    }

    func moved(_ id: ObjectIdentifier, to p: SIMD2<Float>, input: Input) {
        guard var t = tracked[id] else { return }
        let delta = p - t.position
        t.position = p
        switch t.role {
        case .joystick(let origin):
            var v = (units(p) - origin) / joystickRadius
            let length = simd_length(v)
            if length > 1 { v /= length }
            joystick = v
        case .look(let moved, let breaking):
            input.addLook(SIMD2(Double(delta.x), Double(delta.y)) * TouchControls.lookGain)
            if !moved && simd_distance(p, t.start) > TouchControls.slop { t.role = .look(moved: true, breaking: breaking) }
        case .pointer(let mode):
            let d = units(p) - units(t.start)
            switch mode {
            case .pending where simd_length(p - t.start) > TouchControls.slop:
                if abs(d.y) > abs(d.x) * 1.2 {
                    t.role = .pointer(.scrolling)
                } else {
                    input.buttonDown(0, at: t.start)
                    input.movePointer(to: p)
                    t.role = .pointer(.dragging)
                }
            case .dragging:
                input.movePointer(to: p)
            case .scrolling:
                input.addScroll(Double(delta.y / max(0.01, scale)) / 38)
            default:
                break
            }
        default:
            break
        }
        tracked[id] = t
    }

    func ended(_ id: ObjectIdentifier, at p: SIMD2<Float>, input: Input, engine: GameEngine) {
        guard let t = tracked.removeValue(forKey: id) else { return }
        let held = clock - t.startTime
        switch t.role {
        case .joystick:
            joystick = .zero
        case .look(let moved, let breaking):
            if breaking {
                input.setBinding(engine.settings.binding(for: .attack), down: false)
            } else if !moved && held < TouchControls.tapTime {
                worldTap(input: input, engine: engine)
            }
        case .button(let b):
            press(b, down: false, input: input, engine: engine)
        case .pointer(let mode):
            switch mode {
            case .pending:
                if shiftLatched { input.setModifiers(.shift) }
                if clock - lastTapTime < 0.35 && simd_distance(p, lastTapPoint) < 30 { input.markDoubleClick() }
                lastTapTime = clock
                lastTapPoint = p
                input.buttonDown(0, at: p)
                input.buttonUp(0, at: p)
            case .dragging:
                input.buttonUp(0, at: p)
            default:
                break
            }
        default:
            break
        }
    }

    /// A quick tap in the world: hit the creature you're looking at, otherwise use or place.
    private func worldTap(input: Input, engine: GameEngine) {
        guard let s = engine.session else { return }
        let action: GameAction = s.targetMob != nil ? .attack : .use
        input.tapBinding(engine.settings.binding(for: action))
    }

    private func press(_ b: Button, down: Bool, input: Input, engine: GameEngine) {
        let s = engine.settings
        switch b {
        case .jump: input.setBinding(s.binding(for: .jump), down: down)
        case .attack: input.setBinding(s.binding(for: .attack), down: down)
        case .use: input.setBinding(s.binding(for: .use), down: down)
        case .sneak:
            // A tap toggles sneaking; while flying it's held to go down instead.
            if engine.session?.player.flying == true { input.setBinding(s.binding(for: .crouch), down: down) }
            else if down { sneakLatched.toggle() }
        case .inventory: if down { input.tapBinding(s.binding(for: .inventory)) }
        case .pause, .close: if down { input.tapBinding(s.binding(for: .pause)) }
        case .camera: if down { input.tapKey(KeyCode.f5) }
        case .chat: if down { input.tapKey(KeyCode.slash) }
        case .shift: if down { shiftLatched.toggle() }
        }
    }

    // MARK: Per frame

    /// Turns the held controls into the game's inputs for this frame.
    func apply(engine: GameEngine, dt: Double) {
        clock += dt
        scale = engine.ui.scale
        size = engine.ui.size
        let input = engine.input
        let s = engine.session
        let top = engine.topScreen
        let nowPlaying = s != nil && top == nil && !(s?.isLoading ?? true) && !(s?.isDead ?? true)
        if nowPlaying != playing {
            // Switching between playing and menus: let go of everything the other mode was holding.
            playing = nowPlaying
            release(input: input, settings: engine.settings)
        }
        sessionScreenOpen = s != nil && top != nil && !(top is PauseScreen) && !(top is DeathScreen) && !(top is SettingsScreen)
        inventoryScreenOpen = top is InventoryScreen || top is ContainerScreen || top is CreativeInventoryScreen
        if !inventoryScreenOpen { shiftLatched = false }
        guard playing else {
            applyPointerHolds(input: input)
            return
        }

        let settings = engine.settings
        input.setBinding(settings.binding(for: .forward), down: joystick.y < -0.35)
        input.setBinding(settings.binding(for: .backward), down: joystick.y > 0.35)
        input.setBinding(settings.binding(for: .left), down: joystick.x < -0.35)
        input.setBinding(settings.binding(for: .right), down: joystick.x > 0.35)
        input.setBinding(settings.binding(for: .sprint), down: joystick.y < -0.92)
        if s?.player.flying != true {
            input.setBinding(settings.binding(for: .crouch), down: sneakLatched)
        }

        // Holding still on the view starts breaking; holding a hotbar slot drops one of that item.
        for (id, t) in tracked {
            switch t.role {
            case .look(let moved, let breaking) where !moved && !breaking && clock - t.startTime >= TouchControls.holdTime:
                input.setBinding(settings.binding(for: .attack), down: true)
                tracked[id]?.role = .look(moved: false, breaking: true)
            case .hotbar(let slot, let dropped) where !dropped && clock - t.startTime >= 0.6:
                input.hotbarTap = slot
                input.tapBinding(settings.binding(for: .drop))
                tracked[id]?.role = .hotbar(slot: slot, dropped: true)
            default:
                break
            }
        }
    }

    /// Pointer holds that became right-clicks (checked once per frame, before the screens draw).
    private func applyPointerHolds(input: Input) {
        for (id, t) in tracked {
            if case .pointer(.pending) = t.role, clock - t.startTime >= TouchControls.rightClickTime {
                input.buttonDown(1, at: t.start)
                input.buttonUp(1, at: t.start)
                tracked[id]?.role = .pointer(.done)
            }
        }
    }

    private func release(input: Input, settings: GameSettings) {
        for action in [GameAction.forward, .backward, .left, .right, .sprint, .crouch, .jump, .attack, .use] {
            input.setBinding(settings.binding(for: action), down: false)
        }
        for (id, t) in tracked {
            if case .pointer(.dragging) = t.role { input.buttonUp(0) }
            tracked[id]?.role = .ignored
        }
        joystick = .zero
    }

    func reset() {
        tracked.removeAll()
        joystick = .zero
    }

    // MARK: Drawing

    func draw(_ ui: UIContext, engine: GameEngine) {
        let buttons = visibleButtons
        guard !buttons.isEmpty else { return }
        let d = ui.draw
        let held = Set(tracked.values.compactMap { t -> Button? in if case .button(let b) = t.role { return b } else { return nil } })

        if playing {
            // The joystick: where your thumb went down, or its resting spot.
            var origin = joystickHome
            var active = false
            for t in tracked.values { if case .joystick(let o) = t.role { origin = o; active = true } }
            d.circle(center: origin, radius: joystickRadius, Color(linear: 0, 0, 0, active ? 0.28 : 0.16))
            d.circle(center: origin, radius: joystickRadius, Color(linear: 1, 1, 1, active ? 0.35 : 0.18), ring: 2.5)
            let knob = origin + joystick * joystickRadius
            d.circle(center: knob, radius: 36, Color(linear: 1, 1, 1, active ? 0.45 : 0.22))
            if joystick.y < -0.92 {
                d.text("SPRINT", x: origin.x, y: origin.y - joystickRadius - 26, size: 13, color: Theme.amber, face: .display, align: .center,
                       shadow: Color(linear: 0, 0, 0, 0.8))
            }
        }

        for b in buttons {
            let (c, r) = place(b)
            let on = held.contains(b) || (b == .sneak && sneakLatched) || (b == .shift && shiftLatched)
            d.circle(center: c + SIMD2(0, 2), radius: r, Color(linear: 0, 0, 0, 0.25))
            d.circle(center: c, radius: r, on ? Theme.amber.alpha(0.55) : Color(hex: 0x2A1A0C, alpha: 0.5))
            d.circle(center: c, radius: r, Color(linear: 1, 1, 1, on ? 0.7 : 0.3), ring: 2)
            let icon = Rect(c.x - r * 0.52, c.y - r * 0.52, r * 1.04, r * 1.04)
            switch b {
            case .attack:
                if let id = engine.items.id(named: "iron_pickaxe"), let info = engine.items[id] { d.itemIcon(info, icon) }
                else { label("HIT", c, r, d) }
            case .use:
                if let stack = engine.session?.inventory.selectedStack, let info = engine.items[stack.item] { d.itemIcon(info, icon) }
                else { label("USE", c, r, d) }
            case .inventory:
                if let id = engine.items.id(named: "chest"), let info = engine.items[id] { d.itemIcon(info, icon) }
                else { label("BAG", c, r, d) }
            case .jump: label("JUMP", c, r, d)
            case .sneak: label(engine.session?.player.flying == true ? "DOWN" : "SNEAK", c, r, d)
            case .pause: label("II", c, r, d)
            case .camera: label("VIEW", c, r, d)
            case .chat: label("/", c, r, d)
            case .shift: label("SHIFT", c, r, d)
            case .close: label("X", c, r, d)
            }
        }
    }

    private func label(_ text: String, _ c: SIMD2<Float>, _ r: Float, _ d: UIRenderer) {
        let size = min(18, r * (text.count > 3 ? 0.36 : 0.62))
        d.text(text, in: Rect(c.x - r, c.y - r, r * 2, r * 2), size: size, color: Theme.text, face: .display)
    }
}
