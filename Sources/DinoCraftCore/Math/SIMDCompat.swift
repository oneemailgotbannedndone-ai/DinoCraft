// Portable stand-ins for the parts of Apple's simd library that DinoCraftCore uses,
// so the core builds on Windows and Linux. On Apple platforms the real simd is used,
// unless the build defines DINOCRAFT_PORTABLE_SIMD (to test these on a Mac).
#if !canImport(simd) || DINOCRAFT_PORTABLE_SIMD

public func simd_min<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMin(a, b) }
public func simd_max<V: SIMD>(_ a: V, _ b: V) -> V where V.Scalar: Comparable { pointwiseMax(a, b) }
public func simd_clamp<V: SIMD>(_ v: V, _ lo: V, _ hi: V) -> V where V.Scalar: Comparable { pointwiseMin(pointwiseMax(v, lo), hi) }
public func simd_dot<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { (a * b).sum() }
public func simd_length_squared<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint { (v * v).sum() }
public func simd_length<V: SIMD>(_ v: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length_squared(v).squareRoot() }
public func simd_distance<V: SIMD>(_ a: V, _ b: V) -> V.Scalar where V.Scalar: FloatingPoint { simd_length(a - b) }
public func simd_normalize<V: SIMD>(_ v: V) -> V where V.Scalar: FloatingPoint { v / simd_length(v) }
public func simd_mix<V: SIMD>(_ a: V, _ b: V, _ t: V) -> V where V.Scalar: FloatingPoint { a + (b - a) * t }
public func simd_cross<S: SIMDScalar & FloatingPoint>(_ a: SIMD3<S>, _ b: SIMD3<S>) -> SIMD3<S> {
    SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

/// Column-major 4×4 matrix matching simd's layout.
public struct simd_float4x4: Equatable, Sendable {
    public var columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)

    public init(columns: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)) {
        self.columns = columns
    }

    public init(diagonal d: SIMD4<Float>) {
        columns = (SIMD4(d.x, 0, 0, 0), SIMD4(0, d.y, 0, 0), SIMD4(0, 0, d.z, 0), SIMD4(0, 0, 0, d.w))
    }

    public static func == (a: simd_float4x4, b: simd_float4x4) -> Bool {
        a.columns.0 == b.columns.0 && a.columns.1 == b.columns.1 && a.columns.2 == b.columns.2 && a.columns.3 == b.columns.3
    }

    public static func * (m: simd_float4x4, v: SIMD4<Float>) -> SIMD4<Float> {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z + m.columns.3 * v.w
    }

    public static func * (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(columns: (a * b.columns.0, a * b.columns.1, a * b.columns.2, a * b.columns.3))
    }
}

public let matrix_identity_float4x4 = simd_float4x4(diagonal: SIMD4(repeating: 1))

#endif
