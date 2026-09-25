import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Which build this copy of DinoCraft is. The release workflow writes `Resources/Data/build.json`;
/// copies built by hand don't have it and count as development builds (build 0).
public struct BuildInfo: Codable, Sendable {
    public var build: Int
    public var commit: String?
    public var date: String?

    public init(build: Int, commit: String?, date: String?) {
        self.build = build
        self.commit = commit
        self.date = date
    }

    public static let current: BuildInfo = {
        guard let url = try? ResourceLocator.url("Data/build.json"), let data = try? Data(contentsOf: url),
              let info = try? JSONDecoder().decode(BuildInfo.self, from: data) else {
            return BuildInfo(build: 0, commit: nil, date: nil)
        }
        return info
    }()

    public var isDevelopment: Bool { build <= 0 }

    /// What's new in this version (Resources/Data/whatsnew.txt), shown by the launcher.
    public static let whatsNew: String = {
        guard let url = try? ResourceLocator.url("Data/whatsnew.txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()
    public var displayName: String { isDevelopment ? "Development build" : "Build \(build)" }
}

/// A published DinoCraft version on the public releases page.
public struct GameRelease: Sendable {
    public var build: Int
    public var title: String
    public var notes: String
    public var published: String
    /// Download link for each file, by name (for example `DinoCraft-Windows.zip`).
    public var assets: [String: URL]
}

/// Checks the public releases repository for a newer build and downloads it, on a background thread.
/// The launcher polls `state` every frame; installing the download is up to each app.
public final class GameUpdater: @unchecked Sendable {
    /// The public repository the release workflow publishes to (the game's own code stays private).
    public static let releasesRepository = "oneemailgotbannedndone-ai/DinoCraft"

    public enum State: Sendable {
        case idle
        case checking
        case upToDate(GameRelease?)
        /// A newer build exists; `canInstall` is false for development builds and missing downloads.
        case available(GameRelease, canInstall: Bool)
        case downloading(GameRelease, fraction: Double)
        /// The update's zip has downloaded to `file`.
        case downloaded(GameRelease, file: URL)
        case failed(String)
    }

    /// `DinoCraft-Windows.zip` or `DinoCraft-Mac.zip`.
    public let assetName: String
    public let current: BuildInfo
    private let lock = NSLock()
    private var _state = State.idle
    private var task: URLSessionDownloadTask?

    public init(assetName: String, current: BuildInfo = .current) {
        self.assetName = assetName
        self.current = current
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        if case .downloading(let release, _) = _state, let task {
            let expected = task.countOfBytesExpectedToReceive
            let fraction = expected > 0 ? Double(task.countOfBytesReceived) / Double(expected) : 0
            return .downloading(release, fraction: min(1, max(0, fraction)))
        }
        return _state
    }

    private func set(_ s: State) {
        lock.lock()
        _state = s
        lock.unlock()
    }

    /// The newest release, as a notice for the launcher (nil until a check finishes).
    public var latestRelease: GameRelease? {
        switch state {
        case .upToDate(let r): return r
        case .available(let r, _), .downloading(let r, _), .downloaded(let r, _): return r
        default: return nil
        }
    }

    public func check() {
        if case .checking = state { return }
        if case .downloading = state { return }
        set(.checking)
        // DINOCRAFT_UPDATE_URL points the check at a test server instead of GitHub.
        let address = ProcessInfo.processInfo.environment["DINOCRAFT_UPDATE_URL"]
            ?? "https://api.github.com/repos/\(GameUpdater.releasesRepository)/releases/latest"
        guard let url = URL(string: address) else { return }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DinoCraft-Launcher", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if let error {
                Log.warning("Update check failed: \(error.localizedDescription)", category: "Update")
                self.set(.failed("Couldn't reach the update server. Check your internet connection."))
                return
            }
            if status == 403 || status == 429 {
                self.set(.failed("GitHub is busy right now (too many update checks). Try again in a while."))
                return
            }
            if status == 404 {
                self.set(.upToDate(nil))   // nothing published yet
                return
            }
            guard status == 200, let data, let release = GameUpdater.parse(data) else {
                Log.warning("Update check: unexpected reply (HTTP \(status))", category: "Update")
                self.set(.failed("The update server gave an unexpected reply (HTTP \(status))."))
                return
            }
            Log.info("Update check: newest is build \(release.build), this is \(self.current.displayName)", category: "Update")
            if release.build > self.current.build {
                self.set(.available(release, canInstall: !self.current.isDevelopment && release.assets[self.assetName] != nil))
            } else {
                self.set(.upToDate(release))
            }
        }.resume()
    }

    /// Reads GitHub's "latest release" reply.
    public static func parse(_ data: Data) -> GameRelease? {
        struct Asset: Decodable { var name: String; var browser_download_url: String }
        struct Reply: Decodable { var tag_name: String; var name: String?; var body: String?; var published_at: String?; var assets: [Asset] }
        guard let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        // Tags look like "build-42".
        let digits = reply.tag_name.filter(\.isNumber)
        guard let build = Int(digits) else { return nil }
        var assets: [String: URL] = [:]
        for a in reply.assets { if let u = URL(string: a.browser_download_url) { assets[a.name] = u } }
        // The release page starts with download instructions; the launcher only shows what's new.
        var notes = reply.body ?? ""
        if let range = notes.range(of: "## What's new") {
            notes = String(notes[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return GameRelease(build: build, title: reply.name ?? "DinoCraft build \(build)", notes: notes,
                           published: String((reply.published_at ?? "").prefix(10)), assets: assets)
    }

    /// Downloads this platform's zip for an available release.
    public func download() {
        guard case .available(let release, true) = state, let url = release.assets[assetName] else { return }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("DinoCraft-Launcher", forHTTPHeaderField: "User-Agent")
        let task = URLSession.shared.downloadTask(with: request) { [weak self] temp, response, error in
            guard let self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard error == nil, status == 200, let temp else {
                Log.warning("Update download failed: \(error?.localizedDescription ?? "HTTP \(status)")", category: "Update")
                self.set(.failed("The download didn't finish. Try again."))
                return
            }
            // The temporary file disappears when this handler returns, so keep a copy.
            let dir = FileManager.default.temporaryDirectory.appendingPathComponent("DinoCraftUpdate-\(release.build)", isDirectory: true)
            let file = dir.appendingPathComponent(self.assetName)
            do {
                try? FileManager.default.removeItem(at: dir)
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: temp, to: file)
                Log.info("Downloaded build \(release.build) to \(file.path)", category: "Update")
                self.set(.downloaded(release, file: file))
            } catch {
                self.set(.failed("Couldn't save the update: \(error.localizedDescription)"))
            }
        }
        lock.lock()
        self.task = task
        _state = .downloading(release, fraction: 0)
        lock.unlock()
        task.resume()
    }
}
