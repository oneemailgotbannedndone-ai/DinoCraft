import Foundation

/// A small `Wire` protocol host, used when a Windows player opens their world: it serves chunks
/// and relays players, block edits and chat. (The Mac app hosts with its own `GameServer`,
/// which also syncs creatures, items and containers.) Call `poll()` and `tick` from the game loop.
public final class WireHost: @unchecked Sendable {
    public struct Settings {
        public var worldName: String
        public var seed: String
        public var gameMode: String
        public var difficulty: String
        public var hostName: String

        public init(worldName: String, seed: String, gameMode: String, difficulty: String, hostName: String) {
            self.worldName = worldName; self.seed = seed; self.gameMode = gameMode; self.difficulty = difficulty; self.hostName = hostName
        }
    }

    public struct Player {
        public let id: Int
        public let name: String
        public let state: Wire.PlayerState?
    }

    private final class Peer {
        let id: Int
        let connection: WireConnection
        var name = "?"
        var joined = false
        var state: Wire.PlayerState?
        init(id: Int, connection: WireConnection) { self.id = id; self.connection = connection }
    }

    public let settings: Settings
    public let port: UInt16
    /// Game thread: a copy of an already-loaded chunk, or nil to use `makeChunk`.
    public var loadedChunk: (ChunkPos) -> Chunk? = { _ in nil }
    /// Background thread: loads a chunk from disk or generates it.
    public let makeChunk: @Sendable (ChunkPos) -> Chunk
    public var spawnPoint: () -> DVec3 = { .zero }
    public var worldTime: () -> Double = { 0 }
    /// Game thread: apply a player's block edit; return true to broadcast it.
    public var onBlockChange: (BlockPos, BlockID) -> Bool = { _, _ in true }
    public var onChat: (String, String) -> Void = { _, _ in }
    public var onEvent: (String) -> Void = { _ in }

    private let listener: NetSocket
    private let acceptLock = NSLock()
    private var accepted: [NetSocket] = []
    private var stopped = false
    private var peers: [Int: Peer] = [:]
    private var nextID = 1
    private var stateTimer = 0.0
    private var timeTimer = 0.0
    private let chunkQueue = DispatchQueue(label: "com.dinocraft.host.chunks", attributes: .concurrent)
    private let decoder = JSONDecoder()

    public init(settings: Settings, port: UInt16 = Wire.defaultPort, loopbackOnly: Bool = false,
                makeChunk: @escaping @Sendable (ChunkPos) -> Chunk) throws {
        self.settings = settings
        self.makeChunk = makeChunk
        listener = try NetSocket.listen(port: port, loopbackOnly: loopbackOnly)
        self.port = listener.localPort
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "DinoCraft Host"
        thread.start()
        Log.info("Hosting '\(settings.worldName)' on port \(self.port)", category: "Net")
    }

    public var players: [Player] {
        peers.values.filter { $0.joined }.map { Player(id: $0.id, name: $0.name, state: $0.state) }.sorted { $0.id < $1.id }
    }

    public var playerCount: Int { peers.values.filter { $0.joined }.count }

    private func acceptLoop() {
        while true {
            guard let socket = listener.accept() else { return }
            acceptLock.lock()
            let stop = stopped
            if !stop { accepted.append(socket) }
            acceptLock.unlock()
            if stop {
                socket.close()
                return
            }
        }
    }

    /// Accepts new players and handles every message received since the last call.
    public func poll() {
        acceptLock.lock()
        let fresh = accepted
        accepted.removeAll()
        acceptLock.unlock()
        for socket in fresh {
            let id = nextID
            nextID += 1
            peers[id] = Peer(id: id, connection: WireConnection(socket: socket, label: "player \(id)"))
            Log.info("Incoming connection \(id)", category: "Net")
        }
        for peer in Array(peers.values) {
            for event in peer.connection.poll() {
                switch event {
                case .closed(let reason): drop(peer, reason: reason)
                case .chunk: break
                case .message(let kind, let data): handle(peer, kind, data)
                }
            }
        }
    }

    /// Shares the host player's movement (id 0) and the time of day.
    public func tick(dt: Double, hostState: Wire.PlayerState) {
        stateTimer -= dt
        if stateTimer <= 0 {
            stateTimer = 0.05
            var state = hostState
            state.id = 0
            broadcast(.playerState, state)
        }
        timeTimer -= dt
        if timeTimer <= 0 {
            timeTimer = 2
            broadcast(.worldTime, Wire.WorldTime(time: worldTime()))
        }
    }

