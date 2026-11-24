import Foundation
import Metal
import Testing
@testable import WallpaperCore

@Suite("Built-in presets")
struct BuiltInPresetTests {
    @Test func libraryCoversMoodsSeasonsAndVibes() {
        let byCategory = Dictionary(grouping: Preset.builtIns, by: \.category)
        #expect((byCategory[.mood]?.count ?? 0) >= 3)
        #expect(byCategory[.season]?.map(\.name) == ["Winter", "Spring", "Summer", "Autumn"])
        #expect(byCategory[.vibe]?.count == 11)
        #expect(byCategory[.vibe]?.prefix(6).map(\.name) == ["Aurora", "Sunset", "Ocean", "Ember", "Forest", "Monochrome"])
        #expect(byCategory[.mine] == nil)
        #expect(Set(Preset.builtIns.map(\.id)).count == Preset.builtIns.count)
        #expect(Set(Preset.builtIns.map(\.name)).count == Preset.builtIns.count)
    }

    @Test func idsAreStableAcrossLaunches() {
        #expect(Preset.builtIns.map(\.id) == Preset.builtIns.map(\.id))
        #expect(Preset.builtIn(id: Preset.seasons[0].id)?.name == "Winter")
    }

    /// The shader maps its noise field onto the palette in order, so every palette, keyframe
    /// palettes included, must run dark → light.
    @Test(arguments: Preset.builtIns)
    func everyPaletteRunsDarkToLight(preset: Preset) {
        let palettes = [preset.look.palette] + preset.look.dayArc.keyframes.compactMap(\.palette)
        for p in palettes {
            let L = p.colors.map { OKLab($0).L }
            #expect(zip(L, L.dropFirst()).allSatisfy { $0 < $1 }, "\(preset.name) / \(p.name): \(L.map { String(format: "%.2f", $0) })")
        }
    }

    @Test(arguments: Preset.seasons)
    func seasonNoonUsesTheBasePalette(preset: Preset) {
        let noon = preset.look.dayArc.keyframes.first { $0.dayFraction == 0.5 }
        #expect(noon != nil && noon?.palette == nil)
        #expect(preset.look.dayArc.hasPaletteOverrides)
    }

    @Test(arguments: Preset.builtIns)
    func roundTripsThroughTheFileFormat(preset: Preset) throws {
        let back = try Preset.decode(fileData: try preset.fileData())
        #expect(back == preset)
    }
}

@Suite("Preset files (untrusted input)")
struct PresetFileTests {
    @Test func missingFieldsFallBackToDefaults() throws {
        let json = #"{"formatVersion": 1, "name": "Sparse", "look": {"palette": {"colors": [{"red": 0.1}, {"green": 0.9}]}}}"#
        let p = try Preset.decode(fileData: Data(json.utf8))
        #expect(p.name == "Sparse")
        #expect(p.category == .mine)
        #expect(p.look.parameters == RenderParameters())
        #expect(p.look.dayArc == .standard)
        #expect(p.look.palette.colors == [RGBColor(red: 0.1, green: 0, blue: 0), RGBColor(red: 0, green: 0.9, blue: 0)])
    }

