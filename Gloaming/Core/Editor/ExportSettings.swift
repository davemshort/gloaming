import Foundation

/// What the export sheet produces. Remembered between launches (UserDefaults).
public struct ExportSettings: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case sunPosition, timeOfDay, lightDark, stillPNG, stillHEIC, variations

        public var title: String {
            switch self {
            case .sunPosition: "Dynamic (follows the sun)"
            case .timeOfDay: "Dynamic (follows the clock)"
            case .lightDark: "Light & Dark (follows appearance)"
            case .stillPNG: "Still image (PNG)"
            case .stillHEIC: "Still image (HEIC)"
            case .variations: "Variations (several stills)"
            }
        }
    }

    public var kind: Kind = .sunPosition
    public var size: ExportSize?          // nil = the display the editor window is on
    public var frames: Int = 12
    public var variations: Int = 6
    public var directoryPath: String = ImageFiles.defaultDirectory.path

    public init() {}

    public var directory: URL { URL(fileURLWithPath: directoryPath, isDirectory: true) }

    static let defaultsKey = "ExportSettings"

    public static func load(from defaults: UserDefaults = .standard) -> ExportSettings {
        guard let data = defaults.data(forKey: defaultsKey),
              let s = try? JSONDecoder().decode(ExportSettings.self, from: data) else { return ExportSettings() }
        return s
    }

    public func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}
