# Phase 3 — Review, Saved Items, Settings: detailed design

Phase 3 turns the saved data from Phase 2 into a learning loop: an SM-2 review mode over bookmarked
sentences and saved words, a Saved Items browser, a Settings screen (language / voice / rate), dictionary
lookup, sentence merge/split, and the polish pass (haptics, empty/error states, accessibility). Everything
here builds on the existing `SpeechPlayer` word-highlighting playback and the SwiftData schema in
`Models/Models.swift`; nothing in this phase adds networking or third-party code.

**Reads with:** [PROJECT_PLAN.md](../PROJECT_PLAN.md) §4.4–4.6 · [ARCHITECTURE.md](ARCHITECTURE.md) ·
[PHASE2_DESIGN.md](PHASE2_DESIGN.md) (SwiftData wiring, Library) · [UX_SPEC.md](UX_SPEC.md) — per its
precedence clause, UX_SPEC **wins on navigation, screen states, interaction, and haptics**; this doc is
written to conform · [AUDIO_DESIGN.md](AUDIO_DESIGN.md) — §4 below reconciles its §6 voice-selection
sketch · [TRANSLATION_DESIGN.md](TRANSLATION_DESIGN.md) — owns the translation engine; §3–4 below only
consume it (Settings default, read-only saved translations) · [DECISIONS.md](DECISIONS.md)

---

## 1. SRSEngine (`Services/SRSEngine.swift`)

Constraint recap: `SRSState` is a Codable blob, so `#Predicate` **cannot** touch `srs.dueDate`.
We fetch a bounded candidate set with predicates that *are* expressible, then filter in memory.

```swift
/// One reviewable thing. Wraps the live model object so grading writes back directly.
enum ReviewItem: Identifiable {
    case sentence(Sentence)
    case word(SavedWord)

    var id: PersistentIdentifier { ... }        // underlying model's persistentModelID
    var promptText: String { ... }              // what TTS speaks: sentence.text / word.word
    var revealText: String { ... }              // sentence.text / "word — contextSentence"
    var languageCode: String { ... }            // word.languageCode; sentence.page?.book?.languageCode
                                                //   ?? UserDefaults "targetLanguage" (the §4 setting)
    var srs: SRSState { get set }               // nil-coalesced to SRSState() (never-reviewed ⇒ due now)
}

enum ReviewGrade: Int, CaseIterable {           // SM-2 quality mapping (plan §4.5)
    case again = 1, hard = 3, good = 4, easy = 5
}

@MainActor
enum SRSEngine {
    /// Bookmarked sentences + all saved words with srs.dueDate <= now (nil srs counts as due).
    /// Candidate fetches use #Predicate { $0.isBookmarked } / all SavedWords; dueDate filter is in-memory.
    static func dueItems(in context: ModelContext, now: Date = .now) -> [ReviewItem]

    /// dueItems(...).count — cheap at personal-library scale; used for the Review tab badge.
    static func dueCount(in context: ModelContext, now: Date = .now) -> Int

    /// Most-overdue first (dueDate ascending), cap 20, then shuffle the capped set.
    static func buildSession(from due: [ReviewItem], cap: Int = 20) -> [ReviewItem]

    /// Applies SRSState.review(quality:), writes srs back to the model, saves the context.
    static func grade(_ item: inout ReviewItem, _ grade: ReviewGrade, in context: ModelContext)
}
```

Decisions:
- **Enum wrapper over a protocol** for mixed words+sentences: exhaustive switches, no existentials,
  and grading can write `srs` back through the wrapped reference type. A `Reviewable` protocol was
  rejected — `@Model` classes + protocol witnesses + `inout` value semantics get murky fast.
- **Never-reviewed items are due immediately** (`srs == nil` ⇒ `SRSState()` with `dueDate = .now`).
  Phase 2 already initializes `srs` at save time (PHASE2_DESIGN §6 first-bookmark, §7 word save) — keep
  that. The nil-coalescing here is a **defensive fallback** on top of it (legacy rows, future code paths
  that forget), not a replacement; neither side should be removed.
