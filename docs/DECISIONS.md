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

## 2026-07-07 — Language model

25. **Two language axes: unrestricted source vs. native language.** ReadAloud cleanly separates the two
    language axes that #21/#24 still conflated under the misnamed `targetLanguage`, because the language
    *on the page* and the language *in the user's head* are different facts with different owners and
    lifetimes:
    - **Source language = per Book/page.** The language printed on a page. Auto-detected per page
      (`NLLanguageRecognizer`), correctable in **OCRReview** from the **full** set, and now with an
      **optional pre-capture hint** ("Page language: Auto-detect ▾", Library-entry only) that biases
      Vision's `recognitionLanguages` before OCR — **Auto-detect stays the default**. It is **no longer
      restricted to a curated 9-language list**: options come from Vision's supported recognition
      languages via the new `LanguageCatalog` (`ReadAloud/Shared/Languages.swift`), which **replaces the
      old 9-item `SupportedLanguage` enum**. Source belongs to the Book, not the user.
    - **Native language = per user.** The user's *own* language — the translation **destination**. This
      is the real global setting: `@AppStorage("nativeLanguage")`, defaulting to the device language
      (`LanguageCatalog.deviceDefaultNative`). It **replaces `@AppStorage("targetLanguage")`** (whose
      confusing meaning had been "default *source* language"), and it seeds `Book.translationLanguage`
      when translation is built.
    - **Three separately-bounded "supported" sets — never one gate.** *OCR / detect it* = Vision
      recognition languages (broad, unrestricted); *hear it* = installed `AVSpeechSynthesisVoice` (you
      can OCR a language you have no voice for — surface that gap, do not hide the language); *translate
      it* = Translation framework `LanguageAvailability`. The old 9-item list must stop being the single
      gate for all three.
    **Supersedes** the 9-item `SupportedLanguage` list wherever it gated source options, and the
    source-meaning of `targetLanguage`. Refines #24: the per-book target is still `Book.translationLanguage`,
    but its **default seed is now `nativeLanguage`** (the destination), not a separate source default.
    *Why:* forcing a per-book detected value and a per-user setting through one 9-item list mislabeled
    both and hid the honest three-set nuance. (OCR_PIPELINE §1/§2/§4.5, PHASE3 §4, TRANSLATION_DESIGN §7)

## 2026-07-07 — Translation build, iPad, device delivery

26. **Schema stays single-version pre-ship; the V2 split is deferred.** Refines the migration *mechanism*
    of #24 (the V2 fields themselves stand). A `ReadAloudSchemaV2` that lists the *same* `@Model` classes
    as V1 produces an identical version checksum, and SwiftData aborts at launch with "Duplicate version
    checksums detected." A genuine V2 needs a **frozen V1 snapshot** (its own nested model copies without
    the new fields) — worth writing only to migrate a *shipped* store, of which there is none. So the
    translation fields (and, later, `SavedWord.sourceBookTitle`) fold into the single current version.
    **Carry-forward, load-bearing:** before the FIRST model change that lands *after* a build reaches a
    real device (e.g. Ruby's install below), freeze current models as V1 + add a real V2 + `.lightweight`
    stage — that snapshot is what her store migrates from. (Schema.swift, TRANSLATION_DESIGN §2)
27. **Universal app, local-only per-device storage, no sync.** The app targets iPhone **and** iPad
    (`TARGETED_DEVICE_FAMILY "1,2"`, verified running on both simulators). The SwiftData store is
    **local to each device** — no CloudKit, no `ModelConfiguration` cloud database, so a phone and an
    iPad keep independent libraries. *Why:* the user explicitly wants per-device storage without
    cross-device sync for now; the SwiftData default (no CloudKit) already delivers exactly this, so no
    code beyond confirming it. Revisit if shared libraries are wanted later (would add a CloudKit
    container + entitlement). (project.yml, ReadAloudApp.swift)
28. **One playback-speed control, on the Reader, 0.5×–2.0×.** The Settings "speech rate" stepper is
    removed — it was never wired to `SpeechPlayer` (dead UI), and two speed controls confused the user.
    The Reader picker is the single control; its range widens from 0.5–1.0× to **0.5×–2.0×**
    (`utterance.rate = AVSpeechUtteranceDefaultSpeechRate × multiplier`, so 2.0× = the max valid rate).
    Speed stays session-local (resets per Reader open) — persisting it wasn't requested. *Why:* the user
    asked for exactly one speed control, on the reading screen, up to 2×. (ReaderView, SettingsView)

## 2026-07-08 — Live Text capture

29. **Live Text camera (`DataScannerViewController`) is the primary capture; document scanner
    demoted to a fallback.** The user found `VNDocumentCameraViewController` hard to operate — its
    auto-shutter + edge detection fights curved/glossy book pages. The new `LiveTextCameraView`
    shows recognized text highlighted live in the viewfinder (immediate "it's reading the page"
    feedback) with a **manual shutter** the user taps when ready → `capturePhoto()` → the existing
    OCR pipeline. This delivers the plan's "Live Text" capability *and* fixes the capture UX in one
    view. `VNDocumentCameraViewController` remains as a fallback on devices without live scanning
    (`DataScannerViewController.isSupported == false`); Import Photo stays the simulator / camera-denied
    path. *Rejected:* keeping the doc scanner primary (the source of the complaint); a plain
    manual-shutter `AVCapturePhotoOutput` camera (no live-text feedback, less useful). This supersedes
    OCR_PIPELINE's framing of Live Text as a Phase 4 tap-to-hear mode — it's a capture camera now.
    (LiveTextCameraView, ScanFlowView, OCR_PIPELINE §7)

## 2026-07-09 — Real-world learning pivot

30. **Product pivot: real-world text becomes the input surface; the goal/vision is updated.** The app
    generalizes from "photograph a book page" to "turn the language you see — pages, signs, menus,
    screenshots — into listenable, reviewable learning material," per the reviewed Product Direction
    Document (ChatGPT-authored; multi-agent strategy review 2026-07-08). The full handover spec is
    **[PIVOT_PLAN.md](PIVOT_PLAN.md)** — new master plan for Phases 0–5; PROJECT_PLAN.md remains the
    record of the shipped book-reader foundation. Key framing kept from the review: the Reader stays
    the home surface (the new Sentence Learning View is a drill-down from its sentence cards, not a
    replacement); deliberate reading remains the retention anchor with in-the-wild scanning as the
    wedge; the sentence stays the single parent learning unit with saved words/phrases/grammar as
    typed annotations. *Rejected:* the doc's Scan/Learn/Review/Notebook IA (it had no home for the
    Reader — the most complete built surface); its three conflicting save-reason taxonomies; ungraded
    production/usage review modes in v1. (PIVOT_PLAN.md)

