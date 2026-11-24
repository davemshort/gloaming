import CoreGraphics
import Foundation
import ImageIO
import Metal
import Testing
@testable import WallpaperCore

@Suite("Day arc and look")
struct DayArcTests {
    let arc = DayArc(keyframes: [
        .init(dayFraction: 0.0, brightness: 0.3, saturation: 0.8),
        .init(dayFraction: 0.5, brightness: 1.0, saturation: 1.0),
        .init(dayFraction: 0.75, brightness: 0.6, saturation: 1.2),
    ], motion: 240)

    @Test func hitsKeyframesExactly() {
        let s0 = arc.sample(at: 0, base: .aurora), s5 = arc.sample(at: 0.5, base: .aurora)
        #expect(s0.brightness == 0.3 && s0.saturation == 0.8)
        #expect(s5.brightness == 1.0 && s5.saturation == 1.0)
    }

    @Test func interpolatesWithSmoothstep() {
        let mid = arc.sample(at: 0.25, base: .aurora)        // halfway 0 → 0.5
        #expect(abs(mid.brightness - 0.65) < 1e-9)
        let early = arc.sample(at: 0.05, base: .aurora)      // eases out of the keyframe
        #expect(early.brightness - 0.3 < (0.65 - 0.3) * 0.2)
    }

    @Test func wrapsAcrossMidnight() {
        // Between 0.75 (0.6) and 1.0 ≡ 0.0 (0.3): halfway is 0.875.
        let s = arc.sample(at: 0.875, base: .aurora)
        #expect(abs(s.brightness - 0.45) < 1e-9)
        #expect(arc.sample(at: 1.25, base: .aurora).brightness == arc.sample(at: 0.25, base: .aurora).brightness)
    }

    @Test func emptyAndSingleKeyframe() {
        let empty = DayArc(keyframes: [], motion: 0).sample(at: 0.3, base: .ocean)
        #expect(empty.brightness == 1 && empty.ramp == Palette.ocean.ramp(count: PaletteTransition.rampSize))
        let single = DayArc(keyframes: [.init(dayFraction: 0.2, brightness: 0.5)], motion: 0).sample(at: 0.9, base: .ocean)
        #expect(single.brightness == 0.5)
    }

    @Test func blendsKeyframePalettes() {
        let p = DayArc(keyframes: [.init(dayFraction: 0, palette: .ember), .init(dayFraction: 0.5, palette: .ocean)], motion: 0)
        let n = PaletteTransition.rampSize
        #expect(p.sample(at: 0, base: .aurora).ramp == Palette.ember.ramp(count: n))
        #expect(p.sample(at: 0.5, base: .aurora).ramp == Palette.ocean.ramp(count: n))
        let mid = p.sample(at: 0.25, base: .aurora).ramp
        #expect(mid != Palette.ember.ramp(count: n) && mid != Palette.ocean.ramp(count: n))
    }

    @Test func lookPhase() {
        var look = Look(palette: .aurora, seed: 3, time: 10, dayArc: arc)
        #expect(look.phase == 3 * Look.seedSpacing + 10)
        look.parameters.speed = 2
        #expect(look.phase(atDayFraction: 0.5) == look.phase + 240 * 2 * 0.5)
        #expect(Look(palette: .aurora, seed: 1).grainSeed != Look(palette: .aurora, seed: 2).grainSeed)
    }

    @Test func lookCodable() throws {
        let look = Look(palette: .forest, seed: 42, time: 12.5)
        #expect(try JSONDecoder().decode(Look.self, from: JSONEncoder().encode(look)) == look)
    }

    @Test func exportSizeParsing() {
        #expect(ExportSize("6016x3384") == ExportSize(width: 6016, height: 3384))
        #expect(ExportSize("12x") == nil)
        #expect(!ExportSize(width: 20_000, height: 100).isValid)
    }
}