- **Ordering: overdue-first then shuffle within the cap.** Pure-shuffle rejected (a 3-week-overdue item
  could miss the cap); pure-ordered rejected (all sentences clump before all words — boring sessions).
- **Stateless `enum` namespace, not an injected service object.** It holds no state; `ModelContext` is
  the only dependency and is passed per call. A DI'd class was rejected as ceremony.
- `SRSState.review` mutates `dueDate` from `.now` internally — fine for v1; `now` params above exist so
  *queries* are testable (first unit-test target per ARCHITECTURE.md §5).

## 2. Review mode (`Features/Review/`)

### 2.1 Tab, resting screen, session flow

Per UX_SPEC §1 (decided TabView), **Review is a top-level tab, not a Library-launched sheet** — a tab
cannot be disabled, so the tab always opens `ReviewView`, a resting screen with three states:

- **Due > 0** — due count + "Start session" button, which presents `ReviewSessionView` (full screen cover).
- **Nothing due, items exist** — "Nothing due — come back tomorrow" plus the next-due date
  (min `srs.dueDate` across all review items in the store), per UX_SPEC §2.
- **Never saved anything** — cross-promo empty state: "Bookmark sentences in the Reader to build your
  deck" (UX_SPEC §2). Distinct from all-caught-up so first-run users get pointed at the Reader.

The due badge lives on the tab item (`.badge(dueCount)`), recomputed on `scenePhase == .active`, on tab
appear, when a session ends, and **immediately after a bookmark toggle or word save** — new items are due
now, so the badge bumps right after the save, not on next background/foreground (UX_SPEC §1). It can't be
`@Query`-driven (the due filter is in-memory): a tiny `@Observable` due-count holder injected via
`.environment` at the `TabView` root carries it, and the Reader's star toggle and `SaveWordSheet`'s save
call its `refresh(in:)` after writing (the tab bar is hidden behind those screens, so nothing else would
reach it). Polling timers rejected: due counts change at day granularity or on actions we already observe.

`ReviewSessionView` owns an `@Observable ReviewSessionModel` and one `SpeechPlayer` (reused, not redesigned):

```swift
@Observable @MainActor
final class ReviewSessionModel {
    enum Phase { case recall            // audio played, text hidden
                 case revealed          // text shown, grade buttons active
                 case summary }         // session done
    private(set) var queue: [ReviewItem]
    private(set) var index = 0
    private(set) var phase: Phase = .recall
    private(set) var tally: [ReviewGrade: Int] = [:]
    private(set) var voiceMissing = false   // recomputed per card, see below
    let player = SpeechPlayer()

    func playPrompt()                   // player.load([item.promptText], languageCode); player.play(at: 0)
    func reveal()                       // .recall → .revealed
    func grade(_ g: ReviewGrade, in context: ModelContext)  // SRSEngine.grade, tally, advance or → .summary
}
```

Listen-first card: on card appear, `playPrompt()` fires automatically (`.task(id: index)`); a replay
button re-speaks any time. For **words**, prompt speaks the word only; reveal shows word + context
sentence with its own replay button (speaking the context up front would give the answer away).
Grading is **tap-to-commit, no undo** — mis-taps self-correct via SM-2 on the next appearance;
an undo stack was rejected as complexity without evidence of need.

**"Again" re-enqueues.** `SRSState.review(quality: 1)` sets `dueDate` to tomorrow, so without this an
Again-graded card would vanish until the next day — the opposite of what "Again" means in every
mainstream SRS. So: grading Again records the grade normally *and* appends the item once to the end of
the current queue (at most one re-appearance per item per session — loop guard); the second pass is
graded normally. Queue length (the "3 / 20" counter) updates to match.

