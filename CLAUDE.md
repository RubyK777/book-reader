# ReadAloud (book-reader)

iOS app for language learners: photograph a book page → on-device OCR → listen sentence-by-sentence with word-level highlighting → save words → spaced-repetition review. Fully offline: Apple frameworks only (Vision, NaturalLanguage, AVSpeechSynthesizer, SwiftData), no third-party deps, no networking — ever.

## Read first

| Question | Document |
|---|---|
| What are we building, in what order? | [PROJECT_PLAN.md](PROJECT_PLAN.md) — master spec (screens, phases, risks, acceptance criteria) |
| What exists right now, and its contracts? | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| What do I build next? | [docs/TASKS.md](docs/TASKS.md) — **source of truth backlog; check items off as they land** |
| How is feature X designed? | `docs/PHASE2_DESIGN.md`, `PHASE3_DESIGN.md`, `UX_SPEC.md`, `AUDIO_DESIGN.md`, `OCR_PIPELINE.md`, `TESTING_QUALITY.md` |
| Why was it decided this way? | [docs/DECISIONS.md](docs/DECISIONS.md) — append-only decision log |

Keep these documents current: when you finish a task, tick it in TASKS.md; when you make a nontrivial design choice, append it to DECISIONS.md; when structure changes, update ARCHITECTURE.md.

## Build & run

```sh
xcodegen generate            # ONLY after project.yml changes (brew install xcodegen)
open ReadAloud.xcodeproj     # build/run from Xcode; camera needs a real device
```

- **Never hand-edit `ReadAloud.xcodeproj`** — it's generated. Edit `project.yml`, rerun `xcodegen generate`.
- Build check from CLI: `xcodebuild -project ReadAloud.xcodeproj -scheme ReadAloud -destination 'generic/platform=iOS Simulator' build`
- On the simulator use **Import Photo** instead of the camera.
- OCR accuracy spike (macOS CLI, no Xcode needed): `swift Tools/OCRSpike/main.swift fr-FR Fixtures/*.jpg`

## Reuse first — no reinvented wheels

Ruby's standing rule for all agents working in this repo:

1. **Check before you build.** Before writing any new view, style, or helper, look in `Shared/` (and `Services/`) for an existing one to use or extend. Duplicating something that already exists is a defect, not a shortcut.
2. **Keep UI building blocks in `Shared/`, cleanly separated:**
   - `Shared/Components/` — reusable views (cards, badges, empty-state views, toolbars…)
   - `Shared/Styles/` — the iOS equivalent of a CSS layer: `ViewModifier`s, `ButtonStyle`s, and design tokens (colors, spacing, type scale) as extensions/enums. Screens compose these; they don't hardcode their own fonts/colors/paddings.
   - `Shared/Extensions/` — small Foundation/SwiftUI extensions
   - Rule of two: the second time a piece of UI or logic is needed, extract it to `Shared/` instead of copying it.
3. **Write logic as libraries.** Anything app-agnostic (SRS math, sentence splitting, OCR text assembly, WER scoring…) must not import SwiftUI or reference app models/screens — pure input → output APIs. When a `Services/` type proves stable and generic, promote it to a local Swift package under `Packages/` (SPM, referenced from `project.yml`) so other projects can depend on it directly. Design new services with that future extraction in mind: no singletons, dependencies passed in, no `@AppStorage`/UserDefaults inside library code.

## Conventions

- iOS 17.4+ · SwiftUI · `@Observable` macro (never ObservableObject) · SwiftData · Swift Concurrency.
- Layout: `Features/<Screen>/` for views, `Services/` for logic, `Models/Models.swift` for the SwiftData schema, `Shared/` for reusable UI.
- `languageCode` is full BCP-47 (`"fr-FR"`) everywhere; trim to 2 letters only at NL/Vision API call sites.
- `SRSState` is a Codable struct → `#Predicate` can't reach `srs.dueDate`; fetch candidates and filter in memory (see DECISIONS.md).
- `SpeechPlayer.isJumping` suppresses auto-advance on programmatic jumps — preserve this if touching playback (state machine in docs/AUDIO_DESIGN.md).
