# Scan / OCR pipeline design

*How a photograph of a book page becomes clean, ordered, sentence-splittable text. Covers capture UX (document camera), Vision request tuning, line assembly (columns / hyphenation / paragraphs), the confidence-based quality gate, and the measurable OCR-spike protocol behind the "≥ 95% word accuracy" criterion in [PROJECT_PLAN.md](../PROJECT_PLAN.md) §9.*

**Reads with:** [PROJECT_PLAN.md](../PROJECT_PLAN.md) §4.2/§7/§9 · [ARCHITECTURE.md](ARCHITECTURE.md) §2 (OCRService contract, gaps 5–7) · [PHASE2_DESIGN.md](PHASE2_DESIGN.md) §5/§8 · [UX_SPEC.md](UX_SPEC.md) §1–2/§5–§7 · `Tools/OCRSpike/main.swift` · `Fixtures/README.md`

## 1. Capture UX — DECIDE: VisionKit document camera

**Replace `UIImagePickerController` with `VNDocumentCameraViewController`** (VisionKit, iOS 13+, well within our 17.4 floor).

| | UIImagePickerController (current) | VNDocumentCameraViewController (chosen) |
|---|---|---|
| Edge detection / perspective correction | none — raw photo, curved-page risk §7 | automatic, with user-adjustable corners |
| Crop / rotate | we'd build it (tech-debt #6) | built into its review step |
| Multi-page | one photo per presentation | native (`VNDocumentCameraScan.pageCount`) |
| Output | `UIImage` (original) | deskewed, flattened `UIImage` per page |

