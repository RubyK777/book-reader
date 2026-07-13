// swift-tools-version: 5.9
import PackageDescription

/// Pure, app-agnostic learning engines (CLAUDE.md rule 3): sentence splitting,
/// word tokenizing, cloze construction, fragment detection, and pronunciation
/// scoring. Foundation + NaturalLanguage only — no SwiftUI, no SwiftData, no app
/// models — so other projects can depend on it directly (DECISIONS #68).
let package = Package(
    name: "LearningKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "LearningKit", targets: ["LearningKit"]),
    ],
    targets: [
        .target(name: "LearningKit"),
        .testTarget(name: "LearningKitTests", dependencies: ["LearningKit"]),
    ]
)
