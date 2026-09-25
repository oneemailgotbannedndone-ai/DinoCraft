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

section("Pixel font") {
    let sample = "DinoCraft 0123456789 abcxyz ABCXYZ .,:;!?'\"-_+=/\\()<>#*%&@[]$^~|{}` \u{2665}\u{25CF}\u{2026}\u{2192}\u{00B7}\u{00D7}"
    var wellFormed = true, allKnown = true
    for ch in sample {
        let rows = PixelFont.rows(for: ch)
        if rows.count != PixelFont.height || rows.contains(where: { $0 >= 32 }) { wellFormed = false }
        if !PixelFont.hasGlyph(ch) { allKnown = false }
    }
    check(wellFormed, "every glyph is 7 rows of 5 pixels")
    check(allKnown, "the font covers letters, digits, punctuation and HUD symbols")
    check(PixelFont.rows(for: "\u{00E9}") == PixelFont.rows(for: "e"), "accented letters use their plain letter")
    check(PixelFont.rows(for: "\u{4E2D}") == PixelFont.rows(for: "?"), "unknown characters draw as ?")
}

section("Updates") {
    let reply = """
    {"tag_name": "build-42", "name": "DinoCraft build 42", "body": "New packs", "published_at": "2026-09-24T10:00:00Z",
     "assets": [{"name": "DinoCraft-Windows.zip", "browser_download_url": "https://example.com/w.zip"},
                {"name": "DinoCraft-Mac.zip", "browser_download_url": "https://example.com/m.zip"}]}
    """
    let release = GameUpdater.parse(Data(reply.utf8))
    check(release?.build == 42, "release tag build-42 reads as build 42")
    check(release?.assets["DinoCraft-Windows.zip"]?.absoluteString == "https://example.com/w.zip", "release downloads are found by name")
    check(release?.published == "2026-09-24", "release date is kept")
    check(GameUpdater.parse(Data("{}".utf8)) == nil, "a broken reply is ignored")
    let withDownloads = GameUpdater.parse(Data(###"{"tag_name": "build-9", "body": "## Download\n\n- zip\n\n## What's new\n\nSkins!", "assets": []}"###.utf8))
    check(withDownloads?.notes == "Skins!", "the launcher shows only the what's-new part of the notes")
    check(BuildInfo(build: 0, commit: nil, date: nil).isDevelopment, "builds made by hand count as development builds")
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

    // Swimming: a deep pool (water from y 1 to 29, surface at 30) with a wall at x = 6
    let pool = flatWorld(blocks, groundHeight: 1)
    for z in -30..<30 { for x in -30..<30 { for y in 1..<30 { pool.set(x, y, z, x >= 6 ? Blocks.stone : Blocks.water) } } }
    let swimmer = PlayerController(position: DVec3(0.5, 28, 0.5))
    let idle = MovementInput()
    for _ in 0..<300 { swimmer.update(dt: 1.0 / 60, input: idle, world: pool) }
    check(swimmer.position.y > 27 && swimmer.position.y < 30, "you float at the surface (y \(String(format: "%.1f", swimmer.position.y)))")
    var dive = MovementInput(); dive.forward = 1
    swimmer.pitch = -0.8   // look down
    swimmer.yaw = Double.pi / 2   // face -X, away from the wall
    let startY = swimmer.position.y
    for _ in 0..<120 { swimmer.update(dt: 1.0 / 60, input: dive, world: pool) }
    check(swimmer.position.y < startY - 3, "swimming forward while looking down dives (to y \(String(format: "%.1f", swimmer.position.y)))")
    swimmer.pitch = 0.9   // look up
    for _ in 0..<240 { swimmer.update(dt: 1.0 / 60, input: dive, world: pool) }
    check(swimmer.position.y > 26, "looking up swims back to the top (y \(String(format: "%.1f", swimmer.position.y)))")
    let climber = PlayerController(position: DVec3(5.5, 28.6, 0.5))
    climber.yaw = -Double.pi / 2   // face the wall (+X)
    var climb = MovementInput(); climb.forward = 1; climb.jump = true
    for _ in 0..<180 { climber.update(dt: 1.0 / 60, input: climb, world: pool) }
    check(climber.position.y >= 30 && climber.position.x > 6, "jumping at the edge climbs out of the water (\(String(format: "%.1f, %.1f", climber.position.x, climber.position.y)))")

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
    check(PlayerIdentity.isValid(store.settings.playerID), "settings get a player ID")
    check(SettingsStore(url: settingsURL).settings.playerID == store.settings.playerID, "the player ID is kept between launches")
}
section("Persistence", persistenceTests)

section("Leaderboard") {
    var s = PlayerStats.Values()
    s.playSeconds = 3725; s.deaths = 3; s.kills = 41; s.bossesBeaten = 1; s.blocksMined = 900; s.blocksPlaced = 450; s.itemsCrafted = 70
    s.foodEaten = 9; s.metresWalked = 12_345
    let text = Leaderboard.encode(s)
    var back = Leaderboard.decode(text, playSeconds: 3725)
    back.metresWalked = s.metresWalked.rounded(.down)
    var expected = s
    expected.metresWalked = s.metresWalked.rounded(.down)
    check(back == expected, "stats survive the trip through the board (\(text))")
    let one = #"{"dreamlo":{"leaderboard":{"entry":{"name":"Rex_K7Q2","score":"600","seconds":"4","text":"d1k4","date":"x"}}}}"#
    let many = #"{"dreamlo":{"leaderboard":{"entry":[{"name":"Rex_K7Q2","score":"600","seconds":"4","text":"d1k4"},{"name":"Mo_9WDA","score":"60","seconds":"9","text":"k9m50"}]}}}"#
    let none = #"{"dreamlo":{"leaderboard":null}}"#
    let parsedOne = Leaderboard.parse(Data(one.utf8))
    check(parsedOne.count == 1 && parsedOne[0].name == "Rex" && parsedOne[0].tag == "K7Q2" && parsedOne[0].stats.kills == 4, "reads a board with one entry")
    let parsedMany = Leaderboard.parse(Data(many.utf8))
    check(parsedMany.count == 2 && Leaderboard.parse(Data(none.utf8)).isEmpty, "reads boards with several entries, or none")
    check(Leaderboard.ranked(parsedMany, by: .kills).first?.name == "Mo" && Leaderboard.ranked(parsedMany, by: .playtime).first?.name == "Rex",
          "the board sorts by any stat")
    check(Leaderboard.entryName(name: "Rex!", playerID: "0000000000000001").hasPrefix("Rex_"), "entry names are safe for the board")
    let statsURL = FileManager.default.temporaryDirectory.appendingPathComponent("dinocraft-stats-\(UUID().uuidString).json")
    let stats = PlayerStats(url: statsURL)
    stats.record("break", amount: 3); stats.record("kill", "grumblesaurus"); stats.record("die"); stats.record("jump")
    stats.tick(dt: 2, walked: 1.5)
    stats.save()
    let reloaded = PlayerStats(url: statsURL).values
    check(reloaded.blocksMined == 3 && reloaded.kills == 1 && reloaded.bossesBeaten == 1 && reloaded.deaths == 1 && reloaded.playSeconds == 2,
          "lifetime stats count and save")
    try? FileManager.default.removeItem(at: statsURL)
}

section("Ocean life") {
    let reg = try! BlockRegistry.loadDefault()
    check(reg.isSubmerged[Int(Blocks.kelp)] && reg.isWet[Int(Blocks.seagrass)] && reg.isWet[Int(Blocks.water)] && !reg.isWet[Int(Blocks.sand)],
          "sea plants count as water for swimming")
    check(reg.variantLayers.count == 256 && reg[Blocks.coralBlock]?.variants.count == 5 && reg.textureNames.contains("coral_fan_purple"),
          "coral comes in five colours")
    check(reg.emission[Int(Blocks.seaLantern)] == 15, "sea lanterns glow")
    // Somewhere in a big patch of ocean there are kelp, seagrass and a coral reef.
    let gen = TerrainGenerator(seed: 1337)
    var counts: [BlockID: Int] = [:]
    var reefColumn: (Int, Int)?
    search: for ring in 0..<60 {
        for step in 0..<max(1, ring * 8) {
            let a = Double(step) / Double(max(1, ring * 8)) * 2 * .pi
            let x = Int(cos(a) * Double(ring * 16)), z = Int(sin(a) * Double(ring * 16))
            if gen.isReef(x: x, z: z) { reefColumn = (x, z); break search }
        }
    }
    check(reefColumn != nil, "warm seas have coral reefs")
    if let (x, z) = reefColumn {
        for dz in -2...2 { for dx in -2...2 {
            let chunk = gen.generate(ChunkPos(Int32((x >> 4) + dx), Int32((z >> 4) + dz)))
            for y in 0..<WorldConst.height { for cz in 0..<16 { for cx in 0..<16 {
                let id = chunk.block(cx, y, cz)
                if id >= Blocks.kelp { counts[id, default: 0] += 1 }
            } } }
        } }
    }
    check((counts[Blocks.coralBlock] ?? 0) > 20 && (counts[Blocks.coral] ?? 0) > 10, "reefs are built of coral (\(counts[Blocks.coralBlock] ?? 0) blocks, \(counts[Blocks.coral] ?? 0) plants)")
    check((counts[Blocks.seagrass] ?? 0) > 10, "seagrass grows on the sea floor (\(counts[Blocks.seagrass] ?? 0))")
}

section("Crash reports") {
    let log = URL(fileURLWithPath: "/tmp/logs/dinocraft-20260925-030000.log")
    check(CrashReport.companion(of: log).lastPathComponent == "dinocraft-20260925-030000.err.txt", "the error file sits beside its log")
    let lines = (1...400).map { "2026-09-25 03:00:00.000 [INFO ] [Game] (main) line \($0) with some words in it" }
    let report = CrashReport(log: log, text: (lines + ["*** DinoCraft crashed at DinoCraft.exe+0x1a2b3c"]).joined(separator: "\n"))
    let short = report.issueURL(repository: "someone/DinoCraft", build: "build 39", platform: "Windows", maxLength: 2000)
    check(short.map { $0.absoluteString.count <= 2000 } ?? false, "the Windows report link is short enough for the browser")
    check(short.map { $0.absoluteString.contains("1a2b3c") } ?? false, "the shortened report keeps the crash itself")
}

section("Double chests") {
    var world: [SIMD3<Int>: BlockID] = [:]
    let north = Blocks.chest[0], east = Blocks.chest[1]
    func look(_ x: Int, _ y: Int, _ z: Int) -> BlockID { world[SIMD3(x, y, z)] ?? Blocks.air }
    func partner(_ x: Int, _ z: Int) -> (dx: Int, dz: Int)? {
        let id = look(x, 0, z)
        let facing: Int8 = id == north ? Int8(BlockFace.north.rawValue) : Int8(BlockFace.east.rawValue)
        return DoubleChests.partner(x: x, y: 0, z: z, id: id, facing: facing, block: look)
    }
    world[SIMD3(0, 0, 0)] = north
    check(partner(0, 0) == nil, "a lone chest stays single")
    world[SIMD3(1, 0, 0)] = north
    check(partner(0, 0)! == (1, 0) && partner(1, 0)! == (-1, 0), "two chests side by side pair up")
    world[SIMD3(2, 0, 0)] = north
    check(partner(2, 0) == nil && partner(0, 0)! == (1, 0), "a third chest beside a pair stays single")
    world[SIMD3(3, 0, 0)] = north
    check(partner(2, 0)! == (1, 0) && partner(3, 0)! == (-1, 0), "a row of four makes two pairs")
    world[SIMD3(0, 0, 1)] = north
    check(partner(0, 1) == nil, "chests don't pair front to back")
    world[SIMD3(5, 0, 0)] = east; world[SIMD3(6, 0, 0)] = east
    check(partner(5, 0) == nil, "east-facing chests pair along z, not x")
    world[SIMD3(5, 0, 1)] = east
    check(partner(5, 0)! == (0, 1), "east-facing chests side by side pair up")
}

section("Friends") {
    let a = PlayerIdentity.newID(), b = PlayerIdentity.newID()
    check(a != b && PlayerIdentity.isValid(a), "player IDs are random and valid")
    check(PlayerIdentity.tag(for: a).count == 4 && PlayerIdentity.tag(for: a) == PlayerIdentity.tag(for: a), "tags are four stable characters")
    var tags = Set<String>()
    for _ in 0..<2000 { tags.insert(PlayerIdentity.tag(for: PlayerIdentity.newID())) }
    check(tags.count > 1990, "tags rarely repeat (\(tags.count) of 2000)")
    let code = FriendCode.encode(name: "Rex!", id: a, address: "DINO-3M4KA-9QX2B")
    check(FriendCode.decode("hey add me " + code + "\nthanks") == FriendCode.Contents(name: "Rex", id: a, address: "DINO-3M4KA-9QX2B"),
          "friend codes round-trip (\(code))")
    check(FriendCode.decode(FriendCode.encode(name: "Mo", id: b, address: nil))?.address == nil, "friend codes work without an address")
    check(FriendCode.decode("FRIEND:Rex:nothex") == nil && FriendCode.decode("DINO-3M4KA-9QX2B") == nil, "bad friend codes are refused")
    check(Wire.parseAddress("10.0.0.5:1234") == ("10.0.0.5", 1234) && Wire.parseAddress("10.0.0.5").port == Wire.defaultPort, "addresses parse")

    let url = FileManager.default.temporaryDirectory.appendingPathComponent("dinocraft-friends-\(UUID().uuidString).json")
    let list = FriendList(url: url)
    let me = PlayerIdentity.newID()
    check(list.add(code: FriendCode.encode(name: "Me", id: me, address: nil), myID: me).contains("own"), "you can't add yourself")
    list.add(code: code, myID: me)
    check(list.isFriend(a) && list.friends.first?.address == "DINO-3M4KA-9QX2B", "adding a friend code")
    check(!list.met(id: b, name: "Mo", look: "hat=cap", address: nil, myID: me) && list.recent.first?.id == b, "players you meet go in recent")
    check(list.met(id: a, name: "Rex", look: "hat=crown", address: "1.2.3.4:25650", myID: me), "meeting a friend is noticed")
    list.befriend(b)
    list.remove(a)
    let reloaded = FriendList(url: url)
    check(reloaded.isFriend(b) && !reloaded.isFriend(a) && reloaded.recent.first?.id == a && reloaded.recent.first?.look == "hat=crown",
          "the friends list saves and loads")
    try? FileManager.default.removeItem(at: url)

    // A live host answers the status question without anyone joining.
    let hostID = PlayerIdentity.newID()
    let host = try WireHost(settings: WireHost.Settings(worldName: "Friendly Plains", seed: "1", gameMode: "survival", difficulty: "normal",
                                                        hostName: "Rex", hostID: hostID),
                            port: 0, loopbackOnly: true) { TerrainGenerator(seed: 1).generate($0) }
    var met: String?
    host.onMet = { id, _, _ in met = id }
    final class Reply: @unchecked Sendable {
        let lock = NSLock()
        var status: Wire.Status?
        var finished = false
    }
    let reply = Reply(), port = host.port
    DispatchQueue(label: "probe").async {
        let answer = StatusProbe.check(address: "127.0.0.1:\(port)")
        reply.lock.lock(); reply.status = answer; reply.finished = true; reply.lock.unlock()
    }
    let deadline = Date().addingTimeInterval(5)
    while Date() < deadline {
        host.poll()
        reply.lock.lock(); let done = reply.finished; reply.lock.unlock()
        if done { break }
        Thread.sleep(forTimeInterval: 0.02)
    }
    let status = reply.status
    check(status == Wire.Status(hostID: hostID, hostName: "Rex", world: "Friendly Plains", players: 1), "status check sees the hosted world (\(String(describing: status)))")
    let joiner = try WireConnection.connect(host: "127.0.0.1", port: host.port)
    joiner.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "Mo", playerID: b, look: "hat=cap"))
    var welcome: Wire.Welcome?
    let joinDeadline = Date().addingTimeInterval(5)
    while Date() < joinDeadline && welcome == nil {
        host.poll()
        for event in joiner.poll() {
            if case .message(.welcome, let data) = event { welcome = try? JSONDecoder().decode(Wire.Welcome.self, from: data) }
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    check(met == b, "the host learns who joined")
    check(welcome?.players.first?.playerID == hostID, "joiners learn who the host is")
    check(StatusProbe.check(address: "127.0.0.1:1", timeout: 1) == nil, "nobody hosting reads as offline")

    // Private messages: Mo whispers to Zed, and to the host.
    let second = try WireConnection.connect(host: "127.0.0.1", port: host.port)
    second.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "Zed"))
    var hostHeard: (String, String)?
    host.onWhisper = { from, text in hostHeard = (from, text) }
    var zedChats: [Wire.Chat] = [], moChats: [Wire.Chat] = []
    func pump(_ seconds: Double, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end && !done() {
            host.poll()
            for event in second.poll() { if case .message(.chat, let d) = event, let c = try? JSONDecoder().decode(Wire.Chat.self, from: d) { zedChats.append(c) } }
            for event in joiner.poll() { if case .message(.chat, let d) = event, let c = try? JSONDecoder().decode(Wire.Chat.self, from: d) { moChats.append(c) } }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }
    pump(2) { host.playerCount == 2 }
    joiner.send(.chat, Wire.Chat(from: "Mo", text: "psst", to: "zed"))
    joiner.send(.chat, Wire.Chat(from: "Mo", text: "hi host", to: "Rex"))
    joiner.send(.chat, Wire.Chat(from: "Mo", text: "hello?", to: "Nobody"))
    pump(3) { zedChats.contains { $0.text == "psst" } && hostHeard != nil && moChats.count >= 3 }
    check(zedChats.contains { $0.text == "psst" && $0.from == "Mo" && $0.to == "Zed" }, "/msg reaches only its player")
    check(hostHeard?.0 == "Mo" && hostHeard?.1 == "hi host", "/msg to the host reaches the host")
    check(moChats.contains { $0.text.contains("You whisper to Zed") } && moChats.contains { $0.text.contains("No player called Nobody") },
          "the sender sees their whisper, or that nobody has that name")
    check(host.whisper(from: "Rex", to: "MO", text: "hey") && !host.whisper(from: "Rex", to: "ghost", text: "boo"), "the host can whisper to a player")
    check(!zedChats.contains { $0.text == "hi host" || $0.text == "hello?" }, "other players don't see private messages")
    second.close()
    joiner.close()
    host.stop()

    // Hardcore multiplayer: a joiner who dies is remembered and can only spectate when they rejoin.
    let hc = try WireHost(settings: WireHost.Settings(worldName: "One Life", seed: "1", gameMode: "survival", difficulty: "hard",
                                                      hostName: "Rex", hostID: hostID, hardcore: true),
                          port: 0, loopbackOnly: true) { TerrainGenerator(seed: 1).generate($0) }
    var died: (String, String)?
    hc.onHardcoreDeath = { key, name in died = (key, name) }
    func joinHardcore() throws -> (WireConnection, Wire.Welcome?) {
        let c = try WireConnection.connect(host: "127.0.0.1", port: hc.port)
        c.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "Mo", playerID: b))
        var w: Wire.Welcome?
        let end = Date().addingTimeInterval(5)
        while Date() < end && w == nil {
            hc.poll()
            for event in c.poll() { if case .message(.welcome, let d) = event { w = try? JSONDecoder().decode(Wire.Welcome.self, from: d) } }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return (c, w)
    }
    let (first, firstWelcome) = try joinHardcore()
    check(firstWelcome?.hardcore == true && firstWelcome?.spectator == false, "hardcore hosts say so, and new players can play")
    first.send(.playerState, Wire.PlayerState(id: 0, x: 0, y: 80, z: 0, yaw: 0, pitch: 0, moving: 0, sneaking: false, swinging: false,
                                              held: nil, health: 0, dead: true))
    let deathEnd = Date().addingTimeInterval(3)
    while Date() < deathEnd && died == nil { hc.poll(); Thread.sleep(forTimeInterval: 0.02) }
    check(died?.0 == b && died?.1 == "Mo", "the hardcore host notices a joiner's death")
    first.close()
    Thread.sleep(forTimeInterval: 0.2)
    hc.poll()
    let (again, againWelcome) = try joinHardcore()
    check(againWelcome?.spectator == true, "a player who died in hardcore comes back as a spectator")
    again.close()
    hc.stop()
}

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
    for dim in [WorldDimension.underworld, .skylands, .toonland] {
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
        case .toonland:
            check((counts[Blocks.toonGrass] ?? 0) > 1_000, "toonland hills are covered in toon grass")
            check((counts[Blocks.checkerBlock] ?? 0) > 400, "toonland has a checkered stage and roads (\(counts[Blocks.checkerBlock] ?? 0))")
            check(a.generate(ChunkPos(0, 0)).block(3, ToonlandGenerator.stageFloor, 3) == Blocks.checkerBlock, "a stage sits at the origin")
        default:
            check((counts[Blocks.skyGrass] ?? 0) > 50, "skylands islands are grassy (\(counts[Blocks.skyGrass] ?? 0))")
            check((counts[Blocks.cloud] ?? 0) > 500, "skylands has a cloud sea")
        }
    }
    check(WorldDimension.overworld.destination(through: Blocks.underworldPortal) == .underworld, "bone gateways lead to the Underworld")
    check(WorldDimension.underworld.destination(through: Blocks.underworldPortal) == .overworld, "gateways lead home from other dimensions")
    check(WorldDimension.overworld.destination(through: Blocks.toonlandPortal) == .toonland, "checker gateways lead to Toonland")
    check(WorldDimension.gateways.count == 3, "three kinds of gateway")

    // The deep layers: new overworlds go down to Y -70, older worlds keep their floor.
    let deep = TerrainGenerator(seed: 777), flat = TerrainGenerator(seed: 777, deep: false)
    let dc = deep.generate(ChunkPos(2, 5)), fc = flat.generate(ChunkPos(2, 5))
    var slate = 0
    for y in 5..<60 { for z in 0..<16 { for x in 0..<16 where dc.block(x, y, z) == Blocks.deepSlate { slate += 1 } } }
    check(dc.block(4, 0, 4) == Blocks.bedrock && fc.block(4, 0, 4) == Blocks.bedrock, "both kinds of world have bedrock at the bottom")
    check(slate > 5_000, "the deep layers are Deep Slate (\(slate))")
    check(deep.seaLevel == flat.seaLevel + WorldConst.deepLayers && deep.depthOffset == 70 && flat.depthOffset == 0, "deep worlds sit 70 blocks higher")
    check(dc.maxHeight > WorldConst.deepLayers + 30, "the land sits on top of the deep layers")
    var deepest = Int.max
    for z in stride(from: -4000, through: 4000, by: 160) { for x in stride(from: -4000, through: 4000, by: 160) {
        deepest = min(deepest, deep.columnInfo(x: x, z: z).height)
    } }
    check(deepest >= deep.seaLevel - 24, "oceans in new worlds stay fairly shallow (deepest floor \(deepest - deep.seaLevel))")
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

