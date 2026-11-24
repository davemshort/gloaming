import Foundation

/// Maps clock times on a design day to sun positions, so a day arc designed against the clock
/// (night at midnight, dawn in the morning, …) can be exported as a sun-position wallpaper.
///
/// macOS appears to pick the frame whose **altitude** is nearest the real sun's, among frames
/// on the same side of solar noon (morning: azimuth < 180°, afternoon: > 180°). Observed
/// 2026-11-24, see Documentation/PhaseA2-Solar.md. So altitudes are chosen by *light*, not by
/// a reference latitude: twilight, sunrise and sunset happen at the same altitudes everywhere,
/// so those frames land at the real dawn and dusk at any location and season. Midday frames
/// sit low enough (28° for noon) that a winter sun at mid-latitudes still reaches them.
///
/// Azimuths only mark the side; they follow a 40° N equinox path (east at 06:00, south at noon,
/// west at 18:00).
public enum SunPath {
    /// Clock hour → altitude for the morning half (mirrored for the afternoon), interpolated
    /// linearly and strictly increasing so no two same-side frames share an altitude.
    /// Frames switch halfway between neighbouring tags, which sets the timing:
    /// - 06:00 dawn/dusk −4° and 08:00 golden +5°: switch at +0.5°, a few minutes before sunset.
    /// - 04:00 −12° (nautical twilight): blue hour from −8°.
    /// - 10:00 +15°, 12:00 +28°: noon look above 21.5°, reached by the winter sun up to ~45°
    ///   latitude; further north in winter the 10:00/14:00 looks cover midday.
    public static let anchors: [(hour: Double, altitude: Double)] = [
        (0, -50), (2, -30), (4, -12), (6, -4), (8, 5), (10, 15), (12, 28),
    ]

    public struct Position: Equatable, Sendable {
        /// Degrees above (+) / below (−) the horizon.
        public var altitude: Double
        /// Compass degrees clockwise from north, 0..<360.
        public var azimuth: Double
    }

    /// Sun position tagged on the frame for clock time `dayFraction` (0 = midnight, 0.5 = noon).
    public static func position(atDayFraction dayFraction: Double) -> Position {
        let f = dayFraction - floor(dayFraction)
        let hour = f * 24
        return Position(altitude: round2(altitude(atHour: hour)), azimuth: round2(azimuth(atHour: hour)))
    }

    /// Solar entries for frames at `fractions`. macOS counts an azimuth of exactly 180° as
    /// morning (observed 2026-11-24: the noon frame never showed after solar noon), and 0° as
    /// morning too. So a frame at exactly noon or midnight gets a second entry on the
    /// afternoon side (same altitude, azimuth just past 180° / just before 360°), letting it
    /// show on both sides of solar noon / midnight.
    public static func solarEntries(forDayFractions fractions: [Double]) -> [(imageIndex: Int, position: Position)] {
        var entries: [(Int, Position)] = []
        for (i, f) in fractions.enumerated() {
            let p = position(atDayFraction: f)
            entries.append((i, p))
            if p.azimuth == 180 { entries.append((i, Position(altitude: p.altitude, azimuth: afternoonNoonAzimuth))) }
            if p.azimuth == 0 { entries.append((i, Position(altitude: p.altitude, azimuth: afternoonMidnightAzimuth))) }
        }
        return entries
    }

    static let afternoonNoonAzimuth = 181.0
    static let afternoonMidnightAzimuth = 359.0

    static func altitude(atHour hour: Double) -> Double {
        let h = hour > 12 ? 24 - hour : hour          // mirror the afternoon onto the morning
        for (a, b) in zip(anchors, anchors.dropFirst()) where h <= b.hour {
            return a.altitude + (b.altitude - a.altitude) * (h - a.hour) / (b.hour - a.hour)
        }
        return anchors.last!.altitude
    }

    static func azimuth(atHour hour: Double) -> Double {
        let rad = Double.pi / 180
        let hourAngle = (hour - 12) * 15 * rad
        var azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(40 * rad)) / rad + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        return azimuth
    }

    /// Round so files are tidy and comparisons stable.
    private static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
