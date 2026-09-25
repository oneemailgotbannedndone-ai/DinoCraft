import Foundation
import QuartzCore
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Joins a friend's hosted world: receives chunks, block edits, players,
/// creatures and dropped items, and sends this player's state and actions.
final class GameClient: SessionNetwork {
    let isClient = true
    let connection: NetConnection
    let username: String
    let label: String
    private(set) var playerID = -1
    private var players: [Int: RemotePlayer] = [:]
    private var stateTimer = 0.0
    private(set) var chunksReceived = 0
    weak var session: GameSession?

    /// This player's `PlayerIdentity` ID and look, sent in the hello.
    var playerIdentity: (id: String, look: String) = ("", "")
    /// Where the host was reached, remembered for the friends list.
    var address: String?
    var onWelcome: ((WelcomeMessage) -> Void)?
    var onDisconnect: ((String) -> Void)?
    var onChat: ((String, String) -> Void)?

    var remotePlayers: [RemotePlayer] { Array(players.values) }

    init(connection: NetConnection, username: String, label: String) {
        self.connection = connection
        self.username = username
        self.label = label
    }

    func connect() {
        connection.onReady = { [weak self] in
            guard let self else { return }
            Log.info("Connected to \(self.label); saying hello as \(self.username)", category: "Net")
            self.connection.send(.hello, HelloMessage(version: NetConfig.protocolVersion, username: self.username,
                                                      playerID: self.playerIdentity.id, look: self.playerIdentity.look))
        }
        connection.onMessage = { [weak self] type, data in self?.handle(type, data) }
        connection.onChunk = { [weak self] chunk in
            guard let self else { return }
            self.chunksReceived += 1
            if self.chunksReceived == 1 || self.chunksReceived % 100 == 0 { Log.info("Received \(self.chunksReceived) chunks from host", category: "Net") }
            self.session?.world.receiveRemoteChunk(chunk)
        }
        connection.onClose = { [weak self] reason in self?.onDisconnect?(reason) }
        connection.start()
    }

    private func handle(_ type: MessageType, _ data: Data) {
        switch type {
        case .welcome:
            guard let w = NetConnection.decode(WelcomeMessage.self, data) else { return }
            playerID = w.playerID
            for p in w.players {
                players[p.id] = RemotePlayer(id: p.id, name: p.name, position: DVec3(w.x, w.y, w.z))
                FriendList.shared.met(id: p.playerID, name: p.name, look: p.look, address: p.id == 0 ? address : nil, myID: playerIdentity.id)
            }
            Log.info("Joined '\(w.worldName)' as player \(w.playerID) with \(w.players.count) other player(s)", category: "Net")
            onWelcome?(w)
        case .reject:
            let reason = NetConnection.decode(RejectMessage.self, data)?.reason ?? "The host refused the connection."
            onDisconnect?(reason)
            connection.close()
        case .playerJoined:
            guard let p = NetConnection.decode(PlayerInfo.self, data) else { return }
            players[p.id] = RemotePlayer(id: p.id, name: p.name, position: session?.player.position ?? .zero)
            let friend = FriendList.shared.met(id: p.playerID, name: p.name, look: p.look, address: nil, myID: playerIdentity.id)
            onChat?("", friend ? "Your friend \(p.name) joined the game!" : "\(p.name) joined the game")
        case .playerLeft:
            guard let p = NetConnection.decode(PlayerInfo.self, data) else { return }
            players.removeValue(forKey: p.id)
            onChat?("", "\(p.name) left the game")
        case .playerState:
            guard let st = NetConnection.decode(PlayerStateMessage.self, data), st.id != playerID else { return }
            let player = players[st.id] ?? RemotePlayer(id: st.id, name: "Explorer", position: DVec3(st.x, st.y, st.z))
            players[st.id] = player
            player.apply(st, now: CACurrentMediaTime())
        case .blockChange:
            guard let m = NetConnection.decode(BlockChangeMessage.self, data) else { return }
            session?.world.setBlock(BlockPos(m.x, m.y, m.z), m.id)
        case .chat:
            guard let m = NetConnection.decode(ChatMessage.self, data) else { return }
            onChat?(m.from, m.text)
        case .mobSnapshot:
            guard let m = NetConnection.decode(MobSnapshotMessage.self, data) else { return }
            session?.mobs.mirror(m)
        case .itemSnapshot:
            guard let m = NetConnection.decode(ItemSnapshotMessage.self, data), let s = session else { return }
            s.entities.mirror(m, items: s.items)
        case .damage:
            guard let m = NetConnection.decode(DamageMessage.self, data) else { return }
            session?.takeDamage(m.amount, cause: m.cause, knockback: DVec3(m.kx, 0, m.kz))
            if m.cause.hasPrefix("Slain by ") { session?.noteCombat(with: String(m.cause.dropFirst(9))) }
        case .giveItem:
            guard let m = NetConnection.decode(GiveItemMessage.self, data) else { return }
            session?.receiveItem(name: m.item, count: m.count, damage: m.damage)
        case .worldTime:
            guard let m = NetConnection.decode(WorldTimeMessage.self, data) else { return }
            session?.debugSetTime(m.time)
            if let w = m.weather.flatMap({ WeatherKind(rawValue: $0) }) { session?.weather.mirror(w) }
        case .dimensionChange:
            guard let m = NetConnection.decode(DimensionChangeMessage.self, data), let dim = WorldDimension(rawValue: m.dimension) else { return }
            session?.followDimension(dim, position: DVec3(m.x, m.y, m.z))
        case .containerData:
            guard let m = NetConnection.decode(ContainerDataMessage.self, data), let s = session else { return }
            s.containers.apply(m, items: s.items)
        case .disconnect:
            onDisconnect?("The host closed the game.")
            connection.close()
        default:
            break
        }
    }

    func tick(dt: Double) {
        for p in players.values { p.update(dt: dt) }
        guard let s = session, !s.isLoading else { return }
        s.mobs.updateMirrors(dt: dt)
        s.entities.updateMirrors(dt: dt)
        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            connection.send(.playerState, s.localPlayerState(id: playerID))
        }
    }

    func requestChunks(_ list: [ChunkPos]) {
        connection.send(.chunkRequest, ChatlessChunkRequest.make(list))
    }

    func sendChat(_ text: String) {
        connection.send(.chat, ChatMessage(from: username, text: text))
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

enum ChatlessChunkRequest {
    static func make(_ list: [ChunkPos]) -> ChunkRequestMessage {
        ChunkRequestMessage(chunks: list.map { [$0.x, $0.z] })
    }
}
