import Foundation
import Metal
import Testing
@testable import WallpaperCore

private let hasMetal = MTLCreateSystemDefaultDevice() != nil

/// GPU tests. Skipped automatically where no Metal device exists (e.g. some CI runners).
@Suite("Renderer", .enabled(if: hasMetal))
@MainActor
struct RendererTests {
    let context: RenderContext

    init() throws {
        context = try RenderContext()
    }

    // MARK: Shader compilation and layout

    @Test func shadersCompileAndPipelinesBuild() throws {
        let library = try context.device.makeLibrary(source: WallpaperShaders.source, options: nil)
        for name in ["fullscreen_vertex", "field_fragment", "composite_fragment"] {
            #expect(library.functionNames.contains(name), "missing \(name)")
        }
        #expect(context.fieldPipeline.device === context.device)
        #expect(context.compositePipeline.device === context.device)
    }

    private func reflectedMembers(fragment: String, format: MTLPixelFormat) throws -> (size: Int, offsets: [String: Int]) {
        let library = try context.device.makeLibrary(source: WallpaperShaders.source, options: nil)
        let descriptor = try RenderContext.pipelineDescriptor(library, fragment: fragment, format: format)
        var reflection: MTLAutoreleasedRenderPipelineReflection?
        _ = try context.device.makeRenderPipelineState(descriptor: descriptor,
                                                       options: [.bindingInfo, .bufferTypeInfo],
                                                       reflection: &reflection)
        let binding = try #require(reflection?.fragmentBindings.first { $0.name == "u" } as? MTLBufferBinding)
        let members = try #require(binding.bufferStructType?.members)
        return (binding.bufferDataSize, Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0.offset) }))
    }

    @Test func fieldUniformLayoutMatchesShader() throws {
        let (size, o) = try reflectedMembers(fragment: "field_fragment", format: RenderContext.fieldPixelFormat)
        #expect(size == MemoryLayout<FieldUniforms>.stride)
        #expect(o["offsets"] == MemoryLayout<FieldUniforms>.offset(of: \.offsets0))
        #expect(o["resolution"] == MemoryLayout<FieldUniforms>.offset(of: \.resolution))
        #expect(o["aspect"] == MemoryLayout<FieldUniforms>.offset(of: \.aspect))
        #expect(o["complexity"] == MemoryLayout<FieldUniforms>.offset(of: \.complexity))
        #expect(o["warp"] == MemoryLayout<FieldUniforms>.offset(of: \.warp))
        #expect(o["transition"] == MemoryLayout<FieldUniforms>.offset(of: \.transition))
        #expect(o["blend"] == MemoryLayout<FieldUniforms>.offset(of: \.blend))
        #expect(o["scale"] == MemoryLayout<FieldUniforms>.offset(of: \.scale))
        #expect(MemoryLayout<FieldUniforms>.offset(of: \.offsets1) == 16)
        #expect(MemoryLayout<FieldUniforms>.offset(of: \.offsets2) == 32)
    }

    @Test func compositeUniformLayoutMatchesShader() throws {
        let (size, o) = try reflectedMembers(fragment: "composite_fragment", format: RenderContext.outputPixelFormat)
        #expect(size == MemoryLayout<CompositeUniforms>.stride)
        #expect(o["sourceSize"] == MemoryLayout<CompositeUniforms>.offset(of: \.sourceSize))
        #expect(o["outputSize"] == MemoryLayout<CompositeUniforms>.offset(of: \.outputSize))
        #expect(o["brightness"] == MemoryLayout<CompositeUniforms>.offset(of: \.brightness))
        #expect(o["saturation"] == MemoryLayout<CompositeUniforms>.offset(of: \.saturation))
        #expect(o["grain"] == MemoryLayout<CompositeUniforms>.offset(of: \.grain))
        #expect(o["seed"] == MemoryLayout<CompositeUniforms>.offset(of: \.seed))
    }

    // MARK: Rendered output

    private func scene(_ palette: Palette = .aurora, phase: Double, grain: Double = 0) -> SceneState {
        var p = RenderParameters()
        p.grain = grain
        return SceneState(context: context, palette: palette, parameters: p, phase: phase)
    }

    private func render(_ s: SceneState) throws -> Snapshot.Image {
        try Snapshot.render(context: context, scene: s, width: 320, height: 180, fieldScale: 0.5)
    }

    @Test func frameIsNotFlatAndUsesThePalette() throws {
        let img = try render(scene(phase: 300))
        var minL = 255, maxL = 0
        for i in stride(from: 0, to: img.bytes.count, by: 4) {
            let l = Int(img.bytes[i + 1])          // green channel as a brightness proxy
            minL = min(minL, l); maxL = max(maxL, l)
        }
        #expect(maxL - minL > 20, "gradient should vary across the frame")
    }

    @Test func animationMoves() throws {
        let a = try render(scene(phase: 300))
        let b = try render(scene(phase: 330))
        #expect(Snapshot.meanAbsoluteDifference(a, b) > 0.5)
    }

    /// The seam test for "no jumps": stepping across the moment an offset component wraps
    /// must change the image no more than an ordinary step of the same length.
    @Test(arguments: [0, 3, 6, 11])
    func offsetWrapIsSeamless(component: Int) throws {
        let dt = 0.5
        let wrap = AnimationClock.nextWrapPhase(component: component, after: 1000)
        let acrossWrap = Snapshot.meanAbsoluteDifference(
            try render(scene(phase: wrap - dt / 2)), try render(scene(phase: wrap + dt / 2)))
        let ordinary = Snapshot.meanAbsoluteDifference(
            try render(scene(phase: wrap - 50 - dt / 2)), try render(scene(phase: wrap - 50 + dt / 2)))
        print("wrap seam component \(component): across-wrap \(acrossWrap), ordinary \(ordinary)")
        #expect(acrossWrap < ordinary * 2 + 0.5,
                "component \(component): across-wrap diff \(acrossWrap) vs ordinary \(ordinary)")
    }

    @Test func paletteCrossfadeIsGradual() throws {
        let s = scene(phase: 300)
        let start = try render(s)
        s.setPalette(.ember)
        s.advance(to: 0)
        var previous = start
        var steps: [Double] = []
        for i in 1...12 {                       // 12 × 0.25 s = full 3 s transition
            s.advance(to: Double(i) * 0.25)
            let frame = try render(s)
            steps.append(Snapshot.meanAbsoluteDifference(previous, frame))
            previous = frame
        }
        let total = Snapshot.meanAbsoluteDifference(start, previous)
        #expect(total > 10, "ember should look clearly different from aurora")
        #expect(steps.max()! < total * 0.35, "no single quarter-second step should do most of the change")
        #expect(!s.transition.isActive)
    }

    @Test func parameterChangesAreSmoothed() {
        let s = scene(phase: 0)
        var p = s.targetParameters
        p.brightness = 0.5
        s.setParameters(p)
        s.advance(to: 0)
        s.advance(to: 0.1)
        #expect(s.parameters.brightness < 1 && s.parameters.brightness > 0.5)
        for i in 2...40 { s.advance(to: Double(i) * 0.1) }
        #expect(abs(s.parameters.brightness - 0.5) < 0.01)
    }
}
