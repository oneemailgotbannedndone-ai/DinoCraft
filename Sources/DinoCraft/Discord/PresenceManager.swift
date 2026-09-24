import Foundation
import DinoCraftCore
@testable import DinoCraftGame

/// Facts about what the player is doing, reported by the game every frame.
/// The presence layer — not gameplay code — decides how to phrase it.
///
/// To add a future activity, add a field here, set it where the game knows it,
/// and add one rule in `PresenceFormatter`.
struct GameActivityState: Equatable {
    enum Scene: Equatable {
        case mainMenu, worldSelection, worldCreation, loading(newWorld: Bool), settings, credits, playing
    }

    var scene: Scene = .mainMenu
    var gameMode: GameMode?
    var worldName: String?
    var biome: String?
    var dimension: WorldDimension = .overworld
    var fighting: String?
    var hardcore = false
    var spectating = false
    var paused = false
    var inventoryOpen = false
    var crafting = false
    var underground = false
    var swimming = false
    var flying = false
    var mining = false
    var building = false
    var dead = false
    var multiplayer: String?
}

struct PresenceActivity: Equatable {
    var details: String
    var state: String?
    var largeImage = "dinocraft_logo"
    var largeText = "DinoCraft"
    var smallImage: String?
    var smallText: String?
}

enum PresenceFormatter {
    static func activity(for s: GameActivityState, showWorldName: Bool) -> PresenceActivity {
        switch s.scene {
        case .mainMenu:
            return PresenceActivity(details: "In the Main Menu")
        case .worldSelection:
            return PresenceActivity(details: "Choosing a world")
        case .worldCreation:
            return PresenceActivity(details: "Creating a new world")
        case .loading(let isNew):
            let details = s.dimension != .overworld ? "Traveling to \(s.dimension.displayName)"
                : (isNew ? "Generating a new world" : "Loading a world")
            return PresenceActivity(details: details, state: showWorldName ? s.worldName : nil)
        case .settings:
            return PresenceActivity(details: "Changing settings")
        case .credits:
            return PresenceActivity(details: "Watching the credits")
        case .playing:
            let mode = s.gameMode ?? .survival
            let modeName = s.spectating ? "Spectator" : (s.hardcore ? "Hardcore" : mode.displayName)
            let details: String
            if s.dead {
                details = s.hardcore ? "Hardcore • Game Over" : "\(modeName) • Respawning"
            } else if s.paused {
                details = "Paused"
            } else if s.crafting {
                details = "Crafting"
            } else if s.inventoryOpen {
                details = "Managing inventory"
            } else if let foe = s.fighting {
                details = "Fighting a \(foe)"
            } else if s.spectating {
                details = "Spectating a fallen world"
            } else if s.swimming {
                details = "Swimming"
            } else if s.flying {
                details = "\(modeName) • Flying"
            } else if s.mining {
                details = s.underground ? "\(modeName) • Mining underground" : "\(modeName) • Mining"
            } else if s.building {
                details = "\(modeName) • Building"
            } else if s.dimension == .underworld {
                details = "Exploring the Underworld"
            } else if s.dimension == .skylands {
                details = "Exploring the Amber Skylands"
            } else if s.dimension == .toonland {
                details = "Having fun in Toonland"
            } else if s.underground {
                details = "Exploring underground"
            } else {
                details = "\(modeName) • Exploring"
            }
            var state: String?
            if let mp = s.multiplayer {
                state = mp
            } else if showWorldName, let name = s.worldName {
                state = name
            } else if let biome = s.biome, !s.underground {
                state = "In the \(biome)"
            }
            return PresenceActivity(details: details, state: state,
                                    smallImage: mode == .creative ? "mode_creative" : "mode_survival",
                                    smallText: "\(modeName) Mode")
        }
    }
}

/// The single owner of Discord Rich Presence. Receives game state, formats it,
/// rate-limits updates (Discord allows ~5 per 20 s) and survives Discord being
/// absent. Nothing else in the codebase talks to Discord.
final class PresenceManager {
    private var client: DiscordIPCClient?
    private let applicationID: String?
    private let startDate = Date()
    private var enabled = false
    private var lastSent: PresenceActivity?
    private var pending: PresenceActivity?
    private var lastSendTime = Date.distantPast
    private let minInterval: TimeInterval = 4

    init() {
        applicationID = PresenceManager.loadApplicationID()
        if applicationID == nil {
            Log.info("Discord Rich Presence is not configured (no applicationId in discord.json)", category: "Discord")
        }
    }

    static func loadApplicationID() -> String? {
        var candidates = [GamePaths.root.appendingPathComponent("discord.json")]
        if let bundled = try? ResourceLocator.url("Data/discord.json") { candidates.append(bundled) }
        for url in candidates {
            guard let data = try? Data(contentsOf: url) else { continue }
            guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                Log.warning("Ignoring malformed \(url.path)", category: "Discord")
                continue
            }
            if let id = obj["applicationId"] as? String, !id.isEmpty, id.allSatisfy(\.isNumber) { return id }
        }
        return nil
    }

    func setEnabled(_ on: Bool) {
        guard on != enabled else { return }
        enabled = on
        if on, let id = applicationID {
            client = DiscordIPCClient(clientID: id)
            lastSent = nil
        } else if !on {
            client?.stop()
            client = nil
        }
    }

    var statusText: String {
        guard enabled else { return "Disabled" }
        guard applicationID != nil else { return "Not configured — add an applicationId to discord.json" }
        switch client?.status {
        case .connected(let user)?: return "Connected" + (user.map { " as \($0)" } ?? "")
        case .unavailable(let reason)?: return reason
        default: return "Connecting…"
        }
    }

    /// Call every frame; cheap when nothing changed.
    func update(_ state: GameActivityState, showWorldName: Bool) {
        guard enabled, let client else { return }
        let activity = PresenceFormatter.activity(for: state, showWorldName: showWorldName)
        if activity != lastSent { pending = activity }
        guard let next = pending, Date().timeIntervalSince(lastSendTime) >= minInterval else { return }
        client.setActivity(payload(for: next))
        lastSent = next
        pending = nil
        lastSendTime = Date()
    }

    private func payload(for a: PresenceActivity) -> [String: Any] {
        func clamp(_ s: String) -> String {
            var t = s
            if t.count < 2 { t += "  " }
            return String(t.prefix(128))
        }
        var assets: [String: Any] = ["large_image": a.largeImage, "large_text": clamp(a.largeText)]
        if let small = a.smallImage { assets["small_image"] = small }
        if let text = a.smallText { assets["small_text"] = clamp(text) }
        var activity: [String: Any] = [
            "details": clamp(a.details),
            "timestamps": ["start": Int(startDate.timeIntervalSince1970)],
            "assets": assets,
            "type": 0,
        ]
        if let state = a.state, !state.isEmpty { activity["state"] = clamp(state) }
        return activity
    }

    func shutdown() {
        client?.stop()
        client = nil
    }
}
