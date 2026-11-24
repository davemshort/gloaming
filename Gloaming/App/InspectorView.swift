import SwiftUI
import WallpaperCore

struct InspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            PaletteSection(model: model)

            Section("Movement") {
                ParameterSlider(model: model, title: "Speed", key: \.speed, range: 0...3)
                ParameterSlider(model: model, title: "Complexity", key: \.complexity, range: 0...1)
                ParameterSlider(model: model, title: "Softness", key: \.blend, range: 0...1)
            }

            Section("Finish") {
                ParameterSlider(model: model, title: "Grain", key: \.grain, range: 0...1)
                ParameterSlider(model: model, title: "Brightness", key: \.brightness, range: 0.2...1.5)
                ParameterSlider(model: model, title: "Saturation", key: \.saturation, range: 0...2)
            }

            Section {
                DayStrip(model: model, aspect: {
                    let size = model.exportSettings.size ?? ExportSize.currentDisplay() ?? ExportSize(width: 16, height: 9)
                    return Double(size.width) / Double(size.height)
                }())
            } header: {
                Text("Through the Day")
            } footer: {
                Text(model.look.dayArc.hasPaletteOverrides
                     ? "What a Dynamic export shows, including this preset’s dawn, dusk and night colors. Editing colors replaces those with yours."
                     : "What a Dynamic export shows: dimmer at night, brightest at noon.")
            }

            Section {
                HStack {
                    TextField("Seed", value: Binding(get: { Int(model.look.seed) },
                                                     set: { v in model.update { $0.seed = UInt32(clamping: max(0, v)) } }),
                              format: .number.grouping(.never))
                    Button {
                        model.update { $0.seed = UInt32.random(in: 0...100_000) }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .help("New seed: a different region of the same look")
                }
            } header: {
                Text("Variation")
            } footer: {
                Text("The same seed and settings always give the same wallpaper.")
            }
        }
        .formStyle(.grouped)
    }
}

/// Slider bound to one RenderParameters value; one undo step per drag.
private struct ParameterSlider: View {
    @Bindable var model: EditorModel
    let title: String
    let key: WritableKeyPath<RenderParameters, Double>
    let range: ClosedRange<Double>

    var body: some View {
        LabeledContent {
            Slider(value: Binding(get: { model.look.parameters[keyPath: key] },
                                  set: { v in model.update(commit: false) { $0.parameters[keyPath: key] = v } }),
                   in: range,
                   onEditingChanged: { editing in if !editing { model.commit() } })
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(model.look.parameters[keyPath: key], format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 118)
        }
    }
}

private struct PaletteSection: View {
    @Bindable var model: EditorModel

    var body: some View {
        Section {
            let colors = model.look.palette.colors
            ForEach(Array(colors.enumerated()), id: \.offset) { index, color in
                HStack(spacing: 10) {
                    ColorPicker("Color \(index + 1)",
                                selection: Binding(get: { Color(color) },
                                                   set: { model.setColor(WallpaperCore.RGBColor($0), at: index) }),
                                supportsOpacity: false)
                        .labelsHidden()
                    Text(color.hexString)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { model.moveColor(from: index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                        .disabled(index == 0)
                        .help("Move toward the dark end")
                    Button { model.moveColor(from: index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                        .disabled(index == colors.count - 1)
                        .help("Move toward the light end")
                    Button { model.removeColor(at: index) } label: { Image(systemName: "minus.circle") }
                        .disabled(colors.count <= EditorModel.colorRange.lowerBound)
                        .help("Remove color")
                }
                .buttonStyle(.borderless)
            }

            HStack {
                Button { model.addColor() } label: { Label("Add Color", systemImage: "plus") }
                    .disabled(colors.count >= EditorModel.colorRange.upperBound)
                Spacer()
                Button("Shuffle Colors") { model.randomize(.colors) }
            }
            .buttonStyle(.borderless)

            // Ramp preview: what the gradient draws from, dark → light.
            LinearGradient(colors: colors.map(Color.init), startPoint: .leading, endPoint: .trailing)
                .frame(height: 14)
                .clipShape(Capsule())
                .accessibilityHidden(true)
        } header: {
            // Presets are chosen in the sidebar; this section edits the current look's colors.
            HStack {
                Text("Colors")
                Spacer()
                Text(model.look.palette.name.isEmpty ? "Custom" : model.look.palette.name)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
