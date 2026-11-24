import AppKit
import Metal
import QuartzCore

/// Per-display rendering surface: a CAMetalLayer-backed view driven by the macOS 14
/// `NSView.displayLink(target:selector:)`, which follows whichever screen the view is on.
///
/// Resolution:
/// - `renderScale`: field (gradient) resolution as a fraction of the screen's backing pixels.
/// - `outputScale`: drawable resolution as a fraction of backing pixels, or nil for one
///   pixel per point (the default). The composite pass (upsampling, grain, dither) runs at
///   this size; the window server scales the rest. On a 2× display, nil halves drawable
///   memory and composite cost versus native (measured: 145 MB vs 359 MB footprint).
@MainActor
public final class WallpaperView: NSView {
    private let context: RenderContext
    private let scene: SceneState
    private var displayLink: CADisplayLink?
    private var fieldTexture: MTLTexture?
    private var frameIndex: UInt32 = 0
    public let stats = FrameStats()

    public var renderScale: Double { didSet { updateSizes() } }
    public var outputScale: Double? { didSet { updateSizes() } }
    public var preferredFPS: Int { didSet { applyFrameRate() } }
    public var isPaused = false { didSet { displayLink?.isPaused = isPaused } }

    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    public init(context: RenderContext, scene: SceneState, renderScale: Double, outputScale: Double?, fps: Int) {
        self.context = context
        self.scene = scene
        self.renderScale = renderScale
        self.outputScale = outputScale
        self.preferredFPS = fps
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    public override func makeBackingLayer() -> CALayer {
        let l = CAMetalLayer()
        l.device = context.device
        l.pixelFormat = RenderContext.outputPixelFormat
        l.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        l.framebufferOnly = true
        l.isOpaque = true
        l.contentsGravity = .resize
        l.magnificationFilter = .linear
        return l
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        link.isPaused = isPaused
        displayLink = link
        applyFrameRate()
        updateSizes()
    }

    public override func layout() {
        super.layout()
        updateSizes()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateSizes()
    }

    public func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    public var outputSize: CGSize { metalLayer.drawableSize }
    public var fieldSize: CGSize {
        fieldTexture.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    private func applyFrameRate() {
        let f = Float(preferredFPS)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: f, maximum: f, preferred: f)
    }

    /// Pixel size for a fraction of backing resolution; nil means one pixel per point.
    private func pixels(_ scale: Double?) -> (Int, Int) {
        let s: Double = scale.map { Double(window?.backingScaleFactor ?? 2) * $0 } ?? 1
        return (max(1, Int((bounds.width * s).rounded())), max(1, Int((bounds.height * s).rounded())))
    }

    /// Reallocates only when a size actually changes (display/resolution change, scale change).
    private func updateSizes() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let (ow, oh) = pixels(outputScale)
        let drawable = CGSize(width: ow, height: oh)
        if metalLayer.drawableSize != drawable { metalLayer.drawableSize = drawable }
        metalLayer.contentsScale = window?.backingScaleFactor ?? 2

        let (fw, fh) = pixels(renderScale)
        if fieldTexture?.width != fw || fieldTexture?.height != fh {
            fieldTexture = context.makeRenderTarget(width: fw, height: fh, format: RenderContext.fieldPixelFormat)
        }
    }

    @objc private func step(_ link: CADisplayLink) {
        scene.advance(to: link.targetTimestamp)
        drawFrame()
    }

    /// Draws the scene as it is now, without advancing time. Used while paused (scrubbing,
    /// edits), because the display link doesn't fire then.
    public func redraw() {
        updateSizes()
        drawFrame()
    }

    private func drawFrame() {
        let cpuStart = CACurrentMediaTime()
        guard let field = fieldTexture,
              let drawable = metalLayer.nextDrawable(),
              let commandBuffer = context.queue.makeCommandBuffer() else { return }

        frameIndex &+= 1
        FrameEncoder.encode(commandBuffer, context: context, scene: scene,
                            field: field, output: drawable.texture, seed: frameIndex)
        let stats = self.stats
        commandBuffer.addCompletedHandler { cb in
            stats.recordGPU(cb.gpuEndTime - cb.gpuStartTime)
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
        stats.recordFrame(cpuEncode: CACurrentMediaTime() - cpuStart)
    }
}
