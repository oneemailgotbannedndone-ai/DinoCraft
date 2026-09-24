# DinoCraft

An original prehistoric voxel sandbox built from scratch as a **native macOS app for Apple Silicon**. It uses Swift, AppKit, and Metal, with no Electron, no web views, and no engine middleware.

## What's new

The launcher update, for Mac and Windows (the full list is in `Resources/Data/whatsnew.txt`, which the launcher shows):

- **Launcher** with Play, Update, Cosmetics, Skin Creator, Settings and Quit. The Update button downloads new versions and restarts into them.
- **Skin Creator**: draw your own face and shirt, then Save & Play. Share skins with codes; friends see them in multiplayer.
- **Cosmetics**: hats, outfit colours, capes, dino tails and backpacks. Press F5 in game to see yourself.
- **Windows plays like the Mac**: the full survival game, texture and shader packs, particles, weather and settings.
- **Looks**: the Mac uses the Windows pixel font, and every built-in texture pack keeps natural colours.

## Features

- **Worlds.** Endless procedural terrain with biomes, rivers, caves, and ores (coal, iron, gold, diamond, amber, emerald). There are also two extra dimensions, the Underworld and the Amber Skylands, reached through gateways.
- **World detail.**
  - Marble and slate veins, and red rock under the badlands.
  - Palm trees on beaches, dead trees in deserts, and bushes.
  - Flowers, mushrooms and berry bushes that vary by biome.
  - Reeds and lily pads by the water, pebbles, and cactus.
  - Mossy boulders, fallen logs, ice spikes, and dinosaur fossils in the desert.
  - Stalagmites and glowing mushrooms in caves.
- **Weather and particles.**
  - Rain, snow in cold biomes, and thunderstorms with lightning flashes and thunder. Deserts and the other dry biomes stay dry.
  - Weather changes on its own; `/weather` and `/gamerule doWeatherCycle` control it.
  - Particles: block debris when you mine, torch flames and smoke, lava embers, portal sparkles, glowing motes, and ash in the Underworld.
- **Blocks.** 228 blocks, including:
  - Stairs in 8 materials, and slabs.
  - Wool, carpet, dyed clay, stained glass, and painted planks in 10 colors, with dyes made from flowers and minerals.
  - Marble, slate, and red rock bricks.
  - Lanterns, barrels, hay bales, and palm wood.
- **Advancements.** 49 advancements across Story, Adventure, Farming, and Building, with pop-ups when you earn one. Press **L**, or open **Advancements** from the pause menu.
- **Structures.**
  - Villages.
  - Hidden underground **dungeons** guarded by Bone Walkers.
  - Crumbling stone **ruins** with a half-buried chest.
  - **Desert ruins** hiding treasure at the bottom of a pit.
  - Every generated chest rolls its own loot the first time it's opened.
- **Game modes.** Survival, Hardcore (one life on Hard, then spectator mode), and Creative. New worlds can start with an optional Bonus Chest.
- **Survival.** Health and hunger, breaking with tool tiers, and dropped items you have to pick up. You also get:
  - crafting with a 2×2 or 3×3 grid and recipe book
  - chests and furnaces with smelting and fuel
  - doors and wall torches
  - slabs and storage blocks
  - **armor**: helmets, chestplates, leggings and boots in Hide, Iron and Diamond. Each armor point blocks 4% of damage from creatures and arrows (up to 80%), and pieces wear out. Right-click to wear a piece, or use the four armor slots in the inventory. An armor bar shows above your hearts.
  - **farming**: craft a hoe and right-click grass or dirt to till farmland. Plant wheat seeds (sometimes dropped by tall grass) or carrots on it. Crops grow through four stages, faster in the rain. Bone meal, made from Dino Bones, speeds them up. Ripe wheat becomes bread or hay bales.
  - **bows and arrows**: bows are made from sticks and Dino Hide, and arrows from flint, a stick and a feather. Hold right-click to draw (full power after a second) and release to shoot. Arrows arc with gravity, and a bar under the crosshair shows draw strength. In Survival you can walk over arrows stuck in blocks to pick them back up.
  - **beds** (3 wool over 3 planks): right-click to set your respawn point. At night or during a thunderstorm you sleep until morning, and the storm clears. Monsters nearby keep you awake, and only the host can skip the night in multiplayer.
