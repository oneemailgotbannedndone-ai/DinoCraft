import Foundation

/// Asks the home router to forward the game port so friends on other networks can join (portable
/// version of the Mac app's `PortMapper`, used by the Windows game). Tries NAT-PMP first, then UPnP IGD.
/// Everything is local traffic to the router; no outside servers are contacted.
public enum PortMapping {
    public struct Mapping: Sendable {
        public let method: String
        public let externalIP: String?
        public let port: UInt16
        let gateway: String?
        let control: URL?
        let service: String?
    }

    public enum Failure: Error, CustomStringConvertible {
        case noNetwork
        case unsupported
        case refused(String)

        public var description: String {
            switch self {
            case .noNetwork: return "Couldn't find your router."
            case .unsupported: return "Your router doesn't allow automatic port opening (UPnP / NAT-PMP is off or missing)."
            case .refused(let why): return "Your router refused to open the port (\(why))."
            }
        }
    }

    /// Blocking; call from a background thread.
    public static func map(port: UInt16) -> Result<Mapping, Failure> {
        guard let local = NetSocket.localIPv4() else { return .failure(.noNetwork) }
        for gateway in gatewayCandidates(local: local) where natpmpMap(gateway: gateway, port: port, lifetime: 7200) {
            let ip = natpmpExternalAddress(gateway: gateway)
            Log.info("Router opened port \(port) via NAT-PMP (public address \(ip ?? "unknown"))", category: "Net")
            return .success(Mapping(method: "NAT-PMP", externalIP: ip, port: port, gateway: gateway, control: nil, service: nil))
        }
        guard let control = discoverUPnP() else { return .failure(.unsupported) }
        for lease in ["7200", "0"] {
            let args = "<NewRemoteHost></NewRemoteHost><NewExternalPort>\(port)</NewExternalPort><NewProtocol>TCP</NewProtocol>"
                + "<NewInternalPort>\(port)</NewInternalPort><NewInternalClient>\(local)</NewInternalClient><NewEnabled>1</NewEnabled>"
                + "<NewPortMappingDescription>DinoCraft</NewPortMappingDescription><NewLeaseDuration>\(lease)</NewLeaseDuration>"
            guard let (xml, status) = soap(control, action: "AddPortMapping", arguments: args) else { return .failure(.unsupported) }
            if status == 200 {
                let ip = upnpExternalAddress(control)
                Log.info("Router opened port \(port) via UPnP (public address \(ip ?? "unknown"))", category: "Net")
                return .success(Mapping(method: "UPnP", externalIP: ip, port: port, gateway: nil, control: control.url, service: control.service))
            }
            if lease == "0" {
                return .failure(.refused(between(xml, "<errorDescription>", "</errorDescription>") ?? "error \(status)"))
            }
        }
        return .failure(.refused("error"))
    }

    /// Removes a mapping made by `map` (blocking, a few seconds at most).
    public static func unmap(_ mapping: Mapping) {
        if let gateway = mapping.gateway {
            _ = natpmpMap(gateway: gateway, port: mapping.port, lifetime: 0)
        } else if let url = mapping.control, let service = mapping.service {
            let args = "<NewRemoteHost></NewRemoteHost><NewExternalPort>\(mapping.port)</NewExternalPort><NewProtocol>TCP</NewProtocol>"
            _ = soap((url, service), action: "DeletePortMapping", arguments: args)
        }
        Log.info("Removed router port mapping for \(mapping.port)", category: "Net")
    }

    /// Read-only: reports what the router supports without changing anything.
    public static func probe() -> String {
        var lines: [String] = []
        let local = NetSocket.localIPv4()
        lines.append("local \(local ?? "none")")
        if let local {
            let found = gatewayCandidates(local: local).lazy.compactMap { g in natpmpExternalAddress(gateway: g).map { (g, $0) } }.first
            lines.append(found.map { "NAT-PMP at \($0.0), external address \($0.1)" } ?? "NAT-PMP unavailable")
        }
        if let control = discoverUPnP() {
            lines.append("UPnP IGD \(control.service) at \(control.url.host ?? "?")")
            if let ip = upnpExternalAddress(control) { lines.append("UPnP external address \(ip)") }
        } else {
            lines.append("UPnP IGD not found")
        }
        return lines.joined(separator: " · ")
    }

