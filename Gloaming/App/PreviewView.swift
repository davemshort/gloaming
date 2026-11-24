import AppKit
import SwiftUI
import WallpaperCore

/// The animated preview: the Phase 2 Metal view, configured to match export fidelity
/// (field at ½ of native pixels, grain and dither per native pixel).
///
/// `isPlaying` and `redrawCount` are plain stored properties so SwiftUI calls `updateNSView`
/// whenever they change. Rendering pauses while the window is hidden or fully covered.
struct PreviewView: NSViewRepresentable {
    let model: EditorModel
    let isPlaying: Bool
    let redrawCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> WallpaperView {
        let view = WallpaperView(context: model.context, scene: model.scene,
                                 renderScale: 0.5, outputScale: 1.0, fps: 60)
        context.coordinator.attach(view)
        context.coordinator.isPlaying = isPlaying
        return view
    }

    func updateNSView(_ view: WallpaperView, context: Context) {
        context.coordinator.isPlaying = isPlaying
        if !isPlaying { view.redraw() }
    }

    static func dismantleNSView(_ view: WallpaperView, coordinator: Coordinator) {
        view.stop()
        coordinator.detach()
    }

    @MainActor
    final class Coordinator {
        private let model: EditorModel
        private weak var view: WallpaperView?
        private var timer: Timer?
        private var observers: [NSObjectProtocol] = []
        private var windowVisible = true
        var isPlaying = true { didSet { applyPause() } }

        init(model: EditorModel) { self.model = model }

        func attach(_ view: WallpaperView) {
            self.view = view
            // Keep the scrubber in step with the running animation (10 Hz is plenty).
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.isPlaying, self.windowVisible else { return }
                    self.model.syncTimeFromScene()
                }
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Re-read our own window's state rather than passing the notification across.
                    guard let self, let window = self.view?.window else { return }
                    self.windowVisible = window.occlusionState.contains(.visible)
                    self.applyPause()
                }
            })
            applyPause()
            // One diagnostics line a few seconds in (measured FPS and render sizes).
            Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let view = self?.view else { return }
                    let w = view.stats.drain()
                    EventLog.shared.log(String(format: "preview measuredFPS=%.1f gpuWallMs=%.2f field=%dx%d output=%dx%d paused=%@",
                                               w.measuredFPS, w.gpuWallMs, Int(view.fieldSize.width), Int(view.fieldSize.height),
                                               Int(view.outputSize.width), Int(view.outputSize.height), view.isPaused ? "yes" : "no"))
                }
            }
        }

        func detach() {
            timer?.invalidate()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            observers.removeAll()
        }

        private func applyPause() {
            view?.isPaused = !(isPlaying && windowVisible)
        }
    }
}
