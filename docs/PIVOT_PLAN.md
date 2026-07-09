# PIVOT_PLAN.md — Real-World Language Learning

*Handover plan for the product pivot described in "Product Direction Document: Real-World Language Learning" (ChatGPT-authored, reviewed 2026-07-08). This document is self-contained: an implementer should be able to execute it without the original doc. Read [CLAUDE.md](../CLAUDE.md) first — every rule there (reuse-first, Shared/ layering, services-as-libraries, two language axes, xcodegen) still applies.*

**Status: signed off by Ruby 2026-07-09 (decisions recorded in DECISIONS.md #30–#33). Ready for implementation, starting at Phase 0.**

---

## 1. Updated Goal & Vision (proposed)

> **ReadAloud turns the language you see — book pages, signs, menus, screenshots — into listenable, reviewable learning material.** Photograph a sentence in the wild, understand it with a translation and phrase breakdown, hear it spoken, practice saying it, save the useful parts, and drill them until you can use them. All on-device: offline, private, zero running cost.

Positioning notes (deliberate deviations from the ChatGPT doc):

- **The Reader stays the home of the product.** The doc's proposed IA (Scan / Learn / Review / Notebook) silently deleted the app's most complete surface — the read-while-listening session with karaoke highlighting. We keep the existing 5-tab IA. The new **Sentence Learning View is a drill-down from the Reader** (tap a sentence card → learn it deeply), not a replacement for it. This one framing change preserves `ReaderView`, `SpeechPlayer`, and the whole highlight pipeline wholesale.
- **Deliberate reading (books, kids' readers, articles) remains the frequency/retention anchor; in-the-wild scanning (signs, menus) is the wedge and a capture channel.** Sign/menu encounters are episodic; the "what does this say" moment is already owned by Google Lens / Apple Live Text. Our defensible loop is what happens *after* understanding: listen → save → review. Don't bet daily retention on scan frequency.
- **Sentence-first, annotation-based.** The sentence is the single parent learning unit. Saved words, phrases, grammar points, and pronunciation items are lightweight typed *annotations on a sentence*, not five separate 8-field note objects.
- The learning loop we own: **Scan → Understand → Listen → Save → Review → (Shadow, in private)**. Shadowing is decoupled from the scan moment — nobody records their voice in a restaurant. It lives in review sessions.

## 2. Decisions already made (record in DECISIONS.md on sign-off)

| # | Decision | Rationale |
|---|---|---|
| D1 | **All AI intelligence is on-device.** Phrase breakdowns, grammar notes, and note drafting use Apple's **Foundation Models framework** (iOS 26+, Apple Intelligence devices), behind availability gating. **No networking, no cloud LLM, no accounts, no telemetry — the charter stands.** | Ruby's call (2026-07-08): zero per-scan cost. Preserves "works on a plane", privacy (scanned text can include private messages), and the no-third-party-deps rule. |
| D2 | Deployment target stays **iOS 18**; AI features are gated with `#available(iOS 26, *)` + `SystemLanguageModel.default.availability`. Non-AI devices get the fallback learn view (translation + dictionary + user-authored fields). | Don't cut off the working product from non-Apple-Intelligence devices. |
| D3 | **One save taxonomy.** The doc ships three conflicting ones (6 reasons in §5, 7 types + different 6 reasons in §6.4, 5 in §9). We use: **type** = word \| phrase \| sentence \| grammar (inferred from the selection gesture, never asked) + **intent** = optional single tag (remember \| pronounce \| use \| confused), skippable, editable later. Save is always one tap; intent is a refinement, not a gate. | The doc's own Principle 5 / §7.2: friction at the capture moment kills the habit. Measure save-rate before letting intent drive anything. |
| D4 | **Review ships only gradeable modes** on the existing single `SRSState` per item: meaning (exists), listening (new), cloze (new). Shadowing is an **ungraded practice mode** inside review sessions. Production/usage cards are deferred (can't be graded offline without an AI judge). | Ungraded modes can't feed SM-2. One item = one schedule; the card *face* varies by type/intent, the schedule doesn't fork. |
| D5 | **Cloze blanks are deterministic, not AI:** when a word/phrase annotation exists inside a sentence, the annotation *is* the blank. No LLM in the review path. | Free, offline, and immune to the machine-authored-content problem. |
| D6 | **Edit-before-persist stays the law.** OCR correction happens in `OCRReviewView` before anything derives from the text; post-save sentence text edits remain a non-goal (PROJECT_PLAN §2), because edits would orphan translations, breakdowns, and SRS history. | The current codebase already solved the cascade trap the doc reopens; keep it solved. |
| D7 | All AI-generated content is **marked as generated, editable, and deletable**, and review cards visually distinguish scanned-from-life text from anything machine-authored. Generated grammar notes get a "looks wrong" flag that feeds the confusion state. | A wrong grammar note gets spaced-repetition-reinforced for weeks. Trust and provenance are product features. |
| D8 | The doc's §13 metrics section is **replaced by on-device stats** (no telemetry, charter-compliant): a local stats view + the existing JSON export. North Star (self-assessed): *% of saved items that survive to a 3rd successful review within 30 days.* | Every funnel metric in the doc requires networking. A raw scan count is also gameable and quality-blind. |
| D9 | **Primary language pair: French (source) → English (native/explanations).** Ruby is learning French through English and dogfoods this pair. All Phase 0 spikes, voice defaults, and quality bars are graded against fr-FR → en first. The architecture stays language-agnostic (DECISIONS #25 two axes unchanged) and extends to any Apple Intelligence-supported language — but nothing ships for a language until it passes the same spike bar. | One named pair makes quality measurable; both French and English are Apple Intelligence-supported languages, so the primary experience runs fully on-device. |
| D10 | **AI generation lives behind a `LearningAssetsProvider` protocol.** v1 ships exactly one implementation: on-device Foundation Models. A **cloud-API provider is an accepted future alternative** for non-Apple-Intelligence devices — but not in v1, because it amends the no-networking charter, adds per-scan cost, and requires key management + a privacy story for scanned text. If/when added: explicit user opt-in setting, never a silent fallback, and its own DECISIONS.md entry. Below-the-tier devices in v1 get the fallback learn view (translation + dictionary + user-authored fields). | Ruby accepts the two-tier experience and wants the cloud path kept open as an alternative. The protocol seam costs nothing now (it's the CLAUDE.md services-as-libraries rule anyway) and makes the later addition a pure plug-in. |
| D11 | **Save-intent routing of review cards is deferred to a future phase** (see Phase 5). v1 collects intent (optional, D3) and displays it in the Notebook, but review card faces are chosen by annotation *type* only. | Ruby's call: validate that saved items get reviewed at all before optimizing how they're reviewed. |

## 3. Verified baseline (what the implementer inherits)

The ChatGPT doc's "current function" claims are essentially **true** — verified against code 2026-07-08, ~4,060 lines Swift, all five tabs shipped, 14 unit tests green:

- Scan → OCR → **edit/correct → confirm language** → persist: `Features/Scan/` (`ScanFlowView`, `LiveTextCameraView`, `DocumentCameraView`, `OCRReviewView`), `Services/OCRService.swift`, `Services/PageIngestor.swift`
- Sentence-by-sentence TTS with word-level highlighting, 0.5–2.0× speed, repeat, lock-screen controls: `Services/SpeechPlayer.swift` + `Features/Reader/ReaderView.swift`
- Sentence splitting users like (field-validated): `Services/SentenceSplitter.swift`
- Translation as visual aid (iOS 18 Translation framework, persisted): `Sentence.translatedText`, wired in Reader/Saved/Review
- Save words (multi-select chips) + bookmark sentences: `Features/Reader/SaveWordSheet.swift`
- SM-2 spaced repetition with recognition flashcards, grading, due badge: `Services/SRSEngine.swift`, `Features/Review/`
- SwiftData models with a versioned-schema migration path: `Models/Models.swift`, `Models/Schema.swift` (still single V1 — **pre-ship, so schema changes are nearly free right now**)
- Notes browser, dictionary lookup, JSON export, per-language voices: `Features/Notes/`, `Services/DictionaryService.swift`, `Services/ExportService.swift`, `Services/VoiceStore.swift`

Field evidence (Ruby, 2026-07-08): OCR + sentence splitting work well on **real-world signs with several sentences** and kids' reading books. Dense full pages untested and *not* on the pivot's critical path.

⚠️ **Housekeeping:** `docs/ARCHITECTURE.md` §4 is stale — it still lists "SwiftData container not wired / Models.swift is dead code", which is false (`ReadAloudApp.swift:24` wires the container; Phases 2–3 landed). Fix it in Phase 0 so nobody re-plans against a fictional baseline again.

## 4. Open decisions — resolved by Ruby, 2026-07-09

1. **Primary language pair & persona** → **French (source) → English (native)** — Ruby learning French through English, dogfooding personally. Extensible to other Apple Intelligence languages after they pass the same spike bar. Recorded as D9.
2. **Device floor** → **two-tier accepted**: on-device AI on Apple Intelligence hardware, fallback learn view elsewhere. A cloud-API provider is kept open as a future, opt-in alternative behind the `LearningAssetsProvider` seam — not in v1. Recorded as D10.
3. **Intent-driven card routing** → **deferred to a future phase**; v1 routes by annotation type only. Recorded as D11.

## 5. What was cut from the ChatGPT doc, and why

| Cut / changed | Why |
|---|---|
| Scan/Learn/Review/Notebook IA replacing the tabs | Deleted the Reader — the most complete built surface (§1) |
| Mandatory save-reason interrogation (6 reasons) | Contradicts the doc's own friction principle; three conflicting taxonomies collapsed to D3 |
| Five separate note-object types (6–8 fields each) | Sentence-parent annotations (D3/§6) are a fraction of the modeling; "sentence-first" applied to the data model |
| Production & Usage review modes | Not gradeable offline; deferred until an on-device judge is proven (D4) |
| Rhythm/stress highlighting, pronunciation scoring | Doc itself defers scoring; record-and-compare is the v1 shadowing ceiling |
| "Natural/high-quality audio" promises | System voices only (charter). Phase 0 audits enhanced/premium voices for the primary pair; shadowing quality expectation set accordingly |
| §13 metrics program | Requires forbidden telemetry; replaced by D8 |
| AI-generated novel practice sentences on cards | Machine-authored content drilled on trust; deferred, and D7 provenance rules apply if it ever ships |
| §2/§3/§11/§14 positioning boilerplate | Generic; the three ownable mechanics are: intent→review mapping (deferred, §4.3), AI-drafted editable notes (Phase 4), shadowing tied to scanned context (Phase 3) |

## 6. Data model changes (Schema V2 — do while still pre-ship)

Persistence is live but **unshipped** (single V1 schema, no released users) — this is the cheapest moment the migration will ever be. Write the V2 schema + migration first, before any feature code.

- **`Book` → generalize to a source container.** Add `kind: SourceKind` (`book | sign | menu | screenshot | other`, default `.book` in migration). Books keep title/cover ceremony; a **Quick Scan** path creates a lightweight source (auto-title from first sentence, kind pickable) so scanning a sign doesn't require inventing a "book". Source language stays per-container, auto-detected (DECISIONS #25 unchanged).
- **`Annotation` (new `@Model`), sentence-parented:** `type` (word/phrase/sentence/grammar), `range` in parent sentence text, optional `intent`, `userNote`, `userExample`, `tags`, embedded `srs: SRSState`, `isConfusing`/`resolved`. Migration mapping: `SavedWord` → Annotation(.word) (carry `srs`, context, note); bookmarked `Sentence` → Annotation(.sentence). Keep `SavedWord` reads working until Saved tab is ported, then delete.
- **`LearningAssets` on `Sentence`** (Codable value, like `SRSState`): phrase breakdown chunks, key vocab, one grammar/usage point — plus `isGenerated`, model-version string, and per-field user-edited flags (D7). Populated lazily on first visit to the Learning View; regenerated never (text is immutable post-persist, D6).
- Remember the existing constraint: `SRSState` is Codable → `#Predicate` can't reach `srs.dueDate`; `SRSEngine` already fetches-then-filters. Extend `SRSEngine.ReviewItem` to wrap `Annotation` instead of sentence/word pair.

## 7. Phased build plan with reuse map

Effort tags: S (≤1 day), M (2–4 days), L (about a week). Tick tasks in TASKS.md as they land; append decisions to DECISIONS.md.

### Phase 0 — Spikes & housekeeping (gates everything; ~1 week)

| Task | Detail | Acceptance |
|---|---|---|
| 0.1 **Foundation Models quality spike** (M) | Small debug-only screen (or macOS 26 CLI beside `Tools/OCRSpike`) that runs `@Generable` guided generation for `LearningAssets` (chunks / key vocab / one grammar point, short fields) over ~20 fixture **French sentences, explained in English** (D9). Hand-grade outputs. | ≥80% of breakdowns rated usable; wrong-grammar-note rate written down in DECISIONS.md. **If it fails: Phase 2 ships fallback-only (translation + dictionary + user fields) and D1 is revisited — do not silently ship bad grammar notes.** |
| 0.2 **Scene-text OCR fixtures** (S) | Formalize Ruby's field test: add ~15 photos (French signs, menus, kids' books, screenshots) to `Fixtures/`, run `Tools/OCRSpike` with `fr-FR`. Define the **fragment rule**: OCR lines that aren't sentences ("Salade niçoise — 14€") become phrase-type learning units, not sentence cards. | Documented accuracy per fixture class; fragment rule written into UX_SPEC.md. |
| 0.3 **Voice audit** (S) | Enhanced/premium **fr-FR system voices** at 0.4–0.5× and 1.0× rates; pick defaults for `VoiceStore`. | Named default French voice; shadowing-model quality note. |
| 0.4 **Update ARCHITECTURE.md** (S) | Fix stale §4 gaps list (persistence IS wired); add pivot summary pointing here. | Doc matches code. |

### Phase 1 — Schema V2 + Quick Scan (L)

Everything in §6, plus: Library tab renders non-book sources sensibly (kind icon instead of cover ceremony); scan flow gets a "Quick Scan" entry that skips book assignment (`ScanFlowView` + `OCRReviewView` reuse — add a "no book" branch to the existing book-assign step).

*Reuse: `Models/Schema.swift` versioned-migration pattern, `PageIngestor` (unchanged pipeline), `LibraryView`/`CoverThumbnail`, entire `Features/Scan/`.*
*Acceptance: existing data migrates losslessly (write a migration test); scan-a-sign → sentences in a Quick source; all current screens still work.*

### Phase 2 — Sentence Learning View (the pivot's heart) (L)

New `Features/Learn/SentenceLearnView.swift`, opened by drill-down from a `SentenceCard` in `ReaderView` and from `OCRReviewView` after a Quick Scan. Sections:

1. **Original + translation** — reuse the Reader's Translation integration and persisted `translatedText`.
2. **Understand** — `LearningAssets` via a new `Services/LearningAssetsProvider.swift` protocol (D10) whose sole v1 implementation wraps Foundation Models (0.1's prompt), availability-gated (D2), each field marked-generated/editable/deletable (D7). Keep the protocol UI-free and injectable per CLAUDE.md so a cloud provider can plug in later. Fallback below iOS 26 / unsupported device / unsupported language: dictionary lookups (`DictionaryService`) + empty user-authored fields. Generation shows an explicit loading state and a retry; never blocks audio.
3. **Listen** — reuse `SpeechPlayer`: play sentence, slow (0.5×), repeat; add **tap-a-chunk/word to hear it** (one-utterance call — trivial with the existing engine). Phrase-level playback uses the breakdown chunks when present, word tokens otherwise.
4. **Save** — one-tap per D3: long-press/select a word or chunk → Annotation of inferred type; whole-sentence save button; optional intent chips after the save (skippable). Reuse `SaveWordSheet`'s chip `FlowLayout` for selection UI.

*Reuse: `SpeechPlayer`, `SentenceCard`, Translation wiring, `DictionaryService`, `SaveWordSheet`/`FlowLayout`, `DesignSystem` tokens, `WordTokenizer`.*
*Acceptance: scan a sign → tap sentence → understand/listen/save in <30s; airplane-mode run degrades gracefully; a saved chunk appears in Saved and gets a due date.*

### Phase 3 — Review modes (M)

Extend `ReviewSessionView` (keep its session/grading/summary shell) with card renderers chosen by annotation type:

- **Meaning** (exists — port from sentence/word to Annotation).
- **Listening**: `SpeechPlayer` plays first, text hidden, reveal → grade. Sentence- and phrase-type items.
- **Cloze**: deterministic blank per D5 for word/phrase annotations inside a sentence.
- **Shadowing (ungraded)**: play → record (`AVAudioRecorder`, new tiny `Services/VoiceRecorder.swift` — UI-free, injectable, per CLAUDE.md library rules) → replay both. Mic permission primer + denied-state fallback (mode simply hidden). Recordings capped (keep last take only) — no retention UI in v1. Offered at session end for pronounce-intent items; never interrupts graded flow.

One `SRSState` per annotation (D4); grading updates the single schedule whichever face was shown.

*Reuse: `SRSEngine` (extend `ReviewItem`), `ReviewView`/`ReviewSessionView`, `SpeechPlayer`, `AppRouter` due-badge.*
*Acceptance: a session mixes card faces by type; SM-2 math unchanged (existing tests still green); mic denial never blocks a session.*

### Phase 4 — Structured notes & digest (M)

- **Notes tab upgrade**: from flat browser to annotation-centric — filter by type/tag/intent/confused, each note shows parent sentence + source context. AI-drafted `userExample`/explanation offered as an editable draft (accept/edit/delete), availability-gated.
- **Lifecycle rule (one rule settles the doc's whole §7)**: the annotation is the parent; editing it updates card faces in place; deleting cascades to its review card with confirmation; a suspend toggle exists.
- **After-session digest**: on leaving a Reader/scan session, a small summary ("3 sentences, 5 words, 2 phrases saved") with one action: start review now / later. Declined = nothing lost (items are already saved and scheduled).
- **Confusion state**: "I'm confused" on any item → flagged, AI explanation attempt (gated), unresolved/resolved filter in Notes.

*Reuse: `NotesView` search shell, `SavedItemDetailView` patterns, `Shared/` components.*

### Phase 5 — Deferred until the loop is validated

Pronunciation compare via on-device `SFSpeechRecognizer` + WER (the WER scorer belongs in `Services/` as a pure library), production/usage cards (needs a judged-output spike), **intent-driven card routing (D11)**, **cloud `LearningAssetsProvider` for non-Apple-Intelligence devices (D10 — explicit opt-in, charter amendment, own DECISIONS entry)**, additional language pairs beyond fr→en after passing the 0.1/0.3 spike bar (D9), generated practice sentences (D7 rules), multi-page batch capture, on-device stats view (D8), local notification for due reviews.

## 8. Success signals without telemetry (D8)

Dogfood + TestFlight feedback only. Self-checks that mirror the funnel: are you scanning weekly? Do saved items reach a 3rd successful review within 30 days (visible in Saved detail's SRS stats)? Is the fallback (non-AI) learn view good enough that you'd keep it? Any generated grammar note you caught being wrong (D7 flag count in Notes)?

## 9. Risk register (from the strategy review — the survivors)

1. **Foundation-Model quality on a ~3B on-device model** is the pivot's biggest technical bet → gated by Spike 0.1 with an explicit fallback product.
2. **Scan frequency may be episodic** → positioning hedged (§1): reading remains the anchor; validate with your own usage diary during dogfooding.
3. **Fragments-not-sentences** for menus/signs → fragment rule in 0.2; phrase-type units are first-class (D3).
4. **Shadowing opt-in may be low** → it's ungraded, decoupled, and cheap (one recorder service); kill without regret if unused.
5. **System-voice quality varies by language** → 0.3 audit before promising anything; shadowing expectations set per-language.
6. **Apple Intelligence language coverage** is narrower than Vision OCR's catalog → availability gating is per-language, not just per-device; fallback view is the product for uncovered languages.
