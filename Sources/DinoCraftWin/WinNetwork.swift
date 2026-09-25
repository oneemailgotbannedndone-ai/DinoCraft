import Foundation
import DinoCraftCore

/// Another player or a creature from the host, smoothed between network updates.
final class RemoteEntity {
    let id: Int
    let kind: String
    var name: String
    var position: DVec3
    var target: DVec3
    var yaw: Double
    var targetYaw: Double
    var dying: Float = 0
    // Animation
    var walk: Float = 0
    var moving: Float = 0
    var lunge: Float = 0
    var hurt: Float = 0
    var swing: Float = 0
    var pitch: Float = 0
    var sneaking = false
    var health: Float = 20
    var variant = 0
    /// A player's cosmetics (`PlayerLook.encoded`), or nil for the default look.
    var look: String?

    init(id: Int, kind: String, name: String, position: DVec3, yaw: Double) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        target = position
        self.yaw = yaw
        targetYaw = yaw
    }

    func apply(_ s: Wire.PlayerState) {
        target = DVec3(s.x, s.y, s.z)
        targetYaw = Double(s.yaw)
        pitch = s.pitch
        moving = s.moving
        sneaking = s.sneaking
        if s.swinging { swing = 1 }
        if s.health < health { hurt = 0.35 }
        health = s.health
        dying = s.dead ? 1 : 0
        if let l = s.look { look = l }
    }

    func apply(_ m: Wire.MobState) {
        target = DVec3(m.x, m.y, m.z)
        targetYaw = Double(m.yaw)
        walk = m.walk
        moving = m.move
        hurt = max(hurt, m.hurt)
        dying = m.dying
        lunge = m.lunge
        variant = m.variant ?? 0
    }

    func update(dt: Double) {
        if simd_distance(position, target) > 16 {
            position = target
        } else {
            position += (target - position) * min(1, dt * 12)
        }
        var diff = (targetYaw - yaw).truncatingRemainder(dividingBy: 2 * .pi)
        if diff > .pi { diff -= 2 * .pi }
        if diff < -.pi { diff += 2 * .pi }
        yaw += diff * min(1, dt * 12)
        walk += moving * Float(dt) * 7
        swing = max(0, swing - Float(dt) * 3.5)
        hurt = max(0, hurt - Float(dt))
    }
}

/// Joins a DinoCraft game hosted on a Mac and turns its messages into game events.
final class WinNetwork {
    enum Event {
        case chunk(Chunk)
        case blockChange(BlockPos, BlockID)
        case worldTime(Double)
        case dimensionChange(DVec3)
        case notice(String)
        case giveItem(name: String, count: Int, damage: Int)
        case damage(amount: Double, cause: String, knockback: DVec3)
        case containerData(Wire.ContainerData)
        case disconnected(String)
    }

    enum JoinError: Error, CustomStringConvertible {
        case rejected(String)
        case closed(String)
        case timedOut

        var description: String {
            switch self {
            case .rejected(let reason): return reason
            case .closed(let reason): return reason
            case .timedOut: return "The host didn't answer. Make sure their world is open (Esc → Open to LAN or Open to Internet)."
            }
        }
    }

    let connection: WireConnection
    let welcome: Wire.Welcome
    let username: String
    /// This player's `PlayerIdentity` ID, for spotting friends.
    private var myID = ""
    private(set) var players: [Int: RemoteEntity] = [:]
    private(set) var mobs: [Int: RemoteEntity] = [:]
    private var names: [Int: String] = [:]
    private var pending: [WireConnection.Event]
    private let decoder = JSONDecoder()

    private init(connection: WireConnection, welcome: Wire.Welcome, username: String, pending: [WireConnection.Event]) {
        self.connection = connection
        self.welcome = welcome
        self.username = username
        self.pending = pending
        for p in welcome.players { names[p.id] = p.name }
    }

