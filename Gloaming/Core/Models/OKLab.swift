import Foundation

/// A colour in Björn Ottosson's OKLab space (https://bottosson.github.io/posts/oklab/).
/// Palette interpolation happens here because straight lines in OKLab look perceptually
/// even and don't dip through muddy greys the way sRGB interpolation does.
public struct OKLab: Hashable, Sendable {
    public var L: Double
    public var a: Double
    public var b: Double

    public init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    public init(_ c: RGBColor) {
        let r = OKLab.toLinear(c.red), g = OKLab.toLinear(c.green), bl = OKLab.toLinear(c.blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)
        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    /// Converts back to gamma-encoded sRGB, clamping out-of-gamut values.
    public var rgb: RGBColor {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        let r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
        return RGBColor(red: OKLab.toEncoded(r), green: OKLab.toEncoded(g), blue: OKLab.toEncoded(bl))
    }

    /// From lightness, chroma and hue in degrees (OKLCh).
    public init(L: Double, chroma: Double, hueDegrees: Double) {
        let h = hueDegrees * .pi / 180
        self.init(L: L, a: chroma * cos(h), b: chroma * sin(h))
    }

    /// Unclamped linear sRGB.
    var linearRGB: (Double, Double, Double) {
        let l_ = L + 0.3963377774 * a + 0.2158037573 * b
        let m_ = L - 0.1055613458 * a - 0.0638541728 * b
        let s_ = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    public var isInSRGBGamut: Bool {
        let (r, g, b) = linearRGB
        let e = 1e-6
        return r >= -e && r <= 1 + e && g >= -e && g <= 1 + e && b >= -e && b <= 1 + e
    }

    /// Reduces chroma (keeping lightness and hue) until the colour fits in sRGB.
    public func gamutMapped() -> OKLab {
        if isInSRGBGamut { return self }
        var lo = 0.0, hi = 1.0
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if OKLab(L: L, a: a * mid, b: b * mid).isInSRGBGamut { lo = mid } else { hi = mid }
        }
        return OKLab(L: L, a: a * lo, b: b * lo)
    }

    public static func mix(_ x: OKLab, _ y: OKLab, _ t: Double) -> OKLab {
        OKLab(L: x.L + (y.L - x.L) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    static func toLinear(_ c: Double) -> Double {
        let c = min(max(c, 0), 1)
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    static func toEncoded(_ c: Double) -> Double {
        let c = min(max(c, 0), 1)
        return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
}
