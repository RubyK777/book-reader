# ReadAloud — Testing & Quality Strategy

*Purpose: define the test targets, the prioritized test inventory (with exact expected values for the SM-2 math), the seams we add to make `SpeechPlayer` and `SRSState` deterministic, the manual release checklist, and how we verify the PROJECT_PLAN §9 performance bar (scan → listenable ≤ 10 s). The repo currently has **zero** test targets (ARCHITECTURE.md §4 item 2); this doc is the plan to fix that without letting test infrastructure balloon ahead of Phase 2 features.*

**Reads with:** [PROJECT_PLAN.md](../PROJECT_PLAN.md) (§6 phases, §7 risks, §9 acceptance criteria) · [ARCHITECTURE.md](ARCHITECTURE.md) (§2 contracts, §5 testing sketch this doc supersedes)

## 1. Targets in `project.yml`

Add two targets and an explicit scheme (CI needs a shared scheme; Xcode's auto-created ones aren't committed). Exact YAML to append:

```yaml
  ReadAloudTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - ReadAloudTests
    dependencies:
      - target: ReadAloud     # XcodeGen sets TEST_HOST/BUNDLE_LOADER automatically
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES

  ReadAloudUITests:
    type: bundle.ui-testing
    platform: iOS
    sources:
      - ReadAloudUITests
    dependencies:
      - target: ReadAloud
    settings:
      base:
        GENERATE_INFOPLIST_FILE: YES

schemes:
  ReadAloud:
    build:
      targets:
        ReadAloud: all
    test:
      gatherCoverageData: true
      targets:
        - ReadAloudTests
        - ReadAloudUITests
```

Run `xcodegen generate` after editing — never touch the `.xcodeproj`.

- **Framework — DECIDED:** Swift Testing (`@Test` / `#expect`) for unit tests; XCTest for the UI target (XCUITest has no Swift Testing equivalent). *Trade-off:* all-XCTest would be uniform, but Swift Testing's parameterized tests fit the fixture tables below and it's the forward path on Xcode 16+.
- Unit tests are **hosted in the app** (dependency above). *Trade-off:* an unhosted logic-only bundle builds faster, but `SpeechPlayer` touches `AVAudioSession` at init and hosted tests avoid a second target layout.

## 2. Test inventory (priority order)

### 2.1 `SRSStateTests` — SM-2 math (highest logic density, pure)

`SRSState.review(quality:)` calls `.now` internally, which makes `dueDate` assertions racy. First change (carry-forward): add an injectable clock, default preserves the public call:

```swift
mutating func review(quality: Int, on now: Date = .now)
```

*Trade-off:* tolerance-based date assertions (±2 s) would need no code change, but a default-parameter clock is one line and makes tests exact; rejected a full `Clock` protocol as overkill for one call site.

Expected sequences from the **actual implementation** (start: `repetitions 0, easeFactor 2.5, intervalDays 0`; grade buttons map Again/Hard/Good/Easy → 1/3/4/5 per PROJECT_PLAN §4.5). These are characterization values — the interval multiply uses the *pre-update* easeFactor, and EF updates even on failure (a **deviation** from canonical SM-2, which leaves EF unchanged when quality < 3 — tests pin the actual behavior, not the published algorithm):

| Grades  | After review → | repetitions | intervalDays | easeFactor |
|---------|----------------|-------------|--------------|------------|
| 4,4,4   | R1             | 1           | 1            | 2.5        |
|         | R2             | 2           | 6            | 2.5        |
|         | R3             | 3           | 15 (⌊6×2.5⌋) | 2.5        |
| 4,1,4   | R1             | 1           | 1            | 2.5        |
|         | R2 (fail)      | 0           | 1            | 1.96       |
|         | R3             | 1           | 1            | 1.96       |
| 5,5,5   | R1             | 1           | 1            | 2.6        |
|         | R2             | 2           | 6            | 2.7        |
|         | R3             | 3           | 16 (⌊6×2.7⌋) | 2.8        |
| 3,3,3   | R1             | 1           | 1            | 2.36       |
|         | R2             | 2           | 6            | 2.22       |
|         | R3             | 3           | 13 (⌊6×2.22⌋)| 2.08       |
| 1,1,1   | R3             | 0           | 1            | 1.3 (floor)|

