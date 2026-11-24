import AppKit

// Entry point. No Dock icon: .accessory works for both `swift run` and the bundled
// .app (which also sets LSUIElement in its Info.plist).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate(options: Options.parse())
    app.delegate = delegate
    withExtendedLifetime(delegate) {
        app.run()
    }
}
