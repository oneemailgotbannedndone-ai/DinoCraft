import Foundation
import DinoCraftCore

// What the shared game needs from each app (macOS: Metal + AppKit, Windows: OpenGL + SDL).

/// A drawable chunk mesh owned by the platform renderer.
protocol ChunkMeshHandle: AnyObject {
    var maxY: Int { get }
    var memoryBytes: Int { get }
}

/// Whatever a factory makes on a worker thread (a GPU buffer, or CPU vertices waiting for upload).
typealias PreparedChunkMesh = AnyObject

/// Turns finished chunk geometry into meshes the platform renderer can draw.
protocol ChunkMeshFactory: AnyObject {
    /// Worker thread: copy what's needed out of the mesher's reusable buffers.
    func prepare(buffers: MeshBuffers, maxY: Int, label: String) -> PreparedChunkMesh
    /// Main thread: finish a prepared mesh (for example, upload it to the GPU).
    func finish(_ prepared: PreparedChunkMesh) -> ChunkMeshHandle?
    /// Main thread: free a mesh that is no longer used.
    func release(_ mesh: ChunkMeshHandle)
    /// The renderer's clock, for chunk fade-in.
    var clock: Double { get }
}

/// Per-frame keyboard and mouse state for gameplay.
protocol GameInput: AnyObject {
    var mouseDelta: SIMD2<Double> { get }
    var scroll: Double { get }
    func isDown(_ binding: InputBinding) -> Bool
    func wasPressed(_ binding: InputBinding) -> Bool
    /// Hotbar slot (0–8) whose number key was pressed this frame.
    var hotbarKeyPressed: Int? { get }
    /// True while the modifier that drops a whole stack is held.
    var dropWholeStack: Bool { get }
}

/// The app services chat commands use.
protocol CommandHost: AnyObject {
    var session: GameSession? { get }
    var settings: GameSettings { get }
    var blocks: BlockRegistry { get }
    var items: ItemRegistry { get }
    var remotePlayers: [RemotePlayer] { get }
    var isMultiplayer: Bool { get }
    /// True when playing on someone else's world.
    var isClient: Bool { get }
    func addChat(from: String, text: String)
    func sendChat(_ text: String)
    /// Host only: gives items to a connected player. Returns false if they aren't connected.
    func give(playerNamed name: String, item: String, count: Int) -> Bool
}
