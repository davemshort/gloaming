import CoreGraphics
import Foundation
import ImageIO

/// File writing helpers shared by all export formats.
///
/// - Every file is written to a temporary name in the destination folder and then moved into
///   place, so a failed export never leaves a partial image that macOS might try to load.
/// - Names are never reused: macOS caches wallpapers by file URL, and overwriting silently
///   would also lose the user's earlier export.
public enum ImageFiles {
    public enum Format: String, CaseIterable, Sendable {
        case png, heic
        var uti: String { self == .png ? "public.png" : "public.heic" }
        public var fileExtension: String { rawValue }
    }

    public enum Error: Swift.Error, CustomStringConvertible {
        case cannotCreate(URL), finalizeFailed(URL)
        public var description: String {
            switch self {
            case .cannotCreate(let u): "Could not create \(u.lastPathComponent)"
            case .finalizeFailed(let u): "Could not finish writing \(u.lastPathComponent)"
            }
        }
    }

    /// Default export folder: ~/Pictures/Gloaming. Not used by tests or the CLI.
    public static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Pictures/Gloaming", isDirectory: true)
    }

    /// `directory/baseName.ext`, or `baseName 2.ext`, `baseName 3.ext`, … if taken.
    public static func uniqueURL(in directory: URL, baseName: String, fileExtension: String) -> URL {
        let safe = baseName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
        var candidate = directory.appendingPathComponent("\(safe).\(fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(safe) \(n).\(fileExtension)")
            n += 1
        }
        return candidate
    }

    /// Writes via a temporary file in the same folder, then moves it to `url`.
    public static func writeAtomically(to url: URL, _ body: (URL) throws -> Void) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let temp = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.deletingPathExtension().lastPathComponent).partial-\(UUID().uuidString).\(url.pathExtension)")
        do {
            try body(temp)
            try FileManager.default.moveItem(at: temp, to: url)
        } catch {
            try? FileManager.default.removeItem(at: temp)
            throw error
        }
    }

    /// Writes a single image (PNG lossless, or HEIC at `quality`).
    public static func writeStill(_ image: CGImage, format: Format, quality: Double, to url: URL) throws {
        try writeAtomically(to: url) { temp in
            guard let dest = CGImageDestinationCreateWithURL(temp as CFURL, format.uti as CFString, 1, nil) else {
                throw Error.cannotCreate(url)
            }
            let options: CFDictionary? = format == .heic
                ? [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary : nil
            CGImageDestinationAddImage(dest, image, options)
            guard CGImageDestinationFinalize(dest) else { throw Error.finalizeFailed(url) }
        }
    }
}
