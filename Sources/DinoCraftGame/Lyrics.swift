import Foundation
import DinoCraftCore

/// Sing-along lines for songs with words (Resources/Data/lyrics.json), timed in seconds.
enum SongLyrics {
    private struct Line: Decodable { let t: Double; let line: String }

    private static let songs: [String: [Line]] = {
        guard let url = try? ResourceLocator.url("Data/lyrics.json"), let data = try? Data(contentsOf: url),
              let songs = try? JSONDecoder().decode([String: [Line]].self, from: data) else { return [:] }
        return songs
    }()

    /// The line being sung `time` seconds into `track`, or nil between verses.
    static func line(track: String?, time: Double?) -> String? {
        guard let track, let time, let lines = songs[track] else { return nil }
        for (i, l) in lines.enumerated() where time >= l.t - 0.2 {
            let end = i + 1 < lines.count ? min(lines[i + 1].t - 0.2, l.t + 4) : l.t + 4
            if time < end { return l.line }
        }
        return nil
    }

    /// Music for Toonland: the boss theme while King Grumblesaurus is on stage, otherwise the sing-along.
    static func toonlandTrack(_ s: GameSession) -> String {
        s.mobs.boss(near: s.player.position) != nil ? "grumble_stomp" : "sunny_side_up"
    }
}
