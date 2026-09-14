import Foundation
import simd
import DinoCraftCore

enum Username {
    static func validate(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return "At least 3 characters" }
        guard trimmed.count <= 16 else { return "At most 16 characters" }
        guard trimmed.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else { return "Letters, numbers and _ only" }
        return nil
    }
}

/// Shown on first launch (and from the main menu) to choose the explorer name
/// used for multiplayer name tags and chat.
final class UsernameScreen: Screen {
    private var name: String
    private let firstRun: Bool

    init(current: String, firstRun: Bool) {
        name = current
        self.firstRun = firstRun
    }

    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .mainMenu }
    override func back(_ engine: GameEngine) {
        guard !firstRun || Username.validate(engine.settings.username) == nil else { return }
        super.back(engine)
    }

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        if age == 0 { ui.focusedID = "modal.username" }
        let a = appear(0, duration: 0.35)
        ui.dim(0.7 * a)
        let d = ui.draw
        let W = ui.size.x, H = ui.size.y
        d.opacity = a
        let p = Rect(W / 2 - 280, H / 2 - 190 + (1 - a) * 20, 560, 380)
        ui.panel(p)
        if let icon = e.iconTexture { d.image(icon, Rect(p.midX - 36, p.y + 22, 72, 72)) }
        d.text(firstRun ? "Welcome, Explorer!" : "Change Your Name", in: Rect(p.x, p.y + 104, p.w, 40), size: 28, color: Theme.text, face: .display)
        d.text("Choose the name your friends will see above your head.", in: Rect(p.x, p.y + 146, p.w, 24), size: 15, color: Theme.textMuted)

        let field = Rect(p.x + 60, p.y + 190, p.w - 120, 54)
        let submitted = ui.textField("modal.username", field, &name, placeholder: "Username", maxLength: 16)
        let problem = Username.validate(name)
        if let problem, !name.isEmpty {
            d.text(problem, in: Rect(p.x, field.maxY + 8, p.w, 22), size: 13.5, color: Theme.danger)
        } else if problem == nil {
            d.text("Looking good!", in: Rect(p.x, field.maxY + 8, p.w, 22), size: 13.5, color: Theme.jungle)
        }
        let valid = problem == nil
        if ui.button("modal.username.ok", firstRun ? "Start Exploring" : "Save", Rect(p.midX - 150, p.maxY - 84, 300, 56), enabled: valid) || (submitted && valid) {
            let final = name.trimmingCharacters(in: .whitespaces)
            e.settingsStore.update { $0.username = final }
            Log.info("Username set to \(final)", category: "Profile")
            e.popScreen()
        }
        d.opacity = 1
    }
}
