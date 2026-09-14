import Foundation
import DinoCraftCore

/// What the game session needs from the multiplayer layer (host or client).
protocol SessionNetwork: AnyObject {
    var isClient: Bool { get }
    var remotePlayers: [RemotePlayer] { get }
    /// Client only: report a local block edit to the host.
    func blockChanged(_ pos: BlockPos, _ id: BlockID, harvest: Bool)
    /// Returns true when the attack was handed to the host.
    func attackMob(_ mob: Mob, damage: Double, knockback: DVec3) -> Bool
    func attackPlayer(_ player: RemotePlayer, damage: Double, knockback: DVec3)
    /// Returns true when the drop was handed to the host.
    func dropItem(_ stack: ItemStack, at position: DVec3, velocity: DVec3) -> Bool
    func damageRemotePlayer(id: Int, amount: Double, cause: String, knockback: DVec3)
    func dimensionChanged(_ dimension: WorldDimension, position: DVec3)
    func containerOpened(_ pos: BlockPos)
    func containerChanged(_ pos: BlockPos, _ container: Container)
    /// Client only: asks the host to hatch a spawn egg. Returns true when the request was sent.
    func spawnMob(_ kind: MobKind, at position: DVec3) -> Bool
}
