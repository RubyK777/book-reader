# ReadAloud — Architecture (current state)

*Companion to [PROJECT_PLAN.md](../PROJECT_PLAN.md) §5. This document describes what is actually built as of 2026-07-06, the contracts between components, and known gaps. Update it when structure changes, not for every feature.*

## 1. System overview

On-device pipeline. No networking **except** the one-time system language-pack download the Translation framework triggers the first time a new source→target pair is used (§2 · [TRANSLATION_DESIGN.md](TRANSLATION_DESIGN.md)). Every other operation — all OCR, all TTS, and every already-translated page — is offline; the "works on a plane" promise holds after that first, per-pair download.

Capture-first: the user no longer pre-picks a source language. OCR auto-detects it, and the user confirms/corrects it in a review screen **before** anything is persisted.

```
VNDocumentCameraViewController / PhotosPicker
        │  UIImage
        ▼
   OCRService ──── Vision VNRecognizeTextRequest (.accurate, automaticallyDetectsLanguage)
        │           └─ NLLanguageRecognizer over assembled text → detectedLanguageCode
        │  OCRResult (text + detectedLanguageCode)
        ▼
   OCRReviewView ── edit full text · confirm source language · choose translate-to
        │  edited text + confirmed languageCode
        ▼
 SentenceSplitter ─ NLTokenizer(.sentence), confirmed language
        │  [String]  → persist (Book / ScanPage / Sentence)
        ▼
   ReaderView ◄──── observes ──── SpeechPlayer (@Observable, speaks SOURCE only)
   sentence cards                 AVSpeechSynthesizer + delegate
   word highlight ◄─ .translationTask → TranslationSession (iOS 18: batch, persisted)
   translation under card
```

Persistence (SwiftData, `Models.swift`) is **defined but not wired** — `ReadAloudApp` has no `.modelContainer`, nothing reads or writes models yet. That is the first Phase 2 task ([PHASE2_DESIGN.md](PHASE2_DESIGN.md)).

## 2. Component contracts

### OCRService (`Services/OCRService.swift`)
`recognizeText(in: UIImage, languageHint: String? = nil) async throws -> OCRResult`
- Runs Vision `.accurate` with `usesLanguageCorrection` and `automaticallyDetectsLanguage = true` (iOS 16+), on a detached user-initiated task — the source language is **no longer required up front**. When a Book already has a language (Add-Page path), callers pass it as `languageHint`, which sets `recognitionLanguages = [hint]` to bias accuracy.
- Returns `OCRResult` (struct defined in [OCR_PIPELINE.md](OCR_PIPELINE.md)): `text: String` plus `detectedLanguageCode: String`, computed by running `NLLanguageRecognizer` over the assembled text (`.dominantLanguage` → BCP-47, e.g. `"fr"`). Vision exposes no reliable per-page language, so NL does the detection.
- **Honest limit:** "any language" = anything in `VNRecognizeTextRequest.supportedRecognitionLanguages` for the `.accurate` revision (Latin scripts + zh/ja/ko/…) — a bounded list, **not literally every language**.
- Sorts observations by `boundingBox.midY` descending (Vision origin is bottom-left) → **single-column assumption**. Two-column pages will interleave; mitigation (column clustering by midX) is a backlog item, not v1. Hyphenation at line breaks is not repaired (known OCR-quality item). Cancellable per DECISIONS #16.

### SentenceSplitter (`Services/SentenceSplitter.swift`)
`split(_ text: String, languageCode: String) -> [String]`
- `NLTokenizer(.sentence)` with language from the first two chars of the BCP-47 code. Pure function, trivially unit-testable — good first test target.
- In the capture-first flow it splits the **edited** text from `OCRReviewView` using the **confirmed** source language, not a pre-picked one.

### Translation (Reader) — Apple Translation framework, iOS 18+
Core subsystem (was a Phase 4 stretch). Full design in [TRANSLATION_DESIGN.md](TRANSLATION_DESIGN.md); the contract other docs rely on:
- The Reader attaches SwiftUI's `.translationTask(_:action:)`; **SwiftUI provides the `TranslationSession`** (it is not a free-standing async API). Config: `TranslationSession.Configuration(source:target:)` from `Locale.Language(identifier:)` (source = book's detected language, target = `Book.translationLanguage`).
- Batch: `try await session.translations(from: [TranslationSession.Request(sourceText:clientIdentifier:)])`; write each `response.targetText` into `Sentence.translatedText` and save → offline thereafter.
- Availability/downloads: `LanguageAvailability().status(from:to:)` → `.installed`/`.supported`/`.unsupported`. First use of a new pair triggers the **system language-download consent** (network once, then offline).
- TTS **always** speaks source text; translation is a visual aid, never spoken. Rejected: `.translationPresentation(isPresented:text:)` (iOS 17.4) on-demand single-string sheet — not the inline, persisted, whole-page translation the user wants.

### SpeechPlayer (`Services/SpeechPlayer.swift`)
The playback source of truth. `@Observable`; views read, never mutate, playback state.
- Inputs: `load(sentences:languageCode:)`, `play(at:)`, `togglePlayPause()`, `next()`, `previous()`, `stop()`; settable `speedMultiplier` (applies **on the next utterance**, not mid-sentence) and `repeatMode`.
- Outputs: `currentSentenceIndex: Int?`, `highlightRange: NSRange?` (word being spoken, from `willSpeakRangeOfSpeechString`), `isSpeaking`.
- Auto-advance lives in `didFinish`; the `isJumping` flag suppresses auto-advance when a stop was caused by a programmatic jump (`play(at:)`/`stop()` during speech). If you touch playback logic, preserve this — it's the subtle part.
- Audio session: `.playback` + `.spokenAudio` set once at init, activated on each `play`. **Never deactivated**, and there is **no interruption / route-change handling** (phone call, unplugging headphones) — backlog items.

