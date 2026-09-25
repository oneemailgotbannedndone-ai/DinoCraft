import Foundation
import DinoCraftCore
@testable import DinoCraftGame
#if os(Windows)
import WinSDK
#endif

/// Discord Rich Presence on Windows: the same protocol as the Mac client (`DiscordIPCClient`), over
/// Discord's local named pipe (`\\.\pipe\discord-ipc-N`) instead of a Unix socket. Runs on its own
/// thread, retries quietly while Discord isn't running, and never makes the game wait.
final class WinDiscordIPC: PresenceTransport, @unchecked Sendable {
    private enum Opcode: UInt32 { case handshake = 0, frame = 1, close = 2, ping = 3, pong = 4 }

    private let clientID: String
    private let lock = NSLock()
    private var desiredActivity: [String: Any]?
    private var desiredVersion = 0
    private var sentVersion = -1
    private var running = true
    private let stopped = DispatchSemaphore(value: 0)
    private var statusValue: PresenceStatus = .connecting

    #if os(Windows)
    private var pipe: HANDLE?
    #endif
    private var ready = false
    private var failures = 0
    private var nextAttempt = Date.distantPast

    var status: PresenceStatus {
        lock.lock(); defer { lock.unlock() }
        return statusValue
    }

    init(clientID: String) {
        self.clientID = clientID
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "DinoCraft Discord RPC"
        thread.start()
    }

    func setActivity(_ activity: [String: Any]?) {
        lock.lock()
        desiredActivity = activity
        desiredVersion += 1
        lock.unlock()
    }

    func stop() {
        lock.lock()
        running = false
        lock.unlock()
        _ = stopped.wait(timeout: .now() + 1)
    }

    private func setStatus(_ s: PresenceStatus) {
        lock.lock(); statusValue = s; lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return running
    }

    private func run() {
        #if os(Windows)
        while isRunning {
            if pipe == nil {
                if Date() >= nextAttempt { attemptConnection() }
                if pipe == nil { Thread.sleep(forTimeInterval: 0.5); continue }
            }
            // Read whatever Discord has sent (the READY event, pings, errors) without blocking.
            var available: DWORD = 0
            guard PeekNamedPipe(pipe, nil, 0, nil, &available, nil) else {
                disconnect("Discord connection lost")
                continue
            }
            if available >= 8 {
                if !readFrame() { disconnect("Discord closed the connection"); continue }
                continue
            }
            if ready { flushActivity() }
            Thread.sleep(forTimeInterval: 0.2)
        }
        if pipe != nil {
            if ready {
                _ = writeFrame(.frame, ["cmd": "SET_ACTIVITY", "args": ["pid": Int(GetCurrentProcessId()), "activity": NSNull()],
                                        "nonce": UUID().uuidString])
            }
            CloseHandle(pipe)
            pipe = nil
        }
        #else
        setStatus(.unavailable("Discord Rich Presence needs Windows or macOS"))
        #endif
        stopped.signal()
    }

    #if os(Windows)
    private func attemptConnection() {
        setStatus(.connecting)
        for i in 0..<10 {
            let name = "\\\\.\\pipe\\discord-ipc-\(i)"
            let handle: HANDLE? = name.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            guard let handle, handle != INVALID_HANDLE_VALUE else { continue }
            pipe = handle
            ready = false
            sentVersion = -1
            if writeFrame(.handshake, ["v": 1, "client_id": clientID]) {
                Log.info("Connected to Discord at \(name); handshaking", category: "Discord")
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
        if let pipe { CloseHandle(pipe) }
        pipe = nil
        ready = false
        nextAttempt = Date().addingTimeInterval(retryAfter)
        setStatus(.unavailable(reason))
        Log.info("Discord disconnected: \(reason)", category: "Discord")
    }

    private func writeFrame(_ op: Opcode, _ object: [String: Any]) -> Bool {
        guard let pipe, let json = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var data = Data(capacity: json.count + 8)
        withUnsafeBytes(of: op.rawValue.littleEndian) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt32(json.count).littleEndian) { data.append(contentsOf: $0) }
        data.append(json)
        return data.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                var written: DWORD = 0
                guard WriteFile(pipe, raw.baseAddress! + offset, DWORD(raw.count - offset), &written, nil), written > 0 else { return false }
                offset += Int(written)
            }
            return true
        }
    }

    private func readExactly(_ count: Int) -> Data? {
        guard let pipe else { return nil }
        var data = Data(count: count)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            var offset = 0
            while offset < count {
                var got: DWORD = 0
                guard ReadFile(pipe, raw.baseAddress! + offset, DWORD(count - offset), &got, nil), got > 0 else { return false }
                offset += Int(got)
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
        let payload: [String: Any] = [
            "cmd": "SET_ACTIVITY",
            "args": ["pid": Int(GetCurrentProcessId()), "activity": activity ?? NSNull()],
            "nonce": UUID().uuidString,
        ]
        if writeFrame(.frame, payload) {
            sentVersion = version
        } else {
            disconnect("failed to send activity")
        }
    }
    #endif
}

/// The one Discord presence for the Windows game (menus and play share it).
enum WinPresence {
    nonisolated(unsafe) static let shared = PresenceManager { WinDiscordIPC(clientID: $0) }
}
