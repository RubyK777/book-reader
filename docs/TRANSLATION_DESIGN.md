# ReadAloud — Translation Subsystem Design (inline, persisted, offline-after-first)

*Purpose: give the learner the meaning of each sentence **inline, under the source card**, without leaving the Reader and without ever speaking the translation aloud. Translation is a visual aid layered onto the existing scan→listen loop: the source text stays the unit of OCR, splitting, TTS and SRS; the translation is a per-book, per-sentence string we compute once via Apple's Translation framework and persist so it is offline thereafter. This doc owns the Translation-framework integration end to end — the `.translationTask` wiring on `ReaderView`, `TranslationSession` batch calls, `LanguageAvailability` and the first-use download story, the two new model fields and their migration, the per-book target selection, the inline UI, and every empty/loading/error/offline state. Other docs reference it rather than restating it.*

**Reads with:** [PHASE2_DESIGN.md](PHASE2_DESIGN.md) §3/§5 (scan-flow wiring + schema) · [UX_SPEC.md](UX_SPEC.md) §1–2 (Reader display, toggle, screen states) · [PHASE3_DESIGN.md](PHASE3_DESIGN.md) §3–§4 (Settings default, Saved-items interaction, relaxed edit note) · [ARCHITECTURE.md](ARCHITECTURE.md) §2 (model + stack) · [OCR_PIPELINE.md](OCR_PIPELINE.md) §2 (detected source language feeding `Configuration.source`).

## 1. Why iOS 18 — the target bump

The **programmatic** Translation API — `TranslationSession`, `.translationTask`, `LanguageAvailability` — is **iOS 18**. Only the on-demand system sheet (`.translationPresentation(isPresented:text:)`, iOS 17.4) shipped earlier. PROJECT_PLAN §8 decision 4 chose 17.4 *for* the Translation framework as a Phase 4 stretch; inline, persisted, whole-page translation needs the programmatic API, so the **minimum deployment target rises 17.4 → 18.0** (`project.yml` updated, `xcodegen generate` rerun). Every "iOS 17.4+" mention across the docs is amended to 18.0.

*Trade-off:* `.translationPresentation` (17.4) was rejected — it is a one-string modal system sheet the user must summon per sentence, cannot persist its result, and cannot render inline under a card. The user wants the meaning always visible and offline, which only the session API delivers. The cost is dropping the 17.4 floor; acceptable — the app has no shipped users and iOS 18 adoption is broad by 2026.

## 2. Model additions — into `ReadAloudSchemaV2`

Two optional fields, both nil by default so **no data backfill** and a purely additive lightweight migration. They join `ReadAloudSchemaV2` — the version PHASE3_DESIGN §3 already introduced for `SavedWord.sourceBookTitle` — so **one** `VersionedSchema` bump folds in all V2 optional fields together (these two and `SavedWord.sourceBookTitle`); we do not cut a schema version per feature. (OCR_PIPELINE §5's `ocrMeanConfidence` is *not* a V2 field — it is an additive pre-ship edit folded into V1 per PHASE2_DESIGN §1, since models aren't wired yet.)

```swift
@Model final class Book {
    // …existing: title, languageCode, createdAt, coverImageData, pages
    var translationLanguage: String?   // chosen target, BCP-47; nil = translation OFF for this book
}

@Model final class Sentence {
    // …existing: text, orderIndex, isBookmarked, userNote, srs, page
    var translatedText: String?        // persisted translation of `text`; nil = not yet translated
}
```

