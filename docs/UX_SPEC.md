# ReadAloud — App-wide UX Specification

*Defines the finished-v1 navigation model, per-screen states, Reader interaction rules, visual language, haptics, accessibility, and first-run flow. This is the design contract for Phases 2–3 UI work; it builds on the already-implemented word-level highlighting (`SpeechPlayer.highlightRange` + `ReaderView.SentenceCard`) and does not redesign it.*

**Reads with:** [PROJECT_PLAN.md](../PROJECT_PLAN.md) §4 (screens) · [ARCHITECTURE.md](ARCHITECTURE.md) (component contracts, known gaps)

**Precedence.** Where this document and [PHASE2_DESIGN.md](PHASE2_DESIGN.md) / [PHASE3_DESIGN.md](PHASE3_DESIGN.md) disagree, **this document wins on navigation, screen states, interaction, and haptics** (TabView root + `AppRouter`, Review-tab badge, Review openable at 0 due with an empty state, Scan as `.sheet`, §5 haptics map); **the phase docs win on service and data contracts** (versioned `ModelContainer` wiring per PHASE2 §1, `SRSEngine` API per PHASE3 §1). The phase docs must be amended to match (carry-forward task below) and the ruling logged in DECISIONS.md.

## 1. Navigation map

**DECISION: TabView with four tabs — Library, Saved, Review, Settings — plus two modal/pushed flows (Scan, Reader).**
Rejected: single NavigationStack with a hub Home. Saved and Review are destinations users open *cold* (on the bus, without a book in hand); burying them two pushes deep kills the SRS habit loop. Tabs also give Review a free, always-visible due-count badge. Four top-level areas is exactly the sweet spot where a tab bar beats a stack.

```
TabView
├─ Library (NavigationStack)        Saved (NavigationStack)      Review        Settings
│   LibraryView                      SavedItemsView               ReviewView    SettingsView
│   ├─ push → BookDetailView         ├─ push → SavedWordDetail    (flashcard    (Form)
│   │          (pages of a Book)     └─ push → SentenceDetail      session,
│   │          ├─ push → ReaderView                                no pushes)
│   │          └─ sheet → ScanFlowView ("Add Page" — Book known, assign skipped)
│   └─ sheet → ScanFlowView  ── fullScreenCover → document camera
│              (capture [camera + Import Photo] ▸ OCR (auto-detect) ▸ OCRReview
│               [edit text · confirm source lang · translate-to] ▸ assign-to-Book
│               ▸ persist ▸ dismiss, then push Book + ScanPage onto libraryPath)
```

