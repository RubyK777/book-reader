# Handoff — ReadAloud (book-reader)

*Written 2026-07-13 to carry work forward to a **new agent on a new test device**.
Read this first, then [README.md](../README.md), [DEVELOPMENT.md](DEVELOPMENT.md),
[ARCHITECTURE.md](ARCHITECTURE.md), and [DECISIONS.md](DECISIONS.md) (the append-only
decision log — currently 68 entries; the last ~9 are this session).*

> **Repo was restructured after this handoff was first written.** The old
> planning/phase docs, spike tools, `CLAUDE.md`, XcodeGen, and `project.yml` were
> removed; `docs/` was consolidated into `Documentation/`. The checked-in
> `ReadAloud.xcodeproj` is now the single source of truth for the project. The
> workflow notes below reflect the current, post-cleanup repo.

## Where things stand

`main` is on GitHub (`RubyK777/book-reader`). The app is a fully-offline iOS
language-learning app (French→English primary); everything below was built,
tested, and deployed to a physical device this session.

### Shipped this session (newest first, all on `main`)

| Commit | What |
|---|---|
| `6c36e22` | Shared `PronunciationFeedbackView` (dedup review + speaking) |
| `58d4ea9` | Split large Reader/Learn views into per-file subviews |
| `93308f2` | **`Packages/LearningKit`** — pure engines extracted to a local SPM package |
| `33613a6` | Siri/Shortcuts **App Intents** — Start Review + Words Due |
| `0d7452f` | **Configurable widget** — fixes "all widgets refresh together" |
| `61f3999` | Shared **`AudioSessionCoordinator`** (dedup lock-screen/session code) |
| `c963819` | Model-download polish — real progress bar + inline offer-to-download |
| `5c54baa` | **`SavedWord` folded into `Annotation`** (schema **V5**) |
| `a5d0758`, `9fc91a0` | ExportService + CardFace tests |
| `b25da34` | Lock-screen Now Playing for conversation audio |
| `a4f8be1` | Say-your-answer in graded review (speak the answer, on-device check) |

*(These predate the cleanup commit that consolidated docs and removed the project
generator; the app code they describe is unchanged.)*

## ⚠️ New device: first things to do

The old test device ("Grassroots", iPhone 17) had specific IDs baked into the
deploy commands. **On a new device these IDs change — re-discover them:**

```sh
# hardware UDID (for xcodebuild -destination 'id=...')
xcrun xctrace list devices 2>&1 | grep -i iphone
# devicectl identifier (for install/launch) — the UUID in the "Devices" list
xcrun devicectl list devices
```

