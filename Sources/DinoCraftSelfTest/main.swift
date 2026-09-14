import Foundation
import DinoCraftCore
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif

// Headless verification suite for DinoCraftCore.
// Run with:  swift run -c release DinoCraftSelfTest

var failures = 0
var passes = 0

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("  ✗ FAIL: \(message)  (\(file):\(line))")
    }
}

func section(_ name: String, _ body: () throws -> Void) {
    print("▸ \(name)")
    do { try body() } catch {
        failures += 1
        print("  ✗ THREW: \(error)")
    }
}

func time<T>(_ body: () -> T) -> (T, Double) {
    let t0 = Date.timeIntervalSinceReferenceDate
    let r = body()
    return (r, Date.timeIntervalSinceReferenceDate - t0)
}

Log.shared.echoToConsole = false
let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("dinocraft-selftest-\(ProcessInfo.processInfo.processIdentifier)")
try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempRoot) }

guard ResourceLocator.root != nil else {
    print("Resources folder not found. Run from the repository root or set DINOCRAFT_RESOURCES.")
    exit(2)
}

var blocks: BlockRegistry!
var items: ItemRegistry!
var recipes: RecipeRegistry!

section("Registries") {
    blocks = try BlockRegistry.loadDefault()
    items = try ItemRegistry.loadDefault(blocks: blocks)
    recipes = try RecipeRegistry.loadDefault(items: items)
    check(blocks[Blocks.stone]?.name == "stone", "stone registered with id 1")
    check(blocks.isOpaque[Int(Blocks.stone)], "stone is opaque")
    check(!blocks.isOpaque[Int(Blocks.leaves)], "leaves are not opaque")
    check(!blocks.isSolid[Int(Blocks.water)], "water has no collision")
    check(blocks.emission[Int(Blocks.torch)] == 14, "torch emits light")
    check(items.id(named: "stick") != nil, "stick item exists")
    check(items.info(named: "diamond_pickaxe")?.tool?.level == 4, "diamond pickaxe is tier 4")
    check(items.info(named: "planks")?.block == Blocks.planks, "planks item places planks")
    check(recipes.recipes.count >= 30, "recipes loaded (\(recipes.recipes.count))")
    print("  \(blocks.all.count) blocks, \(items.all.count) items, \(recipes.recipes.count) recipes, \(blocks.textureNames.count) block textures")
}

section("Noise") {
    let a = SimplexNoise(seed: 42), b = SimplexNoise(seed: 42), c = SimplexNoise(seed: 43)
    var same = true, differs = false, minV = 1.0, maxV = -1.0
    for i in 0..<5000 {
        let x = Double(i) * 0.137, y = Double(i) * 0.291, z = Double(i) * 0.071
        let va = a.noise3(x, y, z)
        if va != b.noise3(x, y, z) { same = false }
        if va != c.noise3(x, y, z) { differs = true }
        let v2 = a.noise2(x, y)
        minV = min(minV, v2, va); maxV = max(maxV, v2, va)
    }
    check(same, "noise is deterministic for a seed")
    check(differs, "different seeds give different noise")
    check(minV >= -1.05 && maxV <= 1.05, "noise range within [-1, 1] (got \(minV)...\(maxV))")
    check(Hashing.seed(from: "Dino World") == Hashing.seed(from: "Dino World"), "text seeds are stable")
    check(Hashing.seed(from: "12345") == 12345, "numeric seed text maps to the number")
}

func checksum(_ chunk: Chunk) -> UInt64 {
    var h: UInt64 = 0xCBF2_9CE4_8422_2325
    for i in 0..<WorldConst.blocksPerChunk { h = (h ^ UInt64(chunk.blocks[i])) &* 0x100_0000_01B3 }
    return h
}

