import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// Playing on a friend's world with the full shared game, like the Mac's `GameClient`: chunks, block
/// edits, players, creatures, items, chests and chat come from the host, and this player's moves and
/// actions go back. The messages are the same on both computers, so Windows and Mac can play together.
final class WinSessionClient: SessionNetwork {
    let isClient = true
    let connection: WireConnection
    let welcome: WelcomeMessage
    let username: String
    let playerID: Int
    private let myIdentity: String
    private var players: [Int: RemotePlayer] = [:]
    private var pending: [WireConnection.Event]
    private var stateTimer = 0.0
    private var chunksReceived = 0
    private let decoder = JSONDecoder()
    weak var session: GameSession?
    var onChat: ((String, String) -> Void)?
    /// Why the game ended (set once the host goes away).
    private(set) var disconnectReason: String?

    var remotePlayers: [RemotePlayer] { Array(players.values) }

    init?(joined network: WinNetwork) {
        connection = network.connection
        username = network.username
        myIdentity = network.playerIdentityID
        pending = network.takePendingEvents()
        guard let data = try? JSONEncoder().encode(network.welcome),
              let w = try? JSONDecoder().decode(WelcomeMessage.self, from: data) else { return nil }
        welcome = w
        playerID = w.playerID
        for p in w.players { players[p.id] = RemotePlayer(id: p.id, name: p.name, position: DVec3(w.x, w.y, w.z)) }
        for p in w.players { players[p.id]?.look = p.look }
    }

    /// The world as this player sees it: named after the host's world, with the host's rules.
    var meta: WorldMetadata {
        let w = welcome, now = Date()
        return WorldMetadata(formatVersion: w.deep == true ? WorldMetadata.currentFormat : 1, id: "remote", name: w.worldName, seedText: w.seed,
                             seed: w.seed, gameMode: GameMode(rawValue: w.gameMode) ?? .survival,
                             difficulty: Difficulty(rawValue: w.difficulty) ?? .normal, createdAt: now, lastPlayed: now, playTimeSeconds: 0,
                             worldTime: w.worldTime, spawnX: Int(floor(w.x)), spawnY: Int(floor(w.y)), spawnZ: Int(floor(w.z)),
                             hardcore: w.hardcore ? true : nil, hardcoreDead: w.spectator == true ? true : nil)
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? { try? decoder.decode(type, from: data) }

    /// Handles everything the host sent, and sends this player's state 20 times a second.
    func tick(dt: Double) {
        let events = pending + connection.poll()
        pending.removeAll()
        for event in events {
            switch event {
            case .chunk(let chunk):
                chunksReceived += 1
                if chunksReceived == 1 || chunksReceived % 100 == 0 { Log.info("Received \(chunksReceived) chunks from host", category: "Net") }
                session?.world.receiveRemoteChunk(chunk)
            case .closed(let reason):
                if disconnectReason == nil { disconnectReason = reason }
            case .message(let kind, let data):
                handle(kind, data)
            }
        }
        for p in players.values { p.update(dt: dt) }
        guard let s = session, !s.isLoading, disconnectReason == nil else { return }
        s.mobs.updateMirrors(dt: dt)
        s.entities.updateMirrors(dt: dt)
        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            connection.send(.playerState, s.localPlayerState(id: playerID))
        }
    }

