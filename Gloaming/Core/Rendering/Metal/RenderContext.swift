import Metal

/// Shared GPU state for every display: one device, one command queue, compiled pipelines
/// and samplers. Create once per process.
@MainActor
public final class RenderContext {
    public static let fieldPixelFormat: MTLPixelFormat = .rgba16Float
    public static let outputPixelFormat: MTLPixelFormat = .bgra8Unorm

    public let device: MTLDevice
    public let queue: MTLCommandQueue
    public let fieldPipeline: MTLRenderPipelineState
    public let compositePipeline: MTLRenderPipelineState
    public let linearClamp: MTLSamplerState

    public enum Error: Swift.Error, CustomStringConvertible {
        case noDevice, missingFunction(String), samplerFailed
        public var description: String {
            switch self {
            case .noDevice: "No Metal device is available"
            case .missingFunction(let n): "Shader function \(n) is missing"
            case .samplerFailed: "Could not create sampler"
            }
        }
    }

    public init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device, let queue = device.makeCommandQueue() else { throw Error.noDevice }
        let library = try device.makeLibrary(source: WallpaperShaders.source, options: nil)
        self.device = device
        self.queue = queue
        fieldPipeline = try device.makeRenderPipelineState(
            descriptor: Self.pipelineDescriptor(library, fragment: "field_fragment", format: Self.fieldPixelFormat))
        compositePipeline = try device.makeRenderPipelineState(
            descriptor: Self.pipelineDescriptor(library, fragment: "composite_fragment", format: Self.outputPixelFormat))

        let s = MTLSamplerDescriptor()
        s.minFilter = .linear
        s.magFilter = .linear
        s.sAddressMode = .clampToEdge
        s.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: s) else { throw Error.samplerFailed }
        linearClamp = sampler
    }

    nonisolated static func pipelineDescriptor(_ library: MTLLibrary, fragment: String,
                                               format: MTLPixelFormat) throws -> MTLRenderPipelineDescriptor {
        guard let v = library.makeFunction(name: "fullscreen_vertex") else { throw Error.missingFunction("fullscreen_vertex") }
        guard let f = library.makeFunction(name: fragment) else { throw Error.missingFunction(fragment) }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = v
        d.fragmentFunction = f
        d.colorAttachments[0].pixelFormat = format
        return d
    }

    /// A 256×1 rgba16Float texture holding OKLab (L, a, b, 1) stops. A new texture is made
    /// for every palette change so frames already in flight never see a half-written ramp.
    public func makeRampTexture(_ ramp: [OKLab]) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: ramp.count,
                                                         height: 1, mipmapped: false)
        d.usage = .shaderRead
        d.storageMode = .shared
        guard let tex = device.makeTexture(descriptor: d) else { return nil }
        var texels = [Float16](repeating: 1, count: ramp.count * 4)
        for (i, c) in ramp.enumerated() {
            texels[i * 4] = Float16(c.L)
            texels[i * 4 + 1] = Float16(c.a)
            texels[i * 4 + 2] = Float16(c.b)
        }
        texels.withUnsafeBytes { bytes in
            tex.replace(region: MTLRegionMake2D(0, 0, ramp.count, 1), mipmapLevel: 0,
                        withBytes: bytes.baseAddress!, bytesPerRow: ramp.count * 8)
        }
        return tex
    }

    /// Offscreen render target (private storage unless `readable`).
    public func makeRenderTarget(width: Int, height: Int, format: MTLPixelFormat,
                                 readable: Bool = false) -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: max(1, width),
                                                         height: max(1, height), mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = readable ? .shared : .private
        return device.makeTexture(descriptor: d)
    }
}
