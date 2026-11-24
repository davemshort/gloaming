import AppKit

extension NSScreen {
    /// Stable-for-this-session identifier (CGDirectDisplayID).
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}

/// One borderless, click-through window per screen, placed at the desktop window level:
/// above the system wallpaper, below Finder's desktop icons.
///
/// Public APIs only: NSWindow, CGWindowLevelForKey, NSWindow.CollectionBehavior.
@MainActor
final class DesktopWindowController {
    let displayID: CGDirectDisplayID
    let window: NSWindow
    let metalView: MetalView

    init(screen: NSScreen, context: RenderContext, options: Options) {
        displayID = screen.displayID

        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)   // full frame, including under the menu bar
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + options.levelOffset)
        w.collectionBehavior = [
            .canJoinAllSpaces,   // present on every Space, including fullscreen-app Spaces
            .stationary,         // not moved by Mission Control / Exposé
            .ignoresCycle,       // excluded from Cmd-` window cycling
        ]
        w.ignoresMouseEvents = true
        w.isOpaque = true
        w.backgroundColor = .black
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.animationBehavior = .none
        w.title = "DesktopPrototype \(displayID)"

        let view = MetalView(context: context, renderScale: options.renderScale, fps: options.fps)
        view.autoresizingMask = [.width, .height]
        w.contentView = view

        window = w
        metalView = view
        w.orderFrontRegardless()
    }

    func update(for screen: NSScreen) {
        if window.frame != screen.frame { window.setFrame(screen.frame, display: true) }
    }

    func close() {
        metalView.stop()
        window.orderOut(nil)
        window.close()
    }
}
