import Foundation

/// An ordered list of colours. The renderer maps its noise field onto a gradient ramp that
/// runs through these colours in order, so order matters.
public struct Palette: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var colors: [RGBColor]

    public init(id: String, name: String, colors: [RGBColor]) {
        self.id = id
        self.name = name
        self.colors = colors
    }

    init(id: String, name: String, hex: [String]) {
        self.init(id: id, name: name, colors: hex.compactMap(RGBColor.init(hex:)))
    }

    /// Samples the palette into `count` evenly spaced OKLab stops, interpolating between
    /// neighbouring colours in OKLab. Zero colours yields mid grey; one colour is flat.
    public func ramp(count: Int) -> [OKLab] {
        precondition(count >= 2, "ramp needs at least two stops")
        let stops = colors.isEmpty ? [RGBColor(red: 0.5, green: 0.5, blue: 0.5)] : colors
        let labs = stops.map(OKLab.init)
        guard labs.count > 1 else { return Array(repeating: labs[0], count: count) }
        return (0..<count).map { i in
            let x = Double(i) / Double(count - 1) * Double(labs.count - 1)
            let lo = min(Int(x), labs.count - 2)
            return OKLab.mix(labs[lo], labs[lo + 1], x - Double(lo))
        }
    }
}

public extension Palette {
    static let aurora = Palette(id: "aurora", name: "Aurora",
                                hex: ["#071A3D", "#2B1B5A", "#4B2C83", "#0F6E78", "#1FA39A"])
    static let sunset = Palette(id: "sunset", name: "Sunset",
                                hex: ["#2A1240", "#6B1F5C", "#C2386B", "#F06F4A", "#F7A65B"])
    static let ocean = Palette(id: "ocean", name: "Ocean",
                               hex: ["#061A33", "#0B3D6B", "#0F6F8F", "#1BA3A8", "#5ED3C9"])
    static let ember = Palette(id: "ember", name: "Ember",
                               hex: ["#1A0507", "#4A0D16", "#7A1A1F", "#B23A1E", "#E08A2C"])
    static let forest = Palette(id: "forest", name: "Forest",
                                hex: ["#0A1F14", "#163826", "#3E5F43", "#7D8C68", "#B9A65A"])
    static let monochrome = Palette(id: "monochrome", name: "Monochrome",
                                    hex: ["#050505", "#1C1C1E", "#3A3A3C", "#7A7A7E", "#C7C7CC"])

    static let builtIns: [Palette] = [aurora, sunset, ocean, ember, forest, monochrome]

    static func builtIn(id: String) -> Palette? {
        builtIns.first { $0.id == id.lowercased() }
    }
}

extension Palette {
    /// Tolerant and sanitized: missing fields get defaults, 2–8 colours are kept (padding or
    /// truncating as needed).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? "custom"
        let name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Custom"
        var colors = ((try? c.decodeIfPresent([RGBColor].self, forKey: .colors)) ?? nil) ?? []
        if colors.isEmpty { colors = Palette.aurora.colors }
        if colors.count == 1 { colors.append(colors[0]) }
        self.init(id: String(id.prefix(64)), name: String(name.prefix(80)), colors: Array(colors.prefix(8)))
    }
}
