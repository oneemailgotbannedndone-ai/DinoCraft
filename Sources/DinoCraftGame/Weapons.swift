import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif
import DinoCraftCore

/// Spears, crossbows and shields, alongside the bow.
///
/// - Spear: a strong melee weapon; hold Use to wind up and let go to throw it. Walk over it to pick it back up.
/// - Crossbow: hold Use to load a bolt (uses an arrow); it stays loaded until you press Use again to fire.
///   A loaded crossbow is marked by its `damage` value, so it stays loaded in saves and multiplayer.
/// - Shield: hold Use to block everything coming at you from the front. You walk slowly while blocking,
///   and blocked hits wear the shield down.
enum Weapons {
    static let spear = "spear"
    static let crossbow = "crossbow"
    static let shield = "shield"
    /// Seconds to load a crossbow.
    static let loadTime = 1.25
    static let blockAngle = -0.2
}

extension GameSession {
    var selectedItemName: String? { inventory.selectedStack.flatMap { items[$0.item]?.name } }

    /// Whether the selected crossbow has a bolt in it.
    var crossbowLoaded: Bool {
        selectedItemName == Weapons.crossbow && (inventory.selectedStack?.damage ?? 0) > 0
    }

    /// Hold-to-use weapons (bow, spear, crossbow, shield). Returns true when the selected item is one of them.
    func handleHeldWeapon(_ input: GameInput, use: InputBinding, dt: Double) -> Bool {
        guard let name = selectedItemName else { blocking = false; return false }
        switch name {
        case Quests.book:
            blocking = false
            if input.wasPressed(use) { onOpenQuestBook?() }
            return true
        case "bow", Weapons.spear:
            blocking = false
            // Hold to draw (full power after a second), release to shoot or throw.
            if input.isDown(use) {
                if !drawingBow && input.wasPressed(use) {
                    if name == Weapons.spear || hasArrows { drawingBow = true; bowCharge = 0 }
                    else { onToast?("You need arrows to shoot the bow") }
                }
                if drawingBow { bowCharge = min(1, bowCharge + dt * (name == Weapons.spear ? 1.3 : 1)) }
            } else if drawingBow {
                if bowCharge > 0.15 {
                    if name == Weapons.spear { throwSpear(power: bowCharge) } else { fireBow(power: bowCharge) }
                }
                drawingBow = false
                bowCharge = 0
            }
            return true
        case Weapons.crossbow:
            blocking = false
            if crossbowLoaded {
                bowCharge = 1
                if input.wasPressed(use) { fireCrossbow() }
            } else if input.isDown(use) {
                if !drawingBow && input.wasPressed(use) {
                    if hasArrows { drawingBow = true; bowCharge = 0; onSound?("place_wood", 0.4, 1.6) }
                    else { onToast?("You need arrows to load the crossbow") }
                }
                if drawingBow {
                    bowCharge = min(1, bowCharge + dt / Weapons.loadTime)
                    if bowCharge >= 1 { loadCrossbow() }
                }
            } else {
                drawingBow = false
                bowCharge = 0
            }
            return true
        case Weapons.shield:
            drawingBow = false
            bowCharge = 0
            blocking = input.isDown(use) && !player.isSwimming
            return true
        default:
            blocking = false
            return false
        }
    }

    /// Takes one arrow from the inventory (none in Creative). Returns false when there are none.
    private func takeArrow() -> Bool {
        guard player.gameMode == .survival else { return true }
        guard let i = inventory.slots.firstIndex(where: { $0.flatMap { items[$0.item]?.name } == "arrow" }), var st = inventory.slots[i] else { return false }
        st.count -= 1
        inventory.slots[i] = st.count > 0 ? st : nil
        inventory.markChanged()
        return true
    }

    private func loadCrossbow() {
        drawingBow = false
        guard takeArrow(), var st = inventory.selectedStack else { return }
        st.damage = 1
        inventory.slots[inventory.selected] = st
        inventory.markChanged()
        onSound?("place_metal", 0.6, 1.3)
    }

    private func fireCrossbow() {
        guard var st = inventory.selectedStack else { return }
        st.damage = 0
        inventory.slots[inventory.selected] = st
        inventory.markChanged()
        bowCharge = 0
        let dir = player.lookDirection
        arrows.fire(from: player.eyePosition + dir * 0.5 - DVec3(0, 0.08, 0), velocity: dir * 62,
                    damage: 10 * (1 + 0.25 * heldEnchantLevel(.power)), pickup: player.gameMode == .survival, kind: .bolt)
        swing()
        onSound?("bow_shoot", 0.8, 0.7)
        advancements.record("shoot", "crossbow")
        exhaustion += 0.05
    }

    private func throwSpear(power: Double) {
        guard let st = inventory.selectedStack else { return }
        let survival = player.gameMode == .survival
        if survival {
            inventory.slots[inventory.selected] = nil
            inventory.markChanged()
        }
        let dir = player.lookDirection
        arrows.fire(from: player.eyePosition + dir * 0.6 - DVec3(0, 0.05, 0), velocity: dir * (10 + 22 * power),
                    damage: ((3 + 9 * power) * (1 + 0.25 * heldEnchantLevel(.power))).rounded(), pickup: survival, kind: .spear, carried: survival ? st : nil)
        swing()
        onSound?("bow_shoot", 0.7, 0.55)
        advancements.record("shoot", "spear")
        exhaustion += 0.1
    }

    /// A spear that hit a creature falls to the ground beside it.
    func dropThrownSpear(_ arrow: Arrow, at position: DVec3) {
        guard arrow.kind == .spear, let stack = arrow.carried else { return }
        entities.spawnItem(stack, at: position + DVec3(0, 0.5, 0), velocity: DVec3(0, 2, 0), pickupDelay: 0.5)
    }

    /// Picking a stuck spear or bolt back up.
    func pickUpProjectile(_ a: Arrow) -> Bool {
        switch a.kind {
        case .spear:
            guard let stack = a.carried else { return true }
            return inventory.add(stack) == 0
        case .arrow, .bolt:
            guard let arrowID = items.id(named: "arrow") else { return true }
            return inventory.add(ItemStack(item: arrowID, count: 1)) == 0
        }
    }

    /// Blocks a hit with a raised shield if it comes from in front. `from` points from the attacker toward you.
    func blockWithShield(_ amount: Double, from direction: DVec3?) -> Bool {
        guard blocking, selectedItemName == Weapons.shield, let direction else { return false }
        let look = player.lookDirection
        let flatLook = simd_length(DVec3(look.x, 0, look.z)) > 0.01 ? simd_normalize(DVec3(look.x, 0, look.z)) : DVec3(0, 0, -1)
        let flatHit = simd_length(DVec3(direction.x, 0, direction.z)) > 0.01 ? simd_normalize(DVec3(direction.x, 0, direction.z)) : -flatLook
        guard simd_dot(flatLook, flatHit) < Weapons.blockAngle else { return false }
        onSound?("hit_wood", 0.9, 0.8)
        effectBursts.append((player.eyePosition + flatLook * 0.6, .dust))
        player.velocity += DVec3(flatHit.x * 2, 0, flatHit.z * 2)
        if player.gameMode == .survival && inventory.damageSelectedTool(max(1, Int(amount.rounded()))) {
            onSound?("tool_break", 0.8, 1)
            onToast?("Your shield broke!")
            blocking = false
        }
        advancements.record("block")
        return true
    }
}