section("Terrain generation") {
    let genA = TerrainGenerator(seed: 1337), genB = TerrainGenerator(seed: 1337), genC = TerrainGenerator(seed: 7)
    let positions = [ChunkPos(0, 0), ChunkPos(-3, 5), ChunkPos(40, -12), ChunkPos(-100, -100)]
    for p in positions {
        check(checksum(genA.generate(p)) == checksum(genB.generate(p)), "same seed → identical chunk \(p)")
    }
    check(checksum(genA.generate(ChunkPos(2, 2))) != checksum(genC.generate(ChunkPos(2, 2))), "different seed → different chunk")

    let chunk = genA.generate(ChunkPos(0, 0))
    check(chunk.block(3, 0, 3) == Blocks.bedrock, "bedrock floor at y=0")
    check(chunk.maxHeight > 20 && chunk.maxHeight < 256, "reasonable surface height (\(chunk.maxHeight))")

    // Generation throughput
    let batch = (0..<64).map { ChunkPos(Int32($0 % 8) + 10, Int32($0 / 8) - 20) }
    let (_, serial) = time { for p in batch { _ = genA.generate(p) } }
    print(String(format: "  generate: %.2f ms/chunk (single thread)", serial / 64 * 1000))
    let (_, parallel) = time {
        DispatchQueue.concurrentPerform(iterations: batch.count) { i in _ = genA.generate(batch[i]) }
    }
    print(String(format: "  generate: %.2f ms/chunk wall (%d cores)", parallel / 64 * 1000, ProcessInfo.processInfo.activeProcessorCount))

    // Biome variety over a large area
    var counts: [Biome: Int] = [:]
    var minH = 999, maxH = 0
    for z in stride(from: -6000, through: 6000, by: 150) {
        for x in stride(from: -6000, through: 6000, by: 150) {
            let info = genA.columnInfo(x: x, z: z)
            counts[info.biome, default: 0] += 1
            minH = min(minH, info.height); maxH = max(maxH, info.height)
        }
    }
    let summary = Biome.allCases.map { "\($0.displayName)=\(counts[$0] ?? 0)" }.joined(separator: ", ")
    print("  biomes: \(summary)")
    print("  height range: \(minH)...\(maxH)")
    check(counts.keys.count >= 9, "at least 9 biomes appear across 12 km (\(counts.keys.count))")
    check(maxH - minH > 80, "terrain is not flat (range \(maxH - minH))")

    // Caves exist underground
    var air = 0
    for cz in 0..<4 { for cx in 0..<4 {
        let c = genA.generate(ChunkPos(Int32(cx), Int32(cz)))
        for y in 8..<40 { for z in 0..<16 { for x in 0..<16 where c.block(x, y, z) == Blocks.air { air += 1 } } }
    } }
    check(air > 200, "caves carve underground air (\(air) blocks)")

    let spawn = genA.findSpawnColumn()
    let info = genA.columnInfo(x: spawn.x, z: spawn.z)
    check(info.height > WorldConst.seaLevel, "spawn is above sea level")
}

final class TestWorld: BlockSource {
    let registry: BlockRegistry
    var chunks: [ChunkPos: Chunk] = [:]
    init(_ r: BlockRegistry) { registry = r }
    func blockIfLoaded(_ x: Int, _ y: Int, _ z: Int) -> BlockID? {
        guard y >= 0 && y < WorldConst.height else { return Blocks.air }
        let p = ChunkPos(Int32(x >> 4), Int32(z >> 4))
        guard let c = chunks[p] else { return nil }
        return c.block(x & 15, y, z & 15)
    }
    func set(_ x: Int, _ y: Int, _ z: Int, _ id: BlockID) {
        let p = ChunkPos(Int32(x >> 4), Int32(z >> 4))
        chunks[p]?.set(x & 15, y, z & 15, id)
    }
}

func flatWorld(_ r: BlockRegistry, groundHeight: Int = 10) -> TestWorld {
    let w = TestWorld(r)
    for cz in -2...2 { for cx in -2...2 {
        let c = Chunk(pos: ChunkPos(Int32(cx), Int32(cz)))
        for y in 0..<groundHeight { for z in 0..<16 { for x in 0..<16 { c.setRaw(x, y, z, y == groundHeight - 1 ? Blocks.grass : Blocks.stone) } } }
        c.recomputeHeights()
        w.chunks[c.pos] = c
    } }
    return w
}

