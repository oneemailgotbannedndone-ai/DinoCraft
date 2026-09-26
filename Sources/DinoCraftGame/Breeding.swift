import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Dino eggs: feed two of your tamed adults of the same kind (at full health) and they find each other
/// and lay an egg. It hatches into a tamed baby that grows up over about ten minutes (faster if fed).
enum Breeding {
    /// How long a fed adult looks for a partner.
    static let loveTime = 30.0
    /// Rest after laying before it can breed again.
    static let cooldown = 300.0
    static let hatchTime = 45.0
    /// Seconds for a hatchling to grow up; each feeding skips ahead a tenth of that.
    static let growTime = 600.0
    static let partnerRange = 12.0
    /// A saddled Pteranodon is drawn (and collides) this much bigger, so it can carry you.
    static let saddledPteroScale = 1.9

    /// Kinds that can lay eggs, in a fixed order: an egg's `variant` indexes this list.
    static let kinds: [MobKind] = Taming.rules.keys.sorted { $0.rawValue < $1.rawValue }

    static func kind(ofEgg variant: Int) -> MobKind { kinds[max(0, variant) % kinds.count] }

    /// Shell colours of each kind's egg: base and speckles.
    static func eggColors(_ kind: MobKind) -> (UInt32, UInt32) {
        switch kind {
        case .raptor, .compy: return (0xD8C8A0, 0x7A5A34)
        case .ptero: return (0xC8DCE8, 0x5A7A94)
        case .longneck, .parasaur, .iguanodon: return (0xE4E0C8, 0x7E8A52)
        case .stego, .pachy: return (0xE8D0B0, 0xA05A3A)
        case .trikey: return (0xE6D8B8, 0x8A6A3E)
        case .gallimimus, .oviraptor: return (0xDCC4D8, 0x7A4A74)
        case .dodo, .pookpook: return (0xF2EEE0, 0xB0A080)
        default: return (0xEDE4CC, 0x8E7A5A)
        }
    }
}

extension GameSession {
    /// Right-click with its food on one of your creatures that is fully healed: a grown-up goes looking
    /// for a mate, a baby grows a little. Returns true when the click was used.
    func feedToBreed(_ mob: Mob, rule: TameRule) -> Bool {
        let name = mob.petName ?? mob.species.displayName
        if mob.growth < 1 {
            swing()
            if player.gameMode == .survival { inventory.consumeSelected() }
            mob.growth = min(1, mob.growth + 0.1)
            effectBursts.append((mob.position + DVec3(0, mob.species.height * mob.scale, 0), .crumbs))
            onSound?("eat", 0.6, mob.species.callPitch * 1.3)
            if mob.growth >= 1 { onToast?("\(name) is all grown up!") }
            return true
        }
        guard mob.loveTimer <= 0 else { return false }
        if mob.breedCooldown > 0 {
            onToast?("\(name) needs a rest before another egg (\(Int(mob.breedCooldown.rounded(.up)))s).")
            return true
        }
        swing()
        if player.gameMode == .survival { inventory.consumeSelected() }
        mob.loveTimer = Breeding.loveTime
        mob.sitting = false
        effectBursts.append((mob.position + DVec3(0, mob.species.height, 0), .confetti))
        onSound?(mob.species.callSound, 0.6, mob.species.callPitch)
        onToast?("\(name) is in the mood. Feed another tamed \(mob.species.displayName) nearby for an egg!")
        return true
    }
}

extension MobManager {
    /// Grows babies, counts down love and rest, and walks a creature in love to its partner; when they
    /// meet they lay an egg between them.
    func updateBreeding(_ m: Mob, dt: Double, session s: GameSession) {
        if m.growth < 1 { m.growth = min(1, m.growth + dt / Breeding.growTime) }
        m.breedCooldown = max(0, m.breedCooldown - dt)
        guard m.loveTimer > 0 else { return }
        m.loveTimer = max(0, m.loveTimer - dt)
        m.mateTarget = nil
        guard m.rideInput == nil, let partner = mobs.first(where: {
            $0 !== m && !$0.removed && !$0.isDying && $0.isTamed && $0.species.kind == m.species.kind && $0.loveTimer > 0
                && $0.growth >= 1 && simd_distance($0.position, m.position) < Breeding.partnerRange
        }) else { return }
        let to = DVec3(partner.position.x - m.position.x, 0, partner.position.z - m.position.z)
        let d = simd_length(to)
        if d > m.species.width / 2 + partner.species.width / 2 + 0.6 {
            m.mateTarget = partner.position
            return
        }
        // Together: lay an egg between them.
        m.loveTimer = 0
        partner.loveTimer = 0
        m.breedCooldown = Breeding.cooldown
        partner.breedCooldown = Breeding.cooldown
        let egg = spawn(.egg, at: (m.position + partner.position) / 2 + DVec3(0, 0.3, 0))
        egg.variant = Breeding.kinds.firstIndex(of: m.species.kind) ?? 0
        s.effectBursts.append((egg.position + DVec3(0, 0.8, 0), .confetti))
        s.onSound?("place_sand", 0.7, 1.4)
        s.onToast?("An egg! Keep it safe: it hatches in about \(Int(Breeding.hatchTime)) seconds.")
        s.advancements.record("breed", m.species.kind.rawValue)
    }

    /// Eggs sit and wobble, then hatch into a tamed baby.
    func updateEgg(_ m: Mob, dt: Double, session s: GameSession) {
        physics(m, desired: .zero, speed: 0, dt: dt, session: s)
        m.hatchTimer -= dt
        // Wobble harder as hatching nears.
        m.walkPhase += dt * (m.hatchTimer < 10 ? 14 : 5)
        m.moveAmount = m.hatchTimer < 10 ? 0.35 : 0.12
        guard m.hatchTimer <= 0 else { return }
        m.removed = true
        let kind = Breeding.kind(ofEgg: m.variant)
        let baby = spawn(kind, at: m.position)
        baby.owner = Taming.owner
        baby.growth = 0
        baby.health = baby.species.maxHealth
        s.effectBursts.append((m.position + DVec3(0, 0.4, 0), .crumbs))
        s.onSound?("break_glass", 0.4, 1.6)
        s.onSound?(baby.species.callSound, 0.7, baby.species.callPitch * 1.5)
        if simd_distance(s.player.position, m.position) < 48 {
            s.onToast?("A baby \(baby.species.displayName) hatched! Feed it to help it grow.")
        }
        s.advancements.record("hatch", kind.rawValue)
    }
}
