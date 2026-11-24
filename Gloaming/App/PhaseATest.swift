import CoreGraphics
import Foundation
import WallpaperCore

/// Generates the files for the Phase A feasibility check (PROJECT.md §9): can exported
/// wallpapers be applied through System Settings, and do they show on the desktop, the lock
/// screen, and switch as intended? Distinct palettes make each frame easy to identify.
@MainActor
enum PhaseATest {
    static func run(context: RenderContext, directory: String, size: (width: Int, height: Int),
                    renderScale: Double) throws {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        func frame(_ palette: Palette, phase: Double) throws -> CGImage {
            let scene = SceneState(context: context, palette: palette, parameters: RenderParameters(), phase: phase)
            let img = try Snapshot.render(context: context, scene: scene, width: size.width, height: size.height,
                                          fieldScale: Snapshot.fieldScale(renderScale: renderScale))
            guard let cg = Snapshot.makeCGImage(img) else { throw CocoaError(.fileWriteUnknown) }
            return cg
        }

        // 1. Still (Sunset).
        let still = try Snapshot.render(
            context: context,
            scene: SceneState(context: context, palette: .sunset, parameters: RenderParameters(), phase: 300),
            width: size.width, height: size.height, fieldScale: Snapshot.fieldScale(renderScale: renderScale))
        try Snapshot.writePNG(still, to: dir.appendingPathComponent("1-still-sunset.png"))

        // 2. Light/dark: light = Sunset, dark = Ocean.
        try DynamicHEIC.writeAppearance(light: try frame(.sunset, phase: 300), dark: try frame(.ocean, phase: 300),
                                        to: dir.appendingPathComponent("2-appearance-light-sunset-dark-ocean.heic"))

        // 3. Time of day. Scheduled so the dynamic frame *now* is Ember, which is neither the
        //    light (Sunset) nor the dark (Ocean) still, so each mode is unambiguous:
        //    Ember from 1 min ago; Sunset at +60 min, Ocean +62, Forest +64.
        //    3a: h24 only. 3b: h24 plus a separate apr tag.
        let cal = Calendar.current
        let now = Date()
        let secondsToday = now.timeIntervalSince(cal.startOfDay(for: now))
        func fraction(_ offsetMinutes: Double) -> Double {
            let f = (secondsToday + offsetMinutes * 60) / 86_400
            return f - floor(f)
        }
        let palettes: [Palette] = [.sunset, .ocean, .forest, .ember]
        let images = try palettes.enumerated().map { try frame($1, phase: 300 + Double($0) * 40) }
        let entries = [(60.0, 0), (62.0, 1), (64.0, 2), (-1.0, 3)].map {
            DynamicHEIC.TimeEntry(imageIndex: $0.1, dayFraction: fraction($0.0))
        }
        try DynamicHEIC.writeTimeOfDay(images: images, entries: entries, lightIndex: 0, darkIndex: 1,
                                       appearanceTag: false,
                                       to: dir.appendingPathComponent("3a-time-h24-only.heic"))
        try DynamicHEIC.writeTimeOfDay(images: images, entries: entries, lightIndex: 0, darkIndex: 1,
                                       appearanceTag: true,
                                       to: dir.appendingPathComponent("3b-time-h24-plus-apr.heic"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("3-time-of-day-sunset-ocean-forest-ember.heic"))

        // 4. Does a time-of-day file with an apr tag still follow the clock, or does macOS
        //    switch to appearance mode ("Automatic")? Ember now, Forest at +3 min; light =
        //    Sunset, dark = Ocean, so time-following and appearance-following look different.
        //    4a: h24 + apr. 4b: h24 only (control).
        let switching = [(60.0, 0), (62.0, 1), (3.0, 2), (-1.0, 3)].map {
            DynamicHEIC.TimeEntry(imageIndex: $0.1, dayFraction: fraction($0.0))
        }
        try DynamicHEIC.writeTimeOfDay(images: images, entries: switching, lightIndex: 0, darkIndex: 1,
                                       appearanceTag: true,
                                       to: dir.appendingPathComponent("4a-switching-h24-plus-apr.heic"))
        try DynamicHEIC.writeTimeOfDay(images: images, entries: switching, lightIndex: 0, darkIndex: 1,
                                       appearanceTag: false,
                                       to: dir.appendingPathComponent("4b-switching-h24-only.heic"))

        let fmt = DateFormatter()
        fmt.timeStyle = .short
        let schedule = [(-1.0, "Ember"), (3, "Forest (files 4a/4b)"), (60, "Sunset"), (62, "Ocean")]
            .map { "\(fmt.string(from: now.addingTimeInterval($0.0 * 60))) \($0.1)" }
            .joined(separator: ", ")
        print("wrote \(dir.path)")
        print("time-of-day schedule: \(schedule)")
    }
}
