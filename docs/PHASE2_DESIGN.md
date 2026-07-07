# Phase 2 — Persistence + Library detailed design

Purpose: specify exactly how SwiftData is wired into ReadAloud, how navigation moves onto the app-wide TabView root, and how scans, bookmarks, and saved words become persistent — without re-designing anything Phase 1 already delivered (OCR pipeline, SpeechPlayer, word-level highlight in ReaderView). Everything here is on-device, Apple-frameworks-only, iOS 17.4+, `@Observable` + SwiftData.

*Reads with:* [PROJECT_PLAN.md](../PROJECT_PLAN.md) §4–6 · [ARCHITECTURE.md](ARCHITECTURE.md) §2, §4 · [UX_SPEC.md](UX_SPEC.md) — per its precedence clause, UX_SPEC **wins on navigation, screen states, interaction, and haptics**; this document is amended to conform · `ReadAloud/Models/Models.swift`

---

## 1. Container wiring + schema versioning

Version the schema from day one (plan §7 risk: "SwiftData migration pain later").

```swift
// Models/Schema.swift
enum ReadAloudSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Book.self, ScanPage.self, Sentence.self, SavedWord.self]
        // all four explicit — SavedWord has no relationships (nothing pulls it in); omit it and the first insert crashes
    }
}
enum ReadAloudMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [ReadAloudSchemaV1.self] }
    static var stages: [MigrationStage] { [] }   // grows with V2, lightweight-first
}

// App/ReadAloudApp.swift
@main struct ReadAloudApp: App {
    private let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Schema(versionedSchema: ReadAloudSchemaV1.self),
                migrationPlan: ReadAloudMigrationPlan.self)
        } catch { fatalError("Cannot open store: \(error)") } // no degraded mode — nothing works without it
    }()
    @State private var router = AppRouter()
    var body: some Scene {
        WindowGroup { RootView().environment(router) }
            .modelContainer(container)
    }
}
```

Model edits folded into V1 (the app has never shipped, so no migration stage is needed):
- `@Attribute(.externalStorage)` on `ScanPage.imageData` and `Book.coverImageData` (§8).
- New `ScanPage.lastOpenedAt: Date?` — powers resume-reading (§4).
- `SavedWord` stays standalone (no relationship to Sentence) — `contextSentence` snapshot already guarantees survival past page deletion; a relationship would reintroduce that coupling.

Trade-off: `VersionedSchema` ceremony now vs plain `ModelContainer(for:)` — costs 15 lines today, but retrofitting versioning after user data exists is where SwiftData migrations go wrong. The SRS-in-blob limitation stands (see ARCHITECTURE.md §2 warning): `#Predicate` cannot touch `srs.dueDate`; all due-item queries fetch candidates and filter in memory.

## 2. Navigation redesign

**Root is the UX_SPEC §1 TabView — Library, Saved, Review, Settings — not a single NavigationStack.** An earlier draft of this section designed a lone-stack `Router` with Library as a hub; UX_SPEC §1 explicitly rejected that shape (Saved/Review are opened *cold*, and tabs give Review a free due badge), its precedence clause wins on navigation, and PHASE3_DESIGN is already written against tabs — so this section now records the conforming design, closing UX_SPEC's "amend PHASE2" carry-forward. The `[String]: @retroactive Identifiable` hack dies with `ScanHomeView`.

```swift
// App/AppRouter.swift  (shape per UX_SPEC §1)
@Observable final class AppRouter {
    var tab: AppTab = .library              // enum AppTab { case library, saved, review, settings }
    var libraryPath = NavigationPath()      // pushes Book / ScanPage values
    var isScanFlowPresented = false
}

// App/RootView.swift
struct RootView: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            NavigationStack(path: $router.libraryPath) {
                LibraryView()
                    .navigationDestination(for: Book.self) { BookDetailView(book: $0) }
                    .navigationDestination(for: ScanPage.self) { ReaderView(page: $0) }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }.tag(AppTab.library)
            // Saved / Review / Settings tabs: UX_SPEC §2 empty/resting states in Phase 2; PHASE3_DESIGN §2–4 fills them in.
        }
    }
}
```

