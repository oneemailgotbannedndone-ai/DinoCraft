import Foundation

/// DinoCraft's multiplayer wire protocol, shared with the Windows game.
///
/// Framing: `[UInt32 little-endian length][UInt8 kind][payload]`, where the length
/// covers the kind byte and payload. Control messages are JSON; chunk data is a
/// binary chunk position followed by `Chunk.serialize()` output.
///
/// These types must stay in sync with `Sources/DinoCraft/Network/NetProtocol.swift`
/// (the Mac host and client), which uses the same message numbers and JSON keys.
public enum Wire {
    public static let defaultPort: UInt16 = 25650
    public static let protocolVersion = 1
    public static let maxFrame = 8 * 1024 * 1024

    public enum Kind: UInt8 {
        case hello = 1, welcome, reject, chunkRequest, chunkData, blockChange, playerState, playerJoined, playerLeft, chat,
             mobSnapshot, itemSnapshot, attackPlayer, attackMob, dropItem, giveItem, damage, worldTime, dimensionChange,
             disconnect, containerOpen, containerData, containerSet, spawnMob
    }

    public struct Hello: Codable {
        public var version: Int
        public var username: String
        public init(version: Int, username: String) { self.version = version; self.username = username }
    }

    public struct PlayerInfo: Codable {
        public var id: Int
        public var name: String
        public init(id: Int, name: String) { self.id = id; self.name = name }
    }

    public struct Welcome: Codable {
        public var playerID: Int
        public var worldName: String
        public var seed: String
        public var dimension: String
        public var gameMode: String
        public var difficulty: String
        public var hardcore: Bool
        public var x: Double, y: Double, z: Double
        public var worldTime: Double
        public var players: [PlayerInfo]

        public init(playerID: Int, worldName: String, seed: String, dimension: String, gameMode: String, difficulty: String,
                    hardcore: Bool, x: Double, y: Double, z: Double, worldTime: Double, players: [PlayerInfo]) {
            self.playerID = playerID; self.worldName = worldName; self.seed = seed; self.dimension = dimension
            self.gameMode = gameMode; self.difficulty = difficulty; self.hardcore = hardcore
            self.x = x; self.y = y; self.z = z; self.worldTime = worldTime; self.players = players
        }
    }

    public struct Reject: Codable {
        public var reason: String
        public init(reason: String) { self.reason = reason }
    }

    public struct ChunkRequest: Codable {
        public var chunks: [[Int32]]
        public init(_ positions: [ChunkPos]) { chunks = positions.map { [$0.x, $0.z] } }
    }

    public struct BlockChange: Codable {
        public var x: Int32, y: Int32, z: Int32
        public var id: UInt8
        public var harvest: Bool?
        public init(pos: BlockPos, id: BlockID, harvest: Bool? = nil) { x = pos.x; y = pos.y; z = pos.z; self.id = id; self.harvest = harvest }
    }

    public struct PlayerState: Codable {
        public var id: Int
        public var x: Double, y: Double, z: Double
        public var yaw: Float, pitch: Float
        public var moving: Float
        public var sneaking: Bool
        public var swinging: Bool
        public var held: String?
        public var health: Float
        public var dead: Bool
        /// The player's cosmetics (`PlayerLook.encoded`); older versions leave it out.
        public var look: String?

        public init(id: Int, x: Double, y: Double, z: Double, yaw: Float, pitch: Float, moving: Float, sneaking: Bool,
                    swinging: Bool, held: String?, health: Float, dead: Bool, look: String? = nil) {
            self.id = id; self.x = x; self.y = y; self.z = z; self.yaw = yaw; self.pitch = pitch; self.moving = moving
            self.sneaking = sneaking; self.swinging = swinging; self.held = held; self.health = health; self.dead = dead
            self.look = look
        }
    }

    public struct Chat: Codable {
        public var from: String
        public var text: String
        public init(from: String, text: String) { self.from = from; self.text = text }
    }