Also assert: `dueDate == Calendar.current.date(byAdding: .day, value: intervalDays, to: injectedNow)`; easeFactor compared with `abs(a-b) < 0.0001`; quality 0 and 5 don't trap.

### 2.2 `SentenceSplitterTests` — multilingual fixtures (pure function)

Two tiers, because `NLTokenizer` output can shift across OS releases:

1. **Invariants (hard assertions, every fixture):** no empty/whitespace-only sentences; concatenating the output (whitespace-normalized) equals the whitespace-normalized input (no text lost); deterministic across two calls.
2. **Goldens (exact split):** only for fixtures observed stable; each carries a comment with the OS version it was recorded on.

*Trade-off:* asserting *ideal* linguistics (e.g. "M. Dupont" never splits) would fail on NLTokenizer's actual behavior we don't control; characterization goldens + invariants catch regressions without fighting Apple.

Fixture set (parameterized `@Test(arguments:)`):

| ID | languageCode | Input | Checks |
|---|---|---|---|
| fr-dialogue | fr-FR | `« Bonjour ! » dit-il. Elle sourit.` | quote punctuation stays attached to its sentence |
| fr-abbrev | fr-FR | `M. Dupont arriva. Il était en retard.` | golden: 2 sentences (record actual; flag if "M." splits) |
| en-decimal | en-US | `Pi is 3.14. It is irrational.` | 2 sentences; `3.14` not a boundary |
| en-quotes | en-US | `"Stop!" she said. He ran away.` | 2 sentences |
| ja-cjk | ja-JP | `吾輩は猫である。名前はまだ無い。` | 2 sentences, no-space script |
| zh-cjk | zh-Hans | `他走了。她还在等。` | 2 sentences; also proves the `prefix(2)` trim ("zh") doesn't break `zh-Hans` |
| empty | fr-FR | `""` / `"   \n"` | returns `[]` |

### 2.3 `SpeechPlayerTests` — queue / auto-advance / isJumping

`SpeechPlayer` news up `AVSpeechSynthesizer` internally; tests need to drive delegate callbacks deterministically. Add a seam (carry-forward code change):

```swift
protocol SpeechSynthesizing: AnyObject {
    var delegate: AVSpeechSynthesizerDelegate? { get set }
    var isSpeaking: Bool { get }
    var isPaused: Bool { get }
    func speak(_ utterance: AVSpeechUtterance)
    @discardableResult func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func pauseSpeaking(at boundary: AVSpeechBoundary) -> Bool
    @discardableResult func continueSpeaking() -> Bool
}
extension AVSpeechSynthesizer: SpeechSynthesizing {}   // signatures already match

// SpeechPlayer:
init(synthesizer: SpeechSynthesizing = AVSpeechSynthesizer())
```

`FakeSynthesizer` records `spokenUtterances: [AVSpeechUtterance]`, tracks `isSpeaking`/`isPaused`, and **never fires callbacks implicitly** — the test drives them, so both real-world orderings are expressible:

```swift
final class FakeSynthesizer: SpeechSynthesizing {
    let dummy = AVSpeechSynthesizer()   // inert; only feeds the delegate's first parameter
    func fireWillSpeak(range: NSRange)  // → delegate.willSpeakRangeOfSpeechString
    func fireDidFinish()                // → delegate.didFinish(current utterance)
    func fireDidCancel()                // → delegate.didCancel
}
```

*Trade-off:* a custom delegate protocol would drop the `dummy` synthesizer, but `SpeechPlayer`'s delegate methods never read the synthesizer parameter, and keeping `AVSpeechSynthesizerDelegate` means zero changes to the (already working, do-not-redesign) highlight path.

