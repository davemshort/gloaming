import AppKit

/// Output size in pixels.
public struct ExportSize: Codable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int
    public var label: String?

    public init(width: Int, height: Int, label: String? = nil) {
        self.width = width
        self.height = height
        self.label = label
    }

    /// Parses "WxH".
    public init?(_ s: String) {
        let parts = s.lowercased().split(separator: "x").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        self.init(width: parts[0], height: parts[1])
    }

    public var description: String { "\(width)×\(height)" + (label.map { " (\($0))" } ?? "") }

    /// Apple GPUs support 16384-pixel textures; exports render in one pass up to this size.
    public static let maxDimension = 16_384

    public var isValid: Bool { width > 0 && height > 0 && width <= Self.maxDimension && height <= Self.maxDimension }

    public static let presets: [ExportSize] = [
        ExportSize(width: 7680, height: 4320, label: "8K"),
        ExportSize(width: 6016, height: 3384, label: "6K (Pro Display XDR)"),
        ExportSize(width: 5120, height: 2880, label: "5K (Studio Display, iMac 27″)"),
        ExportSize(width: 4480, height: 2520, label: "iMac 24″"),
        ExportSize(width: 3840, height: 2160, label: "4K UHD"),
        ExportSize(width: 3456, height: 2234, label: "MacBook Pro 16″"),
        ExportSize(width: 3024, height: 1964, label: "MacBook Pro 14″"),
        ExportSize(width: 2880, height: 1864, label: "MacBook Air 15″"),
        ExportSize(width: 2560, height: 1664, label: "MacBook Air 13″"),
    ]

    /// Native pixel size of the display the active window is on (`NSScreen.main`), falling back
    /// to the primary display.
    @MainActor
    public static func currentDisplay() -> ExportSize? {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return nil }
        let px = screen.convertRectToBacking(screen.frame).size
        return ExportSize(width: Int(px.width), height: Int(px.height), label: screen.localizedName)
    }

    /// Native pixel sizes of the connected displays.
    @MainActor
    public static func connectedDisplays() -> [ExportSize] {
        NSScreen.screens.map { screen in
            let px = screen.convertRectToBacking(screen.frame).size
            return ExportSize(width: Int(px.width), height: Int(px.height), label: screen.localizedName)
        }
    }
}
