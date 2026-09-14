import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// Asks the home router to forward the game port so friends on other networks
/// can join. Tries NAT-PMP / PCP-style mapping first (Apple and many modern
/// routers), then UPnP IGD. Everything is local traffic to the router — no
/// external servers are contacted.
final class PortMapper {
    struct Mapping {
        let method: String
        let externalIP: String?
        let port: UInt16
    }

    enum Failure: Error, CustomStringConvertible {
        case noGateway
        case unsupported
        case refused(String)

        var description: String {
            switch self {
            case .noGateway: return "Couldn't find your router."
            case .unsupported: return "Your router doesn't allow automatic port opening (UPnP / NAT-PMP is off or missing)."
            case .refused(let why): return "Your router refused to open the port (\(why))."
            }
        }
    }

    private let queue = DispatchQueue(label: "com.dinocraft.portmapper", qos: .utility)
    private(set) var active: Mapping?
    private var upnpControl: (url: URL, service: String)?

    // MARK: Public API (results delivered on the main queue)

    /// Read-only: discovers the router and its public address without changing anything.
    func probe(completion: @escaping (String) -> Void) {
        queue.async {
            var lines: [String] = []
            let gateway = PortMapper.defaultGateway()
            lines.append("gateway \(gateway ?? "none")")
            if let gateway, let ip = PortMapper.natpmpExternalAddress(gateway: gateway) {
                lines.append("NAT-PMP external address \(ip)")
            } else {
                lines.append("NAT-PMP unavailable")
            }
            if let control = PortMapper.discoverUPnP() {
                lines.append("UPnP IGD \(control.service) at \(control.url.host ?? "?")")
                if let ip = PortMapper.upnpExternalAddress(control) { lines.append("UPnP external address \(ip)") }
            } else {
                lines.append("UPnP IGD not found")
            }
            let text = lines.joined(separator: " · ")
            DispatchQueue.main.async { completion(text) }
        }
    }

    func map(port: UInt16, completion: @escaping (Result<Mapping, Failure>) -> Void) {
        queue.async {
            let result = self.mapSync(port: port)
            DispatchQueue.main.async {
                if case .success(let m) = result { self.active = m }
                completion(result)
            }
        }
    }

    func unmap() {
        guard let mapping = active else { return }
        active = nil
        let control = upnpControl
        queue.async {
            if mapping.method == "NAT-PMP", let gateway = PortMapper.defaultGateway() {
                _ = PortMapper.natpmpMap(gateway: gateway, port: mapping.port, lifetime: 0)
            } else if let control {
                _ = PortMapper.upnpDelete(control, port: mapping.port)
            }
            Log.info("Removed router port mapping for \(mapping.port)", category: "Net")
        }
    }

    // MARK: Mapping

    private func mapSync(port: UInt16) -> Result<Mapping, Failure> {
        guard let gateway = PortMapper.defaultGateway() else { return .failure(.noGateway) }
        if PortMapper.natpmpMap(gateway: gateway, port: port, lifetime: 7200) {
            let ip = PortMapper.natpmpExternalAddress(gateway: gateway)
            Log.info("Router opened port \(port) via NAT-PMP (public address \(ip ?? "unknown"))", category: "Net")
            return .success(Mapping(method: "NAT-PMP", externalIP: ip, port: port))
        }
        guard let control = PortMapper.discoverUPnP() else { return .failure(.unsupported) }
        upnpControl = control
        guard let local = NetworkInfo.localIPv4() else { return .failure(.noGateway) }
        switch PortMapper.upnpAdd(control, port: port, client: local) {
        case .success:
            let ip = PortMapper.upnpExternalAddress(control)
            Log.info("Router opened port \(port) via UPnP (public address \(ip ?? "unknown"))", category: "Net")
            return .success(Mapping(method: "UPnP", externalIP: ip, port: port))
        case .failure(let error):
            return .failure(error)
        }
    }

