// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiveSubs",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "LiveSubs", targets: ["LiveSubs"])
    ],
    targets: [
        .executableTarget(
            name: "LiveSubs",
            path: "Sources/LiveSubs"
        ),
        .testTarget(
            name: "LiveSubsTests",
            dependencies: ["LiveSubs"]
        )
    ]
)
