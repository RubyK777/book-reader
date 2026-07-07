# ReadAloud — Project Plan & Handoff Spec
*Language-learning iOS app: turn physical book text into listenable, reviewable audio.*

**Status:** Phase 1 core loop built (scan → tap-to-hear works; word highlight shipped early). OCR spike on real fixtures still pending. Phase 2 next.
**Last updated:** 2026-07-06
**Owner:** Ruby
**Target:** iOS 18.0+, SwiftUI, fully on-device

> **Detailed design docs live in [`docs/`](docs/)** — architecture, per-phase designs, UX/audio/OCR/testing specs, the carry-forward backlog ([docs/TASKS.md](docs/TASKS.md)), and the decision log ([docs/DECISIONS.md](docs/DECISIONS.md)). This file stays the high-level spec; the docs carry the implementation detail.

---

## 1. Problem Statement

Language learners acquire vocabulary and pronunciation best by **reading while listening** — the way children learn from parents. Physical books offer great reading material but no audio. Existing TTS tools work on digital text only, and don't support a learning loop (save → review).

**This app bridges that gap:** photograph a book page → hear each sentence spoken → save words/sentences → review with spaced repetition.

## 2. Goals & Non-Goals

**Goals**
- Convert photographed book text to per-sentence audio, offline
- Read text in **any auto-detected source language** — no pre-picking; the language is detected
  from the page and confirmed at scan (bounded to Vision's `.accurate` supported scripts —
  Latin + zh/ja/ko/… — see §5.1, docs/OCR_PIPELINE.md)
- **Correct the OCR text** before it is saved (full-text edit at scan time)
- **Inline, persisted translation** under each sentence as a learning aid (never spoken — TTS
  stays on the source; iOS 18 Translation framework, docs/TRANSLATION_DESIGN.md)
- Karaoke-style word highlighting synced with speech
- Save words and sentences with notes
- Spaced-repetition review mode
- Zero server dependency — private, works on a plane (one exception: the first translation of a
  new language pair triggers a one-time system pack download — §9)

**Non-Goals (v1)**
- No user accounts, sync, or cloud storage
- No handwriting recognition
- No full-book audiobook generation
- No social/sharing features
- No custom neural TTS voices (system voices only)
- No re-splitting a saved page from edited full text (would destroy sentence-level SRS/bookmarks —
  post-save fixes are merge/split only; docs/PHASE3_DESIGN.md §6)

## 3. Core User Flow

```
Photo/Live Text → OCR → sentence split → tap to listen
     → bookmark/save → review later (SRS)
```

## 4. Screens

