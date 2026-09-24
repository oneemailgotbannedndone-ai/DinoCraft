import AppKit
import Foundation
import DinoCraftCore
@testable import DinoCraftGame

// MARK: - Launcher

/// The pre-launcher shown when DinoCraft opens: news about the newest build, the update button,
/// cosmetics, settings and Play (which goes on to the main menu underneath).
final class LauncherScreen: Screen {
    private var installError: String?

    override var scene: GameActivityState.Scene { .mainMenu }
    override func back(_ engine: GameEngine) {}

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let intro = appear(0, duration: 0.6)
        d.opacity = intro

        let titleY = max(30, H * 0.06)
        d.outlinedText(Brand.title, x: W / 2, y: titleY, size: Brand.title.count > 9 ? 70 : 80, fill: Color(hex: Brand.top),
                       fillBottom: Color(hex: Brand.bottom), outline: Color(hex: 0x2A1740), outlineWidth: 6, tracking: 0.005)
        d.text("LAUNCHER", x: W / 2, y: titleY + 96, size: 14, color: Theme.text.alpha(0.85), face: .display, align: .center,
               tracking: 0.2, shadow: Color(linear: 0, 0, 0, 0.7))

        // News
        let top = titleY + 140
        let panelW = min(640, W * 0.5), panelX = max(30, W / 2 - panelW - 20)
        let panelH = max(260, H - top - 70)
        let panel = Rect(panelX, top, panelW, panelH)
        ui.panel(panel, radius: 20)
        var y = panel.y + 26
        let textW = panel.w - 56
        func line(_ text: String, _ size: Float, _ color: Color, face: FontFace = .body) {
            guard y < panel.maxY - 30 else { return }
            d.text(text, x: panel.x + 28, y: y, size: size, color: color, face: face, maxWidth: textW)
            y += size * 1.45
        }
        func wrapped(_ text: String, _ size: Float, _ color: Color) {
            var current = ""
            for word in text.split(separator: " ") {
                let next = current.isEmpty ? String(word) : current + " " + word
                if d.font.measure(next, size: size) > textW && !current.isEmpty {
                    line(current, size, color)
                    current = String(word)
                } else {
                    current = next
                }
            }
            if !current.isEmpty { line(current, size, color) }
        }
        if let release = e.updater.latestRelease {
            line("What's new", 26, Theme.amber, face: .display)
            y += 4
            line(release.title + (release.published.isEmpty ? "" : "  ·  \(release.published)"), 16, Theme.text)
            y += 6
            for raw in release.notes.split(separator: "\n", omittingEmptySubsequences: false) {
                let text = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "**", with: "")
                if text.hasPrefix("Co-Authored-By") || text.hasPrefix("Claude-Session") { continue }
                if text.isEmpty { y += 8; continue }
                wrapped(text, 15, Theme.textMuted)
            }
        } else {
            line("Welcome, explorer!", 26, Theme.amber, face: .display)
            y += 6
            for tip in ["Press Play to pick a world or join a friend.",
                        "Cosmetics: choose a hat, outfit, cape or dino tail. Friends see it in multiplayer.",
                        "Settings: texture packs, shader packs, controls and more.",
                        "The launcher checks for new versions each time it opens."] {
                wrapped(tip, 15, Theme.textMuted)
                y += 6
            }
        }

        // Buttons
        let bx = panel.maxX + 40, bw = min(400, W - bx - 30), bh: Float = 56, gap: Float = 14
        var by = top
        if ui.button("launcher.play", "Play", Rect(bx, by, bw, bh + 8), style: .primary) {
            e.popScreen()
            return
        }
        by += bh + 8 + gap

        var label = "Check for Updates", enabled = true, style = ButtonStyle.secondary
        var status = BuildInfo.current.displayName
        var action: (() -> Void)? = { e.updater.check() }
        switch e.updater.state {
        case .idle:
            break
        case .checking:
            label = "Checking for Updates…"; enabled = false; action = nil
        case .upToDate(let release):
            label = "Up to Date"
            status = release.map { BuildInfo.current.isDevelopment ? "Newest release is build \($0.build)" : "You have the newest build (\($0.build))" }
                ?? "No releases published yet"
        case .available(let release, let canInstall):
            if canInstall {
                label = "Update to Build \(release.build)"; style = .primary
                action = { e.updater.download() }
                status = "A new version is ready to download"
            } else {
                label = "Build \(release.build) Available"; enabled = false; action = nil
                status = BuildInfo.current.isDevelopment ? "This copy was built by hand, so it can't update itself"
                    : "This release has no Mac download yet"
            }
        case .downloading(let release, let fraction):
            label = "Downloading… \(Int(fraction * 100))%"; enabled = false; action = nil
            status = "Build \(release.build)"
            d.fill(Rect(bx, by + bh + 3, bw, 5), Color(linear: 0, 0, 0, 0.45), radius: 2.5)
            d.fill(Rect(bx, by + bh + 3, bw * Float(fraction), 5), Theme.amber, radius: 2.5)
        case .downloaded(let release, let file):
            label = "Restart to Update"; style = .primary
            status = "Build \(release.build) downloaded"
            action = { [weak self] in
                if let error = MacUpdater.install(zip: file) {
                    self?.installError = error
                } else {
                    e.quitGame()
                }
            }
        case .failed(let reason):
            label = "Try Again"
            status = reason
        }
        if ui.button("launcher.update", label, Rect(bx, by, bw, bh), style: style, enabled: enabled), let action { action() }
        by += bh + 12
        d.text(installError ?? status, x: bx, y: by, size: 13.5, color: installError != nil ? Theme.danger : Theme.textMuted, maxWidth: bw)
        by += 30
        if ui.button("launcher.cosmetics", "Cosmetics", Rect(bx, by, bw, bh), style: .secondary) { e.pushScreen(CosmeticsScreen()) }
        by += bh + gap
        if ui.button("launcher.settings", "Settings", Rect(bx, by, bw, bh), style: .secondary) { e.pushScreen(SettingsScreen()) }
        by += bh + gap
        if ui.button("launcher.quit", "Quit", Rect(bx, by, bw, bh), style: .secondary) { e.quitGame() }

        d.text("DinoCraft \(e.versionString) · \(BuildInfo.current.displayName)", x: 22, y: H - 34, size: 13, color: Theme.textMuted,
               shadow: Color(linear: 0, 0, 0, 0.6))
        d.opacity = 1
    }
}

