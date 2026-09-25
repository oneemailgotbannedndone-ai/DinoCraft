import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// One loaded singleplayer world: terrain streaming for the current dimension,
/// the player, interaction (breaking / placing / combat), creatures, dropped
/// items, survival and hardcore rules, dimension travel, and persistence.
final class GameSession {
    let blocks: BlockRegistry
    let items: ItemRegistry
    let storage: WorldStorage
    private(set) var meta: WorldMetadata
    private(set) var world: World
    private(set) var dimension: WorldDimension
    let player: PlayerController
    let inventory: Inventory
    let isNewWorld: Bool
    private let meshFactory: ChunkMeshFactory
    private let jobs: JobSystem
    private var renderDistance: Int

    // Survival
    private(set) var health: Double = 20
    private(set) var hunger: Double = 20
    private(set) var saturation: Double = 5
    private(set) var air: Double = 10
    private var exhaustion = 0.0, regenTimer = 0.0, starveTimer = 0.0, drownTimer = 0.0, lavaTimer = 0.0, cactusTimer = 0.0
    private var hurtCooldown = 0.0
    private(set) var isDead = false
    private(set) var deathMessage = ""
    private(set) var spectator: Bool

    // World & loading
    private(set) var worldTime: Double
    private(set) var isLoading = true
    private(set) var loadingProgress: Float = 0
    private(set) var loadingDetail = "Preparing terrain"
    private(set) var loadingTitle = "Loading World…"
    private var loadingElapsed = 0.0
    private var needsSpawnResolve: Bool
    private var spawnHint: Int
    private var spawnPoint: DVec3
    private var pendingReturnPortal: BlockID?
    private(set) var portalProgress: Double = 0
    private(set) var portalKind: BlockID?
    private var portalCooldown = 0.0

    // Interaction
    private(set) var target: RaycastHit?
    private(set) var targetMob: Mob?
    private(set) var breakingPos: BlockPos?
    private(set) var breakProgress: Double = 0
    private var hitSoundTimer = 0.0, attackCooldown = 0.0, useCooldown = 0.0, combatCooldown = 0.0
    private(set) var lastMiningTime = -100.0
    private(set) var lastBuildingTime = -100.0
    private(set) var lastCombatTime = -100.0
    private(set) var lastCombatMob = ""
    private(set) var lastCraftTime = -100.0
    private(set) var clock = 0.0
    private var autosaveTimer = 0.0
    private var environmentTimer = 0.0
    private var scrollAccumulator = 0.0
    /// Hold-to-zoom: how far in the zoom goes (the scroll wheel changes it while zooming, and it's
    /// remembered), whether the zoom key is held, and the smoothed amount the camera uses.
    var zoomFactor = 4.0
    private(set) var zooming = false
    private(set) var zoomAmount = 1.0
    static let zoomRange = 1.5...16.0
    private(set) var bobPhase = 0.0
    private(set) var bobAmount = 0.0
    private(set) var damageFlash = 0.0
    private(set) var hotbarNameTimer = 0.0
    private var lastSelected = -1
    private(set) var biome: Biome = .plains
    private(set) var isUnderground = false
    private(set) var swingProgress: Double = 0
    private var swingTimer: Double = -1
    private(set) var equipOffset: Double = 0
    /// Sway, landing dips, sprint lean, eating and tool swings for the first-person hand.
    private(set) var hand = HandAnimator()
    /// Seconds until each puff of crumbs while eating.
    private var crumbTimes: [Double] = []
    private var lastHeldItem: ItemID?

    let entities = EntityManager()
    let mobs = MobManager()

    /// (sound name, volume, pitch)
    var onSound: ((String, Float, Float) -> Void)?
    var onToast: ((String) -> Void)?
    var onOpenCrafting: (() -> Void)?
    var onSleep: (() -> Void)?

    /// Worn armor: head, chest, legs, feet.
    var armor: [ItemStack?] = Array(repeating: nil, count: 4)
    var armorPoints: Int {
        var points = 0
        for piece in armor { if let p = piece, let spec = items[p.item]?.armor { points += spec.protection } }
        return points
    }

    // Multiplayer
    let isRemote: Bool
    weak var network: SessionNetwork?
    private(set) var targetPlayer: RemotePlayer?
    var blockObserver: ((BlockPos, BlockID) -> Void)? { didSet { world.onBlockChanged = blockObserver } }
    var remoteChunkRequester: (([ChunkPos]) -> Void)? { didSet { world.remoteRequest = remoteChunkRequester } }

    // Doors, torches, chests & furnaces
    let variants: BlockVariants
    let containers = ContainerManager()
    let crops = CropManager()
    let arrows = ArrowSystem()
    /// 0…1 while drawing a bow.
    private(set) var bowCharge = 0.0
    private var drawingBow = false
    var smelting: SmeltingRegistry?
    var onOpenContainer: ((BlockPos, ContainerKind) -> Void)?
    var onOpenTrade: ((Mob) -> Void)?
    var onBlockBroken: ((BlockPos, BlockID) -> Void)?
    var onBlockHit: ((BlockPos, BlockID) -> Void)?
    let weather = WeatherSystem()
    let advancements = AdvancementTracker()
    private var explorationTimer = 1.0

    init(meta: WorldMetadata, isNew: Bool, storage: WorldStorage, blocks: BlockRegistry, items: ItemRegistry,
         meshFactory: ChunkMeshFactory, jobs: JobSystem, renderDistance: Int, remote: Bool = false) {
        self.meta = meta
        self.isRemote = remote
        variants = BlockVariants(blocks: blocks)
        self.isNewWorld = isNew
        self.storage = storage
        self.blocks = blocks
        self.items = items
        self.meshFactory = meshFactory
        self.jobs = jobs
        self.renderDistance = renderDistance

        let saved = remote ? nil : storage.loadPlayer(id: meta.id)
        let dim = saved?.dimension.flatMap(WorldDimension.init(rawValue:)) ?? .overworld
        dimension = dim
        let generator: WorldGenerator = dim.makeGenerator(seed: meta.numericSeed, deep: meta.isDeep)
        let overworld = TerrainGenerator(seed: meta.numericSeed, deep: meta.isDeep)
        world = World(registry: blocks, generator: generator, storage: remote ? nil : storage, worldID: remote ? nil : meta.id,
                      meshFactory: meshFactory, jobs: jobs, renderDistance: renderDistance)
        inventory = Inventory(registry: items)
        worldTime = meta.worldTime
        spectator = meta.hardcoreDead ?? false

        if let sx = meta.spawnX, let sy = meta.spawnY, let sz = meta.spawnZ {
            spawnPoint = DVec3(Double(sx) + 0.5, Double(sy), Double(sz) + 0.5)
        } else {
            let column = overworld.findSpawnColumn()
            spawnPoint = DVec3(Double(column.x) + 0.5, Double(overworld.estimatedSurface(x: column.x, z: column.z)) + 1, Double(column.z) + 0.5)
        }

        if let saved {
            player = PlayerController(position: DVec3(saved.x, saved.y, saved.z))
            player.yaw = saved.yaw
            player.pitch = saved.pitch
            health = saved.health
            hunger = saved.hunger
            saturation = saved.saturation
            air = saved.air ?? 10
            for s in saved.inventory where (0..<Inventory.size).contains(s.slot) {
                if let id = items.id(named: s.item) {
                    inventory.slots[s.slot] = ItemStack(item: id, count: max(1, s.count), damage: s.damage ?? 0)
                } else {
                    Log.warning("Dropping unknown saved item '\(s.item)'", category: "Save")
                }
            }
            for s in saved.armor ?? [] where (0..<4).contains(s.slot) {
                if let id = items.id(named: s.item) { armor[s.slot] = ItemStack(item: id, count: 1, damage: s.damage ?? 0) }
            }
            inventory.selected = saved.selectedSlot
            needsSpawnResolve = false
            spawnHint = Int(saved.y)
        } else {
            player = PlayerController(position: spawnPoint)
            needsSpawnResolve = meta.spawnY == nil
            spawnHint = Int(spawnPoint.y)
            if meta.gameMode == .creative {
                for (i, name) in ["grass", "dirt", "stone", "cobblestone", "planks", "log", "glass", "torch", "amber_lantern"].enumerated() {
                    if let id = items.id(named: name) { inventory.slots[i] = ItemStack(item: id, count: 64) }
                }
            }
        }
        player.gameMode = spectator ? .creative : meta.gameMode
        if saved?.flying == true || spectator { player.setFlying(true) }
        player.events.removeAll()
        loadingTitle = isNew ? "Generating World…" : (dim == .overworld ? "Loading World…" : "Entering \(dim.displayName)…")
        if !remote {
            entities.load(from: entitiesURL, items: items)
            mobs.load(from: mobsURL)
            containers.load(from: containersURL, items: items)
            crops.load(from: cropsURL)
        }
        advancements.load(from: advancementsURL)
        if let saved = meta.weather.flatMap({ WeatherKind(rawValue: $0) }) { weather.set(saved, duration: meta.weatherTimer) }
        Log.info("Session '\(meta.name)' opened (\(isNew ? "new" : "existing"), \(meta.gameMode.rawValue)\(meta.isHardcore ? ", hardcore" : ""), \(dim.rawValue), seed \(meta.seedText))", category: "Game")
    }

