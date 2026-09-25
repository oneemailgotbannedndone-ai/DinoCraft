import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// How a creature can be tamed and what it does for you afterwards.
struct TameRule {
    /// Foods it can be tamed (and healed) with.
    let foods: [String]
    /// Can wear a saddle and be ridden.
    let rideable: Bool
    /// Where the rider sits, above the creature's feet.
    let seat: Double
    /// Fights whatever attacks you, and whatever you attack.
    let guardian: Bool
}

enum Taming {
    static let owner = "player"
    /// Each feeding has this chance to tame a creature.
    static let chance = 1.0 / 3.0

    static let rules: [MobKind: TameRule] = [
        .trikey: TameRule(foods: ["berries", "wheat"], rideable: true, seat: 1.05, guardian: false),
        .parasaur: TameRule(foods: ["berries", "wheat"], rideable: true, seat: 1.7, guardian: false),
        .iguanodon: TameRule(foods: ["berries", "wheat", "carrot"], rideable: true, seat: 1.75, guardian: false),
        .stego: TameRule(foods: ["berries", "wheat"], rideable: true, seat: 1.55, guardian: false),
        .longneck: TameRule(foods: ["berries", "wheat"], rideable: true, seat: 3.3, guardian: false),
        .gallimimus: TameRule(foods: ["berries", "raw_poultry"], rideable: true, seat: 1.4, guardian: false),
        .pachy: TameRule(foods: ["berries"], rideable: true, seat: 1.35, guardian: false),
        .raptor: TameRule(foods: ["raw_dino_meat"], rideable: false, seat: 0, guardian: true),
        .compy: TameRule(foods: ["raw_dino_meat", "raw_poultry"], rideable: false, seat: 0, guardian: true),
        .dodo: TameRule(foods: ["wheat_seeds", "berries"], rideable: false, seat: 0, guardian: false),
        .oviraptor: TameRule(foods: ["berries", "raw_poultry"], rideable: false, seat: 0, guardian: false),
        .pookpook: TameRule(foods: ["wheat_seeds"], rideable: false, seat: 0, guardian: false),
        // Fish-eaters of the sky: saddle one and fly.
        .ptero: TameRule(foods: ["raw_fish", "tropical_fish", "cooked_fish"], rideable: true, seat: 0.45, guardian: false),
    ]

    static func rule(_ kind: MobKind) -> TameRule? { rules[kind] }
}

extension Mob {
    var isTamed: Bool { owner != nil }

    /// What to call it: its name if it has one, and what it's doing.
    var label: String {
        var text = petName.map { "\($0) the \(species.displayName)" } ?? species.displayName
        if isTamed {
            if sitting { text += " (sitting)" }
            if saddled { text += " \u{00B7} saddled" }
        }
        return text
    }
}

extension GameSession {
    /// Right-clicking a creature: feed it to tame it, heal it, saddle it, ride it or tell it to sit.
    /// Returns true when the click was used.
    func interactWithCreature(_ mob: Mob) -> Bool {
        if mob.species.isVehicle {
            guard !mob.removed, riding == nil else { return false }
            if isRemote {
                onToast?("Boats work in your own worlds (or ones you host) for now.")
            } else if !player.isSneaking {
                mount(mob)
            } else {
                return false
            }
            return true
        }
        if mob.species.kind == .armorStand {
            if isRemote { onToast?("Armour stands work in your own worlds (or ones you host) for now."); return true }
            return useArmorStand(mob)
        }
        guard let rule = Taming.rule(mob.species.kind), !mob.isDying else { return false }
        let held = inventory.selectedStack.flatMap { items[$0.item]?.name }
        let isFood = held.map { rule.foods.contains($0) } ?? false
        if isRemote {
            if isFood { onToast?("Taming works in your own worlds (or ones you host) for now.") }
            return isFood
        }
        let name = mob.species.displayName
        if !mob.isTamed {
            guard isFood else { return false }
            swing()
            if player.gameMode == .survival { inventory.consumeSelected() }
            onSound?("eat", 0.6, mob.species.callPitch)
            if player.gameMode == .creative || Double.random(in: 0..<1) < Taming.chance {
                mob.owner = Taming.owner
                mob.aggroTimer = 0
                mob.fleeTimer = 0
                mob.wanderTarget = nil
                effectBursts.append((mob.position + DVec3(0, mob.species.height, 0), .confetti))
                onSound?(mob.species.callSound, 0.7, mob.species.callPitch)
                var hint = rule.rideable ? "Put a saddle on it to ride it." : (rule.guardian ? "It will fight for you." : "It will follow you.")
                hint += " Right-click it to make it sit."
                onToast?("You tamed the \(name)! \(hint)")
                advancements.record("tame", mob.species.kind.rawValue)
            } else {
                effectBursts.append((mob.position + DVec3(0, mob.species.height, 0), .dust))
                onToast?("The \(name) isn't sure about you yet. Keep feeding it.")
            }
            return true
        }
        // One of yours
        if isFood && mob.health < mob.species.maxHealth {
            swing()
            if player.gameMode == .survival { inventory.consumeSelected() }
            mob.health = min(mob.species.maxHealth, mob.health + 5)
            effectBursts.append((mob.position + DVec3(0, mob.species.height, 0), .confetti))
            onSound?("eat", 0.6, mob.species.callPitch)
            return true
        }
        if isFood && feedToBreed(mob, rule: rule) { return true }
        if held == "saddle" && rule.rideable && !mob.saddled && mob.growth >= 1 {
            swing()
            mob.saddled = true
            if player.gameMode == .survival { inventory.consumeSelected() }
            onSound?("place_wood", 0.7, 1.2)
            onToast?("Saddled! Right-click to ride, sneak to get off.")
            return true
        }
        if rule.rideable && mob.saddled && mob.growth >= 1 && !player.isSneaking {
            mount(mob)
            return true
        }
        mob.sitting.toggle()
        mob.wanderTarget = nil
        swing()
        onToast?(mob.sitting ? "\(mob.petName ?? name) sits and waits." : "\(mob.petName ?? name) follows you.")
        return true
    }

