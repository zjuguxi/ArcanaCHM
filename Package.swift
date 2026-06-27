// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ArcanaCHM",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArcanaCHM", targets: ["ArcanaCHM"])
    ],
    targets: [
        .executableTarget(
            name: "ArcanaCHM",
            path: "Sources/ArcanaCHM",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ArcanaCHMTests",
            dependencies: ["ArcanaCHM"],
            path: "Tests/ArcanaCHMTests"
        )
    ]
)
