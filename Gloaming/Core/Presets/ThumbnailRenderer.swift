import CoreGraphics
import Foundation

/// Small rendered previews of looks (preset browser, day strip). Uses the exporter's own
/// scenes, so a day-strip frame is exactly what that hour of a Dynamic export looks like.
/// One reused render target; results cached by content.
@MainActor
public final class ThumbnailRenderer {
    public static let size = ExportSize(width: 256, height: 144)     // 2× a 128×72 pt cell

    private let exporter: WallpaperExporter
    private let context: RenderContext
    private var renderers: [ExportSize: FrameRenderer] = [:]
    private struct Key: Hashable { var look: Look; var dayFraction: Double?; var size: ExportSize }
    private var cache: [Key: CGImage] = [:]
    private static let cacheLimit = 300

    public init(context: RenderContext) {
        self.context = context
        exporter = WallpaperExporter(context: context)
    }

    /// Thumbnail size for an aspect ratio (height fixed at 144 px), so the day strip frames
    /// exactly what the export target shows.
    public static func size(aspect: Double) -> ExportSize {
        let a = aspect.isFinite ? min(max(aspect, 0.5), 4) : 16.0 / 9.0
        return ExportSize(width: Int((144 * a).rounded()), height: 144)
    }

    /// The look as designed (`dayFraction` nil) or at a time of day.
    public func image(for look: Look, dayFraction: Double? = nil, size: ExportSize = ThumbnailRenderer.size) -> CGImage? {
        let key = Key(look: look, dayFraction: dayFraction, size: size)
        if let hit = cache[key] { return hit }
        do {
            if renderers[size] == nil {
                if renderers.count > 4 { renderers.removeAll() }
                renderers[size] = try FrameRenderer(context: context, size: size)
            }
            guard let renderer = renderers[size] else { return nil }
            let image = try renderer.render(exporter.scene(for: look, dayFraction: dayFraction), seed: look.grainSeed)
            if cache.count >= Self.cacheLimit { cache.removeAll() }
            cache[key] = image
            return image
        } catch {
            return nil
        }
    }
}
