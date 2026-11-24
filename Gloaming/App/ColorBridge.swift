import AppKit
import SwiftUI
import WallpaperCore

// Note: the macOS 27 SDK also defines an `RGBColor`, so ours is always written qualified here.

extension Color {
    init(_ c: WallpaperCore.RGBColor) {
        self.init(.sRGB, red: c.red, green: c.green, blue: c.blue)
    }
}

extension WallpaperCore.RGBColor {
    /// Converts any SwiftUI colour (P3, extended range, catalog colours) to sRGB. Values may
    /// fall outside 0…1 for wide-gamut picks; EditorModel clamps them.
    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.extendedSRGB) ?? .black
        self.init(red: Double(ns.redComponent), green: Double(ns.greenComponent), blue: Double(ns.blueComponent))
    }
}
