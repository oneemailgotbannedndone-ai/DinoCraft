import Foundation

// MARK: - Who you are

/// Every DinoCraft player is one of a kind. On first launch the game makes a random player ID;
/// your tag (the `#K7Q2` after your name) comes from it, so two players called Rex are still
/// `Rex#K7Q2` and `Rex#9WDA`. Friends are remembered by ID, never by name.
public enum PlayerIdentity {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// A new random ID: 16 lowercase hex digits.
    public static func newID() -> String {
        var rng = SystemRandomNumberGenerator()
        return String(format: "%016llx", rng.next() as UInt64)
    }

    public static func isValid(_ id: String) -> Bool {
        id.count == 16 && id.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    /// Four easy-to-read characters made from the ID, such as `K7Q2`.
    public static func tag(for id: String) -> String {
        var value = UInt64(id, radix: 16) ?? Hashing.seed(from: id)
        value = value &* 0x9E37_79B9_7F4A_7C15
        value ^= value >> 29
        var chars: [Character] = []
        for _ in 0..<4 {
            chars.append(alphabet[Int(value & 31)])
            value >>= 5
        }
        return String(chars)
    }

    /// For example `Rex#K7Q2`.
    public static func display(name: String, id: String) -> String {
        "\(name.isEmpty ? "Explorer" : name)#\(tag(for: id))"
    }

    /// Player names as the game shows them: letters, digits and `_`, at most 16 characters.
    public static func cleanName(_ name: String) -> String {
        String(name.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(16))
    }
}

// MARK: - Friend codes

/// A friend code tells another player who you are and where your games are hosted:
/// `FRIEND:Rex:3f9a1c2b7d4e5f60:DINO-3M4KA-9QX2B` (the address part is optional).
public enum FriendCode {
    public struct Contents: Equatable {
        public var name: String
        public var id: String
        public var address: String?
        public init(name: String, id: String, address: String?) { self.name = name; self.id = id; self.address = address }
    }

    public static func encode(name: String, id: String, address: String?) -> String {
        var code = "FRIEND:\(PlayerIdentity.cleanName(name).isEmpty ? "Explorer" : PlayerIdentity.cleanName(name)):\(id)"
        if let address, !address.isEmpty { code += ":" + address }
        return code
    }

    /// Reads a friend code (with or without extra spaces or text around it); nil if it isn't one.
    public static func decode(_ text: String) -> Contents? {
        guard let start = text.range(of: "FRIEND:", options: .caseInsensitive) else { return nil }
        let body = text[start.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init) ?? body
        let parts = firstLine.split(separator: ":", maxSplits: 2).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        let name = PlayerIdentity.cleanName(parts[0])
        let id = parts[1].lowercased()
        guard !name.isEmpty, PlayerIdentity.isValid(id) else { return nil }
        let address = parts.count > 2 ? parts[2].split(separator: " ").first.map(String.init) : nil
        return Contents(name: name, id: id, address: address?.isEmpty == true ? nil : address)
    }
}

// MARK: - Addresses

extension Wire {
    /// Accepts an invite code (DINO-XXXXX-XXXXX), "host:port" or a plain address.
    public static func parseAddress(_ text: String) -> (host: String, port: UInt16) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let code = InviteCode.decode(trimmed) { return (code.ip, code.port) }
        if let colon = trimmed.lastIndex(of: ":"), let port = UInt16(trimmed[trimmed.index(after: colon)...]) {
            return (String(trimmed[..<colon]), port)
        }
        return (trimmed, defaultPort)
    }

    /// The address friends can use to reach this computer's hosted games on the local network.
    public static func localAddress() -> String? {
        NetSocket.localIPv4().map { "\($0):\(defaultPort)" }
    }
}

// MARK: - Is my friend playing?

/// Asks a host what it's playing (the `status` message) without joining.
public enum StatusProbe {
    /// Blocks for up to `timeout` seconds; nil when nobody answered.
    public static func check(address: String, timeout: Double = 3) -> Wire.Status? {
        let (host, port) = Wire.parseAddress(address)
        let result = Box()
        let done = DispatchSemaphore(value: 0)
        // Connecting can hang on an unreachable address, so it runs on its own thread and is abandoned at the deadline.
        let thread = Thread {
            defer { done.signal() }
            guard let connection = try? WireConnection.connect(host: host, port: port) else { return }
            connection.send(.status, Wire.StatusRequest())
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                for event in connection.poll() {
                    if case .message(.status, let data) = event, let status = try? JSONDecoder().decode(Wire.Status.self, from: data) {
                        result.set(status)
                        connection.close()
                        return
                    }
                    if case .closed = event { return }
                }
                Thread.sleep(forTimeInterval: 0.03)
            }
            connection.close()
        }
        thread.name = "DinoCraft Status \(host)"
        thread.start()
        _ = done.wait(timeout: .now() + timeout + 0.5)
        return result.get()
    }

    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Wire.Status?
        func set(_ v: Wire.Status) { lock.lock(); value = v; lock.unlock() }
        func get() -> Wire.Status? { lock.lock(); defer { lock.unlock() }; return value }
    }
}

// MARK: - The friends list

/// Your friends and the players you've recently played with, saved in `friends.json`.
/// Used from the game's main thread; status checks run in the background.
public final class FriendList: @unchecked Sendable {
    public struct Person: Codable, Equatable, Identifiable {
        public var id: String
        public var name: String
        /// Their cosmetics (`PlayerLook.encoded`), learned when you play together.
        public var look: String?
        /// Where their games are hosted: an invite code, "host:port" or an address.
        public var address: String?
        public var lastPlayed: Date?

