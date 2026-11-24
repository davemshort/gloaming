import Foundation

/// User-adjustable look of the wallpaper. Values outside their ranges are clamped.
public struct RenderParameters: Codable, Hashable, Sendable {
    /// Animation speed multiplier (0 = frozen, 1 = default calm drift).
    public var speed: Double = 1.0
    /// Gradient complexity: number of noise octaves, spatial scale and warp strength.
    public var complexity: Double = 0.5
    /// Colour blending intensity: higher = softer, more diffuse transitions between colours.
    public var blend: Double = 0.6
    /// Film grain amount (0 = off).
    public var grain: Double = 0.25
    /// Linear brightness multiplier.
    public var brightness: Double = 1.0
    /// Saturation multiplier (0 = greyscale, 1 = as designed).
    public var saturation: Double = 1.0

    // Immutable after initialisation; key paths just aren't marked Sendable.
    nonisolated(unsafe) public static let ranges: [WritableKeyPath<RenderParameters, Double>: ClosedRange<Double>] = [
        \.speed: 0...4, \.complexity: 0...1, \.blend: 0...1,
        \.grain: 0...1, \.brightness: 0.2...1.5, \.saturation: 0...2,
    ]

    public init() {}

    public func clamped() -> RenderParameters {
        var p = self
        for (key, range) in Self.ranges {
            p[keyPath: key] = min(max(p[keyPath: key], range.lowerBound), range.upperBound)
        }
        return p
    }

    /// Moves each value toward `target` by `factor` (0...1).
    public func approaching(_ target: RenderParameters, factor: Double) -> RenderParameters {
        var p = self
        for key in Self.ranges.keys {
            p[keyPath: key] += (target[keyPath: key] - p[keyPath: key]) * factor
        }
        return p
    }
}

public enum Smoothing {
    /// Frame-rate-independent exponential smoothing factor: after `timeConstant` seconds a
    /// value has covered ~63 % of the distance to its target, whatever the frame rate.
    public static func factor(dt: Double, timeConstant: Double) -> Double {
        guard timeConstant > 0 else { return 1 }
        return 1 - exp(-max(dt, 0) / timeConstant)
    }
}

extension RenderParameters {
    /// Tolerant: any missing or non-finite value takes its default; all values are clamped.
    public init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = RenderParameters()
        func v(_ k: CodingKeys, _ key: WritableKeyPath<RenderParameters, Double>) {
            let x = (try? c.decodeIfPresent(Double.self, forKey: k)) ?? nil
            self[keyPath: key] = Sanitize.finite(x ?? defaults[keyPath: key], defaults[keyPath: key])
        }
        v(.speed, \.speed); v(.complexity, \.complexity); v(.blend, \.blend)
        v(.grain, \.grain); v(.brightness, \.brightness); v(.saturation, \.saturation)
        self = clamped()
    }
}
