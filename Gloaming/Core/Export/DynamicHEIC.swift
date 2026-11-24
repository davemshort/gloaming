import CoreGraphics
import Foundation
import ImageIO

/// Writes macOS dynamic wallpapers: multi-image HEIC files with Apple's `apple_desktop` XMP
/// metadata.
///
/// ⚠️ Undocumented format. Writing uses only public ImageIO APIs, but the metadata schema
/// was reverse-engineered by the community (stable since macOS 10.14 Mojave). It is
/// isolated in this file so that if Apple changes it, only this file needs updating; still
/// exports never depend on it.
///
/// Schema used:
/// - `apple_desktop:h24` (time of day): base64 binary plist
///   `{ "ti": [ { "i": imageIndex, "t": fractionOfDay0to1 }, … ], "ap": { "l": i, "d": i } }`
/// - `apple_desktop:apr` (light/dark appearance): base64 binary plist `{ "l": i, "d": i }`
///   Not written alongside `h24`: macOS 27 then treats the file as appearance-based and
///   ignores the time schedule (Phase A, A-5c).
/// The metadata goes on the first image only.
public enum DynamicHEIC {
    public static let namespace = "http://ns.apple.com/namespace/1.0/"
    public static let prefix = "apple_desktop"

    public struct TimeEntry: Equatable, Sendable {
        public var imageIndex: Int
        /// Local clock time as a fraction of the day: 0 = midnight, 0.5 = noon.
        public var dayFraction: Double
        public init(imageIndex: Int, dayFraction: Double) {
            self.imageIndex = imageIndex
            self.dayFraction = dayFraction
        }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case noImages, badIndex, cannotCreateDestination, finalizeFailed, metadata
        public var description: String {
            switch self {
            case .noImages: "No images to write"
            case .badIndex: "Image index out of range"
            case .cannotCreateDestination: "Could not create HEIC file (is HEIC encoding available?)"
            case .finalizeFailed: "Could not finish writing the HEIC file"
            case .metadata: "Could not build wallpaper metadata"
            }
        }
    }

    // MARK: - Metadata values

    public static func h24Value(entries: [TimeEntry], lightIndex: Int, darkIndex: Int) throws -> String {
        let sorted = entries.sorted { $0.dayFraction < $1.dayFraction }
        let plist: [String: Any] = [
            "ti": sorted.map { ["i": $0.imageIndex, "t": $0.dayFraction] },
            "ap": ["l": lightIndex, "d": darkIndex],
        ]
        return try encode(plist)
    }

    /// One frame of a sun-position (solar) wallpaper. macOS shows the frame whose position is
    /// closest to the sun's actual position for the Mac's location and date (Location Services
    /// must be on; the app itself never needs location).
    public struct SolarEntry: Equatable, Sendable {
        public var imageIndex: Int
        /// Degrees above (+) or below (−) the horizon.
        public var altitude: Double
        /// Compass degrees clockwise from north (90 = east, 180 = south, 270 = west).
        public var azimuth: Double
        public init(imageIndex: Int, altitude: Double, azimuth: Double) {
            self.imageIndex = imageIndex
            self.altitude = altitude
            self.azimuth = azimuth
        }
    }

    /// `apple_desktop:solar`: base64 binary plist
    /// `{ "si": [ { "i": imageIndex, "a": altitude, "z": azimuth }, … ], "ap": { "l": i, "d": i } }`
    /// (community-documented schema, as used by Apple's own sun-position wallpapers).
    public static func solarValue(entries: [SolarEntry], lightIndex: Int, darkIndex: Int) throws -> String {
        let plist: [String: Any] = [
            "si": entries.map { ["i": $0.imageIndex, "a": $0.altitude, "z": $0.azimuth] },
            "ap": ["l": lightIndex, "d": darkIndex],
        ]
        return try encode(plist)
    }

    public static func aprValue(lightIndex: Int, darkIndex: Int) throws -> String {
        try encode(["l": lightIndex, "d": darkIndex])
    }