section("Meshing & lighting") {
    blocks.bindTextureLayers { name in UInt16(abs(name.hashValue) % 64) }
    let mesher = ChunkMesher(registry: blocks)

    // Flat world: top surface should merge into very few quads.
    let flat = flatWorld(blocks)
    let hood = (-1...1).flatMap { dz in (-1...1).map { dx in flat.chunks[ChunkPos(Int32(dx), Int32(dz))]! } }
    mesher.build(neighborhood: hood)
    let flatQuads = mesher.out.quadCount
    check(flatQuads >= 1 && flatQuads <= 4, "greedy meshing merges a flat 16x16 surface (\(flatQuads) quads)")
    let topSky = mesher.out.opaque.map { $0.sky }.max() ?? 0
    check(topSky == 255, "open-sky surface is fully lit (sky=\(topSky))")

    // Torch lights a sealed cave.
    let cave = flatWorld(blocks, groundHeight: 40)
    for y in 20..<24 { for z in 4..<12 { for x in 4..<12 { cave.set(x, y, z, Blocks.air) } } }
    cave.set(8, 20, 8, Blocks.torch)
    let caveHood = (-1...1).flatMap { dz in (-1...1).map { dx in cave.chunks[ChunkPos(Int32(dx), Int32(dz))]! } }
    mesher.build(neighborhood: caveHood)
    let caveVerts = mesher.out.opaque.filter { $0.y < 40 * 16 - 16 }
    let maxBlock = caveVerts.map { $0.light }.max() ?? 0
    let maxSkyInCave = caveVerts.map { $0.sky }.max() ?? 0
    check(maxBlock > 150, "torch lights the cave walls (block light \(maxBlock))")
    check(maxSkyInCave == 0, "sealed cave receives no sky light (\(maxSkyInCave))")

    // Real terrain throughput
    let gen = TerrainGenerator(seed: 99)
    var terrain: [Chunk] = []
    for dz in -1...1 { for dx in -1...1 { terrain.append(gen.generate(ChunkPos(Int32(dx), Int32(dz)))) } }
    var total = 0.0, light = 0.0, quads = 0
    for _ in 0..<10 {
        mesher.build(neighborhood: terrain)
        total += mesher.lastLightingSeconds + mesher.lastMeshSeconds
        light += mesher.lastLightingSeconds
        quads = mesher.out.quadCount
    }
    print(String(format: "  terrain mesh: %.2f ms (lighting %.2f ms), %d quads", total / 10 * 1000, light / 10 * 1000, quads))
    check(quads > 50, "terrain produces geometry")
    check(mesher.out.opaque.count % 4 == 0 && mesher.out.cutout.count % 4 == 0 && mesher.out.translucent.count % 4 == 0, "vertex counts are whole quads")
    check(MemoryLayout<ChunkVertex>.stride == 18, "ChunkVertex is 18 bytes (\(MemoryLayout<ChunkVertex>.stride))")
    let maxCoord = (mesher.out.opaque + mesher.out.cutout + mesher.out.translucent).map { max($0.x, $0.z) }.max() ?? 0
    check(maxCoord <= 256, "vertex positions stay within the chunk (\(maxCoord))")
}

