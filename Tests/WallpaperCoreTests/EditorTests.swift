import Foundation
import ImageIO
import Metal
import Testing
@testable import WallpaperCore

@Suite("Randomizer")
struct RandomizerTests {
    @Test func sameSeedSameResult() {
        var a = SeededGenerator(seed: 42), b = SeededGenerator(seed: 42)
        #expect(Randomizer.palette(using: &a) == Randomizer.palette(using: &b))
    }

    @Test(arguments: 0..<40)
    func palettesRunDarkToLightAndStayInGamut(seed: Int) {
        var rng = SeededGenerator(seed: UInt64(seed))
        let p = Randomizer.palette(using: &rng)
        #expect(EditorModel.colorRange.contains(p.colors.count))
        let L = p.colors.map { OKLab($0).L }
        #expect(zip(L, L.dropFirst()).allSatisfy { $0 < $1 }, "lightness must increase: \(L)")
        #expect(L.last! - L.first! > 0.4, "needs a real lightness spread")
        for c in p.colors {
            #expect((0...1).contains(c.red) && (0...1).contains(c.green) && (0...1).contains(c.blue))
        }
    }

    @Test func kindsChangeOnlyWhatTheySay() {
        var rng = SeededGenerator(seed: 7)
        let look = Look(palette: .aurora, seed: 5)
        let colors = Randomizer.apply(.colors, to: look, using: &rng)
        #expect(colors.palette != look.palette && colors.parameters == look.parameters && colors.seed == look.seed)
        let movement = Randomizer.apply(.movement, to: look, using: &rng)
        #expect(movement.palette == look.palette && movement.parameters != look.parameters)
        #expect(movement.parameters.grain == look.parameters.grain)
    }
}

