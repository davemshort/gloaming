import Foundation

/// Command-line options for the prototype. All are optional.
///
///   --fps N              Preferred frame rate (default 30). 15, 30 and 60 are the targets.
///   --render-scale S     Fraction of native pixel resolution to render at (default 0.5).
///                        The CAMetalLayer upscales with linear filtering.
///   --level-offset K     Added to CGWindowLevelForKey(.desktopWindow) (default 0).
///   --pause-when-occluded  Stop the display link while the window reports not visible.
///   --exit-after SECONDS Terminate automatically (used for unattended test runs).
struct Options {
    var fps: Int = 30
    var renderScale: Double = 0.5
    var levelOffset: Int = 0
    var pauseWhenOccluded = false
    var exitAfter: TimeInterval?

    static func parse(_ args: [String] = CommandLine.arguments) -> Options {
        var o = Options()
        var it = args.dropFirst().makeIterator()
        while let a = it.next() {
            switch a {
            case "--fps": if let v = it.next().flatMap(Int.init) { o.fps = max(1, min(120, v)) }
            case "--render-scale": if let v = it.next().flatMap(Double.init) { o.renderScale = max(0.1, min(1.0, v)) }
            case "--level-offset": if let v = it.next().flatMap(Int.init) { o.levelOffset = v }
            case "--pause-when-occluded": o.pauseWhenOccluded = true
            case "--exit-after": o.exitAfter = it.next().flatMap(TimeInterval.init)
            default: break // Ignore unknown args (e.g. -NSDocumentRevisionsDebugMode from Xcode)
            }
        }
        return o
    }
}
