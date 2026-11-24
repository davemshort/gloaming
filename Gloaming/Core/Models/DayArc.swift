import Foundation

/// How a look changes across a day in a time-of-day wallpaper: brightness, saturation and
/// optionally palette at keyframe times, plus how far the gradient's movement travels from
/// midnight to midnight.
public struct DayArc: Codable, Hashable, Sendable {
    public struct Keyframe: Codable, Hashable, Sendable {
        /// Local clock time as a fraction of the day (0 = midnight, 0.5 = noon).
        public var dayFraction: Double
        public var brightness: Double
        public var saturation: Double
        /// Palette at this time; nil uses the look's own palette.
        public var palette: Palette?

        public init(dayFraction: Double, brightness: Double = 1, saturation: Double = 1, palette: Palette? = nil) {
            self.dayFraction = dayFraction
            self.brightness = brightness
            self.saturation = saturation
            self.palette = palette
        }
    }

    public var keyframes: [Keyframe]
    /// Animation seconds (at speed 1) travelled from 00:00 to 24:00. Consecutive frames of a
    /// 12-frame export are `motion / 12` seconds apart in the animation.
    public var motion: Double

    public init(keyframes: [Keyframe], motion: Double) {
        self.keyframes = keyframes
        self.motion = motion
    }

    /// Dim at night, full at midday, a little richer into the evening. Brightness is a
    /// linear-light multiplier (0.3 linear reads about 0.55 in sRGB). Motion of 240 s gives
    /// 20 s of drift between the frames of a 12-frame export, so consecutive frames are
    /// clearly related (tuned from contact sheets; 600 s made neighbours look unrelated).
    public static let standard = DayArc(keyframes: [
        Keyframe(dayFraction: 0.0, brightness: 0.3, saturation: 0.8),
        Keyframe(dayFraction: 0.27, brightness: 0.7, saturation: 0.95),
        Keyframe(dayFraction: 0.5, brightness: 1.0, saturation: 1.0),
        Keyframe(dayFraction: 0.77, brightness: 0.65, saturation: 1.1),
    ], motion: 240)

    public struct Sample: Sendable {
        public var brightness: Double
        public var saturation: Double
        public var ramp: [OKLab]
    }

    /// Interpolates the keyframes (smoothstep, wrapping at midnight) at `dayFraction`.
    public func sample(at dayFraction: Double, base: Palette, rampSize: Int = PaletteTransition.rampSize) -> Sample {
        let f = dayFraction - floor(dayFraction)
        let keys = keyframes.sorted { $0.dayFraction < $1.dayFraction }
        guard let first = keys.first else {
            return Sample(brightness: 1, saturation: 1, ramp: base.ramp(count: rampSize))
        }
        guard keys.count > 1 else {
            return Sample(brightness: first.brightness, saturation: first.saturation,
                          ramp: (first.palette ?? base).ramp(count: rampSize))
        }
        // Previous keyframe at or before f (wrapping), and the next one after it.
        let prevIndex = keys.lastIndex { $0.dayFraction <= f } ?? keys.count - 1
        let nextIndex = (prevIndex + 1) % keys.count
        let a = keys[prevIndex], b = keys[nextIndex]
        var span = b.dayFraction - a.dayFraction
        if span <= 0 { span += 1 }
        var offset = f - a.dayFraction
        if offset < 0 { offset += 1 }
        let x = min(max(offset / span, 0), 1)
        let t = x * x * (3 - 2 * x)

        let rampA = (a.palette ?? base).ramp(count: rampSize)
        let ramp = (a.palette == b.palette) ? rampA
            : zip(rampA, (b.palette ?? base).ramp(count: rampSize)).map { OKLab.mix($0, $1, t) }
        return Sample(brightness: a.brightness + (b.brightness - a.brightness) * t,
                      saturation: a.saturation + (b.saturation - a.saturation) * t,
                      ramp: ramp)
    }
}

extension DayArc.Keyframe {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let f = Sanitize.finite((try? c.decodeIfPresent(Double.self, forKey: .dayFraction)) ?? 0, 0)
        self.init(dayFraction: f - floor(f),
                  brightness: Sanitize.clamp((try? c.decodeIfPresent(Double.self, forKey: .brightness)) ?? 1, 0...2, fallback: 1),
                  saturation: Sanitize.clamp((try? c.decodeIfPresent(Double.self, forKey: .saturation)) ?? 1, 0...2, fallback: 1),
                  palette: (try? c.decodeIfPresent(Palette.self, forKey: .palette)) ?? nil)
    }
}

extension DayArc {
    public static let maxKeyframes = 24
    public static let motionRange: ClosedRange<Double> = 0...3600

    /// Tolerant and bounded: missing → standard arc values, at most 24 keyframes, motion clamped.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let keys = ((try? c.decodeIfPresent([Keyframe].self, forKey: .keyframes)) ?? nil) ?? DayArc.standard.keyframes
        let motion = Sanitize.clamp((try? c.decodeIfPresent(Double.self, forKey: .motion)) ?? DayArc.standard.motion,
                                    DayArc.motionRange, fallback: DayArc.standard.motion)
        self.init(keyframes: Array(keys.prefix(DayArc.maxKeyframes)), motion: motion)
    }

    /// The same arc with every keyframe palette removed (brightness/saturation curve kept),
    /// so the whole day uses the look's own palette.
    public var withoutPaletteOverrides: DayArc {
        DayArc(keyframes: keyframes.map { var k = $0; k.palette = nil; return k }, motion: motion)
    }

    public var hasPaletteOverrides: Bool { keyframes.contains { $0.palette != nil } }
}
