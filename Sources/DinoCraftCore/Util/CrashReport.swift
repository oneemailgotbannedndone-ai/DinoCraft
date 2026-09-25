import Foundation

/// Spots when DinoCraft crashed last time (the crash handler writes a marker and backtrace into
/// that run's log) so the launcher can offer to copy the report or post it on GitHub.
public struct CrashReport: Sendable {
    public let log: URL
    /// The end of the crashed run's log, backtrace included.
    public let text: String

    /// The most recent earlier log, if that run crashed. Call after `Log.shared.start`.
    public static func fromLastRun() -> CrashReport? {
        let directory = GamePaths.logs
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return nil }
        let current = Log.shared.currentLogURL?.lastPathComponent
        let logs = files.filter { $0.lastPathComponent.hasPrefix("dinocraft-") && $0.pathExtension == "log" && $0.lastPathComponent != current }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        guard let previous = logs.first, let data = try? Data(contentsOf: previous),
              let text = String(data: data, encoding: .utf8) else { return nil }
        guard text.contains("*** DinoCraft crashed") || text.contains("[FATAL]") || text.contains("Fatal error") else { return nil }
        // Already reported (dismissed or sent) crashes aren't offered again.
        let seen = GamePaths.root.appendingPathComponent("crash-seen.txt")
        if (try? String(contentsOf: seen, encoding: .utf8)) == previous.lastPathComponent { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return CrashReport(log: previous, text: lines.suffix(80).joined(separator: "\n"))
    }

    /// Don't offer this crash again.
    public func dismiss() {
        try? log.lastPathComponent.write(to: GamePaths.root.appendingPathComponent("crash-seen.txt"), atomically: true, encoding: .utf8)
    }

    /// A pre-filled GitHub issue with the report (trimmed to fit in a web address).
    public func issueURL(repository: String, build: String, platform: String) -> URL? {
        var body = "DinoCraft crashed (\(platform), \(build)).\n\nWhat were you doing when it happened?\n\n\n---\n```\n"
        body += String(text.suffix(5500))
        body += "\n```"
        var parts = URLComponents(string: "https://github.com/\(repository)/issues/new")
        parts?.queryItems = [URLQueryItem(name: "title", value: "Crash report: \(platform) \(build)"), URLQueryItem(name: "body", value: body)]
        return parts?.url
    }
}