```
┌───────────────────────────┐   ┌───────────────────────────┐   ┌───────────────────────────┐
│ ✕        3 / 20           │   │ ✕        3 / 20           │   │      Session complete     │
│                           │   │                           │   │                           │
│      🔊  (auto-plays)     │   │  « Il regardait le        │   │   22 reviewed             │
│                           │   │    coucher du soleil. »   │   │   Again 2 · Hard 3        │
│      [ ▶ Replay ]         │   │      [ ▶ Replay ]         │   │   Good 13 · Easy 4        │
│                           │   │  note: "sunset"           │   │                           │
│   ................        │   ├───────┬──────┬──────┬─────┤   │                           │
│   [ Reveal answer ]       │   │ Again │ Hard │ Good │Easy │   │  [Review 7 more] [Done]   │
└───────────────────────────┘   └───────┴──────┴──────┴─────┘   └───────────────────────────┘
        phase .recall                  phase .revealed                  phase .summary
```

States: **exit mid-session** (✕ → confirmation dialog; already-graded items keep their new `srs` —
partial progress is real progress) · **missing voice** (below). Empty states live on `ReviewView`, not here.

**Missing voice is detected proactively, not via a failure event** — `AVSpeechSynthesizer` never errors
on an uninstalled voice: `SpeechPlayer` line `utterance.voice = AVSpeechSynthesisVoice(language:)` yields
nil and the synthesizer silently substitutes the *system default* voice (French text read in English).
So before each `playPrompt()`, `ReviewSessionModel` sets
`voiceMissing = VoiceStore.voices(for: item.languageCode).isEmpty` (primary-subtag matching per §4 — a
bare `AVSpeechSynthesisVoice(language:) == nil` check misfires on `"zh-Hans"`, which has only `zh-CN`-style
voices). When true: skip playback, reveal the text immediately, show a "voice unavailable" banner — the
session stays usable as read-then-grade. The banner's "Open Settings" button must not dead-end inside the
full-screen cover: tapping it runs the same exit-confirmation as ✕ (already-graded items keep their new
`srs`), then dismisses and switches `AppRouter.tab = .settings` (§4). The Reader's missing-voice banner
(UX_SPEC §2: banner + disabled play) is driven by the **same check** at `ReaderView` load.

### 2.2 Summary

**"N reviewed" counts grades given, not unique cards**: an Again-graded card contributes both passes to
N and to the tally, matching the live "x / y" counter (which grows on re-enqueue) — the §2.1 wireframe's
22 = a 20-card queue plus two Again re-appearances; the tally always sums to N.

Summary shows the per-grade tally, then **exactly one of** (mutually exclusive, never both):
- **"Review N more"** when `SRSEngine.dueCount` post-session > 0 — tapping rebuilds a fresh session;
- **"Next review: \<relative date\>"** (min `dueDate` across all review items in the store) when nothing
  is due — if items are due now, the next review *is* now, so no date is shown.

Dismissing the summary returns to `ReviewView`, which re-runs its state logic and refreshes the tab badge.

## 3. Saved Items (`Features/Saved/SavedItemsView.swift`)

Root of the **Saved tab** (UX_SPEC §1). *Phase note:* the plan's §6 table originally listed "Saved Items
screen with notes" under Phase 2; it was deliberately moved here (and the plan updated) because rows
depend on SRS stats and the `sourceBookTitle` addition below — PHASE2_DESIGN never designed it.

