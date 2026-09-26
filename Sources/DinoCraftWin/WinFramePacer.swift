import Foundation
import CSDL3
import DinoCraftCore

/// Keeps frames at the monitor's refresh rate when VSync is on but the driver doesn't honour it (it happens on
/// some dual-GPU laptops, and shows up as tearing or flicker in menus with frames racing far past the display).
final class FramePacer {
    private let window: OpaquePointer
    private var last = 0.0
    private var intervals: [Double] = []
    private var ignored = false

    init(window: OpaquePointer) { self.window = window }

    private var refreshRate: Double {
        let display = SDL_GetDisplayForWindow(window)
        guard display != 0, let mode = SDL_GetCurrentDisplayMode(display), mode.pointee.refresh_rate > 20 else { return 60 }
        return Double(mode.pointee.refresh_rate)
    }

    /// Call right after swapping buffers each frame.
    func frameDone(vsync: Bool) {
        var now = Date.timeIntervalSinceReferenceDate
        defer { last = now }
        guard vsync, last > 0 else { intervals.removeAll(); return }
        if ignored {
            let spare = 1 / refreshRate - (now - last)
            if spare > 0.001 { SDL_Delay(UInt32(spare * 1000)) }
            now = Date.timeIntervalSinceReferenceDate
            return
        }
        intervals.append(now - last)
        guard intervals.count >= 90 else { return }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        intervals.removeAll()
        if average < 0.55 / refreshRate {
            ignored = true
            Log.warning("VSync is on but the driver isn't waiting for the display (\(Int(1 / average)) fps on a \(Int(refreshRate)) Hz screen); pacing frames instead", category: "Renderer")
        }
    }
}
