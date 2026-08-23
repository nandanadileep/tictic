// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TicTic",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TicTic", targets: ["TicTic"])
    ],
    targets: [
        .executableTarget(
            name: "TicTic",
            path: "Sources/TicTic"
        ),
        .testTarget(
            name: "TicTicTests",
            dependencies: ["TicTic"],
            path: "Tests/TicTicTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
