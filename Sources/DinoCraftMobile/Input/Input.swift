import UIKit
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Keyboard modifiers, kept so the shared screens can ask the same questions as on the Mac
/// (on a phone, a double tap counts as a shift-click).
struct ModifierFlags: OptionSet {
    let rawValue: Int
    static let shift = ModifierFlags(rawValue: 1)
    static let control = ModifierFlags(rawValue: 2)
    static let option = ModifierFlags(rawValue: 4)
    static let command = ModifierFlags(rawValue: 8)
}

/// Per-frame input state with the same shape as the Mac version, fed by touches instead of a
/// keyboard and mouse: the on-screen controls press the same virtual keys the game listens for,
/// and in menus a finger acts as the mouse pointer.
final class Input {
    private(set) var keysDown = Set<Int>()
    private(set) var keysPressed = Set<Int>()
    private(set) var keysReleased = Set<Int>()
    /// Includes repeated presses (backspace held on the on-screen keyboard).
    private(set) var keysRepeated = Set<Int>()
    private(set) var buttonsDown = Set<Int>()
    private(set) var buttonsPressed = Set<Int>()
    private(set) var buttonsReleased = Set<Int>()

    /// Pointer position in view points, origin top-left.
    private(set) var mouse = SIMD2<Float>(0, 0)
    private(set) var mouseDelta = SIMD2<Double>(0, 0)
    private(set) var scroll: Double = 0
    private(set) var typedText = ""
    private(set) var modifiers: ModifierFlags = []
    private(set) var doubleClicked = false
    /// A hotbar slot tapped this frame.
    var hotbarTap: Int?

    /// When set, the next key or button is captured for rebinding instead of acting.
    var captureNextBinding: ((InputBinding) -> Void)?

    /// True while playing (the touch controls steer the player instead of a pointer).
    private(set) var mouseCaptured = false
    weak var view: UIView?
    var onActivity: (() -> Void)?
    /// Scripted runs ignore touches.
    var headless = false

    // Releases that arrive in the same frame as their press are held until the next frame, so a quick
    // tap still reads as "pressed" one frame and "released" the next (the way a mouse click does).
    private var deferredKeyUps = Set<Int>()
    private var deferredButtonUps = Set<Int>()
    private var pendingModifiers: ModifierFlags?

    // MARK: Intake (called by the touch controls and the on-screen keyboard)

    func keyDown(_ code: Int) {
        onActivity?()
        if let capture = captureNextBinding {
            captureNextBinding = nil
            capture(.key(code))
            return
        }
        if !keysDown.contains(code) { keysPressed.insert(code) }
        keysDown.insert(code)
        keysRepeated.insert(code)
        deferredKeyUps.remove(code)
    }

    func keyUp(_ code: Int) {
        guard keysDown.contains(code) else { return }
        if keysPressed.contains(code) {
            deferredKeyUps.insert(code)
        } else {
            keysDown.remove(code)
            keysReleased.insert(code)
        }
    }

    /// A key pressed and let go (one frame down, released the next).
    func tapKey(_ code: Int) {
        keyDown(code)
        keyUp(code)
    }

    func setKey(_ code: Int, down: Bool) {
        if down { if !keysDown.contains(code) { keyDown(code) } } else { keyUp(code) }
    }

    func buttonDown(_ button: Int, at point: SIMD2<Float>? = nil) {
        onActivity?()
        if let point { mouse = point }
        if let capture = captureNextBinding {
            captureNextBinding = nil
            capture(.mouse(button))
            return
        }
        if !buttonsDown.contains(button) { buttonsPressed.insert(button) }
        buttonsDown.insert(button)
        deferredButtonUps.remove(button)
    }

    func buttonUp(_ button: Int, at point: SIMD2<Float>? = nil) {
        if let point { mouse = point }
        guard buttonsDown.contains(button) else { return }
        if buttonsPressed.contains(button) {
            deferredButtonUps.insert(button)
        } else {
            buttonsDown.remove(button)
            buttonsReleased.insert(button)
        }
    }

    func setBinding(_ b: InputBinding, down: Bool) {
        switch b.kind {
        case .key: setKey(b.code, down: down)
        case .mouse: if down { if !buttonsDown.contains(b.code) { buttonDown(b.code) } } else { buttonUp(b.code) }
        }
    }

    func tapBinding(_ b: InputBinding) {
        setBinding(b, down: true)
        setBinding(b, down: false)
    }

    func movePointer(to point: SIMD2<Float>) { mouse = point }
    func addLook(_ delta: SIMD2<Double>) { mouseDelta += delta }
    func addScroll(_ amount: Double) { scroll += amount }
    func type(_ text: String) {
        onActivity?()
        typedText += text
    }
    func markDoubleClick() { doubleClicked = true }
    /// Modifiers for the next press only (a double tap in the inventory is a shift-click).
    func setModifiers(_ flags: ModifierFlags) {
        modifiers = flags
        pendingModifiers = []
    }

    // MARK: Frame lifecycle

    func endFrame() {
        keysPressed.removeAll(keepingCapacity: true)
        keysReleased.removeAll(keepingCapacity: true)
        keysRepeated.removeAll(keepingCapacity: true)
        buttonsPressed.removeAll(keepingCapacity: true)
        buttonsReleased.removeAll(keepingCapacity: true)
        for code in deferredKeyUps {
            keysDown.remove(code)
            keysReleased.insert(code)
        }
        deferredKeyUps.removeAll()
        for button in deferredButtonUps {
            buttonsDown.remove(button)
            buttonsReleased.insert(button)
        }
        deferredButtonUps.removeAll()
        if let next = pendingModifiers, buttonsDown.isEmpty {
            modifiers = next
            pendingModifiers = nil
        }
        mouseDelta = .zero
        scroll = 0
        typedText = ""
        doubleClicked = false
        hotbarTap = nil
    }

    /// Clears held state (when the app goes to the background, so nothing stays "stuck").
    func releaseAll() {
        keysDown.removeAll()
        buttonsDown.removeAll()
        deferredKeyUps.removeAll()
        deferredButtonUps.removeAll()
        modifiers = []
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

    func injectMouse(_ position: SIMD2<Float>) { mouse = position }

    /// Simulates a press or release of a binding.
    func inject(_ b: InputBinding, down: Bool) { setBinding(b, down: down) }

    // MARK: Play mode

    func setMouseCaptured(_ captured: Bool) {
        guard captured != mouseCaptured else { return }
        mouseCaptured = captured
        mouseDelta = .zero
    }
}

extension Input: GameInput {
    var hotbarKeyPressed: Int? { hotbarTap ?? KeyCode.digits.firstIndex { keysPressed.contains($0) } }
    var dropWholeStack: Bool { modifiers.contains(.command) || modifiers.contains(.option) }
}

/// Virtual key codes (the Mac's, so the default key bindings work unchanged).
enum KeyCode {
    static let escape = 53, returnKey = 36, enter = 76, tab = 48, delete = 51, forwardDelete = 117
    static let left = 123, right = 124, down = 125, up = 126, space = 49
    static let f1 = 122, f2 = 120, f3 = 99, f5 = 96, f11 = 103
    static let digits = [18, 19, 20, 21, 23, 22, 26, 28, 25]   // 1...9
    static let a = 0, c = 8, v = 9, g = 5, t = 17, slash = 44
}
