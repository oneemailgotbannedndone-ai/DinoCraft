import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

enum MobKind: String, CaseIterable, Codable {
    case trikey, dodo, longneck, raptor, spitter, crawler, magmaRaptor, villager, stego, ankylo, rex, compy, ptero, parasaur, sailback, boneWalker, scorpion,
         pig, cow, sheep, chicken, pookpook, carnotaurus, allosaurus, baryonyx, troodon, spinosaurus,
         grumblesaurus, grinasaurus
}

/// Kinds of particle burst the game can ask for.
enum EffectBurst { case dust, confetti, ink, crumbs }

struct MobDrop {
    let item: String
    let min: Int
    let max: Int
    let chance: Double
}

/// Stats and behaviour of a creature type.
struct MobSpecies {
    let kind: MobKind
    let displayName: String
    let hostile: Bool
    let maxHealth: Double
    let width: Double
    let height: Double
    let walkSpeed: Double
    let runSpeed: Double
    let damage: Double
    let attackReach: Double
    let attackCooldown: Double
    let ranged: Bool
    let fireproof: Bool
    let detectRange: Double
    let drops: [MobDrop]
    let callPitch: Float
    let deepCall: Bool

    static let table: [MobKind: MobSpecies] = [
        .trikey: MobSpecies(kind: .trikey, displayName: "Trikey", hostile: false, maxHealth: 12, width: 0.9, height: 1.0,
                            walkSpeed: 1.3, runSpeed: 4.0, damage: 2.5, attackReach: 1.3, attackCooldown: 1.6, ranged: false, fireproof: false,
                            detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 1, max: 2, chance: 1), MobDrop(item: "dino_hide", min: 0, max: 2, chance: 1)],
                            callPitch: 1.3, deepCall: true),
        .dodo: MobSpecies(kind: .dodo, displayName: "Dodo", hostile: false, maxHealth: 6, width: 0.5, height: 0.9,
                          walkSpeed: 1.6, runSpeed: 4.6, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                          detectRange: 0, drops: [MobDrop(item: "feather", min: 0, max: 2, chance: 1), MobDrop(item: "raw_dino_meat", min: 1, max: 1, chance: 0.8)],
                          callPitch: 2.4, deepCall: false),
        .longneck: MobSpecies(kind: .longneck, displayName: "Longneck", hostile: false, maxHealth: 40, width: 1.6, height: 3.8,
                              walkSpeed: 1.1, runSpeed: 2.6, damage: 4, attackReach: 2.2, attackCooldown: 2.2, ranged: false, fireproof: false,
                              detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 2, max: 5, chance: 1), MobDrop(item: "dino_hide", min: 1, max: 3, chance: 1),
                                                      MobDrop(item: "dino_bone", min: 0, max: 2, chance: 1)],
                              callPitch: 0.7, deepCall: true),
        .raptor: MobSpecies(kind: .raptor, displayName: "Raptor", hostile: true, maxHealth: 16, width: 0.6, height: 1.2,
                            walkSpeed: 1.8, runSpeed: 5.4, damage: 3, attackReach: 1.2, attackCooldown: 1.0, ranged: false, fireproof: false,
                            detectRange: 24, drops: [MobDrop(item: "raptor_claw", min: 0, max: 1, chance: 0.6), MobDrop(item: "raw_dino_meat", min: 0, max: 1, chance: 0.8)],
                            callPitch: 1.6, deepCall: false),
        .spitter: MobSpecies(kind: .spitter, displayName: "Spitter", hostile: true, maxHealth: 18, width: 0.7, height: 1.5,
                             walkSpeed: 1.5, runSpeed: 3.2, damage: 2.5, attackReach: 16, attackCooldown: 2.2, ranged: true, fireproof: false,
                             detectRange: 20, drops: [MobDrop(item: "dino_hide", min: 0, max: 1, chance: 1), MobDrop(item: "dino_bone", min: 0, max: 2, chance: 1)],
                             callPitch: 1.1, deepCall: false),
        .crawler: MobSpecies(kind: .crawler, displayName: "Cave Crawler", hostile: true, maxHealth: 12, width: 0.9, height: 0.5,
                             walkSpeed: 1.4, runSpeed: 3.6, damage: 2, attackReach: 1.0, attackCooldown: 0.8, ranged: false, fireproof: false,
                             detectRange: 14, drops: [MobDrop(item: "dino_hide", min: 0, max: 1, chance: 1), MobDrop(item: "amber", min: 0, max: 1, chance: 0.3)],
                             callPitch: 2.8, deepCall: false),
        .magmaRaptor: MobSpecies(kind: .magmaRaptor, displayName: "Magma Raptor", hostile: true, maxHealth: 24, width: 0.7, height: 1.3,
                                 walkSpeed: 2.0, runSpeed: 6.0, damage: 5, attackReach: 1.3, attackCooldown: 1.0, ranged: false, fireproof: true,
                                 detectRange: 28, drops: [MobDrop(item: "ember_shard", min: 1, max: 3, chance: 1), MobDrop(item: "raptor_claw", min: 0, max: 1, chance: 0.5)],
                                 callPitch: 1.0, deepCall: false),
        .villager: MobSpecies(kind: .villager, displayName: "Villager", hostile: false, maxHealth: 20, width: 0.6, height: 1.95,
                              walkSpeed: 1.1, runSpeed: 3.2, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                              detectRange: 0, drops: [], callPitch: 1.25, deepCall: false),
        .stego: MobSpecies(kind: .stego, displayName: "Stegosaurus", hostile: false, maxHealth: 30, width: 1.2, height: 2.0,
                           walkSpeed: 1.0, runSpeed: 2.8, damage: 3, attackReach: 1.6, attackCooldown: 1.7, ranged: false, fireproof: false,
                           detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 2, max: 4, chance: 1), MobDrop(item: "dino_hide", min: 1, max: 2, chance: 1),
                                                   MobDrop(item: "dino_bone", min: 0, max: 2, chance: 1)],
                           callPitch: 0.8, deepCall: true),
        .ankylo: MobSpecies(kind: .ankylo, displayName: "Ankylosaurus", hostile: false, maxHealth: 36, width: 1.4, height: 1.25,
                            walkSpeed: 0.9, runSpeed: 2.2, damage: 3.5, attackReach: 1.6, attackCooldown: 1.8, ranged: false, fireproof: false,
                            detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 1, max: 3, chance: 1), MobDrop(item: "dino_hide", min: 2, max: 3, chance: 1)],
                            callPitch: 0.6, deepCall: true),
        .rex: MobSpecies(kind: .rex, displayName: "T-Rex", hostile: true, maxHealth: 60, width: 1.2, height: 3.2,
                         walkSpeed: 2.0, runSpeed: 5.4, damage: 8, attackReach: 1.8, attackCooldown: 1.4, ranged: false, fireproof: false,
                         detectRange: 32, drops: [MobDrop(item: "raw_dino_meat", min: 4, max: 8, chance: 1), MobDrop(item: "dino_bone", min: 2, max: 4, chance: 1),
                                                  MobDrop(item: "raptor_claw", min: 1, max: 2, chance: 1), MobDrop(item: "emerald", min: 0, max: 2, chance: 0.5)],
                         callPitch: 0.45, deepCall: true),
        .compy: MobSpecies(kind: .compy, displayName: "Compy", hostile: true, maxHealth: 6, width: 0.4, height: 0.65,
                           walkSpeed: 2.2, runSpeed: 6.2, damage: 1.5, attackReach: 0.8, attackCooldown: 0.7, ranged: false, fireproof: false,
                           detectRange: 18, drops: [MobDrop(item: "feather", min: 0, max: 1, chance: 1), MobDrop(item: "raw_dino_meat", min: 0, max: 1, chance: 0.5)],
                           callPitch: 3.0, deepCall: false),
        .ptero: MobSpecies(kind: .ptero, displayName: "Pteranodon", hostile: true, maxHealth: 10, width: 0.9, height: 0.7,
                           walkSpeed: 3.0, runSpeed: 7.0, damage: 3, attackReach: 1.2, attackCooldown: 1.8, ranged: false, fireproof: false,
                           detectRange: 26, drops: [MobDrop(item: "feather", min: 1, max: 3, chance: 1), MobDrop(item: "raw_dino_meat", min: 0, max: 1, chance: 0.6)],
                           callPitch: 2.0, deepCall: false),
        .parasaur: MobSpecies(kind: .parasaur, displayName: "Parasaurolophus", hostile: false, maxHealth: 24, width: 1.0, height: 2.3,
                              walkSpeed: 1.2, runSpeed: 3.8, damage: 2, attackReach: 1.3, attackCooldown: 1.5, ranged: false, fireproof: false,
                              detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 1, max: 3, chance: 1), MobDrop(item: "dino_hide", min: 0, max: 2, chance: 1)],
                              callPitch: 0.9, deepCall: true),
        .sailback: MobSpecies(kind: .sailback, displayName: "Dimetrodon", hostile: false, maxHealth: 18, width: 0.8, height: 1.4,
                              walkSpeed: 1.0, runSpeed: 3.0, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                              detectRange: 0, drops: [MobDrop(item: "raw_dino_meat", min: 1, max: 2, chance: 1), MobDrop(item: "dino_hide", min: 1, max: 1, chance: 1)],
                              callPitch: 1.1, deepCall: true),
        .boneWalker: MobSpecies(kind: .boneWalker, displayName: "Bone Walker", hostile: true, maxHealth: 20, width: 0.6, height: 1.4,
                                walkSpeed: 1.4, runSpeed: 3.8, damage: 3.0, attackReach: 1.1, attackCooldown: 1.2, ranged: false, fireproof: false,
                                detectRange: 20, drops: [MobDrop(item: "dino_bone", min: 1, max: 3, chance: 1), MobDrop(item: "flint", min: 0, max: 1, chance: 0.4),
                                                         MobDrop(item: "emerald", min: 0, max: 1, chance: 0.1)],
                                callPitch: 0.7, deepCall: false),
        .scorpion: MobSpecies(kind: .scorpion, displayName: "Sand Scorpion", hostile: true, maxHealth: 12, width: 0.9, height: 0.55,
                              walkSpeed: 1.6, runSpeed: 4.8, damage: 2.5, attackReach: 0.9, attackCooldown: 0.9, ranged: false, fireproof: false,
                              detectRange: 16, drops: [MobDrop(item: "raptor_claw", min: 0, max: 1, chance: 0.3), MobDrop(item: "dino_hide", min: 0, max: 1, chance: 1)],
                              callPitch: 2.2, deepCall: false),
        .pig: MobSpecies(kind: .pig, displayName: "Pig", hostile: false, maxHealth: 10, width: 0.8, height: 0.9,
                   walkSpeed: 1.2, runSpeed: 3.6, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                   detectRange: 0, drops: [MobDrop(item: "raw_pork", min: 1, max: 3, chance: 1)],
                   callPitch: 1.0, deepCall: false),
        .cow: MobSpecies(kind: .cow, displayName: "Cow", hostile: false, maxHealth: 10, width: 0.9, height: 1.4,
                   walkSpeed: 1.0, runSpeed: 3.2, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                   detectRange: 0, drops: [MobDrop(item: "raw_beef", min: 1, max: 3, chance: 1), MobDrop(item: "dino_hide", min: 0, max: 2, chance: 1)],
                   callPitch: 1.0, deepCall: true),
        .sheep: MobSpecies(kind: .sheep, displayName: "Sheep", hostile: false, maxHealth: 8, width: 0.8, height: 1.2,
                   walkSpeed: 1.1, runSpeed: 3.4, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                   detectRange: 0, drops: [MobDrop(item: "raw_mutton", min: 1, max: 2, chance: 1)],
                   callPitch: 1.0, deepCall: false),
        .chicken: MobSpecies(kind: .chicken, displayName: "Chicken", hostile: false, maxHealth: 4, width: 0.4, height: 0.7,
                   walkSpeed: 1.2, runSpeed: 3.4, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: false,
                   detectRange: 0, drops: [MobDrop(item: "feather", min: 0, max: 2, chance: 1), MobDrop(item: "raw_poultry", min: 1, max: 1, chance: 1)],
                   callPitch: 1.0, deepCall: false),
        .pookpook: MobSpecies(kind: .pookpook, displayName: "Pookpook", hostile: false, maxHealth: 8, width: 0.7, height: 1.2,
                   walkSpeed: 1.3, runSpeed: 3.6, damage: 2, attackReach: 1.0, attackCooldown: 1.0, ranged: false, fireproof: false,
                   detectRange: 0, drops: [MobDrop(item: "feather", min: 1, max: 3, chance: 1), MobDrop(item: "raw_poultry", min: 1, max: 1, chance: 0.8)],
                   callPitch: 1.0, deepCall: false),
        .carnotaurus: MobSpecies(kind: .carnotaurus, displayName: "Carnotaurus", hostile: true, maxHealth: 34, width: 1.0, height: 2.4,
                   walkSpeed: 2.0, runSpeed: 6.2, damage: 6, attackReach: 1.5, attackCooldown: 1.3, ranged: false, fireproof: false,
                   detectRange: 28, drops: [MobDrop(item: "raw_dino_meat", min: 2, max: 4, chance: 1), MobDrop(item: "dino_hide", min: 1, max: 2, chance: 1), MobDrop(item: "raptor_claw", min: 0, max: 1, chance: 0.5)],
                   callPitch: 0.7, deepCall: true),
        .allosaurus: MobSpecies(kind: .allosaurus, displayName: "Allosaurus", hostile: true, maxHealth: 44, width: 1.1, height: 2.8,
                   walkSpeed: 1.8, runSpeed: 5.2, damage: 7, attackReach: 1.7, attackCooldown: 1.4, ranged: false, fireproof: false,
                   detectRange: 28, drops: [MobDrop(item: "raw_dino_meat", min: 3, max: 5, chance: 1), MobDrop(item: "dino_bone", min: 1, max: 3, chance: 1)],
                   callPitch: 0.55, deepCall: true),
        .baryonyx: MobSpecies(kind: .baryonyx, displayName: "Baryonyx", hostile: true, maxHealth: 30, width: 1.0, height: 2.2,
                   walkSpeed: 1.6, runSpeed: 4.6, damage: 5, attackReach: 1.5, attackCooldown: 1.2, ranged: false, fireproof: false,
                   detectRange: 22, drops: [MobDrop(item: "raw_dino_meat", min: 2, max: 4, chance: 1), MobDrop(item: "raptor_claw", min: 1, max: 2, chance: 1)],
                   callPitch: 0.8, deepCall: true),
        .troodon: MobSpecies(kind: .troodon, displayName: "Troodon", hostile: true, maxHealth: 8, width: 0.5, height: 1.0,
                   walkSpeed: 2.0, runSpeed: 6.0, damage: 2, attackReach: 0.9, attackCooldown: 0.8, ranged: false, fireproof: false,
                   detectRange: 22, drops: [MobDrop(item: "feather", min: 0, max: 2, chance: 1), MobDrop(item: "raw_dino_meat", min: 0, max: 1, chance: 0.6)],
                   callPitch: 2.2, deepCall: false),
        .spinosaurus: MobSpecies(kind: .spinosaurus, displayName: "Spinosaurus", hostile: true, maxHealth: 80, width: 1.4, height: 3.6,
                   walkSpeed: 1.8, runSpeed: 5.0, damage: 9, attackReach: 2.0, attackCooldown: 1.6, ranged: false, fireproof: false,
                   detectRange: 30, drops: [MobDrop(item: "raw_dino_meat", min: 5, max: 9, chance: 1), MobDrop(item: "dino_bone", min: 3, max: 5, chance: 1), MobDrop(item: "emerald", min: 1, max: 3, chance: 0.6)],
                   callPitch: 0.4, deepCall: true),
        .grumblesaurus: MobSpecies(kind: .grumblesaurus, displayName: "King Grumblesaurus", hostile: true, maxHealth: 320, width: 2.2, height: 4.4,
                   walkSpeed: 2.2, runSpeed: 5.0, damage: 7, attackReach: 2.4, attackCooldown: 1.6, ranged: false, fireproof: true,
                   detectRange: 48, drops: [MobDrop(item: "smile_trophy", min: 1, max: 1, chance: 1), MobDrop(item: "diamond", min: 3, max: 6, chance: 1),
                                            MobDrop(item: "emerald", min: 4, max: 8, chance: 1), MobDrop(item: "checker_block", min: 8, max: 16, chance: 1)],
                   callPitch: 0.35, deepCall: true),
        .grinasaurus: MobSpecies(kind: .grinasaurus, displayName: "Happy Grumblesaurus", hostile: false, maxHealth: 320, width: 2.2, height: 4.4,
                   walkSpeed: 1.2, runSpeed: 2.0, damage: 0, attackReach: 0, attackCooldown: 0, ranged: false, fireproof: true,
                   detectRange: 0, drops: [], callPitch: 0.6, deepCall: true),
    ]

    static func of(_ kind: MobKind) -> MobSpecies { table[kind]! }

    var flying: Bool { kind == .ptero }

    /// Neutral creatures leave you alone until you hit them, then fight back.
    var neutral: Bool { [.trikey, .longneck, .stego, .ankylo, .parasaur, .pookpook].contains(kind) }

    var callSound: String {
        switch kind {
        case .pookpook: return "pookpook"
        case .cow: return "animal_moo"
        case .pig: return "animal_oink"
        case .sheep: return "animal_baa"
        case .chicken: return "animal_cluck"
        default: return deepCall ? "amb_dino_low" : "amb_dino_high"
        }
    }
}

