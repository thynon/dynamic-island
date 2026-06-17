// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DynamicIsland",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DynamicIslandCore", targets: ["DynamicIslandCore"]),
        .executable(name: "DynamicIsland", targets: ["DynamicIsland"]),
        .executable(name: "DynamicIslandCoreChecks", targets: ["DynamicIslandCoreChecks"])
    ],
    targets: [
        .target(name: "DynamicIslandCore"),
        .executableTarget(
            name: "DynamicIsland",
            dependencies: ["DynamicIslandCore"]
        ),
        .executableTarget(
            name: "DynamicIslandCoreChecks",
            dependencies: ["DynamicIslandCore"],
            path: "Tests/DynamicIslandCoreChecks"
        )
    ]
)