Cases, in order of value:
1. **Auto-advance:** `play(at: 0)` → `fireDidFinish()` → asserts index 1 spoken, `highlightRange == nil` between utterances.
2. **isJumping suppresses double-advance:** `play(at: 0)`; while `isSpeaking`, `play(at: 5)`; then `fireDidCancel()` (real ordering) — assert index stays 5 and exactly 2 utterances spoken. Repeat with the pathological ordering `fireDidFinish()` for the *old* utterance — assert the guard swallows it.
3. **Repeat mode:** `repeatMode = true`, `fireDidFinish()` → same index re-spoken.
4. **End of queue:** finish last sentence → `isSpeaking == false`, no new utterance.
5. **stop():** clears `currentSentenceIndex`/`highlightRange`, later `fireDidCancel()` doesn't resurrect state.
6. **Rate:** `speedMultiplier = 0.5` → next utterance's `rate == AVSpeechUtteranceDefaultSpeechRate * 0.5`; voice language equals loaded BCP-47 code.
7. **Bounds:** `play(at: 99)` and `next()` at end are no-ops.

### 2.4 `OCRServiceTests` — orientation mapping only

Parameterized test over all 8 `UIImage.Orientation` cases → expected `CGImagePropertyOrientation` (`.up→.up`, … `.rightMirrored→.rightMirrored`). OCR *accuracy* is explicitly **not** unit-tested — that stays with the `Tools/OCRSpike` CLI against real photos in `Fixtures/` (ARCHITECTURE.md §5), because accuracy thresholds on synthetic images give false confidence. Line-ordering (midY-descending sort) gets one test with a tiny rendered two-line image (`UIGraphicsImageRenderer`, "TOP" above "BOTTOM") — skipped via `.enabled(if:)` on CI if Vision proves flaky on virtualized runners.

## 3. UI smoke test: import → reader

