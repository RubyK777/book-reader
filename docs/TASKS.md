# ReadAloud — Task Backlog

*Source of truth for "what do I build next". This file indexes the carry-forward sections of the
design docs — full task wording and acceptance criteria live there; tick items in both places as
they land. Order within a phase is roughly dependency order.*

## Phase 1 — leftovers

- [ ] OCR spike on 5 real book-page fixtures (`Tools/OCRSpike`, `Fixtures/` is empty) — PROJECT_PLAN §6/§7 risk #1.

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

## Phase 3 — Review + polish

From [PHASE3_DESIGN.md](PHASE3_DESIGN.md) § Carry-forward:
- [ ] SRSEngine · `ReadAloudSchemaV2` (`SavedWord.sourceBookTitle`)
- [ ] ReviewView + tab badge (due-count holder) · ReviewSessionView/Model · session summary
- [ ] SavedItemsView + detail · SettingsView + VoiceStore · SpeechPlayer voice/rate resolution
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