Segmented **Words | Sentences** tabs (plan §4.4). Words tab: `@Query(sort: \SavedWord.savedAt,
order: .reverse)`. Sentences tab: `@Query(filter: #Predicate<Sentence> { $0.isBookmarked })`, sorted
in-memory by `book.createdAt` → `page.orderIndex` → `sentence.orderIndex` (cross-relationship sort
descriptors are unreliable in SwiftData; `Sentence` has no `bookmarkedAt`, so recency isn't available —
book-reading order is the deliberate UX, and it groups each book's sentences together).
The screen owns **one** `SpeechPlayer`; a row's replay button does `load([text], languageCode:)` +
`play(at: 0)` — starting a new row auto-stops the previous one for free (per-row players rejected:
overlapping audio, N audio-session activations).

```
┌─────────────────────────────┐   Row: text (2-line cap) · 🔊 replay ·
│ Saved        [Words|Sents]  │   caption "Le Petit Prince · Jun 30".
│ ┌─────────────────────────┐ │   Sentence source = page?.book?.title;
│ │ coucher            🔊   │ │   word source = new `sourceBookTitle`
│ │ Le Petit Prince · Jun 30│ │   snapshot (see below), else language name.
│ └─────────────────────────┘ │   Swipe actions: see removal semantics.
│ │ planète            🔊   │ │
└─────────────────────────────┘
```

**Removal semantics differ by tab.** Words: swipe / detail-view Delete → `modelContext.delete`
(true deletion, item exists nowhere else). Sentences: a bookmarked `Sentence` still belongs to its
`ScanPage` — deleting the model would silently remove it from the scanned page's Reader text, which no
user expects from pruning a saved list. So the sentence swipe action and detail button are labeled
**"Remove from Saved"** and only set `isBookmarked = false` (`srs` retained, per Phase 2 §6's unbookmark
decision); `modelContext.delete` is **never** called on a `Sentence` from this screen.

**Schema addition — `SavedWord.sourceBookTitle: String?`.** The plan's row spec requires a source
book, but `SavedWord` deliberately has no Book relationship (context survives page deletion). A string
snapshot matches the existing `contextSentence` philosophy; a real relationship was rejected — it dies
with the book, defeating the snapshot design. **Migration mechanism:** Phase 2 wired the container with
`ReadAloudSchemaV1` + `ReadAloudMigrationPlan`, and stores already exist under V1, so a silent edit to V1
would make `ModelContainer` creation throw on those stores. Instead: declare **`ReadAloudSchemaV2`**
(V1 models + the new optional property), append it to the plan's `schemas`, and add
`MigrationStage.lightweight(fromVersion: ReadAloudSchemaV1.self, toVersion: ReadAloudSchemaV2.self)` to
`stages`. Phase 2's save-word path populates it going forward; old rows show the language name.

Detail view (both kinds): full text · replay · context sentence (words) · `TextField` bound to
`userNote` (autosaves via SwiftData on edit end) · SRS stats block (`repetitions`, `easeFactor`
formatted ×1 decimal, `intervalDays`, `dueDate` relative) · "Look Up" (words, §5) · Delete / Remove
from Saved per the semantics above, with confirmation. For a bookmarked **sentence**, if its
`Sentence.translatedText` is non-nil (populated by TRANSLATION_DESIGN's Reader pass), show it read-only
in the same `.secondary` style as the Reader card, labeled "Translation"; this view never triggers or
edits a translation — it just surfaces what's already stored, and shows nothing when the field is nil. Empty states per tab tell the user *where* the
action lives: "Star a sentence in the Reader" / "Long-press a sentence in the Reader, then pick a word"
(matches the Phase 2 §7 chip sheet — there is no word-level long-press gesture).

## 4. Settings (`Features/Settings/SettingsView.swift`)

Backing store stays `@AppStorage`/UserDefaults — this is device-local preference data, not learning
data; putting it in SwiftData was rejected (no history/relationships needed, and `@AppStorage` gives
free view invalidation).

| Key | Type | Default | Consumed by |
|---|---|---|---|
| `targetLanguage` (exists) | String BCP-47 | `"fr-FR"` | default for new Books / quick scan |
| `speechRate` | Double | 1.0 | `SpeechPlayer.speedMultiplier` initial value |
| `voiceID.<languageCode>` | String (voice identifier) | unset | voice selection per language |
| `translationLanguage` | String BCP-47 or `"none"` | `"none"` | default translate-to seeding new Books (TRANSLATION_DESIGN) |

```swift
enum VoiceStore {   // thin UserDefaults wrapper; keyed per full BCP-47 code
    static func voiceID(for languageCode: String) -> String?
    static func setVoiceID(_ id: String?, for languageCode: String)
    /// Voices whose language shares the primary subtag ("fr"), exact-region matches sorted first.
    static func voices(for languageCode: String) -> [AVSpeechSynthesisVoice]
    /// Fixed preview sentence per primary subtag (table below); English sample as fallback.
    static func sampleText(for languageCode: String) -> String
}
```

`SpeechPlayer` change (small, additive): `play(at:)` resolves
`voice = VoiceStore.voiceID(for: languageCode).flatMap(AVSpeechSynthesisVoice.init(identifier:))
?? AVSpeechSynthesisVoice(language: languageCode) ?? VoiceStore.voices(for: languageCode).first`.
The last step is load-bearing: `AVSpeechSynthesisVoice(language:)` returns nil for codes with no
exact-region voice (`"zh-Hans"` — only `zh-CN`-style voices exist), the synthesizer would then silently
substitute the system-default voice, and §2.1's primary-subtag `voiceMissing` check stays false — no
banner. Ending the chain with the **same matching logic as detection** means the two can never disagree.
`init` seeds `speedMultiplier` from `speechRate`. Injecting the voice through `load(...)` params was
rejected — every call site would need plumbing for what is a global preference.

**Reconciliation — this section supersedes AUDIO_DESIGN §6/§8's sketch (one contract, not two):** one
service name (`VoiceStore`, not `VoiceCatalog`), one key scheme (`voiceID.<languageCode>` + `speechRate`,
not `voice.<code>` / `defaultSpeed`), AUDIO_DESIGN's fallback ordering absorbed into the chain above; on
missing-voice UX, UX_SPEC §2 wins per precedence — **disable play + banner**, not AUDIO_DESIGN §8's
"speak the system default" row. AUDIO_DESIGN must be amended (carry-forward task; logged in DECISIONS.md).

The plain (non-voice) rows are three. **Target language**: a `Picker` over `BookFormView`'s nine-language
list, bound to `targetLanguage` (defaults *new* Books only). **Default speech rate**: the Reader speed
picker's exact stepped 0.5×–1.0× values (`SpeechPlayer.speedMultiplier`'s displayed range), bound to
`speechRate` — a continuous slider was rejected so Settings and Reader never show unrepresentable values.
**Default translate-to language**: a `Picker` over the same nine-language list plus a leading **None (off)**
row, bound to `translationLanguage` (`"none"` ⇒ new Books start with translation off). It only seeds
`Book.translationLanguage` at create time (per-book override lives in the Reader [⋯] menu / OCRReview /
BookForm); the translation engine that consumes it is TRANSLATION_DESIGN's, not re-specified here. It sits
beside `targetLanguage` because a learner's read-and-listen language and their gloss language differ.

Voice picker rows, grouped per language. **Group list derivation:** `targetLanguage` ∪ distinct
`Book.languageCode` ∪ distinct `SavedWord.languageCode` (two fetches, dedup in memory). Each row: voice
name + quality tag (`.default`/`.enhanced`/`.premium` → "Standard/Enhanced/Premium") + a preview 🔊 that
speaks `VoiceStore.sampleText(for:)` with that voice. One fixed sentence can't serve nine languages, so
the sample table (same language list as `BookFormView`'s picker) is: fr "Le soleil se couche sur la mer."
· es "El sol se pone sobre el mar." · de "Die Sonne versinkt im Meer." · it "Il sole tramonta sul mare."
· pt "O sol se põe sobre o mar." · ja "太陽が海に沈みます。" · ko "해가 바다 위로 집니다." ·
zh "太阳正落在海面上。" · en "The sun sets over the sea." Prefix matching matters: `"zh-Hans"` has no
exact-match voices (`zh-CN` etc.), so primary-subtag matching is required, with a region-exact sort
preference.

**Enhanced-voice download guidance — instruction-based, deliberately no deep link.** This **supersedes
plan §4.6's "Settings deep link" item** (PROJECT_PLAN.md updated to match): the only public Settings
entry points are `UIApplication.openSettingsURLString` (the app's *own* page) and
`openNotificationSettingsURLString`; `App-Prefs:root=…`/`prefs:root=…` schemes are private API, cause
App Store rejection, and can't reach four levels deep anyway. So: when
`VoiceStore.voices(for:)` contains no `.enhanced`/`.premium` voice, show an inline card:

```
┌ For more natural speech ────────────────┐
│ Download an enhanced voice (free,       │
│ ~150 MB, works offline):                │
│ 1. Open the Settings app                │
│ 2. Accessibility → Spoken Content       │
│ 3. Voices → French → pick "Enhanced"    │
│ Then return here to select it.          │
└─────────────────────────────────────────┘
```

No button that pretends to jump there — a button landing on the wrong screen erodes trust more than
honest steps. The card disappears once an enhanced voice is detected (recheck `.onAppear` /
`scenePhase == .active`, since `speechVoices()` reflects new downloads without restart).

## 5. Dictionary lookup (`Services/DictionaryService.swift` + `Shared/DictionaryView.swift`)

```swift
enum DictionaryService {
    static func hasDefinition(for term: String) -> Bool   // wraps UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)
}

struct DictionaryView: UIViewControllerRepresentable {    // sheet-presented
    let term: String                                      // makeUIViewController → UIReferenceLibraryViewController(term:)
}
```

Entry points — anchored to surfaces that exist (there is **no** word-level long-press; per Phase 2 §7 /
UX_SPEC §3 word actions go through the sentence card's chip sheet):
- **SaveWordSheet action row** (the slot Phase 2 §7 explicitly reserved): once a chip is selected, a
  "Look Up" button opens `DictionaryView(term: selectedWord)`. `hasDefinition` decorates the button for
  the *selected chip* (book icon filled vs. outlined) so users learn which words will hit.
- **SavedWord detail** (§3): "Look Up" button with the same filled/outlined decoration for its word.

We **always present** the sheet rather than blocking on `hasDefinition` — when no definition exists,
`UIReferenceLibraryViewController` itself shows "No definition found" with a **Manage Dictionaries**
download flow, which is exactly the guidance we'd otherwise rebuild (and, unlike voices, *is* reachable
in-app). Pre-blocking was rejected: it hides the only path to installing a French/Japanese dictionary.
The Reader card context menu also gains **"Add Note…"** (assigned to Phase 3 by UX_SPEC §3): a small
sheet with a `TextField` bound to `Sentence.userNote`, the same field the Saved detail view edits.

## 6. Sentence merge & split (Reader, persisted mode)

Plan §7's mitigation for NLTokenizer failures ("allow manual merge/split of sentences (Phase 3)") is
designed here so the risk-table promise doesn't silently evaporate. Both actions live in the sentence
card's context menu, stop playback first (indices shift), and rewrite `orderIndex = 0..<n` after.

- **Merge with next** (fixes over-splitting, e.g. "M. Dupont" cut in two): appends the next sentence's
  text (space-joined) onto this card's `Sentence`, keeps this sentence's `srs`/`userNote`, sets
  `isBookmarked` if *either* was, then deletes the next `Sentence` model. Hidden on the last card.
- **Split…** (fixes run-on dialogue): shares only the *visual* chip layout with SaveWordSheet — **not**
  `WordTokenizer.words(in:)`, whose case-insensitive dedup makes split ambiguous ("Il le vit et il le
  prit" would show one "le" chip for two positions). Split tokenizes with `NLTokenizer(.word)` directly,
  keeping **one chip per occurrence, in order, each carrying its token's `Range<String.Index>`** in the
  sentence; tapping a chip splits *before* that occurrence (the first chip is disabled — an empty first
  half is meaningless). The original model keeps the first part (and its srs/note/bookmark); the
  remainder becomes a new un-bookmarked `Sentence` at the next `orderIndex`.

Free-text editing of the OCR transcription happens **at scan time** in `OCRReviewView` (Change 2 /
DECISIONS #22 / OCR_PIPELINE) — the full page text is freely editable there before anything is saved.
Once a page is persisted, structure is fixed only via merge/split above; **re-splitting a saved page from
edited full text is out of scope for v1** because rebuilding the sentence list would destroy each
sentence's `srs`, `userNote`, `isBookmarked`, and `translatedText`. No undo
stack — but not on an invertibility claim: **merge is lossy** for the absorbed sentence (its `srs`
history and `userNote` are discarded; only text and bookmark flag survive), and a later split can't
restore them. Accepted because the action is rare and the stakes are one sentence's stats — and the
risky case is guarded rather than undoable: **merge asks for confirmation when the absorbed sentence
has a `userNote` or `srs.repetitions > 0`**, and is immediate otherwise.

## 7. Polish checklist (exit criteria for Phase 3)

- **Haptics** — implement exactly UX_SPEC §5's map through the shared `Haptics` wrapper (UX_SPEC wins on
  haptics; this doc defines no per-event list of its own). For Phase 3 surfaces that means: grade taps
  and reveal-flip → `Haptics.select()`, word saved / bookmark toggle → `Haptics.bookmark()`, session
  complete → `Haptics.success()`. No haptic on every TTS word — tested pattern, feels like buzzing.
- **Accessibility — v1 ship criterion (plan §9), owned by this phase per UX_SPEC §6:** VoiceOver pass
  (SentenceCard as one combined element with custom actions; Review flashcard as one element, label
  "Card N of M, listening side", custom actions Replay / Reveal, grade buttons as four plain labeled
  buttons; no highlight-range announcements; auto-scroll disabled under VO) · Dynamic Type audit (AX5
  with no truncation, incl. grade buttons and voice-picker rows) · Reduce Motion (drop card scale).
  New Phase 3 controls get explicit labels: "Grade: Good", "Preview <voice name>", "Remove from Saved".
- **Empty states**: Library no books (Phase 2) · Saved tabs (§3) · ReviewView resting states incl.
  never-saved cross-promo (§2.1) · Settings voice list empty ("No voices installed for Korean" + §4 card).
- **Error states**: OCR "no text found" (exists) · missing-voice banner in Review and Reader, proactive
  check per §2.1 · SwiftData save failure → non-blocking toast, never data-destructive · camera
  permission denied → inline explainer + `openSettingsURLString` button (this one *is* the app's own
  page, so a real button is honest here).
- **Loading**: OCR spinner (exists) · Review's due-filter shows UX_SPEC §2's brief spinner state (at our
  scale it resolves within a frame, but the state exists so a huge deck never dead-waits) · no other new
  spinners.
- **Not here — crop/rotate**: plan §4.2's post-capture crop/rotate (risk-#1 mitigation) is **owned by
  Phase 2's ScanFlowView confirm step** per UX_SPEC §1, not this polish pass; PHASE2 §5's earlier
  "Phase 3 polish pass" deferral is superseded (PHASE2 amended; DECISIONS.md). Named so the hand-off
  can't silently evaporate.

## Open questions

1. Should sentence review *hide* the source book title during recall? (It can leak the answer for
   short books; currently we show nothing but may want a "from …" hint on Hard items.)
2. Does grading mid-session need to update the Review tab badge live, or is recompute on session end /
   `scenePhase` enough? (Design assumes the latter; the tab bar is hidden behind the full-screen session.)
3. `speechRate` is a global default while `SpeechPlayer.speedMultiplier` is per-screen mutable — should
   the Reader's speed picker write back to the global default or stay session-local? (Design: session-local.)
4. Cap of 20 is fixed per plan §4.5 — expose as a Settings stepper in v1 or hold until users ask?
5. Should changing the Settings `translationLanguage` default retro-offer to apply to existing Books, or
   only seed new ones? (Design: seed new only — existing books keep their per-book choice; TRANSLATION_DESIGN owns any bulk-apply.)

## Carry-forward tasks

- [ ] **SRSEngine service** — `dueItems`/`dueCount`/`buildSession`/`grade` per §1; acceptance: unit tests
      cover nil-srs-is-due, overdue-first capping at 20, and grade mapping 1/3/4/5 → SM-2 intervals.
- [ ] **`SavedWord.sourceBookTitle` via `ReadAloudSchemaV2`** — optional String snapshot + lightweight
      migration stage per §3; acceptance: a store created under V1 opens and migrates without error, and
      new saves populate the field.
- [ ] **ReviewView resting screen + tab badge** — three states per §2.1, `.badge(dueCount)` recomputed on
      activate / appear / session-end / bookmark-toggle / word-save via the shared due-count holder per
      §2.1; acceptance: badge hits 0 right after completing all due items, bumps immediately after
      starring a sentence or saving a word (no backgrounding needed), and a fresh install shows the
      never-saved cross-promo, not "nothing due".
- [ ] **ReviewSessionView + ReviewSessionModel** — listen-first flow per §2.1 incl. Again re-enqueue and
      proactive `voiceMissing` check; acceptance: audio auto-plays per card, reveal precedes grading,
      Again cards reappear once at queue end, exiting mid-session persists grades already given.
- [ ] **Session summary screen** — tally + mutually exclusive "Review N more" / "Next review" per §2.2;
      acceptance: counts match grades given and the two footers never show together.
- [ ] **SavedItemsView (Words | Sentences)** — rows with replay/source/date; word delete vs. sentence
      "Remove from Saved" per §3; acceptance: replaying row B stops row A, removing a sentence keeps it
      in the Reader (unstarred), and word deletes survive relaunch.
- [ ] **Saved item detail view** — note editing + SRS stats + Look Up; acceptance: edited note persists
      across relaunch and stats reflect the last review.
- [ ] **SettingsView + VoiceStore** — language default, per-language voice picker with per-language sample
      preview, rate; acceptance: chosen voice is used by Reader and Review playback for that language.
- [ ] **Settings default translate-to language** — `@AppStorage("translationLanguage")` picker (nine
      languages + None) beside `targetLanguage`/`speechRate`/`voiceID` per §4; acceptance: picking a
      language seeds `Book.translationLanguage` on newly created Books, picking None leaves new Books with
      translation off, and existing Books are unaffected.
- [ ] **Read-only translation in Saved sentence detail** — surface non-nil `Sentence.translatedText` in
      `.secondary` style per §3; acceptance: a bookmarked sentence that was translated in the Reader shows
      its stored translation read-only, an untranslated one shows nothing, and the detail view never kicks
      off a translation.
- [ ] **SpeechPlayer voice/rate resolution** — identifier lookup, then exact-language, then primary-subtag
      fallback per §4; acceptance: with a stored voiceID that exact voice speaks; with none, a "zh-Hans"
      book resolves to a zh-* voice — never the system-default voice in the wrong language.
- [ ] **Amend AUDIO_DESIGN §6/§8 to the §4 contract** — `VoiceStore` name + key scheme, fallback chain
      ending in primary-subtag matching, missing-voice = disable play + banner; acceptance: no doc still
      specifies `VoiceCatalog`, `voice.<code>`/`defaultSpeed`, or "speaks with the system-default voice".
- [ ] **Enhanced-voice guidance card** — instruction card per §4, no private deep links; acceptance: card
      shows only when no enhanced/premium voice exists and disappears after download + refocus.
- [ ] **DictionaryService + DictionaryView** — wrapper + sheets from SaveWordSheet action row and word
      detail per §5; acceptance: term with a definition shows it; term without shows the system Manage
      Dictionaries flow; chip/button icon reflects `hasDefinition`.
- [ ] **Sentence merge & split** — context-menu actions per §6; acceptance: merge keeps bookmark/srs,
      reindexes, and asks for confirmation when the absorbed sentence has a note or review history; split
      before a chosen occurrence (duplicate words get one chip each) yields two correctly ordered
      sentences, both survive relaunch.
- [ ] **Reader "Add Note…" context-menu action** — per §5; acceptance: note saved from the Reader shows
      in the Saved sentence detail view.
- [ ] **Accessibility pass** — UX_SPEC §6 Phase 3 items per §7; acceptance: VoiceOver user can complete a
      full review session (replay, reveal, grade); AX5 shows no truncation; Reduce Motion drops card scale.
- [ ] **Polish pass** — haptics per UX_SPEC §5, empty/error/permission states per §7; acceptance: every §7
      checklist item demonstrable on device in airplane mode.
