// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MadrabScoringEngine",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MadrabScoringEngine",
            targets: ["MadrabScoringEngine"]
        )
    ],
    targets: [
        .target(
            name: "MadrabScoringEngine"
        ),
        .testTarget(
            name: "MadrabScoringEngineTests",
            dependencies: ["MadrabScoringEngine"]
        ),
    ]
)
