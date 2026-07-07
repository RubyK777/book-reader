# ReadAloud — Decision Log

*Append-only. One entry per nontrivial decision: what was decided, why, what was rejected.
Referenced from CLAUDE.md, ARCHITECTURE.md, and the phase/spec docs — when a doc says
"logged in DECISIONS.md", the entry lives here.*

## 2026-07-06 — Foundation

1. **SRS due-date filtering is in-memory.** `SRSState` is a Codable struct embedded in
   `Sentence`/`SavedWord`, so `#Predicate` cannot reach `srs.dueDate`. Due queries fetch candidates
   (bookmarked sentences / all saved words) and filter in memory. Fine at personal-library scale;
   promote `dueDate` to a stored property if that ever changes. (ARCHITECTURE §2)
2. **Documentation precedence.** UX_SPEC wins on navigation, screen states, interaction, and haptics;
   the phase design docs win on service and data contracts; PROJECT_PLAN stays the high-level spec and
   is amended whenever a design doc supersedes one of its items — no silent contradictions between
   sources of truth. (UX_SPEC header)
3. **TabView root** — Library / Saved / Review / Settings; Scan is a sheet-launched flow from Library,
   Reader is pushed. Rejected: NavigationStack hub (buries Review, killing the SRS habit loop) and a
   Scan tab (scanning is a verb that ends inside a Book). (UX_SPEC §1)

## 2026-07-06 — Phase 2 design

4. **Ephemeral quick-scan retired** — every scan persists into a Book; assign runs *before* processing
   so the language is known before OCR. (PHASE2 §5)
5. **Word saving = card long-press → chip sheet**, superseding plan §4.3's per-word long-press
   (no word-level tap targets; chips are fat-finger-friendly and reuse the tokenizer). (PHASE2 §7)
6. **Saved Items re-scoped Phase 2 → Phase 3** — rows need SRS stats and the `sourceBookTitle`
   addition; PROJECT_PLAN §6 amended to match. (PHASE2 §3, PHASE3 §3)
7. **Explicit `context.save()` at the scan boundary**; autosave everywhere else — a lost scan is
   unforgivable, a lost Bool toggle is recoverable. (PHASE2 §5)
8. **Crop/rotate belongs to Phase 2's ScanFlowView confirm step** per UX_SPEC §1, superseding
   PHASE2 §5's earlier deferral to the Phase 3 polish pass. (UX_SPEC §1, PHASE2 §5, PHASE3 §7)

## 2026-07-06 — Phase 3 design

9. **No Settings deep link for enhanced voices** — `App-Prefs:`/`prefs:` schemes are private API and
   App Store-rejectable; in-app instruction card instead. PROJECT_PLAN §4.6 amended. (PHASE3 §4)
10. **One voice-selection contract: `VoiceStore`** (keys `voiceID.<languageCode>`, `speechRate`),
    superseding AUDIO_DESIGN §6's `VoiceCatalog` sketch. Playback resolution ends in the same
    primary-subtag matching as missing-voice detection, so the two can never disagree (a `"zh-Hans"`
    book resolves to a zh-* voice, never the system default). Missing voice = **disable play + banner**
    (UX_SPEC §2), not AUDIO_DESIGN §8's speak-the-default row; AUDIO_DESIGN §6/§8 to be amended
    (PHASE3 carry-forward task). (PHASE3 §4)
11. **Review badge recomputes** on scene-activate / tab appear / session end / bookmark toggle /
    word save, via a shared `@Observable` due-count holder in the environment — never `@Query`
    (the due filter is in-memory) and never polling timers. (UX_SPEC §1, PHASE3 §2.1)
12. **"N reviewed" counts grades given**, not unique cards — an Again re-enqueue contributes both
    passes to the count and tally. (PHASE3 §2.2)
13. **Merge is lossy and guarded, not undoable** — the absorbed sentence's `srs` history and
    `userNote` are discarded, so merge confirms when either exists; no undo stack (rare action, low
    stakes). Split uses per-occurrence positional tokens (`NLTokenizer(.word)` ranges), not
    `WordTokenizer`'s deduped list. (PHASE3 §6)

## 2026-07-06 — Cross-document reconciliation

