# Architecture

ReadAloud is a native SwiftUI application with an iOS app target, a widget
extension, an app test target, and one local Swift package. It has no server
component and no third-party runtime dependencies.

## Targets

### ReadAloud

The main application target owns the user interface, SwiftData store, capture
flows, playback, translation, saved annotations, and review sessions.

### ReadAloudWidget

The widget extension shows review content. It shares data with the main app
through the `group.com.rubyhung.ReadAloud` application group.

### ReadAloudTests

Application tests cover model migration, persistence-bound behavior, export,
audio ingestion, and review-card routing.

### LearningKit

`Packages/LearningKit` contains deterministic, app-independent learning logic:
sentence splitting, tokenization, cloze construction, fragment detection, and
pronunciation scoring. Its tests live beside it in the Swift package.

## Main application layers

- `App` contains the application entry point, root navigation, and App Intents.
- `Features` groups SwiftUI screens by user-facing capability.
- `Models` defines the SwiftData schema and migration plan.
- `Services` contains integrations and stateful application logic.
- `Shared` contains reusable UI components, styles, language support, and small
  utilities.
- `Resources` contains the asset catalog and bundled resources.

Dependencies should point inward: features may use models, services, shared UI,
and LearningKit; reusable code must not depend on a feature screen. Pure logic
belongs in LearningKit rather than in a view or singleton.

## Capture and reading flow

```text
Document camera or photo picker
              |
              v
      OCRService (Vision)
              |
              v
  OCR review and language confirmation
              |
              v
 LearningKit sentence processing
              |
              v
 SwiftData persistence -> Reader -> SpeechPlayer
                              |
                              +-> on-device translation
```

Text is editable before persistence. The confirmed source language is stored
with the source and uses a full BCP-47 identifier such as `fr-FR`. The user's
native language is a separate setting and is used as the translation target.
Translation is visual; speech playback always uses the source text.

## Persistence

SwiftData models and versioned schemas live in `ReadAloud/Models`. The model
container is created by the app entry point and injected through SwiftUI.

`SRSState` and `LearningAssets` are embedded Codable values. Their shape is part
of the persistent schema: changing either requires a new schema version and a
migration stage, even when a newly added property is optional.

Because the next review date is embedded inside `SRSState`, SwiftData predicates
cannot query it directly. Review candidates are fetched and filtered in memory.

## Platform integrations

- Vision and VisionKit: document capture and OCR
- NaturalLanguage: language detection and text processing
- AVFoundation: speech synthesis, recording, and playback
- Translation: on-device translation on iOS 18+
- SwiftData: local persistence and schema migration
- WidgetKit and App Intents: widget and system integrations

Some translation language pairs require a one-time system model download. Other
core application data and processing remain local to the device.