final class Mob {
    private static var nextID = 1

    let id: Int
    let species: MobSpecies
    var position: DVec3
    var velocity = DVec3.zero
    var yaw: Double = 0
    var health: Double
    var onGround = false
    var inLiquid = false
    var hurtTimer = 0.0
    var attackTimer = 0.0
    var fleeTimer = 0.0
    var aggroTimer = 0.0
    var wanderTarget: DVec3?
    var wanderTimer = 0.0
    var idleTimer = Double.random(in: 1...4)
    var walkPhase = 0.0
    var moveAmount = 0.0
    var deathTimer = -1.0
    var lunge = 0.0
    var callTimer = Double.random(in: 8...30)
    var removed = false
    var remoteID: Int?
    var netTarget: DVec3?
    /// Villager profession (index into `VillagerProfession.all`).
    var variant = 0
    /// Villagers stay near their village plaza.
    var home: DVec3?
    /// Boss attack timers.
    var volleyTimer = 3.0
    var stompTimer = 7.0
    var airborne = false
    var enraged = false

    init(species: MobSpecies, position: DVec3) {
        id = Mob.nextID
        Mob.nextID += 1
        self.species = species
        self.position = position
        health = species.maxHealth
    }

    var isDying: Bool { deathTimer >= 0 }

    var box: DBox {
        let hw = species.width / 2
        return DBox(min: DVec3(position.x - hw, position.y, position.z - hw),
                    max: DVec3(position.x + hw, position.y + species.height, position.z + hw))
    }
}

