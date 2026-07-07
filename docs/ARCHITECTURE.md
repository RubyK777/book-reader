# ReadAloud — Architecture (current state)

*Companion to [PROJECT_PLAN.md](../PROJECT_PLAN.md) §5. This document describes what is actually built as of 2026-07-06, the contracts between components, and known gaps. Update it when structure changes, not for every feature.*

## 1. System overview

Fully on-device pipeline, no networking anywhere:

```
CameraPicker / PhotosPicker
        │  UIImage
        ▼
   OCRService ──── Vision VNRecognizeTextRequest (.accurate, languageCode)
        │  String (lines joined, top-to-bottom)
        ▼
 SentenceSplitter ─ NLTokenizer(.sentence), language-aware
        │  [String]
        ▼
   ReaderView ◄──── observes ──── SpeechPlayer (@Observable)
   sentence cards                 AVSpeechSynthesizer + delegate
   word highlight                 highlightRange from willSpeakRange…
```

Persistence (SwiftData, `Models.swift`) is **defined but not wired** — `ReadAloudApp` has no `.modelContainer`, nothing reads or writes models yet. That is the first Phase 2 task ([PHASE2_DESIGN.md](PHASE2_DESIGN.md)).

## 2. Component contracts

### OCRService (`Services/OCRService.swift`)
`recognizeText(in: UIImage, languageCode: String) async throws -> String`
- Runs Vision `.accurate` with `usesLanguageCorrection`, on a detached user-initiated task.
- Sorts observations by `boundingBox.midY` descending (Vision origin is bottom-left) → **single-column assumption**. Two-column pages will interleave; mitigation (column clustering by midX) is a backlog item, not v1.
- Returns lines joined with spaces; hyphenation at line breaks is not repaired (known OCR-quality item).

### SentenceSplitter (`Services/SentenceSplitter.swift`)
`split(_ text: String, languageCode: String) -> [String]`
- `NLTokenizer(.sentence)` with language from the first two chars of the BCP-47 code. Pure function, trivially unit-testable — good first test target.

### SpeechPlayer (`Services/SpeechPlayer.swift`)
The playback source of truth. `@Observable`; views read, never mutate, playback state.
- Inputs: `load(sentences:languageCode:)`, `play(at:)`, `togglePlayPause()`, `next()`, `previous()`, `stop()`; settable `speedMultiplier` (applies **on the next utterance**, not mid-sentence) and `repeatMode`.
- Outputs: `currentSentenceIndex: Int?`, `highlightRange: NSRange?` (word being spoken, from `willSpeakRangeOfSpeechString`), `isSpeaking`.
- Auto-advance lives in `didFinish`; the `isJumping` flag suppresses auto-advance when a stop was caused by a programmatic jump (`play(at:)`/`stop()` during speech). If you touch playback logic, preserve this — it's the subtle part.
- Audio session: `.playback` + `.spokenAudio` set once at init, activated on each `play`. **Never deactivated**, and there is **no interruption / route-change handling** (phone call, unplugging headphones) — backlog items.

### Views (`Features/`)
- `ScanHomeView` — Phase 1 root: language picker (`@AppStorage("targetLanguage")`), camera/photo import, runs OCR+split inline, pushes Reader via `navigationDestination(item:)`. The `extension [String]: @retroactive Identifiable` at the bottom exists only to make that work — it dies when Phase 2 navigation lands.
- `ReaderView(sentences:languageCode:)` — sentence cards in a `LazyVStack`, tap-to-play, active card tinted + scaled, word highlight via `AttributedString` background, auto-scroll to active card, playback bar (prev/play/next, repeat, speed 0.5–1.0×). Owns its `SpeechPlayer`; `onDisappear` stops playback.
- `CameraPicker` — `UIImagePickerController` wrapper. VisionKit Live Text stays a Phase 4 stretch.

### Models (`Models/Models.swift`) — defined, unused until Phase 2
`Book (title, languageCode) 1─* ScanPage (imageData, rawText, orderIndex) 1─* Sentence (text, orderIndex, isBookmarked, userNote, srs)`, plus standalone `SavedWord (word, contextSentence snapshot, languageCode, srs)`. `SRSState` is a Codable **value type** (SM-2) embedded in both Sentence and SavedWord.

> ⚠️ Because `SRSState` is a Codable blob, **`#Predicate` cannot reach `srs.dueDate`**. Due-item queries must fetch candidates (bookmarked sentences / all saved words) and filter in memory. Fine at personal-library scale; if it ever isn't, promote `dueDate` to a stored property. Logged in [DECISIONS.md](DECISIONS.md).

## 3. Conventions

- **Project file is generated.** Edit `project.yml`, run `xcodegen generate`. Never hand-edit the `.xcodeproj`.
- iOS 17.4+, SwiftUI, `@Observable` (not ObservableObject). No third-party dependencies — Apple frameworks only, by design.
- Feature-first layout: `Features/<Name>/` per screen area; cross-cutting logic in `Services/`; shared UI in `Shared/`.
- `languageCode` is always full BCP-47 (`"fr-FR"`); trim to 2 letters only at NL/Vision API boundaries.
- All user-facing strings inline for now; localization is out of scope for v1.

## 4. Known gaps / tech debt (as of 2026-07-06)

Tracked with owners-of-record in [TASKS.md](TASKS.md):

1. SwiftData container not wired; `Models.swift` is dead code until Phase 2.
2. No test target at all (`project.yml` defines only the app target).
3. `SpeechPlayer`: no interruption/route-change observers; audio session never deactivated; speed changes don't apply mid-utterance.
4. `[String]: @retroactive Identifiable` navigation hack in `ScanHomeView`.
5. OCR single-column assumption; hyphenated line breaks not repaired.
6. No post-capture crop/rotate step (plan §4.2 calls for one).
7. `Fixtures/` is empty — the OCR spike (the plan's #1 risk mitigation) has not been run against real book photos yet.
8. TTS stops when the screen locks: no `audio` background mode. Needed before "continuous page playback" is real.

## 5. Testing strategy (to establish in Phase 2)

- Add `ReadAloudTests` unit target in `project.yml`.
- Priority order: `SRSState.review` (pure math, highest logic density) → `SentenceSplitter` (fixture strings per language) → `SpeechPlayer` queue logic (inject a synthesizer protocol if it gets hairy; don't test AVFoundation itself).
- OCR accuracy is validated by the `Tools/OCRSpike` CLI against `Fixtures/`, not by unit tests.
