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

38. **Phase 4: the Notebook is the annotation surface; one lifecycle rule; Schema V4.** Notes tab
    became a segmented Notebook (annotations with type/Confused filter chips + search) over the
    legacy "Item notes" browser. `AnnotationDetailView` implements the PIVOT_PLAN lifecycle rule in
    one place: the annotation is the parent — edits update its review card in place (cards render
    from the model), **delete cascades to the card with a confirmation that offers suspend as the
    history-keeping alternative**, and `isSuspended` removes it from `SRSEngine.dueItems` without
    touching SRS state. Confusion workflow: `isConfusing`/`isResolved` + a generated
    `aiExplanation` (D7-marked); example drafting and confusion explanation are two new
    `LearningAssetsProviding` methods (D10 seam holds — cloud provider would implement the same).
    The after-session digest is a dismissible Reader bar (counts by type + "Review now" scoped to
    the session's saves); declining loses nothing since items are already scheduled (PIVOT_PLAN
    §7.4). New stored fields forced **Schema V4** with V3 frozen (per #35's rule).
    *Rejected:* a modal digest on Reader exit (interrupts the reading flow; a nav-back interception
    is fragile in SwiftUI); free-text tags UI (comma-separated field is enough for v1).
    (NotesView, AnnotationDetailView, ReaderView, LearningAssetsProvider, Schema.swift, SRSEngine)

## 2026-07-09 — Visual Energy Pass

39. **The content tabs are energized "playful but grown-up" — motion and a semantic palette on top
    of paper & ink (#36), never gamification.** Library/Saved/Review/Notes read as flat because they
    composed raw system defaults with zero animation. This pass adds native iOS-18 motion (animatable
    `MeshGradient`, `.symbolEffect`, `.scrollTransition`, `.contentTransition(.numericText)`, springs,
    and a hand-rolled `TimelineView`+`Canvas` confetti burst) plus a **five-color semantic palette**
    (`Palette`: coral/marigold/verdigris/violet/slate, each with a mandatory lifted dark variant)
    where **source kinds and annotation types each own a hue** (`SourceKind.tint`,
    `AnnotationType.tint`, `ReviewGrade.tint` — computed vars, no schema impact) while **ink blue
    stays primary**. Celebration is **confetti + count-up stats on review completion only — no
    streaks, XP, or currencies** (PIVOT_PLAN forbids heavy gamification). Two hard rules governed the
    work: **(A) zero functional impact** — presentation-only, no `Services/`/`Models/`/routing/data-
    flow changes, same `@Query`s and actions, and all 30 tests stay green after every step; **(B)
    styles live in `Shared/Styles/`, views only compose them** — `Theme.swift` slimmed to base
    identity tokens; `Palette.swift`, `SemanticColors.swift`, `Interactive.swift` (ChipButtonStyle
    gains `tint`+spring press; new `SpringyProminentButtonStyle`), and `Cards.swift` split out;
    reusable animated *views* (`ConfettiView`, `AnimatedMeshBackground`, `CountUpText`,
    `AnimatedEmptyState`) live in `Shared/Components/`. **Reduce Motion is gated inside each shared
    component** (confetti renders nothing, mesh goes static, counts jump, springs → opacity) so
    feature views stay clean. Only the Notebook list converted `List → ScrollView/LazyVStack` (it has
    no swipe actions) to get `.scrollTransition` paper cards; Library/Saved stay `List`s (scroll
    transitions silently no-op inside `List`) and get energy from tints + symbol effects instead.
    *Rejected:* streaks/XP/badges (gamification, out of scope); an asset-catalog palette (code tokens
    keep xcodegen simple, matching #36); animating `.animation` keyed to `@Query` arrays (SwiftData
    identity churn glitches whole lists — animate only user-initiated state). *Marigold's light
    variant is deliberately dark (#A9740E) for 4.5:1 caption contrast on paper; the bright yellow
    lives only in dark mode + confetti.* (Shared/Styles/{Palette,SemanticColors,Interactive,Cards,
    Theme}.swift, Shared/Components/{ConfettiView,AnimatedMeshBackground,CountUpText,
    AnimatedEmptyState}.swift, ReviewView, ReviewSessionView, NotesView, LibraryView, SavedItemsView)

## 2026-07-12 — App icon + accessibility/voice polish pass + first-run onboarding

40. **App icon shipped as a real asset catalog; icon source never floats loose.** Added
    `ReadAloud/Resources/Assets.xcassets` with a single-size **1024×1024 RGB (alpha stripped)**
    `AppIcon` (iOS 18 single-size app-icon slot; Xcode down-samples the home-screen rungs), wired via
    `ASSETCATALOG_COMPILER_APPICON_NAME` in `project.yml`. The loose `ReadALoud_icon.PNG` in the repo
    root was deleted after import — the catalog is the one home for it.

41. **First implementation pass over `docs/IMPROVEMENTS/` — the a11y hard-rules, copy/voice, and
    onboarding quick wins, all reuse-first, zero new services.** (a) *Accessibility* (§1/§4): Reader
    transport (prev/play/next) and Review-session Play/Slow/grade buttons and the Settings voice
    preview now meet the **44 pt** target (reusing `minTapTarget`); Reader transport gains VoiceOver
    labels; the Reader active-card scale and Saved `ReplayButton` bounce are **Reduce-Motion-gated**.
    (b) *Tokens*: new `IconSize.xl` (56) rung replaces off-ladder hero literals (52/56/44); the Reader
    transport spacing stops misusing `minTapTarget` as spacing (→ `Spacing.xl`); the translation-issue
    row uses the **semantic marigold** hue instead of raw `.orange`. (c) *Voice* (§5/§6, DECISIONS
    #39): grade hints became **coaching, not verdicts** ("Show again/Barely/Got it/Easy" — SM-2 grade
    unchanged); empty states (Library/Review/Notebook/Saved/no-matches) and the legacy Item-notes state
    (now `AnimatedEmptyState`) rewritten warm and factual; digest bar "Kept this session… Review these";
    session/​shadowing summaries use adult praise; OCR + translation-unavailable copy end on the real
    next action; the tab reads **"Notebook"** to match its screen. (d) *Feature*: **one-tap "Save all"
    key vocabulary** in Learn — each generated `keyVocab` item saves as a `.word` `Annotation` with its
    gloss kept as `userNote`, skipping already-saved terms (saved rows show a check). (e) *Onboarding*:
    new `Features/Onboarding/WelcomeView.swift` — a skippable **≤3-panel** first-run intro built
    entirely from `AnimatedEmptyState` in a paged `TabView`, gated on `@AppStorage("hasSeenIntro")`,
    shown only when the shelf is empty; its final panel fires the existing scan flow and carries a
    bilingual-aware native-language nudge. *Deferred:* the generated-cover title reflow at AX sizes and
    the shelf-ledge/cover shadow-token extraction (both need layout judgment, not string/flag changes).

42. **Empty-state icon breathing is custom, not `.symbolEffect(.breathe)`; global Dynamic Type ceiling.**
    The built-in breathe effect's scale pulse read as too strong and its amplitude isn't tunable, so
    `AnimatedEmptyState` uses a hand-rolled breath — a slow (2.5s) ±3% `scaleEffect` + soft opacity fade,
    still Reduce-Motion-gated. Separately, text is capped app-wide at `.dynamicTypeSize(...DynamicTypeSize.xLarge)`
    on `RootView` so the largest accessibility sizes don't break layouts (smaller settings still honored).

43. **One Library creation entry: capture-first via the camera; the manual "New Book" (+) button is gone.**
    The `+`/`BookFormView(.create)` path duplicated the camera Scan — both create a source — and violated
    the capture-first model (#21–#22, #25). Removed the toolbar `+`, its sheet, and `isNewBookPresented`;
    the camera is the sole entry. Source **type** (book vs sign/menu/screenshot/other) is chosen in the
    post-OCR **"Save Page To"** step (`AssignBookView`), which now also lets a new *book* take a **title**
    (already) and an **optional cover** (new `PhotosPicker` → `ImageProcessor.coverJPEG`; default cover is
    the scanned page). `BookFormView` stays for **edit** (it keeps the type picker added in this pass so a
    source can be re-classified). *Rejected:* keeping `+` for empty books — capture-first means a source is
    born from a scan; add more pages later via a book's "Add Page".

44. **`SourceKind` collapsed from five kinds to two: `book` vs `quickScan`.** The sign/menu/screenshot/
    other split drove nothing but a shelf tint/icon/badge and the VoiceOver label — it never touched OCR,
    translation, audio, or learning (fragment-vs-sentence is decided per-line by `FragmentDetector` on the
    text, not by kind). The finer split just cost the user a decision on every save. Now: a **book** (multi-
    page, title/cover ceremony) or a **quick scan** (a single capture — sign, menu, screenshot). No
    migration: `kindRaw` stays a plain string and `SourceKind.normalized(_:)` folds legacy raw values
    (`sign`/`menu`/`screenshot`/`other`) into `.quickScan` on read (covered by `MigrationTests`). The
    scan-assign "Quick scan — no book" section became one button; `BookFormView`'s type picker now shows
    two options. *Rejected:* dropping categories entirely — one non-book bucket still earns its keep as
    honest labeling + shelf differentiation (verdigris wash + viewfinder badge) so a mixed shelf reads clearly.

45. **Two engagement quick wins from `docs/IMPROVEMENTS`, both pure reuse, both anti-gamified (#39).**
    (a) **"Use later" phrasebook filter** — a `useLater` chip in the Notebook's existing `TypeFilter`,
    matching `Annotation.intent == .use`; verdigris tint. Turns saved items into a usable phrasebook with
    zero new machinery. (b) **"Taking root" mastery moment** — `SRSEngine.grade` now returns a
    `GradeOutcome` reporting when an item's interval *first* crosses `matureIntervalDays` (21); the review
    session shows a one-shot, auto-dismissing "Taking root — you've really learned this" leaf banner
    (`Haptics.success`, Reduce-Motion-gated transition). It marks genuine memory consolidation, fires at
    most once per item, and carries no counter/streak/score. Confusion semantics were left untouched
    (`isResolved` stays a deliberate manual toggle in `AnnotationDetailView`), so the sibling
    "confusion-resolved delight" idea was deferred rather than auto-flipping resolution on a good grade.

46. **Two reuse-first de-dups + batch page capture (`docs/IMPROVEMENTS`).** (a) **`TranslationResolver`**
    (Services, no SwiftUI) + shared `TranslationMeaning` replace the two identical single-item translate
    copies (ReviewSession, SavedDetail); the Reader's page-batch translate is a different shape and stays
    put. (b) **`.dictionaryLookup(term:)`** View modifier over `DictionaryView` collapses the copy-pasted
    `.sheet(item:)` trio (SaveWordSheet, SentenceLearnView, SavedDetail). (c) **Batch page capture** —
    `DocumentCameraView` now returns *every* VisionKit page (was page 0 only); a "Scan Multiple Pages"
    button routes to a new `BatchReviewView` — a paged editor (one shared source language, per-page text
    + thumbnail) that ingests all pages into one book in order via `PageIngestor` (looped) and the now-
    shared `AssignBookView`. Single-page capture is unchanged (`handleScanned` sends 1 page to the old
    `OCRReviewView` flow, 2+ to batch). No schema change. *Note:* the "subtitle screenshot → listenable
    line" idea needed **no code** — a screenshot is already a quick scan → Reader with karaoke playback;
    adding a separate surface would be redundant after the two-bucket `SourceKind` collapse (#44).

47. **Batch capture uses the Live Text camera, not the document scanner.** First cut routed "Scan
    Multiple Pages" through `VNDocumentCameraViewController`, whose per-page edge/crop-box adjustment felt
    awkward next to the single-page `LiveTextCameraView` (a `DataScanner` with a plain tap-to-shoot shutter,
    no crop box). Fix: `LiveTextCameraView` gained an `allowsMultiple` mode — the shutter appends pages
    (with a thumbnail strip + tap-to-remove-last and a "Done (N)" button) instead of dismissing — and
    `startBatchCamera()` prefers it, keeping `VNDocumentCameraViewController` only as the fallback where
    Live Text is unavailable. Same tap-to-capture feel for one page or a chapter; single-page flow
    unchanged (`onFinish` returns `[UIImage]`; `handleScanned` still splits 1 vs 2+).

48. **Gentle review reminder: one local notification, never streak pings.** New `ReviewReminderService`
    (Services, pure `UNUserNotificationCenter` wrapper — no SwiftUI/models/stored prefs) keeps exactly one
    pending nudge scheduled at the deck's soonest *future* due date (`SRSEngine.nextDue(in:)` — items due
    now are excluded; nothing to wait for). Copy is warm and count-free ("A few cards from {book} are
    ready"). Off by default behind `@AppStorage("reviewRemindersEnabled")` (Settings toggle → requests
    authorization, reverts if denied); `RootView` reschedules on every `scenePhase.active` so the nudge
    tracks the real schedule. Local notifications need no entitlement/Info.plist string. Anti-gamification
    (#39): a single "ready when you are" nudge, never daily/streak reminders.

49. **The "speaking" production face shipped as a standalone ungraded mode, not a graded `CardFace`.**
    Chosen shape (Ruby): the front shows the **source text** for a *cold* read-aloud, then the model TTS
    is the answer to self-check against; offered as a separate **"Speaking practice"** button on the
    Review deck screen (sibling to Shadowing), never mixed into the graded flow. So `CardFace`/`ReviewItem.face`
    are untouched — new `SpeakingPracticeView` (text-first, `SpeechPlayer.speakOnce`, "Hear it"/"Slow"/Next,
    no recording, no SRS writes) runs over `SRSEngine.buildSession(from: deck)`. Distinct from Shadowing
    (model-first + record/compare); here the text leads and the audio is the reveal.

50. **"Your progress" reflection screen — growth story, never a score.** New `ProgressReflectionView`
    (sheet from a chart toolbar button on Review) buckets every saved item by SRS interval into a plant
    metaphor: **Learning** (<7d) → **Taking root** (7–20d) → **Known** (≥`matureIntervalDays`=21), plus a
    total-saved hero (`CountUpText` over `AnimatedMeshBackground`) and the soonest next-due line. Reflection,
    not levels/XP/percentages (#39). Reuse-heavy: `SRSState.intervalDays/dueDate`, `CountUpText`,
    `AnimatedMeshBackground`, `AnimatedEmptyState`. It queries annotations too (Review's `deck` doesn't),
    so the button isn't gated on `deck` — the view shows its own "nothing planted yet" empty state.
    Absorbs the deferred Phase-5 stats view.

51. **Quick-Scan digest — a translate-and-listen glance, no saving.** New `ScanDigestView` (sheet from a
    "Translate & Listen" row in `OCRReviewView`): splits the OCR'd page by newlines (matching a menu/sign's
    layout; falls back to `SentenceSplitter` for prose) and batch-translates every line at once via
    `.translationTask` (clientIdentifier correlation, same pattern as the Reader), showing source + inline
    translation + a per-line speaker (`SpeechPlayer.speakOnce`, source only). Nothing is persisted — the
    traveler gets an answer, not a study object. Offline after the first translate; degrades cleanly when
    the pair isn't offered or source == native. Closes the Phase-4 "Quick Scan digest" TODO.

52. **Home-screen widget via an App Group + a UserDefaults snapshot — no SwiftData in the widget.** Added
    the `group.com.rubyhung.ReadAloud` App Group (entitlements on both targets, generated by XcodeGen;
    automatic signing registered it fine) and a new `ReadAloudWidget` app-extension target. Data sharing is
    a small snapshot (`SharedStore`, compiled into both targets): the app writes `dueCount` + a "phrase to
    remember" (newest annotation + its sentence's translation) inside `AppRouter.recomputeDueCount` and
    calls `WidgetCenter.reloadAllTimelines()`; the widget's `TimelineProvider` just reads it. *Chose the
    snapshot over relocating the SwiftData store to the App Group* — a widget needs a few values, not the
    store, and this avoids schema/container coupling and migration risk (#35). Small = due count; medium adds
    the phrase. The widget declares the `com.apple.widgetkit-extension` point via a hand-written Info.plist
    (`GENERATE_INFOPLIST_FILE: NO`). Prereq now paid for the other Features §6 widget/App-Intent ideas.

53. **Widget redesigned from a due-count to a review-card deck (Ruby's steer).** The "N cards ready" framing
    read oddly at 0; the phrase preview was the liked part. Now the widget is a flashcard: a random saved
    word/phrase/sentence + its meaning, with an **interactive shuffle button** (iOS 17 `Button(intent:)` →
    `ShuffleCardIntent`, runs in-process, no app launch) to switch cards. `SharedStore` now carries a
    `[WidgetCard]` deck (text + meaning + note) + a current index; the app encodes up to 40 recent
    annotations in `updateWidgetSnapshot` (meaning = `userNote ?? sentence.translatedText`; note =
    `userExample ?? contextSentence`) and surfaces a random card each refresh. **Small** = type + text +
    meaning; **medium/large** add the note/context. Empty state prompts saving. Meaning is best-effort from
    already-stored fields (no background translation — the framework is UI-bound); cards without a stored
    meaning still show their context.

## 2026-07-12 — Fresh-start schema: drop page photos, cache translations

54. **Page photos are no longer stored; translations are cached on the annotation.** Two schema changes,
    taken as a clean reset (no prod users — wipe + reinstall rather than a staged migration, per Ruby).
    **(a) Drop `ScanPage.imageData`** — captured photos are transient OCR fodder; once sentences are
    extracted only the **book cover** is kept (set from the first ingested page in `PageIngestor` unless the
    user chose one). Slashes storage (page JPEGs were ~200-500 KB each; one cover per book now). `BookCover`
    drops its page-image fallback; `BookDetailView`'s page row shows a doc glyph + first-sentence preview
    instead of a photo thumbnail; `ImageProcessor.storageJPEG` deleted. **(b) Add `Annotation.translation`**
    — a cached machine translation of the meaning. Filled **opportunistically** (Review reveal now persists
    what it already computed via `ReviewItem.cacheTranslation`) and by **translate-on-save**
    (`SentenceLearnView` batch-translates freshly-saved annotations via a `.translationTask`, nil-then-set to
    re-fire per save). The widget's meaning prefers `translation ?? userNote ?? sentence.translatedText`.
    On-device translation is deterministic, so a card's meaning is stable once written. Both live in schema
    **V4** (redefined in place); frozen V1-V3 snapshots are untouched and MigrationTests still pass (dropping
    a property + adding an optional are lightweight). Incompatible old stores are handled by wiping
    (uninstall/reinstall), not a migration stage.

## 2026-07-12 — Duplication cleanup sweep

55. **Codebase de-duplication (3-agent survey → staged extraction).** Ran a parallel audit (data/logic,
    view patterns, helpers/dead-code) and consolidated the safe, high-value duplication. New
    `Shared/Extensions/`: `Optional<String>.nonBlank`, `String.isBlank/languageBase/hasSameBaseLanguage(as:)/
    titleSnippet(from:)`, `Date.relativeNamed/shortDate`, `PhotosPickerItem.loadCoverJPEG()`. New
    `Shared/Components/`: `ProgressCounter` (the "N of M" counter ×4) and **`PracticeSession`** — a scaffold
    (counter, hero card, two injected content slots, Next/Finish, done screen, advance/finish state machine)
    that Shadowing and Speaking (near-clones) now compose, injecting only their distinct controls +
    `onLeaveCard` cleanup. `SpeechPlayer.speakLine(_:languageCode:slow:)` collapses the load+play/speakOnce
    two-liner across 6 screens. Deleted dead code (`SharedStore.currentCard()` + the write-only `dueCount`
    path). **Fixed two bugs the duplication hid:** `ReviewView`'s resting deck omitted Annotations, and
    `ReviewSessionView.nextDueDate` ignored `isSuspended` + returned `.distantPast` for unreviewed items —
    both now route through the canonical `SRSEngine.nextDue`. SRS thresholds unified via
    `SRSEngine.takingRootIntervalDays` + `maturity(forInterval:)`. *Deferred (divergent, lower value):*
    `SpineRow`, `MeaningView`, generic batch-translate helper.

## 2026-07-12 — Audio-capture loop (AUDIO_LEARNING_DESIGN)

56. **Audio sources: capture → on-device transcribe → review → save (Phases 1–3).** A recorded/imported
    clip becomes a `.conversation` `Book` whose `ScanPage` carries the recording and whose `Sentence`s carry
    segment timings — reusing the whole downstream loop. **Ruby's scope:** both mic recording *and* file/
    video import; build the transcriber and validate accuracy live on-device (no separate CLI spike); defer
    speaker labels + word-level karaoke; one clip per source; French-first. **Schema:** `ScanPage.audioData`
    (external storage) + `audioDuration`, `Sentence.audioStart/audioEnd` (nil ⇒ TTS, non-nil ⇒ real-audio),
    `SourceKind.conversation` (excluded from the manual picker via `manualCases`); modified live models
    directly + wiped (pre-users). **Services (UI-free):** `MicAuthorizer`, `AudioFileStore` (record target,
    offline video→m4a extraction, blob↔temp-file), `OnDeviceTranscriber` (`SFSpeechRecognizer` +
    `requiresOnDeviceRecognition = true` — audio never leaves the device, #31; whole-file for MVP, chunking
    deferred), `AudioIngestor` (pure word-count timing map, tested; persist). **UI:** `AudioCaptureFlowView`
    (record w/ level meter + `.fileImporter` for audio/movie) → `TranscriptionReviewView` (play original,
    edit transcript, language + translate-to, Save). Library capture button became a menu (Scan text /
    Record audio). Added `NSSpeechRecognitionUsageDescription`. **Phase 4 (real-audio `RecordingPlayer` +
    `SentencePlaying` protocol) is next** — until then a conversation's Reader plays the transcript via TTS,
    which already works. Recording + on-device transcription are device-only (not the simulator).

57. **Audio Phase 4 — real-audio playback via a shared `SentencePlaying` protocol.** Extracted
    `SentencePlaying` (the surface the Reader depends on: `currentSentenceIndex`/`highlightRange`/
    `isSpeaking`/`speedMultiplier`/`repeatMode` + `load`/`play(at:)`/`togglePlayPause`/`next`/`previous`/
    `stop`/`reconcile`). `SpeechPlayer` (TTS) conforms unchanged; new `RecordingPlayer` (AVAudioPlayer)
    plays the **real recording**, seeking to each sentence's `[start, end]` and stepping at the boundary
    (0.04 s timer, mirroring TTS stepping); `enableRate`/`rate` give 0.5–2.0× + Slow natively. Sentence-
    level karaoke only for now (`highlightRange` stays nil → the Reader emphasizes the whole active
    sentence; word-level ranges are a later schema bump). The Reader now holds `any SentencePlaying` and
    **picks the engine at init** — a page with `audioData` → `RecordingPlayer` (ranges from the sentences'
    stored timings), else TTS — so it never branches on kind mid-flow; the repeat/speed bindings became
    manual `Binding(get:set:)` to avoid existential key-path issues. No schema change (no wipe). *Deferred
    (§5.2/§9):* shared `AudioSessionCoordinator`, lock-screen Now Playing for `RecordingPlayer`, word-level
    karaoke, long-clip chunking.

58. **Audio Phase 6a — word-level karaoke on real audio.** Store per-word timings and light up each word as
    the recording plays. **Schema:** `WordTiming` Codable (`start`/`end` seconds + `location`/`length`
    NSRange into the sentence text) + `Sentence.wordTimings: [WordTiming]?` (nil for text sentences); part
    of the fingerprint (#35) so wiped fresh. **Ingest:** `AudioIngestor.map(...)` walks the recognizer's
    per-word segments (one per `.byWords` token), pairing each to its NSRange in the sentence — producing
    both the sentence range and its word timings (the old `timings` now derives from it; tested).
    **Playback:** `RecordingPlayer.highlightRange` became a live `var`; its boundary timer (now 0.03 s)
    lights the most recent word whose `start <= currentTime`, and the Reader's existing `highlightRange`
    rendering bolds/backgrounds it — same karaoke path as TTS. Falls back to sentence-level when a sentence
    has no word timings. Light transcript edits stay aligned; heavy edits drift (documented, §7).

59. **On-demand model download via iOS 26 `SpeechAnalyzer`; model download is exempt from the no-network
    rule.** Requiring users to add a keyboard/dictation language to get an offline model was inelegant, so
    the transcriber now downloads the model itself, with consent. `TranscriberFactory` picks
    `SpeechAnalyzerTranscriber` (iOS 26 `SpeechTranscriber`/`SpeechAnalyzer` — native per-word timings via
    `.audioTimeRange` attributed runs, and `AssetInventory.assetInstallationRequest(...).downloadAndInstall()`
    for the model) or the `SFSpeechRecognizer` baseline. `Transcribing` grew `isSupported`/`isModelInstalled`/
    `installModel`; the capture flow shows **supported** languages (not just installed), and when the model is
    missing it **asks permission** then downloads ("audio stays on your phone; only the model is fetched").
    **Rule clarification (extends #31):** downloading Apple's on-device speech *model* — a one-time,
    consented, system-managed asset fetch — is permitted; the invariant is that **user audio/data never leaves
    the device**, which on-device recognition upholds. Regional match handled by `supportedLocale(equivalentTo:)`
    (fr-FR ↔ fr-CA). Recognition still device-only.