    /// True for addresses that are not reachable from the internet (router behind another router, or carrier-grade NAT).
    static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return true }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (0, _): return true
        case (172, 16...31), (192, 168), (169, 254): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    // MARK: Gateway

    static func defaultGateway() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/route")
        process.arguments = ["-n", "get", "default"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                let value = trimmed.dropFirst("gateway:".count).trimmingCharacters(in: .whitespaces)
                return value.split(separator: ".").count == 4 ? value : nil
            }
        }
        return nil
    }

    // MARK: NAT-PMP (RFC 6886)

    private static func udpExchange(host: String, port: UInt16, payload: [UInt8], expectOpcode: UInt8, timeout: Int = 1, attempts: Int = 3) -> [UInt8]? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: timeout, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return nil }
        for _ in 0..<attempts {
            let sent = payload.withUnsafeBytes { buf in
                withUnsafePointer(to: &addr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
                }
            }
            guard sent == payload.count else { continue }
            var reply = [UInt8](repeating: 0, count: 64)
            let n = recv(fd, &reply, reply.count, 0)
            if n >= 8 && reply[1] == expectOpcode { return Array(reply.prefix(n)) }
        }
        return nil
    }

    static func natpmpExternalAddress(gateway: String) -> String? {
        guard let r = udpExchange(host: gateway, port: 5351, payload: [0, 0], expectOpcode: 128), r.count >= 12,
              r[2] == 0 && r[3] == 0 else { return nil }
        return "\(r[8]).\(r[9]).\(r[10]).\(r[11])"
    }

    static func natpmpMap(gateway: String, port: UInt16, lifetime: UInt32) -> Bool {
        var payload: [UInt8] = [0, 2, 0, 0]
        payload += [UInt8(port >> 8), UInt8(port & 0xFF), UInt8(port >> 8), UInt8(port & 0xFF)]
        payload += [UInt8(lifetime >> 24), UInt8((lifetime >> 16) & 0xFF), UInt8((lifetime >> 8) & 0xFF), UInt8(lifetime & 0xFF)]
        guard let r = udpExchange(host: gateway, port: 5351, payload: payload, expectOpcode: 130), r.count >= 16 else { return false }
        return r[2] == 0 && r[3] == 0
    }

    // MARK: UPnP IGD

    static func discoverUPnP() -> (url: URL, service: String)? {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var tv = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(1900).bigEndian
        inet_pton(AF_INET, "239.255.255.250", &addr.sin_addr)
        let search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
        let bytes = Array(search.utf8)
        _ = bytes.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
        }
        var locations: [URL] = []
        let deadline = Date().addingTimeInterval(2.5)
        while Date() < deadline {
            var reply = [UInt8](repeating: 0, count: 2048)
            let n = recv(fd, &reply, reply.count, 0)
            guard n > 0 else { break }
            let text = String(decoding: reply.prefix(n), as: UTF8.self)
            for line in text.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("location:") {
                let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if let url = URL(string: value), !locations.contains(url) { locations.append(url) }
            }
        }
        for location in locations {
            guard let xml = httpGet(location) else { continue }
            for service in ["urn:schemas-upnp-org:service:WANIPConnection:2", "urn:schemas-upnp-org:service:WANIPConnection:1",
                            "urn:schemas-upnp-org:service:WANPPPConnection:1"] {
                guard let range = xml.range(of: "<serviceType>\(service)</serviceType>"),
                      let controlStart = xml.range(of: "<controlURL>", range: range.upperBound..<xml.endIndex),
                      let controlEnd = xml.range(of: "</controlURL>", range: controlStart.upperBound..<xml.endIndex) else { continue }
                let path = String(xml[controlStart.upperBound..<controlEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
                if let url = URL(string: path, relativeTo: location)?.absoluteURL { return (url, service) }
            }
        }
        return nil
    }

    private static func httpGet(_ url: URL) -> String? {
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "GET"
        return synchronous(request).flatMap { String(data: $0.0, encoding: .utf8) }
    }

    private static func synchronous(_ request: URLRequest) -> (Data, Int)? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data, Int)?
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = [:]
        URLSession(configuration: config).dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse { result = (data, http.statusCode) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 4)
        return result
    }

    private static func soap(_ control: (url: URL, service: String), action: String, arguments: String) -> (String, Int)? {
        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="\(control.service)">\(arguments)</u:\(action)></s:Body></s:Envelope>
        """
        var request = URLRequest(url: control.url, timeoutInterval: 3)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=\"utf-8\"", forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(control.service)#\(action)\"", forHTTPHeaderField: "SOAPAction")
        request.httpBody = Data(body.utf8)
        return synchronous(request).map { (String(decoding: $0.0, as: UTF8.self), $0.1) }
    }

    static func upnpExternalAddress(_ control: (url: URL, service: String)) -> String? {
        guard let (xml, status) = soap(control, action: "GetExternalIPAddress", arguments: ""), status == 200,
              let a = xml.range(of: "<NewExternalIPAddress>"), let b = xml.range(of: "</NewExternalIPAddress>") else { return nil }
        let ip = String(xml[a.upperBound..<b.lowerBound])
        return ip.isEmpty ? nil : ip
    }

    static func upnpAdd(_ control: (url: URL, service: String), port: UInt16, client: String) -> Result<Void, Failure> {
        for lease in ["7200", "0"] {
            let args = "<NewRemoteHost></NewRemoteHost><NewExternalPort>\(port)</NewExternalPort><NewProtocol>TCP</NewProtocol>"
                + "<NewInternalPort>\(port)</NewInternalPort><NewInternalClient>\(client)</NewInternalClient><NewEnabled>1</NewEnabled>"
                + "<NewPortMappingDescription>DinoCraft</NewPortMappingDescription><NewLeaseDuration>\(lease)</NewLeaseDuration>"
            guard let (xml, status) = soap(control, action: "AddPortMapping", arguments: args) else { return .failure(.unsupported) }
            if status == 200 { return .success(()) }
            if let a = xml.range(of: "<errorDescription>"), let b = xml.range(of: "</errorDescription>"), lease == "0" {
                return .failure(.refused(String(xml[a.upperBound..<b.lowerBound])))
            }
        }
        return .failure(.refused("error"))
    }

    static func upnpDelete(_ control: (url: URL, service: String), port: UInt16) -> Bool {
        let args = "<NewRemoteHost></NewRemoteHost><NewExternalPort>\(port)</NewExternalPort><NewProtocol>TCP</NewProtocol>"
        return soap(control, action: "DeletePortMapping", arguments: args)?.1 == 200
    }
}
