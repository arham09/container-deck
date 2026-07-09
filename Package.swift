// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContainerDeck",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "ContainerDeck", targets: ["ContainerDeck"]),
        .library(name: "ContainerDeckKit", targets: ["ContainerDeckKit"]),
    ],
    targets: [
        .target(
            name: "ContainerDeckKit"
        ),
        .executableTarget(
            name: "ContainerDeck",
            dependencies: ["ContainerDeckKit"]
        ),
        .testTarget(
            name: "ContainerDeckKitTests",
            dependencies: ["ContainerDeckKit"],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
