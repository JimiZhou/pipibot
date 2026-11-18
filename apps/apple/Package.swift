// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PipiBotApple",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "PipiBotKit",
            targets: ["PipiBotKit"]
        ),
        .library(
            name: "PipiBotIOSUI",
            targets: ["PipiBotIOSUI"]
        ),
        .executable(
            name: "PipiBotMacApp",
            targets: ["PipiBotMacApp"]
        )
    ],
    targets: [
        .target(
            name: "PipiBotKit"
        ),
        .target(
            name: "PipiBotIOSUI",
            dependencies: ["PipiBotKit"]
        ),
        .executableTarget(
            name: "PipiBotMacApp",
            dependencies: ["PipiBotKit", "PipiBotIOSUI"]
        ),
        .testTarget(
            name: "PipiBotKitTests",
            dependencies: ["PipiBotKit", "PipiBotIOSUI"]
        )
    ]
)