    /// True for addresses that are not reachable from the internet (double NAT or carrier-grade NAT).
    public static func isPrivate(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return true }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (0, _): return true
        case (172, 16...31), (192, 168), (169, 254): return true
        case (100, 64...127): return true
        default: return false
        }
    }

    /// Home routers almost always sit at .1 (or .254) of the local /24.
    public static func gatewayCandidates(local: String) -> [String] {
        let parts = local.split(separator: ".")
        guard parts.count == 4 else { return [] }
        let prefix = parts.prefix(3).joined(separator: ".")
        return ["\(prefix).1", "\(prefix).254"].filter { $0 != local }
    }

    // MARK: NAT-PMP (RFC 6886)

    static func natpmpExternalAddress(gateway: String) -> String? {
        let replies = NetSocket.udpExchange(host: gateway, port: 5351, payload: [0, 0], window: 0.6, attempts: 2) { $0.count >= 12 && $0[1] == 128 }
        guard let r = replies.last(where: { $0.count >= 12 && $0[1] == 128 }), r[2] == 0 && r[3] == 0 else { return nil }
        return "\(r[8]).\(r[9]).\(r[10]).\(r[11])"
    }

    static func natpmpMap(gateway: String, port: UInt16, lifetime: UInt32) -> Bool {
        var payload: [UInt8] = [0, 2, 0, 0]
        payload += [UInt8(port >> 8), UInt8(port & 0xFF), UInt8(port >> 8), UInt8(port & 0xFF)]
        payload += [UInt8(lifetime >> 24), UInt8((lifetime >> 16) & 0xFF), UInt8((lifetime >> 8) & 0xFF), UInt8(lifetime & 0xFF)]
        let replies = NetSocket.udpExchange(host: gateway, port: 5351, payload: payload, window: 0.6, attempts: 2) { $0.count >= 16 && $0[1] == 130 }
        guard let r = replies.last(where: { $0.count >= 16 && $0[1] == 130 }) else { return false }
        return r[2] == 0 && r[3] == 0
    }

    // MARK: UPnP IGD

    static func discoverUPnP() -> (url: URL, service: String)? {
        let search = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: urn:schemas-upnp-org:device:InternetGatewayDevice:1\r\n\r\n"
        let replies = NetSocket.udpExchange(host: "239.255.255.250", port: 1900, payload: Array(search.utf8), window: 2.5) { _ in false }
        var locations: [URL] = []
        for reply in replies {
            let text = String(decoding: reply, as: UTF8.self)
            for line in text.components(separatedBy: "\r\n") where line.lowercased().hasPrefix("location:") {
                let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
                if let url = URL(string: value), !locations.contains(url) { locations.append(url) }
            }
        }
        for location in locations {
            guard let (xml, status) = http(location, method: "GET", headers: [], body: nil), status == 200,
                  let found = controlURL(in: xml, location: location) else { continue }
            return found
        }
        return nil
    }

    /// Finds the WAN connection service's control URL in a device description.
    public static func controlURL(in xml: String, location: URL) -> (url: URL, service: String)? {
        for service in ["urn:schemas-upnp-org:service:WANIPConnection:2", "urn:schemas-upnp-org:service:WANIPConnection:1",
                        "urn:schemas-upnp-org:service:WANPPPConnection:1"] {
            guard let range = xml.range(of: "<serviceType>\(service)</serviceType>"),
                  let controlStart = xml.range(of: "<controlURL>", range: range.upperBound..<xml.endIndex),
                  let controlEnd = xml.range(of: "</controlURL>", range: controlStart.upperBound..<xml.endIndex) else { continue }
            let path = String(xml[controlStart.upperBound..<controlEnd.lowerBound]).trimmingCharacters(in: .whitespaces)
            if let url = URL(string: path, relativeTo: location)?.absoluteURL { return (url, service) }
        }
        return nil
    }

    private static func soap(_ control: (url: URL, service: String), action: String, arguments: String) -> (String, Int)? {
        let body = """
        <?xml version="1.0"?>
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
        <s:Body><u:\(action) xmlns:u="\(control.service)">\(arguments)</u:\(action)></s:Body></s:Envelope>
        """
        return http(control.url, method: "POST", headers: ["Content-Type: text/xml; charset=\"utf-8\"", "SOAPAction: \"\(control.service)#\(action)\""],
                    body: Data(body.utf8))
    }

    static func upnpExternalAddress(_ control: (url: URL, service: String)) -> String? {
        guard let (xml, status) = soap(control, action: "GetExternalIPAddress", arguments: ""), status == 200,
              let ip = between(xml, "<NewExternalIPAddress>", "</NewExternalIPAddress>"), !ip.isEmpty else { return nil }
        return ip
    }

    private static func between(_ text: String, _ start: String, _ end: String) -> String? {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return nil }
        return String(text[a.upperBound..<b.lowerBound])
    }

    // MARK: Minimal HTTP/1.1 (routers are on the LAN; no TLS)

    static func http(_ url: URL, method: String, headers: [String], body: Data?) -> (String, Int)? {
        guard url.scheme == "http", let host = url.host else { return nil }
        let port = UInt16(url.port ?? 80)
        guard let socket = try? NetSocket.connect(host: host, port: port) else { return nil }
        defer { socket.close() }
        socket.setReceiveTimeout(3)
        var path = url.path.isEmpty ? "/" : url.path
        if let query = url.query { path += "?" + query }
        var request = "\(method) \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\nUser-Agent: DinoCraft\r\n"
        for header in headers { request += header + "\r\n" }
        request += "Content-Length: \(body?.count ?? 0)\r\n\r\n"
        var data = Data(request.utf8)
        if let body { data.append(body) }
        guard socket.send(data) else { return nil }
        var response = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 8192)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let n = socket.receive(into: &buffer)
            if n <= 0 { break }
            response += buffer.prefix(n)
            if response.count > 1 << 20 { break }
        }
        return parseResponse(response)
    }

    public static func parseResponse(_ bytes: [UInt8]) -> (String, Int)? {
        let separator: [UInt8] = [13, 10, 13, 10]
        guard bytes.count >= 12, let split = (0...(bytes.count - 4)).first(where: { Array(bytes[$0..<($0 + 4)]) == separator }) else { return nil }
        let head = String(decoding: bytes[0..<split], as: UTF8.self)
        let statusParts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        guard statusParts.count >= 2, let status = Int(statusParts[1]) else { return nil }
        var body = Array(bytes[(split + 4)...])
        if head.lowercased().contains("transfer-encoding: chunked") {
            var decoded: [UInt8] = []
            var i = 0
            while i < body.count {
                guard let lineEnd = (i..<max(i, body.count - 1)).first(where: { body[$0] == 13 && body[$0 + 1] == 10 }) else { break }
                let sizeText = String(decoding: body[i..<lineEnd], as: UTF8.self).split(separator: ";").first ?? ""
                guard let size = Int(sizeText.trimmingCharacters(in: .whitespaces), radix: 16), size > 0 else { break }
                let start = lineEnd + 2
                decoded += body[start..<min(body.count, start + size)]
                i = start + size + 2
            }
            body = decoded
        }
        return (String(decoding: body, as: UTF8.self), status)
    }
}
