# New Features & Capabilities

Concrete, reuse-first feature ideas for ReadAloud — each grounded in files that already exist, sized for a single implementer, and filtered against the current capability map so nothing here duplicates what already ships. Everything stays fully offline (Apple frameworks only) and follows the "energetic but not gamified" rule: no streaks, XP, points, or badges.

**How to read this** — Suggestions are grouped by theme; within each group they run quick-wins-first (best value-per-effort at top). Effort is S/M/L with dependencies; the triage table at the end is the fast pick-list.

---

## 1. Understand — grammar, examples, word depth

### More examples from your library
**What & why** — On any word, pull every other sentence you have already captured that contains it, across all books. Real cross-source reinforcement ("you have seen *encore* 4 other times") with zero model cost and high learner value.
**Reuse** — `Services/WordTokenizer.swift` for the term + a SwiftData fetch over `Sentence.text`; render in the Understand section of `Learn/SentenceLearnView.swift` and in `Saved/SavedItemDetailView.swift`. Genuinely new — no such query exists today.
**Effort** — M. No schema change, no AI.
**Notes** — Fully offline, no Foundation Models dependency. Warm framing ("seen elsewhere in your books"), never a count-as-score.

### Save-all key vocab
**What & why** — One tap in Understand saves every `keyVocab` item as word annotations with the sentence as context, instead of re-typing each. High-leverage capture accelerator right where the AI breakdown already surfaces vocab.
**Reuse** — `Learn/SentenceLearnView.swift` save-as-annotation path + `LearningAssets.keyVocab` (`Models/Models.swift:209`) + the `Annotation` model.
**Effort** — S. No schema change.
**Notes** — Offline; pure wiring on top of assets the app already generates.

### Grammar index
**What & why** — A browsable list of every grammar point you have saved, so patterns like "passé composé" collect in one place instead of scattering across sentences.
**Reuse** — `Features/Notes/NotesView.swift` filter-chip + paper-card list pattern (~line 304); filter `Annotation` by type `.grammar` plus `LearningAssets.grammarPoint` (`Models/Models.swift:210`). Pure aggregation view.
**Effort** — S/M. No schema change.
**Notes** — Offline; leans on the existing Notebook styling so it looks native.

### Word etymology / word-family via Understand
**What & why** — Extend the AI seam with a `wordDetail(term:)` call returning root/etymology + related forms, shown alongside the system dictionary. Fills the "offline dictionary depth" gap.
**Reuse** — Extend the `LearningAssetsProviding` protocol (`Services/LearningAssetsProvider.swift`, next to existing `draftExample`/`explainConfusion`); render in `Shared/DictionaryView.swift`'s lookup sheet.
**Effort** — M. Depends on Foundation Models availability gate (same iOS 26 gate as existing calls).
**Notes** — Apple-only; falls back to the system dictionary when the model is unavailable. Extends an existing service — not a new one.

---

## 2. Listen & Speak — pronunciation practice

### Production review face (`.speaking`)
**What & why** — A fourth card face: see the meaning, say the foreign word/phrase aloud, then reveal + hear the model TTS to self-check (ungraded / self-graded). Complements the recognition-only meaning/listening/cloze faces with an active-recall production loop.
**Reuse** — Extend the `CardFace` enum in `Services/SRSEngine.swift:6` + `ReviewItem.face` (~line 108); render in `Review/ReviewSessionView.swift`; model answer via `SpeechPlayer.speakOnce`.
**Effort** — M. Additive `CardFace` change only — safe under the migration guardrail (does not touch the embedded `SRSState`/`LearningAssets` Codable structs).
**Notes** — Offline; self-graded, no percentage or points.

### Pronunciation feedback (word-level)
**What & why** — After a shadowing take, transcribe it on-device and highlight which target words matched vs. missed — not a score. The single biggest missing loop for a speaking learner.
**Reuse** — `Services/VoiceRecorder.swift` already keeps the take file; `Review/ShadowingPracticeView.swift` owns the flow. Add `SFSpeechRecognizer` (on-device) + the WER helper already flagged in `docs/TASKS.md` (Phase 5 "pronunciation-compare"). No Speech framework exists yet — genuinely new.
**Effort** — L. New on-device Speech recognition path.
**Notes** — Apple-only, on-device offline recognition. Anti-gamification is load-bearing here: show "words to revisit," never a percentage. Matches the Phase 5 backlog.

