import Foundation
#if os(Windows)
import WinSDK
#else
import Darwin
#endif

/// Minimal blocking TCP socket for the portable multiplayer client (used by the
/// Windows game and the self-test). The Mac app's host and client use Apple's
/// Network framework; both speak the same `Wire` protocol.
public final class NetSocket: @unchecked Sendable {
    #if os(Windows)
    typealias Handle = SOCKET
    private static let invalidHandle: SOCKET = ~SOCKET(0)
    private static let started: Bool = {
        var data = WSADATA()
        return WSAStartup(0x0202, &data) == 0
    }()
    #else
    typealias Handle = Int32
    private static let invalidHandle: Int32 = -1
    private static let started = true
    #endif

    public enum SocketError: Error, CustomStringConvertible {
        case unavailable
        case resolve(String)
        case connect(String)
        case listen(String)

        public var description: String {
            switch self {
            case .unavailable: return "Networking isn't available on this computer."
            case .resolve(let message), .connect(let message), .listen(let message): return message
            }
        }
    }

    private let handle: Handle
    private let sendLock = NSLock()
    private let stateLock = NSLock()
    private var closed = false

    private init(handle: Handle) {
        self.handle = handle
    }

    deinit { close() }

    // MARK: Connecting

    public static func connect(host: String, port: UInt16) throws -> NetSocket {
        guard started else { throw SocketError.unavailable }
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            throw SocketError.resolve("Couldn't find \(host). Check the invite code or address.")
        }
        defer { freeaddrinfo(first) }
        var entry: UnsafeMutablePointer<addrinfo>? = first
        while let info = entry {
            let h = makeSocket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
            if h != invalidHandle {
                if connectHandle(h, info.pointee.ai_addr, Int(info.pointee.ai_addrlen)) {
                    let socket = NetSocket(handle: h)
                    socket.configure()
                    return socket
                }
                closeHandle(h)
            }
            entry = info.pointee.ai_next
        }
        throw SocketError.connect("Couldn't connect to \(host):\(port). Make sure your friend's world is open and the code is right.")
    }

    /// Listens for incoming connections (port 0 picks a free port; see `localPort`).
    public static func listen(port: UInt16, loopbackOnly: Bool) throws -> NetSocket {
        guard started else { throw SocketError.unavailable }
        let h = makeSocket(AF_INET, SOCK_STREAM, 0)
        guard h != invalidHandle else { throw SocketError.listen("Couldn't create a network socket.") }
        var addr = sockaddr_in()
        #if os(Windows)
        withUnsafePointer(to: Int32(1)) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 4) { _ = setsockopt(h, SOL_SOCKET, SO_REUSEADDR, $0, 4) }
        }
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.S_un.S_addr = loopbackOnly ? UInt32(0x7F00_0001).bigEndian : 0
        #else
        var one: Int32 = 1
        _ = setsockopt(h, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = loopbackOnly ? UInt32(0x7F00_0001).bigEndian : 0
        #endif
        let size = MemoryLayout<sockaddr_in>.size
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bindHandle(h, $0, size) } }
        guard bound, listenHandle(h) else {
            closeHandle(h)
            throw SocketError.listen("Port \(port) is already in use.")
        }
        return NetSocket(handle: h)
    }

    public var localPort: UInt16 {
        var addr = sockaddr_in()
        #if os(Windows)
        var length = Int32(MemoryLayout<sockaddr_in>.size)
        #else
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        #endif
        let ok = withUnsafeMutablePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(handle, $0, &length) == 0 } }
        return ok ? UInt16(bigEndian: addr.sin_port) : 0
    }

    /// This computer's LAN IPv4 address (the one it would use to reach the internet), if any.
    /// Uses an unconnected UDP socket, so no packets are sent.
    public static func localIPv4() -> String? {
        guard started else { return nil }
        #if os(Windows)
        let h = WinSDK.socket(AF_INET, 2 /* SOCK_DGRAM */, 0)
        #else
        let h = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        #endif
        guard h != invalidHandle else { return nil }
        defer { closeHandle(h) }
        let size = MemoryLayout<sockaddr_in>.size
        var remote = sockaddr_in()
        #if os(Windows)
        remote.sin_family = ADDRESS_FAMILY(AF_INET)
        remote.sin_port = UInt16(53).bigEndian
        remote.sin_addr.S_un.S_addr = UInt32(0x0808_0808).bigEndian
        var length = Int32(size)
        #else
        remote.sin_len = UInt8(size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = UInt16(53).bigEndian
        remote.sin_addr.s_addr = UInt32(0x0808_0808).bigEndian
        var length = socklen_t(size)
        #endif
        let connected = withUnsafeMutablePointer(to: &remote) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connectHandle(h, $0, size) } }
        guard connected else { return nil }
        var local = sockaddr_in()
        let named = withUnsafeMutablePointer(to: &local) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(h, $0, &length) == 0 } }
        guard named else { return nil }
        #if os(Windows)
        let raw = UInt32(bigEndian: local.sin_addr.S_un.S_addr)
        #else
        let raw = UInt32(bigEndian: local.sin_addr.s_addr)
        #endif
        guard raw != 0 else { return nil }
        return "\(raw >> 24).\((raw >> 16) & 255).\((raw >> 8) & 255).\(raw & 255)"
    }

    /// Makes `receive` give up after `seconds` (it then returns -1).
    public func setReceiveTimeout(_ seconds: Double) {
        NetSocket.setTimeout(handle, seconds)
    }

    private static func setTimeout(_ h: Handle, _ seconds: Double) {
        #if os(Windows)
        withUnsafePointer(to: UInt32(max(1, seconds * 1000))) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 4) { _ = setsockopt(h, SOL_SOCKET, SO_RCVTIMEO, $0, 4) }
        }
        #else
        var tv = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        _ = setsockopt(h, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        #endif
    }

    /// Parses a dotted IPv4 address into a host-order integer.
    public static func parseIPv4(_ text: String) -> UInt32? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ ($0 ?? 256) < 256 }) else { return nil }
        return parts.reduce(0) { $0 << 8 | $1! }
    }

    /// Sends a UDP datagram and collects replies until `window` seconds pass or `done` returns true.
    /// Repeats the send up to `attempts` times while nothing useful arrived (for NAT-PMP and SSDP).
    public static func udpExchange(host: String, port: UInt16, payload: [UInt8], window: Double, attempts: Int = 1,
                                   done: ([UInt8]) -> Bool) -> [[UInt8]] {
        guard started, let ip = parseIPv4(host) else { return [] }
        #if os(Windows)
        let h = WinSDK.socket(AF_INET, 2 /* SOCK_DGRAM */, 0)
        #else
        let h = Darwin.socket(AF_INET, SOCK_DGRAM, 0)
        #endif
        guard h != invalidHandle else { return [] }
        defer { closeHandle(h) }
        setTimeout(h, min(window, 0.5))
        let size = MemoryLayout<sockaddr_in>.size
        var addr = sockaddr_in()
        #if os(Windows)
        addr.sin_family = ADDRESS_FAMILY(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.S_un.S_addr = ip.bigEndian
        #else
        addr.sin_len = UInt8(size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = ip.bigEndian
        #endif
        var replies: [[UInt8]] = []
        for _ in 0..<max(1, attempts) {
            let sent = payload.withUnsafeBytes { buf -> Int in
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa -> Int in
                        #if os(Windows)
                        return Int(WinSDK.sendto(h, buf.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(buf.count), 0, sa, Int32(size)))
                        #else
                        return Darwin.sendto(h, buf.baseAddress, buf.count, 0, sa, socklen_t(size))
                        #endif
                    }
                }
            }
            guard sent == payload.count else { continue }
            let deadline = Date().addingTimeInterval(window)
            while Date() < deadline {
                var reply = [UInt8](repeating: 0, count: 2048)
                let n = reply.withUnsafeMutableBytes { raw -> Int in
                    #if os(Windows)
                    return Int(WinSDK.recv(h, raw.baseAddress!.assumingMemoryBound(to: CChar.self), Int32(raw.count), 0))
                    #else
                    return Darwin.recv(h, raw.baseAddress, raw.count, 0)
                    #endif
                }
                guard n > 0 else { continue }
                let bytes = Array(reply.prefix(n))
                replies.append(bytes)
                if done(bytes) { return replies }
            }
            if !replies.isEmpty { return replies }
        }
        return replies
    }

    public func accept() -> NetSocket? {
        #if os(Windows)
        let h = WinSDK.accept(handle, nil, nil)
        #else
        let h = Darwin.accept(handle, nil, nil)
        #endif
        guard h != NetSocket.invalidHandle else { return nil }
        let socket = NetSocket(handle: h)
        socket.configure()
        return socket
    }

    // MARK: Data

    /// Blocks until data arrives. Returns the byte count, 0 when the other side closed, or -1 on error.
    public func receive(into buffer: inout [UInt8]) -> Int {
        buffer.withUnsafeMutableBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            #if os(Windows)
            return Int(WinSDK.recv(handle, base.assumingMemoryBound(to: CChar.self), Int32(raw.count), 0))
            #else
            return Darwin.recv(handle, base, raw.count, 0)
            #endif
        }
    }

    /// Sends everything; returns false if the connection is gone.
    public func send(_ data: Data) -> Bool {
        sendLock.lock()
        defer { sendLock.unlock() }
        return data.withUnsafeBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return true }
            var left = raw.count
            while left > 0 {
                #if os(Windows)
                let n = Int(WinSDK.send(handle, pointer.assumingMemoryBound(to: CChar.self), Int32(min(left, 1 << 20)), 0))
                #else
                let n = Darwin.send(handle, pointer, left, 0)
                #endif
                if n <= 0 { return false }
                left -= n
                pointer += n
            }
            return true
        }
    }

    public func close() {
        stateLock.lock()
        let wasClosed = closed
        closed = true
        stateLock.unlock()
        guard !wasClosed else { return }
        #if os(Windows)
        _ = WinSDK.shutdown(handle, 2)
        #else
        _ = Darwin.shutdown(handle, SHUT_RDWR)
        #endif
        NetSocket.closeHandle(handle)
    }

    // MARK: Platform calls

    private func configure() {
        #if os(Windows)
        withUnsafePointer(to: Int32(1)) { p in
            p.withMemoryRebound(to: CChar.self, capacity: 4) { _ = setsockopt(handle, 6 /* IPPROTO_TCP */, TCP_NODELAY, $0, 4) }
        }
        #else
        var one: Int32 = 1
        _ = setsockopt(handle, IPPROTO_TCP, TCP_NODELAY, &one, socklen_t(MemoryLayout<Int32>.size))
        _ = setsockopt(handle, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    #if os(Windows)
    private static func makeSocket(_ family: Int32, _ type: Int32, _ proto: Int32) -> Handle { WinSDK.socket(family, type, proto) }
    private static func connectHandle(_ h: Handle, _ addr: UnsafeMutablePointer<sockaddr>?, _ length: Int) -> Bool {
        WinSDK.connect(h, addr, Int32(length)) == 0
    }
    private static func bindHandle(_ h: Handle, _ addr: UnsafePointer<sockaddr>, _ size: Int) -> Bool { WinSDK.bind(h, addr, Int32(size)) == 0 }
    private static func listenHandle(_ h: Handle) -> Bool { WinSDK.listen(h, 8) == 0 }
    private static func closeHandle(_ h: Handle) { _ = closesocket(h) }
    #else
    private static func makeSocket(_ family: Int32, _ type: Int32, _ proto: Int32) -> Handle { Darwin.socket(family, type, proto) }
    private static func connectHandle(_ h: Handle, _ addr: UnsafeMutablePointer<sockaddr>?, _ length: Int) -> Bool {
        Darwin.connect(h, addr, socklen_t(length)) == 0
    }
    private static func bindHandle(_ h: Handle, _ addr: UnsafePointer<sockaddr>, _ size: Int) -> Bool { Darwin.bind(h, addr, socklen_t(size)) == 0 }
    private static func listenHandle(_ h: Handle) -> Bool { Darwin.listen(h, 8) == 0 }
    private static func closeHandle(_ h: Handle) { _ = Darwin.close(h) }
    #endif
}
