# ReadAloud — Project Plan & Handoff Spec
*Language-learning iOS app: turn physical book text into listenable, reviewable audio.*

**Status:** Phase 1 — OCR spike in progress
**Last updated:** 2026-07-06
**Owner:** Ruby
**Target:** iOS 17.4+, SwiftUI, fully on-device

---

## 1. Problem Statement

Language learners acquire vocabulary and pronunciation best by **reading while listening** — the way children learn from parents. Physical books offer great reading material but no audio. Existing TTS tools work on digital text only, and don't support a learning loop (save → review).

**This app bridges that gap:** photograph a book page → hear each sentence spoken → save words/sentences → review with spaced repetition.

## 2. Goals & Non-Goals

**Goals**
- Convert photographed book text to per-sentence audio, offline
- Karaoke-style word highlighting synced with speech
- Save words and sentences with notes
- Spaced-repetition review mode
- Zero server dependency — private, works on a plane

**Non-Goals (v1)**
- No user accounts, sync, or cloud storage
- No handwriting recognition
- No full-book audiobook generation
- No social/sharing features
- No custom neural TTS voices (system voices only)

## 3. Core User Flow

```
Photo/Live Text → OCR → sentence split → tap to listen
     → bookmark/save → review later (SRS)
```

## 4. Screens

### 4.1 Home / Library
- List of Books (user-created containers for scan sessions)
- Primary CTA: "Scan" button
- Secondary: link to Saved Items, Review (with due-count badge)

### 4.2 Camera / Scan
- Live camera preview, capture button
- Photo-library import fallback
- Post-capture crop/rotate
- Assign scan to a Book (or quick-create)
- **Stretch:** VisionKit Live Text mode for instant tap-to-hear

### 4.3 Sentence Reader *(core screen — wireframe below)*
- Sentences rendered as tappable cards
- Tap → TTS playback, active card highlighted, word-level highlight follows speech
- Bottom playback bar: prev / play-pause / next, repeat toggle, speed (0.5×–1.0×)
- Star icon per sentence → bookmark
- Long-press word → Dictionary / Save Word / Translate
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
- Target language, preferred voice, default speech rate
- Link to iOS enhanced-voice downloads (Settings deep link)
- Data export (JSON) — stretch

## 5. Architecture

### 5.1 Stack
| Concern | Technology | Notes |
|---|---|---|
| UI | SwiftUI, iOS 17+ | @Observable macro |
| OCR | Vision `VNRecognizeTextRequest` | `recognitionLanguages` from Book.languageCode |
| Live scan | VisionKit `DataScannerViewController` | stretch |
| Sentence split | NaturalLanguage `NLTokenizer(.sentence)` | language-aware |
| TTS | `AVSpeechSynthesizer` | offline; `willSpeakRangeOfSpeechString` → highlight |
| Dictionary | `UIReferenceLibraryViewController` | built-in |
| Translation | Translation framework (iOS 17.4+) | stretch |
| Persistence | SwiftData | schema below |

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
- **Book** — title, languageCode (BCP-47), pages[] (cascade)
- **ScanPage** — imageData, rawText, orderIndex, sentences[] (cascade)
- **Sentence** — text, orderIndex, isBookmarked, userNote?, srs?
- **SavedWord** — word, contextSentence (snapshot), languageCode, userNote?, srs?
- **SRSState** — Codable struct, SM-2 (repetitions, easeFactor, intervalDays, dueDate)

Key decisions:
- `contextSentence` is a **string snapshot** so vocab survives page deletion
- `SRSState` is a value type shared by words and sentences
- `languageCode` on Book drives both OCR language and voice selection

### 5.4 Key Component: SpeechPlayer
```
@Observable SpeechPlayer
├── AVSpeechSynthesizer + AVSpeechSynthesizerDelegate
├── currentSentenceIndex: Int?
├── highlightRange: NSRange?     ← from willSpeakRangeOfSpeechString
├── rate: Float, repeatMode: Bool
└── play(sentences:startingAt:) / pause() / next() / previous()
```
Audio session: `.playback` category so audio continues with silent switch on.

## 6. Build Phases

### Phase 1 — MVP core loop (~1–2 wks)
- [ ] Camera capture + photo import
- [ ] OCRService (single language, hardcoded ok)
- [ ] SentenceSplitter
- [ ] Reader view: tap-to-play, playback bar (no highlight yet)
- [ ] No persistence
- **Exit criteria:** photograph a real book page, hear any sentence spoken correctly

### Phase 2 — Persistence + learning (~2 wks)
- [ ] SwiftData schema wired in
- [ ] Library, Book/Page management
- [ ] Bookmark sentences, save words (long-press menu)
- [ ] Saved Items screen with notes
- [ ] Word-level highlight in Reader

### Phase 3 — Review + polish (~2 wks)
- [ ] SRSEngine + Review mode
- [ ] Speed control, voice picker, Settings
- [ ] Dictionary lookup integration
- [ ] Empty states, error states, haptics

### Phase 4 — Stretch
- [ ] Live Text scan mode
- [ ] On-device translation popups
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
1. Target language: **per Book** (as modeled — `Book.languageCode` drives OCR + TTS voice)
2. Storage expiry: **keep pages forever** in v1; revisit if storage complaints arrive
3. Pricing: **free for v1** — no StoreKit; learn what users value before gating
4. Minimum iOS: **17.4** — unlocks Translation framework for Phase 4 stretch

## 9. Acceptance Criteria (v1 ship)
- Scan → listenable sentences in ≤ 10 s on iPhone 12+
- OCR word accuracy ≥ 95% on flat, well-lit pages
- Word highlight drift imperceptible (< 100 ms)
- All features functional in airplane mode
- Saved items and SRS state survive app restart
- VoiceOver-navigable Reader screen

## 10. Handoff Checklist
- [ ] This document reviewed with new owner
- [ ] `Models.swift` added to repo
- [ ] Target languages confirmed + TTS voices tested
- [ ] 5 sample book-page photos added as test fixtures
- [ ] Open questions (§8) answered and logged here
