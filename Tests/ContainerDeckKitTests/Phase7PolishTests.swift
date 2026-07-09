import Foundation
import Testing
@testable import ContainerDeckKit

@MainActor
@Suite("Saved run configurations")
struct SavedConfigurationTests {
    private func makeStore() -> SavedRunConfigurationStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cd-test-configs-\(UUID().uuidString).json")
        return SavedRunConfigurationStore(fileURL: url)
    }

    @Test("Environment values are never persisted — only keys")
    func secretsStripped() throws {
        let store = makeStore()
        var config = ContainerRunConfiguration()
        config.image = "postgres:17"
        config.environment = [KeyValueEntry(key: "POSTGRES_PASSWORD", value: "hunter2")]
        store.save(name: "db", configuration: config)

        let saved = try #require(store.configurations.first)
        #expect(saved.configuration.environment.first?.key == "POSTGRES_PASSWORD")
        #expect(saved.configuration.environment.first?.value == "")

        let exported = try store.exportData()
        #expect(!String(decoding: exported, as: UTF8.self).contains("hunter2"))
    }

    @Test("Export/import round-trips with the versioned envelope")
    func roundTrip() throws {
        let store = makeStore()
        var config = ContainerRunConfiguration()
        config.image = "alpine:latest"
        config.name = "test"
        store.save(name: "mine", configuration: config)
        let data = try store.exportData()

        let second = makeStore()
        try second.importData(data)
        #expect(second.configurations.count == 1)
        #expect(second.configurations.first?.configuration.image == "alpine:latest")
        // Importing the same file again does not duplicate.
        try second.importData(data)
        #expect(second.configurations.count == 1)
    }

    @Test("Future format versions are rejected with guidance")
    func futureVersionRejected() {
        let store = makeStore()
        let future = Data(#"{"formatVersion":99,"configurations":[]}"#.utf8)
        #expect(throws: ContainerEngineError.self) {
            try store.importData(future)
        }
        #expect(throws: ContainerEngineError.self) {
            try store.importData(Data("not json".utf8))
        }
    }

    @Test("Persistence survives a fresh store on the same file")
    func persistence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cd-test-configs-\(UUID().uuidString).json")
        var config = ContainerRunConfiguration()
        config.image = "alpine:latest"
        SavedRunConfigurationStore(fileURL: url).save(name: "kept", configuration: config)
        let reloaded = SavedRunConfigurationStore(fileURL: url)
        #expect(reloaded.configurations.first?.name == "kept")
    }
}