    @Test func valuesAreClampedAndBounded() throws {
        let manyKeys = (0..<500).map { #"{"dayFraction": \#(Double($0) / 500), "brightness": 99}"# }.joined(separator: ",")
        let manyColors = (0..<20).map { _ in #"{"red": 5, "green": -3, "blue": 0.5}"# }.joined(separator: ",")
        let json = """
        {"formatVersion": 1, "name": "\(String(repeating: "x", count: 500))",
         "look": {"parameters": {"speed": 1000, "brightness": -5},
                  "palette": {"colors": [\(manyColors)]},
                  "dayArc": {"keyframes": [\(manyKeys)], "motion": 1e12},
                  "time": -50}}
        """
        let p = try Preset.decode(fileData: Data(json.utf8))
        #expect(p.name.count == 80)
        #expect(p.look.parameters.speed == 4 && p.look.parameters.brightness == 0.2)
        #expect(p.look.palette.colors.count == 8)
        #expect(p.look.palette.colors[0] == RGBColor(red: 1, green: 0, blue: 0.5))
        #expect(p.look.dayArc.keyframes.count == DayArc.maxKeyframes)
        #expect(p.look.dayArc.keyframes.allSatisfy { $0.brightness == 2 })
        #expect(p.look.dayArc.motion == DayArc.motionRange.upperBound)
        #expect(p.look.time == 0)
    }

    @Test func newerFormatIsRefusedWithAClearError() {
        #expect(throws: Preset.FileError.unsupportedVersion(99)) {
            try Preset.decode(fileData: Data(#"{"formatVersion": 99, "name": "Future"}"#.utf8))
        }
    }

    @Test func garbageAndOversizedFilesAreRejected() {
        #expect(throws: Preset.FileError.notAPreset) { try Preset.decode(fileData: Data("not json".utf8)) }
        #expect(throws: Preset.FileError.notAPreset) { try Preset.decode(fileData: Data(#"{"name": "no version"}"#.utf8)) }
        #expect(throws: Preset.FileError.self) { try Preset.decode(fileData: Data(count: Preset.maxFileSize + 1)) }
    }

    @Test func oldFilesWithoutNewFieldsStillDecodeLooks() throws {
        // A Look written before dayArc existed.
        let json = #"{"palette": {"id": "ocean", "name": "Ocean", "colors": [{"red":0,"green":0,"blue":0.2},{"red":0.4,"green":0.8,"blue":0.8}]}, "seed": 4}"#
        let look = try JSONDecoder().decode(Look.self, from: Data(json.utf8))
        #expect(look.seed == 4 && look.dayArc == .standard && look.time == 0)
    }
}

@Suite("Preset store")
@MainActor
struct PresetStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dw-presets-\(UUID().uuidString)")

    private func store() -> PresetStore { PresetStore(directory: dir, deletesToTrash: false) }

    @Test func saveRenameDuplicateDeleteAndReload() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = store()
        let p = Preset(name: "Mine", category: .mine, look: Look(palette: .forest, seed: 3))
        try s.save(p)
        try s.rename(id: p.id, to: "  Renamed  ")
        let copy = try s.duplicate(s.preset(id: p.id)!)
        #expect(copy.name == "Renamed Copy" && copy.id != p.id && copy.look == p.look)
        let fromBuiltIn = try s.duplicate(Preset.seasons[0])
        #expect(fromBuiltIn.name == "Winter" && fromBuiltIn.category == .mine)

        let reloaded = store()
        #expect(reloaded.presets.map(\.name) == ["Renamed", "Renamed Copy", "Winter"])
        // Files are named by UUID; renaming didn't create or rename files.
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(files.count == 3 && files.contains("\(p.id.uuidString).gloamingpreset"))

        try reloaded.delete(id: p.id)
        #expect(store().presets.count == 2)
    }

    @Test func corruptFilesAreSkippedAndReportedNotDeleted() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bad = dir.appendingPathComponent("broken.gloamingpreset")
        try Data("{oops".utf8).write(to: bad)
        try store().save(Preset(name: "Good", category: .mine, look: Look(palette: .ocean)))
        let s = store()
        #expect(s.presets.map(\.name) == ["Good"])
        #expect(s.loadErrors.count == 1)
        #expect(FileManager.default.fileExists(atPath: bad.path))
    }

    @Test func exportThenImportGetsANewIdentityOnConflict() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let s = store()
        let p = Preset(name: "Shared", category: .mine, look: Look(palette: .ember, seed: 9))
        try s.save(p)
        let file = dir.appendingPathComponent("../shared-\(UUID()).gloamingpreset").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: file) }
        try s.exportPreset(p, to: file)
        let imported = try s.importPreset(from: file)
        #expect(imported.id != p.id)                       // same ID existed → new one
        #expect(imported.look == p.look && imported.name == "Shared")
        #expect(s.presets.count == 2)

        let builtInFile = dir.appendingPathComponent("../winter-\(UUID()).gloamingpreset").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: builtInFile) }
        try s.exportPreset(Preset.seasons[0], to: builtInFile)
        let w = try s.importPreset(from: builtInFile)
        #expect(w.id != Preset.seasons[0].id && w.category == .mine)
    }

    @Test func inMemoryStoreTouchesNoFiles() throws {
        let s = PresetStore(directory: nil)
        try s.save(Preset(name: "Temp", category: .mine, look: Look(palette: .aurora)))
        #expect(s.presets.count == 1)
    }
}

@Suite("Presets in the editor", .enabled(if: MTLCreateSystemDefaultDevice() != nil))
@MainActor
struct EditorPresetTests {
    let model: EditorModel
    let winter = Preset.seasons[0]
    let calm = Preset.moods[0]

    init() throws {
        let defaults = UserDefaults(suiteName: "dw-tests-\(UUID().uuidString)")!
        model = EditorModel(context: try RenderContext(), look: Preset.vibes[0].look, randomSeed: 1, defaults: defaults,
                            presetStore: PresetStore(directory: nil), presetID: Preset.vibes[0].id)
    }

    @Test func applyingAPresetSetsTheWholeLookAndIsCurrent() {
        model.apply(winter)
        #expect(model.look == winter.look)
        #expect(model.currentPreset == winter && !model.isModified)
        #expect(model.scene.palette == winter.look.palette)
    }

