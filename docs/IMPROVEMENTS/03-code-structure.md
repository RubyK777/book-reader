# Code Structure & Architecture

This dimension covers how ReadAloud's code is organized: where duplicated logic should be collapsed to one source of truth, which seams unlock unit testing, what to carve into a local SPM package, and how to split the oversized view files — all inside Ruby's reuse-first, offline, Apple-only, anti-gamified constraints. Every item below is grounded in real files and frames partial-overlaps as extensions of what already exists.

**How to read this** — Groups run from cheap-and-safe to expensive-and-schema-touching; within each group, quick wins come first. Skim the triage table at the bottom to pick, then jump to the section for detail.

---

## A. Shared UI extractions (rule-of-two/three, already exceeded)

These are pure lift-and-share moves: a control or modifier already exists (or is copied 3×) and just needs one canonical home under `Shared/`. No behavior change, no schema touch.

### Promote `ReplayButton` to `Shared/Components/`
**What & why** — A finished replay control (load → play → `Haptics.select()`, `.bounce` symbol effect, 44pt frame, accent tint) already exists but is `private` inside `Features/Saved/SavedItemsView.swift:156-178`; the same load+play gesture is hand-inlined at `SavedItemDetailView.swift:49-55`, `Notes/AnnotationDetailView.swift:57-64`, and three times in `ReviewSessionView.swift:166/190/217`. One shared control makes every "play this" tap feel identical and alive.
**Reuse** — Move the existing struct verbatim; swap the five inline buttons for it. Reuses `Haptics` + `Theme.accent` already in play.
**Effort** — S; none.
**Notes** — Reuse-first: it's one `private` keyword away from shareable. Offline.

### `.dictionaryLookup(term:)` view modifier
**What & why** — The `@State lookupTerm: DictionaryTerm?` + `.sheet(item:) { DictionaryView(term:).ignoresSafeArea() }` triad is copied at `SaveWordSheet.swift:16/83`, `SentenceLearnView.swift:22/69`, and `SavedItemDetailView.swift:29/106`. A single modifier collapses lookup to one call site with a consistent affordance.
**Reuse** — Wraps the existing `Shared/DictionaryView.swift` (`DictionaryView` + `DictionaryTerm(id:)`); lives beside it in `Shared/`. Genuinely just plumbing around existing types.
**Effort** — S; none.
**Notes** — Apple `UIReferenceLibraryViewController`, offline.

### `AIActionButton` for Foundation-Models actions
**What & why** — The "sparkles Label / ProgressView+Text while running / disabled" button is duplicated for draft/explain at `AnnotationDetailView.swift:95-108` & `:134-145` and generate/regenerate at `SentenceLearnView.swift:213-218/313`. Both also repeat the same `provider?.isAvailable == true` gate. One control makes AI affordances behave uniformly and enforces the availability gate in a single place.
**Reuse** — `AIActionButton(title:isRunning:action:)` in `Shared/Components/`, driven by the existing `LearningAssetsProviding.isAvailable` (from `LearningAssetsProviderFactory.makeDefault()`).
**Effort** — S; none.
**Notes** — Apple-only, availability-gated (iOS 26). Anti-gamification fine — a utility control, no scoring.

### `SRSStatsSection(srs:)` shared view (also fixes a divergence bug)
**What & why** — `SavedItemDetailView.swift:79-84` and `AnnotationDetailView.swift:152-159` both render the SRS summary as `LabeledContent` rows (repetitions/interval/due) — but they've already drifted: one labels "Ease"+"Repetitions", the other "Reviews", and interval pluralization differs ("1 day" vs raw "days"). One shared section makes the review schedule read the same everywhere and pluralize correctly.
**Reuse** — Fed by the existing `SRSState`; lives in `Shared/Components/`. These two screens are slated to converge in the SavedWord→Annotation port (Group G) — extracting now de-risks that merge.
**Effort** — S; none.
**Notes** — Reuse-first; fixes a live label/pluralization inconsistency.