// MARK: - Cosmetics

/// Choose a hat, outfit colours and something to wear on your back. Friends see it in multiplayer.
final class CosmeticsScreen: Screen {
    override var scene: GameActivityState.Scene { .mainMenu }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        MenuBackdrop.draw(ui)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        let panel = Rect(max(30, W / 2 - 520), max(30, H / 2 - 330), min(1040, W - 60), min(660, H - 60))
        ui.panel(panel, title: "Cosmetics")
        d.text("Friends see your look in multiplayer, on Mac and Windows.", x: panel.midX, y: panel.y + 66, size: 14,
               color: Theme.textMuted, align: .center)

        var look = PlayerLook(encoded: e.settings.cosmetics) ?? PlayerLook.defaultLook(for: e.settings.username)
        let before = look

        // Front view of the explorer, drawn from the same boxes the 3D model uses.
        let preview = Rect(panel.x + 40, panel.y + 110, panel.w * 0.36, panel.h - 200)
        d.fill(preview, Color(linear: 0, 0, 0, 0.25), radius: 18)
        CosmeticsScreen.drawFront(d, look, in: preview)

        // Choices
        let x = preview.maxX + 40, w = panel.maxX - 40 - x
        var y = panel.y + 110
        let rowH: Float = 50
        func row(_ id: String, _ title: String, _ value: String, minus: () -> Void, plus: () -> Void) {
            d.fill(Rect(x, y, w, rowH), Color(linear: 0, 0, 0, 0.22), radius: 12)
            d.text(title, x: x + 16, y: y + 15, size: 17, color: Theme.text)
            let bw: Float = 44, valueW: Float = min(220, w * 0.45)
            let bx = x + w - bw * 2 - valueW - 8
            if ui.button(id + ".minus", "‹", Rect(bx, y + 5, bw, rowH - 10), style: .secondary, fontSize: 22) { minus() }
            d.text(value, x: bx + bw + valueW / 2, y: y + 15, size: 17, color: Theme.amber, align: .center)
            if ui.button(id + ".plus", "›", Rect(bx + bw + valueW, y + 5, bw, rowH - 10), style: .secondary, fontSize: 22) { plus() }
            y += rowH + 10
        }
        func cycle(_ i: inout Int, _ count: Int, _ step: Int) { i = (i + step + count) % count }
        let hats = PlayerLook.Hat.allCases, backs = PlayerLook.Back.allCases
        var hatIndex = hats.firstIndex(of: look.hat) ?? 0, backIndex = backs.firstIndex(of: look.back) ?? 0
        row("cos.hat", "Hat", look.hat.displayName, minus: { cycle(&hatIndex, hats.count, -1) }, plus: { cycle(&hatIndex, hats.count, 1) })
        row("cos.shirt", "Shirt", PlayerLook.shirtNames[look.shirt], minus: { cycle(&look.shirt, PlayerLook.shirtColors.count, -1) },
            plus: { cycle(&look.shirt, PlayerLook.shirtColors.count, 1) })
        row("cos.pants", "Trousers", PlayerLook.pantsNames[look.pants], minus: { cycle(&look.pants, PlayerLook.pantsColors.count, -1) },
            plus: { cycle(&look.pants, PlayerLook.pantsColors.count, 1) })
        row("cos.skin", "Skin", PlayerLook.skinNames[look.skin], minus: { cycle(&look.skin, PlayerLook.skinTones.count, -1) },
            plus: { cycle(&look.skin, PlayerLook.skinTones.count, 1) })
        row("cos.back", "On your back", look.back.displayName, minus: { cycle(&backIndex, backs.count, -1) }, plus: { cycle(&backIndex, backs.count, 1) })
        row("cos.accent", "Accent colour", PlayerLook.accentNames[look.accent],
            minus: { cycle(&look.accent, PlayerLook.accentColors.count, -1) }, plus: { cycle(&look.accent, PlayerLook.accentColors.count, 1) })
        look.hat = hats[hatIndex]
        look.back = backs[backIndex]

