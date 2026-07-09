import Foundation

/// Realistic sample resources for previews and tests.
public enum MockData {
    public static let containers: [ContainerSummary] = [
        ContainerSummary(
            id: "a8f3c1d9e2b4",
            name: "payment-api",
            image: "payment-api:latest",
            state: .running,
            cpuPercent: 4.1,
            memoryBytes: 418_000_000,
            ipAddress: "192.168.64.8",
            ports: [ContainerPort(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 80, proto: "tcp")],
            createdAt: Date().addingTimeInterval(-18 * 60)
        ),
        ContainerSummary(
            id: "b2e7f4a1c8d3",
            name: "postgres",
            image: "postgres:17",
            state: .running,
            cpuPercent: 1.2,
            memoryBytes: 622_000_000,
            ipAddress: "192.168.64.9",
            ports: [ContainerPort(hostAddress: "127.0.0.1", hostPort: 5432, containerPort: 5432, proto: "tcp")],
            createdAt: Date().addingTimeInterval(-3 * 3600)
        ),
        ContainerSummary(
            id: "c5d9a2b7e1f6",
            name: "valkey-cache",
            image: "valkey/valkey:8",
            state: .running,
            cpuPercent: 0.4,
            memoryBytes: 96_000_000,
            ipAddress: "192.168.64.10",
            ports: [ContainerPort(hostAddress: "0.0.0.0", hostPort: 6379, containerPort: 6379, proto: "tcp")],
            createdAt: Date().addingTimeInterval(-3 * 3600)
        ),
        ContainerSummary(
            id: "d1c8e5f2a9b4",
            name: "redis-test",
            image: "redis:7",
            state: .stopped,
            createdAt: Date().addingTimeInterval(-2 * 86400)
        ),
        ContainerSummary(
            id: "e4b1d7c3f8a2",
            name: "docs-site",
            image: "nginx:alpine",
            state: .stopped,
            createdAt: Date().addingTimeInterval(-6 * 86400)
        ),
    ]

    public static let machines: [MachineSummary] = [
        MachineSummary(
            name: "ubuntu-dev",
            image: "ubuntu:24.04",
            state: .running,
            cpuCount: 4,
            memoryBytes: 2_400_000_000,
            isDefault: true
        ),
        MachineSummary(
            name: "fedora-lab",
            image: "fedora:41",
            state: .stopped,
            cpuCount: 2,
            memoryBytes: 0
        ),
    ]

    public static let images: [ImageSummary] = [
        ImageSummary(id: "sha256:11aa", repository: "payment-api", tag: "latest", sizeBytes: 812_000_000, createdAt: Date().addingTimeInterval(-40 * 60), architectures: ["arm64"]),
        ImageSummary(id: "sha256:22bb", repository: "postgres", tag: "17", sizeBytes: 632_000_000, createdAt: Date().addingTimeInterval(-9 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:33cc", repository: "valkey/valkey", tag: "8", sizeBytes: 141_000_000, createdAt: Date().addingTimeInterval(-9 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:44dd", repository: "redis", tag: "7", sizeBytes: 138_000_000, createdAt: Date().addingTimeInterval(-30 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:55ee", repository: "nginx", tag: "alpine", sizeBytes: 58_000_000, createdAt: Date().addingTimeInterval(-30 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:66ff", repository: "ubuntu", tag: "24.04", sizeBytes: 105_000_000, createdAt: Date().addingTimeInterval(-60 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:77aa", repository: "fedora", tag: "41", sizeBytes: 182_000_000, createdAt: Date().addingTimeInterval(-45 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:88bb", repository: "golang", tag: "1.24", sizeBytes: 941_000_000, createdAt: Date().addingTimeInterval(-14 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:99cc", repository: "node", tag: "22-slim", sizeBytes: 244_000_000, createdAt: Date().addingTimeInterval(-21 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:aadd", repository: "python", tag: "3.13-slim", sizeBytes: 208_000_000, createdAt: Date().addingTimeInterval(-21 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:bbee", repository: "busybox", tag: "latest", sizeBytes: 4_500_000, createdAt: Date().addingTimeInterval(-90 * 86400), architectures: ["arm64"]),
        ImageSummary(id: "sha256:ccff", repository: "alpine", tag: "3.21", sizeBytes: 8_400_000, createdAt: Date().addingTimeInterval(-90 * 86400), architectures: ["arm64"]),
    ]

    public static let volumes: [VolumeSummary] = [
        VolumeSummary(name: "app-data", sizeBytes: 3_200_000_000, createdAt: Date().addingTimeInterval(-9 * 86400)),
        VolumeSummary(name: "pg-data", sizeBytes: 7_800_000_000, createdAt: Date().addingTimeInterval(-9 * 86400)),
        VolumeSummary(name: "cache", sizeBytes: 420_000_000, createdAt: Date().addingTimeInterval(-3 * 86400)),
        VolumeSummary(name: "scratch", sizeBytes: 60_000_000, createdAt: Date().addingTimeInterval(-86400)),
    ]

    public static let networks: [NetworkSummary] = [
        NetworkSummary(name: "default", subnet: "192.168.64.0/24"),
        NetworkSummary(name: "backend", subnet: "192.168.65.0/24"),
    ]

    public static let diskUsage = DiskUsage(
        containers: DiskUsageCategory(
            active: 3, total: 5, sizeBytes: 2_100_000_000, reclaimableBytes: 600_000_000
        ),
        images: DiskUsageCategory(
            active: 6, total: 12, sizeBytes: 18_400_000_000, reclaimableBytes: 5_800_000_000
        ),
        volumes: DiskUsageCategory(
            active: 2, total: 4, sizeBytes: 4_100_000_000, reclaimableBytes: 800_000_000
        )
    )

    public static let registries: [RegistryEntry] = [
        RegistryEntry(display: "ghcr.io", rawJSON: #""ghcr.io""#),
        RegistryEntry(display: "docker.io", rawJSON: #""docker.io""#),
    ]

    public static let builderStatus = BuilderStatus(isRunning: false, rawJSON: "[]")

    public static let version = ContainerSystemVersion(
        version: "1.0.0",
        commit: "ee848e3ebfd7c73b04dd419683be54fb450b8779",
        buildType: "release",
        components: [
            ContainerSystemVersion.Component(
                appName: "container",
                version: "1.0.0",
                commit: "ee848e3ebfd7c73b04dd419683be54fb450b8779",
                buildType: "release"
            )
        ]
    )
}
