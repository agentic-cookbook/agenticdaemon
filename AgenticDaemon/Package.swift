// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AgenticDaemon",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "agentic-daemon",
            path: "Sources"
        )
    ]
)
