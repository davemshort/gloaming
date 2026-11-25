import Foundation
import WallpaperCore

/// Command-line modes. Without any of these flags the app opens the editor window.
///
/// Export (renders files and exits):
///   --export KIND           still | sun | time | appearance | variations | sheet | presets
///   --out DIR               destination folder (required)
///   --size WxH              output pixels (default: main display's native resolution)
///   --format png|heic       for still/variations (default png)
///   --frames N              time-of-day frames (default 12)
///   --count N               variations (default 6)
///   --seed N --time X       which part of the animation
///   --name NAME             base file name
/// Look (all modes): --preset NAME (built-in, e.g. winter), --palette ID, --speed, --complexity, --blend, --grain, --brightness, --saturation
/// Other:
///   --snapshot PATH.png     one offscreen frame (with --snapshot-size WxH, --start-phase X)
///   --phase-a-test DIR      Phase A native-format test files (uses --snapshot-size)
///   --exit-after SECONDS    quit the editor automatically (smoke tests)
///   --window-size WxH       editor window size in points (screenshots)
///   --icon DIR [--icon-variant NAME]  app icon review sheet / .icns (see IconCommand)
struct LaunchOptions {
    var palette: Palette = .aurora
    var preset: Preset?
    var parameters = RenderParameters()
    var renderScale: Double = 0.25
    var startPhase: Double = 0
    var exitAfter: TimeInterval?
    var windowSize: CGSize?
    var snapshotPath: String?
    var snapshotSize = (width: 1920, height: 1080)
    var phaseATestDir: String?
    var iconDir: String?
    var solarTestDir: String?
    var iconVariant: String?
    var export: ExportRequest?
    var warnings: [String] = []

    var isCommandLineMode: Bool { snapshotPath != nil || phaseATestDir != nil || export != nil || iconDir != nil || solarTestDir != nil }

    static func parse(_ args: [String] = CommandLine.arguments) -> LaunchOptions {
        var o = LaunchOptions()
        var it = args.dropFirst().makeIterator()
        func double(_ flag: String) -> Double? {
            guard let s = it.next(), let v = Double(s) else { o.warnings.append("\(flag) needs a number"); return nil }
            return v
        }
        func request() -> ExportRequest { o.export ?? ExportRequest() }
        while let a = it.next() {
            switch a {
            case "--preset":
                let name = (it.next() ?? "").lowercased()
                if let p = Preset.builtIns.first(where: { $0.name.lowercased() == name }) { o.preset = p }
                else { o.warnings.append("unknown preset '\(name)'") }
            case "--palette":
                if let id = it.next(), let p = Palette.builtIn(id: id) { o.palette = p }
                else { o.warnings.append("unknown palette; using Aurora") }
            case "--speed": if let v = double(a) { o.parameters.speed = v }
            case "--complexity": if let v = double(a) { o.parameters.complexity = v }
            case "--blend": if let v = double(a) { o.parameters.blend = v }
            case "--grain": if let v = double(a) { o.parameters.grain = v }
            case "--brightness": if let v = double(a) { o.parameters.brightness = v }
            case "--saturation": if let v = double(a) { o.parameters.saturation = v }
            case "--render-scale": if let v = double(a) { o.renderScale = max(0.05, min(1, v)) }
            case "--start-phase": if let v = double(a) { o.startPhase = v }
            case "--exit-after": o.exitAfter = double(a)
            case "--window-size":
                if let s = it.next().flatMap(ExportSize.init) { o.windowSize = CGSize(width: s.width, height: s.height) }
                else { o.warnings.append("--window-size needs WxH") }
            case "--snapshot": o.snapshotPath = it.next()
            case "--snapshot-size":
                let parts = (it.next() ?? "").split(separator: "x").compactMap { Int($0) }
                if parts.count == 2, parts[0] > 0, parts[1] > 0 { o.snapshotSize = (parts[0], parts[1]) }
                else { o.warnings.append("--snapshot-size needs WxH") }
            case "--phase-a-test": o.phaseATestDir = it.next()
            case "--icon": o.iconDir = it.next()
            case "--solar-test": o.solarTestDir = it.next()
            case "--icon-variant": o.iconVariant = it.next()
            case "--export": var r = request(); r.kind = it.next() ?? ""; o.export = r
            case "--out": var r = request(); r.directory = it.next(); o.export = r
            case "--size": var r = request(); r.size = it.next().flatMap(ExportSize.init); o.export = r
            case "--format": var r = request(); r.format = it.next().flatMap(ImageFiles.Format.init) ?? .png; o.export = r
            case "--frames": var r = request(); r.frames = double(a).map(Int.init) ?? 12; o.export = r
            case "--count": var r = request(); r.count = double(a).map(Int.init) ?? 6; o.export = r
            case "--seed": var r = request(); r.seed = double(a).map { UInt32(max(0, $0)) } ?? 0; o.export = r
            case "--time": var r = request(); r.time = double(a) ?? 0; o.export = r
            case "--name": var r = request(); r.name = it.next(); o.export = r
            default: break   // ignore unknown (e.g. -NSDocumentRevisionsDebugMode)
            }
        }
        o.parameters = o.parameters.clamped()
        return o
    }
}

struct ExportRequest {
    var kind = ""
    var directory: String?
    var size: ExportSize?
    var format: ImageFiles.Format = .png
    var frames = 12
    var count = 6
    var seed: UInt32 = 0
    var time: Double = 0
    var name: String?
}
