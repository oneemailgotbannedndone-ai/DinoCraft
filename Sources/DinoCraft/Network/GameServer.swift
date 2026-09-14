import Foundation
import Network
import QuartzCore
import simd
import DinoCraftCore
@testable import DinoCraftGame

/// Hooks the game session uses to talk to the network, implemented by the
/// host (`GameServer`) and by clients (`GameClient`).

enum NetworkInfo {
    /// This Mac's LAN IPv4 address (Wi-Fi or Ethernet), if any.
    static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [(String, String)] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            if let addr = p.pointee.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
               flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    candidates.append((String(cString: p.pointee.ifa_name), String(cString: host)))
                }
            }
            ptr = p.pointee.ifa_next
        }
        return (candidates.first { $0.0.hasPrefix("en") } ?? candidates.first)?.1
    }
}

/// Hosts the current world for friends: listens on TCP (advertised over
/// Bonjour), serves chunks, and keeps blocks, players, creatures and dropped
/// items in sync. The host's session stays authoritative.
final class GameServer: SessionNetwork {
    final class Peer {
        let id: Int
        let connection: NetConnection
        var name = "?"
        var joined = false
        var player: RemotePlayer?
        init(id: Int, connection: NetConnection) {
            self.id = id
            self.connection = connection
        }
    }

    let isClient = false
    private weak var session: GameSession?
    let hostName: String
    let port: UInt16
    private var listener: NWListener?
    private var peers: [Int: Peer] = [:]
    private var nextID = 1
    private var stateTimer = 0.0, mobTimer = 0.0, itemTimer = 0.0, timeTimer = 0.0, containerTimer = 0.0
    private let chunkQueue = DispatchQueue(label: "com.dinocraft.server.chunks", qos: .userInitiated, attributes: .concurrent)

    var onEvent: ((String) -> Void)?
    var onChat: ((String, String) -> Void)?

    var remotePlayers: [RemotePlayer] { peers.values.filter { $0.joined }.compactMap { $0.player } }
    var playerCount: Int { remotePlayers.count + 1 }

