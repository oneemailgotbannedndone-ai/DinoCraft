import Foundation
import CSDL3
import DinoCraftCore
@testable import DinoCraftGame

/// The settings panel, shared by the title screen and the in-game pause menu: graphics on the
/// left, sound and controls on the right. Changes apply and save straight away.
struct SettingsPanel {
    /// Post-processing looks, in the same order and with the same ids as the Mac's `ShaderPack`.
    static let shaderPacks: [(id: String, name: String)] = [("off", "Off"), ("vibrant", "Vibrant"), ("cinematic", "Cinematic"),
                                                            ("retro", "Retro"), ("dreamy", "Dreamy")]

    /// Applies brightness and the shader pack to the renderer.
    static func applyLooks(_ settings: GameSettings, to renderer: WinRenderer) {
        renderer.brightness = Float(settings.brightness)
        renderer.shaderPack = shaderPacks.firstIndex { $0.id == settings.shaderPack } ?? 0
        renderer.shaderStrength = Float(max(0, min(1, settings.shaderStrength)))
    }

    let store: SettingsStore
    let renderer: WinRenderer
    let audio: WinAudio?
    let window: OpaquePointer
    var click: () -> Void

    /// Draws the panel from `top`; returns the y just below it.
    func build(_ ui: inout UIBuilder, input: MenuInput, width W: Float, top: Float, scale s: Float) -> Float {
        let small = max(1, (2 * s).rounded())
        let settings = store.settings
        let colW = min((W - 60 * s) / 2, 520 * s), gapX = 20 * s
        let rowH = 38 * s, rowGap = 8 * s
        let leftX = W / 2 - colW - gapX / 2, rightX = W / 2 + gapX / 2
        var y = [top, top]

        func row(_ column: Int, _ title: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) {
            let x = column == 0 ? leftX : rightX
            ui.rect(x, y[column], colW, rowH, SIMD4(0.08, 0.06, 0.12, 0.85))
            ui.text(title, x: x + 10 * s, y: y[column] + rowH / 2 - 3.5 * small, scale: small, color: SIMD4(1, 1, 1, 1))
            let bw = 38 * s, valueW = min(200 * s, colW * 0.45)
            let bx = x + colW - bw * 2 - valueW - 8 * s
            if ui.button("<", x: bx, y: y[column] + 3 * s, w: bw, h: rowH - 6 * s, scale: s, input: input) { click(); minus() }
            let shown = value.count > Int(valueW / (6 * small)) ? String(value.prefix(Int(valueW / (6 * small)) - 1)) + "\u{2026}" : value
            ui.centeredText(shown, centerX: bx + bw + valueW / 2, y: y[column] + rowH / 2 - 3.5 * small, scale: small, color: SIMD4(1, 0.85, 0.55, 1))
            if ui.button(">", x: bx + bw + valueW, y: y[column] + 3 * s, w: bw, h: rowH - 6 * s, scale: s, input: input) { click(); plus() }
            y[column] += rowH + rowGap
        }
        func toggle(_ column: Int, _ title: String, _ on: Bool, _ flip: @escaping () -> Void) {
            row(column, title, on ? "On" : "Off", minus: flip, plus: flip)
        }
        func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }
        func step(_ key: WritableKeyPath<GameSettings, Double>, _ delta: Double, _ lo: Double, _ hi: Double) {
            store.update { $0[keyPath: key] = min(hi, max(lo, (($0[keyPath: key] + delta) * 100).rounded() / 100)) }
        }