    public struct MobState: Codable {
        public var id: Int
        public var kind: String
        public var x: Double, y: Double, z: Double
        public var yaw: Float
        public var health: Float
        public var maxHealth: Float
        public var walk: Float
        public var move: Float
        public var hurt: Float
        public var dying: Float
        public var lunge: Float
        public var variant: Int?

        public init(id: Int, kind: String, x: Double, y: Double, z: Double, yaw: Float, health: Float, maxHealth: Float) {
            self.id = id; self.kind = kind; self.x = x; self.y = y; self.z = z; self.yaw = yaw
            self.health = health; self.maxHealth = maxHealth
            walk = 0; move = 0; hurt = 0; dying = 0; lunge = 0; variant = nil
        }
    }

    public struct MobSnapshot: Codable {
        public var mobs: [MobState]
        public var spits: [[Double]]
        public init(mobs: [MobState], spits: [[Double]] = []) { self.mobs = mobs; self.spits = spits }
    }

    public struct WorldTime: Codable {
        public var time: Double
        public var weather: String?
        public init(time: Double, weather: String? = nil) { self.time = time; self.weather = weather }
    }

    public struct DimensionChange: Codable {
        public var dimension: String
        public var x: Double, y: Double, z: Double
        public init(dimension: String, x: Double, y: Double, z: Double) { self.dimension = dimension; self.x = x; self.y = y; self.z = z }
    }

    public struct GiveItem: Codable {
        public var item: String
        public var count: Int
        public var damage: Int
        public init(item: String, count: Int, damage: Int) { self.item = item; self.count = count; self.damage = damage }
    }

    public struct Damage: Codable {
        public var amount: Double
        public var cause: String
        public var kx: Double, kz: Double
        public init(amount: Double, cause: String, kx: Double, kz: Double) { self.amount = amount; self.cause = cause; self.kx = kx; self.kz = kz }
    }

    public struct AttackMob: Codable {
        public var mob: Int
        public var damage: Double
        public var kx: Double, kz: Double
        public init(mob: Int, damage: Double, kx: Double, kz: Double) { self.mob = mob; self.damage = damage; self.kx = kx; self.kz = kz }
    }

    public struct AttackPlayer: Codable {
        public var target: Int
        public var damage: Double
        public var kx: Double, kz: Double
        public init(target: Int, damage: Double, kx: Double, kz: Double) { self.target = target; self.damage = damage; self.kx = kx; self.kz = kz }
    }

    public struct NetStack: Codable {
        public var item: String
        public var count: Int
        public var damage: Int?
        public init(item: String, count: Int, damage: Int?) { self.item = item; self.count = count; self.damage = damage }
    }

    public struct ContainerPos: Codable {
        public var x: Int32, y: Int32, z: Int32
        public init(pos: BlockPos) { x = pos.x; y = pos.y; z = pos.z }
    }

    public struct ContainerData: Codable {
        public var x: Int32, y: Int32, z: Int32
        public var kind: String
        public var slots: [NetStack?]
        public var burnLeft: Double, burnTotal: Double, cook: Double, cookTotal: Double
    }

    public struct ContainerSet: Codable {
        public var x: Int32, y: Int32, z: Int32
        public var slots: [NetStack?]
        public init(pos: BlockPos, slots: [NetStack?]) { x = pos.x; y = pos.y; z = pos.z; self.slots = slots }
    }

    public static func frame(_ kind: Kind, _ payload: Data) -> Data {
        var out = Data(capacity: payload.count + 5)
        withUnsafeBytes(of: UInt32(payload.count + 1).littleEndian) { out.append(contentsOf: $0) }
        out.append(kind.rawValue)
        out.append(payload)
        return out
    }

    public static func chunkPayload(_ chunk: Chunk) throws -> Data {
        var data = Data()
        withUnsafeBytes(of: chunk.pos.x.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunk.pos.z.littleEndian) { data.append(contentsOf: $0) }
        data.append(try chunk.serialize())
        return data
    }