One XCUITest proving the core loop end to end in the simulator. **DECIDED: launch-argument fixture hook** rather than automating `PhotosPicker` — the picker is an out-of-process system sheet; automating it (plus `simctl addmedia` seeding) is the flakiest thing in iOS UI testing. This target lands in Phase 2, by which point `ScanHomeView` is deleted (DECISIONS #4, #19), so the hook, `#if DEBUG`-guarded, lives in **`ScanFlowView`** (its Phase-1 home is `ScanHomeView` if you build the smoke test before the refactor):

```swift
.task {
    #if DEBUG
    if let name = ProcessInfo.processInfo.arguments
        .first(where: { $0.hasPrefix("-uiTestFixture=") })?
        .split(separator: "=").last,
       let image = UIImage(named: String(name)) {   // bundled test asset
        await process(image)
    }
    #endif
}
```

Test: launch with `["-uiTestFixture=fixture-fr-page", "-targetLanguage", "fr-FR"]` — the second pair pins the OCR language via the UserDefaults argument domain (which `@AppStorage` reads with zero code change); without it, a stale `targetLanguage` from a previous simulator run could OCR the French fixture under e.g. `ja-JP` and fail the test for an unrelated reason. Wait for the Reader (`app.navigationBars["Reader"]`, timeout 15 s — covers the ≤ 10 s budget plus slack), assert ≥ 1 sentence card exists and the play button is hittable.

Querying requires identifiers `ReaderView` doesn't have yet (cards are plain `Text`s; playback buttons are icon-only). Required app change, tracked in carry-forward: `.accessibilityIdentifier("sentence-card-\(index)")` on each card, `"play-pause"` on the play button — and add `accessibilityLabel`s to all icon-only playback buttons in the same pass, since the §4 VoiceOver check needs those labels anyway. No screen changes otherwise — the flow exercised is exactly PROJECT_PLAN §4.3's existing one.

Fixture image: one well-lit French page photo in a separate `ReadAloud/DebugAssets.xcassets`, stripped from Release via `project.yml` (app-target setting `configs: { Release: { EXCLUDED_SOURCE_FILE_NAMES: [DebugAssets.xcassets] } }`) — asset catalogs have **no** per-configuration folders or membership, so per-config exclusion is the only way to keep the photo out of the App Store binary. The same photo also seeds `Fixtures/` (gap #7).

Error/permission states are covered manually (§4) — camera permission dialogs and airplane mode aren't reliably scriptable; `resetAuthorizationStatus(for: .camera)` exists but the payoff doesn't justify the flake rate for v1.

## 4. Manual release checklist (run per TestFlight/App Store build)

- **Device matrix:** iPhone 12 (the §9 performance baseline, physical), newest iPhone (physical), any iPad (simulator OK — layout only). Oldest supported OS **18.0** on at least one device.
- **Airplane-mode run-through:** enable airplane mode + Wi-Fi off *before launch*; full loop: scan → read → highlight → save word → review. Zero degradation allowed (§9 "all features functional in airplane mode"). **Translation caveat:** the language pack for a pair downloads once online (DECISIONS #23) — pre-download the test pair before going offline, then confirm translations render with the network off.
- **VoiceOver pass (Reader):** every sentence card focusable and read; playback bar buttons labeled (prev/play-pause/next/repeat/speed); tap-to-play works via double-tap; active-card change is announced or discoverable.
- **Voice quality check:** for each of the 9 supported languages: play one sentence with the default **compact** voice, then install the **enhanced** voice (Settings → Accessibility → Spoken Content) and replay. Confirm the app picks up the better voice and word highlighting still tracks (enhanced voices have different timing granularity).
- **Highlight-drift check (§9 "< 100 ms"):** verified by observation, not instrumentation — the observable proxy is: at 0.5× speed on the slowest device (iPhone 12), the highlight never visibly lags or leads the audible word, for one compact and one enhanced voice. If borderline, take a screen recording with audio and scrub frame-by-frame (each frame ≈ 17–33 ms). Per-voice anomalies feed Open Question 2.
- **Persistence across restart (§9; applies once SwiftData lands in Phase 2):** save a word, bookmark a sentence, grade one review; force-quit the app (swipe away, not background); relaunch — the saved word, the bookmark, and the review's updated `dueDate` must all be intact. (In-memory `ModelContainer` tests — Open Question 4 — cannot cover this by construction.)
- **OCR failure / empty result (plan §7 risk #1):** scan a blank page and a dim or glossy page; verify the recoverable "No text found — try a flatter page with more light." message appears and an immediate retry works without restarting the app.
- **Permission-denied states:** deny camera → Scan shows a recoverable message, not a dead button; also revoke camera access in Settings while the scan sheet is up and confirm graceful recovery. (No photo-library check: `PhotosPicker` runs out-of-process and never requests photo permission — the app doesn't even appear under Settings → Privacy → Photos.)
- **Interruption sanity (until observers land, ARCHITECTURE gap #3):** receive a call during playback; unplug headphones — note behavior, file regressions.

## 5. Performance verification — scan → listenable ≤ 10 s **per page** (PROJECT_PLAN §9, DECISIONS #17)

Instrument the pipeline with signposts in the scan handler — Phase-1 `ScanHomeView.process(_:)`, migrating to **`PageIngestor.ingest(...)`** when the Phase-2 refactor lands (DECISIONS #19); the `scanToListenable` interval is measured **per page** (carry-forward code change):

```swift
import os
private let signposter = OSSignposter(subsystem: "com.rubyhung.ReadAloud",
                                      category: "ScanPipeline")
// in process():
let state = signposter.beginInterval("scanToListenable")
let ocrState = signposter.beginInterval("ocr")
let text = try await ocr.recognizeText(in: image, languageCode: languageCode)
signposter.endInterval("ocr", ocrState)
// … split → endInterval("scanToListenable", state) right before readerSentences = sentences
```

Measurement procedure (manual, on the iPhone 12 baseline): Instruments → **os_signpost** template → scan each of the 5 fixture pages 3× → read the `scanToListenable` interval durations; pass if p95 ≤ 10 s and `ocr` dominates (if `split` ever exceeds ~100 ms, something is wrong). *Trade-off:* an automated `XCTMetric` perf test was rejected — it would run on simulator/CI hardware, which says nothing about the iPhone 12 bar; signposts cost nothing in production and double as field debugging.

## 6. Optional CI (explicitly optional — skip until tests exist and flake is tolerable)

Single workflow, `.github/workflows/test.yml`. No signing (simulator only), no caching cleverness:

```yaml
name: test
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - run: brew install xcodegen
      - run: xcodegen generate
      - run: xcodebuild test -scheme ReadAloud
             -destination 'platform=iOS Simulator,name=iPhone 16'
             CODE_SIGNING_ALLOWED=NO
```

*Trade-off:* macOS runners are slow/expensive and this is a solo offline app — CI's value is catching "forgot to run tests," not gating. If UI tests flake on CI, run only `ReadAloudTests` there (`-only-testing:ReadAloudTests`) and keep the smoke test local.

## Open questions

1. Does `NLTokenizer` split "M. Dupont" on current iOS? Record actual behavior when writing the fr-abbrev golden; if it splits, does the plan-§7 "manual merge/split" mitigation get pulled forward from Phase 3?
2. Do enhanced (premium/neural) voices emit `willSpeakRangeOfSpeechString` at the same granularity as compact voices? The §4 manual check answers this; if not, the <100 ms highlight-drift criterion needs a per-voice caveat.
3. Is Vision available/reliable on virtualized GitHub macOS runners for the rendered-image OCR test, or does that test stay local-only?
4. When SwiftData wires in (Phase 2), do we add in-memory `ModelContainer` tests for SRSEngine's fetch-then-filter due query, and where does that fixture builder live?

## Carry-forward tasks

- [ ] Add `ReadAloudTests`/`ReadAloudUITests` targets + scheme to `project.yml` (§1) — *acceptance: `xcodegen generate && xcodebuild test -scheme ReadAloud` runs an empty suite green on a simulator.*
- [ ] Add `now:` parameter to `SRSState.review` and write `SRSStateTests` with the §2.1 table — *acceptance: all five grade-pattern rows pass with exact `dueDate` equality.*
- [ ] Write `SentenceSplitterTests` fixtures + invariants (§2.2) — *acceptance: 7 fixture IDs pass; goldens carry recorded-on-OS comments.*
- [ ] Introduce `SpeechSynthesizing` protocol + injectable init in `SpeechPlayer`, add `FakeSynthesizer`, cover cases 1–7 (§2.3) — *acceptance: isJumping test passes under both didCancel and stale-didFinish orderings; app behavior unchanged on device.*
- [ ] Write `OCRServiceTests` orientation-mapping test (§2.4) — *acceptance: all 8 `UIImage.Orientation` cases asserted.*
- [ ] Add fixture page photos to `Fixtures/` and one to `DebugAssets.xcassets` excluded from Release in `project.yml` (§3); add Reader accessibility identifiers (`sentence-card-\(index)`, `play-pause`) + labels on icon-only playback buttons; implement the `-uiTestFixture` launch hook + XCUITest smoke — *acceptance: test launches with pinned `-targetLanguage fr-FR`, reaches Reader, finds ≥ 1 sentence card, in ≤ 15 s; Release archive contains no fixture image.*
- [ ] Add `OSSignposter` per-page intervals to the scan handler (`ScanHomeView.process`, moving to `PageIngestor.ingest`) (§5) — *acceptance: `scanToListenable` and `ocr` intervals visible in Instruments' os_signpost view during a real scan, one per page.*
- [ ] Run the §5 measurement on iPhone 12 with 5 fixtures × 3 runs; log p95 in PROJECT_PLAN §9 — *acceptance: numbers recorded; pass/fail against 10 s stated.*
- [ ] (Optional) Land `.github/workflows/test.yml` (§6) — *acceptance: green run on a PR; unit tests only if UI tests flake.*
- [ ] Execute the §4 manual release checklist before the first TestFlight build — *acceptance: checklist archived with build number; regressions filed.*
