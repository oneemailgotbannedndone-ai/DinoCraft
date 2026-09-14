import Foundation
import DinoCraftCore

/// Per-worker scratch state. Each worker thread owns one mesher so meshing
/// never allocates its large lighting/meshing buffers per job.
final class WorkerContext {
    let index: Int
    let mesher: ChunkMesher
    init(index: Int, mesher: ChunkMesher) { self.index = index; self.mesher = mesher }
}

/// Fixed pool of long-lived worker threads pulling from a priority queue
/// (lowest value first). Used for terrain generation, chunk loading, lighting
/// and meshing so the main thread only integrates finished results.
final class JobSystem: @unchecked Sendable {
    private struct Job {
        let priority: Int
        let sequence: UInt64
        let group: Int
        let work: (WorkerContext) -> Void
    }

    private let condition = NSCondition()
    private var queue: [Job] = []
    private var sequence: UInt64 = 0
    private var threads: [Thread] = []
    private var contexts: [WorkerContext] = []
    private var running = true
    private var active = 0

    let workerCount: Int

    init(workerCount: Int, makeContext: (Int) -> WorkerContext) {
        self.workerCount = workerCount
        for i in 0..<workerCount {
            let ctx = makeContext(i)
            contexts.append(ctx)
            let thread = Thread { [unowned self] in self.workerLoop(ctx) }
            thread.name = "DinoCraft Worker \(i + 1)"
            #if canImport(ObjectiveC)
            thread.qualityOfService = .userInitiated
            thread.stackSize = 1 << 21
            #else
            thread.stackSize = 1 << 22
            #endif
            threads.append(thread)
            thread.start()
        }
        Log.info("Job system started with \(workerCount) workers", category: "Jobs")
    }

    private func workerLoop(_ ctx: WorkerContext) {
        while true {
            condition.lock()
            while queue.isEmpty && running { condition.wait() }
            if !running { condition.unlock(); return }
            var best = 0
            for i in 1..<queue.count where queue[i].priority < queue[best].priority ||
                (queue[i].priority == queue[best].priority && queue[i].sequence < queue[best].sequence) {
                best = i
            }
            queue.swapAt(best, queue.count - 1)
            let job = queue.removeLast()
            active += 1
            condition.unlock()

            #if canImport(ObjectiveC)
            autoreleasepool { job.work(ctx) }
            #else
            job.work(ctx)
            #endif

            condition.lock()
            active -= 1
            condition.broadcast()
            condition.unlock()
        }
    }

    func submit(priority: Int, group: Int = 0, _ work: @escaping (WorkerContext) -> Void) {
        condition.lock()
        sequence &+= 1
        queue.append(Job(priority: priority, sequence: sequence, group: group, work: work))
        condition.signal()
        condition.unlock()
    }

    /// Drops queued (not yet started) jobs belonging to a group.
    func cancel(group: Int) {
        condition.lock()
        queue.removeAll { $0.group == group }
        condition.unlock()
    }

    var queuedCount: Int {
        condition.lock(); defer { condition.unlock() }
        return queue.count
    }

    var activeCount: Int {
        condition.lock(); defer { condition.unlock() }
        return active
    }

    /// Blocks until the queue is empty and no job is running (bounded by timeout).
    func waitUntilIdle(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        condition.lock()
        while (!queue.isEmpty || active > 0) && Date() < deadline {
            _ = condition.wait(until: min(deadline, Date().addingTimeInterval(0.05)))
        }
        condition.unlock()
    }

    func shutdown() {
        condition.lock()
        running = false
        queue.removeAll()
        condition.broadcast()
        condition.unlock()
    }

    /// Applies new mesher settings (e.g. fancy leaves) to every worker. Takes
    /// effect for jobs that start afterwards.
    func forEachContext(_ body: (WorkerContext) -> Void) {
        condition.lock()
        contexts.forEach(body)
        condition.unlock()
    }
}
