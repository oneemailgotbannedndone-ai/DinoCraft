import Foundation
import simd
import DinoCraftCore
@testable import DinoCraftGame

// MARK: - Messages and chat (the offline parts of the Mac multiplayer screens)

final class MessageScreen: Screen {
    let title: String
    let message: String
    init(title: String, message: String) { self.title = title; self.message = message }
    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        ui.dim(0.6)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let p = Rect(W / 2 - 260, H / 2 - 120, 520, 240)
        ui.panel(p)
        d.text(title, in: Rect(p.x, p.y + 28, p.w, 40), size: 26, color: Theme.text, face: .display)
        d.text(message, in: Rect(p.x + 24, p.y + 80, p.w - 48, 50), size: 15, color: Theme.textMuted)
        if ui.button("modal.ok", "OK", Rect(p.midX - 100, p.maxY - 76, 200, 50)) { back(e) }
    }
}

// MARK: - Chat

final class ChatScreen: Screen {
    private var text: String
    private var frames = 0
    private var selected = 0
    private var lastText = ""

    init(prefill: String = "") { text = prefill }

    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .playing }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        frames += 1
        if frames == 1 {
            ui.focusedID = "modal.chat"
            return   // ignore the key press that opened chat
        }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        // At the top of the screen, clear of the on-screen keyboard; suggestions open below it.
        _ = H
        let field = Rect(20, 76, min(760, W - 140), 46)
        let input = ui.input

        var suggestions = Commands.suggestions(for: text, engine: e)
        if text != lastText { selected = 0; lastText = text }
        if !suggestions.isEmpty {
            if input.keyRepeated(KeyCode.down) { selected = (selected + 1) % suggestions.count }
            if input.keyRepeated(KeyCode.up) { selected = (selected + suggestions.count - 1) % suggestions.count }
            if input.keyPressed(KeyCode.tab) {
                text = suggestions[min(selected, suggestions.count - 1)].completion
                lastText = text
                selected = 0
                suggestions = Commands.suggestions(for: text, engine: e)
            }
        }

        d.fill(field.inset(-6), Color(hex: 0x140A04, alpha: 0.6), radius: 14)
        let submitted = ui.textField("modal.chat", field, &text, placeholder: "Type / for commands", maxLength: 200)
        text = text.replacingOccurrences(of: "\t", with: "")

        if text.hasPrefix("/") {
            let usage = Commands.usage(for: text)
            let rows = Array(suggestions.prefix(8))
            let rowH: Float = 30
            var y = field.maxY + 10
            if let usage {
                let bar = Rect(field.x, y, field.w, 30)
                d.fill(bar, Color(hex: 0x2A180A, alpha: 0.94), radius: 8)
                d.text(usage, x: bar.x + 12, y: bar.y + 6, size: 14, color: Theme.amber, face: .display, maxWidth: bar.w - 24)
                y += 36
            }
            for (i, suggestion) in rows.enumerated() {
                let r = Rect(field.x, y + Float(i) * rowH, field.w, rowH - 2)
                let active = i == selected
                d.fill(r, active ? Theme.amber.alpha(0.28) : Color(hex: 0x2A180A, alpha: 0.9), radius: 8)
                d.text(suggestion.label, x: r.x + 12, y: r.y + 5, size: 15, color: active ? Theme.text : Theme.textMuted, face: active ? .display : .body,
                       maxWidth: field.w * 0.5)
                if let detail = suggestion.detail {
                    d.text(detail, x: r.x + field.w * 0.42, y: r.y + 7, size: 13, color: Theme.textMuted, maxWidth: field.w * 0.56)
                }
                if ui.hoverSilent("chat.suggestion.\(i)", r) && input.buttonsPressed.contains(0) {
                    text = suggestion.completion
                    lastText = text
                    selected = 0
                }
            }
            if rows.isEmpty == false && selected == 0 && frames < 90 {
                d.text("Tap a suggestion to fill it in", x: field.maxX - 210, y: field.y - 20, size: 12, color: Theme.textMuted)
            }
        }

        if submitted {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed != "/" { e.submitChat(trimmed) }
            e.popScreen()
        }
    }
}

/// Chat, and name tags over your tamed creatures (offline: no other players).
enum MultiplayerHUD {
    static func draw(_ ui: UIContext, engine e: GameEngine) {
        guard e.session != nil else { return }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y

        let viewProj = e.lastViewProj

        // Name tags over your tamed creatures (and the name of whatever you're looking at that's yours)
        if let s = e.session {
            for m in s.mobs.mobs where m.isTamed && !m.isDying && m !== s.riding {
                let rel = SIMD3<Float>(Float(m.position.x - e.camera.position.x), Float(m.position.y + m.species.height * m.scale + 0.45 - e.camera.position.y),
                                       Float(m.position.z - e.camera.position.z))
                let distance = simd_length(rel)
                guard distance < 20 else { continue }
                let clip = viewProj * SIMD4(rel, 1)
                guard clip.w > 0.1 else { continue }
                let ndc = SIMD2(clip.x, clip.y) / clip.w
                guard abs(ndc.x) < 1.2, abs(ndc.y) < 1.2 else { continue }
                let text = m === s.targetMob ? m.label : (m.petName ?? (m.sitting ? "\(m.species.displayName) (sitting)" : ""))
                guard !text.isEmpty else { continue }
                let sx = (ndc.x * 0.5 + 0.5) * W, sy = (1 - (ndc.y * 0.5 + 0.5)) * H
                let size = max(11, 15 - distance * 0.15)
                let tw = d.font.measure(text, size: size, face: .display) + 16
                let tag = Rect(sx - tw / 2, sy - size - 8, tw, size + 10)
                d.fill(tag, Color(hex: 0x140A04, alpha: 0.5), radius: 7)
                d.text(text, in: tag, size: size, color: Color(hex: 0xC0FFB4), face: .display)
            }
            if s.riding != nil {
                d.text("Sneak to get off", x: W / 2, y: H - 132, size: 14, color: Theme.text.alpha(0.75), face: .display, align: .center,
                       shadow: Color(linear: 0, 0, 0, 0.8))
            }
            if s.spectator {
                d.text("Spectator — your Hardcore adventure is over", x: W / 2, y: H - 110, size: 14, color: Theme.text.alpha(0.75),
                       face: .display, align: .center, shadow: Color(linear: 0, 0, 0, 0.8))
            }
        }

        // Chat log
        let chatOpen = e.topScreen is ChatScreen
        let recent = e.chatLog.suffix(chatOpen ? 12 : 7)
        var y = H - 170 - Float(recent.count) * 24
        for entry in recent {
            let age = e.time - entry.time
            guard chatOpen || age < 12 else { y += 24; continue }
            let alpha = chatOpen ? 1 : Float(min(1, (12 - age) / 1.5))
            let tw = d.font.measure(entry.text, size: 15) + 20
            d.fill(Rect(16, y - 2, min(tw, W * 0.6), 24), Color(hex: 0x140A04, alpha: 0.45 * alpha), radius: 6)
            d.text(entry.text, x: 26, y: y + 1, size: 15, color: Theme.text.alpha(alpha), maxWidth: W * 0.6 - 20)
            y += 24
        }
    }
}
