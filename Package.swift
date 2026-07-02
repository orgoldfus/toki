// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Toki",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TokiCore", targets: ["TokiCore"]),
        .executable(name: "TokiApp", targets: ["TokiApp"])
    ],
    targets: [
        .target(name: "TokiCore"),
        .executableTarget(
            name: "TokiApp",
            dependencies: ["TokiCore"]
        ),
        .testTarget(
            name: "TokiCoreTests",
            dependencies: ["TokiCore"]
        ),
        .testTarget(
            name: "TokiAppTests",
            dependencies: ["TokiApp"]
        )
    ]
)