    static func join(address: String, username: String, playerID: String, look: String, timeout: Double = 20) throws -> WinNetwork {
        let (host, port) = Wire.parseAddress(address)
        Log.info("Connecting to \(host):\(port) as \(username)", category: "Net")
        let connection = try WireConnection.connect(host: host, port: port)
        connection.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: username, playerID: playerID, look: look))
        let deadline = Date().addingTimeInterval(timeout)
        var early: [WireConnection.Event] = []
        while Date() < deadline {
            for event in connection.poll() {
                switch event {
                case .message(.welcome, let data):
                    let welcome = try JSONDecoder().decode(Wire.Welcome.self, from: data)
                    Log.info("Joined '\(welcome.worldName)' as player \(welcome.playerID) (\(welcome.gameMode), \(welcome.difficulty))", category: "Net")
                    let network = WinNetwork(connection: connection, welcome: welcome, username: username, pending: early)
                    network.myID = playerID
                    for p in welcome.players {
                        FriendList.shared.met(id: p.playerID, name: p.name, look: p.look, address: p.id == 0 ? address : nil, myID: playerID)
                    }
                    return network
                case .message(.reject, let data):
                    let reason = (try? JSONDecoder().decode(Wire.Reject.self, from: data))?.reason ?? "The host refused the connection."
                    connection.close()
                    throw JoinError.rejected(reason)
                case .closed(let reason):
                    throw JoinError.closed(reason)
                default:
                    early.append(event)
                }
            }
            Thread.sleep(forTimeInterval: 0.02)
        }
        connection.close()
        throw JoinError.timedOut
    }

    // MARK: Receiving

    func poll() -> [Event] {
        var out: [Event] = []
        let events = pending + connection.poll()
        pending.removeAll()
        for event in events {
            switch event {
            case .chunk(let chunk):
                out.append(.chunk(chunk))
            case .closed(let reason):
                out.append(.disconnected(reason))
            case .message(let kind, let data):
                switch kind {
                case .blockChange:
                    if let m = try? decoder.decode(Wire.BlockChange.self, from: data) { out.append(.blockChange(BlockPos(m.x, m.y, m.z), m.id)) }
                case .playerState:
                    guard let s = try? decoder.decode(Wire.PlayerState.self, from: data), s.id != welcome.playerID else { continue }
                    let entity = players[s.id] ?? RemoteEntity(id: s.id, kind: "player", name: names[s.id] ?? "Explorer",
                                                                 position: DVec3(s.x, s.y, s.z), yaw: Double(s.yaw))
                    entity.apply(s)
                    players[s.id] = entity
                case .playerJoined:
                    guard let info = try? decoder.decode(Wire.PlayerInfo.self, from: data) else { continue }
                    names[info.id] = info.name
                    players[info.id]?.name = info.name
                    let friend = FriendList.shared.met(id: info.playerID, name: info.name, look: info.look, address: nil, myID: myID)
                    out.append(.notice(friend ? "Your friend \(info.name) joined the game!" : "\(info.name) joined the game"))
                case .playerLeft:
                    guard let info = try? decoder.decode(Wire.PlayerInfo.self, from: data) else { continue }
                    players.removeValue(forKey: info.id)
                    out.append(.notice("\(info.name) left the game"))
                case .chat:
                    guard let m = try? decoder.decode(Wire.Chat.self, from: data) else { continue }
                    out.append(.notice(m.from.isEmpty ? m.text : "<\(m.from)> \(m.text)"))
                case .mobSnapshot:
                    guard let snapshot = try? decoder.decode(Wire.MobSnapshot.self, from: data) else { continue }
                    var next: [Int: RemoteEntity] = [:]
                    for m in snapshot.mobs {
                        let entity = mobs[m.id] ?? RemoteEntity(id: m.id, kind: m.kind, name: m.kind, position: DVec3(m.x, m.y, m.z), yaw: Double(m.yaw))
                        entity.apply(m)
                        next[m.id] = entity
                    }
                    mobs = next
                case .giveItem:
                    if let m = try? decoder.decode(Wire.GiveItem.self, from: data) { out.append(.giveItem(name: m.item, count: m.count, damage: m.damage)) }
                case .damage:
                    if let m = try? decoder.decode(Wire.Damage.self, from: data) {
                        out.append(.damage(amount: m.amount, cause: m.cause, knockback: DVec3(m.kx, 0, m.kz)))
                    }
                case .containerData:
                    if let m = try? decoder.decode(Wire.ContainerData.self, from: data) { out.append(.containerData(m)) }
                case .worldTime:
                    if let m = try? decoder.decode(Wire.WorldTime.self, from: data) { out.append(.worldTime(m.time)) }
                case .dimensionChange:
                    if let m = try? decoder.decode(Wire.DimensionChange.self, from: data) {
                        players.removeAll()
                        mobs.removeAll()
                        out.append(.dimensionChange(DVec3(m.x, m.y, m.z)))
                    }
                case .reject:
                    out.append(.disconnected((try? decoder.decode(Wire.Reject.self, from: data))?.reason ?? "The host removed you from the game."))
                case .disconnect:
                    out.append(.disconnected("The host closed the game."))
                default:
                    break
                }
            }
        }
        return out
    }

    func updateEntities(dt: Double) {
        for p in players.values { p.update(dt: dt) }
        for m in mobs.values { m.update(dt: dt) }
    }

    // MARK: Sending

    func requestChunks(_ positions: [ChunkPos]) {
        connection.send(.chunkRequest, Wire.ChunkRequest(positions))
    }

    /// `harvest` asks the host to drop the block's items (Survival).
    func sendBlock(_ pos: BlockPos, _ id: BlockID, harvest: Bool) {
        connection.send(.blockChange, Wire.BlockChange(pos: pos, id: id, harvest: harvest))
    }

    func sendState(player: PlayerController, swinging: Bool, held: String?, health: Float, dead: Bool, look: String?) {
        connection.send(.playerState, Wire.PlayerState(id: welcome.playerID, x: player.position.x, y: player.position.y, z: player.position.z,
                                                       yaw: Float(player.yaw), pitch: Float(player.pitch),
                                                       moving: Float(player.onGround ? min(1, player.horizontalSpeed / 4.3) : 0),
                                                       sneaking: player.isSneaking, swinging: swinging, held: held, health: health, dead: dead,
                                                       look: look))
    }

    func sendChat(_ text: String) {
        connection.send(.chat, Wire.Chat(from: username, text: String(text.prefix(200))))
    }

    func sendAttackMob(id: Int, damage: Double, knockback: DVec3) {
        connection.send(.attackMob, Wire.AttackMob(mob: id, damage: damage, kx: knockback.x, kz: knockback.z))
    }

    func sendAttackPlayer(id: Int, damage: Double, knockback: DVec3) {
        connection.send(.attackPlayer, Wire.AttackPlayer(target: id, damage: damage, kx: knockback.x, kz: knockback.z))
    }

    func openContainer(_ pos: BlockPos) {
        connection.send(.containerOpen, Wire.ContainerPos(pos: pos))
    }

    func setContainer(_ pos: BlockPos, slots: [Wire.NetStack?]) {
        connection.send(.containerSet, Wire.ContainerSet(pos: pos, slots: slots))
    }

    func disconnect() {
        connection.close()
    }
}