section("Physics") {
    let world = flatWorld(blocks)
    let player = PlayerController(position: DVec3(0.5, 20, 0.5))
    var input = MovementInput()
    for _ in 0..<240 { player.update(dt: 1.0 / 60, input: input, world: world) }
    check(player.onGround, "player lands on the ground")
    check(abs(player.position.y - 10) < 0.01, "player rests on top of the surface (y=\(player.position.y))")

    // Jump apex
    input.jump = true
    var apex = player.position.y
    for i in 0..<60 {
        player.update(dt: 1.0 / 60, input: input, world: world)
        if i == 1 { input.jump = false }
        apex = max(apex, player.position.y)
    }
    let jumpHeight = apex - 10
    check(jumpHeight > 1.05 && jumpHeight < 1.5, "jump clears one block (\(String(format: "%.2f", jumpHeight)))")

    // Wall collision
    for y in 10..<13 { for z in -3...3 { world.set(3, y, z, Blocks.stone) } }
    input = MovementInput()
    player.teleport(to: DVec3(0.5, 10, 0.5))
    player.yaw = -Double.pi / 2   // face +X
    input.forward = 1
    for _ in 0..<180 { player.update(dt: 1.0 / 60, input: input, world: world) }
    check(player.position.x <= 3 - 0.3 + 1e-6 && player.position.x > 2.5, "wall stops the player (x=\(player.position.x))")

    // Sprint is faster than walking
    let open = flatWorld(blocks)
    let a = PlayerController(position: DVec3(0.5, 10, 0.5)), b = PlayerController(position: DVec3(0.5, 10, 0.5))
    var walk = MovementInput(); walk.forward = 1
    var sprint = walk; sprint.sprint = true
    for _ in 0..<60 { a.update(dt: 1.0 / 60, input: walk, world: open); b.update(dt: 1.0 / 60, input: sprint, world: open) }
    check(abs(b.position.z) > abs(a.position.z) * 1.2, "sprinting covers more ground")

    // Sneaking prevents walking off a ledge
    let ledge = flatWorld(blocks)
    for z in -40..<40 { for x in 2..<40 { ledge.set(x, 9, z, Blocks.air) } }
    let s = PlayerController(position: DVec3(0.5, 10, 0.5))
    s.yaw = -Double.pi / 2
    var sneak = MovementInput(); sneak.forward = 1; sneak.sneak = true
    for _ in 0..<5 { s.update(dt: 1.0 / 60, input: MovementInput(), world: ledge) }
    for _ in 0..<240 { s.update(dt: 1.0 / 60, input: sneak, world: ledge) }
    check(s.position.y > 9.99 && s.position.x < 2.4, "sneaking keeps the player on the ledge (x=\(s.position.x), y=\(s.position.y))")

    // Raycast
    let hit = VoxelPhysics.raycast(world, origin: DVec3(0.5, 11.6, 0.5), direction: DVec3(1, 0, 0), maxDistance: 6)
    check(hit?.block == BlockPos(3, 11, 0), "raycast hits the wall block")
    check(hit?.face == .west, "raycast reports the entry face")
    let down = VoxelPhysics.raycast(world, origin: DVec3(0.5, 11.6, 0.5), direction: DVec3(0, -1, 0), maxDistance: 6)
    check(down?.block == BlockPos(0, 9, 0) && down?.face == .up, "raycast down hits the ground top face")
    check(down.map { $0.adjacent == BlockPos(0, 10, 0) } ?? false, "placement cell is above the ground")
}

section("Inventory") {
    let inv = Inventory(registry: items)
    let dirt = items.id(named: "dirt")!, pick = items.id(named: "stone_pickaxe")!
    check(inv.add(ItemStack(item: dirt, count: 100)) == 0, "100 dirt fits")
    check(inv.slots[0]?.count == 64 && inv.slots[1]?.count == 36, "stacks split at 64")
    check(inv.add(ItemStack(item: pick, count: 2)) == 0, "tools added one per slot")
    check(inv.slots[2]?.count == 1 && inv.slots[3]?.item == pick, "tools don't stack")
    check(inv.count(of: dirt) == 100, "count reports total")

    var slot: ItemStack? = ItemStack(item: dirt, count: 10)
    var cursor: ItemStack? = nil
    SlotInteraction.click(&slot, cursor: &cursor, button: .right, maxStack: inv.maxStack)
    check(cursor?.count == 5 && slot?.count == 5, "right-click splits a stack in half")
    SlotInteraction.click(&slot, cursor: &cursor, button: .left, maxStack: inv.maxStack)
    check(slot?.count == 10 && cursor == nil, "left-click merges back")

    inv.selected = 2
    for _ in 0..<150 { inv.damageSelectedTool() }
    check(inv.slots[2] == nil, "tool breaks at durability")
    inv.selected = -1
    check(inv.selected == 8, "hotbar selection wraps")
    for _ in 0..<5 { _ = inv.add(ItemStack(item: dirt, count: 64)) }
    let leftover = inv.add(ItemStack(item: dirt, count: 64 * 40))
    check(leftover > 0, "full inventory reports leftovers")
}

