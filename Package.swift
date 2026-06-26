// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ArcanaCHM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArcanaCHM", targets: ["ArcanaCHM"])
    ],
    targets: [
        .executableTarget(
            name: "ArcanaCHM",
            path: "Sources/ArcanaCHM"
        ),
        .testTarget(
            name: "ArcanaCHMTests",
            dependencies: ["ArcanaCHM"],
            path: "Tests/ArcanaCHMTests"
        )
    ]
)
