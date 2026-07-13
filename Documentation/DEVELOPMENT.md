# Development

## Opening the project

Open `ReadAloud.xcodeproj` directly in Xcode. The checked-in project is the
source of truth; this repository does not require a project generator.

The shared **ReadAloud** scheme builds the app and widget and runs the application
test target. Choose a development team in Signing & Capabilities before running
on a physical device.

## Testing

Run application tests with Xcode's Test action. Run the local package tests from
the repository root with:

```bash
cd Packages/LearningKit
swift test
```

Camera behavior must be verified on a physical iPhone or iPad. Use photo import
when testing the remainder of the scan flow in Simulator.

## Project conventions

- Minimum deployment target: iOS 18.
- Use SwiftUI, SwiftData, Swift Concurrency, and the Observation framework.
- Prefer `@Observable` for observable reference types.
- Keep full BCP-47 language identifiers in app and model code. Shorten them only
  at framework boundaries that explicitly require a shorter code.
- Keep source language and native/translation language as separate concepts.
- Pass dependencies into services; avoid global singletons.
- Keep app-independent, deterministic logic in `Packages/LearningKit`.

## Adding code

Place a new screen or flow under the appropriate `ReadAloud/Features` folder.
Place stateful integrations and reusable application logic in `Services`.
Reusable views and styles belong in `Shared`.

Before adding a component or helper, check `Shared`, `Services`, and LearningKit
for an existing implementation. When code becomes useful to more than one
feature, move it to the narrowest shared layer that fits.

Add files, targets, capabilities, package dependencies, and build settings using
Xcode. Commit intentional `ReadAloud.xcodeproj/project.pbxproj` changes together
with the source change that requires them.

## UI conventions

- Use semantic colors and styles from `Shared/DesignSystem.swift` and
  `Shared/Styles`.
- Use the spacing, radius, and icon-size tokens instead of introducing arbitrary
  constants.
- Keep interactive hit areas at least 44 by 44 points.
- Use SF Symbols for interface icons.
- Preserve Dynamic Type and VoiceOver behavior.

## Persistence changes

Treat model changes as migrations. Add a new versioned schema and migration
stage when changing a SwiftData model or an embedded Codable value. Run
`MigrationTests` before shipping a schema change.

## Release checks

Before merging a release change:

1. Build the ReadAloud scheme for an iOS simulator.
2. Run the ReadAloud application tests.
3. Run the LearningKit package tests.
4. Exercise capture, OCR review, reading, audio, and review on a physical device
   when the change touches those areas.
5. Confirm signing, the application-group entitlement, privacy descriptions,
   and widget behavior.