section("Crafting") {
    let log = items.id(named: "log")!, planks = items.id(named: "planks")!, stick = items.id(named: "stick")!
    let cobble = items.id(named: "cobblestone")!
    func g(_ ids: [ItemID?]) -> [ItemStack?] { ids.map { $0.map { ItemStack(item: $0, count: 1) } } }

    check(recipes.match(grid: g([log, nil, nil, nil]), size: 2)?.result == ItemStack(item: planks, count: 4), "log → 4 planks in 2x2")
    check(recipes.match(grid: g([nil, nil, nil, log]), size: 2)?.result.item == planks, "shapeless recipe anywhere in grid")
    check(recipes.match(grid: g([nil, planks, nil, planks]), size: 2)?.result.item == stick, "sticks from vertical planks")
    check(recipes.match(grid: g([planks, planks, planks, planks]), size: 2)?.result.item == items.id(named: "crafting_bench"), "crafting bench from 4 planks")
    let pickGrid = g([cobble, cobble, cobble, nil, stick, nil, nil, stick, nil])
    check(recipes.match(grid: pickGrid, size: 3)?.result.item == items.id(named: "stone_pickaxe"), "stone pickaxe shaped recipe")
    let mossy = items.id(named: "mossy_cobblestone")!
    check(recipes.match(grid: g([mossy, cobble, mossy, nil, stick, nil, nil, stick, nil]), size: 3)?.result.item == items.id(named: "stone_pickaxe"), "tag ingredients match any member")
    let axeLeft = g([planks, planks, nil, planks, stick, nil, nil, stick, nil])
    let axeRight = g([nil, planks, planks, nil, stick, planks, nil, stick, nil])
    check(recipes.match(grid: axeLeft, size: 3)?.result.item == items.id(named: "wooden_axe"), "axe recipe")
    check(recipes.match(grid: axeRight, size: 3)?.result.item == items.id(named: "wooden_axe"), "mirrored axe recipe")
    check(recipes.match(grid: g([stick, log, planks, cobble]), size: 2) == nil, "nonsense grid has no recipe")
    var grid = g([log, log, nil, nil])
    grid[0]!.count = 3
    RecipeRegistry.consumeIngredients(grid: &grid)
    check(grid[0]?.count == 2 && grid[1] == nil, "crafting consumes one of each ingredient")
}

