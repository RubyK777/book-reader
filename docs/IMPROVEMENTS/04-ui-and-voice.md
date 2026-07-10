# UI, Presentation & Product Voice

This dimension covers how ReadAloud *looks* and how it *speaks*: design-token discipline, accessibility hard-rules (tap targets, VoiceOver, Dynamic Type, Reduce-Motion), reuse of the existing component library, and the written voice of every string a learner reads. Almost nothing here is new construction — it is token compliance, reuse of components that already exist, and copy rewrites of strings already in the code. The one genuinely-new item (first-run onboarding) is called out explicitly and still built entirely from existing components.

**How to read this** — Grouped by theme; within each group, quick wins first (highest learner value for lowest effort). Every item names the exact file/line and the existing token, component, or style it builds on. Skim the triage table at the end to pick.

---

## 1. Accessibility hard-rules (highest priority — these are guideline violations, not preferences)

### Give Reader transport controls a 44pt tap target
**What & why** — The prev/next buttons (`backward.fill`/`forward.fill`) and the digest-dismiss `xmark` in the Reader have no 44×44 frame (ReaderView.swift:336–342), so the core "go back / skip forward while listening" action is sub-target and easy to miss. The star and graduation-cap buttons on the same screen already get it right.
**Reuse** — Copy the `.frame(width: minTapTarget, height: minTapTarget)` already applied to the bookmark/learn buttons (ReaderView.swift:456/467).
**Effort** — S; no dependencies.
**Notes** — DESIGN_GUIDELINES §4 hard-rule violation on the core listen loop.

### Give Review-session Play/Slow and grade buttons a 44pt target
**What & why** — The front-of-card "Play"/"Slow" buttons use `.controlSize(.small)` bordered buttons (ReviewSessionView.swift:168–169, 191–203, 217) — they are the primary way to re-hear a card, yet sub-target. Same fix, same screen family.
**Reuse** — Add a `minTapTarget` frame or drop `.small`.
**Effort** — S.
**Notes** — §4; tap-target gap on the core listen action.

### Add a 44pt frame to the Settings voice-preview button
**What & why** — The `play.circle` voice preview is `.borderless` with no 44 frame (SettingsView.swift:104–110). Everything else on this Form is appropriately plain and correct.
**Reuse** — `minTapTarget` frame; leave the surrounding system Form as-is.
**Effort** — S.
**Notes** — §4; the only nit on an otherwise clean screen.

### Add VoiceOver labels to the Reader transport
**What & why** — prev/play/next in `playbackBar` (ReaderView.swift:366–379) are bare SF Symbols with no `accessibilityLabel`; VoiceOver reads them as "backward fill" etc. instead of "Previous sentence / Play / Next sentence."
**Reuse** — The same `.accessibilityLabel` pattern is already used on the bookmark/learn buttons (ReaderView.swift:459/470).
**Effort** — S.
**Notes** — VoiceOver gap on the transport a learner uses most.

### Gate the Reader active-card scale on Reduce Motion
**What & why** — `SentenceCard` applies `.scaleEffect(isActive ? 1.02)` + `.animation` unconditionally (ReaderView.swift:480–481), so the active-sentence pulse ignores Reduce Motion.
**Reuse** — Read `@Environment(\.accessibilityReduceMotion)` and null the animation, mirroring `NotesView.swift:201–211` (the exemplar: it gates `.scrollTransition` on `reduceMotion`) and the gating already inside `ChipButtonStyle`/`PressableScaleButtonStyle`.
**Effort** — S.
**Notes** — Reduce-Motion gap; NotesView is the reference pattern.

### Explicitly Reduce-Motion-check the Saved ReplayButton bounce
**What & why** — `ReplayButton`'s `.symbolEffect(.bounce)` (SavedItemsView.swift:173) isn't explicitly gated. Minor, but completes the Reduce-Motion sweep.
**Reuse** — Same `@Environment(\.accessibilityReduceMotion)` pattern as above.
**Effort** — S.
**Notes** — Low-priority Reduce-Motion polish.

