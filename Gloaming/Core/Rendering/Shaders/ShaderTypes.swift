import simd

/// Swift mirrors of the uniform structs in `WallpaperShaders.source`. Layouts must match
/// Metal's alignment rules exactly; `ShaderTests` checks every member offset against the
/// compiled pipeline's reflection data.

/// Matches `struct FieldUniforms` (80 bytes).
public struct FieldUniforms {
    public var offsets0: SIMD4<Float>     // float4 offsets[3]
    public var offsets1: SIMD4<Float>
    public var offsets2: SIMD4<Float>
    public var resolution: SIMD2<Float>
    public var aspect: Float
    public var complexity: Float
    public var warp: Float
    public var transition: Float
    public var blend: Float
    public var scale: Float
}

/// Matches `struct CompositeUniforms` (32 bytes).
public struct CompositeUniforms {
    public var sourceSize: SIMD2<Float>
    public var outputSize: SIMD2<Float>
    public var brightness: Float
    public var saturation: Float
    public var grain: Float
    public var seed: UInt32
}
