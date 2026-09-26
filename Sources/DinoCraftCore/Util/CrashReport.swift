import Foundation

/// Spots when DinoCraft crashed last time (the crash handler writes a marker and backtrace into
/// that run's log) so the launcher can offer to copy the report or post it on GitHub.
public struct CrashReport: Sendable {
    public let log: URL
    /// The end of the crashed run's log, backtrace included.
    public let text: String

    public init(log: URL, text: String) {
        self.log = log
        self.text = text
    }

    /// The most recent earlier log, if that run crashed. Call after `Log.shared.start`.
    public static func fromLastRun() -> CrashReport? {
        let directory = GamePaths.logs
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        let current = Log.shared.currentLogURL?.lastPathComponent
        let logs = files.filter { $0.lastPathComponent.hasPrefix("dinocraft-") && $0.pathExtension == "log" && $0.lastPathComponent != current }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let previous = logs.first, let data = try? Data(contentsOf: previous),
              var text = String(data: data, encoding: .utf8) else { return nil }
        // On Windows, Swift's own "Fatal error" message and the crash details land in a file beside the log.
        if let extra = try? String(contentsOf: companion(of: previous), encoding: .utf8),
           !extra.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            text += "\n" + extra
        }
        guard text.contains("*** DinoCraft crashed") || text.contains("[FATAL]") || text.contains("Fatal error") else { return nil }
        // Already reported (dismissed or sent) crashes aren't offered again.
        let seen = GamePaths.root.appendingPathComponent("crash-seen.txt")
        if (try? String(contentsOf: seen, encoding: .utf8)) == previous.lastPathComponent { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return CrashReport(log: previous, text: lines.suffix(80).joined(separator: "\n"))
    }

    /// Where a run's error output goes (Windows): `dinocraft-<time>.log` → `dinocraft-<time>.err.txt`.
    public static func companion(of log: URL) -> URL {
        log.deletingPathExtension().appendingPathExtension("err.txt")
    }

    /// Don't offer this crash again.
    public func dismiss() {
        try? log.lastPathComponent.write(to: GamePaths.root.appendingPathComponent("crash-seen.txt"), atomically: true, encoding: .utf8)
    }

    /// A pre-filled GitHub issue with the report (trimmed to fit in a web address).
    /// `maxLength` keeps the whole address short enough for the browser to be opened with it (the
    /// end of the report, where the crash is, is kept).
    public func issueURL(repository: String, build: String, platform: String, maxLength: Int = 12_000) -> URL? {
        var keep = 5500
        while true {
            var body = "DinoCraft crashed (\(platform), \(build)).\n\nWhat were you doing when it happened?\n\n\n---\n```\n"
            body += String(text.suffix(keep))
            body += "\n```"
            var parts = URLComponents(string: "https://github.com/\(repository)/issues/new")
            parts?.queryItems = [URLQueryItem(name: "title", value: "Crash report: \(platform) \(build)"), URLQueryItem(name: "body", value: body)]
            guard let url = parts?.url else { return nil }
            if url.absoluteString.count <= maxLength || keep <= 200 { return url }
            keep = keep * 3 / 4
        }
    }
}
