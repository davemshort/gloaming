import SwiftUI
import WallpaperCore

struct EditorView: View {
    @Bindable var model: EditorModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.displayScale) private var displayScale
    // `State` stored directly instead of `@State`: in the macOS 27 SDK `@State` is a macro whose
    // plugin ships only with full Xcode, and this project builds with the Command Line Tools.
    private let showingExport = State(initialValue: false)
    /// Name prompt: nil = hidden. `renaming` set → rename that preset; otherwise save as new.
    private let namePrompt = State<String?>(initialValue: nil)
    private let renaming = State<Preset?>(initialValue: nil)
    private let errorMessage = State<String?>(initialValue: nil)

    private var targetSize: ExportSize {
        model.exportSettings.size ?? ExportSize.currentDisplay() ?? ExportSize(width: 16, height: 9)
    }

    var body: some View {
        NavigationSplitView {
            PresetSidebar(model: model, actions: presetActions)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    preview
                    Divider()
                    TimeBar(model: model)
                }
                Divider()
                InspectorView(model: model)
                    .frame(width: 330)
            }
        }
        .navigationTitle(model.currentPreset.map { $0.name + (model.isModified ? " — Edited" : "") } ?? "Gloaming")
        .toolbar { toolbar }
        .alert(renaming.wrappedValue == nil ? "Save Preset" : "Rename Preset",
               isPresented: Binding(get: { namePrompt.wrappedValue != nil },
                                    set: { if !$0 { namePrompt.wrappedValue = nil; renaming.wrappedValue = nil } })) {
            TextField("Name", text: Binding(get: { namePrompt.wrappedValue ?? "" }, set: { namePrompt.wrappedValue = $0 }))
            Button(renaming.wrappedValue == nil ? "Save" : "Rename") { finishNamePrompt() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { errorMessage.wrappedValue != nil }, set: { if !$0 { errorMessage.wrappedValue = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage.wrappedValue ?? "")
        }
        .sheet(isPresented: showingExport.projectedValue) {
            ExportSheet(model: model, isPresented: showingExport.projectedValue)
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
    }

    private var preview: some View {
        ZStack {
            // The window's own adaptive background: light in Light mode, dark in Dark mode,
            // so the wallpaper reads as content rather than sitting in a heavy gray well.
            Color(nsColor: .windowBackgroundColor)
            if model.previewActualSize {
                // One export pixel per screen pixel; scroll to inspect grain and detail.
                GeometryReader { geo in
                    ScrollView([.horizontal, .vertical]) {
                        previewCanvas
                            .frame(width: CGFloat(targetSize.width) / displayScale,
                                   height: CGFloat(targetSize.height) / displayScale)
                            .padding(28)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height)
                    }
                }
            } else {
                previewCanvas
                    .aspectRatio(CGFloat(targetSize.width) / CGFloat(targetSize.height), contentMode: .fit)
                    .padding(28)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewCanvas: some View {
        PreviewView(model: model, isPlaying: model.isPlaying, redrawCount: model.redrawCount)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.isPlaying.toggle()
            } label: {
                Label(model.isPlaying ? "Pause" : "Play", systemImage: model.isPlaying ? "pause.fill" : "play.fill")
            }
            .keyboardShortcut(.space, modifiers: [])
            .help(model.isPlaying ? "Pause the preview (Space)" : "Play the preview (Space)")

            Picker("Preview Size", selection: $model.previewActualSize) {
                Text("Fit").tag(false)
                Text("100%").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Fit the preview to the window (⌘9), or show it at actual pixels (⌘0)")

            Button {
                FullScreenPreview.shared.toggle(model: model, size: targetSize)
            } label: {
                Label("Full-Screen Preview", systemImage: "arrow.up.left.and.arrow.down.right")
            }
            .help("Preview full screen (⇧⌘F; Esc to exit)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                if let current = model.currentPreset, !current.isBuiltIn {
                    Button("Save Changes to “\(current.name)”") { attempt { try model.saveChangesToCurrentPreset() } }
                        .keyboardShortcut("s")
                        .disabled(!model.canSaveChangesToCurrentPreset)
                }
                Button("Save as New Preset…") { namePrompt.wrappedValue = model.suggestedPresetName() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Import Preset File…") {
                    if let url = PresetFilePanels.chooseImportURL() { attempt { try model.importPreset(from: url) } }
                }
                .keyboardShortcut("o")
                if let current = model.currentPreset {
                    Button("Export “\(current.name)” as File…") { presetActions.export(current) }
                }
            } label: {
                Label("Presets", systemImage: "square.stack")
            }
            .help("Save, import and share presets")

            Menu {
                Button("Everything") { model.randomize(.everything) }.keyboardShortcut("r")
                Button("Colors Only") { model.randomize(.colors) }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Movement Only") { model.randomize(.movement) }.keyboardShortcut("r", modifiers: [.command, .option])
            } label: {
                Label("Randomize", systemImage: "dice")
            } primaryAction: {
                model.randomize(.everything)
            }
            .help("Randomize (⌘R)")

            Button {
                showingExport.wrappedValue = true
            } label: {
                Label("Export…", systemImage: "square.and.arrow.up")
            }
            .keyboardShortcut("e")
            .help("Export as wallpaper (⌘E)")
        }
    }
}

extension EditorView {
    var presetActions: PresetActions {
        PresetActions(
            duplicate: { p in attempt { try model.duplicatePreset(p) } },
            rename: { p in renaming.wrappedValue = p; namePrompt.wrappedValue = p.name },
            export: { p in
                if let url = PresetFilePanels.chooseExportURL(for: p) { attempt { try model.presetStore.exportPreset(p, to: url) } }
            },
            delete: { p in attempt { try model.deletePreset(p) } })
    }

    func finishNamePrompt() {
        let name = namePrompt.wrappedValue ?? ""
        if let p = renaming.wrappedValue {
            attempt { try model.renamePreset(p, to: name) }
        } else {
            attempt { try model.saveAsNewPreset(named: name) }
        }
        namePrompt.wrappedValue = nil
        renaming.wrappedValue = nil
    }

    func attempt(_ work: () throws -> Void) {
        do { try work() } catch { errorMessage.wrappedValue = String(describing: error) }
    }
}

/// Play/pause and the time scrubber under the preview.
private struct TimeBar: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 12) {
            Button {
                model.isPlaying.toggle()
            } label: {
                Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 16)
            }
            .buttonStyle(.borderless)
            Slider(value: Binding(get: { min(max(model.playhead, EditorModel.timeRange.lowerBound), EditorModel.timeRange.upperBound) },
                                  set: { model.scrub(to: $0) }),
                   in: EditorModel.timeRange)
            Text(Self.format(model.playhead))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .help("Scrub to choose the moment a still is taken from, or where a dynamic sequence starts")
    }

    static func format(_ t: Double) -> String {
        let s = max(0, Int(t))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