### Move `CoverThumbnail` to `Shared/Components/` + unify the two thumbnail decoders
**What & why** — `CoverThumbnail` (`LibraryView.swift:260`) is documented "Shared by Book detail and Book form rows" yet lives in a feature file. It and shelf `BookCover.load()` (`LibraryView.swift:249-254`) run identical `UIImage(data:)?.preparingThumbnail(of:)` on a detached task, differing only by target size (156×204 vs 400×600); `ScanFlowView.swift:144` decodes raw again. Covers should decode off-main through one downscale path.
**Reuse** — Relocate `CoverThumbnail` to `Shared/`; factor the detached-decode into a tiny `Data.thumbnail(of:)` helper both call, pairing with existing `Services/ImageProcessor.swift`.
**Effort** — M; pairs with the Group C `Data.thumbnail` helper.
**Notes** — Offline; keeps the reuse-first folder contract.

---

## B. Design tokens & folder housekeeping

Cheap cleanups that honor DESIGN_GUIDELINES.md and Ruby's canonical layout.

### Add hero-symbol size tokens to `DesignSystem`
**What & why** — Big-glyph/empty-state sizes are raw literals: `.font(.system(size: 52))` at `ReaderView.swift:373` & `ReviewView.swift:57`; `56` at `ScanFlowView.swift:54` & `ReviewSessionView.swift:343`; `48` at `ShadowingPracticeView.swift:128`; `44` at `ReviewSessionView.swift:181`. `IconSize` stops at `hero48`. Tokens honor the "EVEN font sizes / unified icon sizes" rule.
**Reuse** — Extend the existing `IconSize` enum (`Shared/DesignSystem.swift`) with a canonical hero (e.g. `hero52/hero56`) and swap the literals.
**Effort** — S; none.
**Notes** — Pure token cleanup, no behavior change.

### Create `Shared/Extensions/` and land `trimmedToNil`
**What & why** — Ruby's canonical layout is `Shared/{Components,Styles,Extensions}` but `Extensions/` doesn't exist yet. The "trim whitespace; empty ⇒ nil else keep" idiom recurs at `SavedItemDetailView.swift:219`, `NotesView.swift:296`, `ReaderView.swift:590`, plus bare `.trimmingCharacters` guards in `OCRReviewView.swift`, `BookFormView.swift:111`, `ScanFlowView.swift:159`. A `String.trimmedToNil` extension shrinks surface and prevents "saved an empty note" edge cases — and is the folder's first honest tenant.
**Reuse** — App-agnostic pure logic; headed toward the `Packages/` promotion.
**Effort** — S; none.
**Notes** — Reuse-first folder contract; package-bound pure logic.

### Tidy loose `Shared/` root files into their subfolders
**What & why** — Four files sit loose at `Shared/` root: `DesignSystem.swift`, `Languages.swift`, `DictionaryView.swift`, `ShareSheet.swift`. Grouping them matches the documented layout and gives the `.dictionaryLookup()` modifier (Group A) a home.
**Reuse** — Pure file moves, no code change: `DictionaryView.swift` + `ShareSheet.swift` (UIKit-wrapper views) → `Shared/Components/`; `DesignSystem.swift` (tokens) → `Shared/Styles/`; `Languages.swift` (`LanguageCatalog`, app-agnostic reference data) → candidate for LearningKit (Group E) or a `Shared/` sub-group.
**Effort** — S; none.
**Notes** — Low-risk housekeeping.

> **Not worth extracting yet:** the book-cover shadow/opacity stack in `LibraryView.swift:180-236` (`.black.opacity(0.12/0.30/0.45)`, spine `.frame(width: 12)`, badge `.font(.system(size: 12))`) is all raw literals but localized to the one paper-book cover component — tokenize only if a second cover style appears.

---

## C. Single-source logic consolidation (Services)

Collapse duplicated decision logic so displayed facts can't disagree.

### Move `nextDueDate()` / deck-wide due scan into `SRSEngine`
**What & why** — `ReviewSessionView.swift:522-537` hand-fetches `Sentence`+`SavedWord`+`Annotation` and maps `srs?.dueDate` — the same three-model gather that `SRSEngine.dueItems`/`dueCount` already does — just to find the soonest due date for the summary line. The view drops ~16 lines and the "next review" date can never disagree with the due badge.
**Reuse** — Add `static func nextDueDate(in:) -> Date?` beside the existing `dueItems`/`dueCount` in `Services/SRSEngine.swift`. Also one fewer site to touch during the SavedWord port.
**Effort** — S; none (do before Group G to shrink that port).
**Notes** — Keeps due-logic single-source; testable via in-memory container.

