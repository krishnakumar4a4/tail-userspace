// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TailUserspace",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "TailUserspaceCore",
            targets: ["TailUserspaceCore"]
        ),
        .executable(
            name: "tail-userspace",
            targets: ["TailUserspaceCLI"]
        ),
        .executable(
            name: "TailUserspaceApp",
            targets: ["TailUserspaceApp"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TailUserspaceCore",
            dependencies: [],
            path: "Sources/TailUserspaceCore"
        ),
        .executableTarget(
            name: "TailUserspaceCLI",
            dependencies: ["TailUserspaceCore"],
            path: "Sources/TailUserspaceCLI"
        ),
        .executableTarget(
            name: "TailUserspaceApp",
            dependencies: ["TailUserspaceCore"],
            path: "Sources/TailUserspaceApp"
        ),
        .executableTarget(
            name: "TailUserspaceTests",
            dependencies: ["TailUserspaceCore"],
            path: "Tests/TailUserspaceCoreTests"
        )
    ]
)
