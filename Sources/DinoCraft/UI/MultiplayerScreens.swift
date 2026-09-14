import Foundation
import simd
import DinoCraftCore
@testable import DinoCraftGame

// MARK: - Multiplayer browser

final class MultiplayerScreen: Screen {
    private var address = ""
    private var started = false

    override var scene: GameActivityState.Scene { .worldSelection }

    override func back(_ engine: GameEngine) {
        engine.discovery.stop()
        super.back(engine)
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        if !started {
            started = true
            e.discovery.start()
            address = e.settings.lastServerAddress
        }
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let a = appear(0)
        let pw = min(780, W - 80), ph = min(650, H - 60)
        let p = Rect(W / 2 - pw / 2, H / 2 - ph / 2 + (1 - a) * 24, pw, ph)
        d.opacity = a
        ui.panel(p, title: "Multiplayer")
        let x = p.x + 40, w = p.w - 80
        var y = p.y + 78

        let name = e.settings.username.isEmpty ? "no name yet" : e.settings.username
        d.text("Playing as", x: x, y: y + 4, size: 14, color: Theme.textMuted)
        d.text(name, x: x + 78, y: y + 2, size: 17, color: Theme.amber, face: .display)
        if ui.button("mp.name", "Change Name", Rect(p.maxX - 40 - 150, y - 4, 150, 36), style: .secondary, fontSize: 14) {
            e.pushScreen(UsernameScreen(current: e.settings.username, firstRun: false))
        }
        y += 50

        d.text("GAMES ON YOUR NETWORK", x: x, y: y, size: 12.5, color: Theme.amber, face: .display, tracking: 0.12)
        y += 24
        let list = Rect(x, y, w, 196)
        d.fill(list, Theme.field, radius: 14)
        let hosts = e.discovery.hosts
        if hosts.isEmpty {
            let dots = String(repeating: "•", count: 1 + Int(ui.time * 2) % 3)
            d.text("Searching for DinoCraft games on your Wi-Fi \(dots)", in: list.inset(dx: 20, dy: 0), size: 15, color: Theme.textMuted)
        } else {
            for (i, host) in hosts.prefix(3).enumerated() {
                let row = Rect(list.x + 10, list.y + 10 + Float(i) * 60, list.w - 20, 54)
                d.fill(row, Color(linear: 1, 1, 1, 0.04), radius: 12)
                d.blockIcon(Blocks.grass, Rect(row.x + 12, row.y + 9, 36, 36))
                d.text(host.name, in: Rect(row.x + 60, row.y, row.w - 200, row.h), size: 17, color: Theme.text, face: .display, align: .left)
                if ui.button("mp.lan.\(i)", "Join", Rect(row.maxX - 120, row.y + 7, 110, 40), fontSize: 16) {
                    e.joinGame(lanHost: host)
                }
            }
        }
        y += 196 + 26

        d.text("JOIN WITH INVITE CODE OR ADDRESS", x: x, y: y, size: 12.5, color: Theme.amber, face: .display, tracking: 0.12)
        y += 24
        let submitted = ui.textField("mp.address", Rect(x, y, w - 150, 50), &address, placeholder: "Invite code like DINO-3M4KA-9QX2B, or an address", maxLength: 64)
        let canJoin = !address.trimmingCharacters(in: .whitespaces).isEmpty
        if ui.button("mp.join", "Join", Rect(x + w - 136, y, 136, 50), enabled: canJoin) || (submitted && canJoin) {
            let trimmed = address.trimmingCharacters(in: .whitespaces)
            e.settingsStore.update { $0.lastServerAddress = trimmed }
            e.joinGame(address: trimmed)
        }
        y += 68

        d.text("To host: open a world, press Esc, then “Open to LAN” (same Wi-Fi) or “Open to Internet” (friends elsewhere).", x: x, y: y, size: 14, color: Theme.textMuted, maxWidth: w)
        d.text("Friends need DinoCraft on a Mac. Different networks: the host uses Open to Internet, or you both join one Tailscale network.", x: x, y: y + 22,
               size: 14, color: Theme.textMuted, maxWidth: w)

        if ui.button("mp.back", "Back", Rect(p.midX - 120, p.maxY - 76, 240, 50), style: .secondary) { back(e) }
        d.opacity = 1
    }
}

