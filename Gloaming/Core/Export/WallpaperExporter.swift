import CoreGraphics
import Foundation

/// Turns a `Look` into wallpaper files macOS uses natively (desktop and lock screen; verified
/// in Phase A on macOS 27.2.1).
///
/// Exports are deterministic: scenes are built settled at an exact phase (never advanced),
/// with grain seeded from the look. Same look + size → same pixels on the same GPU; other
/// GPUs may differ by a level or two.
@MainActor
public final class WallpaperExporter {
    private let context: RenderContext
    /// Lossy quality for HEIC output (dynamic wallpapers must be HEIC). 0.75 was chosen in
    /// Phase B: no banding in dark gradients even at 0.6, grain intact at 0.75 (smeared at 0.6),
    /// and files about 2.4× smaller than at 0.9.
    public var heicQuality: Double = 0.75
    /// Gradient resolution relative to output.
    public var fieldScale: Double = 0.5

    public init(context: RenderContext) {
        self.context = context
    }

    // MARK: - Frames

    /// The scene for a still (`dayFraction` nil: the look as designed) or for the frame shown at
    /// `dayFraction` in a time-of-day sequence (day arc applied).
    public func scene(for look: Look, dayFraction: Double? = nil) -> SceneState {
        guard let f = dayFraction else {
            return SceneState(context: context, palette: look.palette, parameters: look.parameters, phase: look.phase)
        }
        let sample = look.dayArc.sample(at: f, base: look.palette)
        var p = look.parameters
        p.brightness *= sample.brightness
        p.saturation *= sample.saturation
        return SceneState(context: context, palette: look.palette, ramp: sample.ramp, parameters: p,
                          phase: look.phase(atDayFraction: f))
    }

    /// Day fractions for an `n`-frame time-of-day export: evenly spaced from midnight.
    public static func dayFractions(frameCount n: Int) -> [Double] {
        (0..<n).map { Double($0) / Double(n) }
    }

    /// Index of the frame closest to `target` (wrapping).
    static func nearestFrame(to target: Double, in fractions: [Double]) -> Int {
        func distance(_ f: Double) -> Double { let d = abs(f - target); return min(d, 1 - d) }
        return fractions.indices.min { distance(fractions[$0]) < distance(fractions[$1]) } ?? 0
    }

    // MARK: - Formats

