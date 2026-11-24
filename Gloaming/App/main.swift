import AppKit
import WallpaperCore

// Command-line modes run here and exit before any UI starts; otherwise the SwiftUI editor
// launches. (Doing CLI work inside App.init would be fragile.)
let options = LaunchOptions.parse()

if options.isCommandLineMode {
    MainActor.assumeIsolated {
        _ = NSApplication.shared            // NSScreen needs the shared application
        options.warnings.forEach { print("warning: \($0)") }
        do {
            let context = try RenderContext()
            if let request = options.export {
                ExportCommand.run(request, options: options, context: context)
            } else if let dir = options.solarTestDir {
                guard let size = ExportSize.currentDisplay() else { throw FrameRenderer.Error.imageCreationFailed }
                try SolarTest.run(context: context, directory: dir, size: size)
            } else if let dir = options.iconDir {
                try IconCommand.run(directory: dir, variant: options.iconVariant, context: context)
            } else if let dir = options.phaseATestDir {
                try PhaseATest.run(context: context, directory: dir, size: options.snapshotSize,
                                   renderScale: options.renderScale)
            } else if let path = options.snapshotPath {
                let scene = SceneState(context: context, palette: options.palette,
                                       parameters: options.parameters, phase: options.startPhase)
                let image = try Snapshot.render(context: context, scene: scene,
                                                width: options.snapshotSize.width, height: options.snapshotSize.height,
                                                fieldScale: Snapshot.fieldScale(renderScale: options.renderScale))
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                try Snapshot.writePNG(image, to: url)
                print("wrote \(url.path)")
            }
        } catch {
            print("failed: \(error)")
            exit(1)
        }
    }
    exit(0)
}

GloamingApp.main()