    private var entitiesURL: URL {
        storage.directory(for: meta.id).appendingPathComponent(dimension == .overworld ? "entities.json" : "entities_\(dimension.rawValue).json")
    }
    private var advancementsURL: URL {
        if isRemote {
            let safe = String(meta.name.map { $0.isLetter || $0.isNumber ? $0 : "_" })
            return GamePaths.root.appendingPathComponent("multiplayer", isDirectory: true).appendingPathComponent("\(safe)-advancements.json")
        }
        return storage.directory(for: meta.id).appendingPathComponent("advancements.json")
    }
    private var containersURL: URL {
        storage.directory(for: meta.id).appendingPathComponent(dimension == .overworld ? "containers.json" : "containers_\(dimension.rawValue).json")
    }
    private var cropsURL: URL {
        storage.directory(for: meta.id).appendingPathComponent(dimension == .overworld ? "crops.json" : "crops_\(dimension.rawValue).json")
    }
    private var mobsURL: URL {
        storage.directory(for: meta.id).appendingPathComponent(dimension == .overworld ? "mobs.json" : "mobs_\(dimension.rawValue).json")
    }

    var isNight: Bool { dimension == .overworld && SkyModel.state(worldTime: worldTime).isNight }
    var canBeTargeted: Bool { !isDead && !spectator && !isLoading && player.gameMode == .survival }
    var modeName: String { spectator ? "Spectator" : (meta.isHardcore ? "Hardcore" : player.gameMode.displayName) }

    // MARK: Loading

    private func updateLoading(_ dt: Double) {
        loadingElapsed += dt
        world.update(focus: player.position, budget: 0.012)
        let cx = Int32(floor(player.position.x / 16)), cz = Int32(floor(player.position.z / 16))
        let r = world.readiness(around: ChunkPos(cx, cz), radius: 4)
        let total = Float(max(1, r.total))
        loadingProgress = Float(r.generated) / total * 0.55 + Float(r.meshed) / total * 0.45
        loadingDetail = "\(r.generated)/\(r.total) chunks generated · \(r.meshed) built"

        if needsSpawnResolve, world.slot(at: ChunkPos(cx, cz)) != nil {
            let x = Int(floor(player.position.x)), z = Int(floor(player.position.z))
            let y: Int
            if let standing = world.findStandingY(x, z, near: spawnHint) {
                y = standing
            } else {
                y = max(8, min(200, spawnHint))
                carveSafeSpot(x, y, z)
            }
            player.teleport(to: DVec3(Double(x) + 0.5, Double(y), Double(z) + 0.5))
            if dimension == .overworld && meta.spawnY == nil {
                spawnPoint = player.position
                meta.spawnX = x; meta.spawnY = y; meta.spawnZ = z
            }
            needsSpawnResolve = false
            Log.info("Arrival resolved at \(x), \(y), \(z) in \(dimension.rawValue)", category: "Game")
        }

        var aroundPlayerLoaded = true
        if isRemote {
            for dz: Int32 in -1...1 { for dx: Int32 in -1...1 where world.slot(at: ChunkPos(cx + dx, cz + dz)) == nil { aroundPlayerLoaded = false } }
        }
        if !needsSpawnResolve && aroundPlayerLoaded && r.meshed >= r.total - 2 && loadingElapsed > 0.8 {
            var scratch: [DBox] = []
            var lifts = 0
            while VoxelPhysics.collides(world, player.box, scratch: &scratch) && lifts < 24 {
                player.teleport(to: player.position + DVec3(0, 1, 0))
                lifts += 1
            }
            if lifts >= 24 {
                player.teleport(to: player.position - DVec3(0, 24, 0))
                carveSafeSpot(Int(floor(player.position.x)), Int(floor(player.position.y)), Int(floor(player.position.z)))
            }
            if let portal = pendingReturnPortal {
                ensureReturnPortal(portal)
                pendingReturnPortal = nil
            }
            isLoading = false
            loadingProgress = 1
            Log.info(String(format: "World ready in %.1fs", loadingElapsed), category: "Game")
            if meta.bonusChest == true && dimension == .overworld && !isRemote { placeBonusChest() }
            if isNewWorld { save() }
        }
    }

    private func carveSafeSpot(_ x: Int, _ y: Int, _ z: Int) {
        let floorBlock: BlockID = dimension == .underworld ? Blocks.basalt : (dimension == .skylands ? Blocks.cloud : (dimension == .toonland ? Blocks.toonStone : Blocks.stone))
        for dz in -1...1 {
            for dx in -1...1 {
                for dy in 0...2 where world.block(x + dx, y + dy, z + dz) != Blocks.bedrock {
                    world.setBlock(BlockPos(x + dx, y + dy, z + dz), Blocks.air)
                }
                if !blocks.isSolid[Int(world.block(x + dx, y - 1, z + dz))] {
                    world.setBlock(BlockPos(x + dx, y - 1, z + dz), floorBlock)
                }
            }
        }
    }

    // MARK: Frame update

    func update(dt: Double, input: GameInput?, settings: GameSettings, paused: Bool) {
        if isLoading { updateLoading(dt); return }
        if isRemote { liftOutOfTerrain() }
        explorationTimer -= dt
        if explorationTimer <= 0 && !spectator {
            explorationTimer = 1.5
            checkExploration()
        }
        if !isRemote, let smelting {
            containers.tick(dt: dt, smelting: smelting, maxStack: inventory.maxStack) { pos, lit in
                if let st = variants.furnaceState(world.block(pos)), let v = variants.furnace(facing: st.facing, lit: lit) { world.setBlock(pos, v) }
            }
            if network == nil { containers.dirty.removeAll() }
        }
        renderDistance = settings.renderDistance
        world.renderDistance = settings.renderDistance
        world.update(focus: player.position)
        damageFlash = max(0, damageFlash - dt * 1.6)
        hotbarNameTimer = max(0, hotbarNameTimer - dt)
        if paused || input == nil || isDead { zooming = false }
        zoomAmount += ((zooming ? zoomFactor : 1) - zoomAmount) * (1 - exp(-14 * dt))
        if abs(zoomAmount - 1) < 0.001 { zoomAmount = 1 }
        if paused { return }

        clock += dt
        if meta.rule("doDaylightCycle") { worldTime += dt }
        weather.update(dt: dt, authoritative: !isRemote, cycle: meta.rule("doWeatherCycle"))
        meta.playTimeSeconds += dt
        hurtCooldown = max(0, hurtCooldown - dt)
        spawnProtection = max(0, spawnProtection - dt)
        if !isRemote { crops.update(dt: dt, world: world, wet: weather.kind != .clear) }

        if isDead {
            if !isRemote {
                mobs.update(dt: dt, session: self)
                entities.update(dt: dt, world: world, player: player, inventory: inventory, pickUp: false) { _ in }
            }
            return
        }

        var move = MovementInput()
        if let input {
            zooming = input.isDown(settings.binding(for: .zoom))
            applyLook(input, settings)
            move = movement(input, settings)
            if zooming {
                // While zooming the scroll wheel sets how far in to zoom instead of changing the hotbar slot.
                if input.scroll != 0 {
                    zoomFactor = min(GameSession.zoomRange.upperBound, max(GameSession.zoomRange.lowerBound, zoomFactor * pow(1.2, input.scroll)))
                }
                if let slot = input.hotbarKeyPressed { inventory.selected = slot }
            } else {
                hotbar(input)
            }
            interact(dt, input, settings)
        } else {
            breakingPos = nil
            breakProgress = 0
        }

        let px = Int(floor(player.position.x)), pz = Int(floor(player.position.z))
        let before = player.position
        if world.isLoaded(px, pz) {
            player.update(dt: dt, input: move, world: world)
        }
        // Lifetime stats: play time and distance walked (not flown). Menu backdrops have no input and don't count.
        if input != nil {
            let moved = player.position - before
            PlayerStats.shared.tick(dt: dt, walked: player.flying || spectator ? 0 : (moved.x * moved.x + moved.z * moved.z).squareRoot())
        }
        processPlayerEvents()
        if !isRemote {
            entities.update(dt: dt, world: world, player: player, inventory: inventory, pickUp: !spectator) { [weak self] stack in
                if let s = self, let name = s.items[stack.item]?.name { s.advancements.record("pickup", name, amount: stack.count) }
                self?.onSound?("pickup", 0.35, Float.random(in: 0.9...1.35))
            }
            mobs.update(dt: dt, session: self)
        }
        arrows.update(dt: dt, session: self)
        collectArrows()
        updateHandAnimation(dt)
        survival(dt)
        environment(dt)
        if !isRemote { updatePortal(dt) }
        if isLoading { return }

        if inventory.selected != lastSelected {
            if lastSelected >= 0 { hotbarNameTimer = 2.2 }
            lastSelected = inventory.selected
        }
        if player.onGround && !player.flying {
            bobPhase += player.horizontalSpeed * dt * 1.8
        }
        let bobTarget = player.onGround && !player.flying ? min(1, player.horizontalSpeed / 4.3) : 0
        bobAmount += (bobTarget - bobAmount) * (1 - exp(-8 * dt))

        autosaveTimer += dt
        if autosaveTimer > 45 {
            autosaveTimer = 0
            save()
        }
    }

    private func applyLook(_ input: GameInput, _ s: GameSettings) {
        // Zoomed in, the view turns slower so aiming stays steady.
        let sens = 0.0022 * (0.25 + s.mouseSensitivity * 1.5) / zoomAmount
        player.yaw -= input.mouseDelta.x * sens
        player.pitch -= input.mouseDelta.y * sens * (s.invertY ? -1 : 1)
        player.pitch = max(-1.5533, min(1.5533, player.pitch))
        player.yaw = player.yaw.truncatingRemainder(dividingBy: 2 * .pi)
    }

