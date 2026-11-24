import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var options: Options
    private var context: RenderContext!
    private var controllers: [CGDirectDisplayID: DesktopWindowController] = [:]
    private var statusItem: NSStatusItem!
    private var pauseItem: NSMenuItem!
    private var statsTimer: Timer?
    private var occlusionPaused: Set<CGDirectDisplayID> = []
    private var occlusionObservers: [CGDirectDisplayID: NSObjectProtocol] = [:]
    private var userPaused = false
    private let log = EventLog.shared

    init(options: Options) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        log.log("launch pid=\(ProcessInfo.processInfo.processIdentifier) os=\(ProcessInfo.processInfo.operatingSystemVersionString) fps=\(options.fps) renderScale=\(options.renderScale) levelOffset=\(options.levelOffset) pauseWhenOccluded=\(options.pauseWhenOccluded)")
        do {
            context = try RenderContext()
            log.log("metal device=\(context.device.name)")
        } catch {
            log.log("FATAL metal init failed: \(error.localizedDescription)")
            NSApp.terminate(nil)
            return
        }

        buildStatusItem()
        rebuildWindows(reason: "launch")
        observeSystemEvents()

        statsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.logStats() }
        }

        if let seconds = options.exitAfter {
            log.log("will exit after \(seconds)s")
            Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
                MainActor.assumeIsolated { NSApp.terminate(nil) }
            }
        }

        // Record where our windows landed in the global stack, and where the status item is.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            self.log.log(WindowList.desktopStackDescription())
            let frame = self.statusItem.button?.window?.frame ?? .zero
            self.log.log("statusItem isVisible=\(self.statusItem.isVisible) hasImage=\(self.statusItem.button?.image != nil) windowFrame=\(frame) onScreen=\(self.statusItem.button?.window?.isOnActiveSpace ?? false) occlusionVisible=\(self.statusItem.button?.window?.occlusionState.contains(.visible) ?? false)")
        }
    }

    /// Fallback control when the menu bar icon is hidden (crowded menu bar, a menu bar
    /// manager, or System Settings > Menu Bar): opening the app again shows this dialog.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.log("reopen requested")
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "DesktopPrototype is running"
        alert.informativeText = "Log: \(log.url.path)"
        alert.addButton(withTitle: "Keep Running")
        alert.addButton(withTitle: "Quit")
        if alert.runModal() == .alertSecondButtonReturn { NSApp.terminate(nil) }
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        controllers.values.forEach { $0.close() }
        log.log("terminate")
    }

    // MARK: - Windows per screen

    private func rebuildWindows(reason: String) {
        let screens = NSScreen.screens
        let ids = Set(screens.map(\.displayID))

        for (id, c) in controllers where !ids.contains(id) {
            if let token = occlusionObservers.removeValue(forKey: id) {
                NotificationCenter.default.removeObserver(token)
            }
            c.close()
            controllers[id] = nil
            log.log("display removed id=\(id)")
        }
        for screen in screens {
            if let c = controllers[screen.displayID] {
                c.update(for: screen)
            } else {
                let c = DesktopWindowController(screen: screen, context: context, options: options)
                c.metalView.isPaused = userPaused
                controllers[screen.displayID] = c
                observeOcclusion(of: c)
            }
        }
        for screen in screens {
            log.log("display id=\(screen.displayID) name=\"\(screen.localizedName)\" frame=\(screen.frame) scale=\(screen.backingScaleFactor) maxFPS=\(screen.maximumFramesPerSecond) (\(reason))")
        }
    }

    private func observeOcclusion(of c: DesktopWindowController) {
        occlusionObservers[c.displayID] = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: c.window, queue: .main) { [weak self, weak c] _ in
            MainActor.assumeIsolated { if let c { self?.occlusionChanged(c) } }
        }
    }

    private func occlusionChanged(_ c: DesktopWindowController) {
        let visible = c.window.occlusionState.contains(.visible)
        log.log("occlusion display=\(c.displayID) visible=\(visible)")
        guard options.pauseWhenOccluded else { return }
        if visible { occlusionPaused.remove(c.displayID) } else { occlusionPaused.insert(c.displayID) }
        c.metalView.isPaused = userPaused || !visible
    }

    // MARK: - System events (logged for the manual test plan)

    private func observeSystemEvents() {
        let nc = NotificationCenter.default
        let ws = NSWorkspace.shared.notificationCenter

        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.log("event screenParametersChanged")
                self?.rebuildWindows(reason: "screenParametersChanged")
            }
        }
        nc.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.log("event lowPowerMode=\(ProcessInfo.processInfo.isLowPowerModeEnabled)")
            }
        }

        let wsEvents: [(Notification.Name, String)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, "activeSpaceChanged"),
            (NSWorkspace.willSleepNotification, "willSleep"),
            (NSWorkspace.didWakeNotification, "didWake"),
            (NSWorkspace.screensDidSleepNotification, "screensDidSleep"),
            (NSWorkspace.screensDidWakeNotification, "screensDidWake"),
            (NSWorkspace.sessionDidResignActiveNotification, "sessionResignedActive"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "sessionBecameActive"),
        ]
        for (name, label) in wsEvents {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let states = self.controllers.values
                        .map { "\($0.displayID):\($0.window.occlusionState.contains(.visible) ? "visible" : "occluded")" }
                        .joined(separator: " ")
                    self.log.log("event \(label) windows=[\(states)]")
                }
            }
        }
    }

    private func logStats() {
        for c in controllers.values.sorted(by: { $0.displayID < $1.displayID }) {
            let s = c.metalView.stats.drain()
            let size = c.metalView.drawableSize
            log.log(String(format: "stats display=%u measuredFPS=%.1f gpuWallMs=%.3f cpuEncodeMs=%.3f drawable=%dx%d paused=%@ occlusionVisible=%@",
                           c.displayID, Double(s.frames) / 10.0, s.gpuMs, s.cpuMs,
                           Int(size.width), Int(size.height), c.metalView.isPaused ? "yes" : "no",
                           c.window.occlusionState.contains(.visible) ? "yes" : "no"))
        }
    }

    // MARK: - Status item (the only UI; the windows are click-through)

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles.rectangle.stack", accessibilityDescription: "Desktop Prototype")
        statusItem.autosaveName = "DesktopPrototypeStatusItem"

        let menu = NSMenu()
        pauseItem = NSMenuItem(title: "Pause", action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        menu.addItem(pauseItem)

        let fpsMenu = NSMenu()
        for fps in [15, 30, 60] {
            let item = NSMenuItem(title: "\(fps) FPS", action: #selector(setFPS(_:)), keyEquivalent: "")
            item.tag = fps
            item.target = self
            item.state = fps == options.fps ? .on : .off
            fpsMenu.addItem(item)
        }
        let fpsItem = NSMenuItem(title: "Frame Rate", action: nil, keyEquivalent: "")
        fpsItem.submenu = fpsMenu
        menu.addItem(fpsItem)

        let dump = NSMenuItem(title: "Log Window Stack", action: #selector(logWindowStack), keyEquivalent: "l")
        dump.target = self
        menu.addItem(dump)
        let reveal = NSMenuItem(title: "Reveal Log in Finder", action: #selector(revealLog), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Desktop Prototype", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func togglePause() {
        userPaused.toggle()
        pauseItem.title = userPaused ? "Resume" : "Pause"
        for c in controllers.values {
            c.metalView.isPaused = userPaused || occlusionPaused.contains(c.displayID)
        }
        log.log("user paused=\(userPaused)")
    }

    @objc private func setFPS(_ sender: NSMenuItem) {
        options.fps = sender.tag
        controllers.values.forEach { $0.metalView.preferredFPS = sender.tag }
        sender.menu?.items.forEach { $0.state = $0.tag == sender.tag ? .on : .off }
        log.log("user fps=\(sender.tag)")
    }

    @objc private func logWindowStack() {
        log.log(WindowList.desktopStackDescription())
    }

    @objc private func revealLog() {
        NSWorkspace.shared.activateFileViewerSelecting([log.url])
    }
}
