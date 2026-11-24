import Foundation
import Observation

/// State and logic behind the editor window, kept free of SwiftUI so it can be unit-tested.
///
/// - `look` is the design being edited. Every change is pushed into the preview `scene`:
///   palettes crossfade (short for colour edits, longer for switching presets), parameters
///   ease in, and seed or scrubber changes move the animation phase.
/// - While paused, changes apply instantly (crossfades only progress while playing), and
///   `redrawCount` increments so the preview draws a frame.
/// - Undo: one step per gesture (`commit()` at the end of a drag, or shortly after the last
///   colour-picker change). The scrubber position is not part of history, and undo never
///   rewinds playback. The seed is part of history.
@MainActor
@Observable
public final class EditorModel {
    public let context: RenderContext
    public let scene: SceneState

    public private(set) var look: Look
    public var isPlaying = true {
        didSet {
            guard isPlaying != oldValue else { return }
            if !isPlaying { captureTime() }
            redrawCount &+= 1
        }
    }
    /// Current position of the animation for the scrubber, refreshed while playing. Kept
    /// separate from `look.time` so playback doesn't rewrite the whole look 10× a second;
    /// it's folded into the look on edits, pause and export.
    public private(set) var playhead: Double
    /// Increments whenever the paused preview needs to draw.
    public private(set) var redrawCount = 0
    public var exportSettings: ExportSettings { didSet { exportSettings.save(to: defaults) } }

    /// The preset the current look came from (built-in or user), if any.
    public private(set) var currentPresetID: UUID?
    public let presetStore: PresetStore
    @ObservationIgnored public let thumbnails: ThumbnailRenderer

    /// Scrubber range in seconds of animation at speed 1.
    public nonisolated static let timeRange: ClosedRange<Double> = 0...1800

    @ObservationIgnored public weak var undoManager: UndoManager?
    private struct Snapshot { var look: Look; var presetID: UUID? }
    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var redoStack: [Snapshot] = []
    @ObservationIgnored private var committed: Look
    @ObservationIgnored private var committedPresetID: UUID?
    /// Crossfade override for the next palette change (e.g. switching presets).
    @ObservationIgnored private var nextPaletteFade: Double?
    @ObservationIgnored private var pendingCommit: Task<Void, Never>?
    /// True while a run of colour-picker changes is grouped into one already-registered step.
    @ObservationIgnored private var burstOpen = false
    @ObservationIgnored private var rng: SeededGenerator
    @ObservationIgnored private let defaults: UserDefaults

    public init(context: RenderContext, look: Look = Look(palette: .aurora), randomSeed: UInt64 = UInt64.random(in: 0...UInt64.max),
                defaults: UserDefaults = .standard, presetStore: PresetStore? = nil, presetID: UUID? = nil) {
        self.context = context
        self.presetStore = presetStore ?? PresetStore(directory: nil)
        self.thumbnails = ThumbnailRenderer(context: context)
        self.currentPresetID = presetID
        self.committedPresetID = presetID
        self.look = look
        self.committed = look
        self.playhead = look.time
        self.rng = SeededGenerator(seed: randomSeed)
        self.defaults = defaults
        self.exportSettings = ExportSettings.load(from: defaults)
        scene = SceneState(context: context, palette: look.palette, parameters: look.parameters, phase: look.phase)
    }

    public var canUndo: Bool { !undoStack.isEmpty || !Self.sameEdit(look, committed) }

    private var committedSnapshot: Snapshot { Snapshot(look: committed, presetID: committedPresetID) }
    private var hasUncommittedChanges: Bool { !Self.sameEdit(look, committed) || currentPresetID != committedPresetID }
    public var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Editing

    /// Applies a change to the look. `commit: false` for continuous gestures (slider drags);
    /// call `commit()` when the gesture ends.
    public func update(commit shouldCommit: Bool = true, _ change: (inout Look) -> Void) {
        captureTime()
        var new = look
        change(&new)
        new.parameters = new.parameters.clamped()
        set(new, userTime: new.time != look.time)
        if shouldCommit { commit() }
    }