    @Test func runOfPresetSelectionsIsOneUndoStep() {
        let um = UndoManager(); um.groupsByEvent = false; model.undoManager = um
        um.beginUndoGrouping()
        model.apply(winter); model.apply(calm); model.apply(Preset.seasons[2])
        um.endUndoGrouping()
        um.undo()
        #expect(model.look.palette == Palette.aurora)
        #expect(model.currentPresetID == Preset.vibes[0].id)     // undo restores which preset is current
    }

    @Test func editsMarkThePresetModified() {
        model.apply(calm)
        model.update { $0.parameters.grain = 0.9 }
        #expect(model.isModified)
        #expect(model.suggestedExportName(for: .sunPosition) == "Calm Dynamic")
    }

    @Test func colorEditsReplaceTheSeasonsDayPalettes() {
        model.apply(winter)
        #expect(model.look.dayArc.hasPaletteOverrides)
        model.setColor(RGBColor(red: 0.9, green: 0.4, blue: 0.2), at: 3)
        #expect(!model.look.dayArc.hasPaletteOverrides)
        // Brightness curve kept; every hour now uses the user's colors.
        #expect(model.look.dayArc.keyframes.map(\.brightness) == winter.look.dayArc.keyframes.map(\.brightness))
        let midnight = model.look.dayArc.sample(at: 0, base: model.look.palette)
        #expect(midnight.ramp == model.look.palette.ramp(count: PaletteTransition.rampSize))
    }

    @Test func parameterEditsKeepTheSeasonsDayPalettes() {
        model.apply(winter)
        model.update { $0.parameters.speed = 2 }
        #expect(model.look.dayArc.hasPaletteOverrides)
    }

    @Test func saveAsNewThenSaveChanges() throws {
        model.apply(winter)
        model.update { $0.parameters.complexity = 0.9 }
        #expect(model.suggestedPresetName() == "My Winter")
        let saved = try model.saveAsNewPreset(named: "Frost")
        #expect(model.currentPreset == saved && !model.isModified && saved.category == .mine)
        model.update { $0.parameters.grain = 0.6 }
        #expect(model.canSaveChangesToCurrentPreset)
        try model.saveChangesToCurrentPreset()
        #expect(model.presetStore.preset(id: saved.id)?.look.parameters.grain == 0.6)
        #expect(!model.isModified)
    }

    @Test func builtInsCannotBeOverwrittenAndDeletingCurrentClearsIt() throws {
        model.apply(calm)
        model.update { $0.parameters.grain = 0.9 }
        #expect(!model.canSaveChangesToCurrentPreset)
        try model.saveChangesToCurrentPreset()                 // no-op for built-ins
        #expect(Preset.builtIn(id: calm.id)?.look == calm.look)
        try model.deletePreset(calm)                           // refused for built-ins
        #expect(model.currentPresetID == calm.id)

        let mine = try model.saveAsNewPreset(named: "Temp")
        try model.deletePreset(mine)
        #expect(model.currentPresetID == nil && model.presetStore.presets.isEmpty)
    }

    @Test func dayStripThumbnailsMatchTheExportScenes() throws {
        let thumb = try #require(model.thumbnails.image(for: winter.look, dayFraction: 0))
        let renderer = try FrameRenderer(context: model.context, size: ThumbnailRenderer.size)
        let expected = try renderer.render(WallpaperExporter(context: model.context).scene(for: winter.look, dayFraction: 0),
                                           seed: winter.look.grainSeed)
        #expect(thumb.dataProvider?.data as Data? == expected.dataProvider?.data as Data?)
    }
}

@Suite("Rename compatibility")
@MainActor
struct RenameCompatibilityTests {
    @Test func legacyPresetFilesStillLoadAndImport() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gl-legacy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let old = Preset(name: "Old Format", category: .mine, look: Look(palette: .ember))
        try old.fileData().write(to: dir.appendingPathComponent("\(old.id.uuidString).dwpreset"))
        let store = PresetStore(directory: dir, deletesToTrash: false)
        #expect(store.presets.map(\.name) == ["Old Format"])
    }

    @Test func migratesTheFormerPresetsFolderOnce() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("gl-migrate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let legacy = base.appendingPathComponent("DynamicWallpaper/Presets")
        let current = base.appendingPathComponent("Gloaming/Presets")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: legacy.appendingPathComponent("x.dwpreset"))
        #expect(PresetStore.migrateLegacyDirectory(to: current, from: legacy))
        #expect(FileManager.default.fileExists(atPath: current.appendingPathComponent("x.dwpreset").path))
        #expect(!PresetStore.migrateLegacyDirectory(to: current, from: legacy))   // nothing left to move
    }
}