- Phase 2 ships the **four-tab shell**: Saved/Review/Settings show only their UX_SPEC §2 empty states (Saved: "Words you save while reading appear here"; Review: the never-saved cross-promo; Settings: a minimal `Form` hosting the existing `targetLanguage` picker). Rejected hiding tabs until Phase 3: adding tabs later shifts muscle memory, and the empty states teach the save→review loop from day one.
- Paths carry model references, not `PersistentIdentifier` — `@Model` is `Hashable`, the path never outlives the container, and it avoids a fetch per push. Rejected ID-based routes: only needed for state restoration/deep links, out of scope for v1.
- Scan is a **`.sheet`** (UX_SPEC §1), not a route or tab — it's a flow that ends by *pushing* the Reader, not a place you navigate back into mid-OCR. Reader is pushed, never modal, and hides the tab bar (`.toolbar(.hidden, for: .tabBar)`) to maximize card space.

## 3. Library screen (`Features/Library/LibraryView.swift`)

```
┌─────────────────────────────┐
│ Library      [📷 Scan] [+]  │  📷 → scan flow (§5) · + → new book
├─────────────────────────────┤
│ ┌──┐ Le Petit Prince        │
│ │📖│ French · 12 pages      │ →  Book detail
│ └──┘                        │
└─────────────────────────────┘
```

