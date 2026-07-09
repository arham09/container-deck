import Foundation
import Observation

/// A named, persisted run configuration (spec §7 Phase 7). The format is
/// versioned for import/export. Environment **values** are never persisted —
/// only keys — so secrets cannot leak into saved files (spec §8); users
/// re-enter values after applying a saved configuration.
public struct SavedRunConfiguration: Sendable, Equatable, Identifiable, Codable {
    public static let currentFormatVersion = 1

    public var id: UUID
    public var name: String
    public var savedAt: Date
    public var configuration: ContainerRunConfiguration

    public init(id: UUID = UUID(), name: String, savedAt: Date = Date(), configuration: ContainerRunConfiguration) {
        self.id = id
        self.name = name
        self.savedAt = savedAt
        var sanitized = configuration
        // Keys survive; values are stripped before persistence.
        sanitized.environment = configuration.environment.map {
            KeyValueEntry(id: $0.id, key: $0.key, value: "")
        }
        self.configuration = sanitized
    }
}

/// Versioned envelope for import/export.
struct SavedConfigurationFile: Codable {
    var formatVersion: Int
    var configurations: [SavedRunConfiguration]
}

/// JSON-file-backed store for saved run configurations.
@MainActor
@Observable
public final class SavedRunConfigurationStore {
    public private(set) var configurations: [SavedRunConfiguration] = []
    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContainerDeck/saved-run-configurations.json")
        load()
    }

    public func save(name: String, configuration: ContainerRunConfiguration) {
        configurations.insert(
            SavedRunConfiguration(name: name, configuration: configuration), at: 0
        )
        persist()
    }

    public func delete(id: UUID) {
        configurations.removeAll { $0.id == id }
        persist()
    }

    public func clear() {
        configurations = []
        persist()
    }

    /// Exports the versioned file; returns the encoded data.
    public func exportData() throws -> Data {
        let file = SavedConfigurationFile(
            formatVersion: SavedRunConfiguration.currentFormatVersion,
            configurations: configurations
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }

    /// Imports a versioned file, merging by ID. Rejects incompatible majors.
    public func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file: SavedConfigurationFile
        do {
            file = try decoder.decode(SavedConfigurationFile.self, from: data)
        } catch {
            throw ContainerEngineError.invalidInput(
                "The file is not a ContainerDeck configuration export."
            )
        }
        guard file.formatVersion <= SavedRunConfiguration.currentFormatVersion else {
            throw ContainerEngineError.invalidInput(
                "This export uses format version \(file.formatVersion); this build supports up to \(SavedRunConfiguration.currentFormatVersion). Update ContainerDeck."
            )
        }
        let existing = Set(configurations.map(\.id))
        configurations.append(contentsOf: file.configurations.filter { !existing.contains($0.id) })
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let file = try? decoder.decode(SavedConfigurationFile.self, from: data),
           file.formatVersion <= SavedRunConfiguration.currentFormatVersion {
            configurations = file.configurations
        }
    }

    private func persist() {
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let data = try? exportData() {
            try? data.write(to: fileURL)
        }
    }
}