section("Multiplayer wire protocol") {
    let frame = Wire.frame(.chat, Data("{}".utf8))
    check(frame.count == 7 && frame[0] == 3 && frame[4] == 10, "frames match the Mac host's layout (length, kind, payload)")

    // A loopback host: accepts one player, answers hello with welcome, a chunk and a creature.
    let server = try NetSocket.listen(port: 0, loopbackOnly: true)
    let port = server.localPort
    check(port > 0, "test host listens on a free port")
    let generator = TerrainGenerator(seed: 9)
    let hostDone = DispatchSemaphore(value: 0)
    Thread {
        defer { hostDone.signal() }
        guard let socket = server.accept() else { return }
        let peer = WireConnection(socket: socket, label: "test host")
        let deadline = Date().addingTimeInterval(5)
        var hello: Wire.Hello?
        while hello == nil && Date() < deadline {
            for case .message(.hello, let data) in peer.poll() { hello = try? JSONDecoder().decode(Wire.Hello.self, from: data) }
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard let hello, hello.username == "Tester", hello.version == Wire.protocolVersion else { return }
        peer.send(.welcome, Wire.Welcome(playerID: 7, worldName: "Loopback", seed: "9", dimension: "overworld", gameMode: "survival",
                                         difficulty: "normal", hardcore: false, x: 1, y: 70, z: 2, worldTime: 300,
                                         players: [Wire.PlayerInfo(id: 0, name: "Host")]))
        if let payload = try? Wire.chunkPayload(generator.generate(ChunkPos(2, -3))) { peer.sendRaw(.chunkData, payload) }
        peer.send(.mobSnapshot, Wire.MobSnapshot(mobs: [Wire.MobState(id: 5, kind: "raptor", x: 3, y: 70, z: 4, yaw: 1, health: 16, maxHealth: 16)]))
        Thread.sleep(forTimeInterval: 0.3)
        peer.close()
    }.start()

    let client = try WireConnection.connect(host: "127.0.0.1", port: port)
    client.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "Tester"))
    var welcome: Wire.Welcome?
    var received: Chunk?
    var mobs = 0
    var closed = false
    let deadline = Date().addingTimeInterval(8)
    while !closed && Date() < deadline {
        for event in client.poll() {
            switch event {
            case .message(.welcome, let data): welcome = try? JSONDecoder().decode(Wire.Welcome.self, from: data)
            case .message(.mobSnapshot, let data): mobs += (try? JSONDecoder().decode(Wire.MobSnapshot.self, from: data))?.mobs.count ?? 0
            case .chunk(let chunk): received = chunk
            case .closed: closed = true
            default: break
            }
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
    _ = hostDone.wait(timeout: .now() + 5)
    check(welcome?.playerID == 7 && welcome?.worldName == "Loopback", "player joins over TCP and receives the welcome")
    check(received?.pos == ChunkPos(2, -3) && received.map(checksum) == checksum(generator.generate(ChunkPos(2, -3))), "chunks arrive intact over the network")
    check(mobs == 1, "creature snapshots arrive")
    check(closed, "disconnect is reported")
    server.close()
}

section("Router port mapping parsing") {
    check(PortMapping.gatewayCandidates(local: "192.168.1.23") == ["192.168.1.1", "192.168.1.254"], "gateway guesses from the LAN address")
    check(PortMapping.isPrivate("100.72.1.9") && !PortMapping.isPrivate("81.2.69.160"), "carrier-grade NAT addresses are private")
    check(NetSocket.parseIPv4("10.0.0.138") == 0x0A00_008A && NetSocket.parseIPv4("300.1.1.1") == nil, "IPv4 parsing")
    let plain = Array("HTTP/1.1 200 OK\r\nContent-Type: text/xml\r\n\r\n<ok/>".utf8)
    check(PortMapping.parseResponse(plain).map { $0.0 == "<ok/>" && $0.1 == 200 } == true, "plain HTTP response")
    let chunked = Array("HTTP/1.1 500 Internal Server Error\r\nTransfer-Encoding: chunked\r\n\r\n5\r\n<err>\r\n6\r\n</err>\r\n0\r\n\r\n".utf8)
    check(PortMapping.parseResponse(chunked).map { $0.0 == "<err></err>" && $0.1 == 500 } == true, "chunked HTTP response")
    let xml = "<device><serviceType>urn:schemas-upnp-org:service:WANIPConnection:1</serviceType><controlURL>/ctl/IPConn</controlURL></device>"
    let control = PortMapping.controlURL(in: xml, location: URL(string: "http://192.168.1.1:5000/rootDesc.xml")!)
    check(control?.url.absoluteString == "http://192.168.1.1:5000/ctl/IPConn", "UPnP control URL resolves against the description location")
}

section("Multiplayer portable host") {
    let generator = TerrainGenerator(seed: 11)
    let host = try WireHost(settings: .init(worldName: "Windows World", seed: "11", gameMode: "creative", difficulty: "normal", hostName: "WinHost"),
                            port: 0, loopbackOnly: true, makeChunk: { generator.generate($0) })
    host.spawnPoint = { DVec3(8.5, 80, 8.5) }
    var edits: [BlockPos] = []
    host.onBlockChange = { pos, _ in edits.append(pos); return true }
    var chats: [String] = []
    host.onChat = { from, text in chats.append("\(from): \(text)") }

    let client = try WireConnection.connect(host: "127.0.0.1", port: host.port)
    client.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "MacFriend"))
    var welcome: Wire.Welcome?
    var chunks = 0, hostStates = 0
    var echoed = false, sent = false
    let target = BlockPos(9, 70, 9)
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline && !(welcome != nil && chunks >= 4 && hostStates > 0 && echoed && !chats.isEmpty) {
        host.poll()
        host.tick(dt: 0.02, hostState: Wire.PlayerState(id: 0, x: 8.5, y: 80, z: 8.5, yaw: 0, pitch: 0, moving: 0, sneaking: false,
                                                        swinging: false, held: nil, health: 20, dead: false))
        for event in client.poll() {
            switch event {
            case .message(.welcome, let data): welcome = try? JSONDecoder().decode(Wire.Welcome.self, from: data)
            case .message(.playerState, let data):
                if (try? JSONDecoder().decode(Wire.PlayerState.self, from: data))?.id == 0 { hostStates += 1 }
            case .message(.blockChange, let data):
                if let m = try? JSONDecoder().decode(Wire.BlockChange.self, from: data), BlockPos(m.x, m.y, m.z) == target { echoed = true }
            case .chunk: chunks += 1
            default: break
            }
        }
        if welcome != nil && !sent {
            client.send(.chunkRequest, Wire.ChunkRequest([ChunkPos(0, 0), ChunkPos(1, 0), ChunkPos(0, 1), ChunkPos(1, 1)]))
            client.send(.blockChange, Wire.BlockChange(pos: target, id: Blocks.stone))
            client.send(.chat, Wire.Chat(from: "MacFriend", text: "hello host"))
            sent = true
        }
        Thread.sleep(forTimeInterval: 0.02)
    }
    check(welcome?.worldName == "Windows World" && welcome?.players.first?.name == "WinHost", "a player joins the portable host")
    check(chunks >= 4, "the portable host serves chunks (\(chunks))")
    check(hostStates > 0, "the portable host shares the host player's movement")
    check(edits == [target] && echoed, "the portable host applies and broadcasts block edits")
    check(chats == ["MacFriend: hello host"], "the portable host relays chat")
    check(host.players.first?.name == "MacFriend", "the portable host lists joined players")
    client.close()
    host.stop()
}

