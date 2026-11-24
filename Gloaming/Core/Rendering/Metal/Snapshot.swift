import CoreGraphics
import Foundation
import ImageIO
import Metal

/// Renders single frames offscreen with exactly the on-screen pipeline. Used for tests,
/// visual review without Screen Recording permission, and README screenshots.
@MainActor
public enum Snapshot {
    public struct Image {
        public let width: Int
        public let height: Int
        /// BGRA8, sRGB-encoded, row-major, `width * 4` bytes per row.
        public let bytes: [UInt8]
    }

    /// `fieldScale` is the field (gradient) size relative to the output size. On the desktop
    /// with defaults (field ¼ of backing pixels, output 1 px per point on a 2× display) it is
    /// 0.5; see `fieldScale(renderScale:backingScale:)`.
    public static func render(context: RenderContext, scene: SceneState, width: Int, height: Int,
                              fieldScale: Double, seed: UInt32 = 1) throws -> Image {
        guard let output = context.makeRenderTarget(width: width, height: height,
                                                    format: RenderContext.outputPixelFormat, readable: true),
              let field = context.makeRenderTarget(width: Int((Double(width) * fieldScale).rounded()),
                                                   height: Int((Double(height) * fieldScale).rounded()),
                                                   format: RenderContext.fieldPixelFormat),
              let cb = context.queue.makeCommandBuffer() else {
            throw RenderContext.Error.noDevice
        }
        FrameEncoder.encode(cb, context: context, scene: scene, field: field, output: output, seed: seed)
        cb.commit()
        cb.waitUntilCompleted()
        if let error = cb.error { throw error }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        bytes.withUnsafeMutableBytes { buf in
            output.getBytes(buf.baseAddress!, bytesPerRow: width * 4,
                            from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        return Image(width: width, height: height, bytes: bytes)
    }

    /// Field/output ratio the desktop uses when output is 1 px per point.
    public static func fieldScale(renderScale: Double, backingScale: Double = 2) -> Double {
        min(1, renderScale * backingScale)
    }

    /// Wraps the pixels in an sRGB CGImage (no copy of the pixel data beyond `Data`).
    public static func makeCGImage(_ image: Image) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(image.bytes) as CFData) else { return nil }
        return CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: image.width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                | CGBitmapInfo.byteOrder32Little.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    public static func writePNG(_ image: Image, to url: URL) throws {
        guard let cg = makeCGImage(image),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// Mean absolute per-channel difference (0...255) between two same-size images.
    public static func meanAbsoluteDifference(_ a: Image, _ b: Image) -> Double {
        precondition(a.bytes.count == b.bytes.count)
        var total = 0
        for i in 0..<a.bytes.count where i % 4 != 3 {
            total += abs(Int(a.bytes[i]) - Int(b.bytes[i]))
        }
        return Double(total) / Double(a.bytes.count / 4 * 3)
    }
}
