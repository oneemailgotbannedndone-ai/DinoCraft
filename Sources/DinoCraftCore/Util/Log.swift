import Foundation

public enum LogLevel: Int, Comparable, Sendable {
    case debug = 0, info, warning, error, fatal

    public static func < (a: LogLevel, b: LogLevel) -> Bool { a.rawValue < b.rawValue }

    var tag: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO "
        case .warning: return "WARN "
        case .error: return "ERROR"
        case .fatal: return "FATAL"
        }
    }
}

/// Thread-safe file + console logger.
///
/// Each launch writes `logs/dinocraft-<timestamp>.log`; older logs beyond the
/// retention count are pruned. Writes happen on a private serial queue so the
/// render and generation threads never block on disk I/O. Error and fatal
/// messages are flushed synchronously so they survive a crash.
public final class Log: @unchecked Sendable {
    public static let shared = Log()

    private let queue = DispatchQueue(label: "com.dinocraft.log", qos: .utility)
    private var handle: FileHandle?
    private let formatter: DateFormatter
    private var recent: [String] = []
    private let recentCapacity = 200

    public private(set) var currentLogURL: URL?
    /// Raw descriptor of the open log file, for async-signal-safe crash reporting (-1 if none).
    public var fileDescriptor: Int32 {
        #if os(Windows)
        return -1
        #else
        return queue.sync { handle?.fileDescriptor ?? -1 }
        #endif
    }
    public var minimumLevel: LogLevel = .debug
    public var echoToConsole = true

    private init() {
        formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    }

    /// Opens a new log file in `directory`, keeping at most `keep` previous logs.
    public func start(directory: URL, keep: Int = 10) {
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                pruneOldLogs(in: directory, keep: keep)
                let stamp = DateFormatter()
                stamp.locale = Locale(identifier: "en_US_POSIX")
                stamp.dateFormat = "yyyyMMdd-HHmmss"
                let url = directory.appendingPathComponent("dinocraft-\(stamp.string(from: Date())).log")
                FileManager.default.createFile(atPath: url.path, contents: nil)
                handle = try FileHandle(forWritingTo: url)
                currentLogURL = url
            } catch {
                try? FileHandle.standardError.write(contentsOf: Data("[DinoCraft] Could not open log file in \(directory.path): \(error)\n".utf8))
            }
        }
    }

    private func pruneOldLogs(in directory: URL, keep: Int) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let logs = files.filter { $0.lastPathComponent.hasPrefix("dinocraft-") && $0.pathExtension == "log" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in logs.dropFirst(max(0, keep - 1)) {
            try? FileManager.default.removeItem(at: old)
        }
    }

    public func write(_ level: LogLevel, _ category: String, _ message: String, file: String, line: Int) {
        guard level >= minimumLevel else { return }
        let thread = Thread.isMainThread ? "main" : "bg"
        let now = Date()
        let body = { [self] in
            let text = "\(formatter.string(from: now)) [\(level.tag)] [\(category)] (\(thread)) \(message)  <\(file):\(line)>\n"
            recent.append(text)
            if recent.count > recentCapacity { recent.removeFirst(recent.count - recentCapacity) }
            if let data = text.data(using: .utf8) {
                try? handle?.write(contentsOf: data)
                // The throwing form: a closed console (Windows games hide theirs) must not crash the game.
                if echoToConsole { try? FileHandle.standardError.write(contentsOf: data) }
            }
            if level >= .error { try? handle?.synchronize() }
        }
        if level >= .error { queue.sync(execute: body) } else { queue.async(execute: body) }
    }

    /// The most recent log lines, used in crash reports and the debug overlay.
    public func recentLines() -> [String] { queue.sync { recent } }

    public func flush() { queue.sync { try? handle?.synchronize() } }

    // MARK: Convenience

    public static func debug(_ message: @autoclosure () -> String, category: String = "Game", file: String = #fileID, line: Int = #line) {
        guard shared.minimumLevel <= .debug else { return }
        shared.write(.debug, category, message(), file: file, line: line)
    }
    public static func info(_ message: @autoclosure () -> String, category: String = "Game", file: String = #fileID, line: Int = #line) {
        shared.write(.info, category, message(), file: file, line: line)
    }
    public static func warning(_ message: @autoclosure () -> String, category: String = "Game", file: String = #fileID, line: Int = #line) {
        shared.write(.warning, category, message(), file: file, line: line)
    }
    public static func error(_ message: @autoclosure () -> String, category: String = "Game", file: String = #fileID, line: Int = #line) {
        shared.write(.error, category, message(), file: file, line: line)
    }
    public static func fatal(_ message: @autoclosure () -> String, category: String = "Game", file: String = #fileID, line: Int = #line) {
        shared.write(.fatal, category, message(), file: file, line: line)
    }
}

/// Well-known on-disk locations. Everything DinoCraft stores lives locally under
/// `~/Library/Application Support/DinoCraft` (overridable with `DINOCRAFT_HOME`
/// for testing).
public enum GamePaths {
    public static var root: URL {
        if let override = ProcessInfo.processInfo.environment["DINOCRAFT_HOME"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("DinoCraft", isDirectory: true)
    }
    public static var worlds: URL { root.appendingPathComponent("worlds", isDirectory: true) }
    public static var logs: URL { root.appendingPathComponent("logs", isDirectory: true) }
    public static var screenshots: URL { root.appendingPathComponent("screenshots", isDirectory: true) }
    public static var settingsFile: URL { root.appendingPathComponent("settings.json") }

    public static func ensureDirectories() throws {
        for dir in [root, worlds, logs, screenshots] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