- `Book.languageCode` (the **source**, now auto-set from OCR detection per DECISION #21) and `Book.translationLanguage` (the **target**) are the two ends of every translation pair. `translationLanguage == nil` means the toggle and all session work are skipped for that book.
- `Sentence.translatedText` is a plain stored string, **not** a relationship — it is a snapshot of meaning that must survive exactly like `SavedWord.contextSentence` does. No SRS/bookmark touches it.
- Migration: `ReadAloudSchemaV2` is a `VersionedSchema`; the `MigrationStage.lightweight(from: V1, to: V2)` needs no custom transform because every new field is optional. *Trade-off:* one combined V2 over per-field versions — fewer migration stages to test, and all these fields land in the same Phase 2/3 window anyway.

## 3. `TranslationSession` integration on `ReaderView`

SwiftUI **provides** the session; we never construct one. `ReaderView` attaches `.translationTask` and, when the configuration is non-nil, batch-translates every sentence still missing `translatedText`, writes results back, and saves.

```swift
import Translation   // iOS 18

struct ReaderView: View {
    let page: ScanPage                            // ReaderView is built from a page (PHASE2 §6)
    @Environment(\.modelContext) private var context
    @State private var config: TranslationSession.Configuration?
    @AppStorage("showTranslations") private var showTranslations = true   // toolbar toggle (§5), persisted

    private var book: Book? { page.book }         // Optional in schema — never force-unwrap
    private var sentences: [Sentence] {           // ordered, this page
        page.sentences.sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        sentenceList
            .translationTask(config) { session in
                await translateMissing(using: session)
            }
            .onAppear { refreshConfig() }
            .onChange(of: page.book?.translationLanguage) { refreshConfig() }
    }

    private func refreshConfig() {
        guard let book, let target = book.translationLanguage else { config = nil; return }
        config = TranslationSession.Configuration(
            source: Locale.Language(identifier: book.languageCode),   // detected source
            target: Locale.Language(identifier: target))
    }

    @MainActor
    private func translateMissing(using session: TranslationSession) async {
        let pending = sentences.filter { $0.translatedText == nil }
        guard !pending.isEmpty else { return }
        // Correlate by clientIdentifier — batch responses are NOT guaranteed to come back in
        // request order, so never zip by position. Map each response back to its Sentence.
        var byID: [String: Sentence] = [:]
        let requests = pending.map { sentence -> TranslationSession.Request in
            let id = "\(sentence.persistentModelID)"   // stable + unique within this batch
            byID[id] = sentence
            return TranslationSession.Request(sourceText: sentence.text, clientIdentifier: id)
        }
        do {
            let responses = try await session.translations(from: requests)   // batch, order NOT guaranteed
            for response in responses {
                guard let sentence = byID[response.clientIdentifier] else { continue }
                sentence.translatedText = response.targetText
            }
            try context.save()               // persisted → offline thereafter
        } catch {
            translationIssue = .failed(error) // §6 error row; leaves translatedText nil
        }
    }
}
```

- **Batch, not per-sentence:** one `session.translations(from:)` over the whole page's pending requests. *Trade-off:* rejected calling `session.translate(_:)` per card — batch amortizes model warm-up. **`clientIdentifier` is the primary correlation, not `zip`:** `translations(from:)` does not contractually return responses in request order, so we key each request with the sentence's `persistentModelID` string and look the response back up by `response.clientIdentifier` — zipping by index would silently persist mismatched (offline, sticky) translations onto the wrong sentences.
- **Lazy & idempotent:** only sentences with `translatedText == nil` are sent, so reopening a fully-translated page costs zero session work; a partially-translated page (interrupted mid-batch) fills the gaps on next open.
- **`config` drives everything:** setting it non-nil is what *starts* a session; setting it nil (translation off) tears the task down. Reassigning it (target changed) re-runs the task — see the clear-on-change rule (§4).
- `Locale.Language(identifier:)` takes our full BCP-47 codes directly — no trim-to-2-letters step here (that rule is for NL/Vision, per CLAUDE.md).

## 4. Per-book target selection + clear-on-change

The translate-to language is **chosen per book**, reachable from three places, all writing `Book.translationLanguage`:

1. **Reader `[⋯]` menu → "Translate to ▾"** (the primary in-context control), including a **None** row that sets it back to nil.
2. **OCRReview** at scan time (the translate-to Picker, per OCR_PIPELINE / CHANGE 3) — first page seeds the book's target.
3. **BookForm** (create/edit) — seeded from the Settings default (§7).

**Clear-on-change rule.** Changing `Book.translationLanguage` (including turning it off then on with a different target) **clears every `Sentence.translatedText` for that book** — the persisted strings are now stale (wrong target). They are re-translated **lazily on next Reader open** via the same `.translationTask` path, not eagerly in the picker.

```swift
func setTranslationLanguage(_ new: String?, for book: Book, in context: ModelContext) {
    guard new != book.translationLanguage else { return }
    for page in book.pages { for s in page.sentences { s.translatedText = nil } }
    book.translationLanguage = new
    try? context.save()
}
```

*Trade-off:* clear-all over keeping stale text or diffing which sentences changed — target changes are rare and deliberate, wiping is one line and cannot leave mixed-language pages; lazy re-fill means the cost is paid only for pages actually reopened. Setting to nil also clears (freeing the storage and guaranteeing a clean re-translate if re-enabled).

## 5. Reader inline UI + show/hide toggle

The translation renders **under** each sentence card in a secondary style (`.secondary`, slightly smaller), visually separated from the source. Source and translation form **one** `SentenceCard`; TTS highlight, tap-to-play, and the star continue to live on the source line only.

```
┌─────────────────────────────────┐
│ ← Page 3        [Aa] [文A] [⋯]  │   [文A] = show/hide translations toggle
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ Le petit prince vivait sur  │ │   source (spoken, highlightable)
│ │ une planète.            ☆   │ │
│ │ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ │ │   hairline separator
│ │ The little prince lived on  │ │   translation: .secondary, ~0.9× size
│ │ a planet.                   │ │
│ └─────────────────────────────┘ │
│ ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓ │
│ ┃ Il regardait le ▌coucher du ┃ │   ACTIVE: tint + word highlight on
│ ┃ soleil.                  ★  ┃ │   SOURCE only
│ ┃ ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄ ┃ │
│ ┃ He watched the sunset.      ┃ │   translation never highlighted, never spoken
│ ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛ │
├─────────────────────────────────┤
│  ◁◁      ▶ / ⏸      ▷▷          │
└─────────────────────────────────┘
```

- **Toggle** (`文A` toolbar button) flips `showTranslations` (`@AppStorage("showTranslations")`, so the preference survives navigation and relaunch) — a **view-only** switch, it does not clear or recompute anything; hidden translations are still persisted and instantly re-shown. It is disabled (dimmed) when `book.translationLanguage == nil` (nothing to show).
- A sentence with `translatedText == nil` while translation is on shows the **loading** shimmer line (§6), not an empty gap, so the card height is stable as the batch fills in.
- *Trade-off:* one combined card over a parallel translation column — glancing between phone and physical book (PROJECT_PLAN §4.3's core principle) wants meaning directly beneath the words, and a second column collapses on narrow width.

**TTS never speaks the translation.** `SpeechPlayer` is loaded with `sentences.map(\.text)` exactly as today (AUDIO_DESIGN §1); `translatedText` is never enqueued, never in an utterance. The translation is a reading aid only. This is DECISION #24 and is non-negotiable — mixing target-language audio into a source-language listening exercise defeats the app's purpose.

## 6. States — empty / loading / error / offline

`LanguageAvailability().status(from:to:)` classifies a pair before/around session use:

```swift
let status = await LanguageAvailability().status(
    from: Locale.Language(identifier: book.languageCode),
    to:   Locale.Language(identifier: target))
switch status {
case .installed:   break                    // fully offline, translate immediately
case .supported:   /* first-use download consent — see below */ break
case .unsupported: translationIssue = .unsupportedPair
@unknown default:  translationIssue = .unsupportedPair
}
```

| State | Detection | UX |
|---|---|---|
| **Off** | `translationLanguage == nil` | No translation lines; `文A` toggle disabled. Not an error. |
| **Empty** (nothing to translate) | page has zero sentences | Reader's existing "Nothing to read" placeholder (AUDIO_DESIGN §8); translation adds nothing. |
| **Loading / translating** | `translatedText == nil` while a session is in flight | Per-card shimmer line ("Translating…") under the source; no modal spinner — cards fill in as the batch returns. |
| **Downloading (first use of a pair)** | `status == .supported` | The **system** presents its language-download consent on first `session.translations`; we show a one-time inline note "Downloading French→English (one-time, needs network)". After download the pair is `.installed` and every later page is offline. |
| **Offline, not downloaded** | `.supported` pair but no network to fetch the model | Inline amber row: "Connect once to download French→English translation." TTS/reading is unaffected; translation fills in when back online. |
| **Unsupported pair** | `status == .unsupported` | Amber row: "Translation to «target» isn't available for «source»." The `[⋯]` picker marks unsupported targets; choosing one is blocked with the same copy. |
| **Session error** | `translations(from:)` throws | `translationIssue = .failed`; row "Couldn't translate this page — tap to retry." `translatedText` stays nil so retry re-sends only the pending sentences. |

**The airplane caveat, stated honestly.** ReadAloud's "works on a plane" promise (PROJECT_PLAN §2) holds for scanning, OCR, splitting, TTS and SRS — all fully offline. **Translation dents it for exactly one moment: the first use of a new language pair, which triggers the system model download and needs network once.** Every translation of that pair thereafter — same book, other books, offline — is local. Surface this only where it bites (the download note above); do not caveat the whole app.

*Trade-off:* we call `status(from:to:)` and let the system own the download-consent UI rather than building our own gate — the framework's consent sheet is the sanctioned path and pre-checking status lets us disable unsupported targets in the picker before the user commits.

## 7. Settings default

Add a **default translate-to language** beside the existing `targetLanguage` / `speechRate` / `voiceID` controls:

```swift
@AppStorage("translationLanguage") var defaultTranslationLanguage: String = "none"   // "none" = None (off)
```

- Seeds `Book.translationLanguage` for **new** books (BookForm reads it at create). Existing books keep their own choice; changing the default never rewrites a book retroactively.
- Includes a **None** option (`"none"`, the sentinel PHASE3 §4 owns) so a user who doesn't want translation gets books that default to off. *Trade-off:* app-default + per-book override (mirrors the voice/rate model) over a single global target — a learner may read French→English in one book and Japanese→English in another; the target belongs to the pair, seeded from a sensible default.

## 8. Word-level translate (optional nice-to-have)

The long-press → word-chip sheet (PHASE2 §7) already isolates a tapped word in context; a "Translate" chip action can reuse the **same** `Book.translationLanguage` target via a one-shot `session.translate(word)` (or the batch API with a single request) and show the gloss in the sheet — not persisted, not on the card. Noted, not specced further for v1: `SavedWord` gains no translation field now (keep the migration minimal); revisit if users ask to store glosses.

## 9. Accessibility

- The translation is its **own VoiceOver element** inside the combined `SentenceCard`, labeled `"Translation: «targetText»"`, focusable separately from the source line so VoiceOver users can hear source then meaning.
- **Dynamic Type** applies to the translation line (it scales with the source; the ~0.9× is a relative step, not a fixed point size).
- The `文A` **show/hide toggle is labeled** ("Show translations" / "Hide translations", `.isSelected` reflecting state) and its disabled state announces why is unnecessary — it simply isn't focusable-as-actionable when no target is set; the `[⋯]` "Translate to" control is the labeled entry point then.
- The download/unsupported/error rows are announced on appearance (`AccessibilityNotification.Announcement`), consistent with AUDIO_DESIGN §8's amber-row pattern — reuse that shared row component (`Shared/Components/`), do not build a second.

## Open questions

1. Does `.translationTask` re-invoke its `action` reliably when only `config`'s target changes (same identity, new value), or must we nil-then-set `config` across a runloop tick to force a fresh session? Needs on-device verification against iOS 18.x.
2. Batch size ceiling — is there a practical per-call request cap for `session.translations(from:)` on a dense page (30–40 sentences), and do we chunk? Measure before assuming one call always suffices.
3. Should a target change clear translations for **all** books sharing that source/target, or only the edited book? Current rule: only the edited book (§4) — revisit if users expect a global re-translate.
4. Does the system download-consent sheet re-prompt per app launch or only until the model is installed? Affects whether the inline download note should persist across sessions until `.installed`.
5. Word-level translate (§8): persist glosses on `SavedWord` (needs a V-next field) or always recompute on view? Deferred with the feature.

## Carry-forward tasks

- [ ] **Bump minimum target 17.4 → 18.0** in `project.yml`, `xcodegen generate`, and sweep every "iOS 17.4+" mention (PROJECT_PLAN §5.1/§8, ARCHITECTURE §3, CLAUDE.md) to 18.0 — *Accept: project builds against the 18.0 SDK floor; no doc still asserts 17.4; PROJECT_PLAN §8 decision 4 rationale reads "18.0 for the programmatic Translation API".*
- [ ] **Add `Book.translationLanguage` + `Sentence.translatedText`** to `ReadAloudSchemaV2` with a lightweight migration alongside `SavedWord.sourceBookTitle` — *Accept: a V1 store opens under V2 with no data loss; both fields default nil; one `MigrationStage.lightweight` covers all V2 optional fields.*
- [ ] **`.translationTask` batch translate on `ReaderView`** (§3): build `Configuration` from `book.languageCode`/`translationLanguage`, send pending sentences, write `translatedText`, `context.save()` — *Accept: opening a page with a target set fills every card's translation within one batch and persists them; reopening offline shows them with zero network; a partially-filled page completes the gaps on reopen.*
- [ ] **Per-book target picker in Reader `[⋯]` + clear-on-change** (§4) with a None option — *Accept: changing the target wipes that book's `translatedText` and the next Reader open re-translates lazily; selecting None hides + clears translations; other books are untouched.*
- [ ] **Inline translation UI + `文A` show/hide toggle** (§5) as one `SentenceCard` — *Accept: translation renders under the source in `.secondary` smaller type; toggle hides/shows instantly without recompute and is disabled when no target; the active card highlights and speaks the SOURCE only.*
- [ ] **`LanguageAvailability` status handling + first-use download + error/offline/unsupported rows** (§6) reusing AUDIO_DESIGN §8's amber row — *Accept: an uninstalled pair triggers the system download once then works offline; an unsupported pair is blocked in the picker with copy; a session throw shows a retry row that re-sends only pending sentences; airplane-mode after download translates with no network.*
- [ ] **Guarantee TTS ignores `translatedText`** (§5) — *Accept: with translations visible, playback speaks only source text; no target-language audio is ever enqueued (verified by asserting `SpeechPlayer.sentences == pageSentences.map(\.text)`).*
- [ ] **Settings default `@AppStorage("translationLanguage")` with None** (§7) seeding new books — *Accept: setting a default makes new books start with that target; existing books keep their own; None yields translation-off new books.*
- [ ] **Translation accessibility pass** (§9) — *Accept: VoiceOver reads the translation as its own "Translation: …" element, Dynamic Type scales it, the toggle is labeled, and download/error rows are announced on appearance.*
- [ ] **(Optional / Phase 4) Word-level translate chip** (§8) reusing the book target — *Accept: the word-chip sheet offers Translate and shows a gloss via one session request without persisting or altering the card.*
- [ ] **Log DECISIONS #21–#24** (auto-detected source, editable OCR, inline persisted translation + target bump, translation-never-spoken/clear-on-change) — *Accept: DECISIONS.md carries all four with rationale; this doc, PHASE2/PHASE3/UX_SPEC/OCR_PIPELINE cross-references resolve without contradiction.*
