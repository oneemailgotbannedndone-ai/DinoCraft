import Foundation
import Darwin
import DinoCraftCore
@testable import DinoCraftGame

/// Minimal native client for Discord's local RPC socket (no SDK, no network).
///
/// Runs entirely on its own thread: discovers `discord-ipc-N` sockets, performs
/// the handshake, answers pings, and pushes the most recent activity. If Discord
/// is not installed, not running, or disconnects, it quietly retries with
/// backoff — the game never waits on it.
final class DiscordIPCClient: @unchecked Sendable {
    enum Status: Equatable {
        case connecting
        case connected(user: String?)
        case unavailable(String)
    }

    private enum Opcode: UInt32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    private let clientID: String
    private let lock = NSLock()
    private var desiredActivity: [String: Any]?
    private var desiredVersion = 0
    private var sentVersion = -1
    private var running = true
    private var clearOnStop = false
    private let stopped = DispatchSemaphore(value: 0)

    // Thread-confined state
    private var fd: Int32 = -1
    private var ready = false
    private var failures = 0
    private var nextAttempt = Date.distantPast
    private var statusValue: Status = .connecting

    var status: Status {
        lock.lock(); defer { lock.unlock() }
        return statusValue
    }

    init(clientID: String) {
        self.clientID = clientID
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "DinoCraft Discord RPC"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Sets (or clears, with nil) the activity. Only the latest value is sent.
    func setActivity(_ activity: [String: Any]?) {
        lock.lock()
        desiredActivity = activity
        desiredVersion += 1
        lock.unlock()
    }

    /// Clears the activity and closes the socket (waits up to 1 s).
    func stop() {
        lock.lock()
        clearOnStop = true
        running = false
        lock.unlock()
        _ = stopped.wait(timeout: .now() + 1)
    }

    private func setStatus(_ s: Status) {
        lock.lock(); statusValue = s; lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    // MARK: Loop

    private func run() {
        while isRunning {
            if fd < 0 {
                if Date() >= nextAttempt { attemptConnection() }
                if fd < 0 { Thread.sleep(forTimeInterval: 0.5); continue }
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let result = poll(&pfd, 1, 200)
            if result > 0 {
                if pfd.revents & Int16(POLLIN) != 0 {
                    if !readFrame() { disconnect("Discord closed the connection"); continue }
                } else if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                    disconnect("Discord connection lost")
                    continue
                }
            } else if result < 0 && errno != EINTR {
                disconnect("poll failed (\(errno))")
                continue
            }
            if ready { flushActivity() }
        }
        if fd >= 0 {
            if ready && clearOnStop {
                _ = writeFrame(.frame, ["cmd": "SET_ACTIVITY", "args": ["pid": Int(getpid()), "activity": NSNull()], "nonce": UUID().uuidString])
            }
            close(fd)
            fd = -1
        }
        stopped.signal()
    }

    // MARK: Connection

    private func socketPaths() -> [String] {
        var dirs: [String] = []
        let env = ProcessInfo.processInfo.environment
        for key in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"] {
            if let v = env[key], !v.isEmpty { dirs.append(v) }
        }
        var buf = [CChar](repeating: 0, count: 1024)
        if confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, buf.count) > 0 { dirs.append(String(cString: buf)) }
        dirs.append(NSTemporaryDirectory())
        dirs.append("/tmp")
        var seen = Set<String>(), paths: [String] = []
        for d in dirs {
            let base = d.hasSuffix("/") ? String(d.dropLast()) : d
            guard seen.insert(base).inserted else { continue }
            for i in 0..<10 { paths.append("\(base)/discord-ipc-\(i)") }
        }
        return paths
    }

    private func attemptConnection() {
        setStatus(.connecting)
        for path in socketPaths() where FileManager.default.fileExists(atPath: path) {
            let s = socket(AF_UNIX, SOCK_STREAM, 0)
            guard s >= 0 else { continue }
            var one: Int32 = 1
            setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let pathBytes = Array(path.utf8CString)
            guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { close(s); continue }
            withUnsafeMutableBytes(of: &addr.sun_path) { raw in
                for (i, b) in pathBytes.enumerated() { raw[i] = UInt8(bitPattern: b) }
            }
            addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
            let rc = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(s, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard rc == 0 else { close(s); continue }
            fd = s
            ready = false
            sentVersion = -1
            if writeFrame(.handshake, ["v": 1, "client_id": clientID]) {
                Log.info("Connected to Discord IPC at \(path); handshaking", category: "Discord")
                return
            }
            disconnect("handshake write failed")
        }
        failures += 1
        let delay = min(60, 5.0 * Double(failures))
        nextAttempt = Date().addingTimeInterval(delay)
        setStatus(.unavailable("Discord is not running"))
        if failures == 1 || failures % 10 == 0 {
            Log.info("Discord not detected; will retry in \(Int(delay))s", category: "Discord")
        }
    }

    private func disconnect(_ reason: String, retryAfter: TimeInterval = 10) {
        if fd >= 0 { close(fd) }
        fd = -1
        ready = false
        nextAttempt = Date().addingTimeInterval(retryAfter)
        setStatus(.unavailable(reason))
        Log.info("Discord disconnected: \(reason)", category: "Discord")
    }

    // MARK: Framing

    private func writeFrame(_ op: Opcode, _ object: [String: Any]) -> Bool {
        guard fd >= 0, let json = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var data = Data(capacity: json.count + 8)
        withUnsafeBytes(of: op.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(json)
        return data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    private func readExactly(_ count: Int) -> Data? {
        var data = Data(count: count)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            var offset = 0
            while offset < count {
                let n = Darwin.read(fd, raw.baseAddress! + offset, count - offset)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
        return ok ? data : nil
    }

    private func readFrame() -> Bool {
        guard let header = readExactly(8) else { return false }
        let op = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
        guard length < 1 << 20, let body = length > 0 ? readExactly(Int(length)) : Data() else { return false }
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

        switch Opcode(rawValue: op) {
        case .frame:
            let evt = object["evt"] as? String
            if evt == "READY" {
                ready = true
                failures = 0
                let user = ((object["data"] as? [String: Any])?["user"] as? [String: Any])?["username"] as? String
                setStatus(.connected(user: user))
                Log.info("Discord ready\(user.map { " (user \($0))" } ?? "")", category: "Discord")
            } else if evt == "ERROR" {
                let message = (object["data"] as? [String: Any])?["message"] as? String ?? "unknown error"
                Log.warning("Discord RPC error: \(message)", category: "Discord")
            }
        case .close:
            let message = object["message"] as? String ?? "closed"
            let code = object["code"] as? Int ?? 0
            Log.warning("Discord refused the connection (\(code)): \(message)", category: "Discord")
            disconnect("Discord refused: \(message)", retryAfter: code == 4000 ? 300 : 30)
            return true
        case .ping:
            _ = writeFrame(.pong, object)
        default:
            break
        }
        return true
    }

    private func flushActivity() {
        lock.lock()
        let version = desiredVersion
        let activity = desiredActivity
        lock.unlock()
        guard version != sentVersion else { return }
        let activityValue: Any = activity ?? NSNull()
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(getpid()), "activity": activityValue],
            "nonce": UUID().uuidString,
        ]
        if writeFrame(.frame, payload) {
            sentVersion = version
        } else {
            disconnect("failed to send activity")
        }
    }
}
