import Foundation

/// Crossfade between two palette ramps, in OKLab.
///
/// Starting a new transition while one is running takes the *currently displayed* blend as
/// the new starting point, so interrupting a crossfade never jumps.
public struct PaletteTransition: Sendable {
    public static let rampSize = 256

    public private(set) var from: [OKLab]
    public private(set) var to: [OKLab]
    /// Linear progress 0...1.
    public private(set) var progress: Double = 1
    public var duration: Double

    public init(palette: Palette, duration: Double = 3) {
        self.init(ramp: palette.ramp(count: Self.rampSize), duration: duration)
    }

    /// Starts settled on an explicit ramp (e.g. a day-arc blend of two palettes).
    public init(ramp: [OKLab], duration: Double = 3) {
        from = ramp
        to = ramp
        self.duration = duration
    }

    public var isActive: Bool { progress < 1 }

    /// Smoothstep-eased progress; this is what the shader uses to mix the two ramps.
    public var easedProgress: Double { progress * progress * (3 - 2 * progress) }

    public func currentRamp() -> [OKLab] {
        let t = easedProgress
        if t >= 1 { return to }
        if t <= 0 { return from }
        return zip(from, to).map { OKLab.mix($0, $1, t) }
    }

    public mutating func begin(to palette: Palette) {
        from = currentRamp()
        to = palette.ramp(count: Self.rampSize)
        progress = duration > 0 ? 0 : 1
    }

    public mutating func advance(by dt: Double) {
        guard isActive else { return }
        progress = duration > 0 ? min(1, progress + max(dt, 0) / duration) : 1
    }
}