- **Creatures.**
  - Farm animals: pigs, cows, sheep (including rare black sheep), and chickens, plus the **Pookpook**, a round white bird with a long orange beak that pecks back if you hit it.
  - Neutral (they fight back when attacked): Trikey, Longneck, Stegosaurus, Ankylosaurus, Parasaurolophus.
  - Harmless: Dodo, Dimetrodon.
  - Hostile at night: Raptor, Troodon packs, Compy packs, Spitter, Cave Crawler, Bone Walker, Sand Scorpion, and the rare T-Rex.
  - Big predators that also hunt in daylight: Carnotaurus, Allosaurus, Baryonyx, and the huge Spinosaurus. How many roam at once depends on difficulty.
  - Other: Magma Raptors in the Underworld, and the swooping Pteranodon in the mountains.
  - Villagers trade with emeralds; there are Farmer, Toolsmith, Mason, and Fossil Hunter professions.
- **Multiplayer (LAN / direct IP).**
  - Host any world from the pause menu with **Open to LAN**, and friends join from **Multiplayer**.
  - Shared chests and furnaces, and dropped items, stay in sync.
  - Includes chat, name tags, and PvP.
- **Packs.** Texture packs: the default **Dino** pack, **TunefulCraft** (a bright remix that also rebrands the title), **Pastel Picnic**, **Retro Pixels** and **Autumn Woods**, plus your own packs. Every built-in pack keeps natural colours, so grass stays green and water stays blue (except autumn leaves). Shader packs: Vibrant, Cinematic, Retro, and Dreamy. Both work on Mac and Windows.
- **Other.** Usernames, an FPS counter, rebindable controls, a debug profiler, Discord Rich Presence, and local saves.

## Requirements

- macOS 14 or later on Apple Silicon (developed and tested on an M4)
- Xcode Command Line Tools (`xcode-select --install`). Full Xcode is **not** required, because shaders are compiled at runtime by Metal.

> **Windows:** there is also a Windows version (SDL3 + OpenGL 3.3), built by the Windows workflow in `.github/workflows/windows.yml`. Your own worlds run the same shared game as the Mac (`Sources/DinoCraftGame`): Survival, Hardcore and Creative, creatures, crafting, furnaces, chests, farming, bows, armor, beds, villagers, portals, weather, advancements and chat commands, with rain and snow, particles, textured dropped items, the item in your hand, texture packs and shader packs. Windows players can host worlds for Mac and Windows friends, and join games hosted on a Mac. Both versions draw their text with the same 5×7 pixel font (`Sources/DinoCraftCore/Util/PixelFont.swift`).

## Build and run

```bash
Scripts/build_app.sh            # → dist/DinoCraft.app (native arm64, ad-hoc signed)
open dist/DinoCraft.app
```

Options:

```bash
Scripts/build_app.sh --test     # run the core self-test suite first
Scripts/build_app.sh --assets   # regenerate textures (including the built-in texture packs), sounds, music and icons first
Scripts/build_app.sh --install  # also copy the app into /Applications, replacing any older copy
```

Each build gets a timestamped build number, shown in Finder under **Get Info**, so you can tell which copy is newest.

Development loop without packaging:

```bash
swift build -c release --product DinoCraft && .build/release/DinoCraft
```

## Launcher, updates and cosmetics

DinoCraft opens on a **launcher** (Mac and Windows) with **Play**, **Update**, **Cosmetics**, **Skin Creator**, **Settings** and **Quit**, a "What's new" panel with the notes of the newest build, your stats (worlds and time played) and **Open Game Folder**.