    public func broadcastBlock(_ pos: BlockPos, _ id: BlockID) {
        broadcast(.blockChange, Wire.BlockChange(pos: pos, id: id))
    }

    public func broadcastChat(from: String, text: String) {
        broadcast(.chat, Wire.Chat(from: from, text: String(text.prefix(200))))
    }

    public func stop() {
        acceptLock.lock()
        stopped = true
        acceptLock.unlock()
        for peer in peers.values { peer.connection.close() }
        peers.removeAll()
        listener.close()
        Log.info("Stopped hosting", category: "Net")
    }

    private func broadcast<T: Encodable>(_ kind: Wire.Kind, _ value: T, except: Int? = nil) {
        guard let payload = try? JSONEncoder().encode(value) else { return }
        for peer in peers.values where peer.joined && peer.id != except { peer.connection.sendRaw(kind, payload) }
    }

    private func drop(_ peer: Peer, reason: String) {
        guard peers.removeValue(forKey: peer.id) != nil else { return }
        peer.connection.close()
        Log.info("Player \(peer.name) disconnected: \(reason)", category: "Net")
        guard peer.joined else { return }
        broadcast(.playerLeft, Wire.PlayerInfo(id: peer.id, name: peer.name))
        onEvent("\(peer.name) left the game")
    }

    private func handle(_ peer: Peer, _ kind: Wire.Kind, _ data: Data) {
        switch kind {
        case .hello:
            guard !peer.joined, let hello = try? decoder.decode(Wire.Hello.self, from: data) else { return }
            guard hello.version == Wire.protocolVersion else {
                peer.connection.send(.reject, Wire.Reject(reason: "This game uses a different DinoCraft version."))
                peer.connection.close()
                return
            }
            var base = String(hello.username.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(16))
            if base.isEmpty { base = "Explorer" }
            let taken = Set(peers.values.filter { $0.joined }.map { $0.name.lowercased() } + [settings.hostName.lowercased()])
            var name = base
            var n = 2
            while taken.contains(name.lowercased()) {
                name = "\(base)\(n)"
                n += 1
            }
            peer.name = name
            peer.joined = true
            let spawn = spawnPoint()
            let others = [Wire.PlayerInfo(id: 0, name: settings.hostName)]
                + peers.values.filter { $0.joined && $0.id != peer.id }.map { Wire.PlayerInfo(id: $0.id, name: $0.name) }
            peer.connection.send(.welcome, Wire.Welcome(playerID: peer.id, worldName: settings.worldName, seed: settings.seed, dimension: "overworld",
                                                        gameMode: settings.gameMode, difficulty: settings.difficulty, hardcore: false,
                                                        x: spawn.x, y: spawn.y, z: spawn.z, worldTime: worldTime(), players: others))
            broadcast(.playerJoined, Wire.PlayerInfo(id: peer.id, name: name), except: peer.id)
            Log.info("\(name) joined (player \(peer.id))", category: "Net")
            onEvent("\(name) joined the game")

        case .chunkRequest:
            guard peer.joined, let request = try? decoder.decode(Wire.ChunkRequest.self, from: data) else { return }
            let connection = peer.connection, make = makeChunk
            for pos in request.chunks.prefix(128).compactMap({ $0.count == 2 ? ChunkPos($0[0], $0[1]) : nil }) {
                let loaded = loadedChunk(pos)
                chunkQueue.async {
                    let chunk = loaded ?? make(pos)
                    if let payload = try? Wire.chunkPayload(chunk) { connection.sendRaw(.chunkData, payload) }
                }
            }

        case .blockChange:
            guard peer.joined, let m = try? decoder.decode(Wire.BlockChange.self, from: data), m.y >= 0, Int(m.y) < WorldConst.height else { return }
            let pos = BlockPos(m.x, m.y, m.z)
            if onBlockChange(pos, m.id) { broadcastBlock(pos, m.id) }

        case .playerState:
            guard peer.joined, var state = try? decoder.decode(Wire.PlayerState.self, from: data) else { return }
            state.id = peer.id
            peer.state = state
            broadcast(.playerState, state, except: peer.id)

        case .chat:
            guard peer.joined, let m = try? decoder.decode(Wire.Chat.self, from: data) else { return }
            let text = String(m.text.prefix(200))
            broadcast(.chat, Wire.Chat(from: peer.name, text: text))
            onChat(peer.name, text)

        case .disconnect:
            peer.connection.close()

        default:
            break
        }
    }
}
