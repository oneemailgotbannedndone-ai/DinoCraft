import Foundation
import DinoCraftCore

/// The step-by-step guide to beating DinoCraft: from the first log to cheering up
/// King Grumblesaurus in Toonland. Each step is finished by an advancement.
enum GameGuide {
    struct Step {
        let advancement: String
        let title: String
        let hint: String
    }

    static let steps: [Step] = [
        Step(advancement: "timber", title: "Punch a tree", hint: "Hold left-click on a log until it breaks."),
        Step(advancement: "workbench", title: "Craft a Crafting Bench", hint: "Press E: turn logs into planks, 4 planks make a bench."),
        Step(advancement: "upgrade", title: "Make a Stone Pickaxe", hint: "Mine stone with a wooden pickaxe, craft at the bench."),
        Step(advancement: "hot_stuff", title: "Smelt some iron", hint: "Iron ore + coal in a furnace (8 cobblestone)."),
        Step(advancement: "lighter", title: "Craft an Ember Lighter", hint: "Flint (dig gravel) + an iron ingot."),
        Step(advancement: "checkered", title: "Craft Checker Blocks", hint: "Coal + bone meal (from dino bones). You need 10."),
        Step(advancement: "toonland", title: "Open the Checker Gateway", hint: "Frame 4 wide, 5 tall. Strike inside with the lighter."),
        Step(advancement: "grumblesaurus", title: "Cheer up King Grumblesaurus", hint: "Follow a checkered road to his stage. Dodge the ink!"),
    ]

    /// The first unfinished step and its number (1-based), or nil once the game is beaten.
    static func current(_ advancements: AdvancementTracker) -> (number: Int, step: Step)? {
        for (i, step) in steps.enumerated() where !advancements.isUnlocked(step.advancement) {
            return (i + 1, step)
        }
        return nil
    }

    /// Short tips shown on the loading screens.
    static let tips: [String] = [
        "Press G to show or hide the guide to beating DinoCraft.",
        "Hold Ctrl to sprint. Sprinting is fast now, but it makes you hungry.",
        "Bone Blocks, Amber Blocks and Checker Blocks each build a different gateway.",
        "King Grumblesaurus stomps the ground: jump or keep your distance!",
        "Sunblooms glow in Toonland's meadows. Pick a few to light your base!",
        "Press F5 to see yourself from behind or from the front.",
        "Beds skip the night and set your spawn point.",
        "Villagers trade emeralds for tools, food and treasure.",
        "Draw your own skin in the launcher's Skin Creator.",
        "Texture packs and shader packs are in Settings.",
        "Raptors hunt in packs at night. Carry a torch.",
        "Farmland needs water within four blocks to grow crops fast.",
        "Press F2 to take a screenshot.",
        "The Skylands float above a sea of walkable clouds.",
    ]
}