    init(session: GameSession, hostName: String, port: UInt16 = NetConfig.port) {
        self.session = session
        self.hostName = hostName
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options { tcp.noDelay = true }
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw NSError(domain: "DinoCraft", code: 1) }
        let listener = try NWListener(using: params, on: nwPort)
        listener.service = NWListener.Service(name: "\(hostName) · \(session?.meta.name ?? "DinoCraft")", type: NetConfig.bonjourType)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                Log.info("Hosting on port \(self?.port ?? 0)", category: "Net")
            case .failed(let error):
                Log.error("Server failed: \(error)", category: "Net")
                self?.onEvent?("Hosting failed: \(error.localizedDescription)")
            default:
                break
            }
        }
        listener.start(queue: .main)
        self.listener = listener
        session?.blockObserver = { [weak self] pos, id in self?.broadcastBlock(pos, id) }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for p in peers.values { p.connection.close() }
        peers.removeAll()
        session?.blockObserver = nil
        Log.info("Stopped hosting", category: "Net")
    }

    private func accept(_ nw: NWConnection) {
        let id = nextID
        nextID += 1
        let connection = NetConnection(connection: nw, label: "player \(id)")
        let peer = Peer(id: id, connection: connection)
        peers[id] = peer
        connection.onMessage = { [weak self, weak peer] type, data in
            guard let self, let peer else { return }
            self.handle(peer, type, data)
        }
        connection.onClose = { [weak self] reason in self?.drop(id, reason: reason) }
        connection.start()
        Log.info("Incoming connection \(id) from \(nw.endpoint)", category: "Net")
    }

    private func drop(_ id: Int, reason: String) {
        guard let peer = peers.removeValue(forKey: id) else { return }
        Log.info("Player \(peer.name) disconnected: \(reason)", category: "Net")
        guard peer.joined else { return }
        broadcast(.playerLeft, PlayerInfo(id: id, name: peer.name))
        onChat?("", "\(peer.name) left the game")
    }

    private func broadcast<T: Encodable>(_ type: MessageType, _ value: T, except: Int? = nil) {
        guard let payload = try? NetCodec.encoder.encode(value) else { return }
        for p in peers.values where p.joined && p.id != except { p.connection.sendRaw(type, payload) }
    }

    /// Sends items to a connected player by name (used by /give). Returns false if nobody matches.
    func give(playerNamed name: String, item: String, count: Int) -> Bool {
        guard let peer = peers.values.first(where: { $0.joined && $0.name.lowercased() == name.lowercased() }) else { return false }
        var left = count
        while left > 0 {
            let batch = min(64, left)
            peer.connection.send(.giveItem, GiveItemMessage(item: item, count: batch, damage: 0))
            left -= batch
        }
        return true
    }

    func broadcastChat(from: String, text: String) {
        broadcast(.chat, ChatMessage(from: from, text: text))
    }

    private func broadcastBlock(_ pos: BlockPos, _ id: BlockID) {
        broadcast(.blockChange, BlockChangeMessage(x: pos.x, y: pos.y, z: pos.z, id: id, harvest: nil))
    }

    // MARK: Messages

    private func handle(_ peer: Peer, _ type: MessageType, _ data: Data) {
        guard let s = session else { return }
        switch type {
        case .hello:
            guard !peer.joined, let hello = NetConnection.decode(HelloMessage.self, data) else { return }
            guard hello.version == NetConfig.protocolVersion else {
                peer.connection.send(.reject, RejectMessage(reason: "This game uses a different DinoCraft version."))
                peer.connection.close()
                return
            }
            var base = String(hello.username.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(16))
            if base.isEmpty { base = "Explorer" }
            let taken = Set(peers.values.filter { $0.joined }.map { $0.name.lowercased() } + [hostName.lowercased()])
            var name = base
            var n = 2
            while taken.contains(name.lowercased()) { name = "\(base)\(n)"; n += 1 }
            peer.name = name
            peer.joined = true
            let spawn = s.player.position + DVec3(Double.random(in: -1.5...1.5), 0.1, Double.random(in: -1.5...1.5))
            peer.player = RemotePlayer(id: peer.id, name: name, position: spawn)
            let others = [PlayerInfo(id: 0, name: hostName)] + peers.values.filter { $0.joined && $0.id != peer.id }.map { PlayerInfo(id: $0.id, name: $0.name) }
            peer.connection.send(.welcome, WelcomeMessage(playerID: peer.id, worldName: s.meta.name, seed: s.meta.seed,
                                                          dimension: s.dimension.rawValue, gameMode: s.meta.gameMode.rawValue,
                                                          difficulty: s.meta.difficulty.rawValue, hardcore: false,
                                                          x: spawn.x, y: spawn.y, z: spawn.z, worldTime: s.worldTime, players: others))
            broadcast(.playerJoined, PlayerInfo(id: peer.id, name: name), except: peer.id)
            onChat?("", "\(name) joined the game")
            Log.info("\(name) joined (player \(peer.id))", category: "Net")

        case .chunkRequest:
            guard peer.joined, let request = NetConnection.decode(ChunkRequestMessage.self, data) else { return }
            serveChunks(request.chunks.prefix(128).compactMap { $0.count == 2 ? ChunkPos($0[0], $0[1]) : nil }, to: peer)

        case .blockChange:
            guard peer.joined, let m = NetConnection.decode(BlockChangeMessage.self, data) else { return }
            s.applyRemoteBlockChange(BlockPos(m.x, m.y, m.z), m.id, harvest: m.harvest ?? false)

        case .playerState:
            guard peer.joined, var state = NetConnection.decode(PlayerStateMessage.self, data) else { return }
            state.id = peer.id
            peer.player?.apply(state, now: CACurrentMediaTime())
            broadcast(.playerState, state, except: peer.id)

        case .chat:
            guard peer.joined, let m = NetConnection.decode(ChatMessage.self, data) else { return }
            let text = String(m.text.prefix(200))
            broadcast(.chat, ChatMessage(from: peer.name, text: text))
            onChat?(peer.name, text)

        case .spawnMob:
            guard peer.joined, let m = NetConnection.decode(SpawnMobMessage.self, data), let kind = MobKind(rawValue: m.kind),
                  simd_distance(DVec3(m.x, m.y, m.z), peer.player?.position ?? DVec3(m.x, m.y, m.z)) < 16 else { return }
            let spot = DVec3(m.x, m.y, m.z)
            let mob = s.mobs.spawn(kind, at: spot)
            if kind == .villager { mob.home = spot }
            Log.info("\(peer.name) hatched a \(mob.species.displayName)", category: "Net")

        case .attackMob:
            guard peer.joined, let m = NetConnection.decode(AttackMobMessage.self, data),
                  let mob = s.mobs.mobs.first(where: { $0.id == m.mob }) else { return }
            s.mobs.hurt(mob, amount: min(m.damage, 40), knockback: DVec3(m.kx, 0, m.kz), session: s)

        case .attackPlayer:
            guard peer.joined, let m = NetConnection.decode(AttackPlayerMessage.self, data) else { return }
            let damage = min(m.damage, 40)
            if m.target == 0 {
                s.takeDamage(damage, cause: "Slain by \(peer.name)", knockback: DVec3(m.kx, 0, m.kz))
                s.noteCombat(with: peer.name)
            } else if let target = peers[m.target], target.joined {
                target.connection.send(.damage, DamageMessage(amount: damage, cause: "Slain by \(peer.name)", kx: m.kx, kz: m.kz))
            }

        case .dropItem:
            guard peer.joined, let m = NetConnection.decode(DropItemMessage.self, data), let id = s.items.id(named: m.item) else { return }
            s.entities.spawnItem(ItemStack(item: id, count: max(1, min(64, m.count)), damage: m.damage), at: DVec3(m.x, m.y, m.z),
                                 velocity: DVec3(m.vx, m.vy, m.vz), pickupDelay: 1.5)

        case .containerOpen:
            guard peer.joined, let m = NetConnection.decode(ContainerPosMessage.self, data) else { return }
            let pos = BlockPos(m.x, m.y, m.z)
            guard let kind = s.variants.containerKind(s.world.block(pos)) else { return }
            s.prepareContainer(at: pos, kind: kind)
            if let msg = s.containers.message(for: pos, items: s.items) { peer.connection.send(.containerData, msg) }

        case .containerSet:
            guard peer.joined, let m = NetConnection.decode(ContainerSetMessage.self, data) else { return }
            let pos = BlockPos(m.x, m.y, m.z)
            guard let kind = s.variants.containerKind(s.world.block(pos)) else { return }
            let c = s.containers.ensure(pos, kind: kind)
            c.slots = ContainerManager.stacks(m.slots, count: kind.slotCount, items: s.items)
            s.containers.dirty.insert(pos)

        case .disconnect:
            peer.connection.close()

        default:
            break
        }
    }

    private func serveChunks(_ positions: [ChunkPos], to peer: Peer) {
        guard let s = session else { return }
        let world = s.world
        var missing: [ChunkPos] = []
        for pos in positions {
            if let slot = world.slot(at: pos) {
                let copy = Chunk(pos: pos)
                copy.blocks.update(from: slot.chunk.blocks, count: WorldConst.blocksPerChunk)
                chunkQueue.async {
                    if let payload = try? NetCodec.chunkPayload(copy) { peer.connection.sendRaw(.chunkData, payload) }
                }
            } else {
                missing.append(pos)
            }
        }
        guard !missing.isEmpty else { return }
        let storage = s.storage, worldID = s.meta.id, generator = world.generator, folder = generator.dimension.storageFolder
        for pos in missing {
            chunkQueue.async {
                let chunk = storage.loadChunk(worldID: worldID, pos: pos, dimension: folder) ?? generator.generate(pos)
                if let payload = try? NetCodec.chunkPayload(chunk) { peer.connection.sendRaw(.chunkData, payload) }
            }
        }
    }

    // MARK: Tick

    func tick(dt: Double) {
        guard let s = session, !s.isLoading else { return }
        for p in remotePlayers { p.update(dt: dt) }

        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            broadcast(.playerState, s.localPlayerState(id: 0))
        }
        mobTimer -= dt
        if mobTimer <= 0 {
            mobTimer = 0.1
            broadcast(.mobSnapshot, s.mobs.snapshot())
        }
        itemTimer -= dt
        if itemTimer <= 0 {
            itemTimer = 0.2
            for peer in peers.values where peer.joined {
                guard let p = peer.player, !p.dead else { continue }
                for stack in s.entities.collect(near: p.position + DVec3(0, 0.8, 0), radius: 1.4) {
                    guard let name = s.items[stack.item]?.name else { continue }
                    peer.connection.send(.giveItem, GiveItemMessage(item: name, count: stack.count, damage: stack.damage))
                }
            }
            broadcast(.itemSnapshot, s.entities.snapshot(items: s.items))
        }
        containerTimer -= dt
        if containerTimer <= 0 {
            containerTimer = 0.2
            for pos in s.containers.dirty {
                if let m = s.containers.message(for: pos, items: s.items) { broadcast(.containerData, m) }
            }
            s.containers.dirty.removeAll()
        }
        timeTimer -= dt
        if timeTimer <= 0 {
            timeTimer = 2
            broadcast(.worldTime, WorldTimeMessage(time: s.worldTime, weather: s.weather.kind.rawValue))
        }
    }

    // MARK: SessionNetwork

    func blockChanged(_ pos: BlockPos, _ id: BlockID, harvest: Bool) {}
    func attackMob(_ mob: Mob, damage: Double, knockback: DVec3) -> Bool { false }
    func dropItem(_ stack: ItemStack, at position: DVec3, velocity: DVec3) -> Bool { false }
    func containerOpened(_ pos: BlockPos) {}
    func spawnMob(_ kind: MobKind, at position: DVec3) -> Bool { false }
    func containerChanged(_ pos: BlockPos, _ container: Container) {}

    func attackPlayer(_ player: RemotePlayer, damage: Double, knockback: DVec3) {
        guard let peer = peers[player.id], peer.joined else { return }
        peer.connection.send(.damage, DamageMessage(amount: damage, cause: "Slain by \(hostName)", kx: knockback.x, kz: knockback.z))
    }

    func damageRemotePlayer(id: Int, amount: Double, cause: String, knockback: DVec3) {
        guard let peer = peers[id], peer.joined else { return }
        peer.connection.send(.damage, DamageMessage(amount: amount, cause: cause, kx: knockback.x, kz: knockback.z))
    }

    func dimensionChanged(_ dimension: WorldDimension, position: DVec3) {
        broadcast(.dimensionChange, DimensionChangeMessage(dimension: dimension.rawValue, x: position.x, y: position.y, z: position.z))
        for p in remotePlayers {
            p.position = position
            p.targetPosition = position
        }
    }
}