// Optional: DINOCRAFT_SERVE_SECONDS=40 hosts a world on port 25650 with the portable host so a real
// DinoCraft client can join (used to verify that Mac players can join a Windows host).
if let serveText = ProcessInfo.processInfo.environment["DINOCRAFT_SERVE_SECONDS"], let seconds = Double(serveText) {
    section("Serving a real client for \(Int(seconds))s") {
        let generator = TerrainGenerator(seed: 4242)
        let column = generator.findSpawnColumn()
        let spawnChunk = generator.generate(ChunkPos(Int32(column.x >> 4), Int32(column.z >> 4)))
        var standY = 100
        for y in stride(from: WorldConst.height - 2, through: 1, by: -1) where blocks.isSolid[Int(spawnChunk.block(column.x & 15, y, column.z & 15))] {
            standY = y + 1
            break
        }
        let spawn = DVec3(Double(column.x) + 0.5, Double(standY), Double(column.z) + 0.5)
        let host = try WireHost(settings: .init(worldName: "Portable Host", seed: "4242", gameMode: "creative", difficulty: "normal", hostName: "Host"),
                                makeChunk: { generator.generate($0) })
        host.spawnPoint = { spawn }
        var chats: [String] = []
        host.onChat = { from, text in chats.append("\(from): \(text)") }
        var events: [String] = []
        host.onEvent = { events.append($0) }
        var sawState = false, announced = false
        let start = Date()
        while Date().timeIntervalSince(start) < seconds {
            host.poll()
            host.tick(dt: 0.02, hostState: Wire.PlayerState(id: 0, x: spawn.x + 1.5, y: spawn.y, z: spawn.z, yaw: 0, pitch: 0, moving: 0,
                                                            sneaking: false, swinging: false, held: "planks", health: 20, dead: false))
            if host.players.first?.state != nil { sawState = true }
            if !announced, sawState, Date().timeIntervalSince(start) > 12 {
                host.broadcastBlock(BlockPos(Int(floor(spawn.x)) + 2, standY + 1, Int(floor(spawn.z))), Blocks.amberLantern)
                host.broadcastChat(from: "Host", text: "hello from the portable host")
                announced = true
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        print("  events: \(events) · chats: \(chats) · movement received: \(sawState) · spawn \(spawn)")
        check(events.contains { $0.hasSuffix("joined the game") }, "a real client joined the portable host")
        check(sawState, "the client's movement reached the portable host")
        check(chats.contains { $0.hasSuffix("hello from mac") }, "the client's chat reached the portable host")
        host.stop()
    }
}

// Optional: DINOCRAFT_LIVE_HOST=127.0.0.1 joins a real hosted DinoCraft game (used to verify cross-play).
if let liveHost = ProcessInfo.processInfo.environment["DINOCRAFT_LIVE_HOST"], !liveHost.isEmpty {
    section("Live host \(liveHost)") {
        let connection = try WireConnection.connect(host: liveHost, port: Wire.defaultPort)
        connection.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: "WinTest"))
        var welcome: Wire.Welcome?
        var chunks = 0, hostStates = 0, mobSnapshots = 0, times = 0, blockEchoes = 0
        var closedReason: String?
        var requested = false, placed = false
        var target = BlockPos(0, 0, 0)
        let start = Date()
        var lastState = Date.distantPast
        while Date().timeIntervalSince(start) < 25 && closedReason == nil {
            for event in connection.poll() {
                switch event {
                case .message(.welcome, let data): welcome = try? JSONDecoder().decode(Wire.Welcome.self, from: data)
                case .message(.playerState, let data):
                    if (try? JSONDecoder().decode(Wire.PlayerState.self, from: data))?.id == 0 { hostStates += 1 }
                case .message(.mobSnapshot, _): mobSnapshots += 1
                case .message(.worldTime, _): times += 1
                case .message(.blockChange, let data):
                    if let m = try? JSONDecoder().decode(Wire.BlockChange.self, from: data), BlockPos(m.x, m.y, m.z) == target { blockEchoes += 1 }
                case .chunk: chunks += 1
                case .closed(let reason): closedReason = reason
                default: break
                }
            }
            if let w = welcome {
                let cx = Int32(floor(w.x / 16)), cz = Int32(floor(w.z / 16))
                if !requested {
                    var list: [ChunkPos] = []
                    for dz: Int32 in -2...2 { for dx: Int32 in -2...2 { list.append(ChunkPos(cx + dx, cz + dz)) } }
                    connection.send(.chunkRequest, Wire.ChunkRequest(list))
                    requested = true
                }
                if chunks >= 25 && !placed {
                    target = BlockPos(Int(floor(w.x)) + 2, Int(floor(w.y)) + 3, Int(floor(w.z)))
                    connection.send(.blockChange, Wire.BlockChange(pos: target, id: Blocks.amberLantern, harvest: false))
                    placed = true
                }
                if Date().timeIntervalSince(lastState) > 0.1 {
                    lastState = Date()
                    let t = Date().timeIntervalSince(start)
                    connection.send(.playerState, Wire.PlayerState(id: w.playerID, x: w.x + cos(t) * 2, y: w.y, z: w.z + sin(t) * 2,
                                                                   yaw: Float(t), pitch: 0, moving: 1, sneaking: false, swinging: false,
                                                                   held: "planks", health: 20, dead: false))
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        print("  welcome \(welcome.map { "'\($0.worldName)' as player \($0.playerID)" } ?? "none") · \(chunks) chunks · \(hostStates) host states · \(mobSnapshots) creature updates · \(times) time updates · \(blockEchoes) block echoes · closed: \(closedReason ?? "no")")
        check(welcome != nil, "joined the live host")
        check(chunks >= 25, "live host served the requested chunks (\(chunks))")
        check(hostStates > 0, "live host's player movement arrives")
        check(mobSnapshots > 0 && times > 0, "live host's creatures and time arrive")
        check(blockEchoes > 0, "a placed block was accepted and broadcast by the host")
        connection.close()
    }
}

print("")
print("DinoCraftCore self-test: \(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
