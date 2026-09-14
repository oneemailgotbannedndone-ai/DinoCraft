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

    init(id: Int, kind: String, name: String, position: DVec3, yaw: Double) {
        self.id = id
        self.kind = kind
        self.name = name
        self.position = position
        target = position
        self.yaw = yaw
        targetYaw = yaw
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

    /// Accepts an invite code (DINO-XXXXX-XXXXX), "host:port" or a plain address.
    static func parseAddress(_ text: String) -> (host: String, port: UInt16) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = InviteCode.decode(trimmed) { return (code.ip, code.port) }
        if let colon = trimmed.lastIndex(of: ":"), let port = UInt16(trimmed[trimmed.index(after: colon)...]) {
            return (String(trimmed[..<colon]), port)
        }
        return (trimmed, Wire.defaultPort)
    }

    static func join(address: String, username: String, timeout: Double = 20) throws -> WinNetwork {
        let (host, port) = parseAddress(address)
        Log.info("Connecting to \(host):\(port) as \(username)", category: "Net")
        let connection = try WireConnection.connect(host: host, port: port)
        connection.send(.hello, Wire.Hello(version: Wire.protocolVersion, username: username))
        let deadline = Date().addingTimeInterval(timeout)
        var early: [WireConnection.Event] = []
        while Date() < deadline {
            for event in connection.poll() {
                switch event {
                case .message(.welcome, let data):
                    let welcome = try JSONDecoder().decode(Wire.Welcome.self, from: data)
                    Log.info("Joined '\(welcome.worldName)' as player \(welcome.playerID) (\(welcome.gameMode), \(welcome.difficulty))", category: "Net")
                    return WinNetwork(connection: connection, welcome: welcome, username: username, pending: early)
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
                    entity.target = DVec3(s.x, s.y, s.z)
                    entity.targetYaw = Double(s.yaw)
                    entity.dying = s.dead ? 1 : 0
                    players[s.id] = entity
                case .playerJoined:
                    guard let info = try? decoder.decode(Wire.PlayerInfo.self, from: data) else { continue }
                    names[info.id] = info.name
                    players[info.id]?.name = info.name
                    out.append(.notice("\(info.name) joined the game"))
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
                        entity.target = DVec3(m.x, m.y, m.z)
                        entity.targetYaw = Double(m.yaw)
                        entity.dying = m.dying
                        next[m.id] = entity
                    }
                    mobs = next
                case .giveItem:
                    if let m = try? decoder.decode(Wire.GiveItem.self, from: data) { out.append(.giveItem(name: m.item, count: m.count, damage: m.damage)) }
                case .damage:
                    if let m = try? decoder.decode(Wire.Damage.self, from: data) {
                        out.append(.damage(amount: m.amount, cause: m.cause, knockback: DVec3(m.kx, 0, m.kz)))
                    }
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

    func sendState(player: PlayerController, swinging: Bool, held: String?, health: Float, dead: Bool) {
        connection.send(.playerState, Wire.PlayerState(id: welcome.playerID, x: player.position.x, y: player.position.y, z: player.position.z,
                                                       yaw: Float(player.yaw), pitch: Float(player.pitch),
                                                       moving: Float(player.onGround ? min(1, player.horizontalSpeed / 4.3) : 0),
                                                       sneaking: player.isSneaking, swinging: swinging, held: held, health: health, dead: dead))
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

    func disconnect() {
        connection.close()
    }
}

/// Simple box models for players and creatures (the Windows version has no model renderer yet).
enum EntityShapes {
    private static func linear(_ hex: UInt32) -> SIMD3<Float> {
        func channel(_ v: UInt32) -> Float {
            let c = Float(v) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return SIMD3(channel((hex >> 16) & 255), channel((hex >> 8) & 255), channel(hex & 255))
    }

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

    private static let colors: [String: UInt32] = [
        "trikey": 0x6E8B4A, "dodo": 0x8A7A6A, "longneck": 0x7A9A6A, "raptor": 0x9A6A3A, "spitter": 0x4A8A5A, "crawler": 0x3A3A4A,
        "magmaRaptor": 0xB8401A, "villager": 0xB08A5A, "stego": 0x6A8A7A, "ankylo": 0x8A7A5A, "rex": 0x6A5A3A, "compy": 0x8AA04A,
        "ptero": 0x9A6A5A, "parasaur": 0x7A9A8A, "sailback": 0x9A5A4A, "boneWalker": 0xD8D0BC, "scorpion": 0x5A3A2A, "pig": 0xE8A0A8,
        "cow": 0x6A4A3A, "sheep": 0xE8E4DC, "chicken": 0xF2F0EA, "pookpook": 0xF4F2EE, "carnotaurus": 0x9A3A2A,
        "allosaurus": 0x8A6A4A, "baryonyx": 0x6A7A5A, "troodon": 0x7A6A9A, "spinosaurus": 0x5A6A4A,
    ]

    private static let bipeds: Set<String> = ["raptor", "magmaRaptor", "rex", "compy", "carnotaurus", "allosaurus", "baryonyx",
                                              "troodon", "spinosaurus", "spitter", "dodo", "chicken", "pookpook", "parasaur"]
    private static let upright: Set<String> = ["villager", "boneWalker"]

    static func size(of kind: String) -> (width: Double, height: Double) {
        let s = sizes[kind] ?? (0.8, 1.2, false)
        return (s.0, s.1)
    }

    static func player(_ e: RemoteEntity) -> [WinRenderer.Box] {
        guard e.dying == 0 else { return [] }
        let shirts: [UInt32] = [0x3A6EC8, 0xC8503A, 0x3AA05A, 0xC8A03A, 0x8A4AC8]
        let shirt = linear(shirts[abs(e.id) % shirts.count]), skin = linear(0xE0B090), legs = linear(0x2A2A40)
        return [
            .init(base: e.position, yaw: e.yaw, right: -0.13, width: 0.22, length: 0.25, height: 0.72, color: legs),
            .init(base: e.position, yaw: e.yaw, right: 0.13, width: 0.22, length: 0.25, height: 0.72, color: legs),
            .init(base: e.position, yaw: e.yaw, y: 0.72, width: 0.52, length: 0.3, height: 0.72, color: shirt),
            .init(base: e.position, yaw: e.yaw, y: 1.44, width: 0.44, length: 0.44, height: 0.44, color: skin),
        ]
    }

    static func mob(_ e: RemoteEntity) -> [WinRenderer.Box] {
        let (w, h, hostile) = sizes[e.kind] ?? (0.8, 1.2, false)
        let color = linear(colors[e.kind] ?? (hostile ? 0x8A3A2A : 0x5E8A3A))
        let dark = color * 0.6
        let base = e.position - DVec3(0, Double(e.dying) * h * 0.5, 0)
        var out: [WinRenderer.Box] = []
        func box(_ right: Double, _ forward: Double, _ y: Double, _ width: Double, _ length: Double, _ height: Double, _ c: SIMD3<Float>) {
            out.append(.init(base: base, yaw: e.yaw, right: right, forward: forward, y: y, width: width, length: length, height: height, color: c))
        }
        if upright.contains(e.kind) {
            box(-w * 0.22, 0, 0, w * 0.35, w * 0.4, h * 0.42, dark)
            box(w * 0.22, 0, 0, w * 0.35, w * 0.4, h * 0.42, dark)
            box(0, 0, h * 0.42, w * 0.9, w * 0.5, h * 0.36, color)
            box(0, 0, h * 0.78, w * 0.7, w * 0.7, h * 0.22, color)
        } else if e.kind == "ptero" {
            box(0, 0, h * 0.3, w * 0.5, w * 1.2, h * 0.4, color)
            box(0, 0, h * 0.55, w * 2.6, w * 0.6, h * 0.08, dark)
            box(0, w * 0.75, h * 0.4, w * 0.3, w * 0.5, h * 0.3, color)
        } else if bipeds.contains(e.kind) {
            let length = w * 2.2
            box(-w * 0.25, 0, 0, w * 0.25, w * 0.3, h * 0.45, dark)
            box(w * 0.25, 0, 0, w * 0.25, w * 0.3, h * 0.45, dark)
            box(0, 0, h * 0.4, w, length, h * 0.35, color)
            box(0, -length * 0.8, h * 0.5, w * 0.45, length * 0.7, h * 0.18, color)
            box(0, length * 0.55, h * 0.62, w * 0.7, w * 0.9, h * 0.3, color)
        } else {
            let length = w * 1.7, legHeight = h * 0.35
            for (r, f) in [(-0.3, -0.32), (0.3, -0.32), (-0.3, 0.32), (0.3, 0.32)] {
                box(w * r, length * f, 0, w * 0.24, w * 0.24, legHeight, dark)
            }
            box(0, 0, legHeight, w, length, h * 0.45, color)
            if e.kind == "longneck" {
                box(0, length * 0.5, h * 0.5, w * 0.3, w * 0.3, h * 0.45, color)
                box(0, length * 0.55, h * 0.9, w * 0.35, w * 0.5, h * 0.12, color)
            } else {
                box(0, length * 0.55, h * 0.5, w * 0.6, w * 0.6, h * 0.4, color)
            }
        }
        return out
    }
}
