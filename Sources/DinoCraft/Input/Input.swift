import AppKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Collects raw input events between frames and exposes per-frame state:
/// held keys/buttons, edges (pressed / released this frame), mouse deltas,
/// scroll, and typed text for text fields. Handles pointer capture for
/// first-person mouse look.
final class Input {
    private(set) var keysDown = Set<Int>()
    private(set) var keysPressed = Set<Int>()
    private(set) var keysReleased = Set<Int>()
    /// Includes auto-repeat presses (for text editing / list navigation).
    private(set) var keysRepeated = Set<Int>()
    private(set) var buttonsDown = Set<Int>()
    private(set) var buttonsPressed = Set<Int>()
    private(set) var buttonsReleased = Set<Int>()

    /// Mouse position in view points, origin top-left.
    private(set) var mouse = SIMD2<Float>(0, 0)
    private(set) var mouseDelta = SIMD2<Double>(0, 0)
    private(set) var scroll: Double = 0
    private(set) var typedText = ""
    private(set) var modifiers: NSEvent.ModifierFlags = []
    private(set) var doubleClicked = false

    /// When set, the next key or mouse button is captured for rebinding instead of acting.
    var captureNextBinding: ((InputBinding) -> Void)?

    private(set) var mouseCaptured = false
    weak var view: NSView?

    /// Called for every discrete event so the engine can mark "user is active".
    var onActivity: (() -> Void)?

    // MARK: Event intake

    func handleKeyDown(_ e: NSEvent) {
        guard !headless else { return }   // scripted runs ignore hardware input
        let code = Int(e.keyCode)
        onActivity?()
        if let capture = captureNextBinding, !e.isARepeat {
            captureNextBinding = nil
            capture(.key(code))
            return
        }
        keysRepeated.insert(code)
        if !e.isARepeat {
            keysDown.insert(code)
            keysPressed.insert(code)
        }
        modifiers = e.modifierFlags
        if let chars = e.characters, !e.modifierFlags.contains(.command) {
            let filtered = chars.unicodeScalars.filter { $0.value >= 32 && $0.value != 127 && !(0xF700...0xF8FF).contains($0.value) }
            typedText += String(String.UnicodeScalarView(filtered))
        }
    }

    func handleKeyUp(_ e: NSEvent) {
        guard !headless else { return }   // scripted runs ignore hardware input
        let code = Int(e.keyCode)
        keysDown.remove(code)
        keysReleased.insert(code)
        modifiers = e.modifierFlags
    }

    private static let modifierMasks: [Int: NSEvent.ModifierFlags] = [
        56: .shift, 60: .shift, 59: .control, 62: .control, 58: .option, 61: .option, 55: .command, 54: .command, 57: .capsLock, 63: .function,
    ]

    func handleFlagsChanged(_ e: NSEvent) {
        guard !headless else { return }   // scripted runs ignore hardware input
        let code = Int(e.keyCode)
        modifiers = e.modifierFlags
        guard let mask = Input.modifierMasks[code] else { return }
        // Device-dependent bits distinguish left/right; fall back to the generic flag.
        let isDown: Bool
        let raw = e.modifierFlags.rawValue
        switch code {
        case 56: isDown = raw & 0x02 != 0
        case 60: isDown = raw & 0x04 != 0
        case 59: isDown = raw & 0x01 != 0
        case 62: isDown = raw & 0x2000 != 0
        case 58: isDown = raw & 0x20 != 0
        case 61: isDown = raw & 0x40 != 0
        case 55: isDown = raw & 0x08 != 0
        case 54: isDown = raw & 0x10 != 0
        default: isDown = e.modifierFlags.contains(mask)
        }
        if isDown {
            onActivity?()
            if let capture = captureNextBinding {
                captureNextBinding = nil
                capture(.key(code))
                return
            }
            if !keysDown.contains(code) { keysPressed.insert(code) }
            keysDown.insert(code)
        } else {
            keysDown.remove(code)
            keysReleased.insert(code)
        }
    }

    func handleMouseDown(_ e: NSEvent, button: Int, view: NSView) {
        guard !headless else { return }   // scripted runs ignore hardware input
        onActivity?()
        updateMousePosition(e, view: view)
        if let capture = captureNextBinding {
            captureNextBinding = nil
            capture(.mouse(button))
            return
        }
        buttonsDown.insert(button)
        buttonsPressed.insert(button)
        if button == 0 && e.clickCount == 2 { doubleClicked = true }
        modifiers = e.modifierFlags
    }

    func handleMouseUp(_ e: NSEvent, button: Int, view: NSView) {
        guard !headless else { return }   // scripted runs ignore hardware input
        updateMousePosition(e, view: view)
        buttonsDown.remove(button)
        buttonsReleased.insert(button)
    }