@Suite("Editor model", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct EditorModelTests {
    let model: EditorModel

    init() throws {
        let defaults = UserDefaults(suiteName: "dw-tests-\(UUID().uuidString)")!
        model = EditorModel(context: try RenderContext(), look: Look(palette: .aurora), randomSeed: 1, defaults: defaults)
    }

    @Test func sliderDragIsOneUndoStep() {
        for v in stride(from: 0.5, through: 2.0, by: 0.25) {
            model.update(commit: false) { $0.parameters.speed = v }
        }
        model.commit()
        #expect(model.look.parameters.speed == 2.0)
        model.undo()
        #expect(model.look.parameters.speed == 1.0)
        #expect(!model.canUndo)
        model.redo()
        #expect(model.look.parameters.speed == 2.0)
    }

    @Test func undoNeverRewindsTheScrubber() {
        model.scrub(to: 100)
        model.selectPalette(.ember)
        model.scrub(to: 300)
        model.undo()
        #expect(model.look.palette == .aurora)
        #expect(model.look.time == 300)
        #expect(!model.canUndo)                    // scrubbing itself is not recorded
    }

    @Test func seedIsUndoable() {
        model.update { $0.seed = 99 }
        model.undo()
        #expect(model.look.seed == 0)
        #expect(model.scene.clock.phase == model.look.phase)
    }

    @Test func newEditClearsRedo() {
        model.selectPalette(.ocean)
        model.undo()
        model.selectPalette(.forest)
        #expect(!model.canRedo)
    }

    @Test func editingColorsMakesCustomAndRespectsLimits() {
        model.setColor(RGBColor(red: 2, green: -1, blue: 0.5), at: 1)
        #expect(model.look.palette.id == "custom")
        #expect(model.look.palette.colors[1] == RGBColor(red: 1, green: 0, blue: 0.5))   // clamped
        while model.look.palette.colors.count < 8 { model.addColor() }
        model.addColor()
        #expect(model.look.palette.colors.count == 8)
        while model.look.palette.colors.count > 2 { model.removeColor(at: 0) }
        model.removeColor(at: 0)
        #expect(model.look.palette.colors.count == 2)
    }

    @Test func colorPickerChangesCoalesceIntoOneStep() async throws {
        model.setColor(RGBColor(red: 0.1, green: 0.2, blue: 0.3), at: 0)
        model.setColor(RGBColor(red: 0.2, green: 0.3, blue: 0.4), at: 0)
        model.setColor(RGBColor(red: 0.3, green: 0.4, blue: 0.5), at: 0)
        try await Task.sleep(for: .milliseconds(900))
        model.undo()
        #expect(model.look.palette == .aurora)
    }

    @Test func moveColor() {
        let original = model.look.palette.colors
        model.moveColor(from: 0, to: 2)
        #expect(model.look.palette.colors[2] == original[0])
        #expect(model.look.palette.colors[0] == original[1])
    }

    @Test func pausedEditsApplyInstantlyAndRequestRedraw() {
        model.isPlaying = false
        let before = model.redrawCount
        model.selectPalette(.ember)
        #expect(model.redrawCount > before)
        #expect(!model.scene.transition.isActive)           // no crossfade while paused
        model.update { $0.parameters.brightness = 0.5 }
        #expect(model.scene.parameters.brightness == 0.5)   // no easing while paused
    }

    @Test func exportCapturesTheCurrentMomentOfThePreview() throws {
        // Advance the preview clock as if it had been playing, then export a still.
        model.scene.advance(to: 0)
        for i in 1...40 { model.scene.advance(to: Double(i) * 0.2) }   // ~8 s of animation
        var settings = ExportSettings()
        settings.kind = .stillPNG
        settings.size = ExportSize(width: 160, height: 90)
        settings.directoryPath = FileManager.default.temporaryDirectory.appendingPathComponent("dw-ed-\(UUID())").path
        defer { try? FileManager.default.removeItem(at: settings.directory) }

        let url = try #require(try model.export(settings).first)
        #expect(abs(model.look.time - 8) < 0.01)

        // Same moment rendered offscreen must match the exported file.
        let renderer = try FrameRenderer(context: model.context, size: settings.size!)
        let expected = try renderer.render(WallpaperExporter(context: model.context).scene(for: model.look),
                                           seed: model.look.grainSeed)
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let written = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        func bytes(_ i: CGImage) -> [UInt8] {
            var buf = [UInt8](repeating: 0, count: i.width * i.height * 4)
            let ctx = CGContext(data: &buf, width: i.width, height: i.height, bitsPerComponent: 8, bytesPerRow: i.width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(i, in: CGRect(x: 0, y: 0, width: i.width, height: i.height))
            return buf
        }
        #expect(bytes(written) == bytes(expected))
    }

    // MARK: Undo through a real UndoManager (what the Edit menu uses)

    private func managedModel() throws -> (EditorModel, UndoManager) {
        let um = UndoManager()
        um.groupsByEvent = false
        model.undoManager = um
        return (model, um)
    }

    @Test func undoManagerUndoesAndRedoesAnEdit() throws {
        let (m, um) = try managedModel()
        um.beginUndoGrouping(); m.selectPalette(.ember); um.endUndoGrouping()
        #expect(um.canUndo)
        um.undo()
        #expect(m.look.palette == .aurora)
        #expect(um.canRedo)
        um.redo()
        #expect(m.look.palette == .ember)
        um.undo()
        #expect(m.look.palette == .aurora)
    }

    @Test func undoRightAfterAColorPickWorks() throws {
        let (m, um) = try managedModel()
        um.beginUndoGrouping()
        m.setColor(RGBColor(red: 0.9, green: 0.1, blue: 0.1), at: 0)
        m.setColor(RGBColor(red: 0.8, green: 0.2, blue: 0.1), at: 0)
        um.endUndoGrouping()
        um.undo()                                    // immediately: no 0.6 s wait
        #expect(m.look.palette == .aurora)
        #expect(um.canRedo)
        um.redo()
        #expect(m.look.palette.colors[0] == RGBColor(red: 0.8, green: 0.2, blue: 0.1))
    }

    @Test func colorBurstAfterAnotherEditUndoesOnlyTheBurst() throws {
        let (m, um) = try managedModel()
        um.beginUndoGrouping(); m.update { $0.parameters.grain = 0.8 }; um.endUndoGrouping()
        um.beginUndoGrouping(); m.setColor(RGBColor(red: 0.5, green: 0.5, blue: 0.5), at: 2); um.endUndoGrouping()
        um.undo()
        #expect(m.look.palette == .aurora)
        #expect(m.look.parameters.grain == 0.8)
        um.undo()
        #expect(m.look.parameters.grain == RenderParameters().grain)
    }

    @Test func playbackMovesThePlayheadNotTheLook() {
        let before = model.look
        model.scene.advance(to: 0)
        for i in 1...10 { model.scene.advance(to: Double(i) * 0.2) }
        model.syncTimeFromScene()
        #expect(model.playhead > 1.9)
        #expect(model.look == before)               // inspector isn't invalidated by playback
        model.isPlaying = false                     // pausing folds the time into the look
        #expect(abs(model.look.time - model.playhead) < 1e-9)
    }

    // MARK: Export names

    @Test func suggestedNamesSayWhatTheExportIs() {
        #expect(model.suggestedExportName(for: .sunPosition) == "Aurora Dynamic")
        #expect(model.suggestedExportName(for: .timeOfDay) == "Aurora Dynamic (Clock)")
        #expect(model.suggestedExportName(for: .lightDark) == "Aurora Light-Dark")
        #expect(model.suggestedExportName(for: .stillPNG) == "Aurora")
        model.setColor(RGBColor(red: 0.2, green: 0.3, blue: 0.4), at: 0)
        let date = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: 11, day: 20, hour: 12).date!
        #expect(model.suggestedExportName(for: .sunPosition, date: date) == "Custom 2026-11-20 Dynamic")
    }

    @Test func exportUsesTheGivenNameOrFallsBack() throws {
        var settings = ExportSettings()
        settings.kind = .stillPNG
        settings.size = ExportSize(width: 64, height: 36)
        settings.directoryPath = FileManager.default.temporaryDirectory.appendingPathComponent("dw-name-\(UUID())").path
        defer { try? FileManager.default.removeItem(at: settings.directory) }
        #expect(try model.export(settings, name: "  Morning Haze ").first?.lastPathComponent == "Morning Haze.png")
        #expect(try model.export(settings, name: "Morning Haze").first?.lastPathComponent == "Morning Haze 2.png")
        #expect(try model.export(settings, name: "   ").first?.lastPathComponent == "Aurora.png")
    }

    @Test func exportSettingsPersist() {
        let defaults = UserDefaults(suiteName: "dw-tests-\(UUID().uuidString)")!
        var s = ExportSettings()
        s.kind = .lightDark
        s.frames = 16
        s.size = ExportSize(width: 3024, height: 1964)
        s.save(to: defaults)
        #expect(ExportSettings.load(from: defaults) == s)
    }
}