/// Creature sizes for hit tests, mirroring `MobSpecies` in the Mac app.
enum EntityShapes {
    /// Width, height and whether the creature is hostile, mirroring `MobSpecies` in the Mac app.
    private static let sizes: [String: (Double, Double, Bool)] = [
        "trikey": (0.9, 1.0, false), "dodo": (0.5, 0.9, false), "longneck": (1.6, 3.8, false), "raptor": (0.6, 1.2, true),
        "spitter": (0.7, 1.5, true), "crawler": (0.9, 0.5, true), "magmaRaptor": (0.7, 1.3, true), "villager": (0.6, 1.95, false),
        "stego": (1.2, 2.0, false), "ankylo": (1.4, 1.25, false), "rex": (1.2, 3.2, true), "compy": (0.4, 0.65, true),
        "ptero": (0.9, 0.7, true), "parasaur": (1.0, 2.3, false), "sailback": (0.8, 1.4, false), "boneWalker": (0.6, 1.4, true),
        "scorpion": (0.9, 0.55, true), "pig": (0.8, 0.9, false), "cow": (0.9, 1.4, false), "sheep": (0.8, 1.2, false),
        "chicken": (0.4, 0.7, false), "pookpook": (0.7, 1.2, false), "carnotaurus": (1.0, 2.4, true), "allosaurus": (1.1, 2.8, true),
        "baryonyx": (1.0, 2.2, true), "troodon": (0.5, 1.0, true), "spinosaurus": (1.4, 3.6, true),
    ]

    static func size(of kind: String) -> (width: Double, height: Double) {
        let s = sizes[kind] ?? (0.8, 1.2, false)
        return (s.0, s.1)
    }
}
