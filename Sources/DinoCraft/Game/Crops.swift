import Foundation
import DinoCraftCore

/// Planted wheat and carrots. Single-player worlds and multiplayer hosts grow them;
/// each growth step is an ordinary block change, so friends see it too.
final class CropManager {
    /// Seed item → first growth stage.
    static let seedCrops: [String: BlockID] = ["wheat_seeds": Blocks.wheat[0], "carrot": Blocks.carrots[0]]

    static func stage(of id: BlockID) -> (stages: [BlockID], stage: Int)? {
        for stages in [Blocks.wheat, Blocks.carrots] {
            if let i = stages.firstIndex(of: id) { return (stages, i) }
        }
        return nil
    }

    private(set) var crops: Set<BlockPos> = []
    private var timer = 1.0

    func plant(_ pos: BlockPos) { crops.insert(pos) }
    func clear() { crops.removeAll() }

    /// Once a second each crop on farmland has a small chance to grow a stage (faster in the rain).
    func update(dt: Double, world: World, wet: Bool) {
        timer -= dt
        guard timer <= 0 else { return }
        timer = 1
        let chance = wet ? 1.0 / 25 : 1.0 / 40
        for pos in crops {
            guard world.isLoaded(Int(pos.x), Int(pos.z)) else { continue }
            guard let info = CropManager.stage(of: world.block(pos)) else {
                crops.remove(pos)
                continue
            }
            guard info.stage < info.stages.count - 1, world.block(pos.offset(.down)) == Blocks.farmland,
                  Double.random(in: 0..<1) < chance else { continue }
            world.setBlock(pos, info.stages[info.stage + 1])
        }
    }

    // MARK: Persistence

    private struct SavedCrops: Codable { var crops: [[Int]] }

    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            let file = try JSONDecoder().decode(SavedCrops.self, from: data)
            for c in file.crops where c.count == 3 { crops.insert(BlockPos(c[0], c[1], c[2])) }
            Log.info("Loaded \(crops.count) crops", category: "Save")
        } catch {
            Log.error("Could not read crops (\(url.lastPathComponent)): \(error)", category: "Save")
        }
    }

    func save(to url: URL) {
        guard !crops.isEmpty else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        do {
            let data = try JSONEncoder().encode(SavedCrops(crops: crops.map { [Int($0.x), Int($0.y), Int($0.z)] }))
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Could not save crops: \(error)", category: "Save")
        }
    }
}
