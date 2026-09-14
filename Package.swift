// swift-tools-version:5.9
//
// DinoCraft — native voxel sandbox. The full game runs on macOS (Apple Silicon);
// the core and its self-test also build on Windows as the first step of a port.
//
// Targets
//   DinoCraftCore      Platform-independent game logic: math, noise, blocks, items,
//                      world data, terrain generation, meshing, lighting, physics,
//                      inventory, crafting, persistence, settings, logging.
//   DinoCraft          The macOS application: AppKit shell, Metal renderer, UI,
//                      audio, input, Discord Rich Presence, game state machine.
//   DinoCraftSelfTest  Headless verification suite for the core (runs without
//                      XCTest so it works with only the Command Line Tools).
//   AssetForge         macOS build-time tool that paints textures and synthesizes audio.
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
        dependencies: ["DinoCraftCore"],
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
]
#endif

let package = Package(
    name: "DinoCraft",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
