import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

/// Keyboard and mouse for the shared game, fed from SDL events. Key bindings are stored with macOS
/// key codes (the settings are shared with the Mac), so they're translated to SDL scancodes here.
final class SDLGameInput: GameInput {
    private(set) var mouseDelta = SIMD2<Double>(0, 0)
    private(set) var scroll = 0.0
    private(set) var hotbarKeyPressed: Int?
    private var keysDown = Set<Int>()
    private var keysPressed = Set<Int>()
    /// Mouse buttons use the Mac numbering: 0 left, 1 right, 2 middle.
    private var buttonsDown = Set<Int>()
    private var buttonsPressed = Set<Int>()

    var dropWholeStack: Bool { isScancodeDown(SDL_SCANCODE_LCTRL) || isScancodeDown(SDL_SCANCODE_RCTRL) }

    func isDown(_ binding: InputBinding) -> Bool {
        switch binding.kind {
        case .mouse: return buttonsDown.contains(binding.code)
        case .key: return SDLGameInput.scancode(forMacKey: binding.code).map { keysDown.contains($0) } ?? false
        }
    }

    func wasPressed(_ binding: InputBinding) -> Bool {
        switch binding.kind {
        case .mouse: return buttonsPressed.contains(binding.code)
        case .key: return SDLGameInput.scancode(forMacKey: binding.code).map { keysPressed.contains($0) } ?? false
        }
    }

    func isScancodeDown(_ code: SDL_Scancode) -> Bool { keysDown.contains(Int(code.rawValue)) }
    func wasScancodePressed(_ code: SDL_Scancode) -> Bool { keysPressed.contains(Int(code.rawValue)) }

    // MARK: Feeding events

    func keyDown(_ scancode: SDL_Scancode, isRepeat: Bool) {
        let code = Int(scancode.rawValue)
        if !isRepeat {
            keysPressed.insert(code)
            if code >= Int(SDL_SCANCODE_1.rawValue) && code <= Int(SDL_SCANCODE_9.rawValue) {
                hotbarKeyPressed = code - Int(SDL_SCANCODE_1.rawValue)
            }
        }
        keysDown.insert(code)
    }

    func keyUp(_ scancode: SDL_Scancode) { keysDown.remove(Int(scancode.rawValue)) }

    /// SDL button numbers: 1 left, 2 middle, 3 right.
    func buttonDown(_ sdlButton: UInt8) {
        guard let b = SDLGameInput.macButton(sdlButton) else { return }
        buttonsDown.insert(b)
        buttonsPressed.insert(b)
    }

    func buttonUp(_ sdlButton: UInt8) {
        guard let b = SDLGameInput.macButton(sdlButton) else { return }
        buttonsDown.remove(b)
    }

    func mouseMoved(dx: Float, dy: Float) { mouseDelta += SIMD2(Double(dx), Double(dy)) }
    func wheel(_ y: Float) { scroll += Double(y) }

    /// Forget everything held (the window lost focus, or a menu opened).
    func releaseAll() {
        keysDown.removeAll()
        buttonsDown.removeAll()
        endFrame()
    }

    /// Clears this frame's presses and movement once the game has read them.
    func endFrame() {
        keysPressed.removeAll()
        buttonsPressed.removeAll()
        mouseDelta = .zero
        scroll = 0
        hotbarKeyPressed = nil
    }

    private static func macButton(_ sdlButton: UInt8) -> Int? {
        switch sdlButton {
        case 1: return 0
        case 2: return 2
        case 3: return 1
        case 4...16: return Int(sdlButton) - 1
        default: return nil
        }
    }

    /// macOS virtual key code → SDL scancode.
    static func scancode(forMacKey code: Int) -> Int? {
        macKeys[code].map { Int($0.rawValue) }
    }

    private static let macKeys: [Int: SDL_Scancode] = [
        0: SDL_SCANCODE_A, 1: SDL_SCANCODE_S, 2: SDL_SCANCODE_D, 3: SDL_SCANCODE_F, 4: SDL_SCANCODE_H, 5: SDL_SCANCODE_G,
        6: SDL_SCANCODE_Z, 7: SDL_SCANCODE_X, 8: SDL_SCANCODE_C, 9: SDL_SCANCODE_V, 11: SDL_SCANCODE_B, 12: SDL_SCANCODE_Q,
        13: SDL_SCANCODE_W, 14: SDL_SCANCODE_E, 15: SDL_SCANCODE_R, 16: SDL_SCANCODE_Y, 17: SDL_SCANCODE_T,
        18: SDL_SCANCODE_1, 19: SDL_SCANCODE_2, 20: SDL_SCANCODE_3, 21: SDL_SCANCODE_4, 22: SDL_SCANCODE_6, 23: SDL_SCANCODE_5,
        24: SDL_SCANCODE_EQUALS, 25: SDL_SCANCODE_9, 26: SDL_SCANCODE_7, 27: SDL_SCANCODE_MINUS, 28: SDL_SCANCODE_8,
        29: SDL_SCANCODE_0, 30: SDL_SCANCODE_RIGHTBRACKET, 31: SDL_SCANCODE_O, 32: SDL_SCANCODE_U, 33: SDL_SCANCODE_LEFTBRACKET,
        34: SDL_SCANCODE_I, 35: SDL_SCANCODE_P, 36: SDL_SCANCODE_RETURN, 37: SDL_SCANCODE_L, 38: SDL_SCANCODE_J,
        39: SDL_SCANCODE_APOSTROPHE, 40: SDL_SCANCODE_K, 41: SDL_SCANCODE_SEMICOLON, 42: SDL_SCANCODE_BACKSLASH,
        43: SDL_SCANCODE_COMMA, 44: SDL_SCANCODE_SLASH, 45: SDL_SCANCODE_N, 46: SDL_SCANCODE_M, 47: SDL_SCANCODE_PERIOD,
        48: SDL_SCANCODE_TAB, 49: SDL_SCANCODE_SPACE, 50: SDL_SCANCODE_GRAVE, 51: SDL_SCANCODE_BACKSPACE, 53: SDL_SCANCODE_ESCAPE,
        55: SDL_SCANCODE_LGUI, 56: SDL_SCANCODE_LSHIFT, 57: SDL_SCANCODE_CAPSLOCK, 58: SDL_SCANCODE_LALT, 59: SDL_SCANCODE_LCTRL,
        60: SDL_SCANCODE_RSHIFT, 61: SDL_SCANCODE_RALT, 62: SDL_SCANCODE_RCTRL,
        122: SDL_SCANCODE_F1, 120: SDL_SCANCODE_F2, 99: SDL_SCANCODE_F3, 118: SDL_SCANCODE_F4, 96: SDL_SCANCODE_F5,
        97: SDL_SCANCODE_F6, 98: SDL_SCANCODE_F7, 100: SDL_SCANCODE_F8, 101: SDL_SCANCODE_F9, 109: SDL_SCANCODE_F10,
        103: SDL_SCANCODE_F11, 111: SDL_SCANCODE_F12,
        123: SDL_SCANCODE_LEFT, 124: SDL_SCANCODE_RIGHT, 125: SDL_SCANCODE_DOWN, 126: SDL_SCANCODE_UP,
    ]
}
