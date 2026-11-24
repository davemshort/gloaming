import Foundation

/// SplitMix64: small, fast, seedable. Deterministic so randomize results are testable.
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }
    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public enum RandomizeKind: String, CaseIterable, Sendable {
    case everything, colors, movement
}

/// Generates tasteful random looks.
///
/// Palettes always run dark → light with a real lightness spread, because the shader maps its
/// noise field onto the ramp in order; random lightness order would look muddy. Hues follow a
/// harmony (analogous, split-complementary or triadic), and every colour is mapped into sRGB.
public enum Randomizer {
    public static func palette<G: RandomNumberGenerator>(using rng: inout G) -> Palette {
        let count = Int.random(in: 4...5, using: &rng)
        let baseHue = Double.random(in: 0..<360, using: &rng)
        let scheme = Int.random(in: 0..<3, using: &rng)
        let spread: Double = switch scheme {
        case 0: Double.random(in: 35...70, using: &rng)      // analogous
        case 1: Double.random(in: 140...200, using: &rng)    // split-complementary
        default: Double.random(in: 100...130, using: &rng)   // triadic-ish
        }
        let darkL = Double.random(in: 0.14...0.24, using: &rng)
        let lightL = Double.random(in: 0.70...0.86, using: &rng)
        let peakChroma = Double.random(in: 0.09...0.17, using: &rng)

        let colors = (0..<count).map { i -> RGBColor in
            let t = Double(i) / Double(count - 1)
            let L = darkL + (lightL - darkL) * t
            // Chroma peaks in the mid tones; very dark and very light stops stay calmer.
            let chroma = peakChroma * (0.45 + 0.55 * sin(.pi * min(1, t * 1.1)))
            let hue = baseHue + spread * t + Double.random(in: -8...8, using: &rng)
            return OKLab(L: L, chroma: chroma, hueDegrees: hue).gamutMapped().rgb
        }
        return Palette(id: "custom", name: "Custom", colors: colors)
    }

    public static func movement<G: RandomNumberGenerator>(_ p: RenderParameters, using rng: inout G) -> RenderParameters {
        var p = p
        p.speed = Double.random(in: 0.5...1.5, using: &rng)
        p.complexity = Double.random(in: 0.2...0.85, using: &rng)
        p.blend = Double.random(in: 0.35...0.85, using: &rng)
        return p
    }

    public static func apply<G: RandomNumberGenerator>(_ kind: RandomizeKind, to look: Look, using rng: inout G) -> Look {
        var l = look
        switch kind {
        case .colors:
            l.palette = palette(using: &rng)
        case .movement:
            l.parameters = movement(l.parameters, using: &rng)
            l.seed = UInt32.random(in: 0...100_000, using: &rng)
        case .everything:
            l.palette = palette(using: &rng)
            l.parameters = movement(l.parameters, using: &rng)
            l.parameters.grain = Double.random(in: 0.1...0.4, using: &rng)
            l.seed = UInt32.random(in: 0...100_000, using: &rng)
        }
        return l
    }
}