func persistenceTests() throws {
    let gen = TerrainGenerator(seed: 5)
    let chunk = gen.generate(ChunkPos(-7, 3))
    chunk.set(1, 100, 1, Blocks.amberLantern)
    let data = try chunk.serialize()
    let restored = try Chunk.deserialize(data, expected: ChunkPos(-7, 3))
    check(checksum(restored) == checksum(chunk), "chunk round-trips through the portable codec")
    check(restored.maxHeight == chunk.maxHeight, "heightmap rebuilt on load")
    print("  chunk file size: \(data.count) bytes (raw \(WorldConst.blocksPerChunk))")
    check(data.count < WorldConst.blocksPerChunk / 4, "chunk data compresses well (\(data.count) bytes)")
    check((try? Chunk.deserialize(data, expected: ChunkPos(0, 0))) == nil, "chunk position mismatch is rejected")
    var corrupt = data; corrupt[20] ^= 0xFF; corrupt[40] ^= 0xFF
    _ = try? Chunk.deserialize(corrupt, expected: ChunkPos(-7, 3))   // must not crash
    check((try? Chunk.deserialize(data.prefix(data.count / 2), expected: ChunkPos(-7, 3))) == nil, "truncated chunk data is rejected")
    var noise = data.prefix(16)
    for i in 0..<4000 { noise.append(UInt8(truncatingIfNeeded: i &* 2_654_435_761 >> 13)) }
    _ = try? Chunk.deserialize(noise, expected: ChunkPos(-7, 3))   // random payload must not crash

    let storage = WorldStorage(root: tempRoot.appendingPathComponent("worlds"))
    let meta = try storage.createWorld(name: "Dino World", seedText: "Dino World", gameMode: .survival, difficulty: .normal)
    let meta2 = try storage.createWorld(name: "Dino World", seedText: "", gameMode: .creative, difficulty: .easy)
    check(meta.id != meta2.id, "duplicate names get unique folders")
    check(meta.numericSeed == Hashing.seed(from: "Dino World"), "seed text stored deterministically")
    try storage.writeChunkData(data, worldID: meta.id, pos: ChunkPos(-7, 3))
    check(storage.loadChunk(worldID: meta.id, pos: ChunkPos(-7, 3)).map(checksum) == checksum(chunk), "chunk saved and loaded from disk")
    let player = PlayerSave(x: 1.5, y: 70, z: -3.25, yaw: 1, pitch: -0.2, health: 17, hunger: 12, saturation: 2, air: 10,
                            flying: false, selectedSlot: 4, inventory: [SavedStack(slot: 0, item: "torch", count: 12, damage: nil)])
    try storage.savePlayer(player, id: meta.id)
    let loadedPlayer = storage.loadPlayer(id: meta.id)
    check(loadedPlayer?.z == -3.25 && loadedPlayer?.inventory.first?.item == "torch", "player save round-trips")
    check(storage.listWorlds().count == 2, "world list shows both worlds")
    try storage.deleteWorld(id: meta2.id)
    check(storage.listWorlds().count == 1, "world deleted")

    let settingsURL = tempRoot.appendingPathComponent("settings.json")
    try Data(#"{"fov": 300, "renderDistance": 8, "bogus": true, "bindings": {"jump": {"kind":"key","code":36}}}"#.utf8).write(to: settingsURL)
    let store = SettingsStore(url: settingsURL)
    check(store.settings.fov == 110, "settings clamp out-of-range values")
    check(store.settings.renderDistance == 8, "settings keep valid values")
    check(store.settings.binding(for: .jump) == .key(36), "custom keybind loads")
    check(store.settings.binding(for: .forward) == .key(13), "missing keybinds use defaults")
}
section("Persistence", persistenceTests)

section("Villages") {
    let gen = TerrainGenerator(seed: 1234)
    let near = gen.villages(near: 0, z: 0, radius: 2500)
    check(!near.isEmpty, "villages generate within 2500 blocks of spawn")
    check(near == TerrainGenerator(seed: 1234).villages(near: 0, z: 0, radius: 2500), "village placement is deterministic")
    if let v = near.first {
        let chunk = gen.generate(ChunkPos(Int32(v.x >> 4), Int32(v.z >> 4)))
        var water = 0, cobble = 0
        for dz in -2...2 { for dx in -2...2 {
            let lx = (v.x + dx) - Int(chunk.pos.originX), lz = (v.z + dz) - Int(chunk.pos.originZ)
            guard (0..<16).contains(lx), (0..<16).contains(lz) else { continue }
            if chunk.block(lx, v.y - 1, lz) == Blocks.water { water += 1 }
            if chunk.block(lx, v.y, lz) == Blocks.cobblestone { cobble += 1 }
        } }
        check(water > 0 && cobble > 0, "village well is built at the plaza (water \(water), rim \(cobble))")
        var doors = 0
        for cz in -3...3 { for cx in -3...3 {
            let c = gen.generate(ChunkPos(Int32(v.x >> 4) + Int32(cx), Int32(v.z >> 4) + Int32(cz)))
            for i in 0..<WorldConst.blocksPerChunk where Blocks.doorLowerClosed.contains(c.blocks[i]) { doors += 1 }
        } }
        check(doors >= 3, "village houses have doors (\(doors))")
        print("  nearest village at \(v.x), \(v.y), \(v.z) with \(doors) doors")
    }
}

section("Structures") {
    let gen = TerrainGenerator(seed: 1234)
    let list = gen.structures(near: 0, z: 0, radius: 1200)
    check(list.contains { $0.kind == .dungeon }, "dungeons generate near spawn")
    check(list.contains { $0.kind == .ruin || $0.kind == .desertRuin }, "ruins generate near spawn")
    check(list == TerrainGenerator(seed: 1234).structures(near: 0, z: 0, radius: 1200), "structure placement is deterministic")
    if let d = list.first(where: { $0.kind == .dungeon }) {
        let c = gen.generate(ChunkPos(Int32(d.x >> 4), Int32(d.z >> 4)))
        let lx = d.x - Int(c.pos.originX), lz = d.z - Int(c.pos.originZ)
        check(c.block(lx, d.y, lz) == Blocks.air && c.block(lx, d.y + 1, lz) == Blocks.air, "dungeon room is hollow")
        let floor = c.block(lx, d.y - 1, lz)
        check([Blocks.cobblestone, Blocks.mossyCobblestone, Blocks.fossilStone].contains(floor), "dungeon has a stone floor")
        check(gen.lootTable(x: d.x - 3, y: d.y, z: d.z) == "dungeon", "dungeon chest has a loot table")
        print("  nearest dungeon at \(d.x), \(d.y), \(d.z)")
    }
    if let r = list.first(where: { $0.kind != .dungeon }) {
        let chest = gen.chestPositions(r)[0]
        let c = gen.generate(ChunkPos(Int32(chest.x >> 4), Int32(chest.z >> 4)))
        let id = c.block(chest.x - Int(c.pos.originX), chest.y, chest.z - Int(c.pos.originZ))
        check(Blocks.chest.contains(id), "\(r.kind.displayName) chest is placed")
        print("  nearest \(r.kind.displayName.lowercased()) at \(r.x), \(r.y), \(r.z)")
    }
    check(gen.lootTable(x: 5, y: 3, z: 5) == nil, "ordinary positions have no loot table")
}

section("Building blocks & world detail") {
    let reg = try BlockRegistry.loadDefault()
    check(reg.all.count >= 220, "block registry has \(reg.all.count) blocks")
    if let stairs = reg.id(named: "cobblestone_stairs_north") {
        check(reg.shapeBoxes[Int(stairs)].count == 2, "stairs are built from two boxes")
        check(reg.boxes[Int(stairs)] == BlockBox([0, 0, 0, 16, 16, 16]), "stairs bounds cover the whole cell")
    } else {
        check(false, "stairs are registered")
    }
    let gen = TerrainGenerator(seed: 777)
    var counts: [BlockID: Int] = [:]
    for cz in -5...5 {
        for cx in -5...5 {
            let c = gen.generate(ChunkPos(Int32(cx), Int32(cz)))
            for i in 0..<WorldConst.blocksPerChunk { counts[c.blocks[i], default: 0] += 1 }
        }
    }
    let flora = [Blocks.blueBloom, Blocks.whiteDaisy, Blocks.pinkPetal, Blocks.redMushroom, Blocks.brownMushroom, Blocks.berryBush,
                 Blocks.cattail, Blocks.horsetail, Blocks.pebbles, Blocks.dryGrass, Blocks.cactus, Blocks.lilyPad]
    let floraCount = flora.reduce(0) { $0 + (counts[$1] ?? 0) }
    check(floraCount > 0, "surface decoration generates (\(floraCount) plants)")
    let caveDecor = (counts[Blocks.stalagmite] ?? 0) + (counts[Blocks.glowMushroom] ?? 0)
    check(caveDecor > 0, "cave decoration generates (\(caveDecor))")
    let stones = (counts[Blocks.marble] ?? 0) + (counts[Blocks.slate] ?? 0)
    check(stones > 0, "marble and slate veins generate (\(stones))")
}

section("Invite codes") {
    for (ip, port) in [("120.155.2.32", UInt16(25650)), ("1.2.3.4", UInt16(1)), ("255.255.255.255", UInt16(65535)), ("127.0.0.1", UInt16(25650))] {
        guard let code = InviteCode.encode(ip: ip, port: port) else {
            check(false, "invite code encodes \(ip)")
            continue
        }
        let decoded = InviteCode.decode(code)
        check(decoded?.ip == ip && decoded?.port == port, "invite code \(code) round-trips \(ip):\(port)")
        let sloppy = code.lowercased().replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "0", with: "o")
        check(InviteCode.decode(sloppy)?.ip == ip, "invite code tolerates case, spaces and O/0 mix-ups")
    }
    check(InviteCode.decode("192.168.1.20") == nil, "IP addresses aren't mistaken for invite codes")
    check(InviteCode.decode("my-mac.local") == nil, "host names aren't mistaken for invite codes")
    check(InviteCode.encode(ip: "300.1.1.1", port: 25650) == nil, "invalid addresses are rejected")
}

