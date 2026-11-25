import AppKit
import SwiftUI
import WallpaperCore

/// The editor app. Entered from main.swift (no @main) after command-line modes are handled.
struct GloamingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // `State` stored directly instead of `@State`: in the macOS 27 SDK `@State` is a macro whose
    // plugin ships only with full Xcode, and this project builds with the Command Line Tools.
    private let model = State<EditorModel?>(initialValue: AppDelegate.makeModel())

    var body: some Scene {
        WindowGroup("Gloaming") {
            if let model = model.wrappedValue {
                EditorView(model: model)
                    .frame(minWidth: 900, minHeight: 560)
            } else {
                ContentUnavailableView("Metal isn't available", systemImage: "exclamationmark.triangle",
                                       description: Text("This Mac can't run the renderer."))
                    .frame(width: 480, height: 300)
            }
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(before: .toolbar) {
                if let model = model.wrappedValue {
                    Button("Zoom to Fit") { model.previewActualSize = false }
                        .keyboardShortcut("9")
                    Button("Actual Size") { model.previewActualSize = true }
                        .keyboardShortcut("0")
                    Button("Full-Screen Preview") {
                        let size = model.exportSettings.size ?? ExportSize.currentDisplay() ?? ExportSize(width: 16, height: 9)
                        FullScreenPreview.shared.toggle(model: model, size: size)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    Divider()
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static func makeModel() -> EditorModel? {
        guard let context = try? RenderContext() else { return nil }
        let o = options
        if PresetStore.migrateLegacyDirectory(to: PresetStore.defaultDirectory) {
            EventLog.shared.log("moved presets from the former DynamicWallpaper folder")
        }
        let store = PresetStore(directory: PresetStore.defaultDirectory)
        store.loadErrors.forEach { EventLog.shared.log("preset load error: \($0)") }
        // Start on --preset if given, else the built-in preset matching the palette (Aurora by default).
        let start = o.preset ?? Preset.vibes.first { $0.look.palette.id == o.palette.id }
        var look = start?.look ?? Look(palette: o.palette)
        if o.parameters != RenderParameters() { look.parameters = o.parameters }
        let model = EditorModel(context: context, look: look, presetStore: store, presetID: start?.id)
        EventLog.shared.log("editor launch device=\(context.device.name) palette=\(o.palette.id)")
        return model
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let size = options.windowSize {
            // After SwiftUI has created and restored the window.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                MainActor.assumeIsolated {
                    guard let window = NSApp.windows.first(where: { $0.isVisible }),
                          let screen = window.screen?.visibleFrame else { return }
                    let frame = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                       width: size.width, height: size.height)
                    window.setFrame(frame, display: true)
                    NSApp.activate()
                }
            }
        }
        if let seconds = options.exitAfter {
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
