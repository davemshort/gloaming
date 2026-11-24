import CoreGraphics
import Foundation
import Testing
@testable import WallpaperCore

@Suite("Dynamic HEIC export")
struct ExportTests {
    private func solidImage(_ gray: CGFloat, size: Int = 64) -> CGImage {
        let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(gray: gray, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()!
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    @Test func timeOfDayRoundTrip() throws {
        let url = tempURL("time.heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [DynamicHEIC.TimeEntry(imageIndex: 1, dayFraction: 0.75),
                       DynamicHEIC.TimeEntry(imageIndex: 0, dayFraction: 0.25)]
        try DynamicHEIC.writeTimeOfDay(images: [solidImage(0.2), solidImage(0.8)], entries: entries,
                                       lightIndex: 0, darkIndex: 1, to: url)
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.imageCount == 2)
        let h24 = try #require(info.h24)
        let ti = try #require(h24["ti"] as? [[String: Any]])
        #expect(ti.map { $0["i"] as? Int } == [0, 1])               // written sorted by time
        #expect(ti.map { $0["t"] as? Double } == [0.25, 0.75])
        let ap = try #require(h24["ap"] as? [String: Int])
        #expect(ap == ["l": 0, "d": 1])
        // No separate apr tag by default: with it, macOS 27 ignores the time schedule.
        #expect(info.aprRaw == nil)
    }

    @Test func timeOfDayWithAppearanceTagOnRequest() throws {
        let url = tempURL("time-apr.heic")
        defer { try? FileManager.default.removeItem(at: url) }
        try DynamicHEIC.writeTimeOfDay(images: [solidImage(0.2), solidImage(0.8)],
                                       entries: [DynamicHEIC.TimeEntry(imageIndex: 0, dayFraction: 0)],
                                       lightIndex: 0, darkIndex: 1, appearanceTag: true, to: url)
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.h24Raw != nil)
        #expect((info.apr as? [String: Int]) == ["l": 0, "d": 1])
    }

    @Test func appearanceRoundTrip() throws {
        let url = tempURL("apr.heic")
        defer { try? FileManager.default.removeItem(at: url) }
        try DynamicHEIC.writeAppearance(light: solidImage(0.9), dark: solidImage(0.1), to: url)
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.imageCount == 2)
        #expect((info.apr as? [String: Int]) == ["l": 0, "d": 1])
        #expect(info.h24Raw == nil)
    }

    @Test func solarRoundTrip() throws {
        let url = tempURL("solar.heic")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [DynamicHEIC.SolarEntry(imageIndex: 0, altitude: -30, azimuth: 0),
                       DynamicHEIC.SolarEntry(imageIndex: 1, altitude: 45, azimuth: 180)]
        try DynamicHEIC.writeSolar(frameCount: 2, entries: entries, lightIndex: 1, darkIndex: 0, to: url) {
            solidImage($0 == 0 ? 0.1 : 0.9)
        }
        let info = try #require(DynamicHEIC.read(url))
        #expect(info.imageCount == 2)
        let si = try #require(info.solar?["si"] as? [[String: Any]])
        #expect(si.map { $0["i"] as? Int } == [0, 1])
        #expect(si.map { $0["a"] as? Double } == [-30, 45])
        #expect(si.map { $0["z"] as? Double } == [0, 180])
        #expect((info.solar?["ap"] as? [String: Int]) == ["l": 1, "d": 0])
        #expect(info.h24Raw == nil && info.aprRaw == nil)
    }

    @Test func rejectsBadIndices() {
        let url = tempURL("bad.heic")
        #expect(throws: DynamicHEIC.Error.self) {
            try DynamicHEIC.writeTimeOfDay(images: [solidImage(0.5)],
                                           entries: [DynamicHEIC.TimeEntry(imageIndex: 3, dayFraction: 0)],
                                           lightIndex: 0, darkIndex: 0, to: url)
        }
    }
}
