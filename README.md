# ReadAloud

ReadAloud is a native iOS language-learning app. Capture text from books, signs,
menus, or photos; review the recognized text; listen sentence by sentence; save
useful words and phrases; and revisit them with spaced repetition.

The app is built with SwiftUI and Apple frameworks. OCR, speech, persistence,
and learning features run on device. Translation can require a one-time Apple
language-model download for a new language pair.

## Requirements

- Xcode 26 or newer
- iOS 18 or newer
- An Apple silicon or Intel Mac supported by Xcode

## Run the app

1. Open `ReadAloud.xcodeproj` in Xcode.
2. Select the **ReadAloud** scheme.
3. In **Signing & Capabilities**, choose your development team.
4. Select an iPhone, iPad, or simulator and press **Run**.

Camera capture requires a physical device. The simulator supports photo import.

## Project structure

```text
ReadAloud.xcodeproj/       Xcode project and shared scheme
ReadAloud/                 Main iOS application
  App/                     App entry point and navigation
  Features/                Feature-oriented SwiftUI screens
  Models/                  SwiftData models and migrations
  Resources/               Asset catalogs and app resources
  Services/                OCR, audio, translation, and persistence services
  Shared/                  Reusable components, styles, and utilities
ReadAloudWidget/           Widget extension
ReadAloudTests/            Application unit tests
Packages/LearningKit/      Reusable Swift package and package tests
Documentation/             Architecture and development notes
```

The checked-in Xcode project is the source of truth. Add targets, files, build
settings, and package dependencies through Xcode.

## Tests

Run the **ReadAloud** test action in Xcode for application tests. The reusable
text-processing package can also be tested independently:

```bash
cd Packages/LearningKit
swift test
```

See [Architecture](Documentation/ARCHITECTURE.md) for component boundaries and
[Development](Documentation/DEVELOPMENT.md) for coding and project conventions.
Historical implementation rationale is retained in the
[decision log](Documentation/DECISIONS.md).
