import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// A set of block/item textures. Packs may be partial: any texture they don't
/// provide falls back to DinoCraft's default art.
struct TexturePack: Identifiable {
    let id: String
    let name: String
    let description: String
    /// Game title shown on the menu and loading screens while the pack is active.
    let title: String
    let titleTop: UInt32
    let titleBottom: UInt32
    /// nil for the built-in default pack.
    let directory: URL?
    let isUser: Bool

    func url(_ kind: String, _ name: String) -> URL? {
        if let directory {
            let candidate = directory.appendingPathComponent("\(kind)/\(name).png")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return try? ResourceLocator.url("Textures/\(kind)/\(name).png")
    }
}

private struct TexturePackManifest: Codable {
    var id: String?
    var name: String
    var description: String?
    var title: String?
    var titleTop: String?
    var titleBottom: String?
}

enum TexturePackLibrary {
    static let defaultPack = TexturePack(id: "dino", name: "Dino (Default)", description: "DinoCraft's original prehistoric look.",
                                         title: "DinoCraft", titleTop: 0xFFE69A, titleBottom: 0xF08A2E, directory: nil, isUser: false)

    /// `~/Library/Application Support/DinoCraft/texturepacks` — drop pack folders here.
    static var userFolder: URL { GamePaths.root.appendingPathComponent("texturepacks", isDirectory: true) }

    static func all() -> [TexturePack] {
        var packs = [defaultPack]
        var seen: Set<String> = [defaultPack.id]
        var folders: [(URL, Bool)] = []
        if let root = ResourceLocator.root { folders.append((root.appendingPathComponent("TexturePacks", isDirectory: true), false)) }
        folders.append((userFolder, true))
        let fm = FileManager.default
        for (folder, isUser) in folders {
            guard let dirs = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { continue }
            for dir in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let manifestURL = dir.appendingPathComponent("pack.json")
                guard let data = try? Data(contentsOf: manifestURL) else { continue }
                do {
                    let m = try JSONDecoder().decode(TexturePackManifest.self, from: data)
                    let id = (m.id ?? dir.lastPathComponent).lowercased()
                    guard seen.insert(id).inserted else { continue }
                    packs.append(TexturePack(id: id, name: m.name, description: m.description ?? (isUser ? "Custom texture pack" : ""),
                                             title: m.title ?? defaultPack.title,
                                             titleTop: m.titleTop.flatMap { UInt32($0, radix: 16) } ?? defaultPack.titleTop,
                                             titleBottom: m.titleBottom.flatMap { UInt32($0, radix: 16) } ?? defaultPack.titleBottom,
                                             directory: dir, isUser: isUser))
                } catch {
                    Log.warning("Ignoring texture pack at \(dir.path): \(error)", category: "Assets")
                }
            }
        }
        return packs
    }

    /// Creates the user pack folder with instructions (first use only).
    static func prepareUserFolder() {
        let fm = FileManager.default
        try? fm.createDirectory(at: userFolder, withIntermediateDirectories: true)
        let readme = userFolder.appendingPathComponent("README.txt")
        guard !fm.fileExists(atPath: readme.path) else { return }
        let text = """
        DinoCraft texture packs
        =======================

        Make a folder here for each pack, for example:

          my_pack/
            pack.json          { "name": "My Pack", "description": "...", "title": "DinoCraft" }
            blocks/stone.png   32×32 PNG, same file names as DinoCraft.app/Contents/Resources/Textures/blocks
            items/diamond.png  32×32 PNG, same names as Resources/Textures/items

        Anything your pack leaves out uses the default texture. Optional pack.json
        keys "titleTop" and "titleBottom" (hex like "FF8AE0") recolor the title.
        Choose the pack in Settings → Packs.
        """
        try? text.write(to: readme, atomically: true, encoding: .utf8)
    }
}

/// The game title and its colors, which the active texture pack can rebrand.
enum Brand {
    static var title = TexturePackLibrary.defaultPack.title
    static var top = TexturePackLibrary.defaultPack.titleTop
    static var bottom = TexturePackLibrary.defaultPack.titleBottom

    static func apply(_ pack: TexturePack) {
        title = pack.title
        top = pack.titleTop
        bottom = pack.titleBottom
    }
}

/// Post-processing looks applied to the 3D scene (the interface stays crisp).
enum ShaderPack: String, CaseIterable {
    case off, vibrant, cinematic, retro, dreamy

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .vibrant: return "Vibrant"
        case .cinematic: return "Cinematic"
        case .retro: return "Retro"
        case .dreamy: return "Dreamy"
        }
    }

    var detail: String {
        switch self {
        case .off: return "No post-processing — the plain DinoCraft look."
        case .vibrant: return "Richer colors, extra contrast and a soft vignette."
        case .cinematic: return "Bloom, teal-and-amber grading, film grain and letterbox bars."
        case .retro: return "Chunky pixels, a limited palette and CRT scanlines."
        case .dreamy: return "Soft glow, pastel tones and lifted shadows."
        }
    }

    var index: Float { Float(ShaderPack.allCases.firstIndex(of: self) ?? 0) }
}