    public static func decodeChunk(_ payload: Data) throws -> Chunk {
        guard payload.count > 8 else { throw Chunk.ChunkIOError.badHeader }
        let bytes = [UInt8](payload.prefix(8))
        let x = Int32(bitPattern: UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24)
        let z = Int32(bitPattern: UInt32(bytes[4]) | UInt32(bytes[5]) << 8 | UInt32(bytes[6]) << 16 | UInt32(bytes[7]) << 24)
        return try Chunk.deserialize(payload.subdata(in: (payload.startIndex + 8)..<payload.endIndex), expected: ChunkPos(x, z))
    }
}

/// A framed `Wire` connection over a `NetSocket`. A background thread reads and
/// parses frames (decoding chunks there); the game drains events with `poll()`.
public final class WireConnection: @unchecked Sendable {
    public enum Event {
        case message(Wire.Kind, Data)
        case chunk(Chunk)
        case closed(String)
    }

    public let label: String
    private let socket: NetSocket
    private let lock = NSLock()
    private var events: [Event] = []
    private var closedFlag = false

    public init(socket: NetSocket, label: String) {
        self.socket = socket
        self.label = label
        let thread = Thread { [weak self] in self?.readLoop() }
        thread.name = "DinoCraft Net \(label)"
        thread.start()
    }

    public static func connect(host: String, port: UInt16) throws -> WireConnection {
        WireConnection(socket: try NetSocket.connect(host: host, port: port), label: "\(host):\(port)")
    }

    public var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closedFlag
    }

    /// Takes every event received since the last call.
    public func poll() -> [Event] {
        lock.lock()
        defer { lock.unlock() }
        let out = events
        events.removeAll(keepingCapacity: true)
        return out
    }

    public func send<T: Encodable>(_ kind: Wire.Kind, _ value: T) {
        guard let payload = try? JSONEncoder().encode(value) else { return }
        sendRaw(kind, payload)
    }

    public func sendRaw(_ kind: Wire.Kind, _ payload: Data) {
        guard !isClosed else { return }
        if !socket.send(Wire.frame(kind, payload)) { finish("The connection was lost.") }
    }

    public func close() {
        if !isClosed { sendRaw(.disconnect, Data()) }
        finish("Disconnected")
        socket.close()
    }

    private func finish(_ reason: String) {
        lock.lock()
        if !closedFlag {
            closedFlag = true
            events.append(.closed(reason))
        }
        lock.unlock()
    }

    private func push(_ event: Event) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    private func readLoop() {
        var pending: [UInt8] = []
        var start = 0
        var scratch = [UInt8](repeating: 0, count: 1 << 16)
        while true {
            let n = socket.receive(into: &scratch)
            if n <= 0 {
                finish(n == 0 ? "The other player closed the connection." : "The connection was lost.")
                return
            }
            pending.append(contentsOf: scratch[0..<n])
            while pending.count - start >= 5 {
                let length = Int(pending[start]) | Int(pending[start + 1]) << 8 | Int(pending[start + 2]) << 16 | Int(pending[start + 3]) << 24
                guard length >= 1, length <= Wire.maxFrame else {
                    finish("Received a damaged message.")
                    socket.close()
                    return
                }
                guard pending.count - start >= 4 + length else { break }
                let kindByte = pending[start + 4]
                let payload = Data(pending[(start + 5)..<(start + 4 + length)])
                start += 4 + length
                guard let kind = Wire.Kind(rawValue: kindByte) else { continue }
                if kind == .chunkData {
                    do {
                        push(.chunk(try Wire.decodeChunk(payload)))
                    } catch {
                        Log.warning("Bad chunk from \(label): \(error)", category: "Net")
                    }
                } else {
                    push(.message(kind, payload))
                }
            }
            if start == pending.count {
                pending.removeAll(keepingCapacity: true)
                start = 0
            } else if start > 1 << 20 {
                pending.removeFirst(start)
                start = 0
            }
        }
    }
}