final class Projectile {
    var position: DVec3
    var velocity: DVec3
    var age = 0.0
    var removed = false
    let damage: Double
    var cause = "Spat on by a Spitter"
    var attacker = "Spitter"

    init(position: DVec3, velocity: DVec3, damage: Double) {
        self.position = position
        self.velocity = velocity
        self.damage = damage
    }
}

private struct SavedMob: Codable {
    var kind: String
    var x: Double, y: Double, z: Double
    var health: Double
    var yaw: Double
    var variant: Int?
    var hx: Double?, hy: Double?, hz: Double?
}

/// Creatures: spawning rules per dimension, biome, light and time of day;
/// wandering, fleeing, chasing and ranged AI; physics; combat; drops; saving.
final class MobManager {
    private(set) var mobs: [Mob] = []
    private(set) var projectiles: [Projectile] = []
    private var spawnTimer = 2.0
    private var villagerTimer = 3.0
    private var guardTimer = 5.0
    private var stageTimer = 1.0
    fileprivate var peacefulHintShown = false
    private var eventTimer = Double.random(in: 240...480)
    private var scratch: [DBox] = []

    func clear() {
        mobs.removeAll()
        projectiles.removeAll()
    }

    @discardableResult
    func spawn(_ kind: MobKind, at p: DVec3) -> Mob {
        let m = Mob(species: .of(kind), position: p)
        m.yaw = Double.random(in: 0..<(2 * .pi))
        if kind == .villager { m.variant = Int.random(in: 0..<VillagerProfession.all.count) }
        if kind == .sheep { m.variant = Int.random(in: 0..<10) == 0 ? 1 : 0 }
        mobs.append(m)
        return m
    }

    // MARK: Update