section("Biomes") {
    let gen = TerrainGenerator(seed: 2024)
    var seen: [Biome: Int] = [:]
    for z in stride(from: -12000, through: 12000, by: 96) {
        for x in stride(from: -12000, through: 12000, by: 96) { seen[gen.columnInfo(x: x, z: z).biome, default: 0] += 1 }
    }
    for b in [Biome.savanna, .redMesa, .blossomGrove, .silverForest, .fungalMarsh, .volcanicWastes, .glacier, .flowerMeadow] {
        check((seen[b] ?? 0) > 0, "\(b.displayName) generates (\(seen[b] ?? 0) samples)")
    }
    print("  " + Biome.allCases.compactMap { b in seen[b].map { "\(b.displayName) \($0)" } }.joined(separator: " · "))
}

section("Dimensions") {
    for dim in [WorldDimension.underworld, .skylands] {
        let a = dim.makeGenerator(seed: 4242), b = dim.makeGenerator(seed: 4242)
        let p = ChunkPos(3, -2)
        let (ca, t) = time { a.generate(p) }
        check(checksum(ca) == checksum(b.generate(p)), "\(dim.displayName) generation is deterministic")
        print(String(format: "  %@: %.2f ms/chunk", dim.displayName, t * 1000))
        var counts: [BlockID: Int] = [:]
        for cz in -2...2 { for cx in -2...2 {
            let c = a.generate(ChunkPos(Int32(cx), Int32(cz)))
            for i in 0..<WorldConst.blocksPerChunk { counts[c.blocks[i], default: 0] += 1 }
        } }
        let spawn = a.findSpawnColumn()
        check(a.estimatedSurface(x: spawn.x, z: spawn.z) > 0, "\(dim.displayName) has a standable spawn column")
        switch dim {
        case .underworld:
            check((counts[Blocks.basalt] ?? 0) > 100_000, "underworld is made of basalt")
            check((counts[Blocks.lava] ?? 0) > 1_000, "underworld has a lava sea")
            check((counts[Blocks.air] ?? 0) > 50_000, "underworld has open caverns")
            check(ca.block(5, 127, 5) == Blocks.bedrock && ca.block(5, 0, 5) == Blocks.bedrock, "underworld has a bedrock ceiling and floor")
        default:
            check((counts[Blocks.skyGrass] ?? 0) > 50, "skylands islands are grassy (\(counts[Blocks.skyGrass] ?? 0))")
            check((counts[Blocks.cloud] ?? 0) > 500, "skylands has a cloud sea")
        }
    }
    check(WorldDimension.overworld.destination(through: Blocks.underworldPortal) == .underworld, "bone gateways lead to the Underworld")
    check(WorldDimension.underworld.destination(through: Blocks.underworldPortal) == .overworld, "gateways lead home from other dimensions")
    let storage = WorldStorage(root: tempRoot.appendingPathComponent("dims"))
    let meta = try storage.createWorld(name: "Hard", seedText: "1", gameMode: .creative, difficulty: .easy, hardcore: true)
    check(meta.isHardcore && meta.gameMode == .survival && meta.difficulty == .hard, "hardcore worlds are survival on hard")
    check(storage.chunkURL(worldID: meta.id, pos: ChunkPos(0, 0), dimension: "dim_underworld").path.contains("dim_underworld/chunks"),
          "dimension chunks are stored separately")
}

