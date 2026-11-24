import AppKit
import Metal
import QuartzCore

/// Shared Metal state: one device, one command queue, one pipeline for all displays.
@MainActor
final class RenderContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let startTime = CACurrentMediaTime()

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else {
            throw NSError(domain: "DesktopPrototype", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Metal is not available"])
        }
        let library = try device.makeLibrary(source: Shaders.source, options: nil)
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "fullscreen_vertex")
        desc.fragmentFunction = library.makeFunction(name: "gradient_fragment")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }
}

/// Matches `struct Uniforms` in Shaders.swift (64 bytes, Metal alignment rules).
private struct Uniforms {
    var time: Float
    var resolution: SIMD2<Float>
    var colorA: SIMD3<Float>
    var colorB: SIMD3<Float>
    var colorC: SIMD3<Float>
}

/// Frame statistics. Written from the main thread (CPU side) and from Metal's
/// completion handler thread (GPU side), so access is lock-protected.
final class FrameStats: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var gpuSeconds: Double = 0
    private var gpuSamples = 0
    private var cpuEncodeSeconds: Double = 0

    func recordFrame(cpuEncode: Double) {
        lock.lock(); frames += 1; cpuEncodeSeconds += cpuEncode; lock.unlock()
    }
    func recordGPU(_ seconds: Double) {
        guard seconds > 0 else { return }
        lock.lock(); gpuSeconds += seconds; gpuSamples += 1; lock.unlock()
    }
    /// Returns (frames, mean GPU ms, mean CPU encode ms) and resets.
    func drain() -> (frames: Int, gpuMs: Double, cpuMs: Double) {
        lock.lock(); defer { frames = 0; gpuSeconds = 0; gpuSamples = 0; cpuEncodeSeconds = 0; lock.unlock() }
        let gpu = gpuSamples > 0 ? gpuSeconds / Double(gpuSamples) * 1000 : 0
        let cpu = frames > 0 ? cpuEncodeSeconds / Double(frames) * 1000 : 0
        return (frames, gpu, cpu)
    }
}

/// Layer-backed view that renders the gradient into a CAMetalLayer, driven by the
/// macOS 14 `NSView.displayLink(target:selector:)` (which follows the view's screen).
@MainActor
final class MetalView: NSView {
    private let context: RenderContext
    private var displayLink: CADisplayLink?
    let stats = FrameStats()

    var renderScale: Double { didSet { updateDrawableSize() } }
    var preferredFPS: Int { didSet { applyFrameRate() } }
    var isPaused: Bool = false { didSet { displayLink?.isPaused = isPaused } }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    init(context: RenderContext, renderScale: Double, fps: Int) {
        self.context = context
        self.renderScale = renderScale
        self.preferredFPS = fps
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = context.device
        l.pixelFormat = .bgra8Unorm
        l.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        l.framebufferOnly = true
        l.isOpaque = true
        // Rendering below native resolution; the compositor upscales.
        l.contentsGravity = .resize
        l.magnificationFilter = .linear
        return l
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = isPaused
        displayLink = link
        applyFrameRate()
        updateDrawableSize()
    }

    override func layout() { super.layout(); updateDrawableSize() }
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        metalLayer.contentsScale = window?.backingScaleFactor ?? 2
        updateDrawableSize()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    var drawableSize: CGSize { metalLayer.drawableSize }

    private func applyFrameRate() {
        let f = Float(preferredFPS)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    private func updateDrawableSize() {
        let scale = (window?.backingScaleFactor ?? 2) * renderScale
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()),
                          height: max(1, (bounds.height * scale).rounded()))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    @objc private func step(_ link: CADisplayLink) {
        let cpuStart = CACurrentMediaTime()
        guard let drawable = metalLayer.nextDrawable(),
              let cb = context.queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        // Time is kept as Double on the CPU and wrapped before narrowing to Float so the
        // shader never sees large values. (The wrap point is a visible discontinuity in
        // this prototype; Phase 2 must make the motion continuous across it.)
        let t = (link.targetTimestamp - context.startTime).truncatingRemainder(dividingBy: 4096)
        var u = Uniforms(
            time: Float(t),
            resolution: SIMD2(Float(drawable.texture.width), Float(drawable.texture.height)),
            colorA: SIMD3(0.04, 0.06, 0.20),   // deep blue
            colorB: SIMD3(0.30, 0.16, 0.50),   // violet
            colorC: SIMD3(0.05, 0.45, 0.48)    // teal
        )

        if let enc = cb.makeRenderCommandEncoder(descriptor: pass) {
            enc.setRenderPipelineState(context.pipeline)
            enc.setFragmentBytes(&u, length: MemoryLayout<Uniforms>.stride, index: 0)
            enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            enc.endEncoding()
        }
        let stats = self.stats
        cb.addCompletedHandler { buffer in
            stats.recordGPU(buffer.gpuEndTime - buffer.gpuStartTime)
        }
        cb.present(drawable)
        cb.commit()
        stats.recordFrame(cpuEncode: CACurrentMediaTime() - cpuStart)
    }
}