    /// Records the current look as one undo step (no-op if nothing changed since the last).
    public func commit() {
        pendingCommit?.cancel()
        pendingCommit = nil
        if burstOpen {
            // The step was registered when the burst began; just fold in the final state.
            burstOpen = false
            committed = look
            committedPresetID = currentPresetID
            return
        }
        guard hasUncommittedChanges else { return }
        undoStack.append(committedSnapshot)
        redoStack.removeAll()
        committed = look
        committedPresetID = currentPresetID
        registerWithUndoManager(redo: false)
    }

    /// Groups a run of changes from a control without an "editing ended" callback (ColorPicker)
    /// into one undo step. The step is registered on the *first* change, so ⌘Z works right
    /// away; later changes fold into it until `delay` passes without another change.
    public func beginOrExtendBurst(after delay: Duration = .milliseconds(600)) {
        if !burstOpen {
            commit()                                   // settle any other pending gesture first
            undoStack.append(committedSnapshot)
            redoStack.removeAll()
            registerWithUndoManager(redo: false)
            burstOpen = true
        }
        commitSoon(after: delay)
    }

    /// Commits after `delay` seconds without further changes.
    public func commitSoon(after delay: Duration = .milliseconds(600)) {
        pendingCommit?.cancel()
        pendingCommit = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.commit()
        }
    }

    public func undo() {
        commit()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(committedSnapshot)
        restore(previous)
        registerWithUndoManager(redo: true)
    }

    public func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(committedSnapshot)
        restore(next)
        registerWithUndoManager(redo: false)
    }

    // MARK: - Palette helpers

    public nonisolated static let colorRange = 2...8

    public func selectPalette(_ palette: Palette) {
        update { $0.palette = palette; Self.usePaletteAllDay(&$0) }
    }

    /// After the user changes colours, the day arc's own palettes (a season preset's dawn,
    /// dusk and night colours) are dropped so the whole Dynamic export uses the user's colours.
    /// The brightness/saturation curve is kept.
    static func usePaletteAllDay(_ l: inout Look) {
        if l.dayArc.hasPaletteOverrides { l.dayArc = l.dayArc.withoutPaletteOverrides }
    }

    /// Changes one colour. Editing turns any built-in palette into "Custom".
    public func setColor(_ color: RGBColor, at index: Int) {
        guard look.palette.colors.indices.contains(index) else { return }
        beginOrExtendBurst()
        update(commit: false) { l in
            l.palette = Palette(id: "custom", name: "Custom", colors: l.palette.colors)
            l.palette.colors[index] = Self.clamped(color)
            Self.usePaletteAllDay(&l)
        }
    }

    public func addColor() {
        guard look.palette.colors.count < Self.colorRange.upperBound else { return }
        update { l in
            var colors = l.palette.colors
            // Insert between the two lightest stops, keeping dark → light order.
            let last = colors.last.map(OKLab.init) ?? OKLab(L: 0.8, a: 0, b: 0)
            let prev = colors.dropLast().last.map(OKLab.init) ?? last
            colors.insert(OKLab.mix(prev, last, 0.5).rgb, at: max(colors.count - 1, 0))
            l.palette = Palette(id: "custom", name: "Custom", colors: colors)
            Self.usePaletteAllDay(&l)
        }
    }

    public func removeColor(at index: Int) {
        guard look.palette.colors.count > Self.colorRange.lowerBound,
              look.palette.colors.indices.contains(index) else { return }
        update { l in
            var colors = l.palette.colors
            colors.remove(at: index)
            l.palette = Palette(id: "custom", name: "Custom", colors: colors)
            Self.usePaletteAllDay(&l)
        }
    }

    public func moveColor(from source: Int, to destination: Int) {
        let colors = look.palette.colors
        guard colors.indices.contains(source), colors.indices.contains(destination), source != destination else { return }
        update { l in
            var c = l.palette.colors
            c.insert(c.remove(at: source), at: destination)
            l.palette = Palette(id: "custom", name: "Custom", colors: c)
            Self.usePaletteAllDay(&l)
        }
    }

    // MARK: - Randomize, time

    public func randomize(_ kind: RandomizeKind) {
        var new = Randomizer.apply(kind, to: look, using: &rng)
        if new.palette != look.palette { Self.usePaletteAllDay(&new) }
        update { $0 = new }
    }

    /// Sets the scrubber position (not recorded in undo history).
    public func scrub(to time: Double) {
        var new = look
        new.time = min(max(time, Self.timeRange.lowerBound), Self.timeRange.upperBound)
        set(new, userTime: true)
        committed.time = new.time
        playhead = new.time
    }

    /// The animation's current position according to the preview clock.
    private var sceneTime: Double { scene.clock.phase - Double(look.seed) * Look.seedSpacing }

    /// Refreshes `playhead` from the preview clock (called ~10× a second while playing).
    public func syncTimeFromScene() {
        let t = sceneTime
        if abs(t - playhead) > 1e-6 { playhead = t }
    }

    /// Folds the preview clock into `look.time` (before edits, on pause and before export).
    func captureTime() {
        let t = sceneTime
        playhead = t
        guard abs(t - look.time) > 1e-6 else { return }
        look.time = t
        committed.time = t
    }

    // MARK: - Export

    /// Default file name for an export: the palette name (or "Custom <date>" for an edited
    /// palette) plus a suffix saying what kind of wallpaper it is.
    public func suggestedExportName(for kind: ExportSettings.Kind, date: Date = Date()) -> String {
        let base: String
        if let preset = currentPreset {
            base = preset.name
        } else if Palette.builtIn(id: look.palette.id) != nil {
            base = look.palette.name
        } else {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            base = "\(look.palette.name) \(f.string(from: date))"
        }
        switch kind {
        case .sunPosition: return "\(base) Dynamic"
        case .timeOfDay: return "\(base) Dynamic (Clock)"
        case .lightDark: return "\(base) Light-Dark"
        case .stillPNG, .stillHEIC, .variations: return base
        }
    }

    /// Exports the current look (including the preview's current moment) and returns the
    /// files written. `name` is used as given (blank → the suggested name); a number is
    /// appended only if a file with that name already exists.
    public func export(_ settings: ExportSettings, name: String? = nil, currentDisplaySize: ExportSize? = nil) throws -> [URL] {
        captureTime()
        let exporter = WallpaperExporter(context: context)
        guard let size = settings.size ?? currentDisplaySize else { throw FrameRenderer.Error.invalidSize(ExportSize(width: 0, height: 0)) }
        let dir = settings.directory
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let name = trimmed.isEmpty ? suggestedExportName(for: settings.kind) : trimmed
        switch settings.kind {
        case .sunPosition:
            return [try exporter.exportSunPosition(look, frameCount: settings.frames, size: size, to: dir, name: name)]
        case .timeOfDay:
            return [try exporter.exportTimeOfDay(look, frameCount: settings.frames, size: size, to: dir, name: name)]
        case .lightDark:
            return [try exporter.exportAppearance(look, size: size, to: dir, name: name)]
        case .stillPNG:
            return [try exporter.exportStill(look, size: size, format: .png, to: dir, name: name)]
        case .stillHEIC:
            return [try exporter.exportStill(look, size: size, format: .heic, to: dir, name: name)]
        case .variations:
            return try exporter.exportVariations(look, count: settings.variations, size: size, format: .heic, to: dir, name: name)
        }
    }

    // MARK: - Presets

    public var currentPreset: Preset? {
        guard let id = currentPresetID else { return nil }
        return Preset.builtIn(id: id) ?? presetStore.preset(id: id)
    }

    /// The look differs from the preset it came from (scrubber position ignored).
    public var isModified: Bool {
        guard let p = currentPreset else { return false }
        return !Self.sameEdit(look, p.look)
    }

    /// Applies a preset, crossfading the preview. Applying several in a row (clicking or
    /// arrowing through the sidebar) is one undo step.
    public func apply(_ preset: Preset) {
        guard preset.id != currentPresetID || isModified else { return }
        beginOrExtendBurst(after: .milliseconds(1500))
        nextPaletteFade = 1.5
        update(commit: false) { $0 = preset.look }
        currentPresetID = preset.id
    }

    public func suggestedPresetName() -> String {
        guard let p = currentPreset else { return presetStore.uniqueName("My Look") }
        return presetStore.uniqueName(p.isBuiltIn || isModified ? "My \(p.name)" : p.name)
    }

    /// Saves the current look as a new user preset and makes it current.
    @discardableResult
    public func saveAsNewPreset(named name: String) throws -> Preset {
        captureTime()
        commit()
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let preset = Preset(name: presetStore.uniqueName(trimmed.isEmpty ? suggestedPresetName() : String(trimmed.prefix(80))),
                            category: .mine, look: look)
        try presetStore.save(preset)
        currentPresetID = preset.id
        committedPresetID = preset.id
        return preset
    }

    /// Saves the current look into the current user preset (built-ins can't be changed).
    public func saveChangesToCurrentPreset() throws {
        guard var p = currentPreset, !p.isBuiltIn else { return }
        captureTime()
        commit()
        p.look = look
        try presetStore.save(p)
    }

    public var canSaveChangesToCurrentPreset: Bool { currentPreset.map { !$0.isBuiltIn && isModified } ?? false }

    public func renamePreset(_ preset: Preset, to name: String) throws {
        try presetStore.rename(id: preset.id, to: name)
    }

    @discardableResult
    public func duplicatePreset(_ preset: Preset) throws -> Preset {
        try presetStore.duplicate(preset)
    }

    public func deletePreset(_ preset: Preset) throws {
        guard !preset.isBuiltIn else { return }
        try presetStore.delete(id: preset.id)
        if currentPresetID == preset.id {
            currentPresetID = nil
            committedPresetID = nil
        }
    }

    /// Imports a shared preset file into My Presets and applies it.
    @discardableResult
    public func importPreset(from url: URL) throws -> Preset {
        let p = try presetStore.importPreset(from: url)
        apply(p)
        return p
    }

    // MARK: - Private

    private func set(_ new: Look, userTime: Bool) {
        let old = look
        look = new
        if old.palette != new.palette {
            let duration = !isPlaying ? 0 : (nextPaletteFade ?? (old.palette.id != new.palette.id ? 1.5 : 0.25))
            scene.setPalette(new.palette, duration: duration)
        }
        nextPaletteFade = nil
        if old.parameters != new.parameters {
            scene.setParameters(new.parameters, animated: isPlaying)
        }
        if old.seed != new.seed || userTime {
            scene.setPhase(new.phase)
        }
        if !isPlaying { redrawCount &+= 1 }
    }

    /// Restores an undo snapshot but keeps the current moment of the animation.
    private func restore(_ snapshot: Snapshot) {
        captureTime()
        var s = snapshot.look
        s.time = look.time
        currentPresetID = snapshot.presetID
        committedPresetID = snapshot.presetID
        let seedChanged = s.seed != look.seed
        set(s, userTime: false)
        if seedChanged { scene.setPhase(s.phase) }
        committed = s
    }

    private func registerWithUndoManager(redo: Bool) {
        guard let um = undoManager else { return }
        um.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { redo ? target.redo() : target.undo() }
        }
        um.setActionName("Edit Wallpaper")
    }

    /// Equal apart from the scrubber position.
    static func sameEdit(_ a: Look, _ b: Look) -> Bool {
        var a = a, b = b
        a.time = 0
        b.time = 0
        return a == b
    }

    static func clamped(_ c: RGBColor) -> RGBColor {
        RGBColor(red: min(max(c.red, 0), 1), green: min(max(c.green, 0), 1), blue: min(max(c.blue, 0), 1))
    }
}