### Grade-button contrast + Dynamic Type in Review session
**What & why** — Grade buttons render `grade.tint` text on `grade.tint.opacity(0.15)` (ReviewSessionView.swift:322–326); the lighter hues (marigold/verdigris) risk failing WCAG 4.5:1 (§5), and four buttons across with `minimumScaleFactor(0.7)` (:313/317) cramp badly at accessibility sizes. This is the moment of self-assessment — it must stay legible.
**Reuse** — The darkened dark-variant hues already exist in `Palette` (e.g. the marigold #A9740E note in the guidelines); consider reflowing to a 2×2 grid at large Dynamic Type.
**Effort** — M.
**Notes** — Contrast + Dynamic Type gap on a core interaction.

### Let generated-cover titles reflow instead of shrink at AX sizes
**What & why** — `minimumScaleFactor(0.75)` + `lineLimit(4)` in the fixed 2:3 tile (LibraryView.swift:206–208) shrinks long titles rather than reflowing them, so at accessibility Dynamic Type sizes generated covers become unreadable.
**Reuse** — Visual-only change; the tile already has a good custom `accessibilityLabel` (:241), so VoiceOver is unaffected. Consider allowing tile height to grow.
**Effort** — S.
**Notes** — Dynamic Type gap; visual side only.

---

## 2. Design-token compliance (quick, mechanical, keeps the paper-&-ink identity honest)

### Route off-ladder hero icon sizes through IconSize
**What & why** — Fixed `.font(.system(size: 52/56/44))` literals recur for hero glyphs (ReaderView.swift:373 play/pause 52; ReviewView.swift:57 brain 52; ReviewSessionView.swift:181 ear 44, :343 seal 56; ScanFlowView.swift:54 viewfinder 56; LibraryView.swift:233 kind badge 12). §1/§6 wants fixed symbol sizes to flow through `DesignSystem.IconSize` and be even.
**Reuse** — `IconSize.hero48` exists; add one `IconSize.xl` (56) rung rather than sprinkling literals.
**Effort** — S.
**Notes** — Pure token compliance, no behavior change; ReviewView is otherwise a good template screen.

### Fix the Reader inter-button spacing token misuse
**What & why** — `HStack(spacing: DesignSystem.minTapTarget)` (ReaderView.swift:365) uses the 44pt *tap-target* constant as *spacing* — semantically wrong and over-wide.
**Reuse** — `Spacing.xl32` or `Spacing.lg24`.
**Effort** — S.
**Notes** — Token hygiene.

### Tokenize the shelf ledge + cover depth
**What & why** — `shelfLedge` uses `cornerRadius: 2` and `shadow(radius: 2, y: 2)` (LibraryView.swift:112–116); `BookCover` uses `radius: 5, x: 3, y: 5` and a `.frame(width: 12)` binding (:182, :221) — all off the 8-pt grid and radius ladder (§2/§3).
**Reuse** — `CornerRadius.small8`, `Spacing.xs4`/`sm8`. Both the ledge and covers need a shadow, so extract a shared `Theme` shadow token (rule-of-two satisfied).
**Effort** — S.
**Notes** — Shadow-token extraction candidate.

### Replace off-grid literals in the Learn word canvas
**What & why** — `FlowLayout(spacing: 6)`, `cornerRadius: 4`, `.padding(.horizontal, 2)` (SentenceLearnView.swift:112/133/131) are off-grid.
**Reuse** — `Spacing.xs4`, `CornerRadius.small8` (or document a 4-pt half-step if intentional).
**Effort** — S.
**Notes** — Token compliance.

### Make the translation-issue + digest rows use the semantic palette
**What & why** — `translationIssueRow` hardcodes `.orange` / `Color.orange.opacity(0.12)` (ReaderView.swift:292/296) instead of the app's five-hue semantic palette. §5 wants functional colors semantic.
**Reuse** — `Theme.marigold` + `Palette.soft(Theme.marigold)` — the established "attention/confused" hue.
**Effort** — S.
**Notes** — Keeps the 5-hue system honest.

---

## 3. Reuse-first component consolidation (delete hand-rolled code, gain gating for free)

### Replace hand-rolled intent chips with ChipButtonStyle
**What & why** — `intentChip` hand-rolls a capsule with stroke/fill/foreground selection logic (SentenceLearnView.swift:424–441) that `ChipButtonStyle(isSelected:tint:)` already provides. Direct reuse-first violation.
**Reuse** — `ChipButtonStyle` (Interactive.swift:13) — it takes a tint, so intents can carry a semantic hue, and you inherit the press spring + Reduce-Motion gating for free. NotesView filter chips (:149) already use it this way.
**Effort** — S.
**Notes** — Reuse-first; removes code and closes a Reduce-Motion gap in one move.

### Extract a `.dictionaryLookup(term:)` view modifier
**What & why** — The `lookupTerm` + `DictionaryTerm` + `.sheet(item:)` trio is copy-pasted in SaveWordSheet (:83), SentenceLearnView (:69), and SavedItemDetailView (:106) — three copies, rule-of-two exceeded.
**Reuse** — Genuinely-new but tiny: a `.dictionaryLookup(term:)` View modifier in `Shared/` wrapping the existing `DictionaryView`/`DictionaryTerm`. Consolidates three call sites.
**Effort** — S.
**Notes** — Reuse/de-dup; belongs in `Shared/`.

### Unify the primary-button voice on SpringyProminentButtonStyle
**What & why** — Learn, Review-session, and Scan lean on system `.borderedProminent`/`.bordered` (SentenceLearnView.swift:157/167, ReviewSessionView.swift:138/168, ScanFlowView.swift:86/92), while Library and Review use the app's `SpringyProminentButtonStyle`. Two button identities dilute the energy-pass look.
**Reuse** — `SpringyProminentButtonStyle(tint:prominent:)` in Interactive.swift — already Reduce-Motion-gated.
**Effort** — M.
**Notes** — Keeps the energetic-not-gamified identity consistent across the loop.

### Move the legacy "Item notes" empty state onto AnimatedEmptyState
**What & why** — The "Item notes" empty state still uses `ContentUnavailableView` (NotesView.swift:287) — the exact component `AnimatedEmptyState` was built to replace. The Notebook segment right above it already uses the new one (:131), so the two halves of one screen speak in different visual voices.
**Reuse** — `AnimatedEmptyState(title:message:systemImage:tint:)`.
**Effort** — S.
**Notes** — Reuse/consistency; ties into the Phase-1 legacy port (see §7).

### Warm up the Scan capture prompt with the empty-state treatment
**What & why** — The empty capture screen is a grey `size: 56` viewfinder + system buttons (ScanFlowView.swift:53–92) — the coldest first-run surface in an otherwise warm app.
**Reuse** — It can't be a pure `AnimatedEmptyState` (it has live pickers/buttons), but it can borrow that component's tinted breathing-symbol treatment (`Palette.soft(tint)` disc + `symbolEffect(.breathe)`, both in AnimatedEmptyState.swift) and a `SpringyProminentButtonStyle` primary.
**Effort** — M.
**Notes** — Raises the emotional floor of onboarding without gamifying.

---

## 4. Product voice — a house style, then apply it

### Adopt a one-screen voice guide
**What & why** — Codify one warm, grown-up coaching voice so every string sounds like one person: (1) speak to a capable adult — no "Yay!", no diminutives; (2) name the payoff, not the mechanic ("hear it read aloud" > "unlock audio"); (3) second person, present tense, one idea per line; (4) bilingual-aware — say "the language you read fluently", never assume English is "normal"; (5) calm, earned encouragement ("Nicely done" > "Amazing!!!"); (6) errors are a next step, never a scold; (7) plain, literate, a little literary — the paper-and-ink identity in words.
**Reuse** — This is the written counterpart to DECISIONS #36 (paper & ink) and #39 (energetic-not-gamified) — no new system, it codifies tone. SentenceLearnView's copy is already the strongest in the app; treat it as the reference.
**Effort** — S (a docs page).
**Notes** — Enforces the anti-gamification rule at the copy layer; makes every rewrite below consistent.

### Standardize on sentence-case for body, one register for buttons
**What & why** — Buttons drift between title-case ("Look Up", "Try Again", "Save Word") and the sentence-case body copy. Pick one register app-wide.
**Reuse** — Label text only: SaveWordSheet.swift:52,70; SentenceLearnView.swift:208,406–408. Leave the already-warm instructional strings ("Tap the words you want to save", :37; "Tap any word to hear it", :144) untouched.
**Effort** — S.
**Notes** — Consistency polish; no flow change.

### Standardize on the four real action verbs
**What & why** — The loop is capture → listen → save → review, but buttons say "Scan", "Use", "Reveal answer", "Practice all", "Star". Lock a small verb set the learner re-sees everywhere: Scan (capture), Play/Slow (listen), Save (keep), Review/Practice (recall). Concretely, rename the OCR-confirm "Use" (OCRReviewView.swift:62) to "Save Page" — "Use" is vague at the moment of commitment.
**Reuse** — Existing buttons, label text only.
**Effort** — S.
**Notes** — Reduces vocabulary load for non-native readers; no flow change.

### Align the Notes tab label to "Notebook"
**What & why** — The tab reads "Notes" (RootView.swift:40) but the screen's own `navigationTitle` is already "Notebook" (NotesView.swift:100). Match the word a learner taps to the screen they land on.
**Reuse** — One-word change in the `RootView.swift:40` Label; screen title already correct.
**Effort** — S.
**Notes** — Consistency; leave Library/Saved/Review — they're clear and non-gamified.

---

## 5. Copy rewrites — empty states (all already use AnimatedEmptyState, so these are string-only)

### Library empty — teach the whole loop in one line
**What & why** — Current message says "book page", but the app explicitly handles signs/menus/screenshots (SourceKind). Rewrite: keep the title; message → "Photograph a page, sign, or menu — then hear it read aloud, word by word." "Word by word" previews the karaoke payoff.
**Reuse** — LibraryView.swift:135–140 (`AnimatedEmptyState`, Theme.coral); matches ScanFlow's own "page, sign, or menu" wording (:56).
**Effort** — S.
**Notes** — Fixes a factual narrowing in existing copy; offline.

### Review empty — say what a "card" is, calmly
**What & why** — Current: "No cards yet" / "…build your deck." "Build your deck" is faintly game-y. Rewrite: "Your review deck is empty" / "Save a word or bookmark a sentence while you read — it comes back here to review, spaced out over time." Explains spaced repetition as a benefit, no XP/streak language.
**Reuse** — ReviewView.swift:118–124 (Theme.violet).
**Effort** — S.
**Notes** — Anti-gamification fit; the reward is the schedule, not a score.

### Notebook empty — point to the real save spot
**What & why** — Current says "from the Learn screen", but users save from Reader and SaveWordSheet too. Rewrite: "Your notebook is empty" / "Words, phrases, and sentences you save while reading gather here — with your notes and examples." Previews the Notebook's unique value vs Saved.
**Reuse** — NotesView.swift:131–135.
**Effort** — S.
**Notes** — Removes a factual inaccuracy.

### Saved empty states — warm up the terse stubs
**What & why** — The two most instructional, least polished strings. Rewrite to sentence case + Apple's gesture wording: "No saved words yet" / "In the Reader, touch and hold a sentence, then choose the words worth keeping." and "No bookmarked sentences yet" / "Tap the star on any sentence in the Reader to keep it here." ("Touch and hold" matches Apple over "Long-press".)
**Reuse** — SavedItemsView.swift:55–56, 81–82.
**Effort** — S.
**Notes** — Apple-HIG gesture wording.

### Notebook "no matches" — softer dead-end
**What & why** — "No matches" reads like a search-engine error. Rewrite: "Nothing here yet" / "No saved items match this filter — try another, or clear your search."
**Reuse** — NotesView.swift:158–162 (Theme.slate).
**Effort** — S.
**Notes** — Stays encouraging; names the escape hatch.

---

## 6. Copy rewrites — feedback, errors & permissions

### Grade hints — coaching, not verdicts
**What & why** — Current label/hint pairs judge the learner: Again/"Forgot", Hard/"Tough", Good/"Knew it", Easy/"Too easy". Rewrite the hint to describe the card's fate, not the person: Again/"Show again", Hard/"Barely", Good/"Got it", Easy/"Easy". The SM-2 grade is unchanged.
**Reuse** — SRSEngine.swift:151–164 (label/hint text only; no algorithm change). The prompt above them — "How well did you know it?" (ReviewSessionView.swift:300) — is already warm; keep it.
**Effort** — S.
**Notes** — Preserves dignity; anti-gamification.

### Session summary — adult praise, reward is information
**What & why** — Fold the real next-due date into the summary so spacing *is* the reward: "Session complete" / "You reviewed N — {nextDueText}". Change Shadowing's "Nice practice!" → "Well practiced".
**Reuse** — ReviewSessionView.swift:348–353 + the existing `nextDueDate()`; ShadowingPracticeView.swift:130.
**Effort** — S.
**Notes** — Energetic but not gamified — the reward is a date, not points.

### Reader digest bar — name the payoff
**What & why** — Rewrite "Saved this session: {…}" + "Review now" → "Kept this session: {…}" + "Review these". "Kept" matches the save-verb; "Review these" scopes the action to the digest set, which is what the button already does.
**Reuse** — ReaderView.swift:329, 333 (text only). The dismiss a11y label "Dismiss — items stay saved and scheduled" (:344) is already excellent — leave it.
**Effort** — S.
**Notes** — Reinforces that saving ≠ losing work.

### OCR failure messages — end on the real next action
**What & why** — Keep the specific, helpful advice; standardize the retake verb so both end on the action that maps to the existing "Retake" button (OCRReviewView.swift:59): "No text found — flatten the page, add light, and retake." / "Couldn't read this page — retake it with more light."
**Reuse** — ScanFlowView.swift:147,160,166 strings; a11y "No text to save…" (OCRReviewView.swift:112).
**Effort** — S.
**Notes** — On-device OCR; advice is correctly about photo quality, not network.

### Translation-unavailable rows — reassure it's offline-normal
**What & why** — Rewrite "Translation isn't available for this language pair." → "Translation isn't offered for this language pair yet." and "Couldn't translate this page — tap to retry." → "…tap to try again." "Isn't offered… yet" reads as an Apple-capability limit, not a learner failure.
**Reuse** — Existing strings: ReaderView.swift:417–418; ReviewSessionView.swift:261.
**Effort** — S.
**Notes** — Honest about the iOS 18 Translation framework's offline pair coverage (TRANSLATION_DESIGN.md); never implies networking.

### Permission rows — adopt the mic-string pattern everywhere
**What & why** — The mic denial string (ShadowingPracticeView.swift:82 — "Microphone access is off — you can still listen and repeat aloud. Enable it in Settings to record and compare.") is the gold standard: states the limit → preserves the core value → gives the fix. Adopt that limit → still-works → how-to-fix shape as the house style for every permission row. The camera string (ScanFlowView.swift:126) is already close — keep it.
**Reuse** — Both existing strings.
**Effort** — S.
**Notes** — Apple-only permissions; degrade-don't-block is already coded — this just makes the copy consistent.

---

## 7. Genuinely new — first-run onboarding (grep confirmed zero onboarding code exists)

### First-run teaching card set (≤3 panels)
**What & why** — A one-time, skippable intro shown when the Library is empty on first launch, framing the four-verb loop in at most three panels: Photograph any text → Listen, word by word → Keep what's worth learning (fold "Review, right on time" into the third), ending on a single "Scan your first page" button. Strictly instructional — no rewards, streaks, or scores.
**Reuse** — Build it *from* `AnimatedEmptyState` (Shared/Components/AnimatedEmptyState.swift): it already has the breathing SF Symbol + mesh disc + `actions` slot, so a `TabView(.page)` of three AnimatedEmptyState-styled panels reuses the whole visual language. Gate on a new `@AppStorage("hasSeenIntro")` (same pattern as `@AppStorage("nativeLanguage")` in SettingsView.swift:29). Fire the existing `isScanPresented` (LibraryView.swift:18,48) from the final button.
**Effort** — M.
**Notes** — Genuinely new (grep for onboard/firstRun/welcome/hasSeen returned nothing), but built entirely from existing components. Fully offline; anti-gamification safe; keep to ≤3 panels to honor "concise, no bloat".

### Native-language nudge on the intro's last panel (reuse, don't build a second flow)
**What & why** — Instead of a separate setup screen, if `nativeLanguage` is still device-default, show a one-line row on the intro's final panel: "Reading into English? You can change your language any time in Settings."
**Reuse** — Reads the existing `@AppStorage("nativeLanguage")` and the copy already in SettingsView.swift:35.
**Effort** — S; depends on the intro card set above.
**Notes** — Bilingual-aware — doesn't assume English; avoids a whole setup screen.

---

## 8. Information architecture — flag alongside the Phase-1 port (not standalone UI work)

### Collapse the "Item notes" segment into Notebook
**What & why** — The legacy "Item notes" segment (NotesView.swift:104–110) exists only for the un-ported `SavedWord`/`Sentence.userNote` path. To a learner it looks like two note systems. Nothing new to build — this disappears when the SavedWord→Annotation port lands.
**Reuse** — Nothing new; flag for the Phase-1 port.
**Effort** — L (data migration, already tracked in TASKS Phase 1).
**Notes** — Clarity; ties to existing backlog, not a copy fix.

### Reconcile "Saved" vs "Notebook" tabs
**What & why** — Saved lists words + bookmarked sentences (SavedItemsView.swift:14–18) while Notebook lists annotations; post-port these become the same mental model in two tabs. Flag the tab consolidation alongside the Phase-1 port.
**Reuse** — Nothing new; tracked.
**Effort** — L (tracked).
**Notes** — IA clarity, anti-bloat; decide during the port, not now.

---

## Triage table

| Suggestion | Impact | Effort | Reuses |
|---|---|---|---|
| Reader transport 44pt target | High | S | `minTapTarget` frame (ReaderView:456) |
| Review-session Play/Slow + grade 44pt | High | S | `minTapTarget` frame |
| Settings voice-preview 44pt | Med | S | `minTapTarget` frame |
| VoiceOver labels on Reader transport | High | S | `.accessibilityLabel` (ReaderView:459) |
| Reduce-Motion gate active card | Med | S | `accessibilityReduceMotion` (NotesView:201) |
| Reduce-Motion Saved ReplayButton | Low | S | `accessibilityReduceMotion` |
| Grade contrast + Dynamic Type | High | M | Palette dark variants; 2×2 grid |
| Cover title reflow at AX sizes | Med | S | existing tile a11y label |
| Hero icon sizes → IconSize | Low | S | `IconSize` (+ new `.xl` rung) |
| Reader spacing token fix | Low | S | `Spacing.xl32` |
| Shelf ledge + cover depth tokens | Low | S | `CornerRadius`, `Spacing`, new shadow token |
| Learn word-canvas literals | Low | S | `Spacing.xs4`, `CornerRadius.small8` |
| Translation-issue row → semantic hue | Low | S | `Theme.marigold`, `Palette.soft` |
| Intent chips → ChipButtonStyle | Med | S | `ChipButtonStyle` (Interactive:13) |
| `.dictionaryLookup(term:)` modifier | Med | S | `DictionaryView`/`DictionaryTerm` |
| Unify primary button style | Med | M | `SpringyProminentButtonStyle` |
| Item-notes empty → AnimatedEmptyState | Med | S | `AnimatedEmptyState` |
| Warm the Scan capture prompt | Med | M | `AnimatedEmptyState` treatment, Springy button |
| Voice guide doc | High | S | DECISIONS #36/#39 |
| Sentence-case / button register | Med | S | label text only |
| Four action verbs ("Use" → "Save Page") | Med | S | label text only |
| Notes tab → "Notebook" | Med | S | RootView:40 label |
| Library empty rewrite | High | S | LibraryView:135 AnimatedEmptyState |
| Review empty rewrite | High | S | ReviewView:118 |
| Notebook empty rewrite | Med | S | NotesView:131 |
| Saved empty rewrites | Med | S | SavedItemsView:55,81 |
| Notebook "no matches" rewrite | Low | S | NotesView:158 |
| Grade hints → coaching | High | S | SRSEngine:151 text only |
| Session summary + next-due | Med | S | ReviewSessionView:348, `nextDueDate()` |
| Reader digest bar copy | Med | S | ReaderView:329,333 |
| OCR failure copy | Med | S | ScanFlowView:147,160,166 |
| Translation-unavailable copy | Med | S | ReaderView:417; ReviewSessionView:261 |
| Permission-row house style | Med | S | ShadowingPractice:82 pattern |
| First-run onboarding (≤3 panels) | High | M | `AnimatedEmptyState`, `@AppStorage`, `isScanPresented` |
| Native-language nudge on last panel | Med | S | `@AppStorage("nativeLanguage")` |
| Collapse Item-notes segment | Med | L | Phase-1 SavedWord→Annotation port |
| Reconcile Saved vs Notebook tabs | Med | L | Phase-1 port |