    @discardableResult
    public func exportStill(_ look: Look, size: ExportSize, format: ImageFiles.Format,
                            to directory: URL, name: String) throws -> URL {
        let renderer = try FrameRenderer(context: context, size: size, fieldScale: fieldScale)
        let image = try renderer.render(scene(for: look), seed: look.grainSeed)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: format.fileExtension)
        try ImageFiles.writeStill(image, format: format, quality: heicQuality, to: url)
        return url
    }

    /// Dynamic wallpaper that changes through the day (System Settings: "Dynamic"). The `ap`
    /// entry names the frame nearest noon as light and nearest midnight as dark, but macOS 27
    /// doesn't use it for Light/Dark (Still), which keep the current frame. Use
    /// `exportAppearance` for a proper light/dark wallpaper.
    @discardableResult
    public func exportTimeOfDay(_ look: Look, frameCount: Int, size: ExportSize,
                                to directory: URL, name: String) throws -> URL {
        let fractions = Self.dayFractions(frameCount: max(2, frameCount))
        let renderer = try FrameRenderer(context: context, size: size, fieldScale: fieldScale)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: "heic")
        let entries = fractions.enumerated().map { DynamicHEIC.TimeEntry(imageIndex: $0.offset, dayFraction: $0.element) }
        try DynamicHEIC.writeTimeOfDay(
            frameCount: fractions.count, entries: entries,
            lightIndex: Self.nearestFrame(to: 0.5, in: fractions),
            darkIndex: Self.nearestFrame(to: 0, in: fractions),
            to: url, quality: heicQuality) { index in
                try renderer.render(self.scene(for: look, dayFraction: fractions[index]), seed: look.grainSeed)
            }
        return url
    }

    /// Dynamic wallpaper that follows the real sun for the Mac's location and date (System
    /// Settings: "Dynamic … based on your location"). Requires Location Services on the Mac;
    /// Gloaming itself never reads location. Frames are the same as a clock export's, each
    /// tagged with a sun altitude chosen by light (twilight, sunrise, midday; see `SunPath`).
    /// Light (Still) = the frame nearest noon, Dark (Still) = nearest midnight; these work for
    /// solar files (Phase A2), unlike clock files.
    @discardableResult
    public func exportSunPosition(_ look: Look, frameCount: Int, size: ExportSize,
                                  to directory: URL, name: String) throws -> URL {
        let fractions = Self.dayFractions(frameCount: max(2, frameCount))
        let renderer = try FrameRenderer(context: context, size: size, fieldScale: fieldScale)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: "heic")
        let entries = SunPath.solarEntries(forDayFractions: fractions).map {
            DynamicHEIC.SolarEntry(imageIndex: $0.imageIndex, altitude: $0.position.altitude, azimuth: $0.position.azimuth)
        }
        try DynamicHEIC.writeSolar(
            frameCount: fractions.count, entries: entries,
            lightIndex: Self.nearestFrame(to: 0.5, in: fractions),
            darkIndex: Self.nearestFrame(to: 0, in: fractions),
            to: url, quality: heicQuality) { index in
                try renderer.render(self.scene(for: look, dayFraction: fractions[index]), seed: look.grainSeed)
            }
        return url
    }

    /// Dynamic wallpaper that follows Light/Dark appearance: the day arc at noon and at midnight.
    @discardableResult
    public func exportAppearance(_ look: Look, size: ExportSize, to directory: URL, name: String) throws -> URL {
        let renderer = try FrameRenderer(context: context, size: size, fieldScale: fieldScale)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: "heic")
        try DynamicHEIC.writeAppearance(to: url, quality: heicQuality) { index in
            try renderer.render(self.scene(for: look, dayFraction: index == 0 ? 0.5 : 0), seed: look.grainSeed)
        }
        return url
    }

    /// `count` stills with different seeds, for macOS's "rotate through folder" option.
    @discardableResult
    public func exportVariations(_ look: Look, count: Int, size: ExportSize, format: ImageFiles.Format,
                                 to directory: URL, name: String) throws -> [URL] {
        let renderer = try FrameRenderer(context: context, size: size, fieldScale: fieldScale)
        return try (0..<max(1, count)).map { i in
            try autoreleasepool {
                var v = look
                v.seed = look.seed &+ UInt32(i) &* 7919
                let image = try renderer.render(scene(for: v), seed: v.grainSeed)
                let url = ImageFiles.uniqueURL(in: directory, baseName: "\(name) \(i + 1)", fileExtension: format.fileExtension)
                try ImageFiles.writeStill(image, format: format, quality: heicQuality, to: url)
                return url
            }
        }
    }

    /// One PNG tiling several looks (stills) with labels, e.g. the preset library.
    @discardableResult
    public func exportSheet(of looks: [Look], labels: [String], columns: Int, thumbnailWidth: Int = 480,
                            aspect: Double = 16.0 / 9.0, to directory: URL, name: String) throws -> URL {
        let thumb = ExportSize(width: thumbnailWidth, height: Int((Double(thumbnailWidth) / aspect).rounded()))
        let renderer = try FrameRenderer(context: context, size: thumb, fieldScale: fieldScale)
        let frames = try looks.map { try renderer.render(scene(for: $0), seed: $0.grainSeed) }
        let sheet = try ContactSheet.make(frames: frames, labels: labels, columns: columns)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: "png")
        try ImageFiles.writeStill(sheet, format: .png, quality: 1, to: url)
        return url
    }

    /// One PNG tiling every frame of a time-of-day export with its clock time, for reviewing
    /// how the sequence evolves across the day.
    @discardableResult
    public func exportContactSheet(_ look: Look, frameCount: Int, thumbnailWidth: Int = 640,
                                   aspect: Double = 16.0 / 9.0, to directory: URL, name: String) throws -> URL {
        let fractions = Self.dayFractions(frameCount: max(2, frameCount))
        let thumb = ExportSize(width: thumbnailWidth, height: Int((Double(thumbnailWidth) / aspect).rounded()))
        let renderer = try FrameRenderer(context: context, size: thumb, fieldScale: fieldScale)
        let frames = try fractions.map { try renderer.render(scene(for: look, dayFraction: $0), seed: look.grainSeed) }
        let labels = fractions.map { f -> String in
            let minutes = Int((f * 24 * 60).rounded())
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }
        let sheet = try ContactSheet.make(frames: frames, labels: labels, columns: frameCount > 9 ? 4 : 3)
        let url = ImageFiles.uniqueURL(in: directory, baseName: name, fileExtension: "png")
        try ImageFiles.writeStill(sheet, format: .png, quality: 1, to: url)
        return url
    }
}