### Extract the translate-on-reveal `Meaning` state machine to a shared `TranslationResolver`
**What & why** — The identical `enum Meaning { none, translating, ready, unavailable }` + `TranslationSession.Configuration` build + `session.translations(from:)` + "skip if source == native base" guard lives at THREE sites: `ReviewSessionView.swift:20` & `:435-468`, `SavedItemDetailView.swift:17` & `:132-167`, and the batch variant in `ReaderView.swift:187-233`. Welded into views, none is testable, and the source-base-skip / persistence rules can drift. One resolver means "show the meaning" is correct in exactly one place.
**Reuse** — Fold the two single-item copies into a small `@Observable TranslationResolver` (holds `Meaning`, decides skip-when-same-language via `LanguageCatalog` primary-subtag compare, drives a `TranslationSession.Configuration`) in `Shared/` or `Services/`. Reader keeps its batch/`clientIdentifier` correlation but shares the enum + config builder.
**Effort** — M; pairs with the ReaderView split (Group F) which folds in the batch trio.
**Notes** — Offline (iOS 18 Translation), Apple-only; translation-as-visual-aid rule preserved (never spoken). Makes skip/ready/unavailable unit-testable.

### Inject `UserDefaults` into `VoiceStore`
**What & why** — `Services/VoiceStore.swift:13-19` reads `UserDefaults.standard` directly — CLAUDE.md flags this as the one thing blocking Services from moving to `Packages/`, and it makes the primary-subtag `voices(for:)` sort (`:25-36`) and `resolvedVoice` fallback (`:40-46`) untestable in isolation.
**Reuse** — Make it a small struct holding an injected `UserDefaults` (default `.standard`); voice-listing/sort stays pure over `AVSpeechSynthesisVoice.speechVoices()`. `SettingsView`'s `VoicePickerRow` just passes the default — no behavior change.
**Effort** — S; none.
**Notes** — Apple-only; concrete step toward a `Packages/` audio lib.

---

## D. Testability seams (extract pure decisions, then cover them)

The 30-test suite covers ClozeBuilder/Fragment/SRSState/TextProcessing/Migration only. These pull the highest-risk untested logic into a testable shape, reusing the in-memory-`ModelContainer` pattern already in `MigrationTests.swift`.

### Extract `ReviewItem.face` routing to a pure `CardFace.for(...)`
**What & why** — Card-face routing (word/grammar→meaning, sentence→listening, phrase→cloze-or-fallback) at `Services/SRSEngine.swift:108-121` is the single most learner-critical decision in Review — wrong face = untrainable card — yet has ZERO tests because it needs a SwiftData-backed `ReviewItem` to exercise. Pull the switch into `static func CardFace.for(type:text:context:) -> CardFace`; `ReviewItem.face` becomes a one-line call; then unit-test all four types + the phrase cloze-fallback branch.
**Reuse** — `SRSEngine.swift:6-14` (`CardFace`), `ClozeBuilder.blank` already pure & tested; mirror `ClozeBuilderTests.swift`.
**Effort** — S; none.
**Notes** — Pure logic, Apple-only; directly reusable in the future SRS package (Group E).

### `ExportService` round-trip test
**What & why** — `ExportService.makeJSON` (`ExportService.swift:42-75`) is deterministic (sorted keys, iso8601) and is the user's ONLY backup, yet untested. Seed an in-memory container (book+page+sentences+savedWord+SRS), encode, assert the DTO shape — catches silent data-loss regressions, especially during the SavedWord port when `savedWords`/`WordDTO` must migrate.
**Reuse** — In-memory container pattern from `MigrationTests.swift`; DTOs already `Codable`.
**Effort** — S; none.
**Notes** — Apple-only; protects offline export/backup.

