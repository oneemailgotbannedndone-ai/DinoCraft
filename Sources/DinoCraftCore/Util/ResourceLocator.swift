import Foundation

/// Finds DinoCraft's bundled resources (data files, textures, sounds, shaders).
///
/// Search order:
/// 1. `DINOCRAFT_RESOURCES` environment variable (tests / development override)
/// 2. The app bundle's `Contents/Resources`
/// 3. A `Resources` directory found by walking up from the executable (for
///    `swift run` during development, and DinoCraft Launcher on Windows), or the
///    resources of a `DinoCraft.app` next to DinoCraft Launcher.app
public enum ResourceLocator {
    private static let marker = "Data/blocks.json"

    public static let root: URL? = {
        let fm = FileManager.default
        if let env = ProcessInfo.processInfo.environment["DINOCRAFT_RESOURCES"], !env.isEmpty {
            let url = URL(fileURLWithPath: env, isDirectory: true)
            if fm.fileExists(atPath: url.appendingPathComponent(marker).path) { return url }
        }
        if let bundled = Bundle.main.resourceURL,
           fm.fileExists(atPath: bundled.appendingPathComponent(marker).path) {
            return bundled
        }
        var dir = URL(fileURLWithPath: CommandLine.arguments.first ?? fm.currentDirectoryPath)
            .resolvingSymlinksInPath().deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent("Resources", isDirectory: true)
            if fm.fileExists(atPath: candidate.appendingPathComponent(marker).path) { return candidate }
            // DinoCraft Launcher.app shares the resources of DinoCraft.app next to it.
            let sibling = dir.appendingPathComponent("DinoCraft.app/Contents/Resources", isDirectory: true)
            if fm.fileExists(atPath: sibling.appendingPathComponent(marker).path) { return sibling }
            dir.deleteLastPathComponent()
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Resources", isDirectory: true)
        if fm.fileExists(atPath: cwd.appendingPathComponent(marker).path) { return cwd }
        return nil
    }()

    public enum LocatorError: Error, CustomStringConvertible {
        case resourcesNotFound
        case missing(String)
        public var description: String {
            switch self {
            case .resourcesNotFound:
                return "DinoCraft could not find its Resources folder. The app bundle may be damaged — try rebuilding with Scripts/build_app.sh."
            case .missing(let path):
                return "A required game resource is missing: \(path)"
            }
        }
    }

    public static func url(_ relativePath: String) throws -> URL {
        guard let root else { throw LocatorError.resourcesNotFound }
        let url = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: url.path) else { throw LocatorError.missing(relativePath) }
        return url
    }

    public static func data(_ relativePath: String) throws -> Data {
        try Data(contentsOf: url(relativePath))
    }

    /// All files in a resource subdirectory with the given extension, sorted by name.
    public static func files(in subdirectory: String, withExtension ext: String) -> [URL] {
        guard let root else { return [] }
        let dir = root.appendingPathComponent(subdirectory, isDirectory: true)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return items.filter { $0.pathExtension.lowercased() == ext.lowercased() }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