    func mount(_ mob: Mob) {
        riding = mob
        if mob.species.flying { advancements.record("ride", "ptero_flight") }
        mob.sitting = false
        if player.flying { player.setFlying(false) }
        onSound?(mob.species.callSound, 0.5, mob.species.callPitch)
        onToast?(mob.species.isVehicle ? "All aboard! Steer where you look; sneak to get off."
                 : "Riding the \(mob.petName ?? mob.species.displayName). Sneak to get off.")
        advancements.record("ride", mob.species.kind.rawValue)
    }

    func dismount() {
        guard let mob = riding else { return }
        riding = nil
        mob.rideInput = nil
        // Step off to the side, clear of the creature.
        let look = player.lookDirection
        let side = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(-look.z, 0, look.x)) : DVec3(1, 0, 0)
        player.teleport(to: mob.position + side * (mob.species.width / 2 + 0.7) + DVec3(0, 0.2, 0))
    }

    /// While riding, your movement keys steer the creature instead of you.
    func steerMount(_ move: MovementInput) {
        guard let mob = riding else { return }
        if move.sneak || mob.isDying || mob.removed || !(mob.isTamed || mob.species.isVehicle) {
            dismount()
            return
        }
        let look = player.lookDirection
        let forward = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(look.x, 0, look.z)) : DVec3(0, 0, -1)
        let right = DVec3(-forward.z, 0, forward.x)
        var desired = forward * move.forward + right * move.strafe
        if mob.species.flying {
            // In the air you fly where you look: tip down to dive, up to climb; Jump flies straight up.
            desired = look * move.forward + right * move.strafe + DVec3(0, move.jump ? 0.8 : 0, 0)
        }
        if simd_length(desired) > 1 { desired = simd_normalize(desired) }
        mob.rideInput = desired
        mob.rideSprint = move.sprint
        mob.rideJump = move.jump
    }

    /// Keeps you in the saddle after the creature has moved.
    func followMount() {
        guard let mob = riding else { return }
        let seat = mob.species.isVehicle ? Boats.seat : (Taming.rule(mob.species.kind)?.seat ?? mob.species.height) * mob.scale
        player.teleport(to: mob.position + DVec3(0, seat, 0))
        player.refreshSurroundings(world)
    }
}

