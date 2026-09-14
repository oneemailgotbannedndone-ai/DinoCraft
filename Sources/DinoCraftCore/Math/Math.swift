import Foundation
#if canImport(simd) && !DINOCRAFT_PORTABLE_SIMD
import simd
#endif

public typealias Vec2 = SIMD2<Float>
public typealias Vec3 = SIMD3<Float>
public typealias Vec4 = SIMD4<Float>
public typealias Mat4 = simd_float4x4

// MARK: - Integer positions

public struct BlockPos: Hashable, Sendable, CustomStringConvertible {
    public var x: Int32, y: Int32, z: Int32
    @inlinable public init(_ x: Int32, _ y: Int32, _ z: Int32) { self.x = x; self.y = y; self.z = z }
    @inlinable public init(_ x: Int, _ y: Int, _ z: Int) { self.x = Int32(x); self.y = Int32(y); self.z = Int32(z) }
    @inlinable public init(floor v: Vec3) {
        x = Int32(v.x.rounded(.down)); y = Int32(v.y.rounded(.down)); z = Int32(v.z.rounded(.down))
    }
    @inlinable public func offset(_ d: BlockFace) -> BlockPos {
        let n = d.normal
        return BlockPos(x + n.x, y + n.y, z + n.z)
    }
    @inlinable public var chunk: ChunkPos { ChunkPos(x >> ChunkPos.shift, z >> ChunkPos.shift) }
    @inlinable public var center: Vec3 { Vec3(Float(x) + 0.5, Float(y) + 0.5, Float(z) + 0.5) }
    public var description: String { "(\(x), \(y), \(z))" }
}

/// Column coordinates of a chunk (chunks span the whole world height).
public struct ChunkPos: Hashable, Sendable, CustomStringConvertible {
    public static let shift: Int32 = 4          // 16 blocks per chunk side
    public var x: Int32, z: Int32
    @inlinable public init(_ x: Int32, _ z: Int32) { self.x = x; self.z = z }
    @inlinable public var originX: Int32 { x << ChunkPos.shift }
    @inlinable public var originZ: Int32 { z << ChunkPos.shift }
    public var description: String { "[\(x), \(z)]" }

    /// Squared distance in chunk units (used for load ordering).
    @inlinable public func distanceSquared(to o: ChunkPos) -> Int32 {
        let dx = x - o.x, dz = z - o.z
        return dx * dx + dz * dz
    }
}

public enum BlockFace: Int, CaseIterable, Sendable {
    case east = 0   // +X
    case west       // -X
    case up         // +Y
    case down       // -Y
    case south      // +Z
    case north      // -Z

    @inlinable public var normal: SIMD3<Int32> {
        switch self {
        case .east: return SIMD3(1, 0, 0)
        case .west: return SIMD3(-1, 0, 0)
        case .up: return SIMD3(0, 1, 0)
        case .down: return SIMD3(0, -1, 0)
        case .south: return SIMD3(0, 0, 1)
        case .north: return SIMD3(0, 0, -1)
        }
    }
    @inlinable public var opposite: BlockFace {
        switch self {
        case .east: return .west
        case .west: return .east
        case .up: return .down
        case .down: return .up
        case .south: return .north
        case .north: return .south
        }
    }
}

// MARK: - Bounding boxes

public struct AABB: Sendable {
    public var min: Vec3
    public var max: Vec3
    @inlinable public init(min: Vec3, max: Vec3) { self.min = min; self.max = max }

    @inlinable public func intersects(_ o: AABB) -> Bool {
        min.x < o.max.x && max.x > o.min.x &&
        min.y < o.max.y && max.y > o.min.y &&
        min.z < o.max.z && max.z > o.min.z
    }
    @inlinable public func offset(_ d: Vec3) -> AABB { AABB(min: min + d, max: max + d) }
    @inlinable public func expanded(by d: Vec3) -> AABB {
        AABB(min: simd_min(min, min + d), max: simd_max(max, max + d))
    }
}

// MARK: - Matrices

