import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WallpaperCore

/// Preset browser: Moods, Seasons, Vibes and My Presets, with thumbnails. Selecting a row
/// applies it (one undo step per run of selections).
struct PresetSidebar: View {
    @Bindable var model: EditorModel
    let actions: PresetActions

    var body: some View {
        List(selection: Binding(get: { model.currentPresetID },
                                set: { id in if let id, let p = lookup(id) { model.apply(p) } })) {
            ForEach([Preset.Category.mood, .season, .vibe], id: \.self) { category in
                Section(category.title) {
                    ForEach(Preset.builtIns.filter { $0.category == category }) { row($0) }
                }
            }
            Section(Preset.Category.mine.title) {
                if model.presetStore.presets.isEmpty {
                    Text("Save a look with ⇧⌘S to keep it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.presetStore.presets) { row($0) }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func lookup(_ id: UUID) -> Preset? {
        Preset.builtIn(id: id) ?? model.presetStore.preset(id: id)
    }

    private func row(_ preset: Preset) -> some View {
        PresetRow(model: model, preset: preset,
                  edited: preset.id == model.currentPresetID && model.isModified)
            .tag(preset.id)
            .contextMenu {
                Button("Duplicate to My Presets") { actions.duplicate(preset) }
                if !preset.isBuiltIn {
                    Button("Rename…") { actions.rename(preset) }
                }
                Button("Export Preset File…") { actions.export(preset) }
                if !preset.isBuiltIn {
                    Divider()
                    Button("Move to Trash", role: .destructive) { actions.delete(preset) }
                }
            }
    }
}

private struct PresetRow: View {
    let model: EditorModel
    let preset: Preset
    let edited: Bool
    private let image = State<CGImage?>(initialValue: nil)

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let cg = image.wrappedValue {
                    Image(decorative: cg, scale: 2)
                        .resizable()
                } else {
                    Rectangle().fill(.quaternary)
                }
            }
            .frame(width: 64, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name).lineLimit(1)
                if edited {
                    Text("Edited").font(.caption).foregroundStyle(.secondary)
                } else if preset.look.dayArc.hasPaletteOverrides {
                    Text("Dawn · Day · Dusk").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        // Render outside `body`; re-render only when the preset's look changes.
        .task(id: preset.look) {
            image.wrappedValue = model.thumbnails.image(for: preset.look)
        }
    }
}

/// Preset actions that need UI (name prompts, file panels, error alerts). Owned by EditorView.
struct PresetActions {
    var duplicate: (Preset) -> Void
    var rename: (Preset) -> Void
    var export: (Preset) -> Void
    var delete: (Preset) -> Void
}

extension UTType {
    static let dynamicWallpaperPreset = UTType(exportedAs: "io.github.gloaming.preset", conformingTo: .json)
}

enum PresetFilePanels {
    @MainActor static func chooseExportURL(for preset: Preset) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(preset.name).\(Preset.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: Preset.fileExtension) ?? .json]
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor static func chooseImportURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Preset.readableFileExtensions.compactMap { UTType(filenameExtension: $0) } + [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