@Suite("Export pipeline", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct ExportPipelineTests {
    let context: RenderContext
    let exporter: WallpaperExporter
    let dir: URL
    let size = ExportSize(width: 192, height: 108)

    init() throws {
        context = try RenderContext()
        exporter = WallpaperExporter(context: context)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("dw-export-\(UUID().uuidString)")
    }

    private func pixels(_ image: CGImage) -> Data {
        image.dataProvider!.data! as Data
    }

    private func meanLuma(_ image: CGImage) -> Double {
        let d = pixels(image)
        var sum = 0
        for i in stride(from: 0, to: d.count, by: 4) { sum += Int(d[i]) + Int(d[i + 1]) + Int(d[i + 2]) }
        return Double(sum) / Double(d.count / 4 * 3)
    }

    @Test func rendersAreDeterministic() throws {
        let look = Look(palette: .sunset, seed: 7, time: 3)
        let r = try FrameRenderer(context: context, size: size)
        let a = try r.render(exporter.scene(for: look), seed: look.grainSeed)
        let b = try r.render(exporter.scene(for: look), seed: look.grainSeed)
        #expect(pixels(a) == pixels(b))
        var other = look
        other.seed = 8
        let c = try r.render(exporter.scene(for: other), seed: other.grainSeed)
        #expect(pixels(a) != pixels(c))
    }

    @Test func nightFramesAreDarkerThanNoon() throws {
        let look = Look(palette: .ocean, seed: 1)
        let r = try FrameRenderer(context: context, size: size)
        let noon = try r.render(exporter.scene(for: look, dayFraction: 0.5), seed: 1)
        let night = try r.render(exporter.scene(for: look, dayFraction: 0), seed: 1)
        #expect(meanLuma(night) < meanLuma(noon) * 0.8)
    }

    @Test(arguments: ImageFiles.Format.allCases)
    func stillHasRightSizeAndColorSpace(format: ImageFiles.Format) throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try exporter.exportStill(Look(palette: .forest), size: size, format: format, to: dir, name: "still")
        #expect(url.pathExtension == format.fileExtension)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let img = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(img.width == size.width && img.height == size.height)
        #expect(img.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func timeOfDayFileHasFramesTimesAndBothTags() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try exporter.exportTimeOfDay(Look(palette: .aurora), frameCount: 12, size: size, to: dir, name: "day")
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.imageCount == 12)
        let ti = try #require(info.h24?["ti"] as? [[String: Any]])
        #expect(ti.compactMap { $0["t"] as? Double } == (0..<12).map { Double($0) / 12 })
        #expect((info.h24?["ap"] as? [String: Int]) == ["l": 6, "d": 0])   // noon frame light, midnight dark
        #expect(info.aprRaw == nil)                                          // keeps the file "Dynamic" 
    }

    @Test func appearanceFileDarkIsDarker() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try exporter.exportAppearance(Look(palette: .sunset), size: size, to: dir, name: "apr")
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetCount(src) == 2)
        let light = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        let dark = try #require(CGImageSourceCreateImageAtIndex(src, 1, nil))
        func luma(_ i: CGImage) -> Double {     // decode to a known layout first
            let ctx = CGContext(data: nil, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
            return meanLuma(ctx.makeImage()!)
        }
        #expect(luma(dark) < luma(light) * 0.8)
        #expect((DynamicHEIC.read(url)?.apr as? [String: Int]) == ["l": 0, "d": 1])
    }

    @Test func variationsAreDistinctFilesWithUniqueNames() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let urls = try exporter.exportVariations(Look(palette: .ember), count: 3, size: size, format: .png, to: dir, name: "v")
        #expect(Set(urls).count == 3)
        let data = try urls.map { try Data(contentsOf: $0) }
        #expect(Set(data).count == 3)
    }

    @Test func neverOverwritesAndLeavesNoPartialFiles() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let first = try exporter.exportStill(Look(palette: .ocean), size: size, format: .png, to: dir, name: "same")
        let second = try exporter.exportStill(Look(palette: .ocean), size: size, format: .png, to: dir, name: "same")
        #expect(first != second)
        #expect(second.lastPathComponent == "same 2.png")

        struct Boom: Error {}
        let target = dir.appendingPathComponent("broken.heic")
        #expect(throws: Boom.self) { try ImageFiles.writeAtomically(to: target) { temp in
            try Data([1, 2, 3]).write(to: temp)
            throw Boom()
        } }
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.contains("partial") || $0.contains("broken") }
        #expect(leftovers.isEmpty)
    }

    @Test func rejectsOversizedExports() {
        #expect(throws: FrameRenderer.Error.self) {
            _ = try FrameRenderer(context: context, size: ExportSize(width: 20_000, height: 100))
        }
    }
}

@Suite("Sun path")
struct SunPathTests {
    @Test func referenceDayPositions() {
        let noon = SunPath.position(atDayFraction: 0.5)
        #expect(abs(noon.altitude - 50) < 0.01 && abs(noon.azimuth - 180) < 0.01)
        let sunrise = SunPath.position(atDayFraction: 0.25)
        #expect(abs(sunrise.altitude) < 0.01 && abs(sunrise.azimuth - 90) < 0.01)
        let sunset = SunPath.position(atDayFraction: 0.75)
        #expect(abs(sunset.altitude) < 0.01 && abs(sunset.azimuth - 270) < 0.01)
        let midnight = SunPath.position(atDayFraction: 0)
        #expect(abs(midnight.altitude + 50) < 0.01 && (midnight.azimuth < 0.01 || midnight.azimuth > 359.99))
    }

    @Test func morningIsEastAndRisingEveningIsWestAndSetting() {
        let nine = SunPath.position(atDayFraction: 9.0 / 24), three = SunPath.position(atDayFraction: 15.0 / 24)
        #expect(nine.azimuth > 90 && nine.azimuth < 180 && nine.altitude > 0)
        #expect(three.azimuth > 180 && three.azimuth < 270 && abs(three.altitude - nine.altitude) < 0.01)
        for i in 0..<48 {
            let p = SunPath.position(atDayFraction: Double(i) / 48)
            #expect(p.azimuth >= 0 && p.azimuth < 360 && abs(p.altitude) <= 50.01)
        }
    }
}

@Suite("Sun-position export", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct SunExportTests {
    @Test func fileFollowsTheSunWithWorkingStills() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gl-sun-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let exporter = WallpaperExporter(context: try RenderContext())
        let url = try exporter.exportSunPosition(Preset.seasons[0].look, frameCount: 12,
                                                 size: ExportSize(width: 160, height: 90), to: dir, name: "Winter Dynamic")
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.imageCount == 12)
        #expect(info.h24Raw == nil && info.aprRaw == nil)          // solar only (Phase A2)
        let si = try #require(info.solar?["si"] as? [[String: Any]])
        #expect(si.count == 12)
        let noon = try #require(si.first { $0["i"] as? Int == 6 })
        #expect(noon["a"] as? Double == 50 && noon["z"] as? Double == 180)
        #expect((info.solar?["ap"] as? [String: Int]) == ["l": 6, "d": 0])
    }

    @Test func sunIsTheDefaultExportType() {
        #expect(ExportSettings().kind == .sunPosition)
        #expect(ExportSettings.Kind.allCases.first == .sunPosition)
    }
}