    func update(dt: Double, session s: GameSession) {
        let world = s.world
        spawnTimer -= dt
        if spawnTimer <= 0 {
            spawnTimer = 1
            trySpawn(s)
        }
        villagerTimer -= dt
        if villagerTimer <= 0 {
            villagerTimer = 4
            spawnVillagers(s)
        }
        guardTimer -= dt
        if guardTimer <= 0 {
            guardTimer = 15
            spawnDungeonGuards(s)
        }
        stageTimer -= dt
        if stageTimer <= 0 {
            stageTimer = 2
            spawnStageGuests(s)
        }
        eventTimer -= dt
        if eventTimer <= 0 {
            eventTimer = Double.random(in: 300...600)
            startStampede(s)
        }
        let player = s.player
        let targets = s.hostileTargets()
        for m in mobs where !m.removed {
            let bx = Int(floor(m.position.x)), bz = Int(floor(m.position.z))
            guard world.isLoaded(bx, bz) else { continue }
            var chosen: (id: Int, pos: DVec3)?
            var best = Double.infinity
            for t in targets {
                let d = simd_distance(t.pos, m.position)
                if d < best { best = d; chosen = t }
            }
            let toPlayer = (chosen?.pos ?? player.position) - m.position
            let distance = simd_length(toPlayer)
            if m.species.hostile && simd_distance(player.position, m.position) > 96 && best > 96 { m.removed = true; continue }

            m.hurtTimer = max(0, m.hurtTimer - dt)
            m.attackTimer = max(0, m.attackTimer - dt)
            m.fleeTimer = max(0, m.fleeTimer - dt)
            m.aggroTimer = max(0, m.aggroTimer - dt)
            m.lunge = max(0, m.lunge - dt * 4)

            if m.isDying {
                m.deathTimer += dt
                if m.deathTimer > 0.8 { finishDeath(m, s) }
                physics(m, desired: .zero, speed: 0, dt: dt, session: s)
                continue
            }
            if m.species.kind == .grumblesaurus {
                updateBoss(m, target: chosen, dt: dt, session: s)
                continue
            }

            var desired = DVec3.zero
            var speed = 0.0
            var facePlayer = false
            let flat = DVec3(toPlayer.x, 0, toPlayer.z)
            let flatDistance = simd_length(flat)
            let dir = flatDistance > 0.01 ? flat / flatDistance : DVec3(0, 0, 1)

            if m.species.hostile || (m.species.neutral && m.aggroTimer > 0), let target = chosen,
               (distance < m.species.detectRange || m.aggroTimer > 0) && distance < 48 {
                facePlayer = true
                if m.species.flying {
                    // Swoop at the target, then climb away until the attack cools down.
                    let climbing = m.attackTimer > m.species.attackCooldown * 0.35
                    let aim = target.pos + DVec3(0, climbing ? 7 : 1.0, 0)
                    let toAim = aim - m.position
                    let length = simd_length(toAim)
                    desired = length > 0.01 ? toAim / length : .zero
                    speed = climbing ? m.species.walkSpeed * 1.4 : chaseSpeed(m, s)
                    if m.attackTimer <= 0 && simd_distance(target.pos + DVec3(0, 0.9, 0), m.position) < m.species.attackReach + 0.9 {
                        m.attackTimer = m.species.attackCooldown * 1.4
                        m.lunge = 1
                        s.damageTarget(id: target.id, amount: m.species.damage, cause: "Snatched by a \(m.species.displayName)",
                                       attacker: m.species.displayName, knockback: dir)
                        s.onSound?("amb_dino_high", audible(distance) * 0.6, m.species.callPitch)
                    }
                } else if m.species.ranged {
                    if flatDistance > 8 { desired = dir; speed = chaseSpeed(m, s) }
                    else if flatDistance < 4.5 { desired = -dir; speed = m.species.walkSpeed }
                    if m.attackTimer <= 0 && flatDistance < m.species.attackReach {
                        shoot(m, at: target.pos + DVec3(0, 1.1, 0))
                        m.attackTimer = m.species.attackCooldown * 1.4
                        m.lunge = 1
                        s.onSound?("amb_dino_high", audible(distance) * 0.5, 1.8)
                    }
                } else {
                    if flatDistance > 0.4 { desired = dir; speed = chaseSpeed(m, s) }
                    let reach = m.species.attackReach + m.species.width / 2 + 0.3
                    if flatDistance < reach && abs(toPlayer.y) < 1.8 && m.attackTimer <= 0 {
                        m.attackTimer = m.species.attackCooldown * 1.4
                        m.lunge = 1
                        s.damageTarget(id: target.id, amount: m.species.damage, cause: "Mauled by a \(m.species.displayName)",
                                       attacker: m.species.displayName, knockback: dir)
                    }
                }
            } else if m.fleeTimer > 0 && distance < 24 {
                desired = -dir
                speed = m.species.runSpeed
            } else {
                wander(m, dt: dt, desired: &desired, speed: &speed)
            }

            physics(m, desired: desired, speed: speed, dt: dt, session: s)
            if facePlayer { m.yaw = MobManager.lerpAngle(m.yaw, atan2(-dir.x, -dir.z), 1 - exp(-10 * dt)) }

            m.callTimer -= dt
            if m.callTimer <= 0 {
                m.callTimer = Double.random(in: 14...40)
                let volume = audible(distance) * (m.species.hostile ? 0.45 : 0.3)
                if volume > 0.01 { s.onSound?(m.species.callSound, volume, m.species.callPitch) }
            }
        }
        updateProjectiles(dt, s)
        mobs.removeAll { $0.removed }
    }

    private func audible(_ distance: Double) -> Float { Float(max(0, 1 - distance / 32)) }

    /// Chasing creatures stay slower than a sprinting player, and on Easy and Normal slower than a walking one.
    private func chaseSpeed(_ m: Mob, _ s: GameSession) -> Double {
        let factor: Double, limit: Double
        switch s.meta.difficulty {
        case .peaceful, .easy: factor = 0.6; limit = 3.6
        case .normal: factor = 0.72; limit = 4.1
        case .hard: factor = 0.85; limit = 5.0
        }
        return min(m.species.runSpeed * factor, m.species.flying ? limit + 1.2 : limit)
    }

    static func lerpAngle(_ a: Double, _ b: Double, _ t: Double) -> Double {
        var diff = (b - a).truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        return a + diff * t
    }

