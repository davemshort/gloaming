import Foundation

/// A named, complete look (palette, parameters, seed, moment, day arc) that can be saved and
/// shared as a `.gloamingpreset` file (versioned JSON).
public struct Preset: Codable, Identifiable, Hashable, Sendable {
    public enum Category: String, Codable, CaseIterable, Sendable {
        case mood, season, vibe, mine

        public var title: String {
            switch self {
            case .mood: "Moods"
            case .season: "Seasons"
            case .vibe: "Vibes"
            case .mine: "My Presets"
            }
        }
    }

    /// Bump when the file format changes incompatibly; older apps refuse newer files.
    public static let currentFormatVersion = 1
    public static let fileExtension = "gloamingpreset"
    /// Extensions from before the app was renamed (DynamicWallpaper → Gloaming); still read.
    public static let legacyFileExtensions = ["dwpreset"]
    public static var readableFileExtensions: [String] { [fileExtension] + legacyFileExtensions }

    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var category: Category
    public var look: Look

    public init(id: UUID = UUID(), name: String, category: Category, look: Look) {
        self.formatVersion = Self.currentFormatVersion
        self.id = id
        self.name = name
        self.category = category
        self.look = look
    }

    public var isBuiltIn: Bool { category != .mine }

    public enum FileError: Swift.Error, Equatable, CustomStringConvertible {
        case tooLarge(Int), unsupportedVersion(Int), notAPreset
        public var description: String {
            switch self {
            case .tooLarge(let n): "The file is too large to be a preset (\(n / 1024) KB)."
            case .unsupportedVersion(let v): "This preset was made with a newer version of the app (format \(v)). Please update to open it."
            case .notAPreset: "The file isn't a Gloaming preset."
            }
        }
    }

    /// Presets are a few KB; anything much larger is refused before parsing.
    public static let maxFileSize = 1 << 20

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let version = try? c.decode(Int.self, forKey: .formatVersion) else { throw FileError.notAPreset }
        guard version <= Self.currentFormatVersion else { throw FileError.unsupportedVersion(version) }
        formatVersion = Self.currentFormatVersion
        id = ((try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        let rawName = ((try? c.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? "Untitled"
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        name = trimmed.isEmpty ? "Untitled" : String(trimmed.prefix(80))
        category = ((try? c.decodeIfPresent(Category.self, forKey: .category)) ?? nil) ?? .mine
        look = ((try? c.decodeIfPresent(Look.self, forKey: .look)) ?? nil) ?? Look(palette: .aurora)
    }

    // MARK: - File format

    public func fileData() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try e.encode(self)
    }

    public static func decode(fileData data: Data) throws -> Preset {
        guard data.count <= maxFileSize else { throw FileError.tooLarge(data.count) }
        do {
            return try JSONDecoder().decode(Preset.self, from: data)
        } catch let e as FileError {
            throw e
        } catch {
            throw FileError.notAPreset
        }
    }
}
