import Foundation

/// Maps clock times on a reference day to sun positions, so a day arc designed against the
/// clock (night at midnight, dawn in the morning, …) can be exported as a sun-position
/// wallpaper.
///
/// Reference: latitude 40° N at an equinox (sun rises due east at 06:00, sets due west at
/// 18:00, peaks at 50° due south). macOS then shows, for the user's real location and date,
/// the frame whose reference position is closest to the actual sun, so dawn colours appear
/// at the real sunrise, dusk colours at the real sunset, and so on through the seasons.
public enum SunPath {
    /// 40° N. A 55° N reference (35° noon) was tried on 2026-11-23 and simulated against the
    /// real sun at ~36° N in late November: midday frame choice was identical (azimuth keeps a
    /// low, due-south sun on the noon frame), but dusk and night arrived ~30 min late, so 40° N stays.
    public static let referenceLatitude: Double = 40

    public struct Position: Equatable, Sendable {
        /// Degrees above (+) / below (−) the horizon.
        public var altitude: Double
        /// Compass degrees clockwise from north, 0..<360.
        public var azimuth: Double
    }

    /// Sun position at local solar time `dayFraction` (0 = midnight, 0.5 = noon).
    public static func position(atDayFraction dayFraction: Double, latitude: Double = referenceLatitude) -> Position {
        let f = dayFraction - floor(dayFraction)
        let rad = Double.pi / 180
        let phi = latitude * rad
        let hourAngle = (f * 24 - 12) * 15 * rad          // declination 0 (equinox)
        let altitude = asin(cos(phi) * cos(hourAngle)) / rad
        var azimuth = atan2(sin(hourAngle), cos(hourAngle) * sin(phi)) / rad + 180
        azimuth = azimuth.truncatingRemainder(dividingBy: 360)
        if azimuth < 0 { azimuth += 360 }
        // Round so files are tidy and comparisons stable.
        return Position(altitude: (altitude * 100).rounded() / 100, azimuth: (azimuth * 100).rounded() / 100)
    }
}
