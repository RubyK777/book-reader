# User Interests & Engagement

This review turns four grounded learner personas — the Traveler, the Heritage learner, the Immersion/Expat learner, and the Media learner — plus a set of warm, non-gamified retention mechanics into concrete, pickable suggestions. Every item is anchored to existing ReadAloud files and obeys Ruby's reuse-first, offline-only, energetic-but-not-gamified rules. Suggestions that merely restate a shipped capability have been dropped; partial matches are framed as EXTENSIONS.

**How to read this** — Suggestions are grouped by theme; within each theme, quick wins come first. Skim titles, read **What & why**, then check **Reuse**/**Effort** before handing an item to an implementer.

---

## Theme 1 — Quick-capture utility surfaces (Traveler & Expat)

These serve the "decode it NOW, don't make me study it" moment. Bursty, one-handed, outdoors.

### Menu/sign "hear it" pronunciation chip
**What & why** — Tap any detected fragment (a dish name, a sign word) to hear it, so the traveler can say it aloud to a waiter. Delivers value in one tap, no ingest ceremony.
**Reuse** — `SpeechPlayer.speakOnce` (already does one-off word/chunk playback) + resolved voice from `Services/VoiceStore.swift`; `SourceKind.menu/.sign` already carry `systemImage`/tint via `Shared/Styles/SemanticColors.swift`.
**Effort** — S. No dependencies.
**Notes** — Apple TTS only; direct reuse of `speakOnce`, no new subsystem.

### Screenshot-native ingest lane (EXTENSION)
**What & why** — Expats live in screenshots. Make screenshot import the fastest path with auto-titling so a landlord's WhatsApp text becomes decodable in seconds.
**Reuse** — EXTENDS existing capture: `SourceKind.screenshot` (`Models/Models.swift:9`, already has `iphone` icon and auto-title path), `Features/Scan/ScanFlowView.swift` import path + `OCRReviewView` auto-title (sign/menu/screenshot/other already auto-titled). This is polish on an existing flow, not a new one.
**Effort** — S.
**Notes** — Offline OCR via `OCRService`; pure reuse.

### Quick-Scan Digest card after a sign/menu scan
**What & why** — After a sign/menu scan, show a one-tap glance: detected items + inline translation, no ingest-to-Book ceremony. The learner gets an answer, not a study object.
**Reuse** — `Services/FragmentDetector.swift` (already classifies price/symbol/short lines), `Features/Scan/OCRReviewView.swift` + `AssignBookView` auto-title path, batch `.translationTask` in `Features/Reader/ReaderView.swift:206`. This is the open **Phase 4 "Quick Scan digest"** in `docs/TASKS.md`.
**Effort** — M. Best done after the `Meaning`/translate-helper extraction (Theme 5) so it rides a shared translate surface.
**Notes** — Offline-after-first-translate; pure reuse; a utility surface, no gamification.

### Ephemeral capture that doesn't clutter the shelf (EXTENSION)
**What & why** — Travelers never "review" a menu. Let sign/menu scans live as throwaway unless explicitly kept, so the Library doesn't become a menu graveyard.
**Reuse** — EXTENDS the Reader's existing `.ephemeral` init (`Features/Reader/ReaderView.swift`) — default the sign/menu scan flow to ephemeral rather than persisting. Ephemeral support already exists; this is wiring it into the scan path.
**Effort** — M.
**Notes** — Keeps the app CONCISE; pure structural reuse.

---

## Theme 2 — Intent-aware learning lanes (Heritage & Expat)

Heritage learners save words to *say correctly*; expats save phrases to *reuse*. The `SaveIntent` enum already exists — these route by it rather than adding models.

### "Pronounce" intent → listening-first review face
**What & why** — Heritage learners save words to pronounce, not translate. Route `SaveIntent.pronounce` annotations to a listening/shadowing-first review face so their queue matches their goal.
**Reuse** — `SaveIntent.pronounce` already exists (`Models/Models.swift:122`); `SRSEngine.ReviewItem.face` already emits a `.listening` face — bias pronounce-intent annotations toward it. Noted as **Phase 5 "intent routing"** in `docs/TASKS.md`.
**Effort** — S (near one-line face routing). No new model.
**Notes** — Reuses existing intent enum + SRS faces; warm, not competitive.

### "Use later" phrasebook filter (EXTENSION)
**What & why** — Expats want to grab a ready phrase when replying or speaking. A filtered surface of `SaveIntent.use` annotations turns saved items into a usable phrasebook.
**Reuse** — EXTENDS `Features/Notes/NotesView.swift`, which already filters annotations by type and Confused — add a `use`-intent filter chip. `Annotation.userExample` already holds a drafted usage.
**Effort** — S.
**Notes** — Reuses existing Notebook filter infra + AI `draftExample`; anti-gamified reference tool.

### Shadowing as a first-class "read this letter aloud" flow (EXTENSION)
**What & why** — Heritage learners want to read a family letter aloud and hear whether their voice matches — the core emotional moment. Surface record-and-compare directly from the Reader for personal documents, not only inside Review.
**Reuse** — EXTENDS `Features/Review/ShadowingPracticeView.swift` + `Services/VoiceRecorder.swift` (already play-original/record-self/replay-both) — lift the entry point into `Features/Reader/ReaderView.swift`. The mechanic exists; only the entry point is new.
**Effort** — M.
**Notes** — Fully offline (AVFoundation); leans into pronunciation anxiety, warm not competitive.

### AI "reply-ready" example from a confusing phrase (EXTENSION)
**What & why** — Turn a confusing official phrase into one the learner could actually say back. Expose the existing AI drafting from the screenshot/expat flow.
**Reuse** — EXTENDS `FoundationModelsAssetsProvider.draftExample` / `explainConfusion` (already wired in `Features/Notes/AnnotationDetailView.swift`) — just expose it from the screenshot flow.
**Effort** — M.
**Notes** — On-device Foundation Models, availability-gated (Phase 0.1 quality gate still open per `docs/SPIKE_RESULTS.md`).

### Recipe/letter source kind
**What & why** — Heritage documents (letters, recipe cards) are neither book nor menu; a warmer container improves fit and tone.
**Reuse** — Adds a case to the `SourceKind` enum (`Models/Models.swift:8`). Genuinely small *because* the enum raw string is not part of the embedded-Codable schema fingerprint.
**Effort** — S.
**Notes** — Watch the schema-fingerprint rule (DECISIONS #35): an enum raw-string case is safe and needs no migration of `LearningAssets`/`SRSState`.

---

## Theme 3 — Warm retention & delight (non-gamified)

Each reuses existing celebration/summary machinery and respects the no-streaks/XP/points/badges rule. Celebrations fire on genuine mastery, never on activity.

### "Taking root" mastery moment
**What & why** — When a reviewed item's SRS interval first crosses into mature (e.g. `intervalDays ≥ 21`), a one-shot tasteful "You've really learned this." This marks memory consolidation — a graduation, not a badge.
**Reuse** — Compare `SRSState.review(quality:)` result before/after in `SRSEngine.grade`; `ConfettiView` + `Haptics.celebrate` already wired in `Features/Review/ReviewSessionView.swift:97,500`.
**Effort** — S.
**Notes** — Tied to real mastery; explicitly not a streak/badge.

### Confusion-resolved delight
**What & why** — When a card flagged `isConfusing` is graded Good/Easy and `isResolved` flips true, a small warm "That one finally clicked." Turns the existing confusion lifecycle into an emotional payoff.
**Reuse** — `Annotation.isConfusing/isResolved` (`Models/Models.swift`), `ConfettiView`, `Haptics.celebrate`; confusion flow already lives in `Features/Notes/AnnotationDetailView.swift`.
**Effort** — S.
**Notes** — Rewards resolving genuine difficulty, not points.

### After-scan digest (EXTENSION)
**What & why** — On finishing an ingest, show a calm recap ("Added 6 sentences · 2 look worth saving") so capture ends in reflection, not a dead-end.
**Reuse** — EXTENDS the Reader's existing `digestBar` + `digestSummary` (`Features/Reader/ReaderView.swift:313,324`) — clone them after `PageIngestor.ingest()`, surfaced in `Features/Scan/OCRReviewView.swift`. Named in `docs/TASKS.md` "Quick Scan digest".
**Effort** — S.
**Notes** — Pure reuse; offline; mirrors an already-approved pattern.

### Session summary → "what's next" framing (EXTENSION)
**What & why** — Extend the session-complete summary with one grounded forward line ("Next few ready in 3 days — or practice any time"), giving closure and a gentle pull-back without a streak.
**Reuse** — EXTENDS `summaryView` (`Features/Review/ReviewSessionView.swift:337`) + `nextDueText`/`nextDueDate` (`Features/Review/ReviewView.swift:108`).
**Effort** — S.
**Notes** — Relative-date framing; no daily-obligation pressure.

### Personalized rest-state copy (EXTENSION)
**What & why** — Make the Review resting/empty screens name the learner's own material ("You saved 4 words from Le Petit Prince"), so the app feels like it remembers their journey.
**Reuse** — EXTENDS `deckState`/`emptyState` strings in `Features/Review/ReviewView.swift:56,124` and `AnimatedEmptyState`, sourcing `Sentence.page?.book?.title` / `Annotation.contextSentence` (`Models/Models.swift`).
**Effort** — S.
**Notes** — Personalization/"why this matters," no metrics.

### Gentle "ready when you are" review reminder
**What & why** — One soft local notification at the deck's soonest `dueDate`, warm copy ("A few cards from Le Petit Prince are ready"), never count-shaming, user-toggleable.
**Reuse** — `SRSEngine.dueItems`/`nextDueDate` (already used in `Features/Review/ReviewView.swift:28`) + `AppRouter.recomputeDueCount` (`App/AppRouter.swift:16`); recompute on the `scenePhase.active` hook already in `App/RootView.swift`. The `UNUserNotification` scheduling itself is genuinely new (verified: none in repo).
**Effort** — M.
**Notes** — Apple-only/offline; schedule a SINGLE nudge, never daily streak pings — that is the anti-gamification guardrail.

---

## Theme 4 — Reflection & continuity

Meaningful, non-numeric ways to resurface effort and progress.

### Reopen recap in Reader (EXTENSION)
**What & why** — When reopening a page studied before, a quiet header "You saved 3 words here last time" resurfaces prior effort at the right moment.
**Reuse** — EXTENDS the `sessionAnnotations` filter-by-`savedAt` pattern (`Features/Reader/ReaderView.swift:304`), generalized to the page's annotations, keyed off `ScanPage.lastOpenedAt` (already drives Resume, `Models/Models.swift`).
**Effort** — M.
**Notes** — Continuity/resurfacing; warm and low-key.

### "Your progress" reflection screen
**What & why** — A calm, non-numeric view: deck maturity as buckets (Learning / Taking root / Known) from SRS interval length, plus words saved and next-up date. Reflection, not scores. Absorbs the deferred **Phase 5 "stats view"**.
**Reuse** — `SRSState.intervalDays/repetitions/dueDate` (`Models/Models.swift`), the `LabeledContent` SRS-stats block already in `Features/Notes/AnnotationDetailView.swift:156`, `CountUpText` + `AnimatedMeshBackground` (`Shared/Components/`).
**Effort** — M.
**Notes** — Reuse-heavy; frame maturity as growth ("taking root"), never levels/XP.

---

## Theme 5 — Media learner & audio (big bets)

The Media learner ("subtitles vanish, I can't grab the audio") is served today by a small bridge, and long-term by the in-flight audio plan. Ordered quick-win first.

### Subtitle screenshot → listenable line
**What & why** — Bridge for media learners before audio ships: OCR a subtitle screenshot and hear it in TTS with karaoke highlighting. Serves them today with zero new subsystems.
**Reuse** — `SourceKind.screenshot` + `OCRService` + `SpeechPlayer` karaoke `highlightRange`. Rides entirely on existing capture + playback.
**Effort** — S.
**Notes** — Offline; immediate reuse.

### Extract the shared translate helper (prerequisite cleanup)
**What & why** — Not a feature, but the de-bloat that should precede several persona surfaces above. The live-translate `Meaning` enum + `translate(using:)` exists in three copies; every translate touchpoint (Quick-Scan digest, phrasebook, subtitle line) rides on it.
**Reuse** — Consolidate `Meaning` from `Features/Review/ReviewSessionView.swift:20`, `Features/Saved/SavedItemDetailView.swift:17`, and the batch impl in `Features/Reader/ReaderView.swift:206` into one `Shared` translate helper. Rule-of-two already exceeded (three copies).
**Effort** — S.
**Notes** — Aligns with REUSE-FIRST/CONCISE; do this first to de-bloat before adding persona surfaces.

### Audio-capture loop (conversation kind)
**What & why** — Record real French audio → on-device transcript → timestamped, replayable, saveable sentences, reusing the entire OCR→sentence→save→review loop. The single biggest capability expansion.
**Reuse** — The in-flight plan in `docs/AUDIO_LEARNING_DESIGN.md`; `PageIngestor`'s 2-step recognize/ingest pattern maps to transcribe/ingest; `SourceKind.conversation` is already proposed.
**Effort** — L. Big-bet; carries the schema-fingerprint cost if new embedded fields are added (DECISIONS #35).
**Notes** — Fully offline (Apple Speech); not a quick pick — a strategic direction.

### Real-audio timestamp playback in Reader
**What & why** — When audio lands, swap TTS for the original recording at sentence timestamps so learners hear the actual actor/singer, keeping one playback abstraction.
**Reuse** — `SpeechPlayer` sentence-queue + `highlightRange` contract (extend to a timestamp source per `AUDIO_LEARNING_DESIGN.md`); `isJumping` already handles programmatic jumps.
**Effort** — L. Depends on the audio-capture bet above.
**Notes** — Keeps one playback abstraction (concise); offline.

---

## Triage table

| Suggestion | Impact | Effort | Reuses |
|---|---|---|---|
| Menu/sign "hear it" chip | Med | S | `SpeechPlayer.speakOnce`, `VoiceStore`, `SemanticColors` |
| Screenshot-native ingest lane | High | S | `SourceKind.screenshot`, `ScanFlowView`, `OCRReviewView` |
| "Pronounce" → listening face | Med | S | `SaveIntent.pronounce`, `SRSEngine.ReviewItem.face` |
| "Use later" phrasebook filter | High | S | `NotesView` filters, `Annotation.userExample` |
| Recipe/letter source kind | Med | S | `SourceKind` enum |
| "Taking root" mastery moment | High | S | `SRSEngine.grade`, `ConfettiView`, `Haptics` |
| Confusion-resolved delight | Med | S | `Annotation.isConfusing/isResolved`, `ConfettiView` |
| After-scan digest | Med | S | `ReaderView` `digestBar`, `PageIngestor` |
| Session summary "what's next" | Med | S | `ReviewSessionView.summaryView`, `nextDueText` |
| Personalized rest-state copy | Med | S | `ReviewView` states, `Book.title` |
| Subtitle screenshot → listenable | High | S | `OCRService`, `SpeechPlayer.highlightRange` |
| Shared translate helper (cleanup) | Med | S | `Meaning` enum x3 → `Shared` |
| Quick-Scan Digest card | High | M | `FragmentDetector`, `OCRReviewView`, batch translate |
| Ephemeral sign/menu capture | Med | M | `ReaderView.ephemeral` init |
| Shadowing from Reader | High | M | `ShadowingPracticeView`, `VoiceRecorder` |
| AI "reply-ready" example | Med | M | `FoundationModelsAssetsProvider.draftExample` |
| Gentle review reminder | High | M | `SRSEngine.dueItems`, `AppRouter` (+ new `UNUserNotification`) |
| Reopen recap in Reader | Med | M | `ReaderView` `sessionAnnotations`, `ScanPage.lastOpenedAt` |
| "Your progress" reflection screen | High | M | `SRSState`, `AnnotationDetailView` stats block, `CountUpText` |
| Audio-capture loop | Very High | L | `AUDIO_LEARNING_DESIGN.md`, `PageIngestor` |
| Real-audio timestamp playback | High | L | `SpeechPlayer` queue + `highlightRange` |