        // Graphics
        // Steps of 2 up to 16 chunks, then 4 up to 64 (far distances need a strong computer).
        let rd = max(4, min(GameSettings.maxRenderDistance, settings.renderDistance))
        row(0, "Render distance", "\(rd) chunks\(rd > 32 ? " (needs a strong PC)" : "")",
            minus: { store.update { $0.renderDistance = max(4, rd - (rd > 16 ? 4 : 2)) } },
            plus: { store.update { $0.renderDistance = min(GameSettings.maxRenderDistance, rd + (rd >= 16 ? 4 : 2)) } })
        row(0, "Field of view", "\(Int(settings.fov))\u{00B0}", minus: { step(\.fov, -5, 50, 110) }, plus: { step(\.fov, 5, 50, 110) })
        row(0, "Brightness", percent(settings.brightness), minus: { step(\.brightness, -0.1, 0, 1) }, plus: { step(\.brightness, 0.1, 0, 1) })
        // Leaves change the next time a world opens.
        toggle(0, "Fancy leaves", settings.graphicsQuality != .fast) {
            store.update { $0.graphicsQuality = $0.graphicsQuality == .fast ? .fancy : .fast }
        }
        toggle(0, "View bobbing", settings.viewBobbing) { store.update { $0.viewBobbing.toggle() } }
        toggle(0, "Fullscreen", settings.fullscreen) {
            store.update { $0.fullscreen.toggle() }
            _ = SDL_SetWindowFullscreen(window, store.settings.fullscreen)
        }
        toggle(0, "Show FPS", settings.showFPS) { store.update { $0.showFPS.toggle() } }
        toggle(0, "VSync", settings.vsync) {
            store.update { $0.vsync.toggle() }
            _ = SDL_GL_SetSwapInterval(store.settings.vsync ? 1 : 0)
        }
        if !settings.vsync {
            let caps = [0, 60, 90, 120, 144, 165, 240, 360]
            let cap = caps.firstIndex(of: settings.maxFPS) ?? 0
            row(0, "Max FPS", settings.maxFPS == 0 ? "Unlimited" : "\(settings.maxFPS)",
                minus: { store.update { $0.maxFPS = caps[(cap + caps.count - 1) % caps.count] } },
                plus: { store.update { $0.maxFPS = caps[(cap + 1) % caps.count] } })
        }
        let looks = SettingsPanel.shaderPacks
        let look = looks.firstIndex { $0.id == settings.shaderPack } ?? 0
        row(0, "Shader pack", looks[look].name,
            minus: { store.update { $0.shaderPack = looks[(look + looks.count - 1) % looks.count].id } },
            plus: { store.update { $0.shaderPack = looks[(look + 1) % looks.count].id } })

        // Sound, controls and looks
        row(1, "Music", percent(settings.musicVolume), minus: { step(\.musicVolume, -0.1, 0, 1) }, plus: { step(\.musicVolume, 0.1, 0, 1) })
        row(1, "Sounds", percent(settings.soundVolume), minus: { step(\.soundVolume, -0.1, 0, 1) }, plus: { step(\.soundVolume, 0.1, 0, 1) })
        row(1, "Ambience", percent(settings.ambientVolume), minus: { step(\.ambientVolume, -0.1, 0, 1) }, plus: { step(\.ambientVolume, 0.1, 0, 1) })
        row(1, "Mouse sensitivity", "\(Int((settings.mouseSensitivity * 200).rounded()))%",
            minus: { step(\.mouseSensitivity, -0.05, 0, 1) }, plus: { step(\.mouseSensitivity, 0.05, 0, 1) })
        toggle(1, "Invert mouse", settings.invertY) { store.update { $0.invertY.toggle() } }
        let packs = TexturePackLibrary.all()
        let current = packs.firstIndex { $0.id == renderer.texturePack.id } ?? 0
        func choosePack(_ index: Int) {
            let pack = packs[(index + packs.count) % packs.count]
            store.update { $0.texturePack = pack.id }
            renderer.applyTexturePack(pack)
        }
        row(1, "Texture pack", packs[current].name, minus: { choosePack(current - 1) }, plus: { choosePack(current + 1) })
        let maxChars = max(8, Int(colW / (6 * small)))
        let about = packs[current].description
        ui.text(about.count > maxChars ? String(about.prefix(maxChars - 1)) + "\u{2026}" : about, x: rightX, y: y[1], scale: small,
                color: SIMD4(0.8, 0.76, 0.9, 0.9))
        y[1] += 10 * small

        audio?.apply(store.settings)
        SettingsPanel.applyLooks(store.settings, to: renderer)
        return max(y[0], y[1])
    }
}
