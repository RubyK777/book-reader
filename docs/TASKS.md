# ReadAloud — Task Backlog

*Source of truth for "what do I build next". This file indexes the carry-forward sections of the
design docs — full task wording and acceptance criteria live there; tick items in both places as
they land. Order within a phase is roughly dependency order.*

**⟶ The pivot backlog below ([PIVOT_PLAN.md](PIVOT_PLAN.md)) is the active work; pre-pivot
phases further down are the shipped foundation plus optional polish.**

## Pivot Phase 0 — spikes & housekeeping (PIVOT_PLAN §7)

- [ ] 0.1 Foundation Models quality spike — harness done (`Tools/LearnSpike`, `Fixtures/french_sentences.txt`) but the quality run is **BLOCKED on this Mac**: Apple Intelligence not enabled + macOS 26.0 beta 2 ABI mismatch vs the Xcode 26.2 SDK (see `docs/SPIKE_RESULTS.md`). Unblock: update to release macOS 26, enable Apple Intelligence, rerun `swift Tools/LearnSpike/main.swift Fixtures/french_sentences.txt`, grade vs the ≥80%-usable bar. **The Phase 2 quality gate stays open until this runs** (running the app on an Apple Intelligence iPhone also works — SentenceLearnView exercises the same path).
- [ ] 0.2 Scene-text OCR fixtures — **needs ~15 real photos from Ruby** (French signs, menus, kids' books, screenshots) into `Fixtures/`, then `swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg`; fragment rule already specced (UX_SPEC §8)
- [x] 0.3 Voice audit CLI (`Tools/VoiceAudit`) — ran: 18 fr-* voices installed, **none enhanced/premium** (best default-tier: Thomas fr-FR). Ruby: download enhanced/premium French voices (Settings → Accessibility → Spoken Content), rerun the tool, pick by ear.
- [x] 0.4 ARCHITECTURE.md un-staled (§4 gaps now match code, dated 2026-07-09)

## Pivot Phase 1 — Schema V2 + restructure (PIVOT_PLAN §6)

- [x] Frozen `ReadAloudSchemaV1` snapshot + `ReadAloudSchemaV2` + `.lightweight` migration stage (DECISIONS #26 honored — Ruby's on-device store migrates; proven by `MigrationTests.v1StoreMigratesToV2`)
- [x] `Book.kindRaw` + `SourceKind` (book | sign | menu | screenshot | other)
- [x] `Annotation` @Model (typed word/phrase/sentence/grammar, optional intent, tags, SRS, sentence-parented) — the pivot's save unit (D3)
- [x] `LearningAssets` Codable on `Sentence` (chunks, key vocab, grammar point, D7 provenance fields)
- [ ] Quick Scan entry (scan without book assignment → lightweight source) — `ScanFlowView`/`OCRReviewView` "no book" branch
- [ ] Library renders non-book source kinds (kind icon instead of cover ceremony)
- [ ] Port Saved tab from `SavedWord` to `Annotation`, then migrate old rows and delete `SavedWord`

## Pivot Phase 2 — Sentence Learning View (PIVOT_PLAN §7)

- [x] `LearningAssetsProviding` protocol + on-device `FoundationModelsAssetsProvider` (D1/D2/D10; availability-gated, structured output via @Generable)
- [x] `SentenceLearnView` basic screen — original + play/slow, translation, Understand (generated breakdown/vocab/grammar with AI-generated badge + fallback view), one-tap save-as-annotation with optional intent chips, saved-items list
- [x] Reader drill-down (graduation-cap button + context menu on `SentenceCard` → Learn sheet)
- [x] `FlowLayout` extracted to `Shared/Components/` (rule of two); `SpeechPlayer.speakOnce` for word/chunk tap-to-hear
- [x] Editable Understand fields (D7): Edit sheet (chunks/vocab/grammar, row delete), Regenerate, Delete Breakdown; edits stamp `userEditedAt` → "AI-generated, edited by you" (required Schema V3 — DECISIONS #35)
- [x] Tap-a-word-in-original to hear it (tokens are tappable; layout fix for the squashed Slow button)
- [x] Fragment handling per UX_SPEC §8 — `FragmentDetector` pure service + 7 tests; fragments get no grammar point and whole-item save is phrase-type

## Design pass — "paper & ink" identity (DECISIONS #36)

- [x] `Shared/Styles/Theme.swift`: serif for source-language content, French ink-blue accent (app-wide tint), warm paper `learningCard`, shared `ChipButtonStyle` + `SectionHeaderLabel` + `Theme.karaoke`
- [x] Applied to the core loop: Reader sentence cards, Learn view, SaveWordSheet
- [ ] Adopt Theme tokens in Library / Saved / Review / Notes / Settings as each screen is next touched (don't hardcode system defaults in new work)

## Pivot Phase 3 — review modes (PIVOT_PLAN §7)

- [x] `SRSEngine.ReviewItem` includes `Annotation` items (due counting, sessions, grading, badge)
- [x] Card faces by item TYPE (D4/D11): word/grammar → meaning, sentence → listening (audio-first, text hidden until reveal, Play/Slow), phrase → cloze via `ClozeBuilder` (D5 deterministic blank, 5 tests; falls back to meaning when unblankable). Cloze never auto-speaks (audio contains the answer)
- [x] `VoiceRecorder` service (UI-free: playAndRecord category swap, last-take-only) + `ShadowingPracticeView` — ungraded, offered from the session summary for the session's full sentences; mic denial degrades to listen-and-repeat; NSMicrophoneUsageDescription added
- [ ] Legacy bookmarked sentences now get listening cards — confirm Ruby likes this (revert to meaning face is one line in `ReviewItem.face`)
- [ ] Phase 4 next: Notes tab annotation upgrade, after-session digest, confusion state (PIVOT_PLAN §7 Phase 4)

## Phase 1 — leftovers

- [ ] OCR spike on 5 real book-page fixtures (`Tools/OCRSpike`, `Fixtures/` is empty) — PROJECT_PLAN §6/§7 risk #1. *(Superseded by pivot task 0.2, which broadens it to scene text.)*

## Phase 2 — Persistence + Library

From [PHASE2_DESIGN.md](PHASE2_DESIGN.md) § Carry-forward:
- [ ] `ModelContainer` with `ReadAloudSchemaV1` + migration plan
- [ ] Models.swift amendments (`.externalStorage`, `ScanPage.lastOpenedAt`)
- [ ] AppRouter/RootView TabView shell; delete `ScanHomeView` + `[String]: Identifiable` hack
- [ ] LibraryView (book CRUD, cover, language lock) · BookDetailView (thumbnails, reorder, resume)
- [ ] ScanFlowView + PageIngestor (explicit save) · camera-permission-denied handling
- [ ] ReaderView persisted/ephemeral dual init · bookmark star persistence · SaveWordSheet
- [ ] Reader accessibility pass · ImageProcessor · `ReadAloudTests` target · due-item query helper
- [x] Append Phase 2 decisions to DECISIONS.md + matching PROJECT_PLAN §4.3/§6 edits *(done 2026-07-06 — entries 4–8)*

Capture-first + auto-detected source language + editable OCR (DECISIONS #21–#22), from [OCR_PIPELINE.md](OCR_PIPELINE.md) / [PHASE2_DESIGN.md](PHASE2_DESIGN.md) / [UX_SPEC.md](UX_SPEC.md) § Carry-forward:
- [ ] Rework `OCRService` to `recognizeText(in:languageHint:) async throws -> OCRResult` — `automaticallyDetectsLanguage = true` (hint-less) / `recognitionLanguages = [hint]` (hinted), `detectedLanguageCode` via `NLLanguageRecognizer.dominantLanguage` over assembled text (OCR_PIPELINE §1) — *acceptance: a hint-less French photo returns `detectedLanguageCode == "fr"`; too-short text yields `"und"`.*
- [ ] Wire the **capture-first** ScanFlow (drop scan-entry/`BookFormView` language pre-pick; `Book.languageCode` auto-set from OCRReview's confirmed language on the first page) per OCR_PIPELINE §1 flow strings — *acceptance: creating a book no longer asks for a language; the first page's confirmed source becomes `Book.languageCode`, editable later.*
- [ ] Build `Features/Scan/OCRReviewView` between OCR and persist (PHASE2 §5.1, UX_SPEC §2): editable `TextEditor` prefilled with `OCRResult.text`, source-language Picker prefilled from `detectedLanguageCode` (correctable), optional translate-to Picker (incl. None); **Use** splits the *edited* text under the confirmed language then persists, **Retake** returns to capture — *acceptance: editing text + correcting language before Use changes saved sentences and the book language; empty editor disables Use; nothing persists until Use.*
- [ ] `BookFormView`: no forced source-language pick on create (auto-set on first scan); source + translate-to editable in edit mode (PHASE2 §5.1) — *acceptance: a book created before any scan shows "Set on first scan"; editing language later does not re-OCR pages.*

From [UX_SPEC.md](UX_SPEC.md) § Carry-forward (Phase 2 items):
- [ ] TabView root + `AppRouter` (incl. `dueCount`/`recomputeDueCount`, DECISIONS #18) + versioned container (all four models registered)
- [ ] ScanFlowView built on `VNDocumentCameraViewController`; crop = the doc camera's corner-adjust review, no custom overlay (DECISIONS #14); imports skip crop (DECISIONS #15)
- [ ] Make `OCRService` cancellable (`request.cancel()` → `CancellationError`); single-page Cancel + batch confirm-dialog (DECISIONS #16)
- [ ] Reader tap/star/context-menu rules · scroll-suspension "Now playing" pill
- [ ] Camera priming + denied panel + first-scan tips ("Long-press to save words")
- [x] Cross-doc reconciliation of the precedence rulings (DECISIONS #2, #14–#20) *(done 2026-07-06)*

**Reuse / structure (applies to every Phase 2+ task — see CLAUDE.md "Reuse first"):**
- [ ] Stand up `Shared/Components`, `Shared/Styles` (ViewModifiers/ButtonStyles/design tokens), `Shared/Extensions` and route common UI through them — *acceptance: Library/Reader/Saved cards share one component + style, no duplicated font/color/padding literals across screens.*
- [ ] Keep `Services/` logic UI-free and injectable (no SwiftUI import, no `@AppStorage` inside) so `SRSState`, `SentenceSplitter`, OCR text-assembly, and WER scoring can be promoted to a local SPM package under `Packages/` later.

From [AUDIO_DESIGN.md](AUDIO_DESIGN.md) § Carry-forward (Phase 2 items):
- [ ] `PlaybackState` enum refactor · session activate/deactivate lifecycle
- [ ] Interruption observer · route-change observer

## Translation (iOS 18) — new subsystem

From [TRANSLATION_DESIGN.md](TRANSLATION_DESIGN.md) § Carry-forward (DECISIONS #23–#24; dependency order):
- [ ] Bump minimum target 17.4 → 18.0 in `project.yml` + `xcodegen generate` and sweep every "iOS 17.4+" mention (PROJECT_PLAN §5.1/§8, ARCHITECTURE §3) — *acceptance: builds against the 18.0 floor; no doc still asserts 17.4; PROJECT_PLAN §8 decision 4 reads "18.0 for the programmatic Translation API".*
- [ ] Add `Book.translationLanguage` + `Sentence.translatedText` to `ReadAloudSchemaV2` (joint with `SavedWord.sourceBookTitle`, one lightweight migration stage) — *acceptance: a V1 store opens under V2 with no data loss; both fields default nil.*
- [ ] `.translationTask` batch translate on `ReaderView` (§3): build `Configuration` from `book.languageCode`/`translationLanguage`, send pending sentences, write `translatedText`, `context.save()` — *acceptance: opening a page with a target fills every card within one batch and persists; reopening offline shows them with zero network; a partial page completes gaps on reopen.*
- [ ] Per-book target picker in Reader `[⋯]` + clear-on-change with a None option (§4) — *acceptance: changing the target wipes that book's `translatedText` and next open re-translates lazily; None hides + clears; other books untouched.*
- [ ] Inline translation UI + `文A` show/hide toggle as one `SentenceCard` (§5) — *acceptance: translation renders under the source in `.secondary` smaller type; toggle hides/shows without recompute, disabled when no target; active card speaks SOURCE only.*
- [ ] `LanguageAvailability` status handling + first-use download + error/offline/unsupported rows (§6, reuse AUDIO_DESIGN §8 amber row) — *acceptance: an uninstalled pair triggers the system download once then works offline; unsupported pair blocked in picker; a throw shows a retry row re-sending only pending sentences.*
- [ ] Guarantee TTS ignores `translatedText` (§5) — *acceptance: with translations visible, playback speaks only source; assert `SpeechPlayer.sentences == pageSentences.map(\.text)`.*
- [ ] Translation accessibility pass (§9) — *acceptance: VoiceOver reads the translation as its own "Translation: …" element, Dynamic Type scales it, the toggle is labeled, download/error rows are announced.*
- [ ] (Optional / Phase 4) Word-level translate chip (§8) reusing the book target — *acceptance: the word-chip sheet offers Translate and shows a gloss via one session request without persisting.*

## Phase 3 — Review + polish

> **✅ Phase 3 goals achieved (2026-07-08).** The review flashcard model is complete:
> recognition flashcards (foreign prompt → reveal meaning/translation + note + context),
> color-coded grading, practice-any-time, Saved Items with live-translated meanings, plus the
> quality pass (tests, audio robustness, per-language voices). Items still listed below are
> **optional polish** (dictionary, merge/split, full accessibility) — not blocking.

**Critical path shipped 2026-07-07 (commit f552672, on device):**
- [x] `SRSEngine` — due items (in-memory srs filter), overdue-first capped-20 shuffled sessions, SM-2 grading
- [x] `ReviewView` + `ReviewSessionView` (now a **recognition flashcard**: foreign prompt → reveal meaning/translation + note + context; color-coded grade choices) + Review-tab due-count badge
- [x] Review any time — "Practice all" regardless of due dates (not just when due)
- [x] `SavedItemsView` (Words | Sentences, replay, delete/remove) + `SavedItemDetailView` (note editing, SRS stats, live-translated **Meaning** section)
- [x] Single playback speed control on the Reader, 0.5×–2.0×; redundant Settings speed stepper removed (DECISIONS #28)
- [ ] Deferred (no-schema-change scope): `SavedWord.sourceBookTitle` — word source shows its language for now; needs the frozen-V1→V2 migration (DECISIONS #26) once done

**Quality & robustness shipped 2026-07-08 (on device):**
- [x] `ReadAloudTests` target — 14 tests (SM-2 scheduling, SentenceSplitter, WordTokenizer), all passing
- [x] Audio interruption + route-change handling in `SpeechPlayer` (call/Siri pauses & resumes; headphone unplug pauses)
- [x] Per-language voice selection: `VoiceStore` + Settings Voices picker (name + quality + preview); `SpeechPlayer` uses the resolved voice
- [ ] **OCR accuracy spike — needs 5 real book-page photos dropped into `Fixtures/`** (the plan's #1 risk, still unmeasured)

From [PHASE3_DESIGN.md](PHASE3_DESIGN.md) § Carry-forward:
- [ ] Settings **native language** `@AppStorage("nativeLanguage")` (full `LanguageCatalog`, defaults to device language) beside `speechRate`/`voiceID`; it is the translation destination and seeds `Book.translationLanguage` (PHASE3 §4, DECISIONS #24, #25) — *acceptance: the native-language picker persists; new Books translate into it (translate on/off via a None sentinel); existing Books unaffected.*
- [ ] Read-only translation in Saved sentence detail — surface non-nil `Sentence.translatedText` in `.secondary` style (PHASE3 §3) — *acceptance: a translated bookmarked sentence shows its stored translation read-only; the detail view never kicks off a translation.*
- [ ] Relax PHASE3 §6 "no free-text editing in v1" note — full-text edit happens at scan time in `OCRReviewView`; after save, structure is fixed via merge/split, re-splitting a saved page is out of scope for v1 (DECISIONS #22) — *acceptance: PHASE3 §6 note reads as relaxed; no doc claims sentence text is uneditable everywhere.*
- [ ] Amend AUDIO_DESIGN §6/§8 to the VoiceStore contract (DECISIONS #10)
- [ ] Enhanced-voice guidance card · DictionaryService/View · sentence merge & split
- [ ] Reader "Add Note…" · accessibility pass · polish pass (haptics, empty/error states)

From [UX_SPEC.md](UX_SPEC.md) § Carry-forward (Phase 3 items):
- [ ] `Shared/Haptics.swift` wired to the §5 map · Reader/Review VoiceOver pass
- [ ] Dynamic Type + Reduce Motion audit · Review badge in-memory filter · missing-voice banner

From [AUDIO_DESIGN.md](AUDIO_DESIGN.md) § Carry-forward (Phase 3 items):
- [ ] Mid-utterance speed change · voice picker UI · Reader audio empty/error rows · repeat-mode delay

## Phase 4 / tech debt

- [ ] Background audio + Now Playing + remote commands (AUDIO_DESIGN §7)
- [ ] Continuous page playback decision (UX_SPEC open question 1)
- [ ] `PlaybackState` transition unit tests behind a synthesizer protocol (AUDIO_DESIGN)
- [ ] OCR column clustering / hyphenated line-break repair (ARCHITECTURE §4 gaps 5)