    private func wander(_ m: Mob, dt: Double, desired: inout DVec3, speed: inout Double) {
        if let target = m.wanderTarget {
            m.wanderTimer -= dt
            let d = DVec3(target.x - m.position.x, 0, target.z - m.position.z)
            let l = simd_length(d)
            if l < 0.6 || m.wanderTimer <= 0 {
                m.wanderTarget = nil
                m.idleTimer = Double.random(in: 2...7)
            } else {
                desired = d / l
                speed = m.species.walkSpeed
            }
        } else {
            m.idleTimer -= dt
            if m.idleTimer <= 0 {
                let a = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 3...10)
                if let home = m.home, simd_distance(DVec3(home.x, m.position.y, home.z), m.position) > 14 {
                    m.wanderTarget = DVec3(home.x + cos(a) * 4, m.position.y, home.z + sin(a) * 4)
                } else {
                    m.wanderTarget = m.position + DVec3(cos(a) * r, 0, sin(a) * r)
                }
                m.wanderTimer = 8
            }
        }
    }

    private func physics(_ m: Mob, desired input: DVec3, speed: Double, dt: Double, session s: GameSession) {
        let world = s.world
        let reg = world.registry
        if m.species.flying {
            flyPhysics(m, desired: input, speed: speed, dt: dt, world: world)
            return
        }
        var desired = input
        // Friendly creatures won't walk off cliffs or into water.
        if !m.species.hostile && simd_length(desired) > 0 && m.onGround && !m.inLiquid {
            let probe = m.position + desired * (m.species.width / 2 + 0.6)
            let px = Int(floor(probe.x)), pz = Int(floor(probe.z)), py = Int(floor(m.position.y))
            let wet = reg.shape[Int(world.block(px, py, pz))] == .liquid || reg.shape[Int(world.block(px, py - 1, pz))] == .liquid
            if wet || !(1...3).contains(where: { reg.isSolid[Int(world.block(px, py - $0, pz))] }) {
                desired = .zero
                m.wanderTarget = nil
            }
        }
        let cx = Int(floor(m.position.x)), cz = Int(floor(m.position.z))
        let middle = world.block(cx, Int(floor(m.position.y + m.species.height * 0.4)), cz)
        m.inLiquid = reg.shape[Int(middle)] == .liquid
        if !m.species.fireproof && (middle == Blocks.lava || world.block(cx, Int(floor(m.position.y + 0.1)), cz) == Blocks.lava) {
            m.health -= 6 * dt
            m.hurtTimer = 0.2
            if m.health <= 0 && !m.isDying { m.deathTimer = 0 }
        }

        let accel = m.onGround ? 10.0 : (m.inLiquid ? 4.0 : 2.0)
        let target = desired * speed * (m.inLiquid ? 0.6 : 1)
        let k = 1 - exp(-accel * dt)
        m.velocity.x += (target.x - m.velocity.x) * k
        m.velocity.z += (target.z - m.velocity.z) * k
        if m.inLiquid {
            // Swim low in the water: rise while the upper body is under, sink gently once it's out.
            let upper = world.block(cx, Int(floor(m.position.y + m.species.height * 0.8)), cz)
            let deep = reg.shape[Int(upper)] == .liquid
            m.velocity.y += ((deep ? 1.4 : -0.5) - m.velocity.y) * min(1, dt * 2.5)
        } else {
            m.velocity.y = max(-40, m.velocity.y - 26 * dt)
        }
        let blocked = move(m, m.velocity * dt, world)
        if blocked && m.onGround && simd_length(desired) > 0 { m.velocity.y = 7.8 }

        let horizontal = DVec3(m.velocity.x, 0, m.velocity.z)
        let hs = simd_length(horizontal)
        if hs > 0.3 && !m.isDying {
            m.yaw = MobManager.lerpAngle(m.yaw, atan2(-horizontal.x, -horizontal.z), 1 - exp(-8 * dt))
        }
        m.moveAmount += (min(1, hs / max(0.5, m.species.walkSpeed)) - m.moveAmount) * (1 - exp(-8 * dt))
        m.walkPhase += hs * dt * (3.2 / max(0.5, m.species.height))
        if m.position.y < -32 { m.removed = true }
    }

    /// Returns true if horizontal movement was blocked.
    private func move(_ m: Mob, _ d: DVec3, _ world: World) -> Bool {
        var box = m.box
        var dx = d.x, dy = d.y, dz = d.z
        let sweep = box.expanded(d)
        VoxelPhysics.colliders(world, in: DBox(min: sweep.min - 0.01, max: sweep.max + 0.01), into: &scratch)
        for c in scratch { dy = VoxelPhysics.clipY(c, box, dy) }
        box = box.offset(DVec3(0, dy, 0))
        for c in scratch { dx = VoxelPhysics.clipX(c, box, dx) }
        box = box.offset(DVec3(dx, 0, 0))
        for c in scratch { dz = VoxelPhysics.clipZ(c, box, dz) }
        box = box.offset(DVec3(0, 0, dz))
        m.onGround = d.y < 0 && dy != d.y
        if dy != d.y { m.velocity.y = 0 }
        if dx != d.x { m.velocity.x = 0 }
        if dz != d.z { m.velocity.z = 0 }
        m.position = DVec3((box.min.x + box.max.x) / 2, box.min.y, (box.min.z + box.max.z) / 2)
        return dx != d.x || dz != d.z
    }

    // MARK: Villages

    /// Keeps each nearby village populated with up to five villagers.
    private func spawnVillagers(_ s: GameSession) {
        guard s.dimension == .overworld, let generator = s.world.generator as? TerrainGenerator else { return }
        let p = s.player.position
        for v in generator.villages(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: 100) {
            let center = DVec3(Double(v.x) + 0.5, Double(v.y), Double(v.z) + 0.5)
            let residents = mobs.filter { $0.species.kind == .villager && simd_distance($0.home ?? $0.position, center) < 48 }.count
            guard residents < 5 else { continue }
            let a = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 4...12)
            let x = Int(floor(center.x + cos(a) * r)), z = Int(floor(center.z + sin(a) * r))
            guard s.world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4)))?.mesh != nil,
                  let y = s.world.findStandingY(x, z, near: v.y), abs(y - v.y) < 8 else { continue }
            let m = spawn(.villager, at: DVec3(Double(x) + 0.5, Double(y), Double(z) + 0.5))
            m.home = center
            Log.info("A \(VillagerProfession.of(m).name) moved into the village at \(v.x), \(v.z)", category: "Game")
        }
    }

    /// Gliding flight: cruise about nine blocks above the ground, circle when idle, fall when dying.
    private func flyPhysics(_ m: Mob, desired input: DVec3, speed: Double, dt: Double, world: World) {
        var desired = input
        if m.isDying {
            desired = DVec3(0, -1, 0)
        } else if abs(desired.y) < 0.001 {
            let x = Int(floor(m.position.x)), z = Int(floor(m.position.z))
            let top = Int(floor(m.position.y))
            var ground = top
            while ground > 1 && top - ground < 32 && !world.registry.isSolid[Int(world.block(x, ground - 1, z))] { ground -= 1 }
            desired.y = max(-0.6, min(0.6, (Double(ground) + 9 - m.position.y) * 0.25))
            if simd_length(DVec3(desired.x, 0, desired.z)) < 0.01 {
                desired.x = -sin(m.yaw + 0.5)
                desired.z = -cos(m.yaw + 0.5)
            }
        }
        let cruise = m.isDying ? 6 : max(speed, m.species.walkSpeed * 0.7)
        let k = 1 - exp(-3 * dt)
        m.velocity += (desired * cruise - m.velocity) * k
        _ = move(m, m.velocity * dt, world)
        let horizontal = DVec3(m.velocity.x, 0, m.velocity.z)
        if simd_length(horizontal) > 0.3 && !m.isDying {
            m.yaw = MobManager.lerpAngle(m.yaw, atan2(-horizontal.x, -horizontal.z), 1 - exp(-4 * dt))
        }
        m.moveAmount = 1
        m.walkPhase += dt * 6
        if m.position.y < -32 { m.removed = true }
    }

    /// Dungeons keep a few Bone Walkers (and the odd Cave Crawler) on guard.
    private func spawnDungeonGuards(_ s: GameSession) {
        guard s.dimension == .overworld, s.meta.difficulty != .peaceful, let generator = s.world.generator as? TerrainGenerator else { return }
        let p = s.player.position
        for d in generator.structures(near: Int(floor(p.x)), z: Int(floor(p.z)), radius: 28) where d.kind == .dungeon {
            let center = DVec3(Double(d.x) + 0.5, Double(d.y), Double(d.z) + 0.5)
            guard simd_distance(center, p) < 28 else { continue }
            let guards = mobs.filter { $0.species.hostile && simd_distance($0.position, center) < 10 }.count
            guard guards < 3 else { continue }
            let x = d.x + Int.random(in: -2...2), z = d.z + Int.random(in: -2...2)
            guard s.world.isLoaded(x, z), s.world.block(x, d.y, z) == Blocks.air, s.world.block(x, d.y + 1, z) == Blocks.air else { continue }
            spawn(Double.random(in: 0..<1) < 0.7 ? .boneWalker : .crawler, at: DVec3(Double(x) + 0.5, Double(d.y), Double(z) + 0.5))
        }
    }

    // MARK: Multiplayer

    func snapshot() -> MobSnapshotMessage {
        MobSnapshotMessage(mobs: mobs.filter { !$0.removed }.map {
            MobState(id: $0.id, kind: $0.species.kind.rawValue, x: $0.position.x, y: $0.position.y, z: $0.position.z, yaw: Float($0.yaw),
                     health: Float($0.health), maxHealth: Float($0.species.maxHealth), walk: Float($0.walkPhase), move: Float($0.moveAmount),
                     hurt: Float($0.hurtTimer), dying: Float($0.deathTimer), lunge: Float($0.lunge), variant: $0.variant)
        }, spits: projectiles.map { [$0.position.x, $0.position.y, $0.position.z] })
    }

    func mirror(_ message: MobSnapshotMessage) {
        var existing: [Int: Mob] = [:]
        for m in mobs { if let r = m.remoteID { existing[r] = m } }
        var next: [Mob] = []
        for st in message.mobs {
            guard let kind = MobKind(rawValue: st.kind) else { continue }
            let m: Mob
            if let found = existing[st.id] {
                m = found
            } else {
                m = Mob(species: .of(kind), position: DVec3(st.x, st.y, st.z))
                m.remoteID = st.id
            }
            m.netTarget = DVec3(st.x, st.y, st.z)
            m.yaw = Double(st.yaw)
            m.health = Double(st.health)
            m.walkPhase = Double(st.walk)
            m.moveAmount = Double(st.move)
            m.hurtTimer = max(m.hurtTimer, Double(st.hurt))
            m.deathTimer = Double(st.dying)
            m.lunge = Double(st.lunge)
            m.variant = st.variant ?? 0
            next.append(m)
        }
        mobs = next
        projectiles = message.spits.compactMap { $0.count == 3 ? Projectile(position: DVec3($0[0], $0[1], $0[2]), velocity: .zero, damage: 0) : nil }
    }

    func updateMirrors(dt: Double) {
        for m in mobs {
            if let t = m.netTarget { m.position += (t - m.position) * min(1, dt * 12) }
            m.hurtTimer = max(0, m.hurtTimer - dt)
        }
    }

    // MARK: Combat

    func hurt(_ m: Mob, amount: Double, knockback: DVec3, session s: GameSession) {
        guard !m.isDying else { return }
        m.health -= amount
        m.hurtTimer = 0.35
        let strength = m.species.width > 1.2 ? 2.0 : 6.5
        m.velocity += DVec3(knockback.x * strength, 3.5, knockback.z * strength)
        if m.species.hostile || m.species.neutral { m.aggroTimer = m.species.hostile ? 20 : 10 } else { m.fleeTimer = 6; m.wanderTarget = nil }
        s.onSound?("hurt", 0.6, m.species.callPitch)
        Log.info("Hit \(m.species.displayName) for \(String(format: "%.1f", amount)) (\(String(format: "%.1f", max(0, m.health))) hp left)", category: "Game")
        if m.health <= 0 {
            m.deathTimer = 0
            s.onSound?(m.species.deepCall ? "amb_dino_low" : "amb_dino_high", 0.5, m.species.callPitch * 1.3)
        }
    }

    private func finishDeath(_ m: Mob, _ s: GameSession) {
        m.removed = true
        if m.species.kind == .grumblesaurus { bossCheeredUp(m, s) }
        let center = m.position + DVec3(0, m.species.height * 0.5, 0)
        for drop in m.species.drops {
            guard Double.random(in: 0..<1) < drop.chance, let item = s.items.id(named: drop.item) else { continue }
            let count = Int.random(in: drop.min...max(drop.min, drop.max))
            guard count > 0 else { continue }
            s.entities.spawnItem(ItemStack(item: item, count: count), at: center,
                                 velocity: DVec3(Double.random(in: -2...2), Double.random(in: 2.5...4.5), Double.random(in: -2...2)), pickupDelay: 0.5)
        }
        if m.species.kind == .sheep, let wool = s.items.id(named: m.variant == 1 ? "wool_black" : "wool_white") {
            s.entities.spawnItem(ItemStack(item: wool, count: Int.random(in: 1...2)), at: center,
                                 velocity: DVec3(Double.random(in: -2...2), 3.5, Double.random(in: -2...2)), pickupDelay: 0.5)
        }
        Log.info("\(m.species.displayName) was defeated", category: "Game")
    }

    func raycast(origin: DVec3, direction: DVec3, maxDistance: Double) -> (Mob, Double)? {
        var best: (Mob, Double)?
        for m in mobs where !m.removed && !m.isDying {
            let hw = m.species.width / 2 + 0.1
            let box = DBox(min: m.position - DVec3(hw, 0, hw), max: m.position + DVec3(hw, m.species.height + 0.1, hw))
            if let t = MobManager.rayBox(origin, direction, box), t <= maxDistance, t < (best?.1 ?? .infinity) {
                best = (m, t)
            }
        }
        return best
    }

    static func rayBox(_ o: DVec3, _ d: DVec3, _ b: DBox) -> Double? {
        var tmin = 0.0, tmax = Double.infinity
        for axis in 0..<3 {
            if abs(d[axis]) < 1e-9 {
                if o[axis] < b.min[axis] || o[axis] > b.max[axis] { return nil }
            } else {
                let inv = 1 / d[axis]
                var t1 = (b.min[axis] - o[axis]) * inv, t2 = (b.max[axis] - o[axis]) * inv
                if t1 > t2 { swap(&t1, &t2) }
                tmin = max(tmin, t1)
                tmax = min(tmax, t2)
                if tmin > tmax { return nil }
            }
        }
        return tmin
    }

    private func shoot(_ m: Mob, at target: DVec3) {
        let origin = m.position + DVec3(0, m.species.height * 0.85, 0)
        var dir = target - origin
        let distance = simd_length(dir)
        dir /= max(distance, 0.001)
        let velocity = dir * 16 + DVec3(0, distance * 0.375, 0)
        projectiles.append(Projectile(position: origin, velocity: velocity, damage: m.species.damage))
    }

    private func updateProjectiles(_ dt: Double, _ s: GameSession) {
        let world = s.world
        for p in projectiles where !p.removed {
            p.age += dt
            p.velocity.y -= 12 * dt
            p.position += p.velocity * dt
            if p.age > 5 { p.removed = true; continue }
            let id = world.block(Int(floor(p.position.x)), Int(floor(p.position.y)), Int(floor(p.position.z)))
            if world.registry.isSolid[Int(id)] {
                p.removed = true
                s.onSound?("splash", 0.25, 1.8)
                continue
            }
            if let hit = s.hostileTargets().first(where: { simd_distance(p.position, $0.pos + DVec3(0, 0.9, 0)) < 0.9 }) {
                p.removed = true
                let flat = DVec3(p.velocity.x, 0, p.velocity.z)
                s.damageTarget(id: hit.id, amount: p.damage, cause: p.cause, attacker: p.attacker,
                               knockback: simd_length(flat) > 0.01 ? simd_normalize(flat) * 0.5 : .zero)
                s.onSound?("splash", 0.5, 1.5)
            }
        }
        projectiles.removeAll { $0.removed }
    }

    // MARK: Spawning

    private func trySpawn(_ s: GameSession) {
        guard s.meta.rule("doMobSpawning") else { return }
        let world = s.world
        let difficulty = s.meta.difficulty
        let hostileCap: Int
        switch difficulty {
        case .peaceful: hostileCap = 0
        case .easy: hostileCap = 3
        case .normal: hostileCap = 5
        case .hard: hostileCap = 9
        }
        if difficulty == .peaceful { mobs.removeAll { $0.species.hostile } }
        let hostiles = mobs.filter { $0.species.hostile }.count
        let friendlies = mobs.filter { !$0.species.hostile && $0.species.kind != .villager }.count
        let allowHostile = hostiles < hostileCap
        let allowFriendly = friendlies < 10 && Double.random(in: 0..<1) < 0.25
        guard allowHostile || allowFriendly else { return }

        let p = s.player.position
        for _ in 0..<4 {
            let angle = Double.random(in: 0..<(2 * .pi)), r = Double.random(in: 28...60)
            let x = Int(floor(p.x + cos(angle) * r)), z = Int(floor(p.z + sin(angle) * r))
            // No hostile spawns close to the world spawn, so new players aren't ambushed.
            let worldSpawn = s.spawnLocation
            let nearSpawn = s.dimension == .overworld && simd_distance(SIMD2(Double(x), Double(z)), SIMD2(worldSpawn.x, worldSpawn.z)) < 32
            guard world.slot(at: ChunkPos(Int32(x >> 4), Int32(z >> 4)))?.mesh != nil else { continue }
            guard let y = world.findStandingY(x, z, near: Int(p.y)), abs(y - Int(p.y)) < 40 else { continue }
            let light = world.light(at: DVec3(Double(x) + 0.5, Double(y) + 0.5, Double(z) + 0.5))
            let ground = world.block(x, y - 1, z)
            guard let kind = chooseSpecies(s, ground: ground, light: light, x: x, y: y, z: z,
                                           allowHostile: allowHostile && !nearSpawn, allowFriendly: allowFriendly) else { continue }
            let species = MobSpecies.of(kind)
            let hw = species.width / 2
            let box = DBox(min: DVec3(Double(x) + 0.5 - hw, Double(y) + 0.01, Double(z) + 0.5 - hw),
                           max: DVec3(Double(x) + 0.5 + hw, Double(y) + species.height, Double(z) + 0.5 + hw))
            guard !VoxelPhysics.collides(world, box, scratch: &scratch),
                  !VoxelPhysics.anyBlock(world, in: box, where: { world.registry.shape[Int($0)] == .liquid }) else { continue }
            let group = (kind == .compy || kind == .troodon) ? 2 : (species.hostile || kind == .stego || kind == .ankylo ? 1 : Int.random(in: 1...3))
            for i in 0..<group {
                spawn(kind, at: DVec3(Double(x) + 0.5 + Double(i) * 0.8, Double(y) + (species.flying ? 8 : 0), Double(z) + 0.5 + Double(i) * 0.4))
            }
            Log.debug("Spawned \(group)× \(species.displayName) at \(x), \(y), \(z)", category: "Game")
            return
        }
    }

    private func chooseSpecies(_ s: GameSession, ground: BlockID, light: (sky: Float, block: Float), x: Int, y: Int, z: Int,
                               allowHostile: Bool, allowFriendly: Bool) -> MobKind? {
        let roll = Double.random(in: 0..<1)
        switch s.dimension {
        case .underworld:
            guard allowHostile, light.block < 0.8 else { return nil }
            return roll < 0.75 ? .magmaRaptor : .crawler
        case .skylands:
            guard allowFriendly, ground == Blocks.skyGrass else { return nil }
            return roll < 0.5 ? .longneck : .dodo
        case .toonland:
            // A happy place: only friendly critters wander the hills.
            guard allowFriendly, ground == Blocks.toonGrass else { return nil }
            let herd: [(Double, MobKind)] = [(0.25, .pookpook), (0.45, .dodo), (0.6, .sheep), (0.75, .pig), (0.88, .chicken), (1.01, .trikey)]
            return herd.first(where: { roll < $0.0 })?.1 ?? .dodo
        case .overworld:
            let dark = light.sky < 0.35 && light.block < 0.3
            let nightSurface = (s.isNight || s.weather.kind == .thunder) && light.sky > 0.5 && light.block < 0.4
            let biome = s.world.generator.biome(x: x, z: z)
            if allowHostile && (biome == .mountains || biome == .snowyPeaks) && light.sky > 0.6 && roll < 0.12 { return .ptero }
            if allowHostile && (dark || nightSurface) {
                if dark && y < s.world.generator.seaLevel { return roll < 0.45 ? .crawler : (roll < 0.75 ? .boneWalker : .raptor) }
                if (biome == .swamp || biome == .fernJungle) && roll < 0.35 { return .spitter }
                if biome == .desert && roll < 0.5 { return .scorpion }
                if (biome == .forest || biome == .fernJungle) && roll < 0.55 { return .troodon }
                if nightSurface && roll > 0.94 { return .rex }
                if roll < 0.3 { return .compy }
                return .raptor
            }
            let goodGround = [Blocks.grass, Blocks.snowyGrass, Blocks.sand, Blocks.mossBlock].contains(ground)
            // Big predators hunt in daylight too, a few at a time.
            let predators: Set<MobKind> = [.carnotaurus, .allosaurus, .baryonyx, .spinosaurus, .rex]
            let dayCap = s.meta.difficulty == .hard ? 2 : (s.meta.difficulty == .normal ? 1 : 0)
            if allowHostile && goodGround && light.sky > 0.6 && Double.random(in: 0..<1) < 0.1
                && mobs.filter({ predators.contains($0.species.kind) }).count < dayCap {
                switch biome {
                case .plains, .desert: return roll < 0.85 ? .carnotaurus : .rex
                case .forest, .mountains, .redwoodTaiga: return .allosaurus
                case .swamp, .river, .beach: return .baryonyx
                case .fernJungle: return roll < 0.25 ? .spinosaurus : .carnotaurus
                default: break
                }
            }
            guard allowFriendly, !s.isNight, light.sky > 0.7, goodGround else { return nil }
            if ground == Blocks.sand { return roll < 0.6 ? .dodo : .pookpook }
            if (biome == .swamp || biome == .fernJungle) && roll < 0.35 { return .sailback }
            if biome == .snowyTundra || biome == .redwoodTaiga {
                return roll < 0.4 ? .sheep : (roll < 0.65 ? .cow : (roll < 0.8 ? .pookpook : .stego))
            }
            let herd: [(Double, MobKind)] = [(0.1, .trikey), (0.17, .dodo), (0.24, .longneck), (0.31, .stego), (0.37, .ankylo), (0.44, .parasaur),
                                              (0.56, .cow), (0.67, .pig), (0.79, .sheep), (0.89, .chicken), (1.01, .pookpook)]
            return herd.first(where: { roll < $0.0 })?.1 ?? .pookpook
        }
    }

    // MARK: Persistence (friendly creatures persist; hostiles are ambient)

    func save(to url: URL) {
        let saved = mobs.filter { !$0.species.hostile && !$0.isDying && !$0.removed }.map {
            SavedMob(kind: $0.species.kind.rawValue, x: $0.position.x, y: $0.position.y, z: $0.position.z, health: $0.health, yaw: $0.yaw,
                     variant: $0.variant, hx: $0.home?.x, hy: $0.home?.y, hz: $0.home?.z)
        }
        do {
            try AtomicFile.write(JSONEncoder().encode(saved), to: url)
        } catch {
            Log.error("Failed to save creatures: \(error)", category: "Save")
        }
    }

    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            for s in try JSONDecoder().decode([SavedMob].self, from: data) {
                guard let kind = MobKind(rawValue: s.kind) else { continue }
                let m = spawn(kind, at: DVec3(s.x, s.y, s.z))
                m.health = min(m.species.maxHealth, max(1, s.health))
                m.yaw = s.yaw
                m.variant = s.variant ?? m.variant
                if let hx = s.hx, let hy = s.hy, let hz = s.hz { m.home = DVec3(hx, hy, hz) }
            }
            Log.info("Restored \(mobs.count) creatures", category: "Save")
        } catch {
            Log.error("Creature save is unreadable (\(error)); ignoring it", category: "Save")
        }
    }
}