Then update the deploy commands below with the new IDs. (The auto-memory note
`grassroots-test-device.md` holds the OLD device's IDs — treat it as stale until re-verified.)

## Build / test / deploy workflow

`ReadAloud.xcodeproj` is checked in and is the source of truth — there is **no
project generator** anymore. Open it directly in Xcode (see
[DEVELOPMENT.md](DEVELOPMENT.md)). Add new files, targets, capabilities, and build
settings **in Xcode**, and commit the resulting `project.pbxproj` change alongside
the source change that needs it.

```sh
# Device build (replace the id with the new device's hardware UDID):
xcodebuild -project ReadAloud.xcodeproj -scheme ReadAloud \
  -destination 'id=<NEW_HW_UDID>' -allowProvisioningUpdates \
  -derivedDataPath build/DeviceBuild build

# Install to device (replace with new devicectl UUID):
xcrun devicectl device install app --device <NEW_DEVICECTL_UUID> \
  build/DeviceBuild/Build/Products/Debug-iphoneos/ReadAloud.app

# App tests (SwiftData/model-bound) — run on a booted simulator:
xcodebuild -project ReadAloud.xcodeproj -scheme ReadAloud \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Package tests (pure engines) — run standalone on the Mac:
cd Packages/LearningKit && swift test
# 24 tests, 4 suites.
```

### Gotchas learned this session
- **New Swift files** must be added to the target in Xcode (drag into the project
  navigator, or File ▸ Add Files) — a file that only exists on disk is not in the
  build. Commit the `ReadAloud.xcodeproj/project.pbxproj` change with it.
- **Stale simulator store** after a schema change → the app crashes on launch in the sim
  with `loadIssueModelContainer`. Fix: `xcrun simctl uninstall <SIM_UUID> com.rubyhung.ReadAloud`
  before running tests (find the sim UUID with `xcrun simctl list devices available`).
- **SourceKit noise**: the editor shows "No such module 'LearningKit'" / "AVAudioSession
  unavailable in macOS" / "Cannot find type X" all the time. These are indexing artifacts —
  **trust `xcodebuild`, not the inline diagnostics.**

## Schema state — IMPORTANT

- Live schema is **V5** (`ReadAloudSchema = ReadAloudSchemaV5` in `Models/Schema.swift`):
  `[Book, ScanPage, Sentence, Annotation]`. `SavedWord` was removed (folded into `Annotation`).
- **No production users**, so schema changes are handled by *reset-fresh + reinstall*, not
  data-preserving migration. Rule: any change to a `@Model` OR an embedded Codable
  (`SRSState`, `LearningAssets`, `WordTiming`) changes the fingerprint → freeze the prior
  version as a nested snapshot, bump to a new `ReadAloudSchemaV<n>`, add a lightweight stage,
  run `MigrationTests`, and **uninstall+reinstall on device** (DECISIONS #35, #63; see also
  the "Persistence changes" note in [DEVELOPMENT.md](DEVELOPMENT.md)).

## On-device things to verify (couldn't be tested headlessly)

1. **Widgets** (`0d7452f`): the config type changed (Static→AppIntentConfiguration), so
   **remove and re-add** any placed widgets once. Then confirm two widgets set to different
   "Show" values are independent (shuffle one, the other stays).
2. **Siri** (`33613a6`): "How many words are due in ReadAloud?" (answers without launching)
   and "Start my review in ReadAloud." Shortcuts phrases can take a minute to register.
3. **Model-download progress** (`c963819`): trigger a language whose speech model isn't
   installed (Speaking practice or a listening/cloze review card) → "Download model" →
   progress bar → "Say it". Tune the 60% pass threshold in `PronunciationScorer.score` if it
   feels off.
4. **Say-your-answer** (`a4f8be1`): listening/cloze review cards have a "Say it" mic.
5. **Lock-screen** (`b25da34`): play a conversation (real-audio) source, lock the phone,
   confirm Now Playing + play/pause/next/prev work.

## What's next (the remaining backlog, with honest risk notes)

The high-value, low-risk work is done. Remaining items and why they were deferred:

- **`ReviewSessionView` / `SentenceLearnView` — further splitting is optional.** A first pass
  extracted the cohesive, low-coupling pieces into per-file subviews (see below), taking each from
  ~700/665 → ~553/542 lines. The remaining bulk is each view's tightly-coupled `@State` state
  machine (Review: recall/speech/model-download phases; Learn: the karaoke original + save flow).
  Breaking those apart means threading many bindings — higher risk, low reward; do only if wanted.

*Done since this handoff:*
- **SM-2 → LearningKit** (DECISIONS #69) — the scheduler math moved to the pure, tested
  `LearningKit.SM2Scheduler`; `SRSState` stayed the storage type (no schema change).
- **View splits (first pass)** — `ReviewSessionView` → `MasteryBanner`, `ReviewGradeButtons`,
  `ReviewSummaryView`; `SentenceLearnView` → `UnderstandContentView`, `SentenceSavedItemsList`.
  Verbatim, behavior-preserving; state stays in the parent and is passed in as values/closures.

*(The old `docs/IMPROVEMENTS/` backlog was removed in the cleanup; its top picks were
already shipped — audio-capture loop, pronunciation, say-your-answer, batch capture,
onboarding, widgets, App Intents, LearningKit, SavedWord port, translate helper, mastery
moment, tests.)*

## Architecture quick map (see [ARCHITECTURE.md](ARCHITECTURE.md) for detail)

- `Features/<Screen>/` views · `Services/` logic · `Models/Models.swift` schema ·
  `Shared/{Components,Styles,Extensions}` reusable UI · `Packages/LearningKit` pure engines.
- Two players behind `SentencePlaying`: `SpeechPlayer` (TTS) and `RecordingPlayer` (real
  audio); the Reader picks one at init. Lock-screen/session handled by `AudioSessionCoordinator`.
- Transcription behind `Transcribing` (`SpeechAnalyzerTranscriber` iOS 26, `OnDeviceTranscriber`
  fallback); on-demand model download with `installModel(_:onProgress:)`.
- Widget + App Intents share the App Group via `SharedStore` (UserDefaults snapshot: cards,
  due count, start-review flag) — no SwiftData in the widget/intent processes.
- Hard rules (see [DEVELOPMENT.md](DEVELOPMENT.md)): fully offline, Apple frameworks only,
  no third-party deps, reuse-first, anti-gamification (no streaks/XP/scores), `@Observable`
  (never ObservableObject).
