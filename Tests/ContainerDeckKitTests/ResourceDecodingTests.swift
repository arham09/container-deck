import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("Resource JSON decoding (fixtures captured from CLI 1.0.0)")
struct ResourceDecodingTests {
    @Test("Container list (stopped container) maps configuration and status")
    func containerListStopped() throws {
        let summaries = try ContainerMapper.summaries(
            from: try fixtureData("container-list"), command: "container list"
        )
        let container = try #require(summaries.first)
        #expect(container.id == "cd-fixture-test")
        #expect(container.name == "cd-fixture-test")
        #expect(container.image == "docker.io/library/alpine:latest")
        #expect(container.state == .stopped)
        #expect(container.cpuLimit == 4)
        #expect(container.memoryLimitBytes == 1_073_741_824)
        #expect(container.architecture == "arm64")
        #expect(container.os == "linux")
        #expect(container.createdAt != nil)
        #expect(container.ipAddress == nil)
    }

    @Test("Container list (running container) exposes IP without prefix length")
    func containerListRunning() throws {
        let summaries = try ContainerMapper.summaries(
            from: try fixtureData("container-list-running"), command: "container list"
        )
        let container = try #require(summaries.first)
        #expect(container.state == .running)
        #expect(container.ipAddress == "192.168.64.2")
        #expect(container.startedAt != nil)
    }

    @Test("Container list maps published ports (host, container, proto)")
    func containerListPorts() throws {
        let summaries = try ContainerMapper.summaries(
            from: try fixtureData("container-list-ports"), command: "container list"
        )
        let container = try #require(summaries.first)
        let port = try #require(container.ports.first)
        #expect(container.ports.count == 1)
        #expect(port.hostPort == 8080)
        #expect(port.containerPort == 80)
        #expect(port.hostAddress == "127.0.0.1")
        #expect(port.proto == "tcp")
    }

    @Test("Container without published ports maps to an empty list")
    func containerListNoPorts() throws {
        let summaries = try ContainerMapper.summaries(
            from: try fixtureData("container-list"), command: "container list"
        )
        #expect(summaries.first?.ports.isEmpty == true)
    }

    @Test("Container inspect decodes with the same DTO")
    func containerInspect() throws {
        let entries = try ResourceMappers.decode(
            [ContainerEntryDTO].self,
            from: try fixtureData("container-inspect"),
            command: "container inspect"
        )
        #expect(entries.count == 1)
        #expect(ContainerMapper.summary(from: entries[0]) != nil)
    }

    @Test("Unknown container fields and states never break decoding")
    func containerUnknownFields() throws {
        let json = """
        [{"id":"x","futureField":{"a":1},"configuration":{"id":"x","newThing":true},"status":{"state":"hibernating"}}]
        """
        let summaries = try ContainerMapper.summaries(from: Data(json.utf8), command: "test")
        #expect(summaries.first?.state == .stopped)
    }

    @Test("Image list maps reference, sizes, and real architectures")
    func imageList() throws {
        let summaries = try ImageMapper.summaries(
            from: try fixtureData("image-list"), command: "container image list"
        )
        let image = try #require(summaries.first)
        #expect(image.repository == "docker.io/library/alpine")
        #expect(image.tag == "latest")
        #expect(image.digest?.hasPrefix("sha256:") == true)
        // Attestation variants (os "unknown") are excluded.
        #expect(!image.architectures.contains("unknown"))
        #expect(image.architectures.contains("arm64"))
        #expect((image.sizeBytes ?? 0) > 0)
        #expect(image.createdAt != nil)
    }

    @Test("Image reference splitting handles tags, digests, and ports")
    func referenceSplitting() {
        #expect(ImageMapper.splitReference("docker.io/library/alpine:latest")
            == ("docker.io/library/alpine", "latest"))
        #expect(ImageMapper.splitReference("alpine") == ("alpine", "latest"))
        #expect(ImageMapper.splitReference("ghcr.io/org/app:1.2") == ("ghcr.io/org/app", "1.2"))
        // A colon inside a registry port (no tag) is not a tag separator.
        #expect(ImageMapper.splitReference("localhost:5000/app") == ("localhost:5000/app", "latest"))
    }

    @Test("Volume list maps configuration")
    func volumeList() throws {
        let summaries = try VolumeMapper.summaries(
            from: try fixtureData("volume-list"), command: "container volume list"
        )
        let volume = try #require(summaries.first)
        #expect(volume.name == "cd-fixture-vol")
        #expect(volume.sizeBytes == 549_755_813_888)
        #expect(volume.driver == "local")
        #expect(volume.format == "ext4")
        #expect(volume.sourcePath?.contains("volumes/cd-fixture-vol") == true)
        #expect(volume.createdAt != nil)
    }

    @Test("Machine list maps the flat schema including the default flag")
    func machineList() throws {
        let summaries = try MachineMapper.summaries(
            from: try fixtureData("machine-list"), command: "container machine list"
        )
        let machine = try #require(summaries.first)
        #expect(machine.name == "cd-fixture-machine")
        #expect(machine.state == .running)
        #expect(machine.isDefault)
        #expect(machine.cpuCount == 6)
        #expect(machine.memoryBytes == 12_884_901_888)
        #expect(machine.ipAddress == "192.168.64.3")
        // Image is not part of the list schema.
        #expect(machine.image == nil)
    }

    @Test("Machine inspect adds image and home mount")
    func machineInspect() throws {
        let entries = try ResourceMappers.decode(
            [MachineEntryDTO].self,
            from: try fixtureData("machine-inspect"),
            command: "container machine inspect"
        )
        let entry = try #require(entries.first)
        #expect(entry.image?.reference == "docker.io/library/alpine:3.22")
        #expect(entry.homeMount == "rw")
        let summary = try #require(MachineMapper.summary(from: entry))
        #expect(summary.image == "docker.io/library/alpine:3.22")
    }

    @Test("system df maps all three categories")
    func diskUsage() throws {
        let usage = try DiskUsageMapper.usage(
            from: try fixtureData("system-df"), command: "container system df"
        )
        #expect(usage.images.total == 1)
        #expect(usage.images.sizeBytes == 657_125_376)
        #expect(usage.images.reclaimableBytes == 657_125_376)
        #expect(usage.volumes.total == 1)
        #expect(usage.containers.total == 0)
        #expect(usage.totalBytes == usage.images.sizeBytes + usage.volumes.sizeBytes)
    }

    @Test("Empty builder status means not running")
    func builderStatus() throws {
        let data = try fixtureData("builder-status")
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [Any])
        #expect(array.isEmpty)
    }

    @Test("Empty registry list decodes to no entries")
    func registryList() throws {
        let entries = try RegistryMapper.entries(
            from: try fixtureData("registry-list"), command: "container registry list"
        )
        #expect(entries.isEmpty)
    }

    @Test("Registry entries tolerate strings and objects")
    func registryShapes() throws {
        let entries = try RegistryMapper.entries(
            from: Data(#"["ghcr.io",{"registry":"docker.io","user":"x"}]"#.utf8),
            command: "container registry list"
        )
        #expect(entries.count == 2)
        #expect(entries[0].display == "ghcr.io")
        #expect(entries[1].display == "docker.io")
    }
}
