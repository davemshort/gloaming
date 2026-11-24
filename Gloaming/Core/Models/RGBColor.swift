import Foundation

/// A gamma-encoded sRGB colour with components in 0...1. This is what users pick and what
/// palettes store; rendering converts to OKLab / linear sRGB.
public struct RGBColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses "#RRGGBB" or "RRGGBB". Returns nil for anything else.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    public var hexString: String {
        func c(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", c(red), c(green), c(blue))
    }
}

extension RGBColor {
    /// Tolerant: missing or non-finite components become 0; values are clamped to 0…1.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func v(_ k: CodingKeys) -> Double {
            Sanitize.clamp((try? c.decodeIfPresent(Double.self, forKey: k)) ?? 0, 0...1, fallback: 0)
        }
        self.init(red: v(.red), green: v(.green), blue: v(.blue))
    }
}

/// Shared sanitizing helpers for decoding untrusted files (shared presets).
enum Sanitize {
    static func finite(_ x: Double, _ fallback: Double) -> Double { x.isFinite ? x : fallback }
    static func clamp(_ x: Double, _ range: ClosedRange<Double>, fallback: Double) -> Double {
        min(max(finite(x, fallback), range.lowerBound), range.upperBound)
    }
}