extension MobManager {
    /// Tamed creatures: sit, follow you (catching up if left far behind), and guardians fight for you.
    func updateTamed(_ m: Mob, dt: Double, session s: GameSession) {
        let owner = s.player.position
        let toOwner = DVec3(owner.x - m.position.x, 0, owner.z - m.position.z)
        let distance = simd_length(toOwner)
        var desired = DVec3.zero, speed = 0.0
        if let ride = m.rideInput, m.species.flying {
            rideFlight(m, input: ride, dt: dt, session: s)
            return
        }
        if let ride = m.rideInput {
            desired = ride
            speed = m.rideSprint ? m.species.runSpeed * 0.85 : max(m.species.walkSpeed * 1.8, 3.2)
            physics(m, desired: desired, speed: speed, dt: dt, session: s)
            if m.rideJump && m.onGround { m.velocity.y = 8.6 }
            return
        }
        if let target = m.guardTarget, !target.isDying, !target.removed, simd_distance(target.position, m.position) < 20 {
            let to = DVec3(target.position.x - m.position.x, 0, target.position.z - m.position.z)
            let d = simd_length(to)
            let dir = d > 0.01 ? to / d : DVec3(0, 0, 1)
            desired = dir
            speed = m.species.runSpeed * 0.85
            if d < m.species.attackReach + target.species.width / 2 + 0.6 && m.attackTimer <= 0 {
                hurt(target, amount: max(2, m.species.damage), knockback: dir, session: s)
                m.attackTimer = max(0.8, m.species.attackCooldown)
                m.lunge = 1
            }
        } else {
            m.guardTarget = nil
            if let mate = m.mateTarget {
                let to = DVec3(mate.x - m.position.x, 0, mate.z - m.position.z)
                if simd_length(to) > 0.1 { desired = simd_normalize(to) }
                speed = m.species.walkSpeed * 1.3
            } else if m.sitting {
                // Stay put.
            } else if distance > 26 && !s.player.flying {
                // Left far behind: catch up.
                let a = Double.random(in: 0..<(2 * .pi))
                m.position = owner + DVec3(cos(a) * 2, 0.5, sin(a) * 2)
                m.velocity = .zero
            } else if distance > 5 {
                desired = toOwner / distance
                speed = distance > 10 ? m.species.runSpeed * 0.8 : m.species.walkSpeed * 1.4
            } else {
                wanderNearOwner(m, dt: dt, desired: &desired, speed: &speed)
            }
        }
        physics(m, desired: desired, speed: speed, dt: dt, session: s)
    }

    /// A ridden flier: glides where the rider steers, hovers with a slow flap when there's no input, and
    /// lands (walking slowly) when it touches the ground.
    private func rideFlight(_ m: Mob, input: DVec3, dt: Double, session s: GameSession) {
        let top = m.rideSprint ? 16.0 : 10.0
        let k = 1 - exp(-(simd_length(input) > 0 ? 2.2 : 1.4) * dt)
        var target = input * top
        if simd_length(input) < 0.01 { target.y = -0.6 }   // drifting slowly down while hovering
        m.velocity += (target - m.velocity) * k
        _ = move(m, m.velocity * dt, s.world)
        let horizontal = DVec3(m.velocity.x, 0, m.velocity.z)
        if simd_length(horizontal) > 0.3 {
            m.yaw = MobManager.lerpAngle(m.yaw, atan2(-horizontal.x, -horizontal.z), 1 - exp(-6 * dt))
        }
        m.moveAmount = m.onGround ? min(1, simd_length(horizontal) / 3) : 1
        m.walkPhase += dt * (m.onGround ? 4 : (m.rideSprint ? 9 : 6))
        if m.position.y < -32 { m.position.y = -32; m.velocity.y = max(0, m.velocity.y) }
    }

    private func wanderNearOwner(_ m: Mob, dt: Double, desired: inout DVec3, speed: inout Double) {
        m.idleTimer -= dt
        if m.idleTimer <= 0 {
            m.idleTimer = Double.random(in: 2...6)
            let a = Double.random(in: 0..<(2 * .pi))
            m.wanderTarget = m.position + DVec3(cos(a) * 2, 0, sin(a) * 2)
            m.wanderTimer = 3
        }
        if let t = m.wanderTarget, m.wanderTimer > 0 {
            m.wanderTimer -= dt
            let d = DVec3(t.x - m.position.x, 0, t.z - m.position.z)
            if simd_length(d) > 0.5 { desired = simd_normalize(d); speed = m.species.walkSpeed * 0.7 }
        }
    }

    /// Your guardians turn on whatever you're fighting (or whatever is fighting you).
    func alertGuardians(against enemy: Mob, near p: DVec3) {
        guard !enemy.isTamed, !enemy.species.isVehicle else { return }
        for m in mobs where m.isTamed && !m.sitting && simd_distance(m.position, p) < 24 {
            if Taming.rule(m.species.kind)?.guardian == true { m.guardTarget = enemy }
        }
    }
}
