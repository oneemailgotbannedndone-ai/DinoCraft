import Foundation

/// Short, typo-tolerant codes for sharing a multiplayer address, e.g. `DINO-3M4KA-9QX2B`.
///
/// The code packs an IPv4 address and port (48 bits) into ten Crockford
/// base-32 characters, so friends can type it without mixing up O/0 or I/1/L.
public enum InviteCode {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func encode(ip: String, port: UInt16) -> String? {
        let parts = ip.split(separator: ".").compactMap { UInt64($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 < 256 }), port > 0 else { return nil }
        var value = (parts[0] << 40) | (parts[1] << 32) | (parts[2] << 24) | (parts[3] << 16) | UInt64(port)
        value <<= 2
        var chars: [Character] = []
        for shift in stride(from: 45, through: 0, by: -5) {
            chars.append(alphabet[Int((value >> UInt64(shift)) & 31)])
        }
        let body = String(chars)
        return "DINO-\(body.prefix(5))-\(body.suffix(5))"
    }

    /// Decodes a code; returns nil for anything that isn't one (such as a plain IP address or host name).
    public static func decode(_ text: String) -> (ip: String, port: UInt16)? {
        let upper = text.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard upper.hasPrefix("DINO") || upper.contains("-") else { return nil }
        let body = (upper.hasPrefix("DINO") ? String(upper.dropFirst(4)) : upper).filter { $0 != "-" && $0 != " " }
        guard body.count == 10 else { return nil }
        var value: UInt64 = 0
        for ch in body {
            let normalized: Character = ch == "O" ? "0" : ((ch == "I" || ch == "L") ? "1" : ch)
            guard let index = alphabet.firstIndex(of: normalized) else { return nil }
            value = (value << 5) | UInt64(index)
        }
        value >>= 2
        let port = UInt16(value & 0xFFFF)
        guard port > 0 else { return nil }
        let ip = "\((value >> 40) & 255).\((value >> 32) & 255).\((value >> 24) & 255).\((value >> 16) & 255)"
        return (ip, port)
    }
}
