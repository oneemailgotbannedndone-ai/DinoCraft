import Foundation
import DinoCraftCore

// AssetForge — generates DinoCraft's original art and audio into Resources/.
//
//   swift run AssetForge [textures] [sounds] [music] [icon]
//
// With no arguments every asset group is regenerated. Output is deterministic.

let args = Set(CommandLine.arguments.dropFirst())
let all = args.isEmpty
let fm = FileManager.default
guard let resources = ResourceLocator.root else {
    FileHandle.standardError.write(Data("AssetForge: run from the repository root (Resources/ not found)\n".utf8))
    exit(1)
}

func ensureDir(_ url: URL) {
    try? fm.createDirectory(at: url, withIntermediateDirectories: true)
}

var failures = 0

if all || args.contains("textures") {
    let blocksDir = resources.appendingPathComponent("Textures/blocks")
    let itemsDir = resources.appendingPathComponent("Textures/items")
    let miscDir = resources.appendingPathComponent("Textures/misc")
    [blocksDir, itemsDir, miscDir].forEach(ensureDir)

    let registry = try BlockRegistry.loadDefault()
    let items = try ItemRegistry.loadDefault(blocks: registry)
    let painted = TexturePainter.blockTextures()
    for name in registry.textureNames {
        guard let canvas = painted[name] else {
            print("  ✗ no painter for block texture '\(name)'")
            failures += 1
            continue
        }
        try canvas.write(to: blocksDir.appendingPathComponent("\(name).png"))
    }
    for name in items.textureNames {
        try TexturePainter.paintItem(name).write(to: itemsDir.appendingPathComponent("\(name).png"))
    }
    for stage in 0..<10 {
        try TexturePainter.paintCrack(stage: stage).write(to: miscDir.appendingPathComponent("crack_\(stage).png"))
    }
    var paintedBlocks: [String: Canvas] = [:], paintedItems: [String: Canvas] = [:]
    for name in registry.textureNames { paintedBlocks[name] = painted[name] }
    for name in items.textureNames { paintedItems[name] = TexturePainter.paintItem(name) }
    let packs = try TexturePackForge.generate(into: resources.appendingPathComponent("TexturePacks"), blocks: paintedBlocks, items: paintedItems)
    for (id, count) in packs.sorted(by: { $0.key < $1.key }) { print("texture pack \(id): \(count) textures") }
    print("textures: \(registry.textureNames.count) block, \(items.textureNames.count) item, 10 crack stages")
}

if all || args.contains("sounds") {
    let dir = resources.appendingPathComponent("Sounds")
    ensureDir(dir)
    let count = try SoundSynth.generateEffects(into: dir)
    print("sounds: \(count) effects")
}

if all || args.contains("music") {
    let dir = resources.appendingPathComponent("Music")
    ensureDir(dir)
    let count = try MusicComposer.generate(into: dir)
    let songs = try SongComposer.generate(music: dir, data: resources.appendingPathComponent("Data"))
    print("music: \(count) tracks, \(songs) Toonland songs")
}

if all || args.contains("icon") {
    try IconPainter.generate(resources: resources)
    print("icon: generated")
}

exit(failures == 0 ? 0 : 1)
