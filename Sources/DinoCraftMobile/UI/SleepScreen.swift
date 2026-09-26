import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// Fades to night-blue while the player sleeps, then wakes them at dawn.
final class SleepScreen: Screen {
    private var elapsed: Float = 0
    private var woke = false

    override var isOverlay: Bool { true }
    override var scene: GameActivityState.Scene { .playing }
    override func back(_ engine: GameEngine) {}   // can't cancel mid-sleep

    override func draw(_ ui: UIContext, _ e: GameEngine) {
        guard let s = e.session else { e.popScreen(); return }
        elapsed += min(0.1, ui.dt)
        let fadeIn = min(1, elapsed / 1.2)
        let fadeOut = max(0, (elapsed - 2.4) / 0.8)
        let darkness = fadeIn * (1 - fadeOut)
        let d = ui.draw
        d.fill(Rect(0, 0, ui.size.x, ui.size.y), Color(hex: 0x05030C, alpha: darkness * 0.96))
        d.text("Sleeping…", x: ui.size.x / 2, y: ui.size.y / 2 - 20, size: 30, color: Theme.text.alpha(darkness), face: .display, align: .center)
        if elapsed > 2.0 && !woke {
            woke = true
            s.wakeUp()
        }
        if elapsed > 3.2 {
            e.popScreen()
            e.showToast("Good morning!")
        }
    }
}
