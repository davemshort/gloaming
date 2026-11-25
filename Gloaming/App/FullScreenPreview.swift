import AppKit
import SwiftUI
import WallpaperCore

/// Distraction-free preview: the wallpaper alone on the editor's screen, with the menu bar
/// and Dock hidden. Esc or ⇧⌘F closes it; Space plays/pauses. The editor's own preview
/// pauses while it's covered (occlusion), so only one view renders.
@MainActor
final class FullScreenPreview {
    static let shared = FullScreenPreview()
    private var window: NSWindow?
    private var editorWindow: NSWindow?

    var isShowing: Bool { window != nil }

    func toggle(model: EditorModel, size: ExportSize) {
        if isShowing { close() } else { show(model: model, size: size) }
    }

    func show(model: EditorModel, size: ExportSize) {
        editorWindow = NSApp.keyWindow
        guard let screen = editorWindow?.screen ?? NSScreen.main else { return }
        let window = PreviewWindow(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces]
        window.onEscape = { [weak self] in self?.close() }
        window.onSpace = { model.isPlaying.toggle() }
        window.contentView = NSHostingView(rootView: FullScreenPreviewContent(model: model, size: size))
        window.setFrame(screen.frame, display: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar]
        window.makeKeyAndOrderFront(nil)
        NSCursor.setHiddenUntilMouseMoves(true)
        self.window = window
        EventLog.shared.log("full-screen preview open \(Int(screen.frame.width))x\(Int(screen.frame.height))pt")
    }

    func close() {
        guard let window else { return }
        self.window = nil
        NSApp.presentationOptions = []
        window.orderOut(nil)
        window.contentView = nil
        editorWindow?.makeKeyAndOrderFront(nil)
        editorWindow = nil
    }
}

/// Borderless windows can't become key by default; this one must, to receive keys.
private final class PreviewWindow: NSWindow {
    var onEscape: (() -> Void)?
    var onSpace: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onEscape?()                       // Esc
        case 49: onSpace?()                        // Space
        default: super.keyDown(with: event)
        }
    }
}

/// Fills the screen the way macOS's "Fill Screen" wallpaper option does: the export's
/// aspect ratio, scaled to cover, centered and cropped.
private struct FullScreenPreviewContent: View {
    let model: EditorModel
    let size: ExportSize
    // `State` stored directly instead of `@State` (macro plugin unavailable without Xcode).
    private let hintVisible = State(initialValue: true)

    var body: some View {
        ZStack {
            Color.black
            PreviewView(model: model, isPlaying: model.isPlaying, redrawCount: model.redrawCount)
                .aspectRatio(CGFloat(size.width) / CGFloat(size.height), contentMode: .fill)
            if hintVisible.wrappedValue {
                Text("Esc to exit  ·  Space to play or pause")
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .transition(.opacity)
            }
        }
        .clipped()
        .ignoresSafeArea()
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.6)) { hintVisible.wrappedValue = false }
        }
    }
}