### Promote `SRSEngine.dueItems`/`buildSession`/`grade` under test
**What & why** — Session assembly (overdue-first sort, cap 20, shuffle) and grading write-back at `SRSEngine.swift:177-222` are the scheduling backbone and completely untested. `buildSession(from:)` is already pure `[ReviewItem]→[ReviewItem]` — testable today for the sort+cap invariant; `dueItems`/`grade` need an in-memory container.
**Reuse** — Tests the orchestration layer above the already-covered SM-2 math (`SRSStateTests.swift`); setup from `MigrationTests.swift`.
**Effort** — M; none.
**Notes** — Apple-only; guards the pivot's core loop.

### Put a synth protocol under `SpeechPlayer`
**What & why** — `SpeechPlayer.swift:14` hard-owns a concrete `AVSpeechSynthesizer`, so the queue/auto-advance/`isJumping`-suppression/interruption-resume state machine (the app's trickiest logic, must-preserve per CLAUDE.md) can't be unit-tested at all. Introduce a `Speaking` protocol (speak/stop/pause + didFinish/didCancel callbacks) with the AVFoundation impl injected in `init`; a fake driver then asserts index advances and that `isJumping` swallows the programmatic-jump `didCancel`. This is the TASKS "PlaybackState enum + tests behind a synth protocol" item.
**Reuse** — Keeps `@Observable`, `managesNowPlaying`, and all public API; only the synthesizer field is swapped for the protocol.
**Effort** — L; none, but unblocks the deferred `PlaybackState` refactor.
**Notes** — Apple-only. Do NOT collapse the per-view `SpeechPlayer()` instances into a singleton — that fights the "no singletons, deps passed in" rule; per-view is correct (only Reader sets `managesNowPlaying`).

---

## E. Local SPM package — `Packages/LearningKit`

Ruby's rule 2 wants app-agnostic pure logic heading to a local SPM package; none exists yet. Carve the genuinely dependency-free engines into ONE package (not one-per-file — over-engineering for ~4 tiny types), unblocking unit tests without the app target.

### Carve the pure engines into `Packages/LearningKit`
**What & why** — Ships the reusable core and lets the pure logic be tested without booting the app.
**Reuse** — Move verbatim (all Foundation / NaturalLanguage only, zero SwiftData/SwiftUI, compile unchanged): `Services/ClozeBuilder.swift`, `Services/FragmentDetector.swift`, `Services/SentenceSplitter.swift`, `Services/WordTokenizer.swift`. Their existing tests (FragmentDetector 7, ClozeBuilder 5) move with them. `Languages.swift` (`LanguageCatalog`) is a candidate co-tenant.
**Effort** — M; a lift-and-shift plus a `Package.swift`.
**Notes** — Offline/Apple-only clean.

### Extract SM-2 math into the package; leave `SRSState` in the schema
**What & why** — The safe carve. Do NOT move `SRSEngine.swift` wholesale — it `import SwiftData` and `ReviewItem` wraps `Sentence`/`SavedWord`/`Annotation` (`SRSEngine.swift:20-24`), so it's not pure. Only the SM-2 arithmetic in `SRSState.review(quality:)` (`Models/Models.swift:247-263`) is pure.
**Reuse** — Extract as a free function `SM2.next(repetitions:ease:interval:quality:) -> (…)` in LearningKit; have `SRSState.review` call it. Leaves the `SRSState` struct in `Models.swift` untouched, so the schema fingerprint (DECISIONS #35) does NOT change. `dueItems`/`buildSession`/`grade` stay in `Services/SRSEngine.swift` (they need SwiftData).
**Effort** — S; depends on the package existing (do with the carve above).
**Notes** — Package gets pure testable math without a migration.

### Reserve a `WERScorer` slot — spec only, don't scaffold
**What & why** — Grep confirms no `wer`/`editDistance`/`levenshtein` anywhere — it genuinely doesn't exist. It's a Phase 5 pronunciation-compare need. Reserve the slot in LearningKit but build it only when the shadowing-compare feature lands.
**Reuse** — Genuinely new; will consume `WordTokenizer` (now co-located in the package) to tokenize reference vs. hypothesis.
**Effort** — S (when built); do not build ahead of the feature.
**Notes** — Pure Foundation, offline; anti-bloat — build with the feature, not before.

---

## F. Split the oversized view files

Three views mix several sub-views and an engine inline. Splitting into the feature folder is pure movement of already-`private` structs plus folding shared logic into Group C/E extractions.

### Split `ReaderView` (613, largest file)
**What & why** — A God view: sentence cards + playback bar + after-session digest + edit sheet + a full batch-translation engine (`refreshTranslationConfig`/`translateMissing`/`setTranslationLanguage`, `:194-245`) all inline. Move the already-`private` `SentenceCard` and `EditSentenceSheet` (`:423-599`) to their own files under `Features/Reader/`, and fold the batch-translate trio into the shared `TranslationResolver` (Group C). Nets a readable core and the only path to testing the subtle correlate-by-`clientIdentifier` persistence (`:215-227`).
**Reuse** — `SentenceCard`/`EditSentenceSheet` extract as-is; `DesignSystem`/`Theme`/`learningCard` already style them; batch translate rejoins the shared resolver.
**Effort** — M; pairs with Group C `TranslationResolver`.
**Notes** — Keep `SpeechPlayer.isJumping` + `managesNowPlaying:true` semantics intact.

### Split `SentenceLearnView` (610, second largest)
**What & why** — Bundles original/karaoke tokens, translation, the whole Understand generate/fallback/provenance block (`:191-354`), save-as-annotation, and an inline 60-line `EditAssetsSheet` (`:542-603`). Move `EditAssetsSheet` and the `understandContent`/`fallbackContent` cluster into `Features/Learn/` files. Frees the save-inference logic (`saveSelection`/`saveWholeSentence`/`hasAnnotation`, `:491-525`) — pure given a sentence — to be readable and unit-covered (word vs. phrase vs. fragment→phrase inference is a real correctness surface).
**Reuse** — `provider` seam (`LearningAssetsProviding`) already injectable; `FragmentDetector` already tested — the save inference just composes them.
**Effort** — M; none.
**Notes** — Apple-only; anti-gamification (no scoring, just save).

---

## G. Schema / model debt (expensive — batch with audio-model work)

SwiftData frozen-schema rules make every model change a new frozen version + migration stage (DECISIONS #35). These are the high-value but costly moves; pay the migration tax once by batching them with the in-flight audio-model work (`docs/AUDIO_LEARNING_DESIGN.md`), not as isolated refactors.

### Finish `SavedWord` → `Annotation` port, then delete the legacy model
**What & why** — `SavedWord` (`Models/Models.swift:222-237`) is dual-model debt: it forces a third `.word` branch through `ReviewItem` id/promptText/revealText/note/languageCode/srs/face (`SRSEngine.swift:24-140`), `dueItems` (`:186-189`), `ReviewSessionView.nextDueDate()` (`:528-531`), and `ExportService.WordDTO` (`:32-39,66-69`), plus a whole `Features/Saved/` pair. Porting to `Annotation(type: .word)` deletes an enum case across ~8 sites and collapses `SavedItemDetailView` (272) and `AnnotationDetailView` (260) toward one screen. This is the biggest single coherence + net-size win — directly serves "keep the app concise." (TASKS Phase 1.)
**Reuse** — `Annotation` already subsumes everything `SavedWord` holds (text/contextSentence/languageCode/userNote/srs) plus tags/intent; migration follows the frozen-schema V4→V5 recipe in `Schema.swift` + `MigrationTests.swift`.
**Effort** — L; data migration of existing rows. Do the Group A `SRSStatsSection` + `ReplayButton` and Group C `nextDueDate` first to shrink the merge.
**Notes** — Net code reduction; the SavedWord-related seams above (`nextDueDate`, `ExportService` test) exist partly to de-risk this.

### Rename `ScanPage` → `SourcePage`
**What & why** — `ScanPage` (`Models/Models.swift`) will soon also hold AUDIO takes (per `AUDIO_LEARNING_DESIGN.md`); "Scan" bakes in image-only provenance and becomes a lie the moment a `.conversation` source lands. Rename to `SourcePage` (neutral, matches the existing `SourceKind`). The folder `Features/Scan/` can keep its name (it genuinely is the image-capture flow); audio capture gets its own `Features/Record/` sibling.
**Reuse** — Pure rename + a migration stage in `Schema.swift`.
**Effort** — L; SwiftData rename = new frozen schema version + migration, same cost class as V3→V4.
**Notes** — Do it together with the audio-model work so the migration tax is paid once.

### Add a `SentencePlayer` playback protocol (the one seam worth adding proactively)
**What & why** — The upcoming `RecordingPlayer` (real recorded audio + word timestamps, per `AUDIO_LEARNING_DESIGN.md`) should drop into Reader/Review/Shadowing without touching call sites. A small protocol captures what every playback view observes so both engines are interchangeable. Worth adding ahead of the feature because RecordingPlayer is already in-flight.
**Reuse** — Extract the seam directly from `SpeechPlayer`'s existing surface — `currentSentenceIndex`, `highlightRange`, `isSpeaking`, `speedMultiplier`, `repeatMode`, `speakOnce`, jump/pause (`Services/SpeechPlayer.swift`). `SpeechPlayer` conforms as-is; `RecordingPlayer` provides the same members backed by `AVAudioPlayer` + timestamp ranges. Keep it a plain protocol (`@Observable` conformers), NOT a package — it references app types, nothing app-agnostic.
**Effort** — M; abstracts playback only. Recording stays separate — `managesNowPlaying` and the `.playback`/`.playAndRecord` swap already coexist cleanly with `VoiceRecorder.swift`.
**Notes** — Apple-only; complements (does not overlap) the Group D synth protocol, which is about testing `SpeechPlayer` internals.

---

## Triage table

| Suggestion | Impact | Effort | Reuses |
|---|---|---|---|
| Promote `ReplayButton` to Shared | Med | S | Existing `private ReplayButton`, `Haptics`, `Theme` |
| `.dictionaryLookup(term:)` modifier | Med | S | `DictionaryView` + `DictionaryTerm` |
| `AIActionButton` shared control | Med | S | `LearningAssetsProviding.isAvailable` |
| `SRSStatsSection` (+fixes label bug) | Med | S | `SRSState` |
| Hero-symbol size tokens | Low | S | `IconSize` enum |
| `Shared/Extensions/` + `trimmedToNil` | Low | S | New folder (canonical layout) |
| Tidy loose `Shared/` root files | Low | S | Pure moves |
| `nextDueDate()` into `SRSEngine` | Med | S | `SRSEngine.dueItems`/`dueCount` |
| Inject `UserDefaults` into `VoiceStore` | Med | S | `VoiceStore` (unblocks Packages) |
| `CardFace.for(...)` pure + tests | High | S | `CardFace`, `ClozeBuilder`, mirror `ClozeBuilderTests` |
| `ExportService` round-trip test | High | S | `MigrationTests` container, Codable DTOs |
| `CoverThumbnail` → Shared + one decoder | Med | M | `CoverThumbnail`, `ImageProcessor` |
| `TranslationResolver` (Meaning ×3) | High | M | 3 copies, `LanguageCatalog` |
| `SRSEngine` session/grade tests | High | M | `SRSStateTests`, `MigrationTests` |
| `LearningKit` package (4 pure engines) | High | M | ClozeBuilder/Fragment/SentenceSplitter/WordTokenizer (+tests) |
| `SM2.next(...)` into package | Med | S | `SRSState.review` body (no migration) |
| `WERScorer` slot (spec only) | Low | S | Genuinely new; will use `WordTokenizer` |
| Split `ReaderView` | Med | M | `SentenceCard`/`EditSentenceSheet`, `TranslationResolver` |
| Split `SentenceLearnView` | Med | M | `LearningAssetsProviding`, `FragmentDetector` |
| `SpeechPlayer` synth protocol | High | L | `SpeechPlayer` public API unchanged |
| `SentencePlayer` playback protocol | High | M | `SpeechPlayer` surface; enables `RecordingPlayer` |
| `SavedWord` → `Annotation` port + delete | High | L | `Annotation`, V4→V5 migration recipe |
| Rename `ScanPage` → `SourcePage` | Med | L | Rename + migration; batch w/ audio work |