*A consistency sweep across all eight design docs found twelve places where two docs specified the
same thing differently. These entries record the winning ruling for each; the losing docs are
amended to match. Where a ruling revises an earlier decision, it references it (append-only — earlier
entries stand as history).*

14. **Document camera wins the capture path — supersedes #8's custom crop mechanism.**
    Capture uses VisionKit `VNDocumentCameraViewController` (OCR_PIPELINE §1), not `CameraPicker` +
    a hand-built draggable crop/rotate overlay (UX_SPEC §1 / PHASE2 §5). The system doc camera's
    corner-adjust review **is** the crop step, it deskews/flattens the page (directly attacking
    PROJECT_PLAN §7 risk #1), closes ARCHITECTURE gap #6 with zero custom UI, and its multi-page
    batch matches how books are actually scanned. The *substance* of #8 survives — crop lands in
    Phase 2 — but via the doc camera, not a custom overlay. Amend UX_SPEC §1/§2 + ScanFlowView
    task and PHASE2 §5/§9 (gate-before-ingest, batch save) to the doc-camera flow. (OCR_PIPELINE §1)
15. **Photo-library import gets no crop in Phase 2.** Downstream of #14: with no custom crop overlay
    to reuse, imported images go straight to the quality gate (which catches bad imports); an
    optional import-crop UI is a Phase 3 carry-forward. Amend UX_SPEC §1's "identical pipeline"
    rule. Import remains the required camera-denied / simulator fallback. (OCR_PIPELINE §1)
16. **OCR is cancellable; batch semantics preserved.** `OCRService` is made cancellable
    (`request.cancel()` → `CancellationError`) so single-page scans show a responsive Cancel
    (UX_SPEC §2 wins on interaction) and multi-page batches keep OCR_PIPELINE's confirm-dialog
    semantics (already-finished pages survive). Fix OCR_PIPELINE §1's stale quote of a PHASE2 rule
    that no longer exists. (UX_SPEC §2, OCR_PIPELINE §1)
17. **"Scan → listenable ≤ 10 s" is per page**, the only interpretation that survives multi-page
    capture. Actually apply the edit to PROJECT_PLAN §9 (stop asserting it happened), and make
    TESTING_QUALITY §5's signpost interval + p95 pass condition per page. (OCR_PIPELINE §1)
18. **`AppRouter` is the due-count holder.** One environment object both tabs and the Reader already
    reach — no second injected singleton. Amend PHASE3 §2.1 + entry #11's "holder" to name
    `AppRouter`; add `dueCount`/`recomputeDueCount(in:)` to PHASE2 §2's router sketch. Also: no
    spinner on the Review due filter (it resolves synchronously in memory — UX_SPEC §2 wins; fix
    PHASE3 §7's circular citation). (UX_SPEC §1)
19. **SpeechPlayer test suite follows `PlaybackState`, not the `isJumping` bool.** AUDIO_DESIGN owns
    the player contract (per #2); its Phase-2 `PlaybackState` refactor would invalidate tests written
    to pin `isJumping`. Keep TESTING §2.3's `SpeechSynthesizing` seam + `FakeSynthesizer`, but state
    the cases against `PlaybackState` transitions — one suite, described the same way in both docs.
    Likewise anchor TESTING's `-uiTestFixture` hook and OSSignposter intervals to `ScanFlowView` /
    `PageIngestor`, not the deleted `ScanHomeView`. (AUDIO_DESIGN §1, PHASE2 §5)
20. **Master-spec staleness swept.** PROJECT_PLAN §5.4's SpeechPlayer sketch
    (`play(sentences:startingAt:)`, `rate`) is replaced by the real surface (`load`, `play(at:)`,
    `togglePlayPause`, `speedMultiplier`) or a pointer to ARCHITECTURE §2; §4.1 is reworded from the
    rejected "link to Saved/Review" hub to the TabView shape (#3); Library's `+` is new-book, a
    separate Scan button launches capture (PHASE2 §3 wins); first-scan tip copy standardizes on
    "Long-press to save words" (UX_SPEC §7). (ARCHITECTURE §2, PHASE2 §3, UX_SPEC §1/§7)

## 2026-07-06 — Any-language, OCR editing & translation

21. **Auto-detected source language; the scan flow becomes capture-first.** OCR no longer needs a
    pre-picked language: `recognizeText(in:languageHint:)` runs Vision with
    `automaticallyDetectsLanguage = true` (or `recognitionLanguages = [hint]` when a Book's language is
    known), and `OCRResult.detectedLanguageCode` is computed via `NLLanguageRecognizer` over the
    assembled text. `Book.languageCode` is auto-set from the language confirmed on the first page
    (editable later), so `BookFormView` no longer forces a create-time pick. *Why:* the user shouldn't
    have to name a language before scanning it; detection then confirm is fewer taps and fixes wrong
    guesses. *Honest limit:* "any language" = any in `VNRecognizeTextRequest.supportedRecognitionLanguages`
    for the `.accurate` revision (Latin scripts + zh/ja/ko/…), not literally every language.
    **Supersedes the ordering clause of #4** (assign-before-capture "so the language is known before
    OCR") — capture and OCR now run first, assign after; #4's "every scan persists into a Book" clause
    still stands. (OCR_PIPELINE §1/§4.5, PHASE2 §5, UX_SPEC §2)
22. **Editable OCR result — `OCRReviewView` between OCR and persistence.** A new post-OCR/pre-persist
    screen (`Features/Scan/OCRReviewView.swift`) shows a full-height editable `TextEditor` prefilled with
    `OCRResult.text`, a source-language Picker prefilled with `detectedLanguageCode` (correctable — this
    is how a wrong detection is fixed), and the translate-to Picker; **Use** splits the *edited* text via
    `SentenceSplitter` under the confirmed language then persists, **Retake** returns to capture. *Why:*
    nothing is saved yet, so full-text editing here is free and risks no sentence-level srs/bookmark.
    Relaxes PHASE3 §6's "no free-text editing in v1" to: full-text edit only at scan time; after save,
    structure is fixed via merge/split, and re-splitting a saved page from edited full text is out of
    scope for v1 (it would destroy sentence-level srs/bookmarks). (OCR_PIPELINE §4.5, PHASE2 §5.1,
    UX_SPEC §2, PHASE3 §6)
23. **Inline, persisted translation via the Translation framework; minimum target 17.4 → 18.0.** The
    Reader attaches SwiftUI's `.translationTask(_:action:)` (iOS 18), which provides a
    `TranslationSession`; a batch `session.translations(from:)` writes each `response.targetText` back to
    `Sentence.translatedText` (persisted → offline thereafter). `LanguageAvailability().status(from:to:)`
    gates the pair; first use of a new pair triggers the system language-download consent — network once,
    then fully offline (honestly denting "works on a plane" for that first pair only). *Why:* the
    programmatic/inline Translation API is iOS 18, so the target rises from 17.4 (PROJECT_PLAN §8
    decision 4's rationale is rewritten accordingly). *Rejected:* `.translationPresentation(isPresented:text:)`
    (iOS 17.4) — an on-demand single-string system sheet — because the user wants inline, persisted,
    whole-page translation. Full design lives in the new **docs/TRANSLATION_DESIGN.md**. (TRANSLATION_DESIGN
    §3/§6, PROJECT_PLAN §8, ARCHITECTURE §3)
24. **Translation fields join `ReadAloudSchemaV2`; translation is never spoken; clear-on-target-change.**
    `Book.translationLanguage: String?` (nil = off) and `Sentence.translatedText: String?` are added
    alongside PHASE3's `SavedWord.sourceBookTitle` in one lightweight migration stage. The target is
    chosen per Book (Reader `[⋯]`, OCRReview, BookForm, plus a Settings `@AppStorage("translationLanguage")`
    default with None seeding new books); changing it clears that book's now-stale `translatedText`,
    re-translated lazily on next Reader open. TTS **always** speaks the source — translation is a visual
    aid rendered `.secondary` under each card with a toolbar toggle, its own VoiceOver element. *Why:*
    one migration for all V2 optionals; speaking a machine translation would mis-teach pronunciation, and
    stale translations after a target switch would be worse than none. (TRANSLATION_DESIGN §3–§9, PHASE2
    §8, PHASE3 §3/§4, UX_SPEC §3/§6)
