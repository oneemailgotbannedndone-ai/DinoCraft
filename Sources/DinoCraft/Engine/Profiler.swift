import Foundation
import QuartzCore
import Darwin

/// Frame timing and resource statistics for the developer overlay.
final class Profiler {
    private var frameTimes = [Double](repeating: 1.0 / 60, count: 240)
    private var cursor = 0
    private var lastFPSUpdate = CACurrentMediaTime()
    private var framesSinceUpdate = 0

    private(set) var fps: Double = 0
    private(set) var frameMs: Double = 0
    private(set) var worstFrameMs: Double = 0
    private(set) var updateMs: Double = 0
    private(set) var encodeMs: Double = 0
    private(set) var gpuMs: Double = 0
    private(set) var memoryMB: Double = 0

    private var sectionStart: Double = 0

    func frame(dt: Double) {
        frameTimes[cursor] = dt
        cursor = (cursor + 1) % frameTimes.count
        framesSinceUpdate += 1
        let now = CACurrentMediaTime()
        if now - lastFPSUpdate >= 0.5 {
            fps = Double(framesSinceUpdate) / (now - lastFPSUpdate)
            framesSinceUpdate = 0
            lastFPSUpdate = now
            frameMs = frameTimes.reduce(0, +) / Double(frameTimes.count) * 1000
            worstFrameMs = (frameTimes.max() ?? 0) * 1000
            memoryMB = Profiler.memoryFootprintMB()
        }
    }

    func begin() { sectionStart = CACurrentMediaTime() }
    func endUpdate() { updateMs = updateMs * 0.9 + (CACurrentMediaTime() - sectionStart) * 1000 * 0.1; sectionStart = CACurrentMediaTime() }
    func endEncode() { encodeMs = encodeMs * 0.9 + (CACurrentMediaTime() - sectionStart) * 1000 * 0.1 }
    func recordGPU(_ seconds: Double) { gpuMs = gpuMs * 0.9 + seconds * 1000 * 0.1 }

    /// Recent frame times (seconds), oldest first, for the frame graph.
    var history: [Double] { Array(frameTimes[cursor...] + frameTimes[..<cursor]) }

    static func memoryFootprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }
}
