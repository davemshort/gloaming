import Foundation

/// Everything needed to reproduce a wallpaper exactly: palette, parameters, seed, the moment
/// in the animation, and the day arc used for time-of-day exports.
public struct Look: Codable, Hashable, Sendable {
    public var palette: Palette
    public var parameters: RenderParameters
    /// Picks a different region of the (effectively endless) animation.
    public var seed: UInt32
    /// Position in the animation in seconds at speed 1 (the editor's time scrubber).
    public var time: Double
    public var dayArc: DayArc

    public init(palette: Palette, parameters: RenderParameters = RenderParameters(), seed: UInt32 = 0,
                time: Double = 0, dayArc: DayArc = .standard) {
        self.palette = palette
        self.parameters = parameters
        self.seed = seed
        self.time = time
        self.dayArc = dayArc
    }

    /// Seconds of animation separating consecutive seeds. Large enough that different seeds
    /// look unrelated; Double keeps full precision far beyond UInt32.max × this.
    static let seedSpacing: Double = 977

    /// Animation phase for a still or the start of a sequence.
    public var phase: Double { Double(seed) * Self.seedSpacing + time }

    /// Phase for the frame shown at `dayFraction` in a time-of-day export. Speed scales how
    /// far the movement travels across the day.
    public func phase(atDayFraction f: Double) -> Double {
        phase + dayArc.motion * parameters.speed * f
    }

    /// Per-frame grain/dither seed derived from the look, so exports are reproducible.
    public var grainSeed: UInt32 { seed &* 2_654_435_761 &+ 1 }
}

extension Look {
    /// Tolerant and sanitized (shared preset files are untrusted input).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(palette: ((try? c.decodeIfPresent(Palette.self, forKey: .palette)) ?? nil) ?? .aurora,
                  parameters: ((try? c.decodeIfPresent(RenderParameters.self, forKey: .parameters)) ?? nil) ?? RenderParameters(),
                  seed: ((try? c.decodeIfPresent(UInt32.self, forKey: .seed)) ?? nil) ?? 0,
                  time: Sanitize.clamp((try? c.decodeIfPresent(Double.self, forKey: .time)) ?? 0, 0...1e7, fallback: 0),
                  dayArc: ((try? c.decodeIfPresent(DayArc.self, forKey: .dayArc)) ?? nil) ?? .standard)
    }
}
