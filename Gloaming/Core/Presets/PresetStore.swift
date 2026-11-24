import Foundation
import Observation

/// The user's own presets, stored one file per preset as `<UUID>.gloamingpreset` in a directory
/// (default: ~/Library/Application Support/Gloaming/Presets).
///
/// - Files are named by UUID, with the preset's name stored inside, so renaming never touches
///   the filesystem and names can't collide.
/// - Writes are atomic; deletes go to the Trash (configurable for tests).
/// - Unreadable files are skipped and reported in `loadErrors`, never deleted.
/// - `directory == nil` keeps presets in memory only (tests, previews).
@MainActor
@Observable
public final class PresetStore {
    public let directory: URL?
    public private(set) var presets: [Preset] = []
    public private(set) var loadErrors: [String] = []
    @ObservationIgnored private let deletesToTrash: Bool

    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gloaming/Presets", isDirectory: true)
    }

    public init(directory: URL?, deletesToTrash: Bool = true) {
        self.directory = directory
        self.deletesToTrash = deletesToTrash
        reload()
    }

    /// Moves presets saved under the app's former name into `directory`, if there are any and
    /// the new folder doesn't exist yet. Returns true if it moved something.
    @discardableResult
    public static func migrateLegacyDirectory(to directory: URL, from legacy: URL = PresetStore.legacyDirectory) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: directory.path) else { return false }
        do {
            try fm.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: legacy, to: directory)
            return true
        } catch {
            return false
        }
    }

    public static var legacyDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicWallpaper/Presets", isDirectory: true)
    }

    public func preset(id: UUID) -> Preset? { presets.first { $0.id == id } }

    public func reload() {
        guard let directory else { return }
        loadErrors = []
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [Preset] = []
        for url in files where Preset.readableFileExtensions.contains(url.pathExtension) {
            do {
                var p = try Preset.decode(fileData: try Data(contentsOf: url))
                p.category = .mine
                loaded.append(p)
            } catch {
                loadErrors.append("\(url.lastPathComponent): \(error)")
            }
        }
        presets = Self.sorted(loaded)
    }

    /// Saves (creates or replaces) a user preset.
    public func save(_ preset: Preset) throws {
        var p = preset
        p.category = .mine
        p.formatVersion = Preset.currentFormatVersion
        if let directory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try p.fileData().write(to: fileURL(p.id, in: directory), options: .atomic)
        }
        presets.removeAll { $0.id == p.id }
        presets = Self.sorted(presets + [p])
    }

    public func rename(id: UUID, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var p = preset(id: id), !trimmed.isEmpty else { return }
        p.name = String(trimmed.prefix(80))
        try save(p)
    }

    /// Copies any preset (built-in or user) into My Presets with a new identity.
    @discardableResult
    public func duplicate(_ preset: Preset) throws -> Preset {
        let copy = Preset(name: uniqueName(preset.isBuiltIn ? preset.name : "\(preset.name) Copy"),
                          category: .mine, look: preset.look)
        try save(copy)
        return copy
    }

    public func delete(id: UUID) throws {
        if let directory {
            let url = fileURL(id, in: directory)
            if FileManager.default.fileExists(atPath: url.path) {
                if deletesToTrash {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: url)
                }
            }
        }
        presets.removeAll { $0.id == id }
    }

    /// Imports a shared `.gloamingpreset` file into My Presets. A new ID is assigned if one with the
    /// same ID already exists, so importing never overwrites.
    @discardableResult
    public func importPreset(from url: URL) throws -> Preset {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = attrs[.size] as? Int, size > Preset.maxFileSize { throw Preset.FileError.tooLarge(size) }
        var p = try Preset.decode(fileData: try Data(contentsOf: url))
        if preset(id: p.id) != nil || Preset.builtIn(id: p.id) != nil { p.id = UUID() }
        p.category = .mine
        try save(p)
        return p
    }

    /// Writes a preset (any category) to a shareable file.
    public func exportPreset(_ preset: Preset, to url: URL) throws {
        try preset.fileData().write(to: url, options: .atomic)
    }

    public func uniqueName(_ base: String) -> String {
        let names = Set(presets.map(\.name))
        guard names.contains(base) else { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }

    private func fileURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString).\(Preset.fileExtension)")
    }

    private static func sorted(_ p: [Preset]) -> [Preset] {
        p.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