section("PNG") {
    let w = 7, h = 5
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        pixels[i * 4] = UInt8(i * 7 % 256)
        pixels[i * 4 + 1] = UInt8(i * 13 % 256)
        pixels[i * 4 + 2] = UInt8(255 - i)
        pixels[i * 4 + 3] = i % 2 == 0 ? 255 : 128
    }
    let encoded = PNG.encode(width: w, height: h, rgba: pixels)
    let decoded = try PNG.decode(encoded)
    check(decoded.width == w && decoded.height == h && decoded.rgba == pixels, "PNG round-trips through the portable writer and reader")
    check((try? PNG.decode(Data(encoded.prefix(40)))) == nil, "truncated PNG is rejected")

    // Generated textures use real zlib compression and row filters.
    let files = ResourceLocator.files(in: "Textures/blocks", withExtension: "png")
    var decodedCount = 0
    for url in files {
        if let image = try? PNG.decode(Data(contentsOf: url)), image.width == 32, image.height == 32 { decodedCount += 1 }
    }
    check(!files.isEmpty && decodedCount == files.count, "all \(files.count) block textures decode (\(decodedCount) ok)")

    #if canImport(ImageIO)
    // Opaque pixels must match Apple's decoder exactly.
    if let url = files.first(where: { $0.lastPathComponent == "grass_top.png" }) ?? files.first,
       let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
       let mine = try? PNG.decode(Data(contentsOf: url)),
       let space = CGColorSpace(name: CGColorSpace.sRGB),
       let context = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4,
                               space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
       let reference = context.data?.assumingMemoryBound(to: UInt8.self) {
        context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        var opaque = 0, mismatched = 0
        for i in 0..<(mine.width * mine.height) where mine.rgba[i * 4 + 3] == 255 {
            opaque += 1
            for c in 0..<3 where abs(Int(mine.rgba[i * 4 + c]) - Int(reference[i * 4 + c])) > 1 { mismatched += 1; break }
        }
        check(opaque > 0 && mismatched == 0, "PNG decoder matches ImageIO on \(url.lastPathComponent) (\(mismatched) of \(opaque) pixels differ)")
    }
    #endif
}

print("")
print("DinoCraftCore self-test: \(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
