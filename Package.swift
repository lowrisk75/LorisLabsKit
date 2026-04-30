// swift-tools-version: 6.0
// LorisLabsKit — shared SwiftUI utilities for the LorisLabs portfolio
// Version: 0.3.0 (see CHANGELOG.md)
import PackageDescription

let package = Package(
    name: "LorisLabsKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "LorisLabsKit", targets: ["LorisLabsKit"]),
    ],
    targets: [
        .target(name: "LorisLabsKit"),
        .testTarget(name: "LorisLabsKitTests", dependencies: ["LorisLabsKit"]),
    ]
)