    private static func encode(_ plist: [String: Any]) throws -> String {
        try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0).base64EncodedString()
    }

    // MARK: - Writing

    /// Time-of-day wallpaper. `entries` map clock times to image indices; macOS shows the
    /// image of the most recent entry at or before the current time (wrapping at midnight).
    ///
    /// `appearanceTag` (default **off**) also writes a separate `apr` tag. Verified in Phase A
    /// on macOS 27.2.1, the two layouts behave differently:
    /// - `h24` only: System Settings shows **Dynamic** and the image follows the clock, but
    ///   "Light (Still)" / "Dark (Still)" ignore `ap` and keep the current frame.
    /// - `h24` + `apr`: System Settings shows **Automatic** and the image follows light/dark
    ///   **appearance, ignoring the time schedule**. The still choices then work.
    /// Time-of-day exports therefore write `h24` only.
    ///
    /// Frames are produced on demand by `frame(index)` and released after encoding, so peak
    /// memory stays around one frame regardless of frame count.
    public static func writeTimeOfDay(frameCount: Int, entries: [TimeEntry], lightIndex: Int, darkIndex: Int,
                                      appearanceTag: Bool = false, to url: URL, quality: Double = 0.9,
                                      frame: (Int) throws -> CGImage) throws {
        let range = 0..<frameCount
        guard frameCount > 0 else { throw Error.noImages }
        guard entries.allSatisfy({ range.contains($0.imageIndex) }),
              range.contains(lightIndex), range.contains(darkIndex) else { throw Error.badIndex }
        var tags = [("h24", try h24Value(entries: entries, lightIndex: lightIndex, darkIndex: darkIndex))]
        if appearanceTag { tags.append(("apr", try aprValue(lightIndex: lightIndex, darkIndex: darkIndex))) }
        try write(count: frameCount, tags: tags, to: url, quality: quality, frame: frame)
    }

    /// Sun-position wallpaper. Experimental (Phase A2): whether macOS 27 also needs `apr` for
    /// Light/Dark (Still), and whether `apr` overrides the sun as it did the clock, is under test.
    public static func writeSolar(frameCount: Int, entries: [SolarEntry], lightIndex: Int, darkIndex: Int,
                                  appearanceTag: Bool = false, to url: URL, quality: Double = 0.9,
                                  frame: (Int) throws -> CGImage) throws {
        let range = 0..<frameCount
        guard frameCount > 0 else { throw Error.noImages }
        guard entries.allSatisfy({ range.contains($0.imageIndex) }),
              range.contains(lightIndex), range.contains(darkIndex) else { throw Error.badIndex }
        var tags = [("solar", try solarValue(entries: entries, lightIndex: lightIndex, darkIndex: darkIndex))]
        if appearanceTag { tags.append(("apr", try aprValue(lightIndex: lightIndex, darkIndex: darkIndex))) }
        try write(count: frameCount, tags: tags, to: url, quality: quality, frame: frame)
    }

    public static func writeTimeOfDay(images: [CGImage], entries: [TimeEntry], lightIndex: Int, darkIndex: Int,
                                      appearanceTag: Bool = false, to url: URL, quality: Double = 0.9) throws {
        try writeTimeOfDay(frameCount: images.count, entries: entries, lightIndex: lightIndex, darkIndex: darkIndex,
                           appearanceTag: appearanceTag, to: url, quality: quality) { images[$0] }
    }

    /// Light/dark wallpaper that follows the system appearance (image 0 light, 1 dark).
    public static func writeAppearance(to url: URL, quality: Double = 0.9,
                                       frame: (Int) throws -> CGImage) throws {
        try write(count: 2, tags: [("apr", try aprValue(lightIndex: 0, darkIndex: 1))],
                  to: url, quality: quality, frame: frame)
    }

    public static func writeAppearance(light: CGImage, dark: CGImage, to url: URL, quality: Double = 0.9) throws {
        try writeAppearance(to: url, quality: quality) { $0 == 0 ? light : dark }
    }

    /// Atomic (temporary file, then move). Metadata goes on image 0.
    private static func write(count: Int, tags: [(key: String, value: String)], to url: URL, quality: Double,
                              frame: (Int) throws -> CGImage) throws {
        guard count > 0 else { throw Error.noImages }
        var compressIntermediates = false
        let metadata = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace as CFString, prefix as CFString, nil) else {
            throw Error.metadata
        }
        for (key, value) in tags {
            guard let tag = CGImageMetadataTagCreate(namespace as CFString, prefix as CFString, key as CFString,
                                                     .string, value as CFString),
                  CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(key)" as CFString, tag) else {
                throw Error.metadata
            }
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        try ImageFiles.writeAtomically(to: url) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, "public.heic" as CFString, count, nil) else {
                throw Error.cannotCreateDestination
            }
            for index in 0..<count {
                try autoreleasepool {
                    let image = try frame(index)
                    if index == 0 {
                        compressIntermediates = image.bytesPerRow * image.height * count > rawMemoryBudget
                    }
                    if index > 0 && compressIntermediates {
                        // ImageIO keeps every added image until finalize. Handing it a small
                        // compressed source instead of raw pixels bounds peak memory.
                        // Frame 0 keeps the direct path because it carries the metadata.
                        let source = try compressedSource(image, quality: quality)
                        CGImageDestinationAddImageFromSource(dest, source, 0, options)
                    } else if index == 0 {
                        CGImageDestinationAddImageAndMetadata(dest, image, metadata, options)
                    } else {
                        CGImageDestinationAddImage(dest, image, options)
                    }
                }
            }
            guard CGImageDestinationFinalize(dest) else { throw Error.finalizeFailed }
        }
    }

    /// Above this many raw pixel bytes in total, frames after the first are handed to ImageIO
    /// as in-memory HEIC instead of raw pixels. Measured at 6K × 12 frames: peak footprint
    /// 1463 MB direct vs 801 MB compressed; the cost is a second lossy encode on those frames
    /// (mean 0.2, max 5 levels of 255). Below the budget the direct path is used (one encode).
    /// 512 MB keeps 6K × 12 frames on the compressed path (a 1 GB budget let it peak at 1.38 GB).
    public static let rawMemoryBudget = 512 << 20

    private static func compressedSource(_ image: CGImage, quality: Double) throws -> CGImageSource {
        let data = NSMutableData()
        guard let d = CGImageDestinationCreateWithData(data, "public.heic" as CFString, 1, nil) else {
            throw Error.cannotCreateDestination
        }
        CGImageDestinationAddImage(d, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(d), let src = CGImageSourceCreateWithData(data, nil) else {
            throw Error.finalizeFailed
        }
        return src
    }

    // MARK: - Reading (tests, diagnostics)

    public struct Info: Sendable {
        public var imageCount: Int
        public var h24: [String: Any]? { decode(h24Raw) }
        public var apr: [String: Any]? { decode(aprRaw) }
        public var h24Raw: String?
        public var aprRaw: String?
        public var solarRaw: String? = nil
        public var solar: [String: Any]? { decode(solarRaw) }

        private func decode(_ s: String?) -> [String: Any]? {
            guard let s, let data = Data(base64Encoded: s) else { return nil }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
        }
    }

    public static func read(_ url: URL) -> Info? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let meta = CGImageSourceCopyMetadataAtIndex(source, 0, nil)
        func value(_ key: String) -> String? {
            guard let meta, let tag = CGImageMetadataCopyTagWithPath(meta, nil, "\(prefix):\(key)" as CFString) else { return nil }
            return CGImageMetadataTagCopyValue(tag) as? String
        }
        return Info(imageCount: CGImageSourceGetCount(source), h24Raw: value("h24"), aprRaw: value("apr"),
                    solarRaw: value("solar"))
    }
}