extension MobKind {
    /// Item name of this creature's spawn egg, e.g. `spawn_egg_magma_raptor`.
    var eggItemName: String {
        var out = "spawn_egg_"
        for ch in rawValue {
            if ch.isUppercase { out += "_" + ch.lowercased() } else { out.append(ch) }
        }
        return out
    }

    static func forEgg(named name: String) -> MobKind? {
        guard name.hasPrefix("spawn_egg_") else { return nil }
        return allCases.first { $0.eggItemName == name }
    }
}

// MARK: - World events

extension MobManager {
    /// Now and then a herd thunders past in daylight, so the overworld doesn't feel the same every day.
    fileprivate func startStampede(_ s: GameSession) {
        guard s.dimension == .overworld, !s.isRemote, !s.isNight, !s.isUnderground, s.meta.rule("doMobSpawning") else { return }
        let p = s.player.position
        let herds: [(MobKind, String)] = [(.parasaur, "Parasaurolophus"), (.trikey, "Trikeys"), (.stego, "Stegosaurus"), (.dodo, "Dodos")]
        let (kind, name) = herds.randomElement()!
        let a = Double.random(in: 0..<(2 * .pi))
        let center = DVec3(p.x + cos(a) * 22, p.y, p.z + sin(a) * 22)
        var placed = 0
        for i in 0..<Int.random(in: 4...7) {
            let x = Int(floor(center.x)) + (i % 3) * 2 - 2, z = Int(floor(center.z)) + (i / 3) * 2 - 2
            guard s.world.isLoaded(x, z), let y = s.world.findStandingY(x, z, near: Int(p.y)), abs(y - Int(p.y)) < 12 else { continue }
            let m = spawn(kind, at: DVec3(Double(x) + 0.5, Double(y), Double(z) + 0.5))
            m.fleeTimer = 14
            placed += 1
        }
        guard placed > 0 else { return }
        s.onToast?("A herd of \(name) is stampeding past!")
        s.onSound?("amb_dino_low", 0.9, 0.8)
    }
}

