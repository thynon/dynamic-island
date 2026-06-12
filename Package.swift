// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Island",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "IslandCore", targets: ["IslandCore"]),
        .executable(name: "Island", targets: ["Island"]),
        .executable(name: "IslandCoreChecks", targets: ["IslandCoreChecks"])
    ],
    targets: [
        .target(name: "IslandCore"),
        .executableTarget(
            name: "Island",
            dependencies: ["IslandCore"]
        ),
        .executableTarget(
            name: "IslandCoreChecks",
            dependencies: ["IslandCore"],
            path: "Tests/IslandCoreChecks"
        )
    ]
)
