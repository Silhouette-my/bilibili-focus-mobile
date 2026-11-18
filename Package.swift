// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BilibiliFocus",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "FocusCore",
            targets: ["FocusCore"]
        ),
    ],
    targets: [
        .target(
            name: "FocusCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "FocusCoreTests",
            dependencies: ["FocusCore"],
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