### Views (`Features/`)
- `ScanHomeView` — Phase 1 root: language picker (`@AppStorage("targetLanguage")`), camera/photo import, runs OCR+split inline, pushes Reader via `navigationDestination(item:)`. The `extension [String]: @retroactive Identifiable` at the bottom exists only to make that work — it dies when Phase 2 navigation lands.
- `OCRReviewView` (`Features/Scan/OCRReviewView.swift`) — **new; shown after OCR, before persistence.** Full-height editable `TextEditor` prefilled with `OCRResult.text`; a source-language `Picker` prefilled with `detectedLanguageCode` (correcting it here is how a wrong detection is fixed); the optional translate-to `Picker`. "Use" splits the edited text with the confirmed language then persists; "Retake" returns to capture. Nothing is saved until "Use", so free-text editing risks no srs/bookmark. Wiring in [PHASE2_DESIGN.md](PHASE2_DESIGN.md); Reader display of the result in [UX_SPEC.md](UX_SPEC.md).

```
┌─────────────────────────────┐
│ ← Review text        [Use]  │
├─────────────────────────────┤
│ Source: [Français ▾]        │
│ Translate to: [English ▾]   │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ Le petit prince vivait  │ │  editable TextEditor
│ │ sur une planète. Il     │ │  (full OCR text,
│ │ regardait le coucher…   │ │   nothing saved yet)
│ └─────────────────────────┘ │
├─────────────────────────────┤
│         [ Retake ]          │
└─────────────────────────────┘
```

- `ReaderView(sentences:languageCode:)` — sentence cards in a `LazyVStack`, tap-to-play, active card tinted + scaled, word highlight via `AttributedString` background, auto-scroll to active card, playback bar (prev/play/next, repeat, speed 0.5–1.0×). Owns its `SpeechPlayer`; `onDisappear` stops playback. Gains: translated text under each card (`.secondary`, smaller), a toolbar show/hide-translations toggle, and a `[⋯]` per-book translate-to picker; hosts the `.translationTask` (§2 · [UX_SPEC.md](UX_SPEC.md)).
- `CameraPicker` — `UIImagePickerController` wrapper. VisionKit Live Text stays a Phase 4 stretch.

### Models (`Models/Models.swift`) — defined, unused until Phase 2
`Book (title, languageCode, translationLanguage?) 1─* ScanPage (imageData, rawText, orderIndex) 1─* Sentence (text, translatedText?, orderIndex, isBookmarked, userNote, srs)`, plus standalone `SavedWord (word, contextSentence snapshot, languageCode, srs)`. `SRSState` is a Codable **value type** (SM-2) embedded in both Sentence and SavedWord.

`Book.languageCode` is now **auto-set** from the confirmed source language of the first page (detected by OCR, editable later) rather than pre-picked; `BookFormView` no longer forces a language choice at create time. `Book.translationLanguage: String?` (BCP-47; nil = translation off) and `Sentence.translatedText: String?` join **ReadAloudSchemaV2** — the single lightweight migration (introduced in PHASE3 for `SavedWord.sourceBookTitle`) that adds all new optional fields at once. Changing `translationLanguage` clears the book's `translatedText` (now stale) → re-translated lazily on next Reader open (DECISIONS #24).

> ⚠️ Because `SRSState` is a Codable blob, **`#Predicate` cannot reach `srs.dueDate`**. Due-item queries must fetch candidates (bookmarked sentences / all saved words) and filter in memory. Fine at personal-library scale; if it ever isn't, promote `dueDate` to a stored property. Logged in [DECISIONS.md](DECISIONS.md).

## 3. Conventions

- **Project file is generated.** Edit `project.yml`, run `xcodegen generate`. Never hand-edit the `.xcodeproj`.
- iOS 18.0+ (raised from 17.4 for the inline/programmatic `TranslationSession` API — DECISIONS #23; `project.yml` already regenerated), SwiftUI, `@Observable` (not ObservableObject). No third-party dependencies — Apple frameworks only, by design.
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
9. **Translation is the only non-offline path.** First use of a new source→target pair needs a one-time system language-pack download (network + user consent); every pair is offline thereafter. Acceptance: airplane-mode replay of an already-translated page shows its `translatedText` with no network.
10. **Capture-first surface is designed, not built.** OCRService auto-detect + `OCRResult`, `OCRReviewView`, `Book.translationLanguage`/`Sentence.translatedText`, and ReadAloudSchemaV2 land with the Phase 2 SwiftData wiring (folds into gap #1). Acceptance: a scan with no pre-picked language reaches OCRReview, and a corrected source language flows through split → persist → Book.languageCode.

## 5. Testing strategy (to establish in Phase 2)

- Add `ReadAloudTests` unit target in `project.yml`.
- Priority order: `SRSState.review` (pure math, highest logic density) → `SentenceSplitter` (fixture strings per language) → `SpeechPlayer` queue logic (inject a synthesizer protocol if it gets hairy; don't test AVFoundation itself).
- OCR accuracy is validated by the `Tools/OCRSpike` CLI against `Fixtures/`, not by unit tests.