---

## 3. Capture — batch & organize

### Batch page capture
**What & why** — Shoot several book pages in one session, OCR them as a queue, review/persist together instead of one-at-a-time. Adult learners photographing a chapter hit the current one-page wall constantly.
**Reuse** — `Scan/DocumentCameraView.swift` (VisionKit already returns multi-page scans but only page 0 is used, ~line 42); `Services/PageIngestor.swift` two-step recognize→ingest loop; `Scan/OCRReviewView.swift` as a per-page pager.
**Effort** — M. No schema change.
**Notes** — Offline; directly closes the "handling long content" gap and the "capture-first wiring polish" TODO in `docs/TASKS.md`.

### Collections (theme decks across books)
**What & why** — Group Books into named collections ("Café menus," "Le Petit Prince ch.1–3") so browsing and review can span sources.
**Reuse** — Add a lightweight `Collection` `@Model` with `books: [Book]` (a *new* `@Model` is an additive lightweight migration per DECISIONS #35 — it does **not** re-trigger a frozen-schema bump); surface it on `Library/LibraryView.swift` shelf rows. Feeds the cross-source review idea below.
**Effort** — L. Additive schema touch only.
**Notes** — Offline; the migration guardrail explicitly permits new `@Model`s.

---

## 4. Retain — cross-source review

### Review by source or collection
**What & why** — Let a session draw only from one book/collection ("just tonight's menu words") instead of the whole deck. Small, high-value control over what you drill.
**Reuse** — `Services/SRSEngine.swift` `buildSession(from:)` already takes a pre-filtered item list — add a source/collection filter upstream; entry point in `Review/ReviewView.swift`.
**Effort** — S. No schema change on its own; pairs with Collections.
**Notes** — Offline; pure filtering on the existing session builder.

---

## 5. Export & sharing

### Flashcard CSV / TSV export (Anki-ready)
**What & why** — Add a front/back/cloze TSV export next to the JSON backup so study material can leave the app for Anki/Quizlet. `ExportService` is JSON-only today.
**Reuse** — `Services/ExportService.swift` (add a `makeCSV`); `Services/ClozeBuilder.swift` for the cloze column; `Shared/ShareSheet.swift` for delivery.
**Effort** — S/M. New format, offline file generation.
**Notes** — No network; genuinely new export shape reusing existing serialization + cloze logic.

### Printable study sheet (PDF)
**What & why** — Render saved words + context + translation to a PDF via `ImageRenderer`, for offline drilling or handing to a tutor.
**Reuse** — `Saved/SavedItemsView.swift` data; the paper-card styling in `Shared/Styles/Cards.swift` as the print layout; `Shared/ShareSheet.swift`.
**Effort** — M. No schema change.
**Notes** — Offline; leans on the paper & ink identity (#36) so the sheet looks native.

---

## 6. Apple-surface reach — widgets, intents, extensions

> **Shared prerequisite (do once, reuse everywhere):** all widget / extension / Watch ideas need the SwiftData store moved into an **App Group** container so extensions can read the same DB. Today `App/ReadAloudApp.swift` builds a default `ModelContainer`. Do this once before picking any item in this section.

### App Intent query "How many words are due?"
**What & why** — A parameterless Siri/Shortcuts intent returning the due count as spoken output — check your standing without launching.
**Reuse** — `SRSEngine.dueCount(in:)` directly (`Services/SRSEngine.swift:202`).
**Effort** — S (after App Group).
**Notes** — Offline; shares the widget's data source, no new logic. Frame as readiness, not a streak.

### Due-count Home / Lock widget
**What & why** — A small widget showing "N ready to review" + next-due date; tap deep-links to the Review tab. A calm, glanceable nudge.
**Reuse** — `SRSEngine.dueCount(in:)` / `dueItems` (`Services/SRSEngine.swift:202,177`) — the exact call `AppRouter.recomputeDueCount` already makes (`App/AppRouter.swift:20`); `AnimatedMeshBackground`/`CountUpText` tokens for a paper-and-ink timeline entry.
**Effort** — M (after App Group).
**Notes** — Fully offline (local query). Readiness, **not** a streak/XP counter — anti-gamification rule.

### "Phrase of the day" widget
**What & why** — Surface one saved `Annotation` (term + `contextSentence`), rotating daily; tap opens `AnnotationDetailView`. Passive re-exposure to your own saved items on the Home Screen.
**Reuse** — `Annotation` model (`Models/Models.swift`) incl. `text`/`contextSentence`/`type.tint` (`Shared/Styles/SemanticColors.swift`); `Theme.termFont`/`sentenceFont` (`Shared/Styles/Theme.swift`) so the widget reads like a Notebook card.
**Effort** — M (after App Group).
**Notes** — Offline; pick deterministically by date so it stays stable across refreshes.

### App Intent + Siri Shortcut "Start my review"
**What & why** — An `AppIntent` that builds today's session and routes into it ("Hey Siri, start my French review"). Zero-friction, hands-free entry.
**Reuse** — `SRSEngine.buildSession(from:)` (`Services/SRSEngine.swift:207`) + `AppRouter.tab`/`dueCount` for routing (`App/AppRouter.swift:12`).
**Effort** — M (after App Group). Donate the intent so it appears in Spotlight/Shortcuts.
**Notes** — Apple-only App Intents; offline.

### Siri App Intent "Explain this word" (Foundation Models)
**What & why** — Pass a term to an intent that returns an on-device explanation via the existing provider — ask about a word conversationally from Siri/Shortcuts.
**Reuse** — `FoundationModelsAssetsProvider.explainConfusion`/`draftExample` + the `isAvailable` gate (`Services/LearningAssetsProvider.swift:132,115,63`).
**Effort** — M (after App Group). Depends on the same iOS 26 availability gate as in-app AI.
**Notes** — Offline, availability-gated; extends an existing service to a new Siri surface. Complements the in-app "Word etymology" idea above — same provider, different entry point.

### CoreSpotlight indexing of saved items
**What & why** — Index each `Annotation` (`text`, `contextSentence`, `userNote`, `tags`) and bookmarked `Sentence.text` as `CSSearchableItem`s so system search deep-links to `AnnotationDetailView`/Notes. Find a half-remembered saved word from system search.
**Reuse** — `Annotation`/`Sentence` fields (`Models/Models.swift`); the same search surface `NotesView` already exposes in-app. Hook indexing into the existing write paths in `SaveWordSheet`/`AnnotationDetailView`.
**Effort** — M (after App Group).
**Notes** — Offline; index on save/edit.

### Handoff / Spotlight "continue reading" (NSUserActivity)
**What & why** — Publish an `NSUserActivity` when a `ScanPage` opens so you can resume the same page on another device and it becomes searchable/handoff-able.
**Reuse** — `ScanPage.lastOpenedAt` (already drives Resume, `Models/Models.swift`) + `AppRouter.libraryPath` navigation (`App/AppRouter.swift:13`); the Resume header in `Features/Library/BookDetailView.swift`.
**Effort** — M. No schema change.
**Notes** — Offline (Handoff is local/AirDrop-class); no data leaves the account.

### Journaling Suggestions donation
**What & why** — Donate finished review sessions and newly-saved annotations as suggestions to Apple's Journal app — reflect on what you learned inside an existing journaling habit. A grown-up, reflective alternative to streaks.
**Reuse** — `Annotation.savedAt` + the session-summary data already computed in `Review/ReviewSessionView.swift`.
**Effort** — M (after App Group).
**Notes** — Apple-only, offline; strong anti-gamification fit (reflection, not point-scoring).

### Share / Action Extension: capture selected text
**What & why** — Accept text shared from Safari/Books/Mail → run the existing ingest path → new source (`SourceKind.screenshot`/`.other`). Save real-world text you hit while browsing, not just camera captures.
**Reuse** — `SentenceSplitter` + `PageIngestor.ingest()` (`Services/PageIngestor.swift`) + the `SourceKind` auto-title logic already in `Features/Scan/OCRReviewView.swift`/`AssignBookView`.
**Effort** — L (new extension target + App Group).
**Notes** — Offline; big reuse of the whole capture→Sentence pipeline — only the entry point is new.

### Apple Watch review companion
**What & why** — A minimal Watch app running the three existing card faces (meaning / cloze / listening) for a quick wrist review; listening cards speak on the Watch. Micro-reviews away from the phone.
**Reuse** — `SRSEngine.ReviewItem` faces + `promptText`/`revealText` + `grade` (`Services/SRSEngine.swift:108`) and `SpeechPlayer.speakOnce` (`Services/SpeechPlayer.swift:212`).
**Effort** — L (App Group + WatchConnectivity + new Watch target).
**Notes** — Offline; keep UI to reveal + 4 grades, no gamified chrome.

---

## Lower priority / conditional

- **Action Extension: image → OCR from other apps** — share a photo/screenshot into ReadAloud, OCR it, land in OCR review. Reuse: `OCRService` + `PageIngestor.recognize()` + `ImageProcessor`. Effort: L. **Overlaps the in-app import path and the Share-text extension** — pick this only if the text extension proves insufficient.
- **Reader playback Live Activity** — show the current sentence (+ translation) on the Lock Screen during TTS. Reuse: `SpeechPlayer` queue + `highlightRange` + the `managesNowPlaying` path (`Services/SpeechPlayer.swift:37,92`). Effort: M. **Incremental** — Now Playing already covers most of this; polish, not new capability.
- **Focus filters** — *Not recommended.* ReadAloud has no per-Focus mode worth toggling (no notifications, no feed); ceremony without learner value. Skip unless a "study-only" mode emerges.

---

## Migration guardrail (applies to every schema-touching idea above)

Any idea that only adds a new `@Model` (Collections) or a new `CardFace`/protocol method (`.speaking` face, `wordDetail`) is safe under the existing lightweight migration plan. **Do not touch the embedded `SRSState`/`LearningAssets` Codable structs** — changing either forces a frozen-schema version bump (DECISIONS #35, `Models/Schema.swift`).

---

## Triage table

| Suggestion | Impact | Effort | Reuses |
|---|---|---|---|
| More examples from your library | High | M | WordTokenizer, SwiftData fetch over Sentence.text |
| Save-all key vocab | Med | S | SentenceLearnView save path, LearningAssets.keyVocab |
| Grammar index | Med | S/M | NotesView list pattern, Annotation `.grammar` + grammarPoint |
| Review by source or collection | Med | S | SRSEngine.buildSession(from:), ReviewView |
| Flashcard CSV/TSV export | Med | S/M | ExportService, ClozeBuilder, ShareSheet |
| App Intent "How many words due?" | Med | S* | SRSEngine.dueCount |
| Production review face (`.speaking`) | High | M | CardFace enum, ReviewSessionView, SpeechPlayer.speakOnce |
| Batch page capture | High | M | DocumentCameraView (multi-page), PageIngestor, OCRReviewView |
| Word etymology via Understand | Med | M | LearningAssetsProviding, DictionaryView |
| Printable study sheet (PDF) | Med | M | SavedItemsView, Cards.swift styling, ShareSheet |
| Due-count widget | Med | M* | SRSEngine.dueCount/dueItems, AppRouter.recomputeDueCount |
| "Phrase of the day" widget | Med | M* | Annotation model, Theme fonts, SemanticColors |
| "Start my review" App Intent | Med | M* | SRSEngine.buildSession, AppRouter |
| "Explain this word" Siri Intent | Med | M* | FoundationModelsAssetsProvider, isAvailable gate |
| CoreSpotlight indexing | Med | M* | Annotation/Sentence fields, save paths |
| Handoff "continue reading" | Low/Med | M | ScanPage.lastOpenedAt, AppRouter.libraryPath |
| Journaling Suggestions donation | Med | M* | Annotation.savedAt, ReviewSessionView summary |
| Pronunciation feedback (word-level) | High | L | VoiceRecorder, ShadowingPracticeView + SFSpeechRecognizer (new) |
| Collections (theme decks) | Med | L | New Collection @Model, LibraryView |
| Share extension: capture text | High | L* | SentenceSplitter, PageIngestor.ingest, SourceKind |
| Apple Watch review companion | Med | L* | SRSEngine.ReviewItem faces, SpeechPlayer.speakOnce |

\* Requires the one-time App Group container move (`App/ReadAloudApp.swift`).
