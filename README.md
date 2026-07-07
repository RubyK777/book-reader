# ReadAloud (book-reader)

Read your book like a parent does! An iOS app for language learners: photograph a book page → on-device OCR → listen sentence by sentence with word-level highlighting → save words → spaced-repetition review.

Fully on-device (Vision, NaturalLanguage, AVSpeechSynthesizer, SwiftData) — no accounts, no servers, works on a plane. See [PROJECT_PLAN.md](PROJECT_PLAN.md) for the full spec.

**Status:** Phase 1 — scan → tap-to-hear loop works; persistence and review come in Phases 2–3.

## Requirements

- Xcode 16+ (built with Xcode 26.2)
- iOS 17.4+ device or simulator
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — only when project files change

## Build & run on your device

```sh
xcodegen generate        # regenerates ReadAloud.xcodeproj from project.yml
open ReadAloud.xcodeproj
```

In Xcode: select the **ReadAloud** target → *Signing & Capabilities* → choose your **Team** (signing is set to Automatic), then pick your iPhone/iPad and hit **Run**. First install on a free account requires trusting the developer profile on the device (Settings → General → VPN & Device Management).

Camera capture needs a real device; on the simulator use **Import Photo** instead.

## Project layout

```
ReadAloud/            app source (SwiftUI, iOS 17.4+)
├── App/              entry point
├── Models/           SwiftData schema + SM-2 SRSState (Phase 2)
├── Services/         OCRService, SentenceSplitter, SpeechPlayer
└── Features/         Scan, Reader (Library/Saved/Review/Settings to come)
Tools/OCRSpike/       macOS CLI to test OCR accuracy on real page photos
Fixtures/             drop 5 real book-page photos here (see its README)
project.yml           XcodeGen spec — edit this, not the .xcodeproj
```

## OCR spike (runs on your Mac)

```sh
swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg
```

Validates the riskiest part of the plan (OCR on curved/glossy pages) using the exact Vision + NLTokenizer pipeline the app uses.