    func handleMouseMoved(_ e: NSEvent, view: NSView) {
        guard !headless else { return }   // scripted runs ignore hardware input
        if mouseCaptured {
            mouseDelta += SIMD2(Double(e.deltaX), Double(e.deltaY))
        } else {
            updateMousePosition(e, view: view)
        }
    }

    func handleScroll(_ e: NSEvent) {
        guard !headless else { return }   // scripted runs ignore hardware input
        onActivity?()
        // Precise (trackpad) deltas are in points; wheel deltas in lines.
        scroll += e.hasPreciseScrollingDeltas ? Double(e.scrollingDeltaY) / 12 : Double(e.scrollingDeltaY)
    }

    private func updateMousePosition(_ e: NSEvent, view: NSView) {
        let p = view.convert(e.locationInWindow, from: nil)
        mouse = SIMD2(Float(p.x), Float(view.bounds.height - p.y))
    }

    // MARK: Frame lifecycle

    func endFrame() {
        keysPressed.removeAll(keepingCapacity: true)
        keysReleased.removeAll(keepingCapacity: true)
        keysRepeated.removeAll(keepingCapacity: true)
        buttonsPressed.removeAll(keepingCapacity: true)
        buttonsReleased.removeAll(keepingCapacity: true)
        mouseDelta = .zero
        scroll = 0
        typedText = ""
        doubleClicked = false
    }

    /// Clears held state (e.g. when focus is lost, so keys don't get "stuck").
    func releaseAll() {
        keysDown.removeAll()
        buttonsDown.removeAll()
        endFrame()
    }

    // MARK: Queries

    func isDown(_ b: InputBinding) -> Bool {
        b.kind == .key ? keysDown.contains(b.code) : buttonsDown.contains(b.code)
    }
    func wasPressed(_ b: InputBinding) -> Bool {
        b.kind == .key ? keysPressed.contains(b.code) : buttonsPressed.contains(b.code)
    }
    func wasReleased(_ b: InputBinding) -> Bool {
        b.kind == .key ? keysReleased.contains(b.code) : buttonsReleased.contains(b.code)
    }
    func keyPressed(_ code: Int) -> Bool { keysPressed.contains(code) }
    func keyRepeated(_ code: Int) -> Bool { keysRepeated.contains(code) }

    // MARK: Automation

    /// When true (scripted test runs), pointer capture is tracked but the real cursor is left alone.
    var headless = false

    func injectMouse(_ position: SIMD2<Float>) { mouse = position }
    func injectModifiers(_ flags: NSEvent.ModifierFlags) { modifiers = flags }

    /// Simulates a press or release of a binding (used by `ScriptRunner`).
    func inject(_ b: InputBinding, down: Bool) {
        switch (b.kind, down) {
        case (.key, true):
            if !keysDown.contains(b.code) { keysPressed.insert(b.code) }
            keysDown.insert(b.code)
        case (.key, false):
            keysDown.remove(b.code)
            keysReleased.insert(b.code)
        case (.mouse, true):
            if !buttonsDown.contains(b.code) { buttonsPressed.insert(b.code) }
            buttonsDown.insert(b.code)
        case (.mouse, false):
            buttonsDown.remove(b.code)
            buttonsReleased.insert(b.code)
        }
    }

    // MARK: Pointer capture

    func setMouseCaptured(_ captured: Bool) {
        guard captured != mouseCaptured else { return }
        mouseCaptured = captured
        if headless { return }
        if captured {
            NSCursor.hide()
            CGAssociateMouseAndMouseCursorPosition(0)
            centerCursor()
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            centerCursor()
            NSCursor.unhide()
        }
        mouseDelta = .zero
    }

    private func centerCursor() {
        guard let view, let window = view.window, let screen = window.screen else { return }
        let frameInWindow = view.convert(view.bounds, to: nil)
        let onScreen = window.convertToScreen(frameInWindow)
        let center = CGPoint(x: onScreen.midX, y: screen.frame.maxY - onScreen.midY + (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY)
        CGWarpMouseCursorPosition(center)
        mouse = SIMD2(Float(view.bounds.width / 2), Float(view.bounds.height / 2))
    }
}

extension Input: GameInput {
    var hotbarKeyPressed: Int? { KeyCode.digits.firstIndex { keysPressed.contains($0) } }
    var dropWholeStack: Bool { modifiers.contains(.command) || modifiers.contains(.option) }
}

enum KeyCode {
    static let escape = 53, returnKey = 36, enter = 76, tab = 48, delete = 51, forwardDelete = 117
    static let left = 123, right = 124, down = 125, up = 126, space = 49
    static let f1 = 122, f2 = 120, f3 = 99, f11 = 103
    static let digits = [18, 19, 20, 21, 23, 22, 26, 28, 25]   // 1...9
    static let a = 0, c = 8, v = 9
}