    private func movement(_ input: GameInput, _ s: GameSettings) -> MovementInput {
        var m = MovementInput()
        m.forward = (input.isDown(s.binding(for: .forward)) ? 1 : 0) - (input.isDown(s.binding(for: .backward)) ? 1 : 0)
        m.strafe = (input.isDown(s.binding(for: .right)) ? 1 : 0) - (input.isDown(s.binding(for: .left)) ? 1 : 0)
        m.jump = input.isDown(s.binding(for: .jump))
        m.jumpPressed = input.wasPressed(s.binding(for: .jump))
        m.sprint = input.isDown(s.binding(for: .sprint))
        m.sneak = input.isDown(s.binding(for: .crouch))
        return m
    }

    private func hotbar(_ input: GameInput) {
        if let slot = input.hotbarKeyPressed { inventory.selected = slot }
        scrollAccumulator += input.scroll
        while scrollAccumulator >= 1 { inventory.selected -= 1; scrollAccumulator -= 1 }
        while scrollAccumulator <= -1 { inventory.selected += 1; scrollAccumulator += 1 }
    }

    // MARK: Interaction

    private func soundGroup(_ id: BlockID) -> String? {
        guard let g = blocks[id]?.sound, g != SoundGroup.none else { return nil }
        return g.rawValue
    }

    private var heldTool: ToolSpec? {
        inventory.selectedStack.flatMap { items[$0.item]?.tool }
    }

    func breakTime(_ info: BlockInfo) -> Double {
        guard info.hardness > 0 else { return 0 }
        let tool = heldTool
        let correct = info.tool != .none && tool?.kind == info.tool
        let speed = correct ? Double(tool?.speed ?? 1) : 1
        var t = Double(info.hardness) * (canHarvest(info) ? 1.5 : 5.0) / speed
        if player.headInWater { t *= 3 }
        if !player.onGround && !player.flying && !player.inWater { t *= 2 }
        return t
    }

    func canHarvest(_ info: BlockInfo) -> Bool {
        guard info.toolLevel > 0 else { return true }
        guard let tool = heldTool else { return false }
        return tool.kind == info.tool && tool.level >= info.toolLevel
    }

    private func interact(_ dt: Double, _ input: GameInput, _ s: GameSettings) {
        let creative = player.gameMode == .creative
        let reach = creative ? 6.5 : 5.0
        target = VoxelPhysics.raycast(world, origin: player.eyePosition, direction: player.lookDirection, maxDistance: reach)
        attackCooldown = max(0, attackCooldown - dt)
        useCooldown = max(0, useCooldown - dt)
        combatCooldown = max(0, combatCooldown - dt)

        let mobHit = mobs.raycast(origin: player.eyePosition, direction: player.lookDirection, maxDistance: 4.2)
        if let (mob, distance) = mobHit, target == nil || distance < target!.distance {
            targetMob = mob
        } else {
            targetMob = nil
        }
        targetPlayer = nil
        if let (rp, pd) = remotePlayerHit(), target == nil || pd < target!.distance, mobHit == nil || pd < mobHit!.1 {
            targetPlayer = rp
            targetMob = nil
        }
        guard !spectator else {
            target = nil
            breakingPos = nil
            breakProgress = 0
            return
        }

        let attack = s.binding(for: .attack)
        var fought = false
        if input.wasPressed(attack) {
            swing()
            if let rp = targetPlayer {
                fought = true
                if combatCooldown <= 0 { attackRemotePlayer(rp) }
            } else if let mob = targetMob {
                fought = true
                if combatCooldown <= 0 { attackMob(mob) }
            }
        }

        if !fought, targetMob == nil, targetPlayer == nil, input.isDown(attack), let hit = target, let info = blocks[hit.id], info.isBreakable {
            let pressed = input.wasPressed(attack)
            if creative {
                if pressed || attackCooldown <= 0 {
                    breakBlock(at: hit.block, harvest: false)
                    attackCooldown = 0.25
                }
                breakingPos = nil
                breakProgress = 0
            } else {
                if breakingPos != hit.block {
                    breakingPos = hit.block
                    breakProgress = 0
                    hitSoundTimer = 0
                }
                let time = breakTime(info)
                if time <= 0.001 {
                    if pressed || attackCooldown <= 0 {
                        breakBlock(at: hit.block, harvest: true)
                        attackCooldown = 0.15
                    }
                } else if attackCooldown <= 0 {
                    breakProgress += dt / time
                    if swingTimer < 0 { swing() }
                    hitSoundTimer -= dt
                    if hitSoundTimer <= 0, let g = soundGroup(hit.id) {
                        onSound?("hit_\(g)", 0.45, 1)
                        onBlockHit?(hit.block, hit.id)
                        hitSoundTimer = 0.25
                    }
                    if breakProgress >= 1 {
                        breakBlock(at: hit.block, harvest: true)
                        breakingPos = nil
                        breakProgress = 0
                        attackCooldown = 0.1
                    }
                }
            }
        } else {
            breakingPos = nil
            breakProgress = 0
        }

        let use = s.binding(for: .use)
        if let stack = inventory.selectedStack, items[stack.item]?.name == "bow" {
            // Hold to draw (full power after a second), release to shoot.
            if input.isDown(use) {
                if !drawingBow && input.wasPressed(use) {
                    if hasArrows { drawingBow = true; bowCharge = 0 } else { onToast?("You need arrows to shoot the bow") }
                }
                if drawingBow { bowCharge = min(1, bowCharge + dt) }
            } else if drawingBow {
                if bowCharge > 0.15 { fireBow(power: bowCharge) }
                drawingBow = false
                bowCharge = 0
            }
        } else {
            drawingBow = false
            bowCharge = 0
            if input.wasPressed(use) || (input.isDown(use) && useCooldown <= 0) {
                if useItem(pressed: input.wasPressed(use)) { useCooldown = 0.22 } else { useCooldown = 0.05 }
            }
        }

        if input.wasPressed(s.binding(for: .pickBlock)), let hit = target, items[ItemID(hit.id)] != nil {
            inventory.pick(item: ItemID(hit.id), creative: creative)
        }

        if input.wasPressed(s.binding(for: .drop)), let stack = inventory.selectedStack {
            let whole = input.dropWholeStack
            var dropped = stack
            dropped.count = whole ? stack.count : 1
            inventory.consumeSelected(dropped.count)
            dropStack(dropped, thrown: true)
            swing()
        }
    }