- **Updates.** The launcher checks the public **DinoCraft-Releases** repository. When a newer build is there, **Update to Build N** downloads it and **Restart to Update** swaps it in and reopens the game. Worlds and settings are kept. Copies you built yourself are "development builds" and never replace themselves.
- **Skin Creator.** Paint your own face (8×8) and shirt front (8×10) with 16 colours: brush or fill, mirror painting, and ideas to start from (smile, sunglasses, dino, beard; stripes, heart, star, dino, tuxedo). **Copy Code** puts a `DINOSKIN:…` code on the clipboard for a friend to **Paste Code**. Friends see your skin in multiplayer, and **F5** in game lets you see yourself.
- **Cosmetics.** Pick a hat (Explorer Hat, Cap, Crown, Top Hat, Dino Hood, Flower Crown or none), shirt, trousers and skin colours, and something for your back (Cape, Dino Tail or Backpack) with an accent colour. Friends see your look in multiplayer on both Mac and Windows. Older versions just see the default explorer.

### Publishing updates (one-time setup)

The game's code stays private; each build is published to a separate public repository that the launcher can read.

1. On GitHub, create a **public** repository named `DinoCraft-Releases` under the same account (it can be empty).
2. Create a token that can publish there: GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate new token. Under *Repository access* choose *Only select repositories* → `DinoCraft-Releases`, and under *Permissions* set **Contents** to *Read and write*.
3. In **this** repository: Settings → Secrets and variables → Actions → **New repository secret**, name `RELEASES_TOKEN`, paste the token.

From then on every push to `main` builds Windows and Mac and publishes them as `build-N`. You can also publish from the Actions tab: run the **Windows** workflow with *Publish* ticked. Without the secret the workflow still builds and just skips publishing.

## Playing with a friend

Everyone needs DinoCraft on a Mac.

**Same Wi-Fi.** The host opens a world, presses **Esc**, and chooses **Open to LAN**. Friends open **Multiplayer** and click the game in the list.

**Different internet connections.**
1. The host opens a world, presses **Esc**, and chooses **Open to Internet**. DinoCraft asks the host's home router to open TCP port **25650** automatically, using NAT-PMP or UPnP.
2. The chat and pause menu show an **invite code** such as `DINO-3M4KA-9QX2B`. Click **Copy Invite Code** in the pause menu and send it to your friends. The code is just your public address in a shorter, easier-to-type form.
3. Friends open **Multiplayer**, paste the code into the **Invite code or address** box, and click **Join**. Case, spaces, and O/0 mix-ups don't matter.

Your friends don't need to change anything on their side; only the host's router is involved.

