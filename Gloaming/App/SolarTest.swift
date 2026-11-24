import CoreGraphics
import Foundation
import WallpaperCore

/// `--solar-test DIR`: files for the sun-position (solar) experiment. Six frames with very
/// different palettes, each tagged with a sun position; which one macOS shows reveals where it
/// thinks the sun is. Light (Still) = Noon, Dark (Still) = Night.
///   solar-a: solar tag only.   solar-b: solar + separate apr tag.
@MainActor
enum SolarTest {
    static let frames: [(name: String, preset: Preset, altitude: Double, azimuth: Double)] = [
        ("Night (purple)", Preset.vibes[0], -30, 0),        // Aurora
        ("Dawn (pink)", Preset.vibes[1], 0, 100),           // Sunset
        ("Morning (green)", Preset.seasons[1], 25, 135),    // Spring
        ("Noon (blue)", Preset.vibes[2], 45, 180),          // Ocean
        ("Afternoon (sand)", Preset.vibes[9], 25, 225),     // Desert
        ("Dusk (dark red)", Preset.vibes[3], 0, 260),       // Ember
    ]

    static func run(context: RenderContext, directory: String, size: ExportSize) throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let renderer = try FrameRenderer(context: context, size: size)
        let exporter = WallpaperExporter(context: context)
        let entries = frames.enumerated().map {
            DynamicHEIC.SolarEntry(imageIndex: $0.offset, altitude: $0.element.altitude, azimuth: $0.element.azimuth)
        }
        func frame(_ i: Int) throws -> CGImage {
            try renderer.render(exporter.scene(for: frames[i].preset.look), seed: 1)
        }
        for (name, apr) in [("solar-a (solar only)", false), ("solar-b (solar + apr)", true)] {
            let url = ImageFiles.uniqueURL(in: dir, baseName: name, fileExtension: "heic")
            try DynamicHEIC.writeSolar(frameCount: frames.count, entries: entries, lightIndex: 3, darkIndex: 0,
                                       appearanceTag: apr, to: url, quality: 0.75, frame: frame)
            print("wrote \(url.path)")
        }
        for (i, f) in frames.enumerated() {
            print(String(format: "  frame %d  %@  altitude %+.0f°  azimuth %.0f°", i, f.name, f.altitude, f.azimuth))
        }
    }
}
