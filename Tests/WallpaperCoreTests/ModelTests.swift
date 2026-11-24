import Foundation
import Testing
@testable import WallpaperCore

@Suite("Models")
struct ModelTests {
    @Test func hexRoundTrip() throws {
        let c = try #require(RGBColor(hex: "#1FA39A"))
        #expect(c.hexString == "#1FA39A")
        #expect(RGBColor(hex: "1fa39a") == c)
        #expect(RGBColor(hex: "#12345") == nil)
        #expect(RGBColor(hex: "zzzzzz") == nil)
    }

    @Test func paletteCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(Palette.builtIns)
        let decoded = try JSONDecoder().decode([Palette].self, from: data)
        #expect(decoded == Palette.builtIns)
    }

    @Test func builtInsMatchSpec() {
        #expect(Palette.builtIns.map(\.id) == ["aurora", "sunset", "ocean", "ember", "forest", "monochrome"])
        #expect(Palette.builtIns.allSatisfy { $0.colors.count == 5 })
        #expect(Palette.builtIn(id: "SUNSET") == .sunset)
        #expect(Palette.builtIn(id: "nope") == nil)
    }

    @Test(arguments: Palette.builtIns.flatMap(\.colors))
    func oklabRoundTrip(color: RGBColor) {
        let back = OKLab(color).rgb
        #expect(abs(back.red - color.red) < 1e-6)
        #expect(abs(back.green - color.green) < 1e-6)
        #expect(abs(back.blue - color.blue) < 1e-6)
    }

    @Test func oklabKnownValues() {
        let white = OKLab(RGBColor(red: 1, green: 1, blue: 1))
        #expect(abs(white.L - 1) < 1e-4 && abs(white.a) < 1e-4 && abs(white.b) < 1e-4)
        let black = OKLab(RGBColor(red: 0, green: 0, blue: 0))
        #expect(abs(black.L) < 1e-9)
    }

    @Test func rampEndpointsAreFirstAndLastColors() {
        let p = Palette.sunset
        let ramp = p.ramp(count: 256)
        #expect(ramp.count == 256)
        #expect(ramp.first == OKLab(p.colors.first!))
        #expect(ramp.last == OKLab(p.colors.last!))
    }

    @Test(arguments: [0, 1, 2, 7])
    func rampHandlesAnyColorCount(count: Int) {
        let colors = (0..<count).map { RGBColor(red: Double($0) / 7, green: 0.3, blue: 0.6) }
        let ramp = Palette(id: "t", name: "t", colors: colors).ramp(count: 16)
        #expect(ramp.count == 16)
        if count <= 1 { #expect(Set(ramp).count == 1) }
        #expect(ramp.allSatisfy { $0.L.isFinite && $0.a.isFinite && $0.b.isFinite })
    }

    @Test func parametersClamp() {
        var p = RenderParameters()
        p.speed = 99; p.complexity = -1; p.brightness = 0; p.saturation = 5
        let c = p.clamped()
        #expect(c.speed == 4 && c.complexity == 0 && c.brightness == 0.2 && c.saturation == 2)
    }

    @Test func parametersCodable() throws {
        var p = RenderParameters()
        p.grain = 0.7
        let back = try JSONDecoder().decode(RenderParameters.self, from: JSONEncoder().encode(p))
        #expect(back == p)
    }
}
