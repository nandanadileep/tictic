// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Vaani",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Vaani", targets: ["Vaani"])
    ],
    targets: [
        .executableTarget(
            name: "Vaani",
            path: "Sources/Vaani"
        ),
        .testTarget(
            name: "VaaniTests",
            dependencies: ["Vaani"],
            path: "Tests/VaaniTests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
