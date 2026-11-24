import Metal

/// Encodes one frame: field passes into `field` (reduced resolution), then the composite
/// pass into `output`. Shared by the on-screen views and offscreen snapshots.
@MainActor
enum FrameEncoder {
    static func encode(_ commandBuffer: MTLCommandBuffer, context: RenderContext, scene: SceneState,
                       field: MTLTexture, output: MTLTexture, seed: UInt32) {
        let fieldSize = SIMD2<Float>(Float(field.width), Float(field.height))
        let outputSize = SIMD2<Float>(Float(output.width), Float(output.height))

        let fieldPass = MTLRenderPassDescriptor()
        fieldPass.colorAttachments[0].texture = field
        fieldPass.colorAttachments[0].loadAction = .dontCare
        fieldPass.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: fieldPass) {
            enc.label = "Field"
            for pass in scene.passes {
                pass.encode(enc, scene: scene, targetSize: fieldSize)
            }
            enc.endEncoding()
        }

        let compositePass = MTLRenderPassDescriptor()
        compositePass.colorAttachments[0].texture = output
        compositePass.colorAttachments[0].loadAction = .dontCare
        compositePass.colorAttachments[0].storeAction = .store
        if let enc = commandBuffer.makeRenderCommandEncoder(descriptor: compositePass) {
            enc.label = "Composite"
            var u = scene.compositeUniforms(sourceSize: fieldSize, outputSize: outputSize, seed: seed)
            enc.setRenderPipelineState(context.compositePipeline)
            enc.setFragmentBytes(&u, length: MemoryLayout<CompositeUniforms>.stride, index: 0)
            enc.setFragmentTexture(field, index: 0)
            enc.setFragmentSamplerState(context.linearClamp, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
    }
}
