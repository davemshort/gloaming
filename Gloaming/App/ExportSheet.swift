import AppKit
import SwiftUI
import WallpaperCore

struct ExportSheet: View {
    @Bindable var model: EditorModel
    @Binding var isPresented: Bool

    // `State` stored directly instead of `@State`: in the macOS 27 SDK `@State` is a macro whose
    // plugin ships only with full Xcode, and this project builds with the Command Line Tools.
    private let settingsState = State(initialValue: ExportSettings())
    private let exportingState = State(initialValue: false)
    private let resultState = State<Result<[URL], Error>?>(initialValue: nil)

    private var settings: ExportSettings {
        get { settingsState.wrappedValue }
        nonmutating set { settingsState.wrappedValue = newValue }
    }
    private var isExporting: Bool {
        get { exportingState.wrappedValue }
        nonmutating set { exportingState.wrappedValue = newValue }
    }
    private var result: Result<[URL], Error>? {
        get { resultState.wrappedValue }
        nonmutating set { resultState.wrappedValue = newValue }
    }
    private var bound: Binding<ExportSettings> { settingsState.projectedValue }
    private let nameState = State(initialValue: "")
    /// True once the user types a name; until then the name follows the export type.
    private let nameEdited = State(initialValue: false)
    private let customWidth = State(initialValue: 3840)
    private let customHeight = State(initialValue: 2160)

    private var displays: [ExportSize] { ExportSize.connectedDisplays() }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Wallpaper").font(.title2.bold()).padding([.horizontal, .top], 20)

            Form {
                Picker("Type", selection: bound.kind) {
                    ForEach(ExportSettings.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                }

                TextField("Name", text: Binding(get: { nameState.wrappedValue },
                                                set: { nameState.wrappedValue = $0; nameEdited.wrappedValue = true }),
                          prompt: Text(model.suggestedExportName(for: settings.kind)))

                HStack {
                    Picker("Size", selection: bound.size) {
                        Text(Self.currentDisplayTitle).tag(ExportSize?.none)
                        Divider()
                        ForEach(displays, id: \.self) { Text($0.description).tag(Optional($0)) }
                    ForEach(ExportSize.presets, id: \.self) { Text($0.description).tag(Optional($0)) }
                    if let custom = settings.size, !ExportSize.presets.contains(custom), !displays.contains(custom) {
                        Divider()
                        Text(custom.description).tag(Optional(custom))
                    }
                    }
                    Button("Use Current Display") { settings.size = nil }
                        .disabled(settings.size == nil)
                        .help("Match the display this window is on")
                }

                LabeledContent("Custom size") {
                    HStack(spacing: 6) {
                        TextField("Width", value: customWidth.projectedValue, format: .number.grouping(.never),
                                  prompt: Text("Width"))
                            .labelsHidden()
                            .frame(width: 70)
                        Text("×")
                        TextField("Height", value: customHeight.projectedValue, format: .number.grouping(.never),
                                  prompt: Text("Height"))
                            .labelsHidden()
                            .frame(width: 70)
                        Button("Use") {
                            settings.size = ExportSize(width: customWidth.wrappedValue, height: customHeight.wrappedValue)
                        }
                        .disabled(!ExportSize(width: customWidth.wrappedValue, height: customHeight.wrappedValue).isValid)
                        .help("Up to \(ExportSize.maxDimension) pixels per side")
                    }
                }

                if settings.kind == .timeOfDay || settings.kind == .sunPosition {
                    Picker("Frames", selection: bound.frames) {
                        ForEach([8, 12, 16, 24], id: \.self) { n in Text("\(n) (every \(Self.interval(n)))").tag(n) }
                    }
                }
                if settings.kind == .variations {
                    Stepper("Count: \(settings.variations)", value: bound.variations, in: 2...24)
                }

                LabeledContent("Folder") {
                    HStack {
                        Text(settings.directory.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Choose…") { chooseFolder() }
                    }
                }

                Text(explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.grouped)

            if let result { resultView(result).padding(.horizontal, 20) }

            HStack {
                if isExporting { ProgressView().controlSize(.small); Text("Exporting…").foregroundStyle(.secondary) }
                Spacer()
                Button(result == nil ? "Cancel" : "Done") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Export") { export() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExporting)
            }
            .padding(20)
        }
        .frame(width: 560)
        .onAppear {
            settings = model.exportSettings
            nameState.wrappedValue = model.suggestedExportName(for: settings.kind)
        }
        .onChange(of: settings.kind) { _, kind in
            if !nameEdited.wrappedValue { nameState.wrappedValue = model.suggestedExportName(for: kind) }
        }
    }

    private var explanation: String {
        switch settings.kind {
        case .sunPosition:
            "One file that follows the real sun where you are: night colors after dark, dawn at sunrise, full light at midday, dusk at sunset, shifting with the seasons. Light and Dark stills also work. Add it in System Settings › Wallpaper (shown as “Dynamic”). Requires Location Services to be on."
        case .timeOfDay:
            "Changes at fixed clock times (every 2 h with 12 frames), the same all year, and needs no Location Services. Note: macOS's Light/Dark (Still) options keep the current frame for this type; use “follows the sun” if you want those."
        case .lightDark:
            "One file with a light and a dark image that follows your Light/Dark appearance (“Automatic” in System Settings)."
        case .stillPNG, .stillHEIC:
            "A single image of the preview at the current moment. PNG is lossless; HEIC is much smaller."
        case .variations:
            "Several stills with different seeds. Add the folder in System Settings › Wallpaper and turn on rotation to cycle through them."
        }
    }

    @ViewBuilder
    private func resultView(_ result: Result<[URL], Error>) -> some View {
        switch result {
        case .success(let urls):
            VStack(alignment: .leading, spacing: 8) {
                Label(urls.count == 1 ? "Exported \(urls[0].lastPathComponent)" : "Exported \(urls.count) files",
                      systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                HStack {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(urls) }
                    Button("Open Wallpaper Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        case .failure(let error):
            Label("Export failed: \(String(describing: error))", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private func export() {
        isExporting = true
        result = nil
        model.exportSettings = settings
        let settings = settings
        // Yield once so "Exporting…" draws before the (main-actor, 0.5–4 s) render starts.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            let name = nameState.wrappedValue
            result = Result { try model.export(settings, name: name, currentDisplaySize: ExportSize.currentDisplay()) }
            if case .success(let urls) = result { EventLog.shared.log("exported \(urls.map(\.lastPathComponent))") }
            isExporting = false
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.directory
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { settings.directoryPath = url.path }
    }

    /// "Current display (3600×2338)": size only; the display's name is in the menu below.
    static var currentDisplayTitle: String {
        guard let d = ExportSize.currentDisplay() else { return "Current display" }
        return "Current display (\(d.width)×\(d.height))"
    }

    static func interval(_ frames: Int) -> String {
        let minutes = 24 * 60 / frames
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}
