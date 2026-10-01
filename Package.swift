// swift-tools-version: 6.0
// LorisLabsKit — the LorisLabs app chassis: shared foundation for the whole portfolio
// Version: 0.8.0 (see CHANGELOG.md)
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
    targets: [
        .target(name: "LorisLabsKit", resources: [.process("Resources")]),
        .target(name: "LorisSync"),
        .target(
            name: "LorisReports",
            resources: [.process("Resources")]
        ),
        .target(name: "LorisDesignCore"),
        .testTarget(name: "LorisLabsKitTests", dependencies: ["LorisLabsKit"]),
        .testTarget(name: "LorisReportsTests", dependencies: ["LorisReports"]),
        .testTarget(name: "LorisSyncTests", dependencies: ["LorisSync"]),
    ]
)
