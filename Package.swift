// swift-tools-version:5.9
//
// DinoCraft — native voxel sandbox. The full game runs on macOS (Apple Silicon);
// the core and its self-test also build on Windows as the first step of a port.
//
// Targets
//   DinoCraftCore      Platform-independent game logic: math, noise, blocks, items,
//                      world data, terrain generation, meshing, lighting, physics,
//                      inventory, crafting, persistence, settings, logging.
//   DinoCraftGame      The shared game used by both apps: world streaming, player,
//                      creatures, items, survival, containers, weather, commands.
//   DinoCraft          The macOS application: AppKit shell, Metal renderer, UI,
//                      audio, input, Discord Rich Presence, game state machine.
//   DinoCraftSelfTest  Headless verification suite for the core (runs without
//                      XCTest so it works with only the Command Line Tools).
//   AssetForge         macOS build-time tool that paints textures and synthesizes audio.
//   DinoCraftMobile    The offline iPhone/iPad edition (UIKit + the Mac's Metal renderer).
import PackageDescription

let optimizedCore: [SwiftSetting] = [
    .unsafeFlags(["-enforce-exclusivity=unchecked", "-wmo"], .when(configuration: .release)),
]

var products: [Product] = []
var targets: [Target] = [
    .target(
        name: "DinoCraftCore",
        path: "Sources/DinoCraftCore",
        swiftSettings: optimizedCore
    ),
    // The shared game: world streaming, player, creatures, items, survival, containers,
    // crops, weather, advancements and commands. Built for both apps, which use
    // `@testable import DinoCraftGame` so the game code keeps Swift's default access level.
    .target(
        name: "DinoCraftGame",
        dependencies: ["DinoCraftCore"],
        path: "Sources/DinoCraftGame",
        swiftSettings: optimizedCore + [.unsafeFlags(["-enable-testing"])]
    ),
    .executableTarget(
        name: "DinoCraftSelfTest",
        dependencies: ["DinoCraftCore"],
        path: "Sources/DinoCraftSelfTest",
        swiftSettings: optimizedCore
    ),
]

#if os(macOS)
products.append(.executable(name: "DinoCraft", targets: ["DinoCraft"]))
targets += [
    .executableTarget(
        name: "DinoCraft",
        dependencies: ["DinoCraftCore", "DinoCraftGame"],
        path: "Sources/DinoCraft",
        swiftSettings: optimizedCore
    ),
    // Build-time tool that paints DinoCraft's original textures and
    // synthesizes its sound effects and music into Resources/.
    .executableTarget(
        name: "AssetForge",
        dependencies: ["DinoCraftCore"],
        path: "Tools/AssetForge"
    ),
    // The offline phone edition (iPhone and iPad), cross-compiled from a Mac with
    // Scripts/build_ios.sh. It has its own copy of the Mac app's renderer and screens.
    .executableTarget(
        name: "DinoCraftMobile",
        dependencies: ["DinoCraftCore", "DinoCraftGame"],
        path: "Sources/DinoCraftMobile",
        swiftSettings: optimizedCore
    ),
]
products.append(.executable(name: "DinoCraftMobile", targets: ["DinoCraftMobile"]))
#endif

#if os(Windows)
products.append(.executable(name: "DinoCraftWin", targets: ["DinoCraftWin"]))
targets += [
    // SDL3 headers and import library come from the Windows build (see .github/workflows/windows.yml).
    .systemLibrary(name: "CSDL3", path: "Sources/CSDL3"),
    // Exports the flags that make laptop drivers run the game on the NVIDIA or AMD GPU.
    .target(name: "CGPUPreference", path: "Sources/CGPUPreference"),
    .executableTarget(
        name: "DinoCraftWin",
        dependencies: ["DinoCraftCore", "DinoCraftGame", "CSDL3", "CGPUPreference"],
        path: "Sources/DinoCraftWin",
        swiftSettings: optimizedCore
    ),
]
#endif

let package = Package(
    name: "DinoCraft",
    platforms: [.macOS(.v14), .iOS(.v16)],
    products: products,
    targets: targets
)
