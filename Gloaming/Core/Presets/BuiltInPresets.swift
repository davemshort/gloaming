import Foundation

/// The built-in preset library, defined in code (SwiftPM resource bundles don't survive the
/// hand-assembled .app). Every palette runs dark → light, which the shader relies on; tests
/// check this and round-trip every preset through the file format.
///
/// Season presets carry palette keyframes for night, morning and evening. Noon has no
/// palette override, so the noon frame of a Dynamic export matches the preview and stills.
public extension Preset {
    static let builtIns: [Preset] = moods + seasons + vibes

    static func builtIn(id: UUID) -> Preset? { builtIns.first { $0.id == id } }

    // MARK: Moods

    static let moods: [Preset] = [
        make("calm", "Calm", .mood,
             palette(["#0E1A2B", "#23324F", "#4A5F8A", "#8A9CC7", "#C9D3EC"]),
             speed: 0.6, complexity: 0.3, blend: 0.85, grain: 0.2, seed: 11),
        make("focus", "Focus", .mood,
             palette(["#081417", "#10282C", "#1E4A4F", "#3F7A7C", "#8FB8B3"]),
             speed: 0.45, complexity: 0.25, blend: 0.75, grain: 0.15, saturation: 0.85, seed: 23),
        make("energize", "Energize", .mood,
             palette(["#2A0A3D", "#7A1458", "#D2335C", "#F77F3B", "#FFC85C"]),
             speed: 1.4, complexity: 0.7, blend: 0.45, grain: 0.3, seed: 37),
        make("dreamy", "Dreamy", .mood,
             palette(["#1B1030", "#3E2A63", "#7A5AA6", "#C29BD8", "#F1D3EC"]),
             speed: 0.7, complexity: 0.4, blend: 0.9, grain: 0.25, seed: 41),
    ]

    // MARK: Seasons (with palette keyframes)

    static let seasons: [Preset] = [
        make("winter", "Winter", .season,
             palette(["#0D1B2E", "#2B4766", "#6E93B8", "#B9D2E6", "#EEF4FA"]),
             speed: 0.6, complexity: 0.35, blend: 0.8, grain: 0.2, seed: 101,
             arc: seasonArc(night: ["#03060F", "#0A1430", "#1B2B57", "#3A4F86", "#7487B8"],
                            morning: ["#1A1830", "#4A3A62", "#9A7FA6", "#E2B8C6", "#F7E6E4"],
                            evening: ["#120E2A", "#2E2557", "#5B4C8C", "#9C8CC4", "#D6CDEB"])),
        make("spring", "Spring", .season,
             palette(["#16301F", "#2F5E3C", "#6FA36A", "#B8D98F", "#F2F0C9"]),
             speed: 0.8, complexity: 0.45, blend: 0.7, grain: 0.2, seed: 131,
             arc: seasonArc(night: ["#060B12", "#0F1C26", "#1D3641", "#36585E", "#668A86"],
                            morning: ["#2A2238", "#5C4A6E", "#B98BAA", "#EDBFC8", "#FBEDE6"],
                            evening: ["#1E1E33", "#3C3B5E", "#7A6E9A", "#C2A9C9", "#EDDDE6"])),
        make("summer", "Summer", .season,
             palette(["#0A2A3A", "#0F5A6B", "#1FA3A3", "#F2B880", "#FFE3B3"]),
             speed: 1.0, complexity: 0.5, blend: 0.65, grain: 0.25, seed: 151,
             arc: seasonArc(night: ["#04101A", "#0A2233", "#123F55", "#1E6372", "#3D8C8C"],
                            morning: ["#1C2340", "#3D4F7A", "#7FA6C9", "#F2C6A0", "#FFF0D6"],
                            evening: ["#2A1035", "#6B1E4F", "#C2465E", "#F28A4B", "#FFD08A"])),
        make("autumn", "Autumn", .season,
             palette(["#2A0F0A", "#6B2410", "#B5531C", "#E09A3E", "#F4D58D"]),
             speed: 0.8, complexity: 0.5, blend: 0.65, grain: 0.3, seed: 173,
             arc: seasonArc(night: ["#0A0608", "#1E1015", "#3A1F24", "#5E3A33", "#8A6248"],
                            morning: ["#1F1A24", "#4D3A3A", "#9A6A4F", "#D8A677", "#F2DDB8"],
                            evening: ["#1E0A1C", "#4A1530", "#8C2F3A", "#C9653A", "#EBAA5B"])),
    ]