Rules:
- **Scan is a flow, not a tab.** It is a `.sheet` launched from Library (toolbar `+` and the empty state CTA) and from Book detail ("Add Page" per PROJECT_PLAN §4.2, which skips the assign step). Rejected: a dedicated Scan tab — scanning is a verb that always ends *inside* a Book, so it belongs to Library. Current `ScanHomeView` is dismantled in Phase 2: the source-language pick moves to the `OCRReviewView` confirm step (not Book creation — `BookFormView` no longer forces a language pick; `Book.languageCode` is auto-set from the confirmed detection on the first page), capture/OCR into `ScanFlowView` (kills the `[String]: @retroactive Identifiable` hack, per ARCHITECTURE §4.4).
- **Capture-first — OCR auto-detects the source language, so no Book (and no pre-picked language) is needed up front (DECISIONS #21, supersedes #4's ordering clause).** A Library-launched scan opens straight on the camera; `OCRService.recognizeText(in:languageHint:)` runs Vision with `automaticallyDetectsLanguage = true` and reports a `detectedLanguageCode`. Then `OCRReviewView` shows the recognized text with the detected source language pre-selected (correctable) and the optional translate-to picker; only after **Use** does the assign panel appear — pick an existing Book or quick-create one (title only; source language pre-filled from detection, editable later). Book-detail "Add Page" passes `languageHint = book.languageCode`, inherits the book's translate-to, and skips assign. #4's every-scan-persists-into-a-Book clause still stands; only the ordering flips. Canonical flow strings:
  ```
  Library (book unknown): capture/import → OCR(auto-detect) → OCRReview(edit text · confirm
    source language · choose translate-to) → assign (pick/quick-create Book; source pre-filled)
    → persist → push Reader
  Add Page (book known):  capture/import → OCR(languageHint = book.languageCode) → OCRReview(edit
    text · confirm source language · translate-to inherited) → persist → push Reader
  ```
  "Any language" = any in `VNRecognizeTextRequest.supportedRecognitionLanguages` for the `.accurate` revision (Latin scripts + zh/ja/ko/… — a bounded list, **not** literally every language). Detection + OCRReview's language confirm are designed in **docs/OCR_PIPELINE.md §1**; the translate-to picker belongs to the translation subsystem in **docs/TRANSLATION_DESIGN.md**. Rejected: assign-before-capture so OCR knows the language — auto-detection removes the reason it existed.
- **Capture step = `VNDocumentCameraViewController`** (the system document camera — auto edge detection, deskew, multi-page batch), **plus an Import Photo `PhotosPicker`** (plan §4.2 fallback; the simulator workflow CLAUDE.md depends on, and the only path when camera permission is denied). Full capture design lives in **docs/OCR_PIPELINE.md §1** — this doc owns the surrounding UX, that doc owns the pipeline. Rejected: `CameraPicker` (`UIImagePickerController`) + a hand-built crop overlay — the doc camera provides deskew/crop for free (DECISIONS #14).
- **Crop = the document camera's corner-adjust review step** (PROJECT_PLAN §4.2; the §7 risk-#1 mitigation; closes ARCHITECTURE gap #6). It confirms/reframes each page inside the system UI before returning the image, so there is no custom crop screen. **Imported** photos have no crop step in v1 — they go straight to OCR and the §4 quality gate catches bad ones (DECISIONS #15); an optional import-crop UI is a Phase 3 carry-forward. This pulls crop into Phase 2 (via the doc camera), superseding PHASE2 §5's "deferred to Phase 3 polish."
- **Reader is pushed, never modal** — it hides the tab bar via `.toolbar(.hidden, for: .tabBar)` to maximize card space. Back returns to BookDetail; `onDisappear` keeps stopping playback. **Post-scan push is two values** (as PHASE2 §5 specifies): the sheet dismisses, then appends the `Book` to `libraryPath` first (skip if it is already the top element — the Book-detail "Add Page" path) and then the `ScanPage`; pushing only the page would make Back land on Library, violating the rule above.
- Routing state lives in one `@Observable` router injected via `.environment`:

```swift
@Observable final class AppRouter {
    var tab: AppTab = .library                 // enum AppTab { case library, saved, review, settings }
    var libraryPath = NavigationPath()          // push Book / ScanPage values
    var isScanFlowPresented = false
    private(set) var dueCount = 0               // Review tab badge source of truth
    func recomputeDueCount(in context: ModelContext) { dueCount = SRSEngine.dueCount(in: context) }
}
```
- App entry becomes `TabView` + the PHASE2 §1 versioned container: `ModelContainer(for: Schema(versionedSchema: ReadAloudSchemaV1.self), migrationPlan: ReadAloudMigrationPlan.self)`, whose schema lists **all four models explicitly**. ScanPage/Sentence would come free via Book's relationship graph, but `SavedWord` has no relationship to anything (Models.swift) — omit it and the first `insert(SavedWord)` crashes at runtime. `ScanPage.imageData` gets `@Attribute(.externalStorage)` before first ship — full-resolution photos do not belong in the SQLite row.
- Review tab badge: `.badge(router.dueCount)`. The count lives on `AppRouter` (above) because it cannot be `@Query`-driven (in-memory SRS filter) and the events that change it fire deep inside Reader — a different tab subtree with the tab bar hidden — so the shared router injected via `.environment` **is** the event channel. `recomputeDueCount(in:)` is called on `scenePhase == .active`, after each review session, and by Reader immediately after bookmarking a sentence or saving a word (new items are due immediately — nil `srs` counts as due, per PHASE3 §1 — so the badge must bump right after a save, not on next background/foreground). Source: `SRSEngine.dueCount(in:)` (API per PHASE3 §1) — fetch bookmarked sentences + all saved words, filter `srs.dueDate <= .now` **in memory** (`#Predicate` cannot reach into the Codable `SRSState`, per ARCHITECTURE §2).

## 2. Per-screen state inventory

Every screen below implements all four columns; "—" means the state cannot occur. (SavedWordDetail / SentenceDetail are pushed *with* their item, so they have no empty/loading states; deleting the item pops the screen.)

| Screen | Empty | Loading | Error | Permission-denied |
|---|---|---|---|---|
| Library | `ContentUnavailableView("Scan your first page", systemImage: "book.pages")` + prominent Scan button | — (SwiftData is sync at this scale) | — | — |
| Book detail | "No pages yet" + **Add Page** CTA (reachable via quick-create-then-cancel or deleting every page; layout per PHASE2 §4) | — | — | — |
| Scan flow | — | `ProgressView("Reading page…")` overlay on frozen capture with a **Cancel** button (cancels the OCR `Task`, returns to capture; requires the `OCRService` cancellation amendment — see the reconcile task). Target ≤ 10 s on iPhone 12+ (plan §9); on slower devices the spinner + Cancel simply persist — never a dead wait | Inline retry card: "No text found — flatten the page, add light" + **Retake** / **Import** buttons; `UINotificationFeedbackGenerator.error` | Camera-denied panel (see §7): explains, offers **Open Settings** (`UIApplication.openSettingsURLString`) and **Import Photo** fallback — the flow is never a dead end |
| OCR Review | — (only reached with non-empty OCR text; empty OCR is caught upstream as the Scan-flow error) | — (text handed in from OCR; translation is deferred to Reader, not run here) | — (free-text edit can't fail; a wrong source-language detection is *fixed* here via the Picker, not surfaced as an error) | — |
| Reader | Cannot open with 0 sentences (Scan flow blocks it); defensive `ContentUnavailableView` anyway | — (sentences passed in); translation shows a per-card "Translating…" secondary line while `.translationTask` runs (§3) | Voice missing for language: banner "No <lang> voice installed" + link to the Settings voice picker (PHASE3 §4); playback buttons disabled. Translation errors are non-fatal and scoped to the secondary line — unsupported pair / not-downloaded states in §3 | — |
| Saved | Per-tab: "Words you save while reading appear here" / same for Sentences, each with a "How to save" hint line | — | — | — |
| Review | "Nothing due — come back tomorrow" + next-due date; if zero items ever saved, cross-promo: "Bookmark sentences in the Reader to build your deck" | — (due filter is a synchronous in-memory pass at personal-library scale, per PHASE3 §7 — no spinner) | — | — |
| Settings | Per-language voice group with zero installed voices: "No voices installed for <language>" + the enhanced-voice guidance card (PHASE3 §4/§7) | Voice list loads sync (`AVSpeechSynthesisVoice.speechVoices()`) | — | Shows camera row status "Denied — tap to open Settings" |

**OCR Review screen** (`Features/Scan/OCRReviewView.swift`, DECISIONS #22) — shown *after* OCR, *before* any persistence, so editing here risks no `srs`/bookmark:

```
┌─────────────────────────────┐
│ Cancel      Review      Use │
├─────────────────────────────┤
│ From: [ French  ▾ ]  (detected — correct it here)
│ Translate to: [ English ▾ ] (optional · None)
├─────────────────────────────┤
│ ┌─────────────────────────┐ │   full-height editable
│ │ Le petit prince vivait  │ │   TextEditor prefilled
│ │ sur une planète.        │ │   with OCRResult.text
│ │ Il regardait le coucher…│ │
│ └─────────────────────────┘ │
├─────────────────────────────┤
│           [ Retake ]        │
└─────────────────────────────┘
```
- **From** = source-language `Picker` prefilled with `OCRResult.detectedLanguageCode`; correcting it is how the user fixes a wrong detection. On Add-Page it defaults to `book.languageCode`.
- **Translate to** = optional target `Picker` (incl. **None**), seeded from `@AppStorage("translationLanguage")` (Library entry) or inherited from the book (Add Page); writes `Book.translationLanguage`. Design in docs/TRANSLATION_DESIGN.md; the picker is surfaced here, in the Reader [⋯] menu, and in BookForm.
- **Use** splits the *edited* text via `SentenceSplitter` under the confirmed source language, then persists (Library entry → assign panel next; Add Page → straight to persist). **Retake** returns to capture. Full-text editing is free *only here* — after a page is saved, structure is fixed via merge/split (PHASE3 §6); re-splitting a saved page from edited full text is out of scope for v1 (it would destroy sentence-level `srs`/bookmarks).

## 3. Reader interaction spec

Wireframe unchanged from PROJECT_PLAN §4.3. Deltas and precise rules:

**Tap targets.** The whole sentence card (min height 44 pt, `.contentShape(Rectangle())`) toggles: tap inactive card → `play(at:)`; tap the *active* card → `togglePlayPause()` (today it restarts the sentence — change this). The star is a separate 44×44 pt `Button` overlaid trailing-top; it must swallow its tap (`Button` already does) so starring never triggers playback.

**Long-press menu** — `.contextMenu` on the card (500 ms system default):
- **Save Word…** → sheet with the sentence's words as tappable chips (word tokenization via `NLTokenizer(.word)`); picking one creates `SavedWord(word:contextSentence:languageCode:)`. The sheet's action row also carries **Look Up** for the selected chip (`UIReferenceLibraryViewController`), exactly the slot PHASE2 §7 reserved and PHASE3 §5 designed — one chip sheet serves both jobs. Rejected: a separate "Look Up…" menu item with its own parallel chip sheet (doubles a nontrivial custom component for one job); per-word tap targets inside the card — they'd collide with word highlighting and card tap.
- **Copy Sentence**, **Bookmark/Unbookmark** (mirrors the star), **Add Note…** (Phase 3, writes `Sentence.userNote`).

**Auto-scroll + manual-scroll rule (DECIDED).** Auto-scroll centers the active card on `currentSentenceIndex` change (already built). New rule: *any user drag suspends auto-scroll; playback continues untouched.* While suspended during playback, a floating pill appears above the playback bar; tapping it recenters and re-arms auto-scroll. Tapping any card also re-arms (explicit intent). The pill keys on `autoScrollSuspended && player.isSpeaking` only (sighted mode; VoiceOver uses a different condition — §6) — **no card-visibility detection** (iOS 17 has no scroll-visibility callbacks; `onScrollVisibilityChange` is iOS 18) and the simpler rule is fine: even with the active card visible, the pill correctly reads as "you scrolled away." The `simultaneousGesture(DragGesture())` suspension trigger is known-finicky across iOS releases — verify on-device early; if it misfires, bridge a `UIScrollView` delegate instead. Rejected: auto-resume after a timeout — yanking the viewport mid-read is exactly the disorientation the "glance between phone and book" principle forbids.

```swift
@State private var autoScrollSuspended = false
ScrollView { … }
    .simultaneousGesture(DragGesture().onChanged { _ in autoScrollSuspended = true })
// pill: Button("Now playing ↓") { autoScrollSuspended = false; scrollToActive() }
```

**Playback bar** (existing) gains a bookmark shortcut for the active sentence. Speed picker and repeat toggle stay as-is.

**Inline translation (per book; DECISIONS #23–24 — full design in docs/TRANSLATION_DESIGN.md).** The Reader is the only screen that *renders* translation; it wires the SwiftUI Translation framework and this doc owns the surrounding UX.
- **Display**: each SentenceCard shows `sentence.translatedText` on a secondary line **under** the source text — `.secondary`, one step smaller (`.footnote` under a `.title3` card), visually separated (top hairline/inset). Hidden entirely when the book has no `translationLanguage` or the toolbar toggle is off. **TTS always speaks the SOURCE text — translation is a visual aid, never spoken.**
- **Toolbar show/hide toggle**: a translate glyph in the Reader toolbar flips an `@AppStorage("showTranslations")` bool (persisted across opens/relaunch); labeled **"Show translations"/"Hide translations"**. Hidden/disabled when the book has no target set.
- **Per-book target picker**: the Reader `[⋯]` menu carries **Translate to ▸** (language list incl. **None**) writing `Book.translationLanguage`; also settable in OCRReview and BookForm, and new books seed from the Settings default `@AppStorage("translationLanguage")` (PHASE3). Changing the target **clears** that book's `Sentence.translatedText` (now stale) → re-translated lazily on next Reader open. One-line trade-off: per-book (not per-sentence) target keeps the whole page in one language and lets a single `.translationTask` batch-fill it.
- **How it runs**: SwiftUI's `.translationTask(_:action:)` (iOS 18) provides a `TranslationSession`; on open we batch-translate the untranslated sentences and write `translatedText` back (persisted → offline thereafter). Word-level translate is an optional nice-to-have reusing the same target — noted, not specced. Rejected: `.translationPresentation` (iOS 17.4 on-demand single-string sheet) — the ask is inline, persisted, whole-page.

Translation states (scoped to the secondary line — never block playback):
- **Off / no target**: no secondary line; toggle hidden or disabled.
- **Loading**: `.translationTask` running → "Translating…" (`.secondary`, italic) in the secondary slot of each not-yet-translated card.
- **Error — unsupported pair** (`LanguageAvailability().status(from:to:) == .unsupported`): "Translation unavailable for this language pair" in the secondary slot; toggle disabled.
- **Offline — pack not downloaded** (`.supported` but not `.installed`, no network): banner "Language not downloaded — connect once to enable translation." The first use of a new pair triggers the **system** language-download consent and needs network **once**, then is fully offline — an honest dent in the works-on-a-plane promise for that first pair only.

## 4. Visual language

- **Type scale** (all Dynamic-Type text styles, never fixed sizes): sentence card text `.title3` (active word `.title3.bold()` — existing); card metadata/captions `.footnote.foregroundStyle(.secondary)`; list rows `.body`; screen titles system `.navigationTitle`. An `[Aa]` toolbar item in Reader offers card-text override `.title3 / .title2 / .title1` stored in `@AppStorage("readerTextSize")` — book learners often want bigger-than-body text without cranking system-wide Dynamic Type.
- **Cards**: `RoundedRectangle(cornerRadius: 14)`; idle fill `Color(.secondarySystemBackground)`, active fill `Color.accentColor.opacity(0.14)` + 2 pt accent border + 1.02 scale (existing — keep). Saved/Review reuse the same card component (`Shared/CardStyle.swift` ViewModifier) so the app reads as one system.
- **Accent**: single accent color (asset-catalog `AccentColor`, teal-ish; final value is a design pick, not a spec concern). Accent is reserved for *the live thing*: active card, play button, word chips. Everything else monochrome. (The Review tab badge stays the system red `.badge` pill — iOS 17 exposes no tint API for tab-item badges, so it is deliberately outside the accent system.) Word highlight stays `.yellow.opacity(0.6)` — semantically "highlighter pen," distinct from accent; on dark mode use `.yellow.opacity(0.35)` with `.primary` text to hold ≥ 4.5:1 contrast.
- **Dark mode**: free by policy — only semantic colors (`Color(.secondarySystemBackground)`, `.primary`, `.secondary`, `.bar`) are permitted; any hardcoded RGB is a review defect. The two exceptions (yellow highlight, accent opacity fills) are specified above for both appearances.

## 5. Haptics map

One shared wrapper (`Shared/Haptics.swift`) so generators are prepared and reused:

```swift
enum Haptics {
    static func tap()      // UIImpactFeedbackGenerator(style: .light)  — card tap starts playback
    static func bookmark() // UIImpactFeedbackGenerator(style: .medium) — star toggled, word saved
    static func success()  // UINotificationFeedbackGenerator .success  — scan OCR succeeded; review session complete
    static func failure()  // UINotificationFeedbackGenerator .error    — OCR found no text / failed
    static func select()   // UISelectionFeedbackGenerator              — speed change, review grade buttons, card flip
}
```

Deliberately silent: auto-advance between sentences (fires every few seconds — haptic spam), pause/resume (audio itself is the feedback), scroll pill.

This map is authoritative; PHASE3 §7 already conforms to it and defines no per-event list of its own — no amendment needed.

## 6. Accessibility

**The core tension:** the app's output *is* synthesized speech, and VoiceOver is also synthesized speech. Two voices talking over each other is the failure mode. Strategy — **VoiceOver narrates the UI; the app's TTS remains the one voice that reads book content. Never both about the same thing.**

- **Card grouping**: each SentenceCard groups its source text + state as one element — `.accessibilityLabel(sentenceText)`, `.accessibilityValue(isActive ? "Playing" : isBookmarked ? "Bookmarked" : "")`, `.accessibilityAddTraits(.isButton)`. The star button is *removed* from the VO tree (`.accessibilityHidden(true)`) and replaced by custom actions on the card: `.accessibilityAction(named: "Play/Pause")`, `"Bookmark"`, `"Save a word"` (opens the §3 chip sheet, whose action row carries Look Up). Rejected: leaving star as a separate element — doubles swipe count through a page for zero benefit.
- **Translation element**: when a translation is shown (§3), it is its **own** VoiceOver element *within* the combined SentenceCard, labeled `"Translation: <text>"` — so VO stops on source-then-translation as two reads (use `.accessibilityElement(children: .contain)` on the card with the source group primary and the translation a distinct child, rather than folding the translation into the source label). Dynamic Type applies to it like any card text. The toolbar show/hide translations control is a labeled button ("Show translations"/"Hide translations"); the `[⋯]` **Translate to** picker exposes standard VO Picker semantics.
- **No announcement spam**: never post `.announcement` for `highlightRange` changes (word-per-second chatter), and do not announce sentence auto-advance while TTS is audible — sighted-identical audio already conveys it. Only post announcements for *silent* state changes: "Bookmarked", "Word saved", "Scan complete, 12 sentences".
- **Ducking (DECIDED)**: do not duck or pause app TTS for VoiceOver. Keep the `.playback` + `.spokenAudio` session; VoiceOver ducks other audio automatically while it speaks — that system behavior is correct here (VO utterances are short UI labels; the sentence remains intelligible). Rejected: pausing TTS whenever `UIAccessibility.isVoiceOverRunning` and VO focus moves — it would make browsing the page while listening impossible, which is the app's whole point.
- **VO focus vs auto-scroll**: while VoiceOver is running, disable auto-scroll entirely (`UIAccessibility.isVoiceOverRunning`) — programmatic scrolls fight VO's own focus-follows-swipe scrolling. §3's drag-keyed pill condition can never fire under VO (VO navigation produces no `DragGesture` callbacks, so `autoScrollSuspended` stays false), so the visibility condition becomes: `UIAccessibility.isVoiceOverRunning ? player.isSpeaking : (autoScrollSuspended && player.isSpeaking)` — under VO the pill is an ordinary labeled button ("Now playing — jump to active sentence") shown whenever playback runs, giving VO users the way back to the active card.
- **Playback bar**: standard labeled buttons ("Previous sentence", "Play"/"Pause", "Next sentence", "Repeat sentence, on/off", "Speech speed, 0.75×"). Speed picker gets `.accessibilityAdjustableAction`.
- **Dynamic Type**: all text in text styles (§4); cards grow vertically, never truncate (`.fixedSize(horizontal: false, vertical: true)`); playback bar switches to two rows at accessibility sizes via `@Environment(\.dynamicTypeSize)`.
- **Contrast**: active-card tint at 0.14 opacity is decorative; the 2 pt accent border + scale carry the state so it also survives Increase Contrast and grayscale. Word highlight per §4. Honor `.accessibilityReduceMotion`: drop the 1.02 scale and use opacity-only transitions.
- **Review screen**: the flashcard is one element; label = "Card N of M, listening side"; custom actions Replay / Reveal; grade buttons are four plain buttons after reveal (not custom actions — they are the primary UI, not shortcuts).

## 7. First-run experience

1. **First launch** lands on Library's empty state (no walkthrough carousel — rejected: users came to scan, let them).
2. **Camera priming**: the pre-permission panel appears at the moment camera access is first needed — now that the flow is capture-first (§1), that is at the *start* of a Library scan (and when tapping "Add Page"), immediately before presenting the document camera, and only while `CameraAuthorizer.status == .notDetermined`. Import needs no permission, so **Not now** still leaves a working path (below) — illustration, "ReadAloud photographs book pages to read them aloud. Photos never leave your device.", buttons **Continue** (→ `AVCaptureDevice.requestAccess(for: .video)`) and **Not now**. **Not now** dismisses only the panel, landing on the flow's capture step with **Import Photo** still offered (§1) and the camera preview replaced by a "Allow camera access" placeholder — it never kills the whole flow. `@AppStorage("hasPrimedCamera")` is set **only on Continue** (once the system dialog has actually been shown); a "Not now" user gets the soft ask again next time, never a surprise jump to the near-irreversible system dialog — which is the entire point of priming.

```swift
enum CameraAuthorizer {
    static var status: AVAuthorizationStatus { AVCaptureDevice.authorizationStatus(for: .video) }
    static func request() async -> Bool      // wraps requestAccess(for: .video)
}
```
3. **Denied path**: Scan flow shows the §2 denied panel; Import Photo keeps the core loop alive with zero camera permission.
4. **First-scan guidance**: capture screen shows a one-time dismissible overlay — "Flatten the page · fill the frame · avoid glare" (the plan's #1 OCR risk, attacked in UX as well as code). `@AppStorage("hasSeenScanTips")`.
5. **First successful scan** → success haptic + push straight into Reader; a one-time tip anchored to the first card: "Tap a sentence to hear it. Long-press to save words."

## 8. Fragment rule — real-world scans (signs, menus, labels)

*Added for the real-world learning pivot ([PIVOT_PLAN.md](PIVOT_PLAN.md) Phase 0 task 0.2 / risk #3). Governs how OCR lines that are not sentences behave in the Reader, the Sentence Learning View, and save.*

**DECISION: a fragment is a phrase-type learning unit, not a sentence.** Scene text routinely yields lines with no sentence structure — "Salade niçoise — 14€", "Sortie", "Ouvert 7j/7". Treating them as sentences would generate grammar breakdowns and sentence-type review cards for things that have no grammar. Rules:

- **Reader — no visual fork.** Fragments render as ordinary tappable cards: same `SentenceCard`, same tap-to-play, same drill-down into the Sentence Learning View. A scanned menu reads as a list of cards like any page. Rejected: hiding fragments or collapsing them into one "menu items" card — the tap-to-hear-and-save loop is exactly as valuable for "Salade niçoise" as for a full sentence, and a second rendering path would fork `SentenceCard` for zero user benefit.
- **Understand section** (Sentence Learning View, PIVOT_PLAN Phase 2): the item is treated as a **phrase** — translation, key vocab, and chunk playback as usual, but **no grammar-point generation**. A generated grammar note for "Salade niçoise — 14€" is precisely the machine-authored garbage PIVOT_PLAN D7 guards against; suppressing it is cheaper than flagging it.
- **Save**: the whole-item save button creates a **phrase-type `Annotation`**, never a sentence-type one (taxonomy per PIVOT_PLAN D3 — type is inferred, never asked). Sub-selections inside a fragment behave as everywhere else (word/phrase inferred from the selection gesture). Downstream, review card faces follow annotation type (PIVOT_PLAN Phase 3), so a fragment never receives a sentence-face card.

**Classification heuristic.** A pure `String → Bool` function beside `SentenceSplitter` in `Services/` (CLAUDE.md library rules: no SwiftUI, no model imports; unit-test against menu/sign fixture lines). After OCR and sentence splitting, a line is a **fragment** when:

- the sentence tokenizer yields **no terminal punctuation** (`.` `!` `?` `…` or CJK equivalents) **and** the line is **under ~6 words**, **or**
- the line is **mostly numerals/symbols/prices** — a majority of its tokens are digits, currency, or symbol/punctuation tokens (e.g. "14€", "9:00–18:00", "Wi-Fi : gratuit").

Everything else stays a sentence, even without terminal punctuation — the ~6-word threshold exists precisely so longer unterminated lines (headlines, kids'-book lines like "Le petit chat regarde la lune") keep the full sentence treatment. Both thresholds are starting values: tune them against the task 0.2 fixture set and log the final values in DECISIONS.md.

## Open questions

1. Should Reader offer a "play whole page" continuous mode in v1, or wait for Phase 4 (needs background-audio mode, ARCHITECTURE gap #8)?
2. Word-chip sheet (Save Word) tokenization: is `NLTokenizer(.word)` adequate for ja/zh where "word" boundaries are fuzzy, or do those languages need character-range selection?
3. Does the Review due-count badge need live updating while the app is foregrounded (timer at midnight boundary), or is refresh-on-activate enough?
4. iPad: default `TabView` renders a bottom tab bar on iPadOS 17 and a top tab bar on iPadOS 18+; a sidebar uses `.tabViewStyle(.sidebarAdaptable)` (iOS 18 — now within our 18.0 target, so no `#available` gate needed). Accept the defaults, or adopt sidebarAdaptable / design a two-column Library/Reader split later?
5. First-pair translation download (needs network once): surface the system consent proactively when a target is chosen in OCRReview, or lazily on first Reader open when the "not downloaded" state appears? (dents the works-on-a-plane promise either way — TRANSLATION_DESIGN owns the resolution.)
6. Should OCRReview's source-language Picker list the full `supportedRecognitionLanguages` set, or only the detected language plus a short "likely" shortlist with a "More…" expander?

## Carry-forward tasks

- [ ] Replace `ScanHomeView` with `TabView` root + `AppRouter` + the PHASE2 §1 versioned `ModelContainer` registering all four models (SavedWord explicitly — it has no relationships) (Phase 2) — acceptance: four tabs render, Scan sheet launches from Library, a `SavedWord` inserts without crashing, `[String]: Identifiable` hack deleted.
- [ ] Build `ScanFlowView` **capture-first** (capture [camera + Import Photo] ▸ confirm/crop ▸ OCR auto-detect ▸ OCRReview ▸ assign-to-Book ▸ persist; "Add Page" passes `languageHint` and skips assign) with loading/error/denied states per §1–2 (Phase 2) — acceptance: every §2 Scan-flow state reachable in manual test, including crop/rotate on confirm (for imports too), Cancel during OCR, and Settings deep link from denied panel; OCR runs with no pre-picked language and the detection lands pre-selected in OCRReview; the import path completes the full flow on the simulator.
- [ ] Build `Features/Scan/OCRReviewView` between OCR and persistence per §2 (Phase 2) — acceptance: editable `TextEditor` prefilled with `OCRResult.text`, source-language Picker prefilled with `detectedLanguageCode` and correctable, optional translate-to Picker (incl. None); **Use** splits the *edited* text under the confirmed source language and persists, **Retake** returns to capture; nothing is saved before Use.
- [ ] Reader inline translation per §3 (Phase 2/3) — acceptance: `sentence.translatedText` renders as a `.secondary` line under each card, the toolbar toggle shows/hides it, the `[⋯]` **Translate to** picker writes `Book.translationLanguage` and clearing/changing it wipes stale `translatedText`; TTS still speaks source only; "Translating…", unsupported-pair, and not-downloaded states all reachable.
- [ ] Reader VoiceOver translation pass per §6 (Phase 3) — acceptance: with a translation shown, VoiceOver reads source and translation as two separate elements ("Translation: …") within the card, and the show/hide toggle is announced with its label.
- [ ] Make `OCRService.recognizeText` cancellable (Phase 2, prerequisite for the §2 Cancel button): keep a reference to the `VNRequest`, honor cooperative `Task` cancellation by calling `request.cancel()` and throwing `CancellationError` — today `handler.perform` runs in a detached task with no cancellation path — acceptance: cancelling the wrapping Task mid-OCR returns to confirm/crop with no result applied.
- [ ] Reconcile PHASE2/PHASE3/PROJECT_PLAN with the precedence note: Router → `TabView` + `AppRouter` (incl. `dueCount`), badge moves to the Review tab, Review opens at 0 due with the §2 empty state, scan resolves the Book before capture, **crop/rotate moves into Phase 2's ScanFlowView** (supersedes PHASE2 §5 "deferred to Phase 3 polish"), **OCR becomes cancellable** (reverses PHASE2 §5 "processing is not cancellable"; service-contract change per the task above), **Review gets no due-filter spinner** (§2 now matches PHASE3 §7's no-spinner decision), and PROJECT_PLAN §4.1's hub wording ("link to Saved Items, Review") updated for tabs; log the rulings in DECISIONS.md. (Haptics need no reconcile — PHASE3 §7 already conforms to §5.)
- [ ] Add `@Attribute(.externalStorage)` to `ScanPage.imageData` before first persisted scan (Phase 2) — acceptance: store file shows image blobs outside the SQLite database.
- [ ] Reader: active-card tap = pause/resume; star = separate 44 pt target; context menu with Save Word chip sheet (Phase 2) — acceptance: starring never starts playback; a word can be saved and appears in Saved tab.
- [ ] Implement manual-scroll suspension + "Now playing" pill per §3 (Phase 2) — acceptance: dragging during playback never fights the user; pill recenters and re-arms auto-scroll.
- [ ] Camera priming panel + denied-state panel + first-scan tips overlay per §7 (Phase 2) — acceptance: fresh install shows priming before system dialog; denial still allows Import Photo scanning.
- [ ] `Shared/Haptics.swift` wired to all §5 events (Phase 3) — acceptance: each mapped event fires exactly its listed generator; auto-advance fires none.
- [ ] Reader/Review VoiceOver pass per §6: combined card elements, custom actions, no highlight announcements, auto-scroll disabled under VO (Phase 3) — acceptance: VoiceOver user can play, bookmark, and save a word from a card without leaving it; ship-criteria "VoiceOver-navigable Reader" met.
- [ ] Dynamic Type + Reduce Motion audit per §4/§6 (Phase 3) — acceptance: AX5 size shows no truncation; Reduce Motion removes card scale animation.
- [ ] Review badge via `AppRouter.dueCount` + `recomputeDueCount(in:)` calls from Reader save/bookmark, session end, and scene activation per §1 (Phase 3) — acceptance: badge equals `dueDate <= now` count across bookmarked sentences and saved words after relaunch, and updates immediately after bookmarking a sentence or saving a word.
- [ ] Missing-voice error banner in Reader with Settings voice link (Phase 3) — acceptance: uninstalled-language book shows banner and disables play instead of falling back to the system default voice in the wrong language (today `AVSpeechSynthesisVoice(language:)` returns nil and the synthesizer substitutes the default voice — a French page read with English pronunciation).
- [ ] Decide continuous-page playback + background audio mode (Phase 4) — acceptance: open question 1 resolved and logged in DECISIONS.md.
