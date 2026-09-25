import Foundation
import DinoCraftCore

/// DinoCraft multiplayer wire protocol.
///
/// Framing: `[UInt32 little-endian length][UInt8 type][payload]` where length
/// covers the type byte and payload. Control messages are JSON; chunk data is
/// a compact binary header followed by the LZFSE chunk blob.
enum NetConfig {
    static let port: UInt16 = 25650
    static let bonjourType = "_dinocraft._tcp"
    static let protocolVersion = 1
    static let maxFrame = 8 * 1024 * 1024
}

enum MessageType: UInt8 {
    case hello = 1
    case welcome
    case reject
    case chunkRequest
    case chunkData
    case blockChange
    case playerState
    case playerJoined
    case playerLeft
    case chat
    case mobSnapshot
    case itemSnapshot
    case attackPlayer
    case attackMob
    case dropItem
    case giveItem
    case damage
    case worldTime
    case dimensionChange
    case disconnect
    case containerOpen
    case containerData
    case containerSet
    case spawnMob
    /// "What are you playing?" — answered without joining, for the friends list.
    case status
}

struct HelloMessage: Codable {
    var version: Int
    var username: String
    /// The player's one-of-a-kind ID (`PlayerIdentity`) and look; older versions leave them out.
    var playerID: String? = nil
    var look: String? = nil
}

struct WelcomeMessage: Codable {
    var playerID: Int
    var worldName: String
    var seed: String
    var dimension: String
    var gameMode: String
    var difficulty: String
    var hardcore: Bool
    var x: Double, y: Double, z: Double
    var worldTime: Double
    var players: [PlayerInfo]
    /// Whether the host's overworld goes down to Y -70 (nil from older hosts: no).
    var deep: Bool? = nil
    /// Hardcore: this player already died here, so they can only spectate.
    var spectator: Bool? = nil
}

struct PlayerInfo: Codable {
    var id: Int
    var name: String
    var playerID: String? = nil
    var look: String? = nil
}

struct RejectMessage: Codable { var reason: String }

struct ChunkRequestMessage: Codable { var chunks: [[Int32]] }

struct BlockChangeMessage: Codable {
    var x: Int32, y: Int32, z: Int32
    var id: UInt8
    var harvest: Bool?
}

struct PlayerStateMessage: Codable {
    var id: Int
    var x: Double, y: Double, z: Double
    var yaw: Float, pitch: Float
    var moving: Float
    var sneaking: Bool
    var swinging: Bool
    var held: String?
    var health: Float
    var dead: Bool
    /// The player's cosmetics (`PlayerLook.encoded`); older versions leave it out.
    var look: String? = nil
}

struct ChatMessage: Codable {
    var from: String
    var text: String
    /// Set for a private message (`/msg`): who it's for.
    var to: String? = nil
}

struct MobState: Codable {
    var id: Int
    var kind: String
    var x: Double, y: Double, z: Double
    var yaw: Float
    var health: Float
    var maxHealth: Float
    var walk: Float
    var move: Float
    var hurt: Float
    var dying: Float
    var lunge: Float
    var variant: Int?
}

struct MobSnapshotMessage: Codable { var mobs: [MobState]; var spits: [[Double]] }

struct ItemState: Codable {
    var id: Int
    var item: String
    var count: Int
    var x: Double, y: Double, z: Double
}

struct ItemSnapshotMessage: Codable { var items: [ItemState] }

struct AttackPlayerMessage: Codable {
    var target: Int
    var damage: Double
    var kx: Double, kz: Double
}

struct AttackMobMessage: Codable {
    var mob: Int
    var damage: Double
    var kx: Double, kz: Double
}

struct DropItemMessage: Codable {
    var item: String
    var count: Int
    var damage: Int
    var x: Double, y: Double, z: Double
    var vx: Double, vy: Double, vz: Double
}

struct GiveItemMessage: Codable {
    var item: String
    var count: Int
    var damage: Int
}

struct DamageMessage: Codable {
    var amount: Double
    var cause: String
    var kx: Double, kz: Double
}

struct WorldTimeMessage: Codable {
    var time: Double
    var weather: String? = nil
}

struct NetStack: Codable {
    var item: String
    var count: Int
    var damage: Int?
}

struct ContainerPosMessage: Codable { var x: Int32, y: Int32, z: Int32 }

struct ContainerDataMessage: Codable {
    var x: Int32, y: Int32, z: Int32
    var kind: String
    var slots: [NetStack?]
    var burnLeft: Double, burnTotal: Double, cook: Double, cookTotal: Double
}

struct ContainerSetMessage: Codable {
    var x: Int32, y: Int32, z: Int32
    var slots: [NetStack?]
}

struct DimensionChangeMessage: Codable {
    var dimension: String
    var x: Double, y: Double, z: Double
}

struct SpawnMobMessage: Codable {
    var kind: String
    var x: Double, y: Double, z: Double
}