    private func handle(_ kind: Wire.Kind, _ data: Data) {
        switch kind {
        case .playerJoined:
            guard let p = decode(PlayerInfo.self, data) else { return }
            let player = RemotePlayer(id: p.id, name: p.name, position: session?.player.position ?? .zero)
            player.look = p.look
            players[p.id] = player
            let friend = FriendList.shared.met(id: p.playerID, name: p.name, look: p.look, address: nil, myID: myIdentity)
            onChat?("", friend ? "Your friend \(p.name) joined the game!" : "\(p.name) joined the game")
        case .playerLeft:
            guard let p = decode(PlayerInfo.self, data) else { return }
            players.removeValue(forKey: p.id)
            onChat?("", "\(p.name) left the game")
        case .playerState:
            guard let st = decode(PlayerStateMessage.self, data), st.id != playerID else { return }
            let player = players[st.id] ?? RemotePlayer(id: st.id, name: "Explorer", position: DVec3(st.x, st.y, st.z))
            players[st.id] = player
            player.apply(st, now: Date.timeIntervalSinceReferenceDate)
        case .blockChange:
            guard let m = decode(BlockChangeMessage.self, data) else { return }
            session?.world.setBlock(BlockPos(m.x, m.y, m.z), m.id)
        case .chat:
            guard let m = decode(ChatMessage.self, data) else { return }
            if m.to != nil { onChat?("", "\(m.from) whispers to you: \(m.text)") } else { onChat?(m.from, m.text) }
        case .mobSnapshot:
            guard let m = decode(MobSnapshotMessage.self, data) else { return }
            session?.mobs.mirror(m)
        case .itemSnapshot:
            guard let m = decode(ItemSnapshotMessage.self, data), let s = session else { return }
            s.entities.mirror(m, items: s.items)
        case .damage:
            guard let m = decode(DamageMessage.self, data) else { return }
            session?.takeDamage(m.amount, cause: m.cause, knockback: DVec3(m.kx, 0, m.kz))
            if m.cause.hasPrefix("Slain by ") { session?.noteCombat(with: String(m.cause.dropFirst(9))) }
        case .giveItem:
            guard let m = decode(GiveItemMessage.self, data) else { return }
            session?.receiveItem(name: m.item, count: m.count, damage: m.damage)
        case .worldTime:
            guard let m = decode(WorldTimeMessage.self, data) else { return }
            session?.debugSetTime(m.time)
            if let w = m.weather.flatMap({ WeatherKind(rawValue: $0) }) { session?.weather.mirror(w) }
        case .dimensionChange:
            guard let m = decode(DimensionChangeMessage.self, data), let dim = WorldDimension(rawValue: m.dimension) else { return }
            session?.followDimension(dim, position: DVec3(m.x, m.y, m.z))
        case .containerData:
            guard let m = decode(ContainerDataMessage.self, data), let s = session else { return }
            s.containers.apply(m, items: s.items)
        case .disconnect:
            if disconnectReason == nil { disconnectReason = "The host closed the game." }
            connection.close()
        default:
            break
        }
    }

    func requestChunks(_ list: [ChunkPos]) {
        connection.send(.chunkRequest, ChatlessChunkRequest.make(list))
    }

    func sendChat(_ text: String, to: String? = nil) {
        connection.send(.chat, ChatMessage(from: username, text: text, to: to))
    }

    func leave() {
        connection.close()
    }

    // MARK: SessionNetwork

    func blockChanged(_ pos: BlockPos, _ id: BlockID, harvest: Bool) {
        connection.send(.blockChange, BlockChangeMessage(x: pos.x, y: pos.y, z: pos.z, id: id, harvest: harvest))
    }

    func attackMob(_ mob: Mob, damage: Double, knockback: DVec3) -> Bool {
        guard let remote = mob.remoteID else { return true }
        connection.send(.attackMob, AttackMobMessage(mob: remote, damage: damage, kx: knockback.x, kz: knockback.z))
        mob.hurtTimer = 0.35
        return true
    }

    func attackPlayer(_ player: RemotePlayer, damage: Double, knockback: DVec3) {
        connection.send(.attackPlayer, AttackPlayerMessage(target: player.id, damage: damage, kx: knockback.x, kz: knockback.z))
    }

    func dropItem(_ stack: ItemStack, at position: DVec3, velocity: DVec3) -> Bool {
        guard let name = session?.items[stack.item]?.name else { return true }
        connection.send(.dropItem, DropItemMessage(item: name, count: stack.count, damage: stack.damage,
                                                   x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z))
        return true
    }

    func damageRemotePlayer(id: Int, amount: Double, cause: String, knockback: DVec3) {}

    func spawnMob(_ kind: MobKind, at position: DVec3) -> Bool {
        connection.send(.spawnMob, SpawnMobMessage(kind: kind.rawValue, x: position.x, y: position.y, z: position.z))
        return true
    }

    func containerOpened(_ pos: BlockPos) {
        connection.send(.containerOpen, ContainerPosMessage(x: pos.x, y: pos.y, z: pos.z))
    }

    func containerChanged(_ pos: BlockPos, _ container: Container) {
        guard let items = session?.items else { return }
        connection.send(.containerSet, ContainerSetMessage(x: pos.x, y: pos.y, z: pos.z, slots: ContainerManager.netSlots(container.slots, items: items)))
    }

    func dimensionChanged(_ dimension: WorldDimension, position: DVec3) {}
}
