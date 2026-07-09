# SPIKE_RESULTS.md — Phase 0 spike runs (PIVOT_PLAN §7)

*Run 2026-07-09. Machine: Mac, macOS 26.0 — **build 25A5295e, a 26.0 BETA seed** (this matters, see 0.1) — Xcode 26.2 (17C52), `/System/Library/Frameworks/FoundationModels.framework` present. 180 system voices installed.*

---

## Spike 0.1 — Foundation Models quality spike: **BLOCKED on this machine** (no quality data yet)

**Harness:** `Tools/LearnSpike/main.swift` (standalone CLI, not in any Xcode target) + `Fixtures/french_sentences.txt` (20 French sentences: book prose, signage, menu lines, polite requests, idioms, reflexives, a subjunctive trigger, passé composé vs imparfait). The tool checks `SystemLanguageModel.default.availability`, then runs `@Generable` guided generation of `LearningAssetsDraft` (chunks {text, gloss} / keyVocab {term, meaning} / one grammarPoint, English explanations per D9) per sentence with per-sentence timing and error handling.

**Result: the model could not be exercised. Two independent blockers, both verified:**

1. **`unavailable(.appleIntelligenceNotEnabled)`** — exact output:
   ```
   SystemLanguageModel.default.availability: unavailable(.appleIntelligenceNotEnabled)
   — Apple Intelligence is not turned on in System Settings
   ```
2. **OS/SDK ABI mismatch — generation would fail even with Apple Intelligence enabled.** The host runs macOS 26.0 **beta 2** (25A5295e), whose FoundationModels framework exports a pre-release ABI (`respond(…isolation:)`, `LanguageModelSession.init(model:guardrails:tools:instructions:)`). Binaries built with the release SDKs on this machine (Xcode 26.2, and the CLT MacOSX26.0.sdk — also release-ABI) reference symbols the installed framework does not export:
   - `LanguageModelSession.init(model:tools:instructions:)`
   - `LanguageModelSession.respond(to:generating:includeSchemaInPrompt:options:)`

   Consequences on this host: `swift Tools/LearnSpike/main.swift …` dies with *"JIT session error: Symbols not found"*, and a normally-linked `swiftc` binary aborts at launch in dyld. The tool now weak-links the framework and runs a dlsym ABI probe, so it launches, reports availability, and prints the exact mismatch instead of crashing (build command in the file header).

**Timing stats:** none — no generation call ever executed. **Quality grading vs the ≥80%-usable bar:** not gradeable — zero outputs produced. **Wrong-grammar-note rate:** no data. This is a failure to run, not a pass.

**What unblocks a real run (in order):**
1. Update the Mac from the 26.0 beta seed to **release macOS 26.0+** (fixes the ABI mismatch; beta-2-era framework is missing the shipped API surface).
2. **Enable Apple Intelligence** in System Settings and let model assets download.
3. Rerun: `swift Tools/LearnSpike/main.swift Fixtures/french_sentences.txt` (interpreter mode should work once OS and SDK agree). Hand-grade the 20 outputs; record the wrong-grammar-note rate in DECISIONS.md per the 0.1 acceptance row.

**Gate status:** the 0.1 gate is **still open** — per PIVOT_PLAN, Phase 2's AI path cannot be committed (nor the fallback-only decision taken) until this spike runs on Apple Intelligence hardware. Nothing here suggests the model is bad; we simply have no evidence either way yet.

---

## Spike 0.3 — French voice audit: ran; **no enhanced/premium French voices installed on this machine**

**Harness:** `Tools/VoiceAudit/main.swift` — `swift Tools/VoiceAudit/main.swift` (ran clean under the interpreter; AVFoundation has no ABI issue).

**Installed fr-\* voices: 18, every one of them `default` tier.** No enhanced, no premium, no novelty/personal traits.

| locale | name | quality | identifier |
|---|---|---|---|
| fr-FR | Eddy | default | com.apple.eloquence.fr-FR.Eddy |
| fr-FR | Flo | default | com.apple.eloquence.fr-FR.Flo |
| fr-FR | Grandma | default | com.apple.eloquence.fr-FR.Grandma |
| fr-FR | Grandpa | default | com.apple.eloquence.fr-FR.Grandpa |
| fr-FR | Jacques | default | com.apple.eloquence.fr-FR.Jacques |
| fr-FR | Rocko | default | com.apple.eloquence.fr-FR.Rocko |
| fr-FR | Sandy | default | com.apple.eloquence.fr-FR.Sandy |
| fr-FR | Shelley | default | com.apple.eloquence.fr-FR.Shelley |
| fr-FR | Thomas | default | com.apple.voice.super-compact.fr-FR.Thomas |
| fr-CA | Amélie | default | com.apple.voice.super-compact.fr-CA.Amelie |
| fr-CA | Eddy, Flo, Grandma, Grandpa, Reed, Rocko, Sandy, Shelley | default | com.apple.eloquence.fr-CA.\* |

**Reading of the table (mechanical, pre-listening):**

- 16 of 18 are **Eloquence** voices — formant-synthesis accessibility voices (robotic). They are poor candidates for a learner's shadowing model regardless of tier label.
- The only non-Eloquence options are **Thomas (fr-FR)** and **Amélie (fr-CA)**, both `super-compact` (the smallest concatenative tier).
- **Per-tier default pick:** premium — *(none installed)*; enhanced — *(none installed)*; default — **Thomas (fr-FR, super-compact)**: the only installed non-Eloquence fr-FR voice, so the least-bad shadowing model currently on this machine. (The tool's alphabetical tie-break prints Eddy first; Thomas is the deliberate recommendation.)

**The audit that 0.3 actually asks for — enhanced/premium fr-FR at 0.4–0.5× and 1.0× — cannot be completed until higher-tier French voices are downloaded** (System Settings → Accessibility → Spoken Content → System Voice → Manage Voices… → French; Apple's catalog carries enhanced/premium fr-FR voices, e.g. the Thomas/Audrey/Aurélie families — exact tiers visible in that list). Rerun `swift Tools/VoiceAudit/main.swift` after downloading and they will appear ranked at the top of the recommendation table.

**Final listening judgment (which voice becomes the `VoiceStore` default, and the shadowing-quality note) is Ruby's, by ear** — this audit only establishes what is installed and at which tier. Note for expectations (PIVOT_PLAN risk #5): if enhanced-tier fr-FR turns out to be the practical ceiling on user devices, the shadowing-model quality note should be written against enhanced, not premium.

---

## Rerun checklist

- [ ] macOS updated to release 26.0+ (clears the FoundationModels beta-ABI mismatch)
- [ ] Apple Intelligence enabled, model assets downloaded
- [ ] `swift Tools/LearnSpike/main.swift Fixtures/french_sentences.txt` → hand-grade 20 outputs, record timing + wrong-grammar-note rate here and in DECISIONS.md
- [ ] Enhanced/premium French voices downloaded → `swift Tools/VoiceAudit/main.swift` → Ruby listens at 0.4–0.5× and 1.0×, names the `VoiceStore` default here
