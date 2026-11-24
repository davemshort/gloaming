import Foundation
import simd

/// Animation time, designed to run for weeks without jumps, precision loss or visible loops.
///
/// - `phase` integrates `dt × speed` in Double, so speed changes never cause a jump.
/// - The shader never sees `phase`. It sees six 2-D drift offsets, each `phase × velocity`
///   wrapped into `[0, period)`. Every noise lookup in the shader is exactly periodic in
///   `period` (lattice coordinates are masked before hashing; octave frequencies are
///   integer powers of two; only integer constant offsets are added), so wrapping an offset
///   is invisible. Values stay small, so Float precision stays good indefinitely.
/// - Each offset component wraps at a different time (incommensurate velocities), so the
///   combined motion has no practical repeat period.
public struct AnimationClock: Sendable {
    /// Noise lattice period. Must be a power of two; the shader masks with `period - 1`.
    public static let period: Int = 256

    /// Drift velocities in noise units per second at speed 1.
    public static let velocities: [SIMD2<Double>] = [
        SIMD2(0.021, 0.013), SIMD2(-0.017, 0.019), SIMD2(0.011, -0.023),
        SIMD2(-0.019, -0.009), SIMD2(0.007, 0.015), SIMD2(-0.005, 0.004),
    ]

    /// Longest step accepted from one frame to the next, so resuming after a pause, sleep or
    /// a hitch continues smoothly instead of leaping forward.
    public static let maxStep: Double = 0.25

    public private(set) var phase: Double
    public private(set) var lastTimestamp: Double?

    public init(phase: Double = 0) {
        self.phase = phase
    }

    /// Advances to `timestamp` (seconds, monotonic). Timestamps at or before the last one are
    /// ignored, so several displays can drive one shared clock. Returns the dt applied.
    @discardableResult
    public mutating func advance(to timestamp: Double, speed: Double) -> Double {
        guard let last = lastTimestamp else {
            lastTimestamp = timestamp
            return 0
        }
        guard timestamp > last else { return 0 }
        lastTimestamp = timestamp
        let dt = min(timestamp - last, Self.maxStep)
        phase += dt * max(speed, 0)
        return dt
    }

    public mutating func setPhase(_ value: Double) {
        phase = value
    }

    /// Wraps into `[0, period)`.
    public static func wrap(_ x: Double) -> Double {
        let p = Double(period)
        let r = x.truncatingRemainder(dividingBy: p)
        return r < 0 ? r + p : r
    }

    /// The six wrapped drift offsets packed as three float4s (xy, zw), matching the shader.
    public var packedOffsets: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        func o(_ i: Int) -> SIMD2<Float> {
            let v = Self.velocities[i]
            return SIMD2(Float(Self.wrap(phase * v.x)), Float(Self.wrap(phase * v.y)))
        }
        func pack(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD4<Float> { SIMD4(a.x, a.y, b.x, b.y) }
        return (pack(o(0), o(1)), pack(o(2), o(3)), pack(o(4), o(5)))
    }

    /// Phase at which offset component `index` (0..<12, x/y interleaved) next reaches a wrap
    /// boundary at or after `phase`. Used by tests and the `--start-phase` debugging aid.
    public static func nextWrapPhase(component index: Int, after phase: Double) -> Double {
        let v = velocities[index / 2]
        let speed = abs(index % 2 == 0 ? v.x : v.y)
        let interval = Double(period) / speed
        return (floor(phase / interval) + 1) * interval
    }
}