31. **AI intelligence is on-device only (Apple Foundation Models, iOS 26+), behind a
    `LearningAssetsProvider` protocol; deployment target stays iOS 18.** Phrase breakdowns, grammar
    notes, and note drafting come from the on-device Foundation Models framework, gated on
    `#available(iOS 26, *)` + `SystemLanguageModel` availability; non-Apple-Intelligence devices get a
    fallback learn view (translation + dictionary + user-authored fields). The no-networking charter
    stands. *Why:* zero per-scan cost (Ruby's explicit constraint), privacy for scanned text, works
    offline. A **cloud-API provider is an accepted future alternative** for the lower tier — kept open
    via the provider seam but out of v1 because it would amend the charter, add COGS, and require key
    management + a privacy story; if added it must be explicit user opt-in with its own DECISIONS
    entry. Gate: PIVOT_PLAN Phase 0 spike 0.1 must pass (≥80% usable breakdowns) or Phase 2 ships
    fallback-only. (PIVOT_PLAN.md D1/D2/D10)

32. **Primary language pair is French (source) → English (native).** Ruby is learning French through
    English and dogfoods this pair; all Phase 0 quality spikes (Foundation Models output, scene-text
    OCR fixtures, voice audit) are graded against fr-FR → en first. The two-axes language model
    (#25) is unchanged and the architecture stays language-agnostic; additional Apple
    Intelligence-supported languages ship only after passing the same spike bar. (PIVOT_PLAN.md D9)

33. **Save-intent is collected but does not route review cards in v1.** Saving is one tap; type
    (word/phrase/sentence/grammar) is inferred from the selection gesture, intent
    (remember/pronounce/use/confused) is an optional, skippable, later-editable tag shown in the
    Notebook. Review card faces are chosen by annotation *type* only; intent→card-mode routing —
    the direction doc's strongest idea — is deferred to a future phase until we've observed that
    saved items actually get reviewed. *Why:* friction at the capture moment kills the save habit,
    and routing is an optimization of a loop that must exist first. (PIVOT_PLAN.md D3/D11)

34. **Pivot restructure landed as a real frozen-V1 → V2 lightweight migration, not a fold-into-V1.**
    PIVOT_PLAN §6 assumed the schema was still pre-ship ("migration nearly free"), but a build with a
    live store is already on Ruby's device (#26), so the V1 models are frozen as nested copies inside
    `ReadAloudSchemaV1` and the live classes became `ReadAloudSchemaV2` with a `.lightweight` stage:
    added `Annotation` entity, added optionals (`Sentence.learningAssets`, annotation relationship),
    and `Book.kindRaw` (non-optional with default `"book"`). Enums (`SourceKind`, `AnnotationType`,
    `SaveIntent`) are stored as raw strings with tolerant accessors (unknown → sensible fallback) to
    keep future migrations lightweight. Proven by `MigrationTests.v1StoreMigratesToV2`, which builds a
    V1 store, reopens it through the plan, and checks data + defaults + V2 writes. Also in this batch:
    `FlowLayout` promoted to `Shared/Components/` (rule of two — SaveWordSheet + SentenceLearnView),
    and `SpeechPlayer.speakOnce(_:slow:)` for one-off word/chunk playback (clears the queue position
    so didFinish can't auto-advance — preserves the AUDIO_DESIGN state machine). *Rejected:* renaming
    `Book` to `Source` (heavy migration for a cosmetic win; `kind` carries the semantics).
    (Schema.swift, Models.swift, MigrationTests.swift, PIVOT_PLAN §6)

35. **Codable value structs are part of the SwiftData schema fingerprint — changing one means a new
    schema version.** Adding the optional `LearningAssets.userEditedAt` (D7 edited-provenance) changed
    the V2 checksum; a store created by the V2 build (already on Ruby's iPhone the same day) then
    failed to open with "Cannot use staged migration with an unknown model version" — caught by the
    simulator test host before it could ship. Fix: V2 is now a **frozen snapshot carrying its own
    nested `LearningAssets` copy** (without the new field), live models are `ReadAloudSchemaV3`, and
    the plan chains two lightweight stages (V1→V2→V3). `MigrationTests.v2StoreMigratesToV3` replays
    the on-device store shape. *Rule going forward:* treat `SRSState`/`LearningAssets`/any embedded
    Codable exactly like @Model fields — every change, even adding an optional, freezes the previous
    version and bumps the schema. (Schema.swift, MigrationTests.swift)

36. **Visual identity: "paper & ink", via the previously-missing `Shared/Styles/` layer.** The app
    read as plain because every screen composed raw system defaults. `Theme.swift` now defines it:
    learning content (sentences, words, chunks — anything in the source language) is set in **serif**
    (`.fontDesign(.serif)`, New York) like a book page, while UI chrome and native-language glosses
    stay system sans — the type distinction *is* the information (source vs. native). One accent
    everywhere: **French ink blue** (#2B5B84 light / lifted for dark, from the pivot-plan identity),
    applied app-wide via `.tint`. Cards are warm paper with a hairline stroke (`learningCard(active:)`
    modifier), chips share `ChipButtonStyle`, section headers share `SectionHeaderLabel`, and the
    karaoke color is a single `Theme.karaoke` token used by both Reader and Learn. Applied to the
    core loop (Reader cards, Learn view, SaveWordSheet) first; remaining screens adopt the same
    tokens as they're touched. *Why:* Ruby asked for a visual upgrade; CLAUDE.md's Shared/Styles rule
    already mandated this layer. *Rejected:* an asset-catalog accent (code tokens keep xcodegen
    simple); theming every screen in one pass (risk of churn before Phase 3 reworks Review anyway).
    (Shared/Styles/Theme.swift, ReaderView, SentenceLearnView, SaveWordSheet, ReadAloudApp)

37. **Phase 3 review modes: one queue, three card faces, routed by item type (D4/D11).**
    `ReviewItem` gained `.annotation` and a `face` property: word/grammar → meaning (the existing
    flashcard), sentence → **listening** (audio-first, text hidden until reveal — this includes
    legacy bookmarked sentences, a deliberate behavior change consistent with the pivot; reverting is
    one line in `ReviewItem.face`), phrase → **cloze** via the pure `ClozeBuilder` (D5: the saved
    term IS the blank; case/diacritic-insensitive; falls back to meaning when the term isn't
    blankable). Cloze fronts never auto-speak — the audio contains the answer. One `SRSState` per
    item regardless of face (D4). **Shadowing is ungraded** and lives behind a "Practice speaking"
    button on the session summary (never interrupts grading): `VoiceRecorder` service swaps the
    audio session to `.playAndRecord` only while recording and keeps just the last take; mic denial
    degrades to listen-and-repeat. *Rejected:* per-face SRS schedules (fork explosion, D4 says one);
    shadowing as a graded card (can't be judged offline). (SRSEngine, ClozeBuilder, VoiceRecorder,
    ReviewSessionView, ShadowingPracticeView, project.yml mic usage string)
