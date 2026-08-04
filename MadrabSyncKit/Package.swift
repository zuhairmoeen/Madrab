// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MadrabSyncKit",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MadrabSyncKit",
            targets: ["MadrabSyncKit"]
        )
    ],
    dependencies: [
        .package(path: "../MadrabScoringEngine")
    ],
    targets: [
        .target(
            name: "MadrabSyncKit",
            dependencies: [
                .product(name: "MadrabScoringEngine", package: "MadrabScoringEngine")
            ]
        ),
        .testTarget(
            name: "MadrabSyncKitTests",
            dependencies: ["MadrabSyncKit"]
        ),
    ]
)