// MARK: - King Grumblesaurus

extension MobManager {
    /// The boss fighting near `p`, for the boss health bar.
    func boss(near p: DVec3) -> Mob? {
        mobs.first { $0.species.kind == .grumblesaurus && !$0.removed && simd_distance($0.position, p) < 64 }
    }

    /// Keeps King Grumblesaurus on the nearest Toonland stage until he's cheered up,
    /// and a happy Grumblesaurus there afterwards.
    fileprivate func spawnStageGuests(_ s: GameSession) {
        guard s.dimension == .toonland, !s.isRemote else { return }
        let p = s.player.position
        let stage = ToonlandGenerator.nearestStage(x: Int(floor(p.x)), z: Int(floor(p.z)))
        let center = DVec3(Double(stage.x) + 0.5, Double(ToonlandGenerator.stageFloor + 1), Double(stage.z) + 0.5)
        guard simd_distance(SIMD2(p.x, p.z), SIMD2(center.x, center.z)) < 40,
              s.world.slot(at: ChunkPos(Int32(stage.x >> 4), Int32(stage.z >> 4)))?.mesh != nil else { return }
        if s.isBossDefeated("grumblesaurus") {
            guard !mobs.contains(where: { $0.species.kind == .grinasaurus && simd_distance($0.position, center) < 40 }) else { return }
            let m = spawn(.grinasaurus, at: center)
            m.home = center
        } else if !mobs.contains(where: { $0.species.kind == .grumblesaurus }) {
            guard s.meta.difficulty != .peaceful else {
                if !peacefulHintShown { s.onToast?("King Grumblesaurus only comes out on Easy difficulty or harder") }
                peacefulHintShown = true
                return
            }
            let m = spawn(.grumblesaurus, at: center)
            m.home = center
            s.onToast?("King Grumblesaurus stomps onto the stage! Cheer him up!")
            s.onSound?("amb_dino_low", 1, 0.35)
            s.effectBursts.append((center, .ink))
        }
    }