        let half = (w - 12) / 2
        if ui.button("cos.random", "Surprise Me", Rect(x, y + 6, half, 50), style: .secondary) {
            look.hat = hats.randomElement()!
            look.back = backs.randomElement()!
            look.shirt = Int.random(in: 0..<PlayerLook.shirtColors.count)
            look.pants = Int.random(in: 0..<PlayerLook.pantsColors.count)
            look.skin = Int.random(in: 0..<PlayerLook.skinTones.count)
            look.accent = Int.random(in: 0..<PlayerLook.accentColors.count)
        }
        if ui.button("cos.reset", "Reset", Rect(x + half + 12, y + 6, half, 50), style: .secondary) {
            look = PlayerLook.defaultLook(for: e.settings.username)
        }
        if look != before { e.settingsStore.update { $0.cosmetics = look.encoded } }
        if ui.button("cos.done", "Done", Rect(panel.midX - 160, panel.maxY - 74, 320, 52), style: .primary) { back(e) }
    }

    /// Draws the explorer from the front: every box of the model as a flat rectangle, back to front.
    static func drawFront(_ d: UIRenderer, _ look: PlayerLook, in r: Rect) {
        var boxes: [(z: Float, rect: Rect, color: Color)] = []
        let scale = min(r.w / 1.4, r.h / 2.5)
        let cx = r.midX, feet = r.maxY - 20
        for part in PlayerAvatar.parts(look) {
            for box in part.boxes {
                let lo = part.pivot + box.0, hi = part.pivot + box.1
                // Seen from the front, the explorer's +x side is on the viewer's left.
                let rect = Rect(cx - hi.x * scale, feet - hi.y * scale, (hi.x - lo.x) * scale, (hi.y - lo.y) * scale)
                boxes.append((lo.z, rect, Color(linear: box.2.x, box.2.y, box.2.z, 1)))
            }
        }
        for b in boxes.sorted(by: { $0.z > $1.z }) { d.fill(b.rect, b.color) }
    }
}

// MARK: - Installing updates

/// Replaces this DinoCraft.app with a downloaded one. The app can't replace itself while it runs, so
/// a small script waits for it to quit, swaps the bundles and opens the new version. Worlds and
/// settings live in Application Support, so they're untouched.
enum MacUpdater {
    /// Returns an error message, or nil when DinoCraft should now quit to finish the update.
    static func install(zip: URL) -> String? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app" else { return "Updates install into DinoCraft.app; this copy isn't running from an app." }
        let fm = FileManager.default
        let unpacked = zip.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        try? fm.removeItem(at: unpacked)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, unpacked.path]
        do {
            try ditto.run()
            ditto.waitUntilExit()
        } catch {
            return "Couldn't unpack the update: \(error.localizedDescription)"
        }
        let newApp = unpacked.appendingPathComponent("DinoCraft.app")
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: newApp.appendingPathComponent("Contents/MacOS/DinoCraft").path) else {
            return "The update download was damaged. Try again."
        }
        guard fm.isWritableFile(atPath: app.deletingLastPathComponent().path) else {
            return "DinoCraft can't write to \(app.deletingLastPathComponent().path). Move DinoCraft.app to a folder you own and try again."
        }
        func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.5; done
        rm -rf \(quote(app.path))
        /usr/bin/ditto \(quote(newApp.path)) \(quote(app.path))
        /usr/bin/xattr -dr com.apple.quarantine \(quote(app.path)) 2>/dev/null
        /usr/bin/open \(quote(app.path))

        """
        let scriptURL = zip.deletingLastPathComponent().appendingPathComponent("update.sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let runner = Process()
            runner.executableURL = URL(fileURLWithPath: "/bin/sh")
            runner.arguments = [scriptURL.path]
            try runner.run()
        } catch {
            return "Couldn't start the updater: \(error.localizedDescription)"
        }
        Log.info("Update ready: \(newApp.path) → \(app.path)", category: "Update")
        return nil
    }
}
