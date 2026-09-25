import Foundation

/// The credits, shown on both platforms (each names its own graphics and sound technology).
enum GameCredits {
    enum Style { case title, heading, line, spacer, thanks }

    static func lines(technology: [String]) -> [(text: String, style: Style)] {
        var out: [(String, Style)] = [
            ("DinoCraft", .title),
            ("A prehistoric voxel adventure for Mac and Windows", .line),
            ("", .spacer),
            ("DESIGN & ENGINEERING", .heading),
            ("Built for you, from scratch, in Swift", .line),
            ("", .spacer),
            ("TECHNOLOGY", .heading),
        ]
        out += technology.map { ($0, .line) }
        out += [
            ("Multithreaded chunk streaming", .line),
            ("Greedy meshing with smooth lighting & ambient occlusion", .line),
            ("One shared game for both computers: same world, creatures and items", .line),
            ("", .spacer),
            ("ART & AUDIO", .heading),
            ("All textures painted procedurally by AssetForge", .line),
            ("All sounds and music synthesized from scratch", .line),
            ("", .spacer),
            ("SOUNDTRACK", .heading),
            ("Where Giants Roamed · Fernlight · Amber Dusk", .line),
            ("Deep Strata · Titan Valley", .line),
            ("Sunny Side Up · Grumble Stomp", .line),
            ("", .spacer),
            ("SPECIAL THANKS", .heading),
            ("Every player who wrote a review", .line),
            ("Every dinosaur that ever roamed the Earth", .line),
            ("", .spacer),
            ("Thank you for playing.", .thanks),
        ]
        return out
    }
}
