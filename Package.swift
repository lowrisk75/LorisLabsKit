// swift-tools-version: 6.0
// LorisLabsKit — the LorisLabs app chassis: shared foundation for the whole portfolio
// Version: 0.10.1 (see CHANGELOG.md)
//
// v2 layout — one repo, modular products; apps import only what they use:
//   LorisLabsKit    review prompts, cross-promo, paywall, referral, trial + license (existing consumers keep working)
//   LorisSync       protocol-abstracted CloudKit sync engine (seeded from Mela/ProfileSyncKit)
//   LorisReports    in-app bug reports + triage (seeded from Lumen's BugReportKit — canonical of the 5 forks)
//   LorisDesignCore shared primitives + tokens (canonical GlassCard of the 4 copies)
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
        .library(name: "LorisSync", targets: ["LorisSync"]),
        .library(name: "LorisReports", targets: ["LorisReports"]),
        .library(name: "LorisDesignCore", targets: ["LorisDesignCore"]),
    ],
    dependencies: [
        // Published release; 0.x minors may break, so stay within 0.2.x.
        // For side-by-side development use `swift package edit`.
        .package(url: "https://github.com/lowrisk75/LorisFoundation.git", .upToNextMinor(from: "0.2.0")),
    ],
    targets: [
        .target(name: "LorisLabsKit", dependencies: [.product(name: "LorisSecurity", package: "LorisFoundation")], resources: [.process("Resources")]),
        .target(name: "LorisSync"),
        .target(
            name: "LorisReports",
            resources: [.process("Resources")]
        ),
        .target(name: "LorisDesignCore"),
        .testTarget(name: "LorisLabsKitTests", dependencies: ["LorisLabsKit", .product(name: "LorisSecurityTesting", package: "LorisFoundation")]),
        .testTarget(name: "LorisReportsTests", dependencies: ["LorisReports"], resources: [.process("Fixtures")]),
        .testTarget(name: "LorisSyncTests", dependencies: ["LorisSync"]),
    ]
)