    // MARK: Vibes (the original six palettes)

    static let vibes: [Preset] = [
        make("aurora", "Aurora", .vibe, .aurora, seed: 0),
        make("sunset", "Sunset", .vibe, .sunset, seed: 5),
        make("ocean", "Ocean", .vibe, .ocean, seed: 3),
        make("ember", "Ember", .vibe, .ember, seed: 9),
        make("forest", "Forest", .vibe, .forest, seed: 2),
        make("monochrome", "Monochrome", .vibe, .monochrome, grain: 0.35, saturation: 1, seed: 7),
        // Added after Phase D review. New entries go at the end so existing indices stay put.
        make("spooky", "Spooky", .vibe,
             palette(["#07050A", "#1E0B2B", "#3D1450", "#C2561A", "#F2A33A"]),
             speed: 0.7, complexity: 0.65, blend: 0.5, grain: 0.4, seed: 1031),
        make("neon", "Neon", .vibe,
             palette(["#0A0520", "#3A0C78", "#C21896", "#FF5FB0", "#7DF4FF"]),
             speed: 1.2, complexity: 0.6, blend: 0.3, grain: 0.25, seed: 77),
        make("nebula", "Nebula", .vibe,
             palette(["#05030F", "#1A1240", "#40237A", "#8E4FB8", "#F0A6CF"]),
             speed: 0.6, complexity: 0.7, blend: 0.7, grain: 0.35, seed: 404),
        make("desert", "Desert", .vibe,
             palette(["#2B1A12", "#6B3F24", "#B87A47", "#E0B07A", "#F6E2BF"]),
             speed: 0.6, complexity: 0.35, blend: 0.8, grain: 0.3, seed: 52),
        make("pastel", "Pastel", .vibe,
             palette(["#6A6AA8", "#9A9FD8", "#C9B4E6", "#F5B8CF", "#FFE2C4"]),
             speed: 0.7, complexity: 0.35, blend: 0.55, grain: 0.15, seed: 219),
    ]

    // MARK: Helpers

    private static func palette(_ hex: [String], id: String = "", name: String = "") -> Palette {
        Palette(id: id, name: name, colors: hex.compactMap(RGBColor.init(hex:)))
    }

    private static func seasonArc(night: [String], morning: [String], evening: [String]) -> DayArc {
        DayArc(keyframes: [
            .init(dayFraction: 0.0, brightness: 0.6, saturation: 0.9, palette: palette(night, id: "night", name: "Night")),
            .init(dayFraction: 0.27, brightness: 0.85, saturation: 0.95, palette: palette(morning, id: "morning", name: "Morning")),
            .init(dayFraction: 0.5, brightness: 1.0, saturation: 1.0),
            .init(dayFraction: 0.77, brightness: 0.85, saturation: 1.05, palette: palette(evening, id: "evening", name: "Evening")),
        ], motion: DayArc.standard.motion)
    }

    /// Stable IDs derived from the slug so built-ins keep their identity across launches.
    private static func stableID(_ slug: String) -> UUID {
        var bytes = [UInt8](repeating: 0, count: 16)
        for (i, b) in "gloamingpreset-\(slug)".utf8.enumerated() { bytes[i % 16] = bytes[i % 16] &* 31 &+ b }
        bytes[6] = (bytes[6] & 0x0F) | 0x40   // version 4 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private static func make(_ slug: String, _ name: String, _ category: Category, _ palette: Palette,
                             speed: Double = 1, complexity: Double = 0.5, blend: Double = 0.6, grain: Double = 0.25,
                             saturation: Double = 1, seed: UInt32, arc: DayArc = .standard) -> Preset {
        var p = RenderParameters()
        p.speed = speed
        p.complexity = complexity
        p.blend = blend
        p.grain = grain
        p.saturation = saturation
        var pal = palette
        if pal.id.isEmpty { pal.id = slug; pal.name = name }
        return Preset(id: stableID(slug), name: name, category: category,
                      look: Look(palette: pal, parameters: p, seed: seed, time: 0, dayArc: arc))
    }
}
