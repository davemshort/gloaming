import CoreGraphics
import Foundation
import Metal

/// Renders export frames at a fixed size, reusing its GPU render targets across frames.
/// Each frame costs one GPU→CPU copy into a `Data` buffer that backs the returned CGImage.
@MainActor
public final class FrameRenderer {
    public let width: Int
    public let height: Int
    private let context: RenderContext
    private let output: MTLTexture
    private let field: MTLTexture

    public enum Error: Swift.Error, CustomStringConvertible {
        case invalidSize(ExportSize), allocationFailed, imageCreationFailed
        public var description: String {
            switch self {
            case .invalidSize(let s): "Unsupported export size \(s) (max \(ExportSize.maxDimension) px per side)"
            case .allocationFailed: "Could not allocate GPU memory for the export"
            case .imageCreationFailed: "Could not create the output image"
            }
        }
    }

    /// `fieldScale`: gradient resolution relative to output (0.5 matches the desktop preview on
    /// a 2× display). The gradient is soft, so it upsamples cleanly; grain and dither are
    /// always applied at full output resolution.
    public init(context: RenderContext, size: ExportSize, fieldScale: Double = 0.5) throws {
        guard size.isValid else { throw Error.invalidSize(size) }
        guard let output = context.makeRenderTarget(width: size.width, height: size.height,
                                                    format: RenderContext.outputPixelFormat, readable: true),
              let field = context.makeRenderTarget(width: max(1, Int((Double(size.width) * fieldScale).rounded())),
                                                   height: max(1, Int((Double(size.height) * fieldScale).rounded())),
                                                   format: RenderContext.fieldPixelFormat) else {
            throw Error.allocationFailed
        }
        self.context = context
        self.width = size.width
        self.height = size.height
        self.output = output
        self.field = field
    }

    public func render(_ scene: SceneState, seed: UInt32) throws -> CGImage {
        guard let cb = context.queue.makeCommandBuffer() else { throw Error.allocationFailed }
        FrameEncoder.encode(cb, context: context, scene: scene, field: field, output: output, seed: seed)
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw error }

        let bytesPerRow = width * 4
        var data = Data(count: bytesPerRow * height)
        data.withUnsafeMutableBytes { buf in
            output.getBytes(buf.baseAddress!, bytesPerRow: bytesPerRow,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: bytesPerRow, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false,
                                  intent: .defaultIntent) else {
            throw Error.imageCreationFailed
        }
        return image
    }
}
