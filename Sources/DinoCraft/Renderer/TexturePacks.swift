import Foundation
import DinoCraftCore
@testable import DinoCraftGame

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
