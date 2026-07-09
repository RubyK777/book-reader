# ReadAloud — Architecture (current state)

*Companion to [PROJECT_PLAN.md](../PROJECT_PLAN.md) §5. This document describes what is actually built as of 2026-07-09, the contracts between components, and known gaps. Update it when structure changes, not for every feature.*

> **Pivot note (2026-07-09):** the project has pivoted to real-world language learning — signs, menus, and screenshots become first-class sources alongside book pages. **[PIVOT_PLAN.md](PIVOT_PLAN.md) is the current master plan** (Phases 0–5, decisions D1–D11, reuse map); this document describes the shipped baseline that plan builds on.

## 1. System overview

On-device pipeline. No networking **except** the one-time system language-pack download the Translation framework triggers the first time a new source→target pair is used (§2 · [TRANSLATION_DESIGN.md](TRANSLATION_DESIGN.md)). Every other operation — all OCR, all TTS, and every already-translated page — is offline; the "works on a plane" promise holds after that first, per-pair download.

Capture-first: the user no longer pre-picks a source language. OCR auto-detects it, and the user confirms/corrects it in a review screen **before** anything is persisted.

**Two language axes** (DECISIONS #25). *Source* = the language on the page: a property of the **Book/page**, auto-detected, correctable, optionally hinted before capture — its option set is `LanguageCatalog` (`Shared/Languages.swift`), derived from Vision's `supportedRecognitionLanguages`, which **replaced the old 9-item `SupportedLanguage` enum** (source is no longer restricted to nine curated languages). *Native* = the user's own language: the per-user global setting `@AppStorage("nativeLanguage")` (default `LanguageCatalog.deviceDefaultNative`), which is the translation **destination** and **replaces the misnamed `targetLanguage`**. Recognizing, hearing (installed voices), and translating (`LanguageAvailability`) a language are three separately-bounded sets, never one gate.

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

Persistence (SwiftData, `Models.swift`) is **live**: `ReadAloudApp.swift:24` attaches `.modelContainer` (versioned `ReadAloudSchemaV1` + migration plan, `Models/Schema.swift`), and every feature area reads/writes models through `@Environment(\.modelContext)` (Reader saves/bookmarks, Saved, Review grading, Notes, Settings export).

## 2. Component contracts

### OCRService (`Services/OCRService.swift`)
`recognizeText(in: UIImage, languageHint: String? = nil) async throws -> OCRResult`
- Runs Vision `.accurate` with `usesLanguageCorrection` and `automaticallyDetectsLanguage = true` (iOS 16+), on a detached user-initiated task — the source language is **no longer required up front**. When a Book already has a language (Add-Page path), callers pass it as `languageHint`, which sets `recognitionLanguages = [hint]` to bias accuracy.
- Returns `OCRResult` (struct defined in [OCR_PIPELINE.md](OCR_PIPELINE.md)): `text: String` plus `detectedLanguageCode: String`, computed by running `NLLanguageRecognizer` over the assembled text (`.dominantLanguage` → BCP-47, e.g. `"fr"`). Vision exposes no reliable per-page language, so NL does the detection.
- **Honest limit:** "any language" = anything in `VNRecognizeTextRequest.supportedRecognitionLanguages` for the `.accurate` revision (Latin scripts + zh/ja/ko/…) — a bounded list, **not literally every language**, surfaced app-wide as `LanguageCatalog` (`Shared/Languages.swift`, which replaced the old 9-item `SupportedLanguage` enum). Far broader than the retired nine, but still bounded.
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
- `ScanHomeView` — **deleted in Phase 2.** It was the Phase 1 root: a mandatory source-language picker, camera/photo import, OCR+split inline, Reader pushed via `navigationDestination(item:)`. The `extension [String]: @retroactive Identifiable` hack died with it when the `RootView` TabView + `ScanFlowView` (`Features/Scan/`) landed. *Superseded:* its mandatory pre-pick is gone (source is auto-detected); what survives is an **optional pre-capture "Page language" hint** over `LanguageCatalog` on the Library scan entry, and the old `@AppStorage("targetLanguage")` is replaced by `@AppStorage("nativeLanguage")` (the native/translation-destination setting — DECISIONS #25).
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
- Capture is now `DocumentCameraView` (`VNDocumentCameraViewController`) plus `LiveTextCameraView` (VisionKit Live Text with manual shutter — shipped, no longer a Phase 4 stretch) and the `PhotosPicker` import path, all inside `Features/Scan/ScanFlowView`.

### Models (`Models/Models.swift`) — live since Phase 2
`Book (title, languageCode, translationLanguage?) 1─* ScanPage (imageData, rawText, orderIndex) 1─* Sentence (text, translatedText?, orderIndex, isBookmarked, userNote, srs)`, plus standalone `SavedWord (word, contextSentence snapshot, languageCode, srs)`. `SRSState` is a Codable **value type** (SM-2) embedded in both Sentence and SavedWord.

`Book.languageCode` (the **source** language) is now **auto-set** from the confirmed source language of the first page (detected by OCR, editable later) rather than pre-picked; `BookFormView` no longer forces a language choice at create time, and where a source language *is* chosen (OCRReview, BookForm edit, pre-capture hint) the options are the full `LanguageCatalog` set. `Book.translationLanguage: String?` (BCP-47; nil = translation off) is the **destination**, seeded from the user's `@AppStorage("nativeLanguage")` when translation is on (DECISIONS #25). `Book.translationLanguage` and `Sentence.translatedText: String?` join **ReadAloudSchemaV2** — the single lightweight migration (introduced in PHASE3 for `SavedWord.sourceBookTitle`) that adds all new optional fields at once. Changing `translationLanguage` clears the book's `translatedText` (now stale) → re-translated lazily on next Reader open (DECISIONS #24).

> ⚠️ Because `SRSState` is a Codable blob, **`#Predicate` cannot reach `srs.dueDate`**. Due-item queries must fetch candidates (bookmarked sentences / all saved words) and filter in memory. Fine at personal-library scale; if it ever isn't, promote `dueDate` to a stored property. Logged in [DECISIONS.md](DECISIONS.md).

## 3. Conventions

- **Project file is generated.** Edit `project.yml`, run `xcodegen generate`. Never hand-edit the `.xcodeproj`.
- iOS 18.0+ (raised from 17.4 for the inline/programmatic `TranslationSession` API — DECISIONS #23; `project.yml` already regenerated), SwiftUI, `@Observable` (not ObservableObject). No third-party dependencies — Apple frameworks only, by design.
- Feature-first layout: `Features/<Name>/` per screen area; cross-cutting logic in `Services/`; shared UI in `Shared/`.
- `languageCode` is always full BCP-47 (`"fr-FR"`); trim to 2 letters only at NL/Vision API boundaries.
- **Source vs. native language** (DECISIONS #25): the *source* language is per-Book, auto-detected, and chosen (when needed) from `LanguageCatalog` (Vision-derived, unrestricted — not a curated nine); the *native* language is `@AppStorage("nativeLanguage")`, the per-user translation destination that replaced `targetLanguage`. Never route a source language through a `targetLanguage` setting.
- All user-facing strings inline for now; localization is out of scope for v1.

## 4. Known gaps / tech debt (as of 2026-07-09)

Tracked with owners-of-record in [TASKS.md](TASKS.md). Resolved since the last audit (Phases 2–3 shipped): SwiftData container wired (`ReadAloudApp.swift:24`, versioned schema + migration plan); `ReadAloudTests` unit target (SRS math + text processing, green); `SpeechPlayer` interruption/route-change handling; background `audio` mode + lock-screen Now Playing controls; the `[String]: @retroactive Identifiable` hack (deleted with `ScanHomeView` when `RootView`/`ScanFlowView` landed); post-capture crop via the document camera's corner-adjust step; and the whole capture-first surface (`ScanFlowView`, `OCRReviewView`, `LiveTextCameraView`, auto-detect, translation persistence). Still open:

1. OCR single-column assumption — two-column pages interleave; mitigation (column clustering by midX) is a backlog item. Hyphenated line breaks are not repaired.
2. `SavedWord.sourceBookTitle` is planned (`Models/Schema.swift` comment) but not in the model — a saved word doesn't record which book/source it came from.
3. **Imported photos have no crop step** — only doc-camera pages get the system corner-adjust (DECISIONS #15); the bad-scan quality gate is the backstop, an import-crop UI remains a carry-forward.
4. `SpeechPlayer`: speed changes apply on the next utterance, not mid-sentence; the audio session is never deactivated (defensible now that background audio is a feature, but unexamined).
5. `Fixtures/` still holds no photos — the OCR spike has never run against real images. [PIVOT_PLAN.md](PIVOT_PLAN.md) task 0.2 closes this with ~15 real-world French fixtures (signs, menus, kids' books, screenshots).
6. Multi-page batch capture: the doc camera can return batches, but the pipeline ingests one page per scan — deferred to PIVOT_PLAN Phase 5.
7. **Translation is the only non-offline path.** First use of a new source→target pair needs a one-time system language-pack download (network + user consent); every pair is offline thereafter. Acceptance: airplane-mode replay of an already-translated page shows its `translatedText` with no network.

## 5. Testing strategy (established)

- `ReadAloudTests` unit target exists (`project.yml`): `SRSStateTests` (SM-2 math) and `TextProcessingTests` (sentence splitting / tokenization) — the two highest-logic-density targets, green.
- Still untested by design: `SpeechPlayer` queue logic (inject a synthesizer protocol if it gets hairy; don't test AVFoundation itself).
- OCR accuracy is validated by the `Tools/OCRSpike` CLI against `Fixtures/`, not by unit tests — blocked on gap #5 (no fixtures yet; PIVOT_PLAN task 0.2).