    private func attackMob(_ mob: Mob) {
        let tool = heldTool
        var damage = Double(tool?.damage ?? 1)
        if player.gameMode == .creative { damage *= 6 }
        let critical = !player.onGround && !player.inWater && player.velocity.y < -1
        if critical { damage *= 1.5 }
        let look = player.lookDirection
        let flat = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(look.x, 0, look.z)) : DVec3(0, 0, -1)
        if !(network?.attackMob(mob, damage: damage, knockback: flat) ?? false) {
            mobs.hurt(mob, amount: damage, knockback: flat, session: self)
            if mob.health <= 0 {
                advancements.record("kill", mob.species.kind.rawValue)
                if mob.species.hostile { advancements.record("kill", "hostile") }
            }
        }
        combatCooldown = 0.35
        noteCombat(with: mob.species.displayName)
        if critical { onToast?("Critical hit!") }
        if tool != nil && player.gameMode == .survival && inventory.damageSelectedTool() {
            onSound?("tool_break", 0.8, 1)
            onToast?("Your tool broke!")
        }
        exhaustion += 0.1
    }

    // MARK: Bows

    private var hasArrows: Bool {
        player.gameMode == .creative || inventory.slots.contains { $0.flatMap { items[$0.item]?.name } == "arrow" }
    }

    private func fireBow(power: Double) {
        let survival = player.gameMode == .survival
        if survival {
            guard let i = inventory.slots.firstIndex(where: { $0.flatMap { items[$0.item]?.name } == "arrow" }), var st = inventory.slots[i] else { return }
            st.count -= 1
            inventory.slots[i] = st.count > 0 ? st : nil
            inventory.markChanged()
        }
        let dir = player.lookDirection
        arrows.fire(from: player.eyePosition + dir * 0.5 - DVec3(0, 0.08, 0), velocity: dir * (12 + 38 * power),
                    damage: (1.5 + 7.5 * power).rounded(), pickup: survival)
        swing()
        onSound?("bow_shoot", 0.7, Float(0.85 + power * 0.3))
        advancements.record("shoot")
        exhaustion += 0.05
    }

    /// Called by the arrow simulation when an arrow reaches a creature.
    func arrowHit(_ mob: Mob, arrow: Arrow) {
        let flat = DVec3(arrow.velocity.x, 0, arrow.velocity.z)
        let knockback = simd_length(flat) > 0.01 ? simd_normalize(flat) * 0.6 : .zero
        if !(network?.attackMob(mob, damage: arrow.damage, knockback: knockback) ?? false) {
            mobs.hurt(mob, amount: arrow.damage, knockback: knockback, session: self)
            if mob.health <= 0 {
                advancements.record("kill", mob.species.kind.rawValue)
                if mob.species.hostile { advancements.record("kill", "hostile") }
            }
        }
        let distance = simd_distance(arrow.origin, mob.position)
        if distance >= 15 { advancements.record("snipe") }
        noteCombat(with: mob.species.displayName)
        onSound?("arrow_hit", 0.7, 1.4)
        Log.info(String(format: "Arrow hit %@ for %.0f from %.1f blocks", mob.species.displayName, arrow.damage, distance), category: "Game")
    }

    /// Walk over arrows stuck in blocks to get them back.
    private func collectArrows() {
        guard !spectator, !isDead, let arrowID = items.id(named: "arrow") else { return }
        let center = player.position + DVec3(0, 0.9, 0)
        for a in arrows.arrows where a.stuck && a.pickup && !a.done && a.age > 0.5 && simd_distance(a.position, center) < 1.8 {
            if inventory.add(ItemStack(item: arrowID, count: 1)) == 0 {
                a.done = true
                onSound?("pickup", 0.35, 1.25)
            }
        }
    }

    func noteCombat(with name: String) {
        lastCombatTime = clock
        lastCombatMob = name
    }

    private func breakBlock(at pos: BlockPos, harvest: Bool) {
        let id = world.block(pos)
        guard let info = blocks[id], info.isBreakable else { return }
        // Plants that grow under water leave their water behind, and so does anything next to water.
        let waterNearby = info.submerged
            || [BlockFace.up, .north, .south, .east, .west].contains { Blocks.holdsWater(world.block(pos.offset($0)), blocks) }
        guard place(pos, waterNearby ? Blocks.water : Blocks.air, harvest: harvest && player.gameMode == .survival && canHarvest(info)) else { return }
        Log.info("Broke \(info.name) at \(pos)\(harvest && canHarvest(info) ? " (harvested)" : "")", category: "Game")
        onBlockBroken?(pos, id)
        advancements.record("break", info.name)
        if !isRemote, let kind = variants.containerKind(id) { prepareContainer(at: pos, kind: kind) }
        spillContainer(at: pos)
        if let door = variants.doorState(id) {
            let other = door.upper ? pos.offset(.down) : pos.offset(.up)
            if variants.doorState(world.block(other)) != nil {
                place(other, Blocks.air)
                if door.upper, harvest, player.gameMode == .survival, !isRemote,
                   let lowerID = variants.door(upper: false, open: false, facing: door.facing), let lowerInfo = blocks[lowerID] {
                    giveDrops(lowerInfo, at: other)
                }
            }
        }
        for f in BlockVariants.horizontal {
            let n = pos.offset(f)
            let nid = world.block(n)
            if variants.wallTorchWall(nid) == f.opposite {
                place(n, Blocks.air)
                if player.gameMode == .survival, !isRemote, let torchInfo = blocks[nid] { giveDrops(torchInfo, at: n) }
            }
        }
        if let g = soundGroup(id) { onSound?("break_\(g)", 0.85, 1) }
        lastMiningTime = clock

        if harvest && player.gameMode == .survival {
            if canHarvest(info) && !isRemote { giveDrops(info, at: pos) }
            if info.hardness > 0, heldTool != nil, inventory.damageSelectedTool() {
                onSound?("tool_break", 0.8, 1)
                onToast?("Your tool broke!")
            }
            exhaustion += 0.005
        }
        if WorldDimension.gateways.contains(where: { $0.frame == id }) { collapsePortals(near: pos) }
        let above = pos.offset(.up)
        if blocks[world.block(above)]?.needsSupport == true { breakBlock(at: above, harvest: harvest) }
    }

    /// Spawns a block's drops as item entities that pop out of the broken block.
    private func giveDrops(_ info: BlockInfo, at pos: BlockPos) {
        let center = DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.25, Double(pos.z) + 0.5)
        for drop in info.drops {
            if let chance = drop.chance, Float.random(in: 0..<1) >= chance { continue }
            let lo = drop.min ?? 1, hi = max(lo, drop.max ?? lo)
            let count = Int.random(in: lo...hi)
            guard count > 0, let item = items.id(named: drop.item) else { continue }
            let velocity = DVec3(Double.random(in: -1.4...1.4), Double.random(in: 3...4.5), Double.random(in: -1.4...1.4))
            entities.spawnItem(ItemStack(item: item, count: count), at: center, velocity: velocity, pickupDelay: 0.3)
        }
    }

    /// Throws (or gently drops) a stack from the player's hands.
    func dropStack(_ stack: ItemStack, thrown: Bool) {
        guard stack.count > 0 else { return }
        let dir = player.lookDirection
        let origin = player.eyePosition - DVec3(0, 0.3, 0) + dir * 0.35
        let velocity = thrown
            ? dir * 5.5 + DVec3(0, 1.8, 0)
            : DVec3(Double.random(in: -1...1), 2, Double.random(in: -1...1))
        if !(network?.dropItem(stack, at: origin, velocity: velocity) ?? false) {
            entities.spawnItem(stack, at: origin, velocity: velocity, pickupDelay: 1.5)
        }
        onSound?("ui_toggle", 0.35, 0.7)
    }

    func noteCrafted(_ item: ItemID? = nil, count: Int = 1) {
        lastCraftTime = clock
        if let item, let name = items[item]?.name { advancements.record("craft", name, amount: count) }
    }

    func swing() {
        if swingTimer < 0 || swingTimer > 0.14 { swingTimer = 0 }
    }

    private func updateHandAnimation(_ dt: Double) {
        if swingTimer >= 0 {
            swingTimer += dt
            swingProgress = min(1, swingTimer / 0.28)
            if swingTimer >= 0.28 { swingTimer = -1; swingProgress = 0 }
        }
        let held = inventory.selectedStack?.item
        if held != lastHeldItem {
            lastHeldItem = held
            equipOffset = 1
        }
        equipOffset = max(0, equipOffset - dt * 5)
        let tool = held.flatMap { items[$0]?.tool?.kind }
        hand.update(dt: dt, player: player, swing: swingProgress, tool: tool)
        if !crumbTimes.isEmpty {
            crumbTimes = crumbTimes.map { $0 - dt }
            for _ in crumbTimes.filter({ $0 <= 0 }) {
                effectBursts.append((player.eyePosition + player.lookDirection * 0.45 - DVec3(0, 0.2, 0), .crumbs))
            }
            crumbTimes.removeAll { $0 <= 0 }
        }
    }

    /// Returns true if something happened.
    private func useItem(pressed: Bool) -> Bool {
        if pressed, let mob = targetMob, mob.species.kind == .villager, !mob.isDying {
            swing()
            onOpenTrade?(mob)
            return true
        }
        if pressed, let hit = target, hit.id == Blocks.craftingBench, !player.isSneaking {
            swing()
            onOpenCrafting?()
            return true
        }
        if pressed, let hit = target, !player.isSneaking {
            if hit.id == Blocks.bed {
                swing()
                useBed(at: hit.block)
                return true
            }
            if variants.doorState(hit.id) != nil {
                swing()
                toggleDoor(at: hit.block)
                return true
            }
            if let kind = variants.containerKind(hit.id) {
                swing()
                openContainer(at: hit.block, kind: kind)
                return true
            }
        }
        guard let stack = inventory.selectedStack, let info = items[stack.item] else { return false }

        if let kind = MobKind.forEgg(named: info.name) {
            guard pressed, let hit = target else { return false }
            var cell = hit.adjacent
            if blocks[hit.id]?.replaceable == true { cell = hit.block }
            let species = MobSpecies.of(kind)
            let spot = DVec3(Double(cell.x) + 0.5, Double(cell.y) + (species.flying ? 1 : 0), Double(cell.z) + 0.5)
            swing()
            if !(network?.spawnMob(kind, at: spot) ?? false) {
                let mob = mobs.spawn(kind, at: spot)
                if kind == .villager { mob.home = spot }
            }
            if species.hostile && meta.difficulty == .peaceful {
                onToast?("Hostile creatures can't stay on Peaceful difficulty")
            }
            if player.gameMode == .survival { inventory.consumeSelected() }
            onSound?(species.deepCall ? "amb_dino_low" : "amb_dino_high", 0.6, species.callPitch)
            Log.info("Spawn egg hatched a \(species.displayName) at \(cell)", category: "Game")
            return true
        }

        if info.name == "ember_lighter" {
            guard pressed, let hit = target else { return false }
            swing()
            if tryActivatePortal(at: hit.adjacent) { return true }
            onToast?("Strike the Ember Lighter inside a Bone Block, Amber Block or Checker Block frame")
            return true
        }

        if let spec = info.armor {
            guard pressed else { return false }
            let i = spec.slot.index
            let old = armor[i]
            armor[i] = stack
            inventory.slots[inventory.selected] = old
            inventory.markChanged()
            onSound?("place_metal", 0.6, 1.25)
            advancements.record("equip", info.name)
            swing()
            return true
        }

        // Farming: till with a hoe, plant seeds on farmland, speed crops up with bone meal.
        if let tool = info.tool, tool.kind == .hoe {
            guard pressed, let hit = target, hit.face != .down,
                  hit.id == Blocks.grass || hit.id == Blocks.dirt || hit.id == Blocks.snowyGrass else { return false }
            let above = hit.block.offset(.up)
            let aboveID = world.block(above)
            guard aboveID == Blocks.air || blocks[aboveID]?.replaceable == true, aboveID != Blocks.water else { return false }
            if aboveID != Blocks.air { place(above, Blocks.air) }
            guard place(hit.block, Blocks.farmland) else { return false }
            swing()
            onSound?("place_dirt", 0.8, 0.9)
            advancements.record("till")
            if player.gameMode == .survival && inventory.damageSelectedTool() {
                onSound?("tool_break", 0.8, 1)
                onToast?("Your tool broke!")
            }
            return true
        }
        if let crop = CropManager.seedCrops[info.name], pressed, let hit = target, hit.id == Blocks.farmland,
           world.block(hit.block.offset(.up)) == Blocks.air {
            let cell = hit.block.offset(.up)
            guard place(cell, crop) else { return false }
            if !isRemote { crops.plant(cell) }
            swing()
            onSound?("place_grass", 0.7, 1.2)
            advancements.record("plant", info.name)
            if player.gameMode == .survival { inventory.consumeSelected() }
            return true
        }
        if info.name == "bone_meal" {
            guard pressed, let hit = target, let growth = CropManager.stage(of: hit.id), growth.stage < growth.stages.count - 1 else { return false }
            let next = min(growth.stages.count - 1, growth.stage + Int.random(in: 1...2))
            guard place(hit.block, growth.stages[next]) else { return false }
            if !isRemote { crops.plant(hit.block) }
            onBlockHit?(hit.block, growth.stages[next])
            swing()
            onSound?("place_grass", 0.7, 1.5)
            if player.gameMode == .survival { inventory.consumeSelected() }
            return true
        }

        if let food = info.food, player.gameMode == .survival {
            guard pressed, hunger < 20 else { return false }
            hunger = min(20, hunger + Double(food.hunger))
            saturation = min(hunger, saturation + Double(food.saturation))
            inventory.consumeSelected()
            onSound?("eat", 0.7, 1)
            advancements.record("eat", info.name)
            hand.startEating()
            crumbTimes = [0, 0.2, 0.4]
            return true
        }

        guard var blockID = info.block, let hit = target else { return false }
        var pos = hit.adjacent
        if blocks[hit.id]?.replaceable == true { pos = hit.block }
        guard pos.y >= 0, pos.y < Int32(WorldConst.height), world.isLoaded(Int(pos.x), Int(pos.z)) else { return false }
        guard blocks[world.block(pos)]?.replaceable ?? true else { return false }
        // Orientation variants: wall torches, doors (two blocks), furnaces and chests facing the player.
        let towardPlayer = BlockVariants.horizontalFacing(player.lookDirection).opposite
        var upperDoor: BlockID?
        if blockID == Blocks.torch, hit.face != .up, pos == hit.adjacent {
            guard hit.face != .down, blocks.isSolid[Int(hit.id)], let wall = variants.wallTorch(facing: hit.face.opposite) else { return false }
            blockID = wall
        } else if variants.doorState(blockID) != nil {
            guard pos.y + 1 < Int32(WorldConst.height),
                  let lower = variants.door(upper: false, open: false, facing: towardPlayer),
                  let upper = variants.door(upper: true, open: false, facing: towardPlayer),
                  blocks[world.block(pos.offset(.up))]?.replaceable ?? true,
                  blocks.isSolid[Int(world.block(pos.offset(.down)))] else { return false }
            blockID = lower
            upperDoor = upper
        } else if let family = variants.family(of: blockID) {
            let face = blocks[blockID]?.placement == "look" ? BlockVariants.horizontalFacing(player.lookDirection) : towardPlayer
            if let variant = family[face] { blockID = variant }
        }
        guard let placed = blocks[blockID] else { return false }
        let below = world.block(pos.offset(.down))
        // Kelp grows on kelp; sea plants only go in water.
        if placed.needsSupport && !blocks.isSolid[Int(below)] && !(placed.submerged && below == blockID) { return false }
        if placed.submerged && world.block(pos) != Blocks.water { return false }
        if placed.solid {
            let origin = DVec3(Double(pos.x), Double(pos.y), Double(pos.z))
            let shape = blocks.boxes[Int(blockID)]
            let extra = DVec3(0, upperDoor != nil ? 1 : 0, 0)
            let box = DBox(min: origin + (shape?.minBlocks ?? DVec3(0, 0, 0)), max: origin + (shape?.maxBlocks ?? DVec3(1, 1, 1)) + extra)
            if box.intersects(player.box) { return false }
            if mobs.mobs.contains(where: { !$0.isDying && $0.box.intersects(box) }) { return false }
        }
        guard place(pos, blockID) else { return false }
        if let upperDoor { place(pos.offset(.up), upperDoor) }
        advancements.record("place", placed.name)
        Log.info("Placed \(placed.name) at \(pos)", category: "Game")
        swing()
        if let g = soundGroup(blockID) { onSound?("place_\(g)", 0.8, 1) }
        lastBuildingTime = clock
        if player.gameMode == .survival { inventory.consumeSelected() }
        return true
    }

    // MARK: Gateways

    private func isPortal(_ id: BlockID) -> Bool { WorldDimension.forPortal(id) != nil }

    private func airish(_ p: BlockPos) -> Bool {
        let id = world.block(p)
        return id == Blocks.air || blocks[id]?.replaceable == true
    }

    /// Lights a rectangular gateway frame (interior 2–6 wide, 3–7 tall) of bone, amber or checker blocks.
    private func tryActivatePortal(at cell: BlockPos) -> Bool {
        guard airish(cell) else { return false }
        for (portal, frame) in WorldDimension.gateways {
            for alongX in [true, false] {
                let neg: BlockFace = alongX ? .west : .north
                let posDir: BlockFace = alongX ? .east : .south
                var bottom = cell
                var steps = 0
                while world.block(bottom.offset(.down)) != frame {
                    guard airish(bottom.offset(.down)), steps < 6 else { steps = 99; break }
                    bottom = bottom.offset(.down); steps += 1
                }
                guard steps < 99 else { continue }
                var start = bottom
                steps = 0
                while world.block(start.offset(neg)) != frame {
                    guard airish(start.offset(neg)), steps < 6 else { steps = 99; break }
                    start = start.offset(neg); steps += 1
                }
                guard steps < 99 else { continue }
                var width = 1, probe = start
                while world.block(probe.offset(posDir)) != frame && width <= 6 {
                    guard airish(probe.offset(posDir)) else { width = 99; break }
                    probe = probe.offset(posDir); width += 1
                }
                var height = 1
                probe = start
                while world.block(probe.offset(.up)) != frame && height <= 7 {
                    guard airish(probe.offset(.up)) else { height = 99; break }
                    probe = probe.offset(.up); height += 1
                }
                guard (2...6).contains(width), (3...7).contains(height) else { continue }
                let n = posDir.normal
                func cellAt(_ w: Int, _ h: Int) -> BlockPos {
                    BlockPos(start.x + n.x * Int32(w), start.y + Int32(h), start.z + n.z * Int32(w))
                }
                var valid = true
                for w in 0..<width where valid {
                    if world.block(cellAt(w, -1)) != frame || world.block(cellAt(w, height)) != frame { valid = false }
                    for h in 0..<height where !airish(cellAt(w, h)) { valid = false }
                }
                for h in 0..<height where valid {
                    if world.block(cellAt(-1, h)) != frame || world.block(cellAt(width, h)) != frame { valid = false }
                }
                guard valid else { continue }
                for w in 0..<width { for h in 0..<height { place(cellAt(w, h), portal) } }
                let target = WorldDimension.forPortal(portal) ?? .skylands
                onSound?("discover", 0.9, target == .underworld ? 0.7 : (target == .toonland ? 1.5 : 1.2))
                switch target {
                case .underworld: onToast?("The Underworld Gateway awakens!")
                case .toonland: onToast?("The Toonland Gateway swirls with golden light!")
                default: onToast?("The Skylands Gateway shimmers open!")
                }
                Log.info("Activated \(target.rawValue) gateway \(width)x\(height) at \(start)", category: "Game")
                return true
            }
        }
        return false
    }

    private func collapsePortals(near pos: BlockPos) {
        var queue = BlockFace.allCases.map { pos.offset($0) }.filter { isPortal(world.block($0)) }
        var removed = 0
        while let p = queue.popLast(), removed < 256 {
            guard isPortal(world.block(p)) else { continue }
            place(p, Blocks.air)
            removed += 1
            for f in BlockFace.allCases where isPortal(world.block(p.offset(f))) { queue.append(p.offset(f)) }
        }
        if removed > 0 { onSound?("break_glass", 0.8, 0.6) }
    }

    private func updatePortal(_ dt: Double) {
        let box = player.box
        var found: BlockID?
        for y in Int(floor(box.min.y))...Int(floor(box.max.y)) {
            for z in Int(floor(box.min.z))...Int(floor(box.max.z)) {
                for x in Int(floor(box.min.x))...Int(floor(box.max.x)) where isPortal(world.block(x, y, z)) {
                    found = world.block(x, y, z)
                }
            }
        }
        portalKind = found
        guard let portal = found else {
            portalCooldown = max(0, portalCooldown - dt)
            portalProgress = max(0, portalProgress - dt * 2)
            return
        }
        guard portalCooldown <= 0 else { return }
        if portalProgress == 0 { onSound?("ui_open", 0.6, 0.5) }
        portalProgress += dt / (player.gameMode == .creative ? 0.7 : 2.2)
        if portalProgress >= 1 {
            portalProgress = 0
            changeDimension(to: dimension.destination(through: portal), portal: portal, arrival: nil)
        }
    }

    /// Travels to another dimension: saves this one, streams in the target and
    /// places the player at the scaled coordinates (building a return gateway if needed).
    func changeDimension(to target: WorldDimension, portal: BlockID?, arrival: DVec3?) {
        guard target != dimension || arrival != nil else { return }
        save()
        world.shutdown()
        let scale = dimension.coordinateScale / target.coordinateScale
        let destination = arrival ?? DVec3(player.position.x * scale, player.position.y, player.position.z * scale)
        Log.info("Travelling \(dimension.rawValue) → \(target.rawValue)", category: "Game")
        dimension = target
        let generator: WorldGenerator = target.makeGenerator(seed: meta.numericSeed, deep: meta.isDeep)
        world = World(registry: blocks, generator: generator, storage: isRemote ? nil : storage, worldID: isRemote ? nil : meta.id,
                      meshFactory: meshFactory, jobs: jobs, renderDistance: renderDistance)
        world.onBlockChanged = blockObserver
        world.remoteRequest = remoteChunkRequester
        entities.clear()
        mobs.clear()
        containers.clear()
        crops.clear()
        arrows.clear()
        if !isRemote {
            entities.load(from: entitiesURL, items: items)
            mobs.load(from: mobsURL)
            containers.load(from: containersURL, items: items)
            crops.load(from: cropsURL)
        }
        let x = Int(floor(destination.x)), z = Int(floor(destination.z))
        let estimate = arrival.map { Int($0.y) } ?? generator.estimatedSurface(x: x, z: z)
        spawnHint = estimate > 0 ? estimate : (target == .underworld ? 64 : (target == .toonland ? 70 : 100))
        player.teleport(to: DVec3(Double(x) + 0.5, Double(spawnHint), Double(z) + 0.5))
        needsSpawnResolve = true
        pendingReturnPortal = arrival == nil ? portal : nil
        portalCooldown = 4
        portalProgress = 0
        isLoading = true
        loadingElapsed = 0
        loadingProgress = 0
        loadingTitle = "Entering \(target.displayName)…"
        advancements.record("dimension", target.rawValue)
        network?.dimensionChanged(target, position: destination)
        onSound?("discover", 0.8, target == .underworld ? 0.6 : 1.3)
        if target == .toonland { onToast?("Welcome to Toonland! Follow a checkered road to King Grumblesaurus's stage.") }
    }

    private func ensureReturnPortal(_ portal: BlockID) {
        let px = Int(floor(player.position.x)), py = Int(floor(player.position.y)), pz = Int(floor(player.position.z))
        for dy in -8...8 { for dz in -12...12 { for dx in -12...12 where world.block(px + dx, py + dy, pz + dz) == portal { return } } }
        guard let frame = WorldDimension.forPortal(portal)?.frameBlock else { return }
        let floorBlock: BlockID = dimension == .underworld ? Blocks.obsidian : (dimension == .skylands ? Blocks.cloud : (dimension == .toonland ? Blocks.toonStone : Blocks.stone))
        let ox = px + 2, z = pz - 1, y = py
        for x in (ox - 2)...(ox + 3) {
            for zz in (z - 1)...(z + 1) {
                for yy in y...(y + 3) where world.block(x, yy, zz) != Blocks.bedrock { world.setBlock(BlockPos(x, yy, zz), Blocks.air) }
            }
            for zz in (z - 2)...(z + 2) where !blocks.isSolid[Int(world.block(x, y - 1, zz))] {
                world.setBlock(BlockPos(x, y - 1, zz), floorBlock)
            }
        }
        for x in (ox - 1)...(ox + 2) {
            world.setBlock(BlockPos(x, y - 1, z), frame)
            world.setBlock(BlockPos(x, y + 3, z), frame)
        }
        for yy in y...(y + 2) {
            world.setBlock(BlockPos(ox - 1, yy, z), frame)
            world.setBlock(BlockPos(ox + 2, yy, z), frame)
            world.setBlock(BlockPos(ox, yy, z), portal)
            world.setBlock(BlockPos(ox + 1, yy, z), portal)
        }
        Log.info("Built return gateway at \(ox), \(y), \(z)", category: "Game")
    }

    // MARK: Advancements

    /// Periodic checks for exploration advancements: depth, height, creatures nearby, villages and structures.
    private func checkExploration() {
        let p = player.position
        let shownY = p.y - Double(world.generator.depthOffset)
        if shownY < 12 { advancements.record("depth") }
        if shownY < -60 { advancements.record("depth", "bottom") }
        if shownY > 180 { advancements.record("height") }
        for m in mobs.mobs where !m.isDying && simd_distance(m.position, p) < 8 {
            advancements.record("near", m.species.kind.rawValue)
        }
        guard dimension == .overworld, let generator = world.generator as? TerrainGenerator else { return }
        let x = Int(floor(p.x)), z = Int(floor(p.z))
        if !advancements.isUnlocked("village"), !generator.villages(near: x, z: z, radius: 20).isEmpty {
            advancements.record("visit", "village")
        }
        for s in generator.structures(near: x, z: z, radius: 10) where abs(Double(s.y) - p.y) < 16 {
            advancements.record("visit", s.kind.rawValue)
        }
    }

    // MARK: Doors & containers

    private func toggleDoor(at pos: BlockPos) {
        guard let st = variants.doorState(world.block(pos)) else { return }
        let lower = st.upper ? pos.offset(.down) : pos
        let top = lower.offset(.up)
        let open = !st.open
        if variants.doorState(world.block(lower)) != nil, let l = variants.door(upper: false, open: open, facing: st.facing) { place(lower, l) }
        if variants.doorState(world.block(top)) != nil, let u = variants.door(upper: true, open: open, facing: st.facing) { place(top, u) }
        onSound?(open ? "ui_open" : "ui_close", 0.6, 0.75)
        Log.info("Door at \(lower) \(open ? "opened" : "closed")", category: "Game")
    }

    /// Both halves of a double chest (or just this chest), in screen order.
    func chestHalves(_ pos: BlockPos) -> [BlockPos] {
        ChestHalves.positions(pos, registry: blocks) { [world] x, y, z in world.block(x, y, z) }
    }

    private func openContainer(at pos: BlockPos, kind: ContainerKind) {
        let halves = kind == .chest ? chestHalves(pos) : [pos]
        for half in halves {
            if isRemote {
                network?.containerOpened(half)
            } else {
                prepareContainer(at: half, kind: kind)
            }
        }
        onSound?("ui_open", 0.5, kind == .chest ? 0.9 : 0.7)
        onOpenContainer?(pos, kind)
    }

    /// The container at a chest or furnace, created on first use. Chests that
    /// villages, dungeons or ruins generated roll their loot at that moment.
    @discardableResult
    func prepareContainer(at pos: BlockPos, kind: ContainerKind) -> Container {
        if let existing = containers.get(pos), existing.kind == kind { return existing }
        let c = containers.ensure(pos, kind: kind)
        if kind == .chest, !isRemote, dimension == .overworld, !containers.looted.contains(pos),
           let generator = world.generator as? TerrainGenerator,
           let table = generator.lootTable(x: Int(pos.x), y: Int(pos.y), z: Int(pos.z)) {
            containers.looted.insert(pos)
            LootTables.fill(c, table: table, items: items)
            advancements.record("loot", table)
            containers.dirty.insert(pos)
            Log.info("Rolled \(table) loot for the chest at \(pos)", category: "Game")
        }
        return c
    }

    /// Called by container screens after the player moves items.
    func containerChanged(_ pos: BlockPos) {
        if isRemote {
            if let c = containers.get(pos) { network?.containerChanged(pos, c) }
        } else {
            containers.dirty.insert(pos)
        }
    }

    /// Drops a removed chest's or furnace's contents into the world (authoritative side only).
    private func spillContainer(at pos: BlockPos) {
        guard !isRemote, let c = containers.remove(pos) else { return }
        let center = DVec3(Double(pos.x) + 0.5, Double(pos.y) + 0.5, Double(pos.z) + 0.5)
        for stack in c.slots.compactMap({ $0 }) {
            let v = DVec3(Double.random(in: -2...2), Double.random(in: 2...4), Double.random(in: -2...2))
            entities.spawnItem(stack, at: center, velocity: v, pickupDelay: 0.5)
        }
    }

    /// New worlds created with "Bonus Chest": a chest of starter supplies ringed by torches near spawn.
    private func placeBonusChest() {
        meta.bonusChest = false
        let px = Int(floor(player.position.x)), py = Int(floor(player.position.y)), pz = Int(floor(player.position.z))
        for (dx, dz) in [(2, 0), (-2, 0), (0, 2), (0, -2), (2, 2), (-2, -2), (3, 1), (1, 3), (-3, -1)] {
            let x = px + dx, z = pz + dz
            guard let y = world.findStandingY(x, z, near: py), abs(y - py) <= 3 else { continue }
            let pos = BlockPos(x, y, z)
            let front = BlockVariants.horizontalFacing(DVec3(Double(-dx), 0, Double(-dz)))
            guard let chestID = variants.chest(facing: front), world.setBlock(pos, chestID) else { continue }
            let chest = containers.ensure(pos, kind: .chest)
            let loot: [(String, Int)] = [("log", 6), ("planks", 12), ("stick", 8), ("wooden_pickaxe", 1), ("wooden_axe", 1),
                                         ("berries", 6), ("trail_mix", 2), ("torch", 8), ("coal", 4)]
            for (i, entry) in loot.enumerated() {
                if let id = items.id(named: entry.0) { chest.slots[(i * 3 + 1) % 27] = ItemStack(item: id, count: entry.1) }
            }
            for f in BlockVariants.horizontal where f != front {
                let t = pos.offset(f)
                if world.block(t) == Blocks.air, blocks.isSolid[Int(world.block(t.offset(.down)))] { world.setBlock(t, Blocks.torch) }
            }
            Log.info("Bonus chest placed at \(pos)", category: "Game")
            onToast?("A bonus chest is waiting next to you!")
            return
        }
        Log.warning("No room for the bonus chest near spawn", category: "Game")
    }

    // MARK: Multiplayer

    /// Clients receive terrain asynchronously; if a chunk arrives around the
    /// player (or a remote edit fills their space), move them up onto solid ground.
    private func liftOutOfTerrain() {
        guard !player.flying else { return }
        let x = Int(floor(player.position.x)), z = Int(floor(player.position.z))
        guard world.isLoaded(x, z) else { return }
        let feet = Int(floor(player.position.y + 0.05)), head = Int(floor(player.position.y + 1.6))
        guard blocks.isSolid[Int(world.block(x, feet, z))] || blocks.isSolid[Int(world.block(x, head, z))] else { return }
        var y = feet + 1
        while y < WorldConst.height - 2 && (blocks.isSolid[Int(world.block(x, y, z))] || blocks.isSolid[Int(world.block(x, y + 1, z))]) { y += 1 }
        player.teleport(to: DVec3(player.position.x, Double(y), player.position.z))
        Log.info("Lifted player out of terrain to y \(y)", category: "Net")
    }

    /// Sets a block locally and, when connected to a host, reports the edit.
    @discardableResult
    private func place(_ pos: BlockPos, _ id: BlockID, harvest: Bool = false) -> Bool {
        guard world.setBlock(pos, id) else { return false }
        if isRemote { network?.blockChanged(pos, id, harvest: harvest) }
        return true
    }

    func localPlayerState(id: Int) -> PlayerStateMessage {
        PlayerStateMessage(id: id, x: player.position.x, y: player.position.y, z: player.position.z,
                           yaw: Float(player.yaw), pitch: Float(player.pitch),
                           moving: Float(player.onGround ? min(1, player.horizontalSpeed / 4.3) : 0),
                           sneaking: player.isSneaking, swinging: swingTimer >= 0,
                           held: inventory.selectedStack.flatMap { items[$0.item]?.name },
                           health: Float(health), dead: isDead || spectator, look: playerLook.isEmpty ? nil : playerLook)
    }

    /// This player's cosmetics (`PlayerLook.encoded`), sent to friends with every update.
    var playerLook = ""

    /// Host: applies a block edit made by a connected player (even in unloaded chunks).
    func applyRemoteBlockChange(_ pos: BlockPos, _ id: BlockID, harvest: Bool) {
        guard pos.y >= 0, pos.y < Int32(WorldConst.height), blocks[id] != nil else { return }
        // Crops a friend plants (or fertilizes) grow on the host.
        if CropManager.stage(of: id) != nil { crops.plant(pos) }
        let old: BlockID
        if world.isLoaded(Int(pos.x), Int(pos.z)) {
            old = world.block(pos)
            guard world.setBlock(pos, id) else { return }
        } else {
            let folder = dimension.storageFolder
            let chunk = storage.loadChunk(worldID: meta.id, pos: pos.chunk, dimension: folder) ?? world.generator.generate(pos.chunk)
            let lx = Int(pos.x) & 15, lz = Int(pos.z) & 15
            old = chunk.block(lx, Int(pos.y), lz)
            chunk.set(lx, Int(pos.y), lz, id)
            do {
                try storage.writeChunkData(chunk.serialize(), worldID: meta.id, pos: pos.chunk, dimension: folder)
            } catch {
                Log.error("Could not apply remote edit at \(pos): \(error)", category: "Net")
            }
            blockObserver?(pos, id)
        }
        if let kind = variants.containerKind(old), variants.containerKind(id) == nil {
            prepareContainer(at: pos, kind: kind)
            spillContainer(at: pos)
        }
        if harvest, id == Blocks.air || id == Blocks.water, old != id, let info = blocks[old], info.isBreakable {
            giveDrops(info, at: pos)
        }
    }

    func receiveItem(name: String, count: Int, damage: Int) {
        guard let id = items.id(named: name) else { return }
        advancements.record("pickup", name, amount: count)
        let left = inventory.add(ItemStack(item: id, count: count, damage: damage))
        if left > 0 { dropStack(ItemStack(item: id, count: left, damage: damage), thrown: false) }
        onSound?("pickup", 0.35, Float.random(in: 0.9...1.35))
    }

    /// Particle bursts requested by the game (boss stomps, confetti), drained by the particle system.
    var effectBursts: [(position: DVec3, kind: EffectBurst)] = []

    func isBossDefeated(_ name: String) -> Bool { meta.defeatedBosses?.contains(name) == true }

    func markBossDefeated(_ name: String) {
        guard !isBossDefeated(name) else { return }
        meta.defeatedBosses = (meta.defeatedBosses ?? []) + [name]
        save()
    }

    func followDimension(_ target: WorldDimension, position: DVec3) {
        changeDimension(to: target, portal: nil, arrival: position)
    }

    /// Everyone hostile creatures may chase: the local player (id 0 on the host) and connected players.
    func hostileTargets() -> [(id: Int, pos: DVec3)] {
        var list: [(id: Int, pos: DVec3)] = []
        if canBeTargeted { list.append((0, player.position)) }
        if let n = network, !n.isClient {
            for p in n.remotePlayers where !p.dead { list.append((p.id, p.position)) }
        }
        return list
    }

    func damageTarget(id: Int, amount: Double, cause: String, attacker: String, knockback: DVec3) {
        if id == 0 {
            takeDamage(amount, cause: cause, knockback: knockback)
            noteCombat(with: attacker)
        } else {
            network?.damageRemotePlayer(id: id, amount: amount, cause: cause, knockback: knockback)
        }
    }

    private func remotePlayerHit() -> (RemotePlayer, Double)? {
        guard let players = network?.remotePlayers, !spectator else { return nil }
        var best: (RemotePlayer, Double)?
        for p in players where !p.dead {
            if let t = MobManager.rayBox(player.eyePosition, player.lookDirection, p.box), t < 4.2, t < (best?.1 ?? .infinity) {
                best = (p, t)
            }
        }
        return best
    }

    private func attackRemotePlayer(_ target: RemotePlayer) {
        let tool = heldTool
        var damage = Double(tool?.damage ?? 1)
        if !player.onGround && !player.inWater && player.velocity.y < -1 { damage *= 1.5 }
        let look = player.lookDirection
        let flat = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(look.x, 0, look.z)) : DVec3(0, 0, -1)
        network?.attackPlayer(target, damage: damage, knockback: flat)
        target.hurtTimer = 0.35
        combatCooldown = 0.45
        noteCombat(with: target.name)
        onSound?("hurt", 0.6, 1.1)
        if tool != nil && player.gameMode == .survival && inventory.damageSelectedTool() {
            onSound?("tool_break", 0.8, 1)
            onToast?("Your tool broke!")
        }
    }

    // MARK: Survival

    private func processPlayerEvents() {
        for event in player.events {
            switch event {
            case .footstep(let id):
                if let g = soundGroup(id) { onSound?("step_\(g)", player.isSneaking ? 0.12 : 0.28, 1) }
            case .landed(let distance, let id):
                hand.landed(fallDistance: distance)
                if distance > 3.5 && player.gameMode == .survival && !player.inWater {
                    damage((distance - 3).rounded(.down), cause: "Fell from a high place")
                    onSound?("land", 0.8, 1)
                } else if distance > 1, let g = soundGroup(id) {
                    onSound?("step_\(g)", 0.45, 0.9)
                }
            case .jumped:
                exhaustion += player.isSprinting ? 0.2 : 0.05
            case .enteredWater:
                if player.velocity.y < -5 { onSound?("splash", 0.6, 1) }
            default:
                break
            }
        }
        player.events.removeAll()
    }

    private func survival(_ dt: Double) {
        guard player.gameMode == .survival else {
            health = 20; hunger = 20; air = 10
            return
        }
        let difficulty = meta.difficulty
        if player.isSprinting && player.onGround { exhaustion += player.horizontalSpeed * dt * 0.1 }
        if difficulty == .peaceful {
            exhaustion = 0
            hunger = 20
        }
        while exhaustion >= 4 {
            exhaustion -= 4
            if saturation > 0 { saturation = max(0, saturation - 1) } else { hunger = max(0, hunger - 1) }
        }
        if hunger >= 18 && health < 20 {
            regenTimer += dt
            if regenTimer >= (difficulty == .peaceful ? 1 : 3.5) {
                regenTimer = 0
                health = min(20, health + 1)
                exhaustion += 1.5
            }
        } else {
            regenTimer = 0
        }
        if hunger <= 0 {
            starveTimer += dt
            if starveTimer >= 4 {
                starveTimer = 0
                let floorHealth: Double = difficulty == .hard ? 0 : (difficulty == .normal ? 1 : 10)
                if health > floorHealth { damage(1, cause: "Starved in the wilderness") }
            }
        }
        if player.headInWater && Blocks.holdsWater(world.block(Int(floor(player.eyePosition.x)), Int(floor(player.eyePosition.y)), Int(floor(player.eyePosition.z))), world.registry) {
            air -= dt
            if air < 0 {
                drownTimer += dt
                if drownTimer >= 1 { drownTimer = 0; damage(2, cause: "Drowned") }
            }
        } else {
            air = min(10, air + dt * 5)
            drownTimer = 0
        }
        cactusTimer = max(0, cactusTimer - dt)
        let prickBox = DBox(min: player.box.min - DVec3(0.06, 0, 0.06), max: player.box.max + DVec3(0.06, 0, 0.06))
        if cactusTimer <= 0, VoxelPhysics.anyBlock(world, in: prickBox, where: { $0 == Blocks.cactus }) {
            cactusTimer = 0.6
            damage(1, cause: "Pricked by a cactus")
        }
        if VoxelPhysics.anyBlock(world, in: player.box, where: { $0 == Blocks.lava }) {
            lavaTimer += dt
            if lavaTimer >= 0.5 {
                lavaTimer = 0
                damage(4, cause: "Tried to swim in lava")
                onSound?("splash", 0.5, 0.5)
            }
        } else {
            lavaTimer = 0.4
        }
        if player.position.y < -24 { damage(1000, cause: "Fell out of the world") }
    }

    /// Damage from creatures and projectiles: brief invulnerability, knockback, difficulty scaling.
    func takeDamage(_ amount: Double, cause: String, knockback: DVec3?) {
        guard canBeTargeted, hurtCooldown <= 0, spawnProtection <= 0 else { return }
        let scale: Double
        switch meta.difficulty {
        case .peaceful: scale = 0
        case .easy: scale = 0.4
        case .normal: scale = 0.6
        case .hard: scale = 1.0
        }
        guard scale > 0 else { return }
        hurtCooldown = 0.55
        if let k = knockback {
            player.velocity += DVec3(k.x * 7, 4.5, k.z * 7)
        }
        damage(absorbArmor(amount * scale), cause: cause)
    }

    /// Armor soaks up 4% of creature and projectile damage per point (at most 80%) and wears down with each hit.
    private func absorbArmor(_ amount: Double) -> Double {
        let points = armorPoints
        guard points > 0, amount < 1000, !godMode else { return amount }
        for i in armor.indices {
            guard var piece = armor[i], let info = items[piece.item], let spec = info.armor else { continue }
            piece.damage += 1
            if piece.damage >= spec.durability {
                armor[i] = nil
                onSound?("break_metal", 0.7, 1)
                onToast?("Your \(info.displayName) broke!")
            } else {
                armor[i] = piece
            }
        }
        return amount * (1 - min(0.8, Double(points) * 0.04))
    }

    // MARK: Beds

    private func useBed(at pos: BlockPos) {
        guard dimension == .overworld else { onToast?("Beds only work in the Overworld"); return }
        setSpawnPoint(DVec3(Double(pos.x) + 0.5, Double(pos.y) + 1, Double(pos.z) + 0.5))
        guard isNight || weather.kind == .thunder else {
            onToast?("Respawn point set. You can sleep at night or during thunderstorms")
            return
        }
        guard !isRemote else { onToast?("Respawn point set. Only the host can skip the night"); return }
        let danger = mobs.mobs.contains { $0.species.hostile && !$0.isDying && simd_distance($0.position, player.position) < 8 }
        guard !danger else { onToast?("You can't sleep now, there are monsters nearby"); return }
        advancements.record("sleep")
        Log.info("Player went to sleep at \(pos)", category: "Game")
        onSleep?()
    }

    /// Called by the sleep screen: skip to morning and clear any storm.
    func wakeUp() {
        if isNight {
            worldTime = (floor(worldTime / SkyModel.dayLength) + 1) * SkyModel.dayLength + 20
        }
        if weather.kind != .clear { weather.set(.clear) }
        health = min(20, health + 4)
        Log.info("Player woke up (\(SkyModel.periodName(worldTime: worldTime)), weather \(weather.kind.rawValue))", category: "Game")
    }

    private func damage(_ amount: Double, cause: String) {
        guard !isDead, !spectator, amount > 0, !(godMode && amount < 10_000) else { return }
        let scaled = meta.difficulty == .easy && amount < 1000 ? max(1, amount * 0.75) : amount
        health = max(0, health - scaled)
        damageFlash = 1
        onSound?("hurt", 0.8, 1)
        guard health <= 0 else { return }
        isDead = true
        deathMessage = cause
        advancements.record("die")
        breakingPos = nil
        breakProgress = 0
        onSound?("death", 0.8, 1)
        Log.info("Player died: \(cause)\(meta.isHardcore ? " (hardcore — world locked)" : "")", category: "Game")
        lastPosition = player.position
        // Everything carried spills onto the ground (unless /gamerule keepInventory is on).
        if !meta.rule("keepInventory") {
            let center = player.position + DVec3(0, 1, 0)
            for stack in inventory.slots.compactMap({ $0 }) + armor.compactMap({ $0 }) {
                let v = DVec3(Double.random(in: -3...3), Double.random(in: 2...5), Double.random(in: -3...3))
                if !(network?.dropItem(stack, at: center, velocity: v) ?? false) { entities.spawnItem(stack, at: center, velocity: v, pickupDelay: 2) }
            }
            inventory.clear()
            armor = Array(repeating: nil, count: 4)
        }
        if meta.isHardcore {
            meta.hardcoreDead = true
            save()
        }
    }

    func respawn() {
        guard !meta.isHardcore else { enterSpectator(); return }
        isDead = false
        health = 20; hunger = 20; saturation = 5; air = 10
        damageFlash = 0
        spawnProtection = 12
        if dimension != .overworld && !isRemote {
            changeDimension(to: .overworld, portal: nil, arrival: spawnPoint)
        } else {
            player.teleport(to: spawnPoint)
        }
    }

    /// Hardcore multiplayer: remembers that a joining player died (by `WireHost.deathKey`), so they can
    /// only spectate from now on. Returns true the first time.
    @discardableResult
    func recordHardcoreDeath(_ key: String) -> Bool {
        var dead = meta.hardcoreDeadPlayers ?? []
        guard meta.isHardcore, !dead.contains(key) else { return false }
        dead.append(key)
        meta.hardcoreDeadPlayers = dead
        save()
        return true
    }

    /// Hardcore: after death the world can only be watched.
    func enterSpectator() {
        isDead = false
        spectator = true
        health = 20; hunger = 20; air = 10
        damageFlash = 0
        player.gameMode = .creative
        player.setFlying(true)
        meta.hardcoreDead = true
        save()
    }

    func debugSetTime(_ t: Double) { worldTime = t }

    // MARK: Commands

    func setGameMode(_ mode: GameMode) {
        guard !spectator else { return }
        player.gameMode = mode
        meta.gameMode = mode
        if mode == .survival { player.setFlying(false) }
    }

    func setDifficulty(_ difficulty: Difficulty) { meta.difficulty = difficulty }

    /// /god: ignore all damage except /kill.
    var godMode = false
    /// Seconds of safety from creatures after joining a world or respawning.
    private(set) var spawnProtection = 12.0
    /// Where /back returns to (set before teleports and on death).
    var lastPosition: DVec3?
    var spawnLocation: DVec3 { spawnPoint }

    func setRule(_ name: String, _ value: Bool) { meta.setRule(name, value) }
    func setCommandsAllowed(_ on: Bool) {
        meta.allowCommands = on
        Log.info("Commands turned \(on ? "on" : "off") for '\(meta.name)'", category: "Game")
    }
    func setHome(_ p: DVec3) { meta.home = [p.x, p.y, p.z] }

    func restoreVitals() {
        health = 20
        hunger = 20
        saturation = 5
        air = 10
    }

    func setSpawnPoint(_ p: DVec3) {
        spawnPoint = p
        if dimension == .overworld {
            meta.spawnX = Int(floor(p.x)); meta.spawnY = Int(floor(p.y)); meta.spawnZ = Int(floor(p.z))
        }
    }

    private func environment(_ dt: Double) {
        environmentTimer -= dt
        guard environmentTimer <= 0 else { return }
        environmentTimer = 0.5
        let x = Int(floor(player.position.x)), z = Int(floor(player.position.z))
        biome = world.generator.biome(x: x, z: z)
        let eyeY = Int(floor(player.eyePosition.y))
        if dimension == .overworld, let top = world.topSolidY(x, z) {
            isUnderground = eyeY < top - 3 && eyeY < world.generator.seaLevel + 8
        } else {
            isUnderground = false
        }
    }

    // MARK: Persistence

    func makePlayerSave() -> PlayerSave {
        var stacks: [SavedStack] = []
        for (i, slot) in inventory.slots.enumerated() {
            guard let s = slot, let info = items[s.item] else { continue }
            stacks.append(SavedStack(slot: i, item: info.name, count: s.count, damage: s.damage > 0 ? s.damage : nil))
        }
        var save = PlayerSave(x: player.position.x, y: player.position.y, z: player.position.z, yaw: player.yaw, pitch: player.pitch,
                              health: isDead ? 20 : health, hunger: isDead ? 20 : hunger, saturation: saturation, air: air,
                              flying: player.flying, selectedSlot: inventory.selected, inventory: stacks,
                              dimension: dimension == .overworld ? nil : dimension.rawValue)
        let worn = armor.enumerated().compactMap { i, slot -> SavedStack? in
            guard let s = slot, let info = items[s.item] else { return nil }
            return SavedStack(slot: i, item: info.name, count: 1, damage: s.damage > 0 ? s.damage : nil)
        }
        save.armor = worn.isEmpty ? nil : worn
        return save
    }

    func save() {
        advancements.save(to: advancementsURL)
        guard !isRemote else { return }
        meta.lastPlayed = Date()
        meta.worldTime = worldTime
        meta.weather = weather.kind.rawValue
        meta.weatherTimer = weather.timer
        do {
            try storage.saveMetadata(meta)
            if !needsSpawnResolve {
                var snapshot = makePlayerSave()
                if isDead && !meta.isHardcore {
                    snapshot.x = spawnPoint.x; snapshot.y = spawnPoint.y; snapshot.z = spawnPoint.z
                    snapshot.dimension = nil
                }
                try storage.savePlayer(snapshot, id: meta.id)
            }
        } catch {
            Log.error("Failed to save world '\(meta.name)': \(error)", category: "Save")
            onToast?("Saving failed — see logs")
        }
        entities.save(to: entitiesURL, items: items)
        mobs.save(to: mobsURL)
        containers.save(to: containersURL, items: items)
        crops.save(to: cropsURL)
        let queued = world.saveModifiedChunks()
        Log.info("Saved '\(meta.name)' [\(dimension.rawValue)] (\(queued) chunks queued)", category: "Save")
    }

    func shutdown() {
        save()
        world.shutdown()
        Log.info("Session '\(meta.name)' closed", category: "Game")
    }
}
