import Foundation
import Metal

/// Everything that defines what the wallpaper looks like at a moment in time: palette (with
/// crossfade), parameters (smoothed toward their targets), the animation clock, and the
/// ordered field passes.
///
/// One instance can drive several displays: `advance(to:)` ignores timestamps that are not
/// newer than the last one, so each display's link can call it and time moves once.
@MainActor
public final class SceneState {
    /// Seconds for a parameter change to cover ~63 % of the way to its new value.
    public static let parameterTimeConstant: Double = 0.6

    public private(set) var palette: Palette
    public private(set) var targetParameters: RenderParameters
    public private(set) var parameters: RenderParameters
    public private(set) var clock: AnimationClock
    public private(set) var transition: PaletteTransition
    public private(set) var rampFrom: MTLTexture?
    public private(set) var rampTo: MTLTexture?
    public var passes: [FieldPass] = []

    private let context: RenderContext

    public convenience init(context: RenderContext, palette: Palette, parameters: RenderParameters, phase: Double = 0) {
        self.init(context: context, palette: palette, ramp: palette.ramp(count: PaletteTransition.rampSize),
                  parameters: parameters, phase: phase)
    }

    /// Settled scene on an explicit OKLab ramp, with no transition running and parameters
    /// applied immediately. This is what exports use (deterministic: never call `advance`).
    public init(context: RenderContext, palette: Palette, ramp: [OKLab], parameters: RenderParameters, phase: Double) {
        self.context = context
        self.palette = palette
        let p = parameters.clamped()
        targetParameters = p
        self.parameters = p
        clock = AnimationClock(phase: phase)
        transition = PaletteTransition(ramp: ramp)
        passes = [GradientFieldPass(context: context)]
        uploadRamps()
    }

    /// Starts a crossfade to `palette` (or switches instantly if `animated` is false).
    public func setPalette(_ palette: Palette, animated: Bool = true) {
        setPalette(palette, duration: animated ? 3 : 0)
    }

    /// Crossfades to `palette` over `duration` seconds (0 = instant).
    public func setPalette(_ palette: Palette, duration: Double) {
        self.palette = palette
        let saved = transition.duration
        transition.duration = duration
        transition.begin(to: palette)
        transition.duration = saved
        uploadRamps()
    }

    public func setParameters(_ parameters: RenderParameters, animated: Bool = true) {
        targetParameters = parameters.clamped()
        if !animated { self.parameters = targetParameters }
    }

    public func setPhase(_ phase: Double) {
        clock.setPhase(phase)
    }

    /// Advances animation to `timestamp` (CACurrentMediaTime-based). Returns the dt applied.
    @discardableResult
    public func advance(to timestamp: Double) -> Double {
        let dt = clock.advance(to: timestamp, speed: parameters.speed)
        guard dt > 0 else { return 0 }
        if parameters != targetParameters {
            parameters = parameters.approaching(
                targetParameters, factor: Smoothing.factor(dt: dt, timeConstant: Self.parameterTimeConstant))
        }
        if transition.isActive {
            transition.advance(by: dt)
            if !transition.isActive { uploadRamps() }   // collapse to a single ramp
        }
        return dt
    }

    func fieldUniforms(targetSize: SIMD2<Float>) -> FieldUniforms {
        let (o0, o1, o2) = clock.packedOffsets
        let c = Float(parameters.complexity)
        return FieldUniforms(
            offsets0: o0, offsets1: o1, offsets2: o2,
            resolution: targetSize,
            aspect: targetSize.x / max(targetSize.y, 1),
            complexity: c,
            warp: 0.6 + 1.2 * c,
            transition: Float(transition.easedProgress),
            blend: Float(parameters.blend),
            scale: 0.45 + 0.6 * c)
    }

    func compositeUniforms(sourceSize: SIMD2<Float>, outputSize: SIMD2<Float>, seed: UInt32) -> CompositeUniforms {
        CompositeUniforms(sourceSize: sourceSize, outputSize: outputSize,
                          brightness: Float(parameters.brightness),
                          saturation: Float(parameters.saturation),
                          grain: Float(parameters.grain),
                          seed: seed)
    }

    private func uploadRamps() {
        if transition.isActive {
            rampFrom = context.makeRampTexture(transition.from)
            rampTo = context.makeRampTexture(transition.to)
        } else {
            let t = context.makeRampTexture(transition.to)
            rampFrom = t
            rampTo = t
        }
    }
}
