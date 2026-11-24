import Foundation
import WallpaperCore

/// `--export` mode: renders wallpaper files from launch options and prints what it wrote,
/// with timing and peak memory. Used for testing until the editor (Phase C) exists.
@MainActor
enum ExportCommand {
    static func run(_ r: ExportRequest, options: LaunchOptions, context: RenderContext) {
        guard let dirPath = r.directory else { print("export: --out DIR is required"); return }
        let dir = URL(fileURLWithPath: (dirPath as NSString).expandingTildeInPath, isDirectory: true)
        guard let size = r.size ?? ExportSize.connectedDisplays().first else { print("export: no size"); return }
        let look = options.preset?.look ?? Look(palette: options.palette, parameters: options.parameters, seed: r.seed, time: r.time)
        let exporter = WallpaperExporter(context: context)
        let base = r.name ?? "\(options.preset?.name ?? options.palette.name) \(r.kind)"
        let start = Date()
        do {
            let urls: [URL]
            switch r.kind {
            case "still":
                urls = [try exporter.exportStill(look, size: size, format: r.format, to: dir, name: base)]
            case "sun":
                urls = [try exporter.exportSunPosition(look, frameCount: r.frames, size: size, to: dir, name: base)]
            case "time":
                urls = [try exporter.exportTimeOfDay(look, frameCount: r.frames, size: size, to: dir, name: base)]
            case "appearance":
                urls = [try exporter.exportAppearance(look, size: size, to: dir, name: base)]
            case "variations":
                urls = try exporter.exportVariations(look, count: r.count, size: size, format: r.format, to: dir, name: base)
            case "presets":
                // Review aid: every built-in preset as a still, plus each season's day sequence.
                var out = [try exporter.exportSheet(of: Preset.builtIns.map(\.look), labels: Preset.builtIns.map(\.name),
                                                    columns: 4, to: dir, name: "Built-in presets")]
                for p in Preset.seasons {
                    out.append(try exporter.exportContactSheet(p.look, frameCount: 12, to: dir, name: "\(p.name) day"))
                }
                urls = out
            case "sheet":
                urls = [try exporter.exportContactSheet(look, frameCount: r.frames,
                                                        aspect: Double(size.width) / Double(size.height), to: dir, name: base)]
            default:
                print("export: unknown kind '\(r.kind)' (still | sun | time | appearance | variations | sheet | presets)")
                return
            }
            let peak = ProcessMetrics.peakFootprint().map { String(format: "%.0f MB", Double($0) / 1_048_576) } ?? "n/a"
            print(String(format: "export %@ %@ in %.2f s · peak memory footprint %@ (measured)",
                         r.kind, size.description, Date().timeIntervalSince(start), peak))
            for url in urls {
                let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
                print(String(format: "  %@ (%.1f MB)", url.path, Double(bytes) / 1_048_576))
            }
        } catch {
            print("export failed: \(error)")
        }
    }
}