public enum MathUtil {
    /// Right-handed perspective projection with **reverse-Z** (near → 1, far → 0)
    /// for far better depth precision across long view distances.
    public static func perspectiveReverseZ(fovyRadians fovy: Float, aspect: Float, near: Float, far: Float) -> Mat4 {
        let ys = 1 / tan(fovy * 0.5)
        let xs = ys / aspect
        let zz = near / (far - near)
        let zw = far * near / (far - near)
        return Mat4(columns: (
            Vec4(xs, 0, 0, 0),
            Vec4(0, ys, 0, 0),
            Vec4(0, 0, zz, -1),
            Vec4(0, 0, zw, 0)))
    }

    /// Orthographic projection mapping pixels (origin top-left) to clip space.
    public static func orthoPixels(width: Float, height: Float) -> Mat4 {
        Mat4(columns: (
            Vec4(2 / width, 0, 0, 0),
            Vec4(0, -2 / height, 0, 0),
            Vec4(0, 0, 1, 0),
            Vec4(-1, 1, 0, 1)))
    }

    public static func translation(_ t: Vec3) -> Mat4 {
        var m = matrix_identity_float4x4
        m.columns.3 = Vec4(t.x, t.y, t.z, 1)
        return m
    }

    public static func rotationX(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (Vec4(1, 0, 0, 0), Vec4(0, c, s, 0), Vec4(0, -s, c, 0), Vec4(0, 0, 0, 1)))
    }

    public static func rotationY(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (Vec4(c, 0, -s, 0), Vec4(0, 1, 0, 0), Vec4(s, 0, c, 0), Vec4(0, 0, 0, 1)))
    }

    public static func rotationZ(_ a: Float) -> Mat4 {
        let c = cos(a), s = sin(a)
        return Mat4(columns: (Vec4(c, s, 0, 0), Vec4(-s, c, 0, 0), Vec4(0, 0, 1, 0), Vec4(0, 0, 0, 1)))
    }

    public static func scale(_ s: Vec3) -> Mat4 {
        Mat4(diagonal: Vec4(s.x, s.y, s.z, 1))
    }

    /// View matrix for a first-person camera. Yaw 0 looks toward -Z; positive
    /// pitch looks up.
    public static func fpsView(eye: Vec3, yaw: Float, pitch: Float) -> Mat4 {
        rotationX(-pitch) * rotationY(-yaw) * translation(-eye)
    }

    @inlinable public static func forward(yaw: Float, pitch: Float) -> Vec3 {
        Vec3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
    }

    @inlinable public static func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { Swift.min(Swift.max(v, lo), hi) }
    @inlinable public static func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
    @inlinable public static func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
        let t = clamp((x - e0) / (e1 - e0), 0, 1)
        return t * t * (3 - 2 * t)
    }
    /// Frame-rate independent exponential approach.
    @inlinable public static func damp(_ current: Float, _ target: Float, rate: Float, dt: Float) -> Float {
        lerp(current, target, 1 - exp(-rate * dt))
    }
}

// MARK: - Frustum

/// View frustum extracted from a view-projection matrix (Gribb/Hartmann),
/// valid for Metal's [0, w] clip depth range including reverse-Z.
public struct Frustum: Sendable {
    public var planes: [Vec4] = []

    public init(viewProjection m: Mat4) {
        func row(_ i: Int) -> Vec4 { Vec4(m.columns.0[i], m.columns.1[i], m.columns.2[i], m.columns.3[i]) }
        let r0 = row(0), r1 = row(1), r2 = row(2), r3 = row(3)
        let raw = [r3 + r0, r3 - r0, r3 + r1, r3 - r1, r2, r3 - r2]
        planes = raw.map { p in
            let len = simd_length(Vec3(p.x, p.y, p.z))
            return len > 0 ? p / len : p
        }
    }

    /// Conservative AABB test: false only if the box is fully outside a plane.
    @inlinable public func contains(_ box: AABB) -> Bool {
        for p in planes {
            let v = Vec3(p.x >= 0 ? box.max.x : box.min.x,
                         p.y >= 0 ? box.max.y : box.min.y,
                         p.z >= 0 ? box.max.z : box.min.z)
            if p.x * v.x + p.y * v.y + p.z * v.z + p.w < 0 { return false }
        }
        return true
    }
}
