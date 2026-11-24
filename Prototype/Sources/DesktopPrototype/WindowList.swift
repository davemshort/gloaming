import CoreGraphics
import Foundation

/// Dumps the on-screen window stack (front to back) for windows at or below the
/// desktop-icon level, using the public CGWindowListCopyWindowInfo. Owner names, layers
/// and bounds do not require Screen Recording permission; window titles may be absent.
enum WindowList {
    static func desktopStackDescription() -> String {
        let desktop = Int(CGWindowLevelForKey(.desktopWindow))
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        var lines = ["levels: desktopWindow=\(desktop) desktopIconWindow=\(icons) normal=\(CGWindowLevelForKey(.normalWindow))",
                     "front-to-back, layer <= desktopIconWindow:"]
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in info {
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            guard layer <= icons else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let name = w[kCGWindowName as String] as? String ?? ""
            let id = w[kCGWindowNumber as String] as? Int ?? 0
            var bounds = CGRect.zero
            if let b = w[kCGWindowBounds as String] as? NSDictionary {
                bounds = CGRect(dictionaryRepresentation: b) ?? .zero
            }
            lines.append("  layer=\(layer) (desktop\(layer - desktop >= 0 ? "+" : "")\(layer - desktop)) owner=\(owner) id=\(id) name=\"\(name)\" bounds=\(Int(bounds.minX)),\(Int(bounds.minY)) \(Int(bounds.width))x\(Int(bounds.height))")
        }
        return lines.joined(separator: "\n")
    }
}