If the router refuses, or your internet provider hides your public address (common on mobile and some fiber plans), you have two options:
- Forward TCP port 25650 to the host's Mac in your router's settings.
- Simpler: install the free [Tailscale](https://tailscale.com) app on every Mac, sign in to the same Tailscale network, and join using the host's Tailscale address (it starts with `100.`). DinoCraft then works as if you were on the same Wi-Fi.

The router mapping is removed when you stop hosting or quit.

> **Friends on Windows** can join with the same invite code or address, using the Windows version (see Requirements).

While playing:
   - **T** opens chat and **Tab** shows who's online.
   - Hit another player to fight.
   - Chests and furnaces are shared.

The host's world is authoritative and is saved on the host's Mac. macOS may ask the host to allow incoming network connections the first time.

## Spawn eggs & commands

**Spawn eggs.** Every creature has one. Find them in the Creative inventory under **Spawn Eggs**, or get one with `/give spawn_egg_rex`. Right-click the ground to hatch it. Eggs are used up in Survival. In multiplayer, a friend's egg hatches on the host's world, so everyone sees the creature.

**Commands.** Press **T** or **/** to open chat, then type a command. Type `/help` in the game for the full list. To turn commands off for a world, untick **Allow Commands** when you create it, or use **Commands: On/Off** in the pause menu. Hardcore worlds never allow commands.

| Command | What it does |
| --- | --- |
| `/give <item> [count]` | Give yourself items, e.g. `/give diamond 5` |
| `/give <player> <item> [count]` | Give items to a friend in your game |
| `/summon <creature> [x y z]` | Spawn a creature, e.g. `/summon trex` |
| `/tp <x> <y> <z>` or `/tp <player>` | Teleport. `~` means your position, e.g. `/tp ~ ~10 ~` |
| `/time set <day\|noon\|sunset\|night\|midnight>` | Change the time of day |
| `/gamemode <survival\|creative>` | Switch mode |
| `/difficulty <peaceful\|easy\|normal\|hard>` | Change difficulty |
| `/heal`, `/clear` | Refill health and hunger, or empty your inventory |
| `/kill [creatures\|hostile]` | Defeat yourself, or clear creatures |
| `/setblock <x> <y> <z> <block>` | Place one block |
| `/fill <x1> <y1> <z1> <x2> <y2> <z2> <block>` | Fill a box, up to 32,768 blocks (`air` clears) |
| `/locate <village\|dungeon\|ruin\|desert_ruin>` | Find the nearest structure |
| `/spawnpoint` | Respawn where you're standing |
| `/dimension <overworld\|underworld\|skylands>` | Travel to a dimension |
| `/seed`, `/say <message>` | Show the seed, or announce a message |

More commands:

| Command | What it does |
| --- | --- |
| `/home`, `/sethome`, `/back` | Go home, set home, or return to where you were before a teleport or death |
| `/fly [on\|off]`, `/god [on\|off]` | Fly in Survival (double-tap jump), or take no damage |
| `/repair [all]` | Fix the tool in your hand, or every tool |
| `/gamerule <keepInventory\|doDaylightCycle\|doMobSpawning> [true\|false]` | Change world rules |
| `/day`, `/night` | Skip straight to morning or nightfall |
| `/summon <creature> <count>` | Spawn several at once, e.g. `/summon raptor 3` |
| `/locate biome <name>` | Find the nearest biome, e.g. `/locate biome red_mesa` |
| `/kill items` | Remove dropped items |
| `/fill … <block> replace <old block>` | Replace only one kind of block in the box |
| `/biome`, `/coords`, `/list` | Show your biome, your position, or who's playing |

**Suggestions and autocorrect.**
- As you type a `/` command, the chat box shows matching commands, then options for each part: items, blocks, creatures, biomes, players, and choices like `night`.
- Press **Tab** to complete a suggestion, or pick one with **↑** and **↓**.
- Typos are fixed automatically. For example, `/giv dimond 3` runs `/give diamond 3`, and chat says what was corrected.

Commands work in single-player and for the host of a multiplayer game. Friends who join can only use `/help`, `/seed`, `/locate`, `/biome`, `/coords` and `/list`. Hardcore worlds turn commands off so the challenge stays fair.

## Texture packs & shader packs

Open **Settings → Packs**.

**Texture packs.** Built in are **Dino (Default)**, **TunefulCraft** (saturated colours with equalizer stripes; it also renames the game on the title screen), **Pastel Picnic** (soft pastels), **Retro Pixels** (chunky 16-pixel look) and **Autumn Woods** (golden grass, red and orange leaves). They're made by `Tools/AssetForge/Packs.swift` from DinoCraft's own art. On Windows, choose a pack under Settings. To add your own:

1. Click **Open Texture Packs Folder**, which opens `~/Library/Application Support/DinoCraft/texturepacks/`.
2. Create a folder containing:
   ```
   my_pack/
     pack.json          { "name": "My Pack", "description": "…", "title": "DinoCraft", "titleTop": "FFE69A", "titleBottom": "F08A2E" }
     blocks/<name>.png  32×32, same names as Resources/Textures/blocks
     items/<name>.png   32×32, same names as Resources/Textures/items
   ```
   Packs can be partial. Missing textures fall back to the default art, and switching packs applies instantly.

**Shader packs.** These are post-processing looks applied to the 3D scene; the interface stays sharp. **Strength** blends them with the original image.

| Pack | Look |
| --- | --- |
| Vibrant | richer color, contrast, soft vignette |
| Cinematic | bloom, teal/amber grading, film grain, letterbox bars |
| Retro | chunky pixels, limited palette, CRT scanlines |
| Dreamy | soft glow, pastel tones, lifted shadows |

## Tests

```bash
swift run -c release DinoCraftSelfTest
```

The self-test suite covers the following:
- registries
- noise determinism
- terrain generation (determinism, biomes, caves)
- villages
- dimensions
- meshing and lighting
- physics
- inventory
- crafting
- chunk and world persistence
- settings

### End-to-end scripted tests

The game can drive itself through a script in a real window:

```bash
DINOCRAFT_HOME=/tmp/dc-test .build/release/DinoCraft --world "Test" --seed dino --script path/to/script.txt
```

Commands are documented in `Sources/DinoCraft/Engine/ScriptRunner.swift`, grouped here by purpose:

| Purpose | Commands |
| --- | --- |
| Timing and input | `wait`, `wait-world`, `look`, `look-at`, `aim-nearest`, `press`, `hold`, `click`, `shift`, `slot` |
| Items | `give`, `select`, `select-item` |
| World setup | `set-block`, `block` |
| Creatures | `spawn`, `mobs`, `face-mob` |
| Test setup and progress | `clear-area`, `advancements`, `net-probe` (read-only router check) |
| Travel and time | `dimension`, `time` |
| Containers and trading | `containers`, `trade` |
| Villages and structures | `villages`, `tp-village`, `structures`, `tp-structure`, `unstick` |
| Multiplayer | `host`, `chat`, `players`, `tp-player`, `face-player` |
| Packs | `pack`, `shader` |
| Output and exit | `screenshot`, `state`, `quit` |

Other flags:

| Flag | Effect |
| --- | --- |
| `--windowed` | Ignore the fullscreen setting |
| `--world <name>` | Open or create a world immediately |
| `--seed <text>` | Seed used for `--world` |
| `--creative` | Use Creative mode for `--world` |
| `--bonus-chest` | New `--world` starts with a bonus chest |
| `--join <host[:port]>` | Join a multiplayer game on launch |
| `--username <name>` | Set the username |
| `--screenshot <path>` | Capture a screenshot (use with `--screenshot-after <seconds>`) |
| `--exit-after <seconds>` | Quit automatically after that many seconds |

## Controls (default, rebindable in Settings)

| Action | Key |
| --- | --- |
| Move | W A S D |
| Jump / swim up (double-tap to fly in Creative) | Space |
| Sprint | Left Control |
| Crouch / sneak | Left Shift |
| Break / attack (hold in Survival) | Left click |
| Place / use / open doors, chests, furnaces / trade with villagers / eat | Right click |
| Pick block | Middle click |
| Inventory | E |
| Drop item | Q |
| Hotbar | 1–9 or scroll |
| Chat / player list (multiplayer) | T / Tab |
| Advancements | L |
| Camera: first person / behind / facing you | F5 |
| Pause | Esc |
| Debug overlay | F1 |
| Screenshot | F2 |
| Hide HUD | F3 |

Torches placed against the side of a block become wall torches. Doors, furnaces, and chests face you when placed.

## Discord Rich Presence

DinoCraft talks to the Discord desktop app directly over its local IPC socket. It needs no SDK and no network access. If Discord isn't running, the game keeps working normally and reconnects on its own when Discord starts.

To have Discord show **Playing DinoCraft**:

1. Go to <https://discord.com/developers/applications> and create an application named **DinoCraft**.
2. Copy its **Application ID**.
3. Create `~/Library/Application Support/DinoCraft/discord.json`:
   ```json
   { "applicationId": "YOUR_APPLICATION_ID" }
   ```
4. Optional: under **Rich Presence → Art Assets**, upload these images from `Resources/Art/`:
   | File | Asset key |
   | --- | --- |
   | `discord_large.png` | `dinocraft_logo` |
   | `discord_mode_survival.png` | `mode_survival` |
   | `discord_mode_creative.png` | `mode_creative` |

Presence reflects:
- menus and loading
- the game mode, including Hardcore and spectating
- the current activity (mining, building, exploring, swimming)
- which dimension you're in
- fights
- multiplayer

It uses Discord's native elapsed timer. You can turn it off, or hide just the world name, under **Settings → Discord**.

## Where things live

| Data | Location |
| --- | --- |
| Worlds (chunks, player, creatures, chests & furnaces per dimension) | `~/Library/Application Support/DinoCraft/worlds/` |
| Settings (including username, packs) | `~/Library/Application Support/DinoCraft/settings.json` |
| Your texture packs | `~/Library/Application Support/DinoCraft/texturepacks/` |
| Logs (last 10 launches, crash backtraces included) | `~/Library/Application Support/DinoCraft/logs/` |
| Screenshots | `~/Library/Application Support/DinoCraft/screenshots/` |

DinoCraft has no accounts, analytics, or telemetry. Multiplayer connects only to the computers you choose, and LAN discovery uses Bonjour on your local network.

## Architecture

```
Sources/DinoCraftCore      platform-independent engine logic (unit-tested)
  Math/      vectors, matrices (reverse-Z), frustum
  World/     chunks, simplex noise, TerrainGenerator, Villages, Dimensions (Underworld, Skylands)
  Meshing/   ChunkMesher: flood-fill sky/block light, greedy meshing with smooth light & AO, box/torch/plant shapes
  Blocks/    data-driven BlockRegistry (orientation variants, collision boxes)   (Resources/Data/blocks.json)
  Items/     ItemRegistry, Inventory, slot logic                             (Resources/Data/items.json)
  Crafting/  RecipeRegistry (shaped/shapeless/tags), SmeltingRegistry        (recipes.json, smelting.json)
  Physics/   voxel collision (per-block boxes), DDA raycasting
  Player/    PlayerController (walk, sprint, sneak, swim, fly, fall tracking)
  Save/      WorldStorage (JSON metadata, LZFSE-compressed chunks, atomic writes)
  Settings/  GameSettings + tolerant persistence

Sources/DinoCraft          the macOS application
  App/       AppKit lifecycle, window, crash handler, launch options
  Engine/    GameEngine (state machine & frame loop), JobSystem, Profiler, ScriptRunner
  Renderer/  Metal renderer, chunk/sky/model/overlay/UI passes, SDF pixel font,
             creature & player models, texture packs, shader-pack post-processing
  World/     Metal chunk meshes for the shared world
  Network/   framed TCP protocol, GameServer (host), GameClient, Bonjour LAN discovery
  UI/        immediate-mode widgets, menus, HUD, inventories, chests/furnaces, trading, multiplayer
  Audio/     AVAudioEngine effects, ambience loops and music
  Discord/   DiscordIPCClient + PresenceManager

Sources/DinoCraftGame      the shared game both apps run: GameSession, world streaming, creatures,
                           items, containers, crops, weather, advancements, chat commands
Sources/DinoCraftWin       the Windows application: SDL3 window, input and audio, OpenGL renderer,
                           menus, single-player on the shared game, hosting and joining

Tools/AssetForge           generates every texture (and the built-in texture packs), sound, music track and icon
Resources/                 data, shaders, texture packs, and the generated art and audio
```

### Performance notes (Apple M4)

- Chunks are generated, lit and meshed on a pool of worker threads, each with its own mesher scratch buffers. The main thread integrates finished results within a time budget.
- Greedy meshing merges faces whose texture and per-corner light and AO match. Geometry uses a compact 18-byte vertex and one shared quad index buffer.
- Chunk buffers use shared (unified-memory) storage, so there is no copy to the GPU.
- Frustum culling runs per chunk. Reverse-Z depth and camera-relative geometry keep far views precise.
- Texture arrays with coverage-preserving mipmaps avoid atlas bleeding. Switching texture packs swaps the arrays without remeshing.
- Shader packs cost one extra fullscreen pass and are skipped entirely when set to Off.
