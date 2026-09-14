import Foundation
import Network
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
}

struct HelloMessage: Codable {
    var version: Int
    var username: String
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
}

struct PlayerInfo: Codable {
    var id: Int
    var name: String
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
}

struct ChatMessage: Codable {
    var from: String
    var text: String
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

enum NetCodec {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    static func frame(_ type: MessageType, _ payload: Data) -> Data {
        var out = Data(capacity: payload.count + 5)
        withUnsafeBytes(of: UInt32(payload.count + 1).littleEndian) { out.append(contentsOf: $0) }
        out.append(type.rawValue)
        out.append(payload)
        return out
    }

    static func chunkPayload(_ chunk: Chunk) throws -> Data {
        var data = Data()
        withUnsafeBytes(of: chunk.pos.x.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: chunk.pos.z.littleEndian) { data.append(contentsOf: $0) }
        data.append(try chunk.serialize())
        return data
    }

    static func decodeChunk(_ payload: Data) throws -> Chunk {
        guard payload.count > 8 else { throw Chunk.ChunkIOError.badHeader }
        let x = payload.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: Int32.self)) }
        let z = payload.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: Int32.self)) }
        return try Chunk.deserialize(payload.subdata(in: 8..<payload.count), expected: ChunkPos(x, z))
    }
}

/// A framed, message-oriented TCP connection. Bytes are parsed on a private
/// queue; decoded messages are delivered on the main queue.
final class NetConnection: @unchecked Sendable {
    let connection: NWConnection
    private let queue = DispatchQueue(label: "com.dinocraft.net")
    private var buffer = Data()
    private var closed = false
    var label: String

    /// Delivered on the main queue. Chunk payloads are pre-decoded into `Chunk`.
    var onMessage: ((MessageType, Data) -> Void)?
    var onChunk: ((Chunk) -> Void)?
    var onReady: (() -> Void)?
    var onClose: ((String) -> Void)?

    private(set) var bytesSent = 0
    private(set) var bytesReceived = 0

    init(connection: NWConnection, label: String) {
        self.connection = connection
        self.label = label
    }

    convenience init(host: String, port: UInt16) {
        let params = NWParameters.tcp
        if let tcp = params.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.noDelay = true
            tcp.enableKeepalive = true
        }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port) ?? 25650, using: params)
        self.init(connection: conn, label: "\(host):\(port)")
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.onReady?() }
            case .failed(let error):
                self.finish("Connection failed: \(error.localizedDescription)")
            case .waiting(let error):
                self.finish("Could not reach the host: \(error.localizedDescription)")
            case .cancelled:
                self.finish("Disconnected")
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func finish(_ reason: String) {
        queue.async {
            guard !self.closed else { return }
            self.closed = true
            self.connection.cancel()
            DispatchQueue.main.async { self.onClose?(reason) }
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.bytesReceived += data.count
                self.buffer.append(data)
                self.parse()
            }
            if let error {
                self.finish("Connection error: \(error.localizedDescription)")
                return
            }
            if isComplete {
                self.finish("The other side closed the connection")
                return
            }
            self.receive()
        }
    }

    private func parse() {
        while buffer.count >= 5 {
            let length = Int(buffer.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) })
            guard length >= 1, length <= NetConfig.maxFrame else {
                finish("Received a malformed message")
                return
            }
            guard buffer.count >= 4 + length else { return }
            let typeByte = buffer[buffer.startIndex + 4]
            let payload = buffer.subdata(in: (buffer.startIndex + 5)..<(buffer.startIndex + 4 + length))
            buffer.removeSubrange(buffer.startIndex..<(buffer.startIndex + 4 + length))
            guard let type = MessageType(rawValue: typeByte) else {
                Log.warning("Ignoring unknown message type \(typeByte) from \(label)", category: "Net")
                continue
            }
            if type == .chunkData {
                do {
                    let chunk = try NetCodec.decodeChunk(payload)
                    DispatchQueue.main.async { self.onChunk?(chunk) }
                } catch {
                    Log.error("Bad chunk from \(label): \(error)", category: "Net")
                }
            } else {
                DispatchQueue.main.async { self.onMessage?(type, payload) }
            }
        }
    }

    func send<T: Encodable>(_ type: MessageType, _ value: T) {
        guard let payload = try? NetCodec.encoder.encode(value) else { return }
        sendRaw(type, payload)
    }

    func sendRaw(_ type: MessageType, _ payload: Data) {
        let frame = NetCodec.frame(type, payload)
        bytesSent += frame.count
        connection.send(content: frame, completion: .contentProcessed { [weak self] error in
            if let error { self?.finish("Send failed: \(error.localizedDescription)") }
        })
    }

    func close() {
        sendRaw(.disconnect, Data())
        finish("Disconnected")
    }

    static func decode<T: Decodable>(_ type: T.Type, _ data: Data) -> T? {
        do {
            return try NetCodec.decoder.decode(type, from: data)
        } catch {
            Log.warning("Could not decode \(T.self): \(error)", category: "Net")
            return nil
        }
    }
}

/// Finds DinoCraft games hosted on the local network via Bonjour.
final class LANDiscovery {
    struct Host: Equatable, Identifiable {
        var id: String { name }
        let name: String
        let endpoint: NWEndpoint
    }

    private var browser: NWBrowser?
    private(set) var hosts: [Host] = []

    func start() {
        guard browser == nil else { return }
        let b = NWBrowser(for: .bonjour(type: NetConfig.bonjourType, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap { r -> Host? in
                if case let .service(name, _, _, _) = r.endpoint { return Host(name: name, endpoint: r.endpoint) }
                return nil
            }
            DispatchQueue.main.async { self?.hosts = found }
        }
        b.stateUpdateHandler = { state in
            if case .failed(let error) = state { Log.warning("LAN discovery failed: \(error)", category: "Net") }
        }
        b.start(queue: .main)
        browser = b
    }

    func stop() {
        browser?.cancel()
        browser = nil
        hosts = []
    }
}
