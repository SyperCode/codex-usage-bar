// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexUsageBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexUsageBar", targets: ["CodexUsageBar"]),
        .executable(name: "CodexUsageProbe", targets: ["CodexUsageProbe"])
    ],
    targets: [
        .target(
            name: "CodexUsageCore",
            path: "CoreSources/CodexUsageCore"
        ),
        .executableTarget(
            name: "CodexUsageBar",
            dependencies: ["CodexUsageCore"],
            path: "AppSources/CodexUsageBar"
        ),
        .executableTarget(
            name: "CodexUsageProbe",
            dependencies: ["CodexUsageCore"],
            path: "CoreSources/CodexUsageProbe"
        ),
        .testTarget(
            name: "CodexUsageCoreTests",
            dependencies: ["CodexUsageCore"],
            path: "Tests/CodexUsageCoreTests"
        )
    ]
)