final class ConnectingScreen: Screen {
    let label: String
    init(label: String) { self.label = label }
    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .worldSelection }
    override func back(_ engine: GameEngine) { engine.cancelJoin() }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        ui.dim(0.7)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let p = Rect(W / 2 - 240, H / 2 - 110, 480, 220)
        ui.panel(p)
        let dots = String(repeating: ".", count: 1 + Int(ui.time * 3) % 3)
        d.text("Connecting\(dots)", in: Rect(p.x, p.y + 30, p.w, 40), size: 26, color: Theme.text, face: .display)
        d.text(label, in: Rect(p.x + 20, p.y + 76, p.w - 40, 24), size: 15, color: Theme.textMuted)
        if ui.button("modal.cancelJoin", "Cancel", Rect(p.midX - 110, p.maxY - 76, 220, 50), style: .secondary) { e.cancelJoin() }
    }
}

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
        let field = Rect(20, H - 150, min(760, W - 40), 46)
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

        d.fill(field.inset(-6), Color(hex: 0x0A0614, alpha: 0.6), radius: 14)
        let submitted = ui.textField("modal.chat", field, &text, placeholder: "Chat, or type / for commands (Tab completes, Enter sends, Esc closes)", maxLength: 200)
        text = text.replacingOccurrences(of: "\t", with: "")

        if text.hasPrefix("/") {
            let usage = Commands.usage(for: text)
            let rows = Array(suggestions.prefix(8))
            let rowH: Float = 30
            var y = field.y - 12 - Float(rows.count) * rowH - (usage != nil ? 36 : 0)
            if let usage {
                let bar = Rect(field.x, y, field.w, 30)
                d.fill(bar, Color(hex: 0x120B22, alpha: 0.94), radius: 8)
                d.text(usage, x: bar.x + 12, y: bar.y + 6, size: 14, color: Theme.amber, face: .display, maxWidth: bar.w - 24)
                y += 36
            }
            for (i, suggestion) in rows.enumerated() {
                let r = Rect(field.x, y + Float(i) * rowH, field.w, rowH - 2)
                let active = i == selected
                d.fill(r, active ? Theme.amber.alpha(0.28) : Color(hex: 0x120B22, alpha: 0.9), radius: 8)
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
                d.text("Tab to complete · ↑↓ to choose", x: field.maxX - 210, y: field.maxY + 8, size: 12, color: Theme.textMuted)
            }
        }

        if submitted {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && trimmed != "/" { e.submitChat(trimmed) }
            e.popScreen()
        }
    }
}

enum MultiplayerHUD {
    static func draw(_ ui: UIContext, engine e: GameEngine) {
        guard e.session != nil else { return }
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y

        // Name tags
        let viewProj = e.lastViewProj
        for p in e.remotePlayers where !p.dead {
            let rel = SIMD3<Float>(Float(p.position.x - e.camera.position.x), Float(p.position.y + 2.15 - e.camera.position.y),
                                   Float(p.position.z - e.camera.position.z))
            let distance = simd_length(rel)
            guard distance < 64 else { continue }
            let clip = viewProj * SIMD4(rel, 1)
            guard clip.w > 0.1 else { continue }
            let ndc = SIMD2(clip.x, clip.y) / clip.w
            guard abs(ndc.x) < 1.2, abs(ndc.y) < 1.2 else { continue }
            let sx = (ndc.x * 0.5 + 0.5) * W, sy = (1 - (ndc.y * 0.5 + 0.5)) * H
            let size = max(11, 17 - distance * 0.12)
            let tw = d.font.measure(p.name, size: size, face: .display) + 16
            let tag = Rect(sx - tw / 2, sy - size - 8, tw, size + 10)
            d.fill(tag, Color(hex: 0x0A0614, alpha: 0.55), radius: 7)
            d.text(p.name, in: tag, size: size, color: p.hurtTimer > 0 ? Theme.danger : Theme.text, face: .display)
            let hp = Float(max(0, min(20, p.health)) / 20)
            d.fill(Rect(tag.x + 4, tag.maxY + 2, (tag.w - 8) * hp, 3), Theme.danger.mix(Theme.jungle, hp), radius: 1.5)
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
            d.fill(Rect(16, y - 2, min(tw, W * 0.6), 24), Color(hex: 0x0A0614, alpha: 0.45 * alpha), radius: 6)
            d.text(entry.text, x: 26, y: y + 1, size: 15, color: Theme.text.alpha(alpha), maxWidth: W * 0.6 - 20)
            y += 24
        }

        // Player list (hold Tab)
        if e.showPlayerList {
            let names = [e.settings.username + " (you)"] + e.remotePlayers.map { $0.name }
            let pw: Float = 320, ph = Float(names.count) * 30 + 70
            let panel = Rect(W / 2 - pw / 2, 90, pw, ph)
            d.fill(panel, Color(hex: 0x120B22, alpha: 0.88), radius: 16)
            d.stroke(panel, Theme.amber.alpha(0.35), radius: 16, width: 1.2)
            d.text(e.server != nil ? "Hosting · \(names.count) players" : "Players · \(names.count)", in: Rect(panel.x, panel.y + 12, pw, 32),
                   size: 17, color: Theme.amber, face: .display)
            for (i, n) in names.enumerated() {
                d.text(n, x: panel.x + 28, y: panel.y + 54 + Float(i) * 30, size: 16, color: Theme.text)
            }
        }
    }
}
