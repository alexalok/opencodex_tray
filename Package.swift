// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenCodexQuotaTray",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "OpenCodexQuotaCore", targets: ["OpenCodexQuotaCore"]),
        .executable(name: "OpenCodexTray", targets: ["OpenCodexTray"]),
    ],
    targets: [
        .target(name: "OpenCodexQuotaCore"),
        .executableTarget(
            name: "OpenCodexTray",
            dependencies: ["OpenCodexQuotaCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OpenCodexQuotaCoreTests",
            dependencies: ["OpenCodexQuotaCore"],
            path: "tests/OpenCodexQuotaCoreTests"
        ),
    ]
)