- `@Query(sort: \Book.createdAt, order: .reverse) private var books: [Book]`.
- Row: cover thumbnail (or `book.pages` first page's image, or SF Symbol placeholder), title, language name + page count.
- **Create**: `[+]` → sheet `BookFormView(mode: .create)` — title field, language `Picker` (same list as old ScanHomeView, default `@AppStorage("targetLanguage")`), optional cover via `PhotosPicker`. Save inserts `Book` into `modelContext`.
- **Rename / cover**: swipe action or context menu → same `BookFormView(mode: .edit(Book))`. In edit mode the language `Picker` is **disabled once `book.pages` is non-empty** (caption: "Language is locked after the first page is scanned") — existing sentences were OCR'd in the old language and would instantly be spoken with the new language's voice; re-OCR-on-language-change is not a v1 feature.
- **Delete**: swipe → `confirmationDialog("Delete '\(title)' and its N pages?")` → `modelContext.delete(book)` (cascade removes pages + sentences; `SavedWord`s survive by design).
- Empty state per UX_SPEC §2: `ContentUnavailableView("Scan your first page", systemImage: "book.pages")` + prominent Scan button (launches §5's assign-first flow, which quick-creates the first Book).
- **Plan change (re-scope — applied 2026-07-06):** plan §6 listed "Saved Items screen with notes" under Phase 2; it moves to **Phase 3**, where [PHASE3_DESIGN.md](PHASE3_DESIGN.md) §3 already designs it alongside Review (the two share replay + SRS plumbing, and its row spec needs the Phase 3 `sourceBookTitle` schema addition). PROJECT_PLAN §6 now lists it under Phase 3, and the decision is logged in [DECISIONS.md](DECISIONS.md) (#6). The interim gap stays narrow: notes on already-saved words remain editable through §7's duplicate path, and the Saved/Review *tabs* exist from Phase 2 (§2), showing their empty states rather than dead screens.

Trade-off: `List` vs cover grid — list chosen; page count and language matter more than cover art for a study tool, and rows give free swipe actions.

## 4. Book detail (`Features/Library/BookDetailView.swift`)

```
┌─────────────────────────────┐
│ ← Le Petit Prince    [Edit] │
├─────────────────────────────┤
│ ▶ Resume · Page 3           │  ← only if lastOpenedAt exists
├─────────────────────────────┤
│ ┌──┐ Page 1 · 14 sentences  │
│ │▒▒│ Jul 2   (Edit: ≡ drag) │ →  Reader
│ └──┘                        │
├─────────────────────────────┤
│        [ 📷 Add Page ]      │
└─────────────────────────────┘
```

- Pages sorted by `orderIndex` (sort the relationship array in the view — SwiftData does not guarantee order).
- Row tap → `router.libraryPath.append(page)`; sets `page.lastOpenedAt = .now`.
- **Resume**: header button targeting `pages.max(by: { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) })`. Trade-off vs storing `Book.lastReadPageID`: a per-page timestamp is one optional Date, needs no cleanup on page deletion, and doubles as "recently read" data later.
- **Reorder**: Edit mode + `.onMove` → rewrite `orderIndex = 0..<n` on the moved array. Rejected fractional indices: pages-per-book is tens, full rewrite is trivial and keeps ints.
- **Delete page**: swipe → confirm → `modelContext.delete(page)` (cascades sentences; SavedWords unaffected).
- Thumbnails: `UIImage(data:)?.byPreparingThumbnail(ofSize:)` off-main in `.task`, cached in an `NSCache<NSString, UIImage>` keyed by `persistentModelID` description. Rejected persisting thumbnail Data: duplicates storage for a decode we can cache.
- Empty state: "No pages yet" + Add Page button. `[Edit]` opens `BookFormView(mode: .edit)`.

## 5. Scan flow + persistence (`Features/Scan/ScanFlowView.swift`)

**DECIDED: the ephemeral quick-scan path is retired.** Every successful scan persists. Justification: (a) plan §8 already decided "keep pages forever"; (b) two Reader data paths means every Phase 2/3 feature (stars, save-word, SRS) needs an "unless ephemeral" branch; (c) "I just wanted to try it" is served by quick-create + swipe-to-delete, which costs the user two taps, not the codebase a second mode. `ScanHomeView` is deleted; its language picker moves into `BookFormView`.

Entry points: Library toolbar Scan / empty-state CTA (book unknown → assign step) and Book detail "Add Page" (book preassigned → straight to capture). Both present `ScanFlowView(book: Book?)` as a **`.sheet`** (UX_SPEC §1); only `CameraPicker` inside it is a `fullScreenCover`. **On the Library path, assign runs *before* capture** (UX_SPEC §1 rule) — `PageIngestor` needs `book.languageCode` for both OCR and sentence splitting, and assign-first also puts the language in front of the user before the camera ever opens. Rejected OCR-first using the `@AppStorage("targetLanguage")` guess and reconciling at assign time: a wrong-language pass silently corrupts text (exactly open question 1's failure mode) and a corrective re-OCR doubles the wait.

```
Add Page (book known):  capture ▶ confirm/crop ▶ [processing…] ▶ push Reader
Library (book == nil):  assign ▶ capture ▶ confirm/crop ▶ [processing…] ▶ push Reader
┌──────────────────────────────┐
│ Add to book              ✕   │
│ ◉ Le Petit Prince (French)   │
│ ○ Momo (German)              │
│ ○ New book: [___________]    │
│    Language: [French ▾]      │
│         [ Continue ]         │
└──────────────────────────────┘
```

- **Assign**: Continue is disabled until an existing Book is selected or the new-book title is non-empty. A quick-created Book is held as an **un-inserted instance**: it enters the `ModelContext` only inside `ingest`'s success path (relating the saved page pulls it in on save), so cancelling at any later step — including after an OCR failure — leaves **no zero-page ghost book** in Library.
- **Capture** offers both `CameraPicker` **and an Import Photo `PhotosPicker`** (plan §4.2 fallback, carried over from ScanHomeView) — import is the only in-app path when camera permission is denied/restricted, and it is the simulator workflow CLAUDE.md depends on. The first-ever capture shows the one-time dismissible "Flatten the page · fill the frame · avoid glare" overlay (`@AppStorage("hasSeenScanTips")`, UX_SPEC §7 — the plan's #1 OCR risk attacked in UX as well as code).
- Post-capture **crop/rotate ships with this flow** (plan §4.2 + §7 mitigation; ARCHITECTURE gap #6): per UX_SPEC §1 the confirm step *is* crop/rotate — frozen capture, full-frame-default crop rectangle + rotate-90° button; **Use Photo** runs OCR on the cropped original-resolution image, **Retake** returns to the camera. (An earlier draft deferred it to the Phase 3 polish pass; superseded by UX_SPEC's precedence — PHASE3 §7 points back here so the hand-off can't evaporate.)
- **Permission states**, checked via `CameraAuthorizer` (UX_SPEC §7) before presenting `CameraPicker`: `.notDetermined` → pre-permission **priming panel** ("ReadAloud photographs book pages to read them aloud. Photos never leave your device." — **Continue** calls `requestAccess(for: .video)` and only then sets `@AppStorage("hasPrimedCamera")`; **Not now** returns to the capture step with Import Photo still offered, never killing the flow). `.denied/.restricted` → **denied panel** offering "Open Settings" (`UIApplication.openSettingsURLString`) and "Import a photo instead". Never a dead end, never a surprise jump to the near-irreversible system dialog.
- **Processing**: `ProgressView("Reading page…")` over the frozen capture **with a Cancel button** that cancels the ingest `Task` and returns to confirm/crop — the ≤10 s target (plan §9) only holds on iPhone 12+, so slower devices must never face a dead wait with every exit hidden (UX_SPEC §2). OCR error / zero sentences → inline "No text found — flatten the page, add light" + **Retake** / **Import** buttons.
- **Exits**: ✕ at any step before `ingest` returns discards the captured image and any quick-created (un-inserted) Book, then dismisses the sheet — nothing has been persisted or left behind.

Ingestion is one service so Scan stays a dumb flow:

```swift
// Services/PageIngestor.swift
struct PageIngestor {
    var ocr = OCRService(); var splitter = SentenceSplitter()
    /// OCR on the (cropped) ORIGINAL image — resolution helps Vision; store downscaled copy.
    @MainActor
    func ingest(_ image: UIImage, into book: Book, context: ModelContext) async throws -> ScanPage {
        let text = try await ocr.recognizeText(in: image, languageCode: book.languageCode)
        let parts = splitter.split(text, languageCode: book.languageCode)
        guard !parts.isEmpty else { throw IngestError.noTextFound }
        let page = ScanPage(imageData: ImageProcessor.storageJPEG(image), rawText: text,
                            orderIndex: (book.pages.map(\.orderIndex).max() ?? -1) + 1)
        page.sentences = parts.enumerated().map { Sentence(text: $1, orderIndex: $0) }
        context.insert(page)
        book.pages.append(page)   // also pulls a quick-created, un-inserted Book into the context
        try context.save()        // explicit save at the flow boundary — see below
        return page
    }
}
```

**Explicit save decided** (closes a former open question): a freshly scanned page is exactly the data users won't forgive losing, and autosave timing is undocumented — so `ingest` saves before returning. Elsewhere (bookmarks, notes, reorder) autosave is acceptable; a lost Bool toggle is recoverable, a lost scan is not. On success the flow dismisses (`isScanFlowPresented = false`), then appends the Book (if not already on the path) and the ScanPage to `router.libraryPath`, so Back from the Reader lands on Book detail. The first successful scan ever also fires the success haptic and a one-time tip anchored to the Reader's first card: "Tap a sentence to hear it. Long-press for word actions." (UX_SPEC §7).

## 6. ReaderView refactor (`Features/Reader/ReaderView.swift`)

Keep the existing playback/highlight machinery untouched; add a source enum:

```swift
struct ReaderView: View {
    private enum Source { case persisted(ScanPage), ephemeral([String], String) }
    private let source: Source
    init(page: ScanPage) { source = .persisted(page) }                                                    // app path
    init(sentences: [String], languageCode: String) { source = .ephemeral(sentences, languageCode) }     // #Preview / tests only
}
```

- Persisted mode iterates `[Sentence]` sorted by `orderIndex`; `player.load` receives `sentences.map(\.text)` — SpeechPlayer keeps its `[String]` contract and never learns about SwiftData.
- Language source in persisted mode: `page.book?.languageCode ?? @AppStorage("targetLanguage")` — `ScanPage.book` is Optional in the schema, but every route is built from a page listed under a Book, so the fallback is defensive; never force-unwrap. The same resolved code feeds `SaveWordSheet` (§7).
- **UX_SPEC §3's Phase 2 interaction deltas land in this refactor** (UX_SPEC wins on interaction): tapping the *active* card toggles `togglePlayPause()` instead of restarting the sentence; any user drag suspends auto-scroll, and a "Now playing" pill recenters + re-arms it (rule and code sketch live in UX_SPEC §3 — not duplicated here).
- **Bookmark star** (persisted mode only): trailing `☆/★` — a separate 44×44 pt `Button` overlaid trailing-top that swallows its tap so starring never triggers playback (UX_SPEC §3) → `sentence.isBookmarked.toggle()`; on first bookmark set `sentence.srs = SRSState()`. Unbookmarking keeps `srs` (history preserved; Phase 3 review queries filter on `isBookmarked == true` first, then in-memory `srs.dueDate <= now`). Rejected nil-ing srs: destroys learning history for one Bool flip.
- Ephemeral mode hides star + save-word affordances. Rejected splitting into two views: 90% of the body (cards, highlight, playback bar) is shared.

## 7. Save-word UX (`Features/Reader/SaveWordSheet.swift`)

Delivery follows UX_SPEC §3: **long-press a sentence card → `.contextMenu`**, whose **"Save Word…"** item opens the word-chip sheet below. Phase 2 menu items: Save Word…, Copy Sentence, Bookmark/Unbookmark (mirrors the star); Look Up… and Add Note… join the menu in Phase 3 (PHASE3_DESIGN §5). Chips rather than word-level tap targets: SwiftUI `Text` offers no per-word targets, `UITextView` selection bridging is heavy, and per-word gestures would collide with the existing highlight rendering; chips give exact, fat-finger-friendly selection and reuse the tokenizer we already ship. **Plan change (applied 2026-07-06):** this supersedes plan §4.3's "long-press word → Dictionary / Save Word / Translate" — same gesture, card-level target. PROJECT_PLAN §4.3 and the §6 checklist are amended to match, and the decision is logged in [DECISIONS.md](DECISIONS.md) (#5).

```swift
// Services/WordTokenizer.swift
struct WordTokenizer {
    /// NLTokenizer(unit: .word); dedup case-insensitively, preserve first-occurrence order & casing.
    func words(in sentence: String, languageCode: String) -> [String]
}
```

```
┌─────────────────────────────┐
│ Save a word             ✕   │
│ "Il regardait le coucher    │
│  du soleil chaque soir."    │
│ ┌──┐┌─────────┐┌──┐┌───────┐│
│ │Il││regardait││le││coucher││  ← chips, tap to select
│ └──┘└─────────┘└──┘└───────┘│
│ Note (optional) [_________] │
│      [ Save “coucher” ]     │
└─────────────────────────────┘
```

Flow: "Save Word…" → sheet (`presentationDetents([.medium])`) shows the sentence, chips in a wrapping flow layout (small custom `Layout`), optional note field. Selection is **single-select**: tapping a chip selects it (accent fill), tapping a different chip swaps the selection, tapping the selected chip deselects. **Save stays disabled until a chip is selected.** Save creates `SavedWord(word: selected, contextSentence: sentence.text, languageCode: <resolved code from §6>)` with `srs = SRSState()` set immediately (words are always review items), then inserts and dismisses with a confirmation haptic. The duplicate check runs **on every selection change**: fetch `SavedWord` where `languageCode ==` book's, compare `word` case-insensitively in memory (vocab counts are small); on hit the sheet switches to **update mode** — the note field prefills the existing row's `userNote` and the button reads "Update note"; switching to a non-duplicate chip reverts to save mode and clears the note field (a note belongs to its word, not to the sheet). This keeps notes editable before Phase 3's Saved Items screen exists (§3 re-scope). Original casing is stored (German nouns).

Trade-offs: chips vs `.textSelection(.enabled)` — textSelection gives copy only, no selection callback. Chips vs long-press-on-word via `UIViewRepresentable` + `UITextGesture` — rejected: fragile geometry mapping against the existing `AttributedString` highlight rendering. Dictionary/translate actions from the same sheet are Phase 3; the sheet leaves room for an action row.

### Accessibility (plan §9 acceptance: VoiceOver-navigable Reader — model per UX_SPEC §6)

- Each SentenceCard is **one combined element** (`.accessibilityElement(children: .combine)`): label = sentence text, value = "Playing" / "Bookmarked". The star is removed from the VO tree (`.accessibilityHidden(true)`) and replaced by custom actions on the card — **Play/Pause, Bookmark, Save a word** (Look up joins in Phase 3). The context menu remains reachable, but custom actions are the primary VO path; one element per card halves the swipe count through a page.
- Chips are buttons labeled with their word; selection sets the `.isSelected` trait.
- Save confirmation is not haptic-only: post `UIAccessibility.post(notification: .announcement, argument: "Saved \(word)")` and briefly swap the Save button to a checkmark, covering VoiceOver users and devices without haptics.

## 8. Image storage policy

```swift
enum ImageProcessor {
    /// Longest side ≤ 2048 px, JPEG quality 0.7 → typically 250–600 KB per page.
    static func storageJPEG(_ image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.7) -> Data
    /// Covers don't need re-OCR resolution: ≤ 1024 px, quality 0.6.
    static func coverJPEG(_ image: UIImage) -> Data
}
```

- `@Attribute(.externalStorage)` on `ScanPage.imageData` and `Book.coverImageData` — SwiftData spills large blobs to files next to the store, keeping row fetches (page lists!) cheap.
- OCR always runs on the **original** (cropped) capture; only the stored copy is downscaled. 2048 px keeps enough resolution for a future re-OCR ("re-read this page in another language") while cutting a 12 MP capture (~4–7 MB HEIC-equivalent) to well under 1 MB. Rejected storing originals: 100 pages ≈ 0.5 GB and plan §8 says pages are kept forever. Rejected HEIC: JPEG decode is faster for thumbnail scrolling and universally re-exportable for the Phase 4 JSON/export stretch.

## 9. File-level change list

- New: `App/AppRouter.swift`, `App/RootView.swift` (TabView root + Phase 2 placeholder tabs), `Models/Schema.swift`, `Services/PageIngestor.swift`, `Services/WordTokenizer.swift`, `Services/ImageProcessor.swift` (pure logic — no SwiftUI, per the CLAUDE.md library rule), `Features/Library/{LibraryView,BookDetailView,BookFormView}.swift`, `Features/Scan/{ScanFlowView,CropConfirmView,CameraAuthorizer}.swift`, `Features/Reader/SaveWordSheet.swift`.
- Modified: `ReadAloudApp.swift` (container + AppRouter), `Models.swift` (V1 amendments §1), `ReaderView.swift` (§6).
- Deleted: `ScanHomeView.swift` (including the `[String]: @retroactive Identifiable` extension); its `PhotosPicker` import path moves into `ScanFlowView` (§5). `CameraPicker` survives unchanged inside `ScanFlowView`.
- `project.yml`: no target changes required for the above; the `ReadAloudTests` unit target (ARCHITECTURE.md §5) rides along in this phase.

## Open questions

1. Should quick-created books during scan-assign default their language to the last-used `@AppStorage` value, or force an explicit pick every time (mis-set language silently ruins OCR + TTS)? Assign-before-capture (§5) at least guarantees the user sees the language before the camera opens.
2. Does `NLTokenizer(unit: .word)` chip UX hold up for `ja-JP`/`zh-Hans` (no spaces, fine-grained tokens)? Needs a device check with real text before Phase 3 builds review on top of SavedWord.
3. When the same physical page is scanned twice, do we want any dedup/merge affordance, or is manual page deletion enough for v1?

## Carry-forward tasks

- [ ] Wire `ModelContainer` with `ReadAloudSchemaV1` + migration plan — *acceptance: app cold-starts with a persisted store; a created Book survives relaunch.*
- [ ] Amend Models.swift: `.externalStorage` attributes + `ScanPage.lastOpenedAt` — *acceptance: schema builds; page image blobs land outside the main store file.*
- [ ] TabView root + `AppRouter` per UX_SPEC §1, with placeholder empty states for Saved/Review/Settings; delete ScanHomeView and the `[String]` Identifiable hack — *acceptance: four tabs render; grep for `@retroactive Identifiable` returns nothing; Library is the first tab.*
- [ ] LibraryView with create/rename/delete book + cover — *acceptance: full book CRUD works and survives relaunch; delete confirms with page count; language picker is disabled when editing a book that has pages.*
- [ ] BookDetailView with thumbnails, reorder, delete, resume — *acceptance: reordered pages keep order after relaunch; Resume opens the most recently opened page.*
- [ ] ScanFlowView as a `.sheet` (assign-first on the Library path, camera + Import Photo, confirm/crop step, cancellable OCR) + PageIngestor with explicit save — *acceptance: scan from Library and from Book detail both end in a persisted Reader; crop/rotate is reachable on confirm; Cancel during OCR returns to confirm; the import path completes the flow on the simulator; cancelling after a quick-create leaves no empty Book in Library.*
- [ ] First-run camera UX per UX_SPEC §7: `CameraAuthorizer`, priming panel on `.notDetermined`, denied panel (Open Settings / Import-instead), `hasSeenScanTips` capture overlay, first-scan Reader tip — *acceptance: a fresh install shows the priming panel before the system dialog; with camera denied the user still completes a scan via Import.*
- [ ] ReaderView persisted/ephemeral dual init — *acceptance: #Preview still renders with string arrays; app path renders from a ScanPage.*
- [ ] Reader interaction deltas per UX_SPEC §3: active-card tap = pause/resume, 44 pt star target, scroll-suspension + "Now playing" pill — *acceptance: starring never starts playback; dragging during playback never fights auto-scroll; the pill recenters and re-arms.*
- [ ] Bookmark star persistence — *acceptance: starred sentence shows ★ after relaunch and has non-nil srs.*
- [ ] SaveWordSheet behind the card `.contextMenu` ("Save Word…") with NLTokenizer word chips + duplicate guard — *acceptance: saved word persists with context snapshot; re-saving the same word lands in update-mode and edits the existing note; Save is disabled with no chip selected.*
- [ ] Reader accessibility pass (§7): combined card element with custom actions, star hidden from VO, chip traits, save announcement — *acceptance: with VoiceOver on, a user can play a sentence, toggle its bookmark, and save a word without leaving the card, and hears "Saved" announced.*
- [ ] ImageProcessor downscale/recompress (2048 px / 0.7) — *acceptance: a 12 MP capture stores < 1 MB; OCR still runs on the original.*
- [ ] Add `ReadAloudTests` target in project.yml; first tests: SRSState.review, SentenceSplitter, WordTokenizer — *acceptance: `xcodegen generate` then test action passes in CI-less local run.*
- [x] **`docs/DECISIONS.md` created (2026-07-06)** with the Phase 2 decisions logged (quick-scan retired; context-menu + chip sheet supersedes plan §4.3; Saved Items re-scoped to Phase 3; explicit save at scan boundary; UX_SPEC precedence reconciliation) and the matching PROJECT_PLAN §4.3/§6 edits applied — *acceptance met: the decision log lists them with rationale; PROJECT_PLAN no longer contradicts this document.*
- [ ] (Tech debt, unblocks Phase 3) In-memory due-item query helper honoring the SRS-blob predicate limitation — *acceptance: helper returns bookmarked sentences + saved words with `srs.dueDate <= now` without any #Predicate on srs.*