### 4.1 Home / Library
- Library is the first tab of the app-wide TabView root — Library · Saved · Review · Settings
  (docs/UX_SPEC.md §1; DECISIONS.md #3)
- List of Books (user-created containers for scan sessions)
- Toolbar `+` creates a Book; a separate **Scan** button (and the empty-state CTA) launches capture
  (docs/PHASE2_DESIGN.md §3; DECISIONS.md #20)
- Saved Items and Review are sibling tabs, not links; the Review tab carries the due-count badge

### 4.2 Camera / Scan *(capture-first)*
- **Capture-first flow** — OCR auto-detects the source language, so nothing is picked up front.
  This supersedes the old "assign-before-capture so OCR knows the language" ordering (every scan
  still persists into a Book — DECISIONS.md #4/#21):
  ```
  Library (book unknown):
    capture/import → OCR(auto-detect) → OCRReview(edit text · confirm source language · choose translate-to)
      → assign (pick or quick-create Book; source language pre-filled from detection) → persist → push Reader
  Book-detail "Add Page" (book known):
    capture/import → OCR(languageHint = book.languageCode) → OCRReview(edit text · confirm source language ·
      translate-to inherited from book) → persist → push Reader
  ```
- System document camera (`VNDocumentCameraViewController`) — auto edge detection, deskew,
  multi-page capture (docs/OCR_PIPELINE.md §1)
- Photo-library import fallback
- Post-capture crop/rotate — provided by the document camera's corner-adjust review step on the
  camera path; imports skip crop in v1 (the OCR quality gate catches bad ones)
- **Stretch:** VisionKit Live Text mode for instant tap-to-hear

### 4.2a OCR Review / Edit *(new — between OCR and persistence)*
- `Features/Scan/OCRReviewView.swift`, shown AFTER OCR and BEFORE anything is saved — so editing
  is free (no SRS/bookmark at risk).
- Full-height `TextEditor` prefilled with `OCRResult.text`; a **source-language Picker** prefilled
  with `detectedLanguageCode` (correcting it here is how the user fixes a wrong detection); the
  optional **translate-to Picker** (§4.7).
- `Use` splits the **edited** text via `SentenceSplitter` using the confirmed source language, then
  persists (source language auto-sets `Book.languageCode` on the first page). `Retake` → capture.

```
┌─────────────────────────────┐
│ ✕ Review          [Use]     │
├─────────────────────────────┤
│ Source: [Français ▾]        │  ← prefilled from detection, correctable
│ Translate to: [English ▾]   │  ← optional (None = off)
├─────────────────────────────┤
│ Le petit prince vivait sur  │
│ une planète à peine plus    │  ← editable full OCR text
│ grande que lui.             │
│ …                           │
├─────────────────────────────┤
│           [Retake]          │
└─────────────────────────────┘
```

### 4.3 Sentence Reader *(core screen — wireframe below)*
- Sentences rendered as tappable cards
- Tap → TTS playback, active card highlighted, word-level highlight follows speech
- Bottom playback bar: prev / play-pause / next, repeat toggle, speed (0.5×–1.0×)
- Star icon per sentence → bookmark
- Long-press sentence card → word-chip sheet → Save Word / Look Up (card-level gesture supersedes
  per-word long-press — see docs/PHASE2_DESIGN.md §7)
- **Translation under each card** — if the book has a translate-to language, the persisted
  `Sentence.translatedText` renders under the sentence in a secondary style (`.secondary`, slightly
  smaller, visually separated). Toolbar `[⋯]` menu picks the per-book translate-to language; a
  toolbar toggle shows/hides translations. TTS always speaks the SOURCE — translation is visual only.
  Full design in docs/TRANSLATION_DESIGN.md.
- Auto-scroll keeps active card centered

```
┌─────────────────────────────┐
│ ← Page 3         [Aa] [⋯]  │
├─────────────────────────────┤
│ ┌─────────────────────────┐ │
│ │ Le petit prince vivait  │ │   idle card
│ │ sur une planète.    ☆   │ │
│ └─────────────────────────┘ │
│ ┏━━━━━━━━━━━━━━━━━━━━━━━━━┓ │
│ ┃ Il regardait le ▌coucher┃ │   ACTIVE card:
│ ┃ du soleil chaque soir.★ ┃ │   tinted, word highlight
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━┛ │
│ ┌─────────────────────────┐ │
│ │ Un jour, il décida de   │ │
│ │ partir en voyage.   ☆   │ │
│ └─────────────────────────┘ │
├─────────────────────────────┤
│  ◁◁      ▶ / ⏸      ▷▷     │
│  🔁 repeat   0.75× ▾ speed  │
└─────────────────────────────┘
```

**Design principle:** active card is visually loud (tint + slight scale), rest quiet — users glance between phone and physical book and must re-find their place instantly.

### 4.4 Saved Items
- Tabs: **Words** | **Sentences**
- Row: text, replay button, source book, date
- Detail: personal note field, context sentence, SRS stats

### 4.5 Review Mode
- Flashcard flow, listen-first: audio plays → user recalls → reveal text
- Self-grade buttons: Again / Hard / Good / Easy → maps to SM-2 quality 1/3/4/5
- Session = all items with `dueDate <= now`, capped at 20

### 4.6 Settings
- **Native language** — your own language (`@AppStorage("nativeLanguage")`, default = device language),
  the translation **destination**. Replaces the misnamed `targetLanguage`; it is *not* a source picker —
  the source language of each book is per-book and **auto-detected** at scan (DECISIONS.md #25).
- Preferred voice (per source language), default speech rate
- **Translate new books (on/off default)** — `@AppStorage("translationLanguage")` with a **None** (off)
  option; when on, new books translate into the **native language**. Sits beside `nativeLanguage` /
  `speechRate` / `voiceID`.
- Enhanced-voice download guidance: in-app instruction card — Settings deep links into
  Accessibility are private API (`App-Prefs:` schemes) and App Store-rejectable; see
  [docs/PHASE3_DESIGN.md](docs/PHASE3_DESIGN.md) §4
- Data export (JSON) — stretch

### 4.7 Translation *(new — inline learning aid)*
- Whole-page, **persisted** translation shown under each sentence card (§4.3), never spoken.
- Destination is the user's **native language** (`@AppStorage("nativeLanguage")`, §4.6); the per-Book
  target `Book.translationLanguage` (Reader `[⋯]` menu · OCRReview · BookForm) is **seeded from it**
  when translation is on. Changing `Book.translationLanguage` clears that book's stale
  `Sentence.translatedText` → re-translated lazily on next Reader open.
- iOS 18 Translation framework: SwiftUI's `.translationTask` provides a `TranslationSession`;
  sentences are batch-translated and written back to `Sentence.translatedText` (offline thereafter).
  Full design + API facts in docs/TRANSLATION_DESIGN.md. Word-level translate is a nice-to-have
  reusing the same target.

## 5. Architecture

### 5.1 Stack
| Concern | Technology | Notes |
|---|---|---|
| UI | SwiftUI, iOS 18+ | @Observable macro |
| OCR | Vision `VNRecognizeTextRequest` | `automaticallyDetectsLanguage = true`; optional `languageHint` from Book.languageCode or a pre-capture Page-language hint; source options = `LanguageCatalog` (unrestricted, replaced 9-item `SupportedLanguage`) |
| Language detect | NaturalLanguage `NLLanguageRecognizer` | dominant language of assembled OCR text → `detectedLanguageCode` |
| Live scan | VisionKit `DataScannerViewController` | stretch |
| Sentence split | NaturalLanguage `NLTokenizer(.sentence)` | language-aware |
| TTS | `AVSpeechSynthesizer` | offline; `willSpeakRangeOfSpeechString` → highlight; speaks source only |
| Dictionary | `UIReferenceLibraryViewController` | built-in |
| Translation | Translation framework (iOS 18) | inline persisted; `.translationTask` + `TranslationSession`; docs/TRANSLATION_DESIGN.md |
| Persistence | SwiftData | schema below (ReadAloudSchemaV2) |

### 5.2 Module Layout
```
ReadAloud/
├── App/                 entry, DI, routing
├── Models/              SwiftData models + SRSState (see Models.swift)
├── Services/
│   ├── OCRService       photo → recognized text
│   ├── SentenceSplitter text → [String] (NLTokenizer)
│   ├── SpeechPlayer     TTS engine + highlight ranges (@Observable)
│   └── SRSEngine        due queries, review grading
├── Features/
│   ├── Library/
│   ├── Scan/
│   ├── Reader/
│   ├── Saved/
│   ├── Review/
│   └── Settings/
└── Shared/              components, extensions
```

### 5.3 Data Model (summary — full code in Models.swift)
- **Book** — title, languageCode (BCP-47, **auto-set** from the confirmed source language of the
  first page; editable later), `translationLanguage: String?` (BCP-47; nil = translation off), pages[] (cascade)
- **ScanPage** — imageData, rawText, orderIndex, sentences[] (cascade)
- **Sentence** — text, orderIndex, isBookmarked, userNote?, srs?, `translatedText: String?` (persisted)
- **SavedWord** — word, contextSentence (snapshot), languageCode, userNote?, srs?
- **SRSState** — Codable struct, SM-2 (repetitions, easeFactor, intervalDays, dueDate)

`translationLanguage` + `translatedText` (plus PHASE3's `SavedWord.sourceBookTitle`) join
**ReadAloudSchemaV2** — one lightweight migration adds all the optional fields together.

Key decisions:
- `contextSentence` is a **string snapshot** so vocab survives page deletion
- `SRSState` is a value type shared by words and sentences
- `languageCode` on Book is the **source** language: it drives both OCR language and voice selection,
  and is no longer pre-picked — detection (`OCRResult.detectedLanguageCode`, via NLLanguageRecognizer)
  confirms it in OCRReview; where a source language is chosen the options are the **full, unrestricted
  `LanguageCatalog`** (Vision-derived, not a curated nine — DECISIONS.md #25). The user's **native**
  language (`@AppStorage("nativeLanguage")`) is a separate per-user setting = the translation destination.
- `translatedText` is cleared when `Book.translationLanguage` changes (stale) → re-translated lazily

### 5.4 Key Component: SpeechPlayer
```
@Observable SpeechPlayer
├── AVSpeechSynthesizer + AVSpeechSynthesizerDelegate
├── currentSentenceIndex: Int?
├── highlightRange: NSRange?     ← from willSpeakRangeOfSpeechString
├── speedMultiplier: Float (0.5×–1.0×, applies on next utterance), repeatMode: Bool
└── load(sentences:languageCode:) / play(at:) / togglePlayPause() / next() / previous() / stop()
```
Audio session: `.playback` category so audio continues with silent switch on.
This mirrors the shipped surface — docs/ARCHITECTURE.md §2 is the authoritative current-state
contract; docs/AUDIO_DESIGN.md §1 designs its evolution.

## 6. Build Phases

### Phase 1 — MVP core loop (~1–2 wks)
- [x] Camera capture + photo import
- [x] OCRService (language picker, per-scan)
- [x] SentenceSplitter
- [x] Reader view: tap-to-play, playback bar (word highlight shipped early too)
- [x] No persistence
- [ ] OCR spike validated on 5 real book-page fixtures (§7 risk #1 — still open)
- **Exit criteria:** photograph a real book page, hear any sentence spoken correctly

### Phase 2 — Persistence + learning (~2 wks)
- [ ] SwiftData schema wired in (ReadAloudSchemaV2)
- [ ] Library, Book/Page management
- [ ] **Auto-detected source language** — capture-first OCR (`automaticallyDetectsLanguage`) +
  `NLLanguageRecognizer` → `detectedLanguageCode`; Book.languageCode auto-set (docs/OCR_PIPELINE.md)
- [ ] **OCR review/edit** — `OCRReviewView` (edit text · confirm source · pick translate-to) before persist
- [ ] **Inline translation** (iOS 18 Translation framework) — `.translationTask` batch-translates a
  page, persists `Sentence.translatedText`, renders under cards with a Reader toggle
  *(spans Phase 2/3; full design docs/TRANSLATION_DESIGN.md)*
- [ ] Bookmark sentences, save words (card long-press → chip sheet, per docs/PHASE2_DESIGN.md §7)
- [x] Word-level highlight in Reader *(done in Phase 1)*

### Phase 3 — Review + polish (~2 wks)
- [ ] SRSEngine + Review mode
- [ ] Saved Items screen with notes *(moved from Phase 2 — needs SRS stats + `sourceBookTitle`; see docs/PHASE2_DESIGN.md §3, docs/PHASE3_DESIGN.md §3)*
- [ ] Speed control, voice picker, Settings (incl. default translate-to language)
- [ ] Translation polish — per-book language picker, show/hide toggle, clear-on-target-change
- [ ] Dictionary lookup integration
- [ ] Empty states, error states, haptics

### Phase 4 — Stretch
- [ ] Live Text scan mode
- [ ] Word-level translate (reuse the book's translate-to target)
- [ ] Shadowing: record & compare
- [ ] Continuous page playback
- [ ] JSON export

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| OCR on curved/glossy book pages | High — core loop breaks | **Prototype first.** Encourage flat pages, good light; add crop step; test Vision accuracy on 5 real books before Phase 1 ends |
| System TTS quality varies by language | Med — retention | Test target languages day 1; surface enhanced-voice download prompt |
| Sentence splitting on dialogue/abbreviations | Med | NLTokenizer is decent; allow manual merge/split of sentences (Phase 3) |
| OCR merges two-column layouts | Low–Med | Use Vision bounding boxes to sort by column if needed |
| SwiftData migration pain later | Low | Keep schema minimal; version from start |

## 8. Open Questions — ✅ decided 2026-07-06
1. Source language: **auto-detected**, confirmed in OCRReview (capture-first) and auto-set on the
   Book; `Book.languageCode` still drives OCR hint + TTS voice. Translate-to language: **per Book**.
2. Storage expiry: **keep pages forever** in v1; revisit if storage complaints arrive
3. Pricing: **free for v1** — no StoreKit; learn what users value before gating
4. Minimum iOS: **18.0** — the inline/programmatic Translation API (`TranslationSession`,
   `.translationTask`) is iOS 18. (17.4 gave the framework but only the on-demand
   `.translationPresentation` sheet, rejected for not being inline/persisted — DECISIONS.md #23)

## 9. Acceptance Criteria (v1 ship)
- Scan → listenable sentences in ≤ 10 s **per page** on iPhone 12+ (a multi-page batch legitimately
  takes proportionally longer — docs/OCR_PIPELINE.md §1; DECISIONS.md #17)
- OCR word accuracy ≥ 95% on flat, well-lit pages
- Word highlight drift imperceptible (< 100 ms)
- Source language auto-detected correctly on flat, well-lit pages of a supported script; wrong
  detection is fixable in OCRReview before saving
- Inline translation renders under each sentence and persists across restart; TTS speaks the source
  only; changing a book's translate-to language re-translates on next open
- All features functional in airplane mode — **one exception**: the first translation of a new
  language pair needs network once to download the system language pack (fully offline thereafter)
- Saved items and SRS state survive app restart
- VoiceOver-navigable Reader screen (translation is its own labeled element within the sentence card)

## 10. Handoff Checklist
- [ ] This document reviewed with new owner
- [x] `Models.swift` added to repo (not yet wired — first Phase 2 task)
- [ ] Target languages confirmed + TTS voices tested
- [ ] 5 sample book-page photos added as test fixtures
- [x] Open questions (§8) answered and logged here
- [x] Detailed design docs written (`docs/` — 2026-07-06)