Trade-off: we give up camera-UI customization (it's a system sheet) and it is device-only — but flattened, deskewed input attacks the plan's #1 risk directly, and its review step **closes tech-debt item #6 (post-capture crop/rotate) for the camera path with zero custom UI**. Rejected: custom AVFoundation capture + our own crop tool — weeks of work to rebuild what VisionKit ships.

**Precedence & docs to amend.** [UX_SPEC.md](UX_SPEC.md)'s precedence note covers only the phase docs, so the ruling between UX_SPEC and this doc is made here; log it in DECISIONS.md (carry-forward). For the **camera path only**, this section supersedes:

- **UX_SPEC §1's "capture (CameraPicker) ▸ confirm/crop" steps** — the document camera's corner-adjust review replaces the custom draggable crop overlay and rotate-90° button. Amend: UX_SPEC nav map, §2 Scan-flow row, and its ScanFlowView carry-forward task.
- **PHASE2_DESIGN §5/§9's "CameraPicker survives unchanged inside ScanFlowView"**, and its "processing is not cancellable" rule — both were scoped to single-page capture; multi-page processing must be cancelable (see States below).

Explicitly **not** superseded: UX_SPEC §7's camera-priming panel survives unchanged — it is shown, and `AVCaptureDevice.requestAccess(for: .video)` resolved, *before* the document camera is presented, gated on `@AppStorage("hasPrimedCamera")` exactly as specced (the doc camera would otherwise trigger the system dialog itself, which is what priming exists to prevent). The import path (PhotosPicker → same pipeline) is also untouched.

```swift
/// Features/Scan/DocumentCameraView.swift — replaces CameraPicker
struct DocumentCameraView: UIViewControllerRepresentable {
    let onScan: ([UIImage]) -> Void      // one image per captured page, already deskewed
    // Coordinator: VNDocumentCameraViewControllerDelegate
    //   didFinishWith scan: (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
    //   didCancel / didFailWithError → dismiss (+ error banner on failure)
}
```

- Guard with `VNDocumentCameraViewController.isSupported`; when false (Simulator, some iPads) hide the Scan button and lead with **Import Photo** (`PhotosPicker` stays as the second path).
- **Multi-page (Phase 1):** OCR pages sequentially in capture order, then join the pages' assembled texts *before* sentence splitting: if a page's text ends without terminal punctuation (book pages almost always break mid-sentence), join to the next page's text with a single space; otherwise with `"\n\n"`. One split over the joined text keeps cross-page sentences whole instead of producing two garbage fragment cards per page boundary. Phase 2's model (each image its own `ScanPage`, `orderIndex` = capture order, `Sentence` rows belonging to one page) re-introduces the boundary split — accepted for v1 and logged as open question 5.
- **Phase 2 integration:** [PHASE2_DESIGN.md](PHASE2_DESIGN.md) §5 replaces `ScanHomeView` with a modal `ScanFlowView`; when that lands, `DocumentCameraView` becomes the flow's capture step and pages persist only *after* the quality gate — full sequencing specced at the end of §4 (PHASE2 §5 to be amended). Until then it plugs into `ScanHomeView` (see carry-forward).
- **Crop story for imports:** photo-library imports get no crop step in v1; the quality gate (§4) catches bad imports and suggests retaking with the document camera. A dedicated import-crop UI is a Phase 3 carry-forward, not v1. Trade-off: one uncropped path vs building crop UI now — the camera path is the primary flow and imports are a fallback.

```
ScanHomeView (updated §4.2)                 Quality gate sheet (§4)
┌─────────────────────────────┐            ┌─────────────────────────────┐
│        📖 ReadAloud         │            │  ⚠️ This scan looks blurry  │
│  Photograph a book page…    │            │                             │
│                             │            │  Recognized 31 lines, but   │
│   Language: French ▾        │            │  confidence is low. Words   │
│                             │            │  may be wrong.              │
│  [ 📷 Scan Pages          ] │──capture──▶│  ┌───────────────────────┐  │
│  [ 🖼 Import Photo        ] │  (system   │  │ preview of worst lines│  │
│                             │   doc-cam  │  └───────────────────────┘  │
│  (processing: spinner +     │   UI with  │  [ Retake ]  [ Use anyway ] │
│   "Reading page 2 of 3…")   │   crop)    └─────────────────────────────┘
└─────────────────────────────┘
```

**States:** *loading* — per-page progress text ("Reading page 2 of 3…") plus a **Cancel** button, other buttons hidden. Cancel with pages still pending asks first — `confirmationDialog("Stop reading? 8 remaining pages will be discarded.")` — because the discarded cost is physical re-photographing effort; confirming lets the in-flight page finish, runs the §4 gate over the pages done so far, then opens the Reader with them (or restores the entry buttons if none finished). **This is the one Cancel behavior**; it supersedes UX_SPEC §2's "cancels the Vision task, returns to confirm/crop" (no confirm/crop step exists on this path — see precedence above) and PHASE2_DESIGN §5's "not cancellable" (scoped to one page, where it remains true: single-page processing shows no Cancel). **Plan change:** PROJECT_PLAN §9's "scan → listenable in ≤ 10 s" was written when a scan was one photo; it now reads **per page** — a 10-page capture legitimately takes longer, which is exactly why loading must be cancelable. PROJECT_PLAN §9 is updated to "≤ 10 s per page" and the change logged in DECISIONS.md (carry-forward); *empty* — zero sentences across the whole batch → inline "No text found — try a flatter page with more light" (existing copy); a single empty page *inside* a batch is not this state — it surfaces in the §4 sheet; *error* — Vision throw → inline message + buttons restored; *permission-denied* — the UX_SPEC §7 priming panel runs before the doc camera is presented (see precedence above); if `AVCaptureDevice.authorizationStatus(for: .video) == .denied` show "Camera access is off — enable it in Settings" with a `UIApplication.openSettingsURLString` link instead of presenting the camera.

## 2. OCRService v2 — structured result + request tuning

`recognizeText` now returns structure, not a bare `String`, so the quality gate and persistence can see confidence:

```swift
struct OCRResult {
    var text: String               // paragraph-aware assembly (§3)
    var meanConfidence: Double     // char-count-weighted mean of top-candidate confidences
    var lowConfidenceLineRatio: Double  // lines with confidence < 0.5 / total lines
    var lineCount: Int             // recognized lines — the sheet's "Recognized 31 lines" (§4)
    var worstLines: [String]       // ≤ 3 lowest-confidence line strings — the sheet's preview (§4)
    var columnCount: Int           // 1 or 2 (§3.1)
}

struct OCRService {
    func recognizeText(in image: UIImage,
                       languageCode: String,
                       customWords: [String] = []) async throws -> OCRResult
}
```

Request configuration (each line = a decision):

- `recognitionLevel = .accurate` — unchanged; §9 allows 10 s per page and `.accurate` is *expected* to land around 1–2 s/page — a number to be verified by the spike once `Fixtures/` is populated (§6), not a measurement we have today.
- **`revision = VNRecognizeTextRequestRevision3` pinned explicitly.** Trade-off: pinning will keep the spike's numbers (measured on macOS) comparable to the app across OS updates; floating `.currentRevision` gets silent accuracy changes that invalidate the calibrated gate threshold. Re-evaluate the pin once per major OS.
- `recognitionLanguages = [languageCode]`, full BCP-47 passed through — Vision accepts it (trim-at-boundary rule applies to NL, not Vision).
- **`automaticallyDetectsLanguage = false`** (default, keep it). We *know* the language from Book/`@AppStorage`; auto-detect trades a known prior for guessing and degrades correction on short/noisy lines. Rejected: enabling it as a "wrong picker" safety net — instead, when `meanConfidence < QualityGate.languageHintThreshold` (placeholder **0.5**; calibrate in the spike by running fixture 1 through a deliberately wrong language) the retake sheet adds the wrong-language hint and its **Change Language & Rescan** action specced in §4.
- **`minimumTextHeight = 0.012`.** Full-page photos put body text at ≈ 0.02 of image height; 0.012 keeps body text and footnotes but drops speckle and dust. Trade-off: raising it (e.g. 0.03) is faster but silently eats small print — exactly the fixture-5 case.
- **`customWords`** — Phase 2: feed the book's `SavedWord.word` values (cap 200, same language) plus tokenized book title; novels repeat character names Vision's lexicon lacks. Requires `usesLanguageCorrection = true` (already on). Phase 1 passes `[]`.
- Off-main execution stays as-is (`Task.detached`, user-initiated).

## 3. Line assembly

Assembly works on `[LineObservation]` (`string`, `confidence`, `boundingBox` in Vision's bottom-left-origin normalized space). Besides the joined text, assembly emits `lineCount` and the ≤ 3 lowest-confidence line strings as `worstLines` — per-line data the §4 sheet needs that would otherwise be discarded here.

### 3.1 Multi-column detection (trigger heuristic + fallback)

1. Compute each observation's `midX`. Sort ascending and find the **largest gap** between consecutive `midX` values.
2. **Trigger:** treat the page as two-column iff (a) the gap ≥ 0.15 normalized width, (b) each side of the gap holds ≥ 25% of observations, and (c) the two clusters' `boundingBox` x-ranges do not overlap by more than 0.05. All three must hold.
3. When triggered: sort each cluster by `midY` descending, emit left cluster fully, then right (`columnCount = 2`, a paragraph break between columns).
4. **Fallback:** any condition fails → current single-column behavior (sort all by `midY` descending). Ambiguity resolves toward the existing behavior, never toward reordering text speculatively.

Trade-off: 1-D largest-gap split vs k-means/DBSCAN clustering — the heuristic is ~15 lines, deterministic, and testable; real k-means adds tuning surface for a "Low–Med" risk (§7). ≥3-column layouts (newspapers) are out of scope; the fallback merely interleaves them, same as today.

### 3.2 Hyphenation repair at line ends

When joining consecutive lines *within a paragraph*: if a line ends in `-` (or `‐` U+2010) **and** the next line starts with a lowercase letter → drop the hyphen and join with no space (`beau-` + `coup` → `beaucoup`). If the next line starts uppercase, keep the hyphen and join with no space (likely a split compound proper noun, `Saint-` + `Exupéry`). Otherwise join with a single space.

Trade-off: this coarse rule vs validating the joined word with `UITextChecker` (keep the hyphen if the joined form isn't in the lexicon, preserving genuine compounds like *porte-monnaie* split at the hyphen). Rejected for v1: the checker's per-language coverage is uneven and both errors read fine aloud via TTS; revisit if spike WER shows hyphenation as a top error class.

### 3.3 Paragraph vs line joining — and why sentence splitting cares

Joining every line with a single space (current behavior) makes headings, captions, and page headers glue onto the first body sentence — NLTokenizer then produces one garbage mega-sentence per page top. Instead:

- Compute the median vertical gap between consecutive lines' `midY` (per column).
- Gap > 1.6 × median, or a column switch → **paragraph break**: join with `"\n\n"`.
- Otherwise → same paragraph: join with `" "` (after §3.2 hyphen handling).

`NLTokenizer(.sentence)` treats `"\n\n"` as a hard boundary, so a chapter heading becomes its own one-line sentence card instead of contaminating the first sentence — acceptable UX (tap it, hear the heading). Trade-off: indentation-based paragraph detection was rejected — first-line indents vary by typography and perspective correction skews x more than y; vertical-gap is robust after deskewing. `ScanPage.rawText` stores this paragraph-joined text so re-splitting after future splitter improvements needs no re-OCR.

## 4. Quality gate — "retake the photo"

Vision's `VNRecognizedText.confidence` is coarse in practice (clusters near 0.3 / 0.5 / 1.0), so the gate uses two signals from `OCRResult`:

```swift
enum ScanQuality { case good, poor(OCRResult) }   // .poor carries everything the sheet renders
func assess(_ r: OCRResult) -> ScanQuality {
    (r.meanConfidence < QualityGate.meanThreshold
        || r.lowConfidenceLineRatio > QualityGate.lowLineRatioThreshold) ? .poor(r) : .good
}
```

- `meanConfidence` is **character-count-weighted** so one garbled speck line can't sink a clean page.
- **The sheet renders only `OCRResult` fields**: title copy uses `lineCount` ("Recognized 31 lines, but confidence is low"), the preview box shows `worstLines` (≤ 3 lowest-confidence line strings, collected during assembly §3). Never a hard block: **Retake** or **Use anyway** (proceed to Reader). Blocking was rejected: confidence is a proxy, and a determined user with a weird font should still get audio.
- **Wrong-language hint — with a real exit.** When `meanConfidence < QualityGate.languageHintThreshold` (placeholder **0.5**, see §2) the sheet adds the line "Wrong language? This scan was read as *French*." plus a third button **Change Language & Rescan**: an inline picker (same list as the scan screen), then `recognizeText` re-runs on the **retained page images** with the new code — the photos are already in hand; re-photographing identical pages just to change a parameter would be the worst remedy — and the batch is re-assessed once. In Phase 1 the new pick also writes `@AppStorage("targetLanguage")`. **Phase 2 drops the button**: language belongs to the Book and is locked once pages exist (PHASE2_DESIGN §3), so the copy becomes "Scanning into the wrong book? Cancel and add this page to a book in the right language" — safe because nothing has been persisted at gate time (see Phase 2 sequencing below).
- **Retake is entry-path-specific.** Camera path: Retake re-presents the document camera. Import path: the button reads **"Choose Another Photo"** and re-presents `PhotosPicker`; where `isSupported` is true the body copy may additionally suggest the document camera, but on unsupported devices (Simulator, some iPads — §1) the copy never mentions the camera.
- **Multi-page reconciliation — one sheet per batch, after all pages OCR.** Assess per page; a single sheet lists every flagged page as a row: **thumbnail** (the captured `UIImage` is already in hand — with a physical book the user cannot otherwise know which page to re-shoot), "Page 2 · 31 lines, low confidence", and that page's `worstLines` preview. The §1 mock is the one-flagged-page case; its title copy uses that page's `lineCount`. Buttons: **Retake 2 Pages** and **Use anyway** (accepts everything). Retake re-presents the document camera; newly captured pages **replace the flagged pages in flagged order**, and any extras append at the end. **Fewer new pages than flagged** → the unreplaced flagged pages keep their original captures (implicit Use-anyway). **Canceling the doc camera mid-retake** → back to the sheet, unchanged. The gate re-assesses only the new pages, with a **one-retake soft limit per batch**: if a retaken page is still poor, the sheet returns with **Use anyway** as the highlighted default — no infinite retake loop.
- **Empty pages are surfaced, never silently dropped.** `OCRResult` with zero observations is *defined* as `meanConfidence = 0`, `lowConfidenceLineRatio = 1`, `lineCount = 0`, `worstLines = []` (no 0/0 NaN), so `assess` always returns `.poor`. Its sheet row reads "Page 2 · no text found" (thumbnail, no preview) and offers Retake or **Remove Page** — no Use-anyway for it; there is nothing to keep. A batch whose *every* page is empty falls through to the §1 *empty* state instead of the sheet.
- **Accessibility & haptics** (amends UX_SPEC §5/§6, which predate this sheet — carry-forward): presenting the sheet fires `Haptics.failure()` (extending that row's "OCR found no text / failed" mapping); the `worstLines` preview gets a container `accessibilityLabel` ("Preview of 3 low-confidence lines") so VoiceOver never reads garbled OCR strings verbatim; after the soft limit, the highlighted Use-anyway default is announced ("Retake didn't improve quality"), not conveyed by tint alone. UX_SPEC §6's "Scan complete, N sentences" announcement posts only after a good result or Use anyway — never alongside the sheet.
- **0.85 / 0.25 / 0.5 are placeholders** calibrated by the spike: for every fixture record `(meanConfidence, lowConfLineRatio, WER)` and set thresholds at the boundary where WER crosses 5% (the §9 line). The constants live in one `enum QualityGate` (`meanThreshold`, `lowLineRatioThreshold`, `languageHintThreshold`) for easy retuning.

**Phase 2 sequencing** (amends PHASE2_DESIGN §5, whose flow diagram has no gate step): capture N images → OCR + assess all **in memory** (nothing persisted, no `IngestError` surfaced) → gate sheet if any page is poor/empty → only accepted / Use-anyway pages are ingested, in capture order, via a new overload `PageIngestor.ingest(_ image: UIImage, result: OCRResult, into: Book, context:)` that takes the already-computed `OCRResult` so Vision never re-runs after the gate, with one `context.save()` after the batch (the explicit-save-at-flow-boundary rule, applied once per batch instead of per page) → dismiss, then push the Reader at the **first newly ingested page**. Because nothing persists before the gate resolves, "Use anyway" *is* what persists a poor page, Retake never deletes or re-orders persisted rows (no orphaned `orderIndex`), and pages the user removes are simply never ingested — `IngestError.noTextFound` becomes unreachable from this flow.

## 5. Persistence notes (SwiftData, Phase 2)

Models are not yet wired (no `.modelContainer`), so these are additive field choices, not migrations:

- `ScanPage.imageData` gets **`@Attribute(.externalStorage)`** (already decided, PHASE2_DESIGN §1/§8) and stores **`ImageProcessor.storageJPEG(deskewedImage)`** — this doc *defers to PHASE2 §8's policy* (longest side ≤ 2048 px, JPEG 0.7, typically 250–600 KB) rather than restating its own numbers; the delta here is only *which* image feeds it: the **deskewed doc-camera output**, since the raw frame has no post-doc-camera value. OCR runs on the full-resolution deskewed image; only the stored copy is downscaled. Trade-off: keeping full-resolution originals would allow re-cropping later; rejected — the doc camera already produced the corrected image, and 100 unscaled pages ≈ 0.5 GB kept forever (plan §8, PHASE2 §8).
- Add `ScanPage.ocrMeanConfidence: Double` — lets Library badge low-quality pages and lets a future "re-scan this page" prompt find candidates without re-running Vision. Cheap now, painful to backfill later. Joins PHASE2_DESIGN §1's list of model edits folded into V1 (doc to amend, carry-forward).
- `Sentence.text` stores post-assembly, post-hyphen-repair text — SRS/bookmarks must never see raw OCR artifacts.

## 6. OCR spike protocol — making "≥ 95% word accuracy" measurable

**Fixtures/ contents** (currently empty — blocking the plan's #1 risk mitigation):

```
Fixtures/
  01-flat-good-light.jpg        + 01-flat-good-light.ref.txt
  02-curved-spine.jpg           + 02-curved-spine.ref.txt
  03-glossy-glare.jpg           + 03-glossy-glare.ref.txt
  04-dim-warm-light.jpg         + 04-dim-warm-light.ref.txt
  05-small-print-dialogue.jpg   + 05-small-print-dialogue.ref.txt
  06-two-column-layout.jpg      + 06-two-column-layout.ref.txt
```

Each `.ref.txt` is the page's text **hand-typed from the physical book** (ground truth, not corrected OCR output — correcting OCR output biases toward its own errors). One paragraph per line; typography preserved except line-break hyphenation, which the typist joins.

**Word accuracy = 1 − WER**, computed by `Tools/OCRSpike` — extend `main.swift` (which today only prints assembled sentences and an unweighted mean confidence) to auto-pair `X.jpg` with `X.ref.txt` when present and to implement `normalize`/`wer`:

```swift
func normalize(_ s: String) -> [String] {
    // lowercase → strip punctuation except intra-word ' - ’ → collapse whitespace → split
}
func wer(reference: [String], hypothesis: [String]) -> Double {
    // word-level Levenshtein: (substitutions + deletions + insertions) / reference.count
}
```

Normalization is symmetric (applied to both sides) so punctuation and casing — which TTS tolerates — don't count as errors, but wrong/missing/extra *words* do. Trade-off: plain WER vs order-independent bag-of-words accuracy — WER is chosen because column interleaving and line misordering *must* count as errors (they wreck sentence audio even when every word is individually right). Spike output per fixture: `WER, accuracy %, meanConfidence, lowConfLineRatio, seconds`, plus a repo-tracked summary table appended to `Fixtures/README.md`. **Pass:** accuracy ≥ 95% on fixture 1 (and ideally 4); fixtures 2/3/5 are diagnostic, feeding the §4 thresholds; fixture 6 exercises §3.1 column ordering (WER counts interleaving as errors, so it doubles as the clustering acceptance check). The spike CLI must share assembly logic with the app conceptually (port §3 into `main.swift` when it lands in `OCRService`) or its numbers stop describing the app.

## 7. Phase 4 stretch — Live Text via DataScannerViewController

Instant tap-to-hear without capturing: `DataScannerViewController(recognizedDataTypes: [.text(languages: [languageCode])], qualityLevel: .accurate, isHighlightingEnabled: true)` wrapped in `LiveScanView: UIViewControllerRepresentable`. `didTapOn item:` → `case .text(let t)`: run `SentenceSplitter` on `t.transcript`, hand to a transient `SpeechPlayer` — no persistence, no ScanPage; it's a "listen right now" mode, not a scanning mode. Requires `DataScannerViewController.isSupported && .isAvailable` (A12+, camera permission) — the mode's entry button hides when unsupported. Deliberately *not* the primary flow: Live Text gives no stable page artifact to bookmark/review against, which is the app's whole learning loop. Design details deferred to a Phase 4 doc; nothing in §§1–6 blocks or depends on it.

## Open questions

1. Does `VNDocumentCameraViewController`'s flash/auto-shutter behavior fight glossy pages (fixture 3), and do we need retake guidance copy specific to glare?
2. Which real languages do the first fixtures use — French only, or one CJK set (zh-Hans) to validate that word-based WER needs a character-level variant for unspaced scripts?
3. `customWords` cap and refresh point (on each scan? on Book open?) once SavedWord is wired — measure whether it moves WER at all before keeping it.
4. Should "Use anyway" pages be visually flagged in the Phase 2 Library (using `ocrMeanConfidence`) so users know which pages to re-scan?
5. Phase 2 splits sentences per `ScanPage`, so a sentence continuing across a page boundary becomes two fragment cards again (§1 fixes this only for the Phase 1 in-memory session). Merge trailing unpunctuated fragments with the next page at Reader load time, or accept the fragments for v1?

## Carry-forward tasks

- [ ] Replace `CameraPicker` with `DocumentCameraView` (VNDocumentCameraViewController) in the scan entry view — `ScanHomeView` today; once Phase 2's `ScanFlowView` supersedes it ([PHASE2_DESIGN.md](PHASE2_DESIGN.md) §5), `DocumentCameraView` becomes that flow's capture step with gate-before-ingest sequencing per §4 — incl. `isSupported` fallback, UX_SPEC §7 priming before presentation, and permission-denied state — *Accept: on device, capturing 2 pages yields one Reader session with both pages' sentences in order (a sentence spanning the page break stays one card); Simulator shows Import-only UI.*
- [ ] Rework `OCRService` to return `OCRResult` with pinned Revision3, `minimumTextHeight = 0.012`, and explicit `automaticallyDetectsLanguage = false` — *Accept: existing callers compile against `.text`; on a real photo the result carries nonzero meanConfidence, correct lineCount, and ≤ 3 worstLines.*
- [ ] Implement column clustering (largest-midX-gap heuristic + single-column fallback) — *Accept: fixture 6 (two-column) reads left column fully before right; single-column fixtures yield the identical line **sequence** as today's midY sort (fallback engages, no reordering) — compare ordered line arrays, not joined strings, since §3.2/§3.3 change joining for every page.*
- [ ] Implement hyphenation repair + vertical-gap paragraph joining in line assembly — *Accept: unit test joins `beau-`/`coup` → `beaucoup`, keeps `Saint-`/`Exupéry` hyphen, and a heading becomes its own sentence card.*
- [ ] Add quality gate (`assess` + retake sheet) to the scan flow — *Accept: a deliberately blurred photo triggers the sheet showing line count + worst-lines preview; Retake and Use-anyway work on both camera and import paths; in a 3-page batch with one blurred page the sheet shows that page's row with a thumbnail; an all-blank page shows "no text found" with Remove; a clean photo never shows it.*
- [ ] Populate `Fixtures/` with 6 photos + hand-typed `.ref.txt` files per §6 — *Accept: all six pairs exist and `swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg` consumes them.*
- [ ] Extend `Tools/OCRSpike/main.swift` with ref-file auto-pairing, normalize/WER, and the summary table, then calibrate the §4 thresholds (incl. `languageHintThreshold` via a wrong-language run on fixture 1) — *Accept: spike prints per-fixture accuracy %; fixture 1 ≥ 95%; chosen thresholds recorded in `QualityGate` and DECISIONS.md.*
- [ ] Phase 2: `@Attribute(.externalStorage)` on `ScanPage.imageData` + new `ocrMeanConfidence` field, stored copy via `ImageProcessor.storageJPEG` per PHASE2_DESIGN §8 — *Accept: matches PHASE2 §8's criterion — a 12 MP capture stores < 1 MB, outside the main store file — and persists its confidence.*
- [ ] Amend UX_SPEC.md (nav map + §2 Scan-flow row: document camera replaces capture ▸ confirm/crop on the camera path; §5/§6: gate-sheet haptic + preview label + announcement timing; §7 note that priming precedes the doc camera) and PHASE2_DESIGN.md (§5/§9: `DocumentCameraView` replaces CameraPicker, multi-page processing cancelable, gate-before-ingest sequencing + `ingest(_:result:into:context:)` overload; §1 V1 field list gains `ocrMeanConfidence`) — *Accept: neither doc contradicts §1/§4/§5 of this one.*
- [ ] Log in DECISIONS.md: the doc-camera precedence ruling over UX_SPEC §1, the single Cancel behavior (§1 States), and the "≤ 10 s **per page**" plan change; update PROJECT_PLAN §9 to match — *Accept: DECISIONS.md lists all three with rationale; PROJECT_PLAN §9 reads "per page".*
- [ ] Phase 3: minimal crop/rotate step for the photo-import path — *Accept: an imported two-page spread can be cropped to one page before OCR.*
- [ ] Phase 4: `LiveScanView` (DataScannerViewController) tap-to-hear mode per §7 — *Accept: tapping a paragraph on a live page speaks its first sentence within 1 s; entry point hidden on unsupported devices.*