        public var display: String { PlayerIdentity.display(name: name, id: id) }

        public init(id: String, name: String, look: String? = nil, address: String? = nil, lastPlayed: Date? = nil) {
            self.id = id; self.name = name; self.look = look; self.address = address; self.lastPlayed = lastPlayed
        }
    }

    public enum Status: Equatable {
        case unknown, checking, offline
        case hosting(world: String, players: Int)
    }

    private struct File: Codable {
        var friends: [Person] = []
        var recent: [Person] = []
        var myAddress: String?
    }

    public static let shared = FriendList(url: GamePaths.root.appendingPathComponent("friends.json"))

    public private(set) var friends: [Person] = []
    /// Players you've been in a game with who aren't friends yet, newest first.
    public private(set) var recent: [Person] = []
    /// Where this player's own games were last opened to friends (their invite code), put in their friend code.
    public var myAddress: String? {
        didSet { if myAddress != oldValue { save() } }
    }
    private let url: URL
    private let lock = NSLock()
    private var statuses: [String: Status] = [:]

    public init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url), let file = try? JSONDecoder.iso.decode(File.self, from: data) {
            friends = file.friends
            recent = file.recent
            myAddress = file.myAddress
        }
    }

    /// This player's friend code, with the address their games were last hosted at.
    public func myCode(name: String, id: String) -> String {
        FriendCode.encode(name: name, id: id, address: myAddress ?? Wire.localAddress())
    }

    public func isFriend(_ id: String?) -> Bool {
        guard let id else { return false }
        return friends.contains { $0.id == id }
    }

    /// Adds a friend from their code. Returns a message to show.
    @discardableResult
    public func add(code text: String, myID: String) -> String {
        guard let contents = FriendCode.decode(text) else { return "That isn't a friend code. Ask your friend to press Copy My Friend Code." }
        guard contents.id != myID else { return "That's your own friend code!" }
        let existing = friends.firstIndex { $0.id == contents.id }
        var person = existing.map { friends[$0] } ?? recent.first { $0.id == contents.id } ?? Person(id: contents.id, name: contents.name)
        person.name = contents.name
        if let address = contents.address { person.address = address }
        if let existing { friends[existing] = person } else { friends.append(person) }
        recent.removeAll { $0.id == contents.id }
        save()
        return existing == nil ? "\(person.display) is now your friend!" : "Updated \(person.display)."
    }

    /// Turns someone you played with into a friend.
    public func befriend(_ id: String) {
        guard let person = recent.first(where: { $0.id == id }), !isFriend(id) else { return }
        friends.append(person)
        recent.removeAll { $0.id == id }
        save()
    }

    public func remove(_ id: String) {
        guard let index = friends.firstIndex(where: { $0.id == id }) else { return }
        var person = friends.remove(at: index)
        person.lastPlayed = person.lastPlayed ?? Date()
        recent.insert(person, at: 0)
        save()
    }

    /// Call when you meet a player in a game. `address` is where they host (known when you joined them).
    /// Returns true when they're a friend, so the game can say so.
    @discardableResult
    public func met(id: String?, name: String, look: String?, address: String?, myID: String) -> Bool {
        guard let id, PlayerIdentity.isValid(id), id != myID else { return false }
        func update(_ p: inout Person) {
            p.name = PlayerIdentity.cleanName(name).isEmpty ? p.name : PlayerIdentity.cleanName(name)
            if let look, !look.isEmpty { p.look = look }
            if let address, !address.isEmpty { p.address = address }
            p.lastPlayed = Date()
        }
        if let index = friends.firstIndex(where: { $0.id == id }) {
            update(&friends[index])
            save()
            return true
        }
        var person = recent.first { $0.id == id } ?? Person(id: id, name: name)
        update(&person)
        recent.removeAll { $0.id == id }
        recent.insert(person, at: 0)
        if recent.count > 20 { recent.removeLast(recent.count - 20) }
        save()
        return false
    }

    public func status(_ id: String) -> Status {
        lock.lock(); defer { lock.unlock() }
        return statuses[id] ?? .unknown
    }

    /// How many friends are hosting a game right now (as of the last check).
    public var playingCount: Int {
        friends.filter { if case .hosting = status($0.id) { return true } else { return false } }.count
    }

    /// "Friends", or "Friends (2 on)" when some are hosting.
    public var buttonLabel: String { playingCount > 0 ? "Friends (\(playingCount) on)" : "Friends" }

    /// Checks, in the background, which friends are hosting a game right now.
    public func refreshStatuses() {
        for friend in friends {
            guard let address = friend.address, status(friend.id) != .checking else { continue }
            setStatus(friend.id, .checking)
            let id = friend.id
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let reply = StatusProbe.check(address: address)
                // Only count it when the host really is this friend (or an older host that doesn't say who it is).
                let isThem = reply.map { $0.hostID == nil || $0.hostID == id } ?? false
                self?.setStatus(id, isThem ? .hosting(world: reply!.world, players: reply!.players) : .offline)
            }
        }
    }

    private func setStatus(_ id: String, _ status: Status) {
        lock.lock(); statuses[id] = status; lock.unlock()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try AtomicFile.write(encoder.encode(File(friends: friends, recent: recent, myAddress: myAddress)), to: url)
        } catch {
            Log.error("Couldn't save the friends list: \(error)", category: "Friends")
        }
    }
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
