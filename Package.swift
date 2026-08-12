// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "OpenCodexPauseWorker",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PauseWorkerCore", targets: ["PauseWorkerCore"]),
        .executable(name: "OpenCodexTray", targets: ["OpenCodexTray"]),
        .executable(name: "pause-worker-once", targets: ["PauseWorkerOnce"]),
    ],
    targets: [
        .target(name: "PauseWorkerCore"),
        .executableTarget(
            name: "OpenCodexTray",
            dependencies: ["PauseWorkerCore"],
            resources: [.process("Resources")]
        ),
        .executableTarget(name: "PauseWorkerOnce", dependencies: ["PauseWorkerCore"]),
        .testTarget(
            name: "PauseWorkerCoreTests",
            dependencies: ["PauseWorkerCore"],
            path: "tests/PauseWorkerCoreTests"
        ),
    ]
)