    fileprivate func updateBoss(_ m: Mob, target: (id: Int, pos: DVec3)?, dt: Double, session s: GameSession) {
        if !m.enraged && m.health < m.species.maxHealth * 0.5 {
            m.enraged = true
            s.onToast?("King Grumblesaurus is getting REALLY grumpy!")
            s.onSound?("amb_dino_low", 1, 0.3)
        }
        let rage = m.enraged ? 1.35 : 1.0
        var desired = DVec3.zero
        var speed = 0.0
        if let target, simd_distance(target.pos, m.position) < 56 {
            let to = target.pos - m.position
            let flat = DVec3(to.x, 0, to.z)
            let dist = simd_length(flat)
            let dir = dist > 0.01 ? flat / dist : DVec3(0, 0, 1)
            if dist > 2 && !m.airborne { desired = dir; speed = 3.0 * rage }
            m.yaw = MobManager.lerpAngle(m.yaw, atan2(-dir.x, -dir.z), 1 - exp(-6 * dt))

            // Chomp
            if dist < m.species.attackReach + m.species.width / 2 && abs(to.y) < 3 && m.attackTimer <= 0 {
                m.attackTimer = m.species.attackCooldown / rage
                m.lunge = 1
                s.damageTarget(id: target.id, amount: m.species.damage, cause: "Chomped by King Grumblesaurus",
                               attacker: "King Grumblesaurus", knockback: dir * 1.5)
                s.onSound?("amb_dino_low", 0.8, 0.45)
            }
            // Ink splatter volley
            m.volleyTimer -= dt * rage
            if m.volleyTimer <= 0 && dist > 4 {
                m.volleyTimer = 5
                let origin = m.position + DVec3(0, m.species.height * 0.8, 0)
                let shots = m.enraged ? 5 : 3
                for i in 0..<shots {
                    let spread = (Double(i) - Double(shots - 1) / 2) * 0.22
                    let aim = target.pos + DVec3(0, 1, 0) - origin
                    let d = simd_length(aim)
                    let flatAim = DVec3(aim.x, 0, aim.z)
                    let side = simd_length(flatAim) > 0.01 ? simd_normalize(DVec3(-flatAim.z, 0, flatAim.x)) : DVec3(1, 0, 0)
                    let v = simd_normalize(aim) * 15 + side * spread * 15 + DVec3(0, d * 0.35, 0)
                    let blob = Projectile(position: origin, velocity: v, damage: 4)
                    blob.cause = "Splattered by King Grumblesaurus"
                    blob.attacker = "King Grumblesaurus"
                    projectiles.append(blob)
                }
                m.lunge = 1
                s.onSound?("splash", 0.9, 0.6)
            }
            // Grumpy stomp: a big jump and a shockwave on landing
            m.stompTimer -= dt * rage
            if m.stompTimer <= 0 && m.onGround && !m.airborne {
                m.stompTimer = 9
                m.airborne = true
                m.velocity.y = 12
                m.velocity += dir * 3
                s.onSound?("amb_dino_low", 0.9, 0.5)
            }
        } else if let home = m.home, simd_distance(SIMD2(home.x, home.z), SIMD2(m.position.x, m.position.z)) > 6 {
            let to = DVec3(home.x - m.position.x, 0, home.z - m.position.z)
            desired = simd_normalize(to)
            speed = m.species.walkSpeed
        }
        let wasAirborne = m.airborne && m.velocity.y < 0
        physics(m, desired: desired, speed: speed, dt: dt, session: s)
        if wasAirborne && m.onGround {
            m.airborne = false
            s.effectBursts.append((m.position, .dust))
            s.onSound?("break_stone", 1, 0.5)
            for t in s.hostileTargets() {
                let d = t.pos - m.position
                let flat = DVec3(d.x, 0, d.z)
                let dist = simd_length(flat)
                guard dist < 7.5, abs(d.y) < 2.5 else { continue }
                let away = dist > 0.01 ? flat / dist : DVec3(1, 0, 0)
                s.damageTarget(id: t.id, amount: 6 * (1 - dist / 12), cause: "Stomped by King Grumblesaurus",
                               attacker: "King Grumblesaurus", knockback: away * 2)
            }
        }
        m.callTimer -= dt
        if m.callTimer <= 0 {
            m.callTimer = Double.random(in: 6...12)
            s.onSound?("amb_dino_low", 0.7, m.species.callPitch)
        }
    }

    /// Defeating the boss cheers him up: confetti, a happy Grumblesaurus and a trophy.
    fileprivate func bossCheeredUp(_ m: Mob, _ s: GameSession) {
        s.effectBursts.append((m.position + DVec3(0, 2, 0), .confetti))
        s.markBossDefeated("grumblesaurus")
        let happy = spawn(.grinasaurus, at: m.position)
        happy.yaw = m.yaw
        happy.home = m.home
        s.onToast?("You cheered up King Grumblesaurus! You beat DinoCraft! Keep exploring and building.")
        s.onSound?("discover", 1, 1.4)
    }
}
