import Metal

/// One step of the reduced-resolution field pass. Passes run in order into the same
/// render encoder; the first one must cover every pixel (the target is not cleared).
///
/// This is the extension point for later effects (e.g. weather layers in Phase 5): a new
/// pass draws on top of the gradient with its own pipeline and blending, without changes
/// to the frame loop.
@MainActor
public protocol FieldPass: AnyObject {
    func encode(_ encoder: MTLRenderCommandEncoder, scene: SceneState, targetSize: SIMD2<Float>)
}

/// The base layer: the domain-warped palette gradient.
@MainActor
public final class GradientFieldPass: FieldPass {
    private let context: RenderContext

    public init(context: RenderContext) {
        self.context = context
    }

    public func encode(_ encoder: MTLRenderCommandEncoder, scene: SceneState, targetSize: SIMD2<Float>) {
        var u = scene.fieldUniforms(targetSize: targetSize)
        encoder.setRenderPipelineState(context.fieldPipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<FieldUniforms>.stride, index: 0)
        encoder.setFragmentTexture(scene.rampFrom, index: 0)
        encoder.setFragmentTexture(scene.rampTo, index: 1)
        encoder.setFragmentSamplerState(context.linearClamp, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
